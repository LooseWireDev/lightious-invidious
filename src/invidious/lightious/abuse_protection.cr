require "openssl/hmac"

module Invidious::Lightious::AbuseProtection
  extend self

  TURNSTILE_ACTION = "lightious_login"

  private RATE_LIMIT_DOMAIN = "lightious:rate-limit:v1"
  private GLOBAL_SOURCE     = "all"

  @@initialization_mutex = Mutex.new
  @@login_attempt_mutex = Mutex.new
  @@pairing_attempt_mutex = Mutex.new
  @@login_account_limiter : Invidious::Lightious::SlidingWindowRateLimiter? = nil
  @@login_ip_limiter : Invidious::Lightious::SlidingWindowRateLimiter? = nil
  @@login_global_limiter : Invidious::Lightious::SlidingWindowRateLimiter? = nil
  @@pairing_ip_limiter : Invidious::Lightious::SlidingWindowRateLimiter? = nil
  @@pairing_global_limiter : Invidious::Lightious::SlidingWindowRateLimiter? = nil
  @@turnstile_verifier : Invidious::Lightious::TurnstileVerifier? = nil

  # Atomically checks all login buckets and reserves the IP and global attempt
  # before the caller performs human verification or password hashing. Every
  # protected POST therefore counts, including successful registrations.
  def begin_login_attempt(env : HTTP::Server::Context, account : String?) : Int32?
    credential_key = account_key(account)
    client_key = ip_key(env)
    shared_key = global_key("login")

    @@login_attempt_mutex.synchronize do
      retry_values = [] of Int32
      credential_key.try do |key|
        login_account_limiter.retry_after([key]).try { |seconds| retry_values << seconds }
      end
      login_ip_limiter.retry_after([client_key]).try { |seconds| retry_values << seconds }
      login_global_limiter.retry_after([shared_key]).try { |seconds| retry_values << seconds }

      if retry_after = retry_values.max?
        retry_after
      else
        login_ip_limiter.record([client_key])
        login_global_limiter.record([shared_key])
        nil
      end
    end
  end

  # Only a human-verified request that reached credential validation may affect
  # the account bucket. Early validation/challenge failures have already been
  # reserved against the IP and global buckets by begin_login_attempt.
  def record_login_credential_failure(account : String?) : Nil
    account_key(account).try { |key| login_account_limiter.record_failure([key]) }
  end

  # A successful login proves control of one account. It must not erase IP or
  # global failures that may have targeted other accounts.
  def clear_login_account(account : String?) : Nil
    account_key(account).try { |key| login_account_limiter.clear(key) }
  end

  # Pairing creation is an anonymous bootstrap operation, so every accepted
  # request consumes both IP and global capacity. The check and reservation are
  # serialized to prevent a concurrent burst from slipping past the limit.
  def begin_pairing_attempt(env : HTTP::Server::Context) : Int32?
    client_key = ip_key(env)
    shared_key = global_key("pairing")

    @@pairing_attempt_mutex.synchronize do
      retry_values = [] of Int32
      pairing_ip_limiter.retry_after([client_key]).try { |seconds| retry_values << seconds }
      pairing_global_limiter.retry_after([shared_key]).try { |seconds| retry_values << seconds }

      if retry_after = retry_values.max?
        retry_after
      else
        pairing_ip_limiter.record([client_key])
        pairing_global_limiter.record([shared_key])
        nil
      end
    end
  end

  def turnstile_enabled? : Bool
    CONFIG.lightious.security.turnstile_enabled?
  end

  def verify_turnstile(env : HTTP::Server::Context) : Bool
    verifier = turnstile_verifier
    return true unless verifier

    verifier.verify(
      env.params.body["cf-turnstile-response"]?,
      client_ip(env),
    )
  end

  def protected_login? : Bool
    CONFIG.lightious.enabled
  end

  def lightious_login_page?(referer : String) : Bool
    CONFIG.lightious.enabled && (CONFIG.lightious.lockdown || referer.starts_with?("/lightious"))
  end

  def valid_login_origin?(env : HTTP::Server::Context) : Bool
    Invidious::Lightious::SecurityInputs.login_origin_allowed?(
      env.request.headers["Origin"]?,
      CONFIG.lightious.public_url,
      env.request.headers["Host"]?,
      (Kemal.config.ssl || CONFIG.https_only) == true,
    )
  end

  def client_ip(env : HTTP::Server::Context) : String?
    if header = CONFIG.lightious.security.trusted_client_ip_header
      if forwarded = env.request.headers[header]?
        if candidate = Invidious::Lightious::SecurityInputs.canonical_ip(forwarded)
          return candidate
        end
      end
    end

    case address = env.request.remote_address
    when Socket::IPAddress
      address.address
    when Nil
      nil
    else
      nil
    end
  end

  private def login_account_limiter : Invidious::Lightious::SlidingWindowRateLimiter
    existing = @@login_account_limiter
    return existing if existing

    @@initialization_mutex.synchronize do
      @@login_account_limiter ||= new_limiter(
        CONFIG.lightious.security.login_account_limit,
        CONFIG.lightious.security.login_window_minutes,
      )
    end
  end

  private def login_ip_limiter : Invidious::Lightious::SlidingWindowRateLimiter
    existing = @@login_ip_limiter
    return existing if existing

    @@initialization_mutex.synchronize do
      @@login_ip_limiter ||= new_limiter(
        CONFIG.lightious.security.login_ip_limit,
        CONFIG.lightious.security.login_window_minutes,
      )
    end
  end

  private def login_global_limiter : Invidious::Lightious::SlidingWindowRateLimiter
    existing = @@login_global_limiter
    return existing if existing

    @@initialization_mutex.synchronize do
      @@login_global_limiter ||= new_limiter(
        CONFIG.lightious.security.login_global_limit,
        CONFIG.lightious.security.login_window_minutes,
      )
    end
  end

  private def pairing_ip_limiter : Invidious::Lightious::SlidingWindowRateLimiter
    existing = @@pairing_ip_limiter
    return existing if existing

    @@initialization_mutex.synchronize do
      @@pairing_ip_limiter ||= new_limiter(
        CONFIG.lightious.security.pairing_ip_limit,
        CONFIG.lightious.security.pairing_window_minutes,
      )
    end
  end

  private def pairing_global_limiter : Invidious::Lightious::SlidingWindowRateLimiter
    existing = @@pairing_global_limiter
    return existing if existing

    @@initialization_mutex.synchronize do
      @@pairing_global_limiter ||= new_limiter(
        CONFIG.lightious.security.pairing_global_limit,
        CONFIG.lightious.security.pairing_window_minutes,
      )
    end
  end

  private def turnstile_verifier : Invidious::Lightious::TurnstileVerifier?
    return nil unless turnstile_enabled?

    existing = @@turnstile_verifier
    return existing if existing

    @@initialization_mutex.synchronize do
      @@turnstile_verifier ||= Invidious::Lightious::TurnstileVerifier.new(
        CONFIG.lightious.security.turnstile_secret_key,
        TURNSTILE_ACTION,
        CONFIG.lightious.security.turnstile_hostname || CONFIG.lightious.public_url.host.to_s,
      )
    end
  end

  private def new_limiter(limit : Int32, window_minutes : Int32) : Invidious::Lightious::SlidingWindowRateLimiter
    Invidious::Lightious::SlidingWindowRateLimiter.new(
      limit,
      window_minutes.minutes,
      CONFIG.lightious.security.max_tracked_keys,
    )
  end

  private def account_key(account : String?) : String?
    normalized = account.try(&.strip.downcase)
    return nil unless normalized && !normalized.empty?

    opaque_key("account", normalized)
  end

  private def ip_key(env : HTTP::Server::Context) : String
    opaque_key("ip", client_ip(env) || "unknown")
  end

  private def global_key(kind : String) : String
    opaque_key("global:#{kind}", GLOBAL_SOURCE)
  end

  private def opaque_key(kind : String, value : String) : String
    OpenSSL::HMAC.hexdigest(:sha256, HMAC_KEY, "#{RATE_LIMIT_DOMAIN}\0#{kind}\0#{value}")
  end
end
