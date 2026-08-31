{% skip_file if flag?(:api_only) %}

module Invidious::Routes::LightiousControl
  extend self

  CSRF_SCOPE = {"POST:lightious/*"}
  MODES      = {"explore", "focused"}
  POLICIES   = {"listen_only", "watch_and_listen"}

  def dashboard(env)
    locale = env.get("preferences").as(Preferences).locale
    user = env.get?("user")
    sid = env.get?("sid")
    return redirect_to_login(env, "/lightious") unless user && sid

    user = user.as(User)
    sid = sid.as(String)
    profile = Invidious::Database::Lightious.ensure_profile(
      user.email,
      Random::Secure.hex(16),
      Time.utc,
    )
    items = Invidious::Database::Lightious.items_for_profile(profile.id)
    devices = Invidious::Database::Lightious.devices_for_account(user.email)
    csrf_token = generate_response(sid, CSRF_SCOPE, HMAC_KEY)
    notice = notice_text(env.params.query["notice"]?)

    templated "lightious/dashboard", navbar_search: false
  end

  def pair_page(env)
    locale = env.get("preferences").as(Preferences).locale
    user = env.get?("user")
    sid = env.get?("sid")
    return redirect_to_login(env, "/lightious/pair") unless user && sid

    sid = sid.as(String)
    csrf_token = generate_response(sid, CSRF_SCOPE, HMAC_KEY)
    user_code = ""
    pending_pairing = nil
    error_message = nil

    templated "lightious/pair", navbar_search: false
  end

  def preview_pairing(env)
    locale = env.get("preferences").as(Preferences).locale
    user = env.get?("user")
    sid = env.get?("sid")
    return redirect_to_login(env, "/lightious/pair") unless user && sid

    sid = sid.as(String)
    if error_message = csrf_error(env, sid)
      return error_template(400, error_message)
    end

    user_code = env.params.body["user_code"]?.to_s
    digest = Invidious::Lightious::Pairing.user_code_digest(HMAC_KEY, user_code)
    pending_pairing = digest.try do |value|
      Invidious::Database::Lightious.pairing_for_user_code(value, Time.utc)
    end
    error_message = pending_pairing ? nil : "That pairing code is invalid or expired."
    csrf_token = generate_response(sid, CSRF_SCOPE, HMAC_KEY)

    templated "lightious/pair", navbar_search: false
  end

  def claim_pairing(env)
    locale = env.get("preferences").as(Preferences).locale
    user = env.get?("user")
    sid = env.get?("sid")
    return redirect_to_login(env, "/lightious/pair") unless user && sid

    user = user.as(User)
    sid = sid.as(String)
    if error_message = csrf_error(env, sid)
      return error_template(400, error_message)
    end

    user_code = env.params.body["user_code"]?.to_s
    digest = Invidious::Lightious::Pairing.user_code_digest(HMAC_KEY, user_code)
    return error_template(400, "That pairing code is invalid or expired.") unless digest

    pairing = Invidious::Database::Lightious.claim_pairing(
      digest,
      user.email,
      Random::Secure.hex(16),
      Time.utc,
    )
    return error_template(409, "That pairing code is invalid, expired, or already used.") unless pairing

    env.redirect "/lightious?notice=paired"
  end

  def update_mode(env)
    user = authenticated_user(env, "/lightious")
    return unless user
    sid = env.get("sid").as(String)
    if error_message = csrf_error(env, sid)
      return error_template(400, error_message)
    end

    mode = env.params.body["mode"]?.to_s
    return error_template(400, "Choose Explore or Focused mode.") unless MODES.includes?(mode)

    profile = Invidious::Database::Lightious.update_mode(user.email, mode, Time.utc)
    return error_template(404, "Lightious profile not found.") unless profile

    env.redirect "/lightious?notice=mode"
  end

  def add_video(env)
    user = authenticated_user(env, "/lightious")
    return unless user
    sid = env.get("sid").as(String)
    if error_message = csrf_error(env, sid)
      return error_template(400, error_message)
    end

    input = env.params.body["video"]?.to_s
    video_id = Invidious::Lightious::VideoInput.extract_video_id(input)
    return error_template(400, "Enter a valid YouTube video ID or URL.") unless video_id

    policy = env.params.body["playback_policy"]?.to_s
    return error_template(400, "Choose a valid playback policy.") unless POLICIES.includes?(policy)

    begin
      video = get_video(video_id)
    rescue ex : NotFoundException
      return error_template(404, ex)
    rescue ex
      return error_template(502, ex)
    end

    Invidious::Database::Lightious.ensure_profile(user.email, Random::Secure.hex(16), Time.utc)
    saved = Invidious::Database::Lightious.upsert_item(
      account: user.email,
      item_id: Random::Secure.hex(16),
      video_id: video.id,
      title: video.title,
      author: video.author,
      length_seconds: video.length_seconds.to_i64,
      thumbnail_url: "/vi/#{video.id}/mqdefault.jpg",
      playback_policy: policy,
      now: Time.utc,
    )
    return error_template(500, "Could not save this video.") unless saved

    env.redirect "/lightious?notice=video"
  end

  def update_video_policy(env)
    user = authenticated_user(env, "/lightious")
    return unless user
    sid = env.get("sid").as(String)
    if error_message = csrf_error(env, sid)
      return error_template(400, error_message)
    end

    policy = env.params.body["playback_policy"]?.to_s
    return error_template(400, "Choose a valid playback policy.") unless POLICIES.includes?(policy)

    Invidious::Database::Lightious.update_item_policy(
      user.email,
      env.params.url["id"],
      policy,
      Time.utc,
    )
    env.redirect "/lightious?notice=policy"
  end

  def delete_video(env)
    user = authenticated_user(env, "/lightious")
    return unless user
    sid = env.get("sid").as(String)
    if error_message = csrf_error(env, sid)
      return error_template(400, error_message)
    end

    Invidious::Database::Lightious.delete_item(user.email, env.params.url["id"], Time.utc)
    env.redirect "/lightious?notice=removed"
  end

  def revoke_device(env)
    user = authenticated_user(env, "/lightious")
    return unless user
    sid = env.get("sid").as(String)
    if error_message = csrf_error(env, sid)
      return error_template(400, error_message)
    end

    Invidious::Database::Lightious.revoke_device(
      env.params.url["id"],
      user.email,
      Time.utc,
    )
    env.redirect "/lightious?notice=revoked"
  end

  private def authenticated_user(env, referer : String) : User?
    user = env.get?("user").try &.as(User)
    unless user && env.get?("sid")
      redirect_to_login(env, referer)
      return nil
    end
    user
  end

  private def csrf_error(env, sid : String) : String?
    validate_request(env.params.body["csrf_token"]?, sid, env.request, HMAC_KEY, nil)
    nil
  rescue ex
    ex.message || "Invalid request."
  end

  private def redirect_to_login(env, referer : String)
    env.redirect "/login?referer=#{URI.encode_www_form(referer)}"
  end

  private def notice_text(value : String?) : String?
    case value
    when "paired"  then "Phone approved. Confirm pairing on the phone."
    when "mode"    then "Experience mode updated."
    when "video"   then "Video sent to the focused library."
    when "policy"  then "Playback permission updated."
    when "removed" then "Video removed from the focused library."
    when "revoked" then "Phone access revoked."
    end
  end
end
