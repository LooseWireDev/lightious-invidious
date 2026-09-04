require "base64"
require "crypto/subtle"
require "openssl/hmac"

module Invidious::Lightious::ChannelContinuation
  extend self

  TTL               = 6.hours
  MAX_RAW_BYTES     = 6_000
  MAX_ENCODED_BYTES = 8_000
  MAX_TOKEN_BYTES   = 8_100
  private TOKEN_TAG         = "lptc1"
  private SIGNATURE_DOMAIN  = "lightious:channel-continuation:v1"

  def mint(
    key : String,
    device_id : String,
    channel_id : String,
    raw_continuation : String,
    now : Time = Time.utc,
  ) : String?
    return nil unless valid_device_id?(device_id)
    return nil unless valid_channel_id?(channel_id)
    return nil if raw_continuation.empty? || raw_continuation.bytesize > MAX_RAW_BYTES

    expires_at = (now + TTL).to_unix
    encoded = Base64.urlsafe_encode(raw_continuation, padding: false)
    return nil if encoded.bytesize > MAX_ENCODED_BYTES

    signature = sign(key, device_id, channel_id, expires_at, raw_continuation)
    "#{TOKEN_TAG}.#{expires_at}.#{encoded}.#{signature}"
  end

  def verify(
    key : String,
    device_id : String,
    channel_id : String,
    token : String,
    now : Time = Time.utc,
  ) : String?
    return nil unless valid_device_id?(device_id)
    return nil unless valid_channel_id?(channel_id)
    return nil if token.bytesize > MAX_TOKEN_BYTES

    parts = token.split('.', 4)
    return nil unless parts.size == 4 && parts[0] == TOKEN_TAG

    expires_at = parts[1].to_i64?
    encoded = parts[2]
    supplied_signature = parts[3]
    return nil unless expires_at
    return nil unless expires_at > now.to_unix
    return nil unless expires_at <= (now + TTL).to_unix
    return nil if encoded.empty? || encoded.bytesize > MAX_ENCODED_BYTES
    return nil unless supplied_signature.matches?(/\A[0-9a-f]{64}\z/)

    raw_continuation = decode(encoded)
    return nil unless raw_continuation

    expected_signature = sign(key, device_id, channel_id, expires_at, raw_continuation)
    return nil unless Crypto::Subtle.constant_time_compare(expected_signature, supplied_signature)

    raw_continuation
  end

  private def decode(encoded : String) : String?
    decoded = Base64.decode(encoded)
    return nil if decoded.empty? || decoded.size > MAX_RAW_BYTES

    String.new(decoded)
  rescue Base64::Error
    nil
  end

  private def sign(
    key : String,
    device_id : String,
    channel_id : String,
    expires_at : Int64,
    raw_continuation : String,
  ) : String
    value = String.build do |io|
      io << SIGNATURE_DOMAIN << '\0'
      io << device_id << '\0'
      io << channel_id << '\0'
      io << expires_at << '\0'
      io << raw_continuation
    end
    OpenSSL::HMAC.hexdigest(:sha256, key, value)
  end

  private def valid_device_id?(value : String) : Bool
    value.matches?(/\A[0-9a-f]{32}\z/)
  end

  private def valid_channel_id?(value : String) : Bool
    value.matches?(/\AUC[A-Za-z0-9_-]{22}\z/)
  end
end
