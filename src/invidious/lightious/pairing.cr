require "base64"
require "crypto/subtle"
require "openssl/digest"
require "openssl/hmac"
require "random/secure"

module Invidious::Lightious::Pairing
  USER_CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
  USER_CODE_LENGTH   = 8

  POLL_SECRET_PREFIX   = "lpt_poll_"
  DEVICE_BEARER_PREFIX = "lpt_device_"

  SECRET_BYTES            = 32
  ENCODED_SECRET_BYTESIZE = 43
  SHA256_HEX_BYTESIZE     = 64

  private USER_CODE_DIGEST_DOMAIN  = "lightious:user-code:v1"
  private POLL_SECRET_DIGEST_DOMAIN = "lightious:poll-secret:v1"
  private BASE64URL_FINAL_CHARS     = "AEIMQUYcgkosw048"

  def self.generate_user_code : String
    normalized = String.build(USER_CODE_LENGTH) do |io|
      USER_CODE_LENGTH.times do
        io << USER_CODE_ALPHABET[Random::Secure.rand(USER_CODE_ALPHABET.size)]
      end
    end

    return "#{normalized[0, 4]}-#{normalized[4, 4]}"
  end

  # Returns the canonical, unformatted representation used for lookups.
  # Crockford's O/0 and I/L/1 aliases are safe because the ambiguous letters
  # are never generated.
  def self.normalize_user_code(user_code : String) : String?
    normalized = String::Builder.new(USER_CODE_LENGTH)
    length = 0

    user_code.each_char do |character|
      next if character.whitespace? || character == '-'

      canonical = case character
                  when 'O', 'o'
                    '0'
                  when 'I', 'i', 'L', 'l'
                    '1'
                  else
                    character.upcase
                  end

      return nil unless USER_CODE_ALPHABET.includes?(canonical)

      normalized << canonical
      length += 1
      return nil if length > USER_CODE_LENGTH
    end

    return nil unless length == USER_CODE_LENGTH

    normalized.to_s
  end

  def self.format_user_code(user_code : String) : String?
    normalized = normalize_user_code(user_code)
    return nil unless normalized

    "#{normalized[0, 4]}-#{normalized[4, 4]}"
  end

  def self.generate_poll_secret : String
    random_bearer(POLL_SECRET_PREFIX)
  end

  def self.generate_device_bearer : String
    random_bearer(DEVICE_BEARER_PREFIX)
  end

  def self.valid_poll_secret?(poll_secret : String) : Bool
    valid_random_bearer?(poll_secret, POLL_SECRET_PREFIX)
  end

  def self.valid_device_bearer?(device_bearer : String) : Bool
    valid_random_bearer?(device_bearer, DEVICE_BEARER_PREFIX)
  end

  def self.user_code_digest(key : String, user_code : String) : String?
    normalized = normalize_user_code(user_code)
    return nil unless normalized

    domain_separated_hmac(key, USER_CODE_DIGEST_DOMAIN, normalized)
  end

  def self.poll_secret_digest(key : String, poll_secret : String) : String?
    return nil unless valid_poll_secret?(poll_secret)

    domain_separated_hmac(key, POLL_SECRET_DIGEST_DOMAIN, poll_secret)
  end

  # Device bearers are generated on the phone, so this intentionally uses an
  # unkeyed digest. Only the digest is sent during pairing and stored later.
  def self.device_bearer_digest(device_bearer : String) : String
    digest = OpenSSL::Digest.new("SHA256")
    digest << device_bearer
    digest.final.hexstring
  end

  def self.valid_device_bearer_digest?(digest : String) : Bool
    return false unless digest.bytesize == SHA256_HEX_BYTESIZE

    digest.each_byte.all? do |byte|
      (byte >= '0'.ord && byte <= '9'.ord) ||
        (byte >= 'a'.ord && byte <= 'f'.ord)
    end
  end

  def self.valid_device_bearer?(device_bearer : String, expected_digest : String) : Bool
    return false unless valid_device_bearer?(device_bearer)
    return false unless valid_device_bearer_digest?(expected_digest)

    Crypto::Subtle.constant_time_compare(
      device_bearer_digest(device_bearer),
      expected_digest
    )
  end

  # Invidious stores both email addresses and username-style identifiers in
  # its email field. Mask only values that are clearly email-shaped.
  def self.account_display(account : String) : String
    account = account.strip
    parts = account.split('@')
    return account unless parts.size == 2

    local = parts[0]
    domain = parts[1]
    return account if local.empty? || domain.empty?

    visible_length = Math.min(local.size, 2)
    "#{local[0, visible_length]}…@#{domain}"
  end

  private def self.random_bearer(prefix : String) : String
    payload = Base64.urlsafe_encode(Random::Secure.random_bytes(SECRET_BYTES), padding: false)
    prefix + payload
  end

  private def self.valid_random_bearer?(bearer : String, prefix : String) : Bool
    return false unless bearer.starts_with?(prefix)

    payload = bearer.byte_slice(prefix.bytesize)
    return false unless payload.bytesize == ENCODED_SECRET_BYTESIZE
    return false unless BASE64URL_FINAL_CHARS.includes?(payload[-1])

    payload.each_byte.all? do |byte|
      (byte >= 'A'.ord && byte <= 'Z'.ord) ||
        (byte >= 'a'.ord && byte <= 'z'.ord) ||
        (byte >= '0'.ord && byte <= '9'.ord) ||
        byte == '-'.ord || byte == '_'.ord
    end
  end

  private def self.domain_separated_hmac(key : String, domain : String, value : String) : String
    OpenSSL::HMAC.hexdigest(:sha256, key, "#{domain}\0#{value}")
  end
end
