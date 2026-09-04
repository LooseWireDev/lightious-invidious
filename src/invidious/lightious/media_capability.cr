require "base64"
require "crypto/subtle"
require "http/params"
require "openssl/hmac"
require "uri"

module Invidious::Lightious::MediaCapability
  extend self

  TTL               = 6.hours
  MAX_SOURCE_BYTES  =  9_000
  MAX_ENCODED_BYTES = 12_000

  DEVICE_ID_PARAM = "device"
  VIDEO_ID_PARAM  = "video"
  AUTHOR_ID_PARAM = "author"
  KIND_PARAM      = "kind"
  EXPIRES_PARAM   = "expires"
  SOURCE_PARAM    = "source"
  SIGNATURE_PARAM = "signature"

  private SIGNATURE_DOMAIN = "lightious:media-capability:v1"
  private VALID_KINDS      = {"audio", "video", "muxed"}

  record Grant,
    device_id : String,
    video_id : String,
    author_ucid : String?,
    kind : String,
    expires_at : Int64,
    source : String

  def mint(
    key : String,
    device_id : String,
    video_id : String,
    author_ucid : String?,
    kind : String,
    raw_url : String,
    now : Time = Time.utc,
  ) : String?
    return nil unless valid_device_id?(device_id)
    return nil unless valid_video_id?(video_id)
    return nil unless valid_author_ucid?(author_ucid)
    return nil unless VALID_KINDS.includes?(kind)

    source = normalize_source(raw_url)
    return nil unless source

    expires_at = capability_expiry(source, now)
    return nil unless expires_at > now.to_unix

    encoded_source = Base64.urlsafe_encode(source, padding: false)
    signature = sign(key, device_id, video_id, author_ucid, kind, expires_at, source)
    params = HTTP::Params.new
    params[DEVICE_ID_PARAM] = device_id
    params[VIDEO_ID_PARAM] = video_id
    params[AUTHOR_ID_PARAM] = author_ucid || ""
    params[KIND_PARAM] = kind
    params[EXPIRES_PARAM] = expires_at.to_s
    params[SOURCE_PARAM] = encoded_source
    params[SIGNATURE_PARAM] = signature

    "/api/lightious/v1/media?#{params}"
  end

  def verify(key : String, params : HTTP::Params, now : Time = Time.utc) : Grant?
    device_id = params[DEVICE_ID_PARAM]?
    video_id = params[VIDEO_ID_PARAM]?
    author_value = params[AUTHOR_ID_PARAM]?
    kind = params[KIND_PARAM]?
    expires_value = params[EXPIRES_PARAM]?
    encoded_source = params[SOURCE_PARAM]?
    supplied_signature = params[SIGNATURE_PARAM]?

    return nil unless device_id && valid_device_id?(device_id)
    return nil unless video_id && valid_video_id?(video_id)
    return nil unless author_value
    author_ucid = author_value.empty? ? nil : author_value
    return nil unless valid_author_ucid?(author_ucid)
    return nil unless kind && VALID_KINDS.includes?(kind)
    return nil unless expires_value && (expires_at = expires_value.to_i64?)
    return nil unless expires_at > now.to_unix
    return nil unless expires_at <= (now + TTL).to_unix
    return nil unless encoded_source && encoded_source.bytesize <= MAX_ENCODED_BYTES
    return nil unless supplied_signature && valid_signature?(supplied_signature)

    source = decode_source(encoded_source)
    return nil unless source
    return nil unless normalize_source(source) == source

    expected_signature = sign(key, device_id, video_id, author_ucid, kind, expires_at, source)
    return nil unless Crypto::Subtle.constant_time_compare(expected_signature, supplied_signature)

    Grant.new(device_id, video_id, author_ucid, kind, expires_at, source)
  end

  private def normalize_source(raw_url : String) : String?
    return nil if raw_url.bytesize > MAX_SOURCE_BYTES

    uri = URI.parse(raw_url)
    return nil if uri.fragment
    return nil unless uri.path == "/videoplayback"
    return nil if uri.query.to_s.empty?

    source = uri.request_target
    return nil unless source.bytesize <= MAX_SOURCE_BYTES

    source_params = uri.query_params
    host = source_params["host"]?
    return nil unless host && host.matches?(/\A[\w-]+\.(?:googlevideo|c\.youtube)\.com\z/)

    source
  rescue URI::Error
    nil
  end

  private def decode_source(encoded : String) : String?
    decoded = Base64.decode(encoded)
    return nil if decoded.size > MAX_SOURCE_BYTES

    String.new(decoded)
  rescue Base64::Error
    nil
  end

  private def capability_expiry(source : String, now : Time) : Int64
    expires_at = (now + TTL).to_unix
    upstream_expiry = URI.parse(source).query_params["expire"]?.try &.to_i64?

    if upstream_expiry && upstream_expiry < expires_at
      upstream_expiry
    else
      expires_at
    end
  end

  private def sign(
    key : String,
    device_id : String,
    video_id : String,
    author_ucid : String?,
    kind : String,
    expires_at : Int64,
    source : String,
  ) : String
    value = String.build do |io|
      io << SIGNATURE_DOMAIN << '\0'
      io << device_id << '\0'
      io << video_id << '\0'
      io << author_ucid.to_s << '\0'
      io << kind << '\0'
      io << expires_at << '\0'
      io << source
    end
    OpenSSL::HMAC.hexdigest(:sha256, key, value)
  end

  private def valid_device_id?(value : String) : Bool
    value.matches?(/\A[0-9a-f]{32}\z/)
  end

  private def valid_video_id?(value : String) : Bool
    value.matches?(/\A[A-Za-z0-9_-]{11}\z/)
  end

  private def valid_author_ucid?(value : String?) : Bool
    value.nil? || value.matches?(/\AUC[A-Za-z0-9_-]{22}\z/)
  end

  private def valid_signature?(value : String) : Bool
    value.matches?(/\A[0-9a-f]{64}\z/)
  end
end
