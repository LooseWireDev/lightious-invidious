module Invidious::Lightious::DeviceAuthorization
  extend self

  enum RequestAccess
    Public
    DeviceBearer
    MediaCapability
    Deny
  end

  DEVICE_CONTEXT_KEY = "lightious.device"

  private PAIRING_STATUS_PATH    = /\A\/api\/lightious\/v1\/pairings\/[0-9a-f]{32}\z/
  private PAIRING_ACTIVATE_PATH  = /\A\/api\/lightious\/v1\/pairings\/[0-9a-f]{32}\/activate\z/
  private VIDEO_MUTATION_PATH    = /\A\/lightious\/videos\/[0-9a-f]{32}\/(?:policy|delete)\z/
  private CHANNEL_MUTATION_PATH  = /\A\/lightious\/channels\/[0-9a-f]{32}\/(?:policy|delete)\z/
  private PLAYLIST_MUTATION_PATH = /\A\/lightious\/playlists\/[0-9a-f]{32}\/(?:rename|items\/remove|search\/add|delete)\z/
  private PLAYLIST_PAGE_PATH     = /\A\/lightious\/playlists\/[0-9a-f]{32}\z/
  private CHANNEL_PAGE_PATH      = /\A\/lightious\/channels\/UC[A-Za-z0-9_-]{22}\z/
  private CHANNEL_ADD_PATH       = /\A\/lightious\/channels\/UC[A-Za-z0-9_-]{22}\/(?:add|videos\/add)\z/
  private DEVICE_REVOKE_PATH     = /\A\/lightious\/devices\/[0-9a-f]{32}\/revoke\z/

  # Parses only an RFC 6750-style bearer credential and returns the digest used
  # for the indexed device lookup. The opaque credential itself is never put in
  # request context, logs, media URLs, or database storage.
  def bearer_digest(authorization : String?) : String?
    return nil unless authorization

    parts = authorization.split(' ', 2)
    return nil unless parts.size == 2
    return nil unless parts[0].downcase == "bearer"

    bearer = parts[1]
    return nil unless Invidious::Lightious::Pairing.valid_device_bearer?(bearer)

    Invidious::Lightious::Pairing.device_bearer_digest(bearer)
  end

  # This allowlist is intentionally small. When Lightious lockdown is enabled,
  # every new route starts denied; device API additions must opt in under the
  # protected namespace rather than accidentally exposing upstream Invidious.
  def request_access(method : String, path : String) : RequestAccess
    normalized_method = method.upcase
    read_method = normalized_method == "GET" || normalized_method == "HEAD"

    return RequestAccess::Public if lightious_browser_path?(normalized_method, path)
    return RequestAccess::Public if login_path?(normalized_method, path)
    return RequestAccess::Public if read_method && static_or_thumbnail_path?(path)
    return RequestAccess::Public if read_method && path == "/api/v1/stats"

    if path == "/api/lightious/v1/media"
      return RequestAccess::Public if normalized_method == "OPTIONS"
      return read_method ? RequestAccess::MediaCapability : RequestAccess::Deny
    end

    if path == "/api/lightious/v1/pairings" && normalized_method == "POST"
      return RequestAccess::Public
    end

    if PAIRING_STATUS_PATH.matches?(path) && read_method
      return RequestAccess::Public
    end

    if PAIRING_ACTIVATE_PATH.matches?(path) && normalized_method == "POST"
      return RequestAccess::Public
    end

    if lightious_api_path?(path)
      return RequestAccess::Public if normalized_method == "OPTIONS"
      return RequestAccess::DeviceBearer
    end

    RequestAccess::Deny
  end

  # Browser routes still perform SID and CSRF validation in LightiousControl.
  # Keep this list exact so a future route is not made public merely by using
  # the Lightious namespace.
  private def lightious_browser_path?(method : String, path : String) : Bool
    if {"GET", "HEAD"}.includes?(method)
      return true if PLAYLIST_PAGE_PATH.matches?(path) || CHANNEL_PAGE_PATH.matches?(path)
      return {
        "/lightious",
        "/lightious/library",
        "/lightious/search",
        "/lightious/playlists",
        "/lightious/pair",
      }.includes?(path)
    end

    return false unless method == "POST"
    return true if {
                     "/lightious/pair/preview",
                     "/lightious/pair",
                     "/lightious/mode",
                     "/lightious/library/add",
                     "/lightious/videos/bulk",
                     "/lightious/channels/bulk",
                     "/lightious/playlists",
                   }.includes?(path)

    VIDEO_MUTATION_PATH.matches?(path) ||
      CHANNEL_MUTATION_PATH.matches?(path) ||
      CHANNEL_ADD_PATH.matches?(path) ||
      PLAYLIST_MUTATION_PATH.matches?(path) ||
      DEVICE_REVOKE_PATH.matches?(path)
  end

  private def lightious_api_path?(path : String) : Bool
    path == "/api/lightious/v1" || path.starts_with?("/api/lightious/v1/")
  end

  private def login_path?(method : String, path : String) : Bool
    return true if path == "/login" && {"GET", "HEAD", "POST"}.includes?(method)
    return true if path == "/signout" && method == "POST"
    return true if path == "/toggle_theme" && {"GET", "HEAD"}.includes?(method)

    false
  end

  private def static_or_thumbnail_path?(path : String) : Bool
    return true if {
                     "/favicon.ico",
                     "/favicon-16x16.png",
                     "/favicon-32x32.png",
                     "/apple-touch-icon.png",
                     "/safari-pinned-tab.svg",
                     "/site.webmanifest",
                     "/browserconfig.xml",
                     "/robots.txt",
                     "/.well-known/dnt-policy.txt",
                   }.includes?(path)

    {
      "/css/",
      "/js/",
      "/fonts/",
      "/vi/",
      "/ggpht/",
    }.any? { |prefix| path.starts_with?(prefix) }
  end
end
