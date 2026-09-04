require "spectator"
require "../../../src/invidious/lightious/turnstile_verifier"

private class StubTurnstileTransport < Invidious::Lightious::TurnstileVerifier::Transport
  getter forms = [] of HTTP::Params

  def initialize(
    @response : Invidious::Lightious::TurnstileVerifier::TransportResponse,
    @raise_transport_error : Bool = false,
  )
  end

  def post(form : HTTP::Params) : Invidious::Lightious::TurnstileVerifier::TransportResponse
    @forms << form
    raise IO::Error.new("test transport failure") if @raise_transport_error
    @response
  end
end

Spectator.describe Invidious::Lightious::TurnstileVerifier do
  def successful_response(
    action : String = "lightious_login",
    hostname : String = "login.example.com",
    status_code : Int32 = 200,
  )
    body = %({"success":true,"action":#{action.to_json},"hostname":#{hostname.to_json}})
    Invidious::Lightious::TurnstileVerifier::TransportResponse.new(status_code, body)
  end

  it "posts the secret, exact token, and optional remote address" do
    transport = StubTurnstileTransport.new(successful_response(hostname: "LOGIN.EXAMPLE.COM."))
    verifier = described_class.new(
      secret: "server-secret",
      expected_action: "lightious_login",
      expected_hostname: "login.example.com",
      transport: transport,
    )

    expect(verifier.verify("opaque-token", "203.0.113.8")).to be_true
    expect(transport.forms.size).to eq(1)
    expect(transport.forms[0]["secret"]).to eq("server-secret")
    expect(transport.forms[0]["response"]).to eq("opaque-token")
    expect(transport.forms[0]["remoteip"]).to eq("203.0.113.8")
  end

  it "omits an absent remote address" do
    transport = StubTurnstileTransport.new(successful_response)
    verifier = described_class.new("server-secret", "lightious_login", "login.example.com", transport)

    expect(verifier.verify("opaque-token", nil)).to be_true
    expect(transport.forms[0]["remoteip"]?).to be_nil
  end

  it "rejects invalid request inputs without contacting Siteverify" do
    transport = StubTurnstileTransport.new(successful_response)
    verifier = described_class.new("server-secret", "lightious_login", "login.example.com", transport)

    expect(verifier.verify(nil, nil)).to be_false
    expect(verifier.verify("", nil)).to be_false
    expect(verifier.verify("a" * 2049, nil)).to be_false
    expect(verifier.verify("token", "a" * 65)).to be_false
    expect(transport.forms).to be_empty
  end

  it "requires success plus the expected action and hostname" do
    invalid_responses = [
      Invidious::Lightious::TurnstileVerifier::TransportResponse.new(200, %({"success":false,"action":"lightious_login","hostname":"login.example.com"})),
      Invidious::Lightious::TurnstileVerifier::TransportResponse.new(200, %({"success":true,"action":"pair","hostname":"login.example.com"})),
      Invidious::Lightious::TurnstileVerifier::TransportResponse.new(200, %({"success":true,"action":"lightious_login","hostname":"other.example.com"})),
      Invidious::Lightious::TurnstileVerifier::TransportResponse.new(200, %({"success":true,"hostname":"login.example.com"})),
      Invidious::Lightious::TurnstileVerifier::TransportResponse.new(200, %({"success":true,"action":"lightious_login"})),
    ]

    invalid_responses.each do |response|
      transport = StubTurnstileTransport.new(response)
      verifier = described_class.new("server-secret", "lightious_login", "login.example.com", transport)
      expect(verifier.verify("opaque-token", nil)).to be_false
    end
  end

  it "fails closed for HTTP, response-size, JSON, and transport errors" do
    responses = [
      successful_response(status_code: 500),
      Invidious::Lightious::TurnstileVerifier::TransportResponse.new(200, "{"),
      Invidious::Lightious::TurnstileVerifier::TransportResponse.new(200, " " * (16 * 1024 + 1)),
    ]

    responses.each do |response|
      verifier = described_class.new(
        "server-secret",
        "lightious_login",
        "login.example.com",
        StubTurnstileTransport.new(response),
      )
      expect(verifier.verify("opaque-token", nil)).to be_false
    end

    failing_transport = StubTurnstileTransport.new(successful_response, raise_transport_error: true)
    verifier = described_class.new("server-secret", "lightious_login", "login.example.com", failing_transport)
    expect(verifier.verify("opaque-token", nil)).to be_false
  end

  it "rejects incomplete verifier configuration" do
    transport = StubTurnstileTransport.new(successful_response)

    expect { described_class.new("", "lightious_login", "login.example.com", transport) }.to raise_error(ArgumentError)
    expect { described_class.new("secret", "", "login.example.com", transport) }.to raise_error(ArgumentError)
    expect { described_class.new("secret", "contains spaces", "login.example.com", transport) }.to raise_error(ArgumentError)
    expect { described_class.new("secret", "lightious_login", "", transport) }.to raise_error(ArgumentError)
    expect { described_class.new("secret", "lightious_login", " https://login.example.com", transport) }.to raise_error(ArgumentError)
    expect { described_class.new("secret", "lightious_login", "login.example.com:443", transport) }.to raise_error(ArgumentError)
  end
end
