class LightiousLockdownHandler < Kemal::Handler
  def call(env)
    unless CONFIG.lightious.enabled && CONFIG.lightious.lockdown
      return call_next env
    end

    access = Invidious::Lightious::DeviceAuthorization.request_access(
      env.request.method,
      env.request.path,
    )

    case access
    when Invidious::Lightious::DeviceAuthorization::RequestAccess::Public,
         Invidious::Lightious::DeviceAuthorization::RequestAccess::MediaCapability
      call_next env
    when Invidious::Lightious::DeviceAuthorization::RequestAccess::DeviceBearer
      if device = active_device(env)
        env.set Invidious::Lightious::DeviceAuthorization::DEVICE_CONTEXT_KEY, device
        call_next env
      else
        reject_device(env)
      end
    when Invidious::Lightious::DeviceAuthorization::RequestAccess::Deny
      hide_route(env)
    end
  end

  private def active_device(env) : Invidious::Database::Lightious::Device?
    digest = Invidious::Lightious::DeviceAuthorization.bearer_digest(
      env.request.headers["Authorization"]?,
    )
    digest.try { |value| Invidious::Database::Lightious.active_device(value) }
  end

  private def reject_device(env)
    env.response.status_code = 401
    env.response.content_type = "application/json"
    env.response.headers["Cache-Control"] = "no-store"
    env.response.headers["WWW-Authenticate"] = %(Bearer realm="Lightious", error="invalid_token")
    env.response.print({"error" => "Invalid device credential."}.to_json) unless env.request.method == "HEAD"
    env.response.close
  end

  private def hide_route(env)
    env.response.status_code = 404
    env.response.headers["Cache-Control"] = "no-store"
    env.response.headers["X-Robots-Tag"] = "noindex, nofollow"

    unless env.request.method == "HEAD"
      if env.request.path.starts_with?("/api/")
        env.response.content_type = "application/json"
        env.response.print({"error" => "Not found."}.to_json)
      else
        env.response.content_type = "text/plain; charset=utf-8"
        env.response.print("Not found.")
      end
    end

    env.response.close
  end
end
