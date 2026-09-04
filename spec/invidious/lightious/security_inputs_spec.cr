require "spectator"
require "../../../src/invidious/lightious/security_inputs"

Spectator.describe Invidious::Lightious::SecurityInputs do
  describe ".canonical_ip" do
    it "canonicalizes one numeric IPv4 or IPv6 address" do
      expect(described_class.canonical_ip("203.0.113.8")).to eq("203.0.113.8")
      expect(described_class.canonical_ip("2001:0db8:0:0:0:0:0:1")).to eq("2001:db8::1")
    end

    it "rejects forwarding chains, hostnames, whitespace, and oversized input" do
      expect(described_class.canonical_ip(nil)).to be_nil
      expect(described_class.canonical_ip("")).to be_nil
      expect(described_class.canonical_ip(" 203.0.113.8")).to be_nil
      expect(described_class.canonical_ip("203.0.113.8, 198.51.100.2")).to be_nil
      expect(described_class.canonical_ip("proxy.example.com")).to be_nil
      expect(described_class.canonical_ip("1" * 65)).to be_nil
    end
  end

  describe ".normalize_hostname" do
    it "normalizes a bare DNS hostname" do
      expect(described_class.normalize_hostname("LOGIN.Example.COM.")).to eq("login.example.com")
      expect(described_class.normalize_hostname("localhost")).to eq("localhost")
    end

    it "rejects URI syntax, ports, whitespace, and malformed DNS labels" do
      invalid = {
        "",
        " login.example.com",
        "https://login.example.com",
        "login.example.com:443",
        "login.example.com/path",
        "-login.example.com",
        "login..example.com",
        "login_.example.com",
        "#{"a" * 64}.example.com",
      }

      invalid.each do |hostname|
        expect(described_class.normalize_hostname(hostname)).to be_nil
      end
    end
  end

  describe ".login_origin_allowed?" do
    it "requires the exact configured public origin" do
      public_url = URI.parse("https://Lightious.Example.com/library")

      expect(described_class.login_origin_allowed?(
        "https://lightious.example.com",
        public_url,
        "internal:3000",
        false,
      )).to be_true
      expect(described_class.login_origin_allowed?(nil, public_url, "internal:3000", false)).to be_false
      expect(described_class.login_origin_allowed?("https://evil.example", public_url, "internal:3000", false)).to be_false
      expect(described_class.login_origin_allowed?("http://lightious.example.com", public_url, "internal:3000", false)).to be_false
      expect(described_class.login_origin_allowed?("https://lightious.example.com:444", public_url, "internal:3000", false)).to be_false
      expect(described_class.login_origin_allowed?("null", public_url, "internal:3000", false)).to be_false
    end

    it "allows the documented compatibility path only on a matching local origin" do
      no_public_url = URI.parse("")

      expect(described_class.login_origin_allowed?(nil, no_public_url, "localhost:3000", false)).to be_true
      expect(described_class.login_origin_allowed?("http://localhost:3000", no_public_url, "localhost:3000", false)).to be_true
      expect(described_class.login_origin_allowed?("http://127.0.0.1:3000", no_public_url, "localhost:3000", false)).to be_false
      expect(described_class.login_origin_allowed?("https://localhost:3000", no_public_url, "localhost:3000", false)).to be_false
      expect(described_class.login_origin_allowed?(nil, no_public_url, "lightious.example.com", true)).to be_false
      expect(described_class.login_origin_allowed?("http://evil.example", no_public_url, "localhost:3000", false)).to be_false
    end
  end

  it "keeps Turnstile challenge rendering independent from Lightious theming" do
    template = File.read("src/invidious/views/user/login.ecr")

    expect(template).to contain("lightious_login = Invidious::Lightious::AbuseProtection.lightious_login_page?(referer)")
    expect(template).to contain("lightious_turnstile = protected_login && Invidious::Lightious::AbuseProtection.turnstile_enabled?")
  end

  it "escapes the locale before placing it in the companion html language attribute" do
    template = File.read("src/invidious/views/lightious/template.ecr")

    expect(template).to contain(%(<html lang="<%= HTML.escape(locale) %>">))
    expect(template).not_to contain(%(<html lang="<%= locale %>">))
  end
end
