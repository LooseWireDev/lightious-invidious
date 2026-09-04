{% skip_file if flag?(:api_only) %}

module Invidious::Routes::Login
  def self.login_page(env)
    locale = env.get("preferences").as(Preferences).locale

    user = env.get? "user"

    referer = get_referer(env, "/feed/subscriptions")
    referer = "/lightious" if CONFIG.lightious.enabled && CONFIG.lightious.lockdown

    return env.redirect referer if user

    if !CONFIG.login_enabled
      return error_template(400, "Login has been disabled by administrator.")
    end

    email = nil
    password = nil
    login_error = nil
    protected_login = Invidious::Lightious::AbuseProtection.protected_login?
    lightious_login_page = Invidious::Lightious::AbuseProtection.lightious_login_page?(referer)
    env.response.headers["Cache-Control"] = "no-store" if protected_login
    captcha = if protected_login && CONFIG.captcha_enabled && !Invidious::Lightious::AbuseProtection.turnstile_enabled?
                Invidious::User::Captcha.generate_image(HMAC_KEY)
              end

    account_type = env.params.query["type"]?
    account_type ||= "invidious"

    if lightious_login_page
      templated "user/login", "lightious/template", navbar_search: false
    else
      templated "user/login"
    end
  end

  def self.login(env)
    locale = env.get("preferences").as(Preferences).locale
    host = env.get("header_x-forwarded-host")

    referer = get_referer(env, "/feed/subscriptions")
    referer = "/lightious" if CONFIG.lightious.enabled && CONFIG.lightious.lockdown

    if !CONFIG.login_enabled
      return error_template(403, "Login has been disabled by administrator.")
    end

    # https://stackoverflow.com/a/574698
    email = env.params.body["email"]?.try &.downcase.byte_slice(0, 254)
    password = env.params.body["password"]?
    login_error = nil
    captcha = nil

    account_type = env.params.query["type"]?
    account_type ||= "invidious"
    protected_login = Invidious::Lightious::AbuseProtection.protected_login?
    env.response.headers["Cache-Control"] = "no-store" if protected_login

    if protected_login
      unless Invidious::Lightious::AbuseProtection.valid_login_origin?(env)
        return render_protected_login(
          env,
          locale,
          referer,
          account_type,
          "This sign-in request did not come from the configured Lightious site. Reload the page and try again.",
          403,
        )
      end

      if retry_after = Invidious::Lightious::AbuseProtection.begin_login_attempt(env, email)
        env.response.headers["Retry-After"] = retry_after.to_s
        return render_protected_login(
          env,
          locale,
          referer,
          account_type,
          "Too many failed sign-in attempts. Wait a little before trying again.",
          429,
        )
      end
    end

    case account_type
    when "invidious"
      if email.nil? || email.empty?
        if protected_login
          return render_protected_login(env, locale, referer, account_type, "Enter your user ID.", 401)
        end
        return error_template(401, "User ID is a required field")
      end

      if password.nil? || password.empty?
        if protected_login
          return render_protected_login(env, locale, referer, account_type, "Enter your password.", 401)
        end
        return error_template(401, "Password is a required field")
      end

      # Bcrypt only considers the first 55 bytes. Enforce the same bound before
      # looking up the account so this validation cannot disclose whether a
      # submitted user ID exists.
      if password.bytesize > 55
        if protected_login
          return render_protected_login(
            env,
            locale,
            referer,
            account_type,
            "Password cannot be longer than 55 characters.",
            400,
          )
        end
        return error_template(400, "Password cannot be longer than 55 characters")
      end

      if protected_login
        challenge_valid = if Invidious::Lightious::AbuseProtection.turnstile_enabled?
                            Invidious::Lightious::AbuseProtection.verify_turnstile(env)
                          elsif CONFIG.captcha_enabled
                            valid_lightious_captcha?(env, locale)
                          else
                            true
                          end

        unless challenge_valid
          return render_protected_login(
            env,
            locale,
            referer,
            account_type,
            "Human verification failed. Reload the challenge and try again.",
            403,
          )
        end
      end

      user = Invidious::Database::Users.select(email: email)

      if user
        if Crypto::Bcrypt::Password.new(user.password.not_nil!).verify(password.byte_slice(0, 55))
          sid = Base64.urlsafe_encode(Random::Secure.random_bytes(32))
          Invidious::Database::SessionIDs.insert(sid, email)

          if alt = CONFIG.alternative_domains.index(host)
            env.response.cookies["SID"] = Invidious::User::Cookies.sid(CONFIG.alternative_domains[alt], sid)
          else
            env.response.cookies["SID"] = Invidious::User::Cookies.sid(CONFIG.domain, sid)
          end
          Invidious::Lightious::AbuseProtection.clear_login_account(email) if protected_login
        else
          if protected_login
            Invidious::Lightious::AbuseProtection.record_login_credential_failure(email)
            return render_protected_login(
              env,
              locale,
              referer,
              account_type,
              "Wrong user ID or password.",
              401,
            )
          end
          return error_template(401, "Wrong username or password")
        end

        # Since this user has already registered, we don't want to overwrite their preferences
        if env.request.cookies["PREFS"]?
          cookie = env.request.cookies["PREFS"]
          cookie.expires = Time.utc(1990, 1, 1)
          env.response.cookies << cookie
        end
      else
        if !CONFIG.registration_enabled
          if protected_login
            Invidious::Lightious::AbuseProtection.record_login_credential_failure(email)
            return render_protected_login(
              env,
              locale,
              referer,
              account_type,
              "Wrong user ID or password.",
              401,
            )
          end
          return error_template(400, "Registration has been disabled by administrator.")
        end

        if password.empty?
          return error_template(401, "Password cannot be empty")
        end

        password = password.byte_slice(0, 55)

        if CONFIG.captcha_enabled && !protected_login
          answer = env.params.body["answer"]?

          account_type = "invidious"
          captcha = Invidious::User::Captcha.generate_image(HMAC_KEY)

          tokens = env.params.body.select { |k, _| k.match(/^token\[\d+\]$/) }.map { |_, v| v }

          if answer
            answer = answer.lstrip('0')
            answer = OpenSSL::HMAC.hexdigest(:sha256, HMAC_KEY, answer)

            begin
              validate_request(tokens[0], answer, env.request, HMAC_KEY, locale)
            rescue ex : InfoException
              return error_template(400, InfoException.new("Erroneous CAPTCHA"))
            rescue ex
              return error_template(400, ex)
            end
          else
            if referer.starts_with?("/lightious")
              return templated "user/login", "lightious/template", navbar_search: false
            else
              return templated "user/login"
            end
          end
        end

        sid = Base64.urlsafe_encode(Random::Secure.random_bytes(32))
        user, sid = create_user(sid, email, password)

        if language_header = env.request.headers["Accept-Language"]?
          if language = ANG.language_negotiator.best(language_header, I18n::LOCALES.keys)
            user.preferences.locale = language.header
          end
        end

        view_name = "subscriptions_#{sha256(user.email)}"
        PG_DB.transaction do |transaction|
          connection = transaction.connection
          Invidious::Database::Users.insert(connection, user)
          Invidious::Database::SessionIDs.insert(connection, sid, email)
          connection.exec("CREATE MATERIALIZED VIEW #{view_name} AS #{MATERIALIZED_VIEW_SQL.call(user.email)}")
        end

        if alt = CONFIG.alternative_domains.index(host)
          env.response.cookies["SID"] = Invidious::User::Cookies.sid(CONFIG.alternative_domains[alt], sid)
        else
          env.response.cookies["SID"] = Invidious::User::Cookies.sid(CONFIG.domain, sid)
        end

        if env.request.cookies["PREFS"]?
          user.preferences = env.get("preferences").as(Preferences)
          Invidious::Database::Users.update_preferences(user)

          cookie = env.request.cookies["PREFS"]
          cookie.expires = Time.utc(1990, 1, 1)
          env.response.cookies << cookie
        end
        Invidious::Lightious::AbuseProtection.clear_login_account(email) if protected_login
      end

      env.redirect referer
    else
      env.redirect referer
    end
  end

  def self.signout(env)
    locale = env.get("preferences").as(Preferences).locale

    user = env.get? "user"
    sid = env.get? "sid"
    referer = get_referer(env)

    if !user
      return env.redirect referer
    end

    user = user.as(User)
    sid = sid.as(String)
    token = env.params.body["csrf_token"]?

    begin
      validate_request(token, sid, env.request, HMAC_KEY, locale)
    rescue ex
      return error_template(400, ex)
    end

    Invidious::Database::SessionIDs.delete(sid: sid)

    env.request.cookies.each do |cookie|
      cookie.expires = Time.utc(1990, 1, 1)
      env.response.cookies << cookie
    end

    env.redirect referer
  end

  private def self.render_protected_login(env, locale, referer, account_type, login_error, status_code)
    email = nil
    password = nil
    captcha = if CONFIG.captcha_enabled && !Invidious::Lightious::AbuseProtection.turnstile_enabled?
                Invidious::User::Captcha.generate_image(HMAC_KEY)
              end
    env.response.status_code = status_code
    env.response.headers["Cache-Control"] = "no-store"
    if Invidious::Lightious::AbuseProtection.lightious_login_page?(referer)
      templated "user/login", "lightious/template", navbar_search: false
    else
      templated "user/login"
    end
  end

  private def self.valid_lightious_captcha?(env, locale) : Bool
    answer = env.params.body["answer"]?
    return false unless answer

    tokens = env.params.body
      .select { |key, _| key.match(/^token\[\d+\]$/) }
      .sort_by { |key, _| key }
      .map { |_, value| value }
    return false if tokens.empty?

    answer_digest = OpenSSL::HMAC.hexdigest(:sha256, HMAC_KEY, answer.lstrip('0'))
    validate_request(tokens[0], answer_digest, env.request, HMAC_KEY, locale)
    true
  rescue
    false
  end
end
