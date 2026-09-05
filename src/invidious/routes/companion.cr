module Invidious::Routes::Companion
  private LIGHTIOUS_MEDIA_RESPONSE_HEADERS = {
    "accept-ranges",
    "content-disposition",
    "content-length",
    "content-range",
    "content-type",
    "etag",
    "expires",
    "last-modified",
    "retry-after",
  }

  # GET /companion
  def self.get_companion(env)
    url = env.request.path
    if env.request.query
      url += "?#{env.request.query}"
    end

    begin
      COMPANION_POOL.client do |wrapper|
        wrapper.client.get(url, env.request.headers) do |resp|
          return self.proxy_companion(env, resp)
        end
      end
    rescue ex
    end
  end

  # POST /companion
  def self.post_companion(env)
    url = env.request.path
    if env.request.query
      url += "?#{env.request.query}"
    end

    begin
      COMPANION_POOL.client do |wrapper|
        wrapper.client.post(url, env.request.headers, env.request.body) do |resp|
          return self.proxy_companion(env, resp)
        end
      end
    rescue ex
    end
  end

  def self.options_companion(env)
    url = env.request.path
    if env.request.query
      url += "?#{env.request.query}"
    end

    begin
      COMPANION_POOL.client do |wrapper|
        wrapper.client.options(url, env.request.headers) do |resp|
          return self.proxy_companion(env, resp)
        end
      end
    rescue ex
    end
  end

  # The Lightious endpoint authorizes the device and source URL before handing
  # the media request to Companion. Companion owns the YouTube-specific HEAD +
  # POST exchange and keeps every hop on the same configured egress.
  def self.get_lightious_video_playback(env, query_params : HTTP::Params)
    env.response.headers["Cache-Control"] = "private, no-store"
    headers = HTTP::Headers.new
    if range = env.request.headers["Range"]?
      headers["Range"] = range
    end

    response_started = false
    begin
      COMPANION_POOL.stream do |wrapper|
        base_path = wrapper.companion.private_url.path.rstrip("/")
        url = "#{base_path}/videoplayback?#{query_params}"
        wrapper.client.get(url, headers) do |resp|
          response_started = true
          return self.proxy_lightious_media(env, resp)
        end
      end
    rescue ex
      # Exception messages from HTTP clients can include the full signed
      # upstream request target, so keep this log deliberately generic.
      LOGGER.error("Lightious media request to Companion failed (#{ex.class}).")
      raise ex if response_started

      env.response.status_code = 502
      env.response.content_type = "text/plain"
      env.response.print("Media gateway unavailable.")
    end
  end

  private def self.proxy_companion(env, response)
    env.response.status_code = response.status_code
    response.headers.each do |key, value|
      env.response.headers[key] = value
    end

    return IO.copy response.body_io, env.response
  end

  private def self.proxy_lightious_media(env, response)
    # Companion's /videoplayback endpoint is a byte-stream endpoint. Never let
    # an unexpected redirect escape the signed Lightious gateway.
    if response.status_code >= 300 && response.status_code < 400
      env.response.status_code = 502
      env.response.content_type = "text/plain"
      return env.response.print("The media gateway returned an invalid redirect.")
    end

    env.response.status_code = response.status_code
    response.headers.each do |key, value|
      normalized_key = key.downcase
      if LIGHTIOUS_MEDIA_RESPONSE_HEADERS.includes?(normalized_key)
        env.response.headers[key] = value
      end
    end

    env.response.headers["Cache-Control"] = "private, no-store"
    IO.copy response.body_io, env.response
    nil
  end
end
