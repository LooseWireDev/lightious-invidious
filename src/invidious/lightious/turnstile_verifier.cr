require "http/client"
require "json"
require "uri"

require "./security_inputs"

module Invidious::Lightious
  class TurnstileVerifier
    SITEVERIFY_URI      = URI.parse("https://challenges.cloudflare.com/turnstile/v0/siteverify")
    MAX_TOKEN_BYTES     = 2048
    MAX_REMOTE_IP_BYTES =   64
    MAX_RESPONSE_BYTES  = 16 * 1024
    ACTION_PATTERN      = /\A[A-Za-z0-9_-]{1,32}\z/

    record TransportResponse, status_code : Int32, body : String

    abstract class Transport
      abstract def post(form : HTTP::Params) : TransportResponse
    end

    class HTTPTransport < Transport
      def initialize(
        @connect_timeout : Time::Span = 3.seconds,
        @read_timeout : Time::Span = 5.seconds,
        @write_timeout : Time::Span = 5.seconds,
      )
      end

      def post(form : HTTP::Params) : TransportResponse
        client = HTTP::Client.new(SITEVERIFY_URI)
        begin
          client.connect_timeout = @connect_timeout
          client.read_timeout = @read_timeout
          client.write_timeout = @write_timeout

          headers = HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
          response = client.post(SITEVERIFY_URI.request_target, headers, form.to_s)
          TransportResponse.new(response.status_code, response.body)
        ensure
          client.close
        end
      end
    end

    private struct SiteverifyResponse
      include JSON::Serializable

      getter success : Bool = false
      getter action : String?
      getter hostname : String?
    end

    getter expected_action : String
    getter expected_hostname : String

    @transport : Transport

    def initialize(
      @secret : String,
      @expected_action : String,
      expected_hostname : String,
      @transport : Transport = HTTPTransport.new,
    )
      raise ArgumentError.new("Turnstile secret must not be empty") if @secret.empty?
      unless ACTION_PATTERN.matches?(@expected_action)
        raise ArgumentError.new("Turnstile action must contain 1-32 letters, digits, underscores, or hyphens")
      end

      @expected_hostname = Invidious::Lightious::SecurityInputs.normalize_hostname(expected_hostname) ||
                           raise ArgumentError.new("Turnstile hostname must be a bare DNS hostname")
    end

    # Returns false for malformed input, transport failures, non-success HTTP
    # responses, malformed Siteverify JSON, unsuccessful challenges, or an
    # action/hostname mismatch. Tokens and secrets are never logged.
    def verify(token : String?, remote_ip : String?) : Bool
      return false unless token
      return false if token.empty? || token.bytesize > MAX_TOKEN_BYTES
      return false if remote_ip && remote_ip.bytesize > MAX_REMOTE_IP_BYTES

      form = HTTP::Params.new
      form["secret"] = @secret
      form["response"] = token
      form["remoteip"] = remote_ip if remote_ip && !remote_ip.empty?

      response = @transport.post(form)
      valid_response?(response)
    rescue
      false
    end

    private def valid_response?(response : TransportResponse) : Bool
      return false unless (200..299).includes?(response.status_code)
      return false if response.body.bytesize > MAX_RESPONSE_BYTES

      result = SiteverifyResponse.from_json(response.body)
      return false unless result.success
      return false unless result.action == @expected_action

      hostname = result.hostname
      return false unless hostname
      Invidious::Lightious::SecurityInputs.normalize_hostname(hostname) == @expected_hostname
    rescue JSON::ParseException
      false
    end
  end
end
