module Invidious::Routes::API::Lightious::V1
  extend self

  MAX_JSON_BODY_BYTES = 4096

  def create_pairing(env)
    prepare_json(env)
    body = parse_json_body(env).try &.as_h?
    return error_json(400, "Invalid JSON body.") unless body

    device_label = body["deviceLabel"]?.try(&.as_s?).to_s.gsub(/\s+/, " ").strip
    if device_label.empty? || device_label.bytesize > 64
      return error_json(400, "Device label must be between 1 and 64 bytes.")
    end

    bearer_digest = body["deviceBearerDigest"]?.try(&.as_s?).to_s
    unless Invidious::Lightious::Pairing.valid_device_bearer_digest?(bearer_digest)
      return error_json(400, "Invalid device credential digest.")
    end

    now = Time.utc
    Invidious::Database::Lightious.delete_expired_pairings(now)
    user_code = Invidious::Lightious::Pairing.generate_user_code
    poll_secret = Invidious::Lightious::Pairing.generate_poll_secret
    user_code_digest = Invidious::Lightious::Pairing.user_code_digest(HMAC_KEY, user_code).not_nil!
    poll_secret_digest = Invidious::Lightious::Pairing.poll_secret_digest(HMAC_KEY, poll_secret).not_nil!
    pairing_id = Random::Secure.hex(16)
    expires_at = now + CONFIG.lightious.pairing_ttl_minutes.minutes

    begin
      Invidious::Database::Lightious.insert_pairing(
        pairing_id,
        user_code_digest,
        poll_secret_digest,
        bearer_digest,
        device_label,
        now,
        expires_at,
      )
    rescue ex : DB::Error
      LOGGER.warn("Lightious pairing creation failed: #{ex.message}")
      return error_json(409, "Could not create a unique pairing. Try again.")
    end

    env.response.status_code = 201
    JSON.build do |json|
      json.object do
        json.field "pairingId", pairing_id
        json.field "userCode", user_code
        json.field "pollSecret", poll_secret
        json.field "verificationUrl", verification_url
        json.field "expiresAt", expires_at.to_rfc3339
      end
    end
  end

  def pairing_status(env)
    prepare_json(env)
    poll_secret = bearer_token(env)
    digest = poll_secret.try do |secret|
      Invidious::Lightious::Pairing.poll_secret_digest(HMAC_KEY, secret)
    end
    return error_json(401, "Invalid pairing credential.") unless digest

    pairing = Invidious::Database::Lightious.pairing_status(env.params.url["id"], digest)
    return error_json(404, "Pairing not found.") unless pairing

    state = if pairing.expires_at <= Time.utc && pairing.state != "consumed"
              "expired"
            elsif pairing.state == "created"
              "pending"
            else
              pairing.state
            end

    JSON.build do |json|
      json.object do
        json.field "state", state
        json.field "deviceLabel", pairing.device_label
        json.field "expiresAt", pairing.expires_at.to_rfc3339
        if account = pairing.claimed_account
          json.field "account", Invidious::Lightious::Pairing.account_display(account)
        end
      end
    end
  end

  def activate_pairing(env)
    prepare_json(env)
    poll_secret = bearer_token(env)
    digest = poll_secret.try do |secret|
      Invidious::Lightious::Pairing.poll_secret_digest(HMAC_KEY, secret)
    end
    return error_json(401, "Invalid pairing credential.") unless digest

    device = Invidious::Database::Lightious.activate_pairing(
      env.params.url["id"],
      digest,
      Random::Secure.hex(16),
      Time.utc,
    )
    return error_json(409, "Pairing is not approved or has expired.") unless device

    JSON.build do |json|
      json.object do
        json.field "deviceId", device.id
        json.field "account", Invidious::Lightious::Pairing.account_display(device.account)
      end
    end
  end

  def sync(env)
    prepare_json(env)
    device_bearer = bearer_token(env)
    unless device_bearer && Invidious::Lightious::Pairing.valid_device_bearer?(device_bearer)
      return error_json(401, "Invalid device credential.")
    end

    bearer_digest = Invidious::Lightious::Pairing.device_bearer_digest(device_bearer)
    device = Invidious::Database::Lightious.active_device(bearer_digest)
    return error_json(401, "Invalid device credential.") unless device

    profile = Invidious::Database::Lightious.profile_for_id(device.profile_id)
    return error_json(404, "Lightious profile not found.") unless profile
    items = Invidious::Database::Lightious.items_for_profile(profile.id)
    Invidious::Database::Lightious.touch_device(device.id, Time.utc)

    JSON.build do |json|
      json.object do
        json.field "deviceId", device.id
        json.field "account", Invidious::Lightious::Pairing.account_display(profile.account)
        json.field "revision", profile.revision
        json.field "mode", profile.mode
        json.field "items" do
          json.array do
            items.each do |item|
              json.object do
                json.field "id", item.id
                json.field "videoId", item.video_id
                json.field "title", item.title
                json.field "author", item.author
                json.field "lengthSeconds", item.length_seconds
                json.field "thumbnailUrl" do
                  if thumbnail_url = item.thumbnail_url
                    json.string thumbnail_url
                  else
                    json.null
                  end
                end
                json.field "playbackPolicy", item.playback_policy
              end
            end
          end
        end
      end
    end
  end

  private def prepare_json(env)
    env.response.content_type = "application/json"
    env.response.headers["Cache-Control"] = "no-store"
  end

  private def parse_json_body(env) : JSON::Any?
    body = env.request.body.try &.gets_to_end
    return nil unless body && body.bytesize <= MAX_JSON_BODY_BYTES
    JSON.parse(body)
  rescue JSON::ParseException
    nil
  end

  private def bearer_token(env) : String?
    authorization = env.request.headers["Authorization"]?
    return nil unless authorization && authorization.starts_with?("Bearer ")
    authorization.lchop("Bearer ").strip
  end

  private def verification_url : String
    base = CONFIG.lightious.public_url.to_s.rstrip("/")
    base.empty? ? "/lightious/pair" : "#{base}/lightious/pair"
  end
end
