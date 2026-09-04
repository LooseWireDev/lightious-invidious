require "socket"
require "uri"

module Invidious::Lightious::SecurityInputs
  extend self

  MAX_IP_BYTES       =  64
  MAX_HOSTNAME_BYTES = 253

  private record Origin, scheme : String, host : String, port : Int32

  # Accept only one numeric address and return the standard library's
  # canonical representation. Hostnames and comma-delimited forwarding chains
  # are deliberately rejected.
  def canonical_ip(value : String?) : String?
    return nil unless value
    return nil unless value == value.strip
    return nil if value.empty? || value.bytesize > MAX_IP_BYTES || value.includes?(',')
    return nil unless Socket::IPAddress.valid?(value)

    Socket::IPAddress.new(value, 0).address
  rescue Socket::Error
    nil
  end

  # Returns a lowercase, dot-normalized bare DNS hostname. URI syntax, ports,
  # whitespace, empty labels, and labels outside DNS length/character rules
  # are rejected. `localhost` remains valid for Turnstile test keys.
  def normalize_hostname(value : String) : String?
    return nil unless value == value.strip

    normalized = value.downcase.rchop('.')
    return nil if normalized.empty? || normalized.bytesize > MAX_HOSTNAME_BYTES

    labels = normalized.split('.')
    return nil unless labels.all? do |label|
                        (1..63).includes?(label.bytesize) &&
                        label.matches?(/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/)
                      end

    normalized
  end

  # Public deployments require an explicit Origin that matches public_url.
  # When public_url is intentionally omitted, the compatibility path is
  # restricted to a localhost Host header; an absent Origin is accepted there
  # for command-line and older local clients, while any supplied Origin must
  # still match exactly.
  def login_origin_allowed?(
    origin_header : String?,
    public_url : URI,
    request_host : String?,
    local_https : Bool,
  ) : Bool
    if expected = origin_from_uri(public_url)
      supplied = origin_header.try { |value| parse_origin(value) }
      return supplied == expected
    end

    expected = local_request_origin(request_host, local_https)
    return false unless expected
    return true unless origin_header

    parse_origin(origin_header) == expected
  end

  private def local_request_origin(request_host : String?, local_https : Bool) : Origin?
    return nil unless request_host
    return nil unless request_host == request_host.strip
    return nil if request_host.empty? || request_host.bytesize > MAX_HOSTNAME_BYTES + 8

    scheme = local_https ? "https" : "http"
    uri = URI.parse("#{scheme}://#{request_host}")
    return nil unless uri.path.empty?
    return nil if uri.query || uri.fragment || uri.user || uri.password
    origin = origin_from_uri(uri)
    return nil unless origin
    return nil unless {"localhost", "127.0.0.1", "::1"}.includes?(origin.host)

    origin
  rescue URI::Error
    nil
  end

  private def parse_origin(value : String) : Origin?
    return nil unless value == value.strip
    return nil if value.empty? || value.bytesize > 512

    uri = URI.parse(value)
    return nil unless uri.path.empty?
    return nil if uri.query || uri.fragment || uri.user || uri.password

    origin_from_uri(uri)
  rescue URI::Error
    nil
  end

  private def origin_from_uri(uri : URI) : Origin?
    scheme = uri.scheme.try &.downcase
    return nil unless scheme && {"http", "https"}.includes?(scheme)
    return nil if uri.user || uri.password

    raw_host = uri.host
    return nil unless raw_host
    host = normalize_origin_host(raw_host)
    return nil unless host

    port = uri.port || (scheme == "https" ? 443 : 80)
    return nil unless (1..65_535).includes?(port)

    Origin.new(scheme, host, port)
  end

  private def normalize_origin_host(value : String) : String?
    candidate = value
    if candidate.starts_with?('[') && candidate.ends_with?(']')
      candidate = candidate[1...-1]
    end

    canonical_ip(candidate) || normalize_hostname(candidate)
  end
end
