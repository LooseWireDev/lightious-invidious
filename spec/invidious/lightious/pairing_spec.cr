require "spectator"
require "../../../src/invidious/lightious/pairing"

Spectator.configure do |config|
  config.fail_blank
  config.randomize
end

Spectator.describe Invidious::Lightious::Pairing do
  describe ".generate_user_code" do
    it "generates an eight-character Crockford-style code in two groups" do
      codes = Array.new(32) { described_class.generate_user_code }

      expect(codes).to all(match(/\A[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}\z/))
      expect(codes.uniq.size).to be > 1
      expect(codes.join).to_not match(/[ILOU]/)
    end
  end

  describe ".normalize_user_code" do
    it "accepts case, whitespace, separators, and safe Crockford aliases" do
      expect(described_class.normalize_user_code(" o1il-abcd ")).to eq("0111ABCD")
      expect(described_class.normalize_user_code("s b-z 2 3 4 5")).to eq("SBZ2345")
      expect(described_class.format_user_code("o1il abcd")).to eq("0111-ABCD")
    end

    it "rejects invalid characters and the wrong number of symbols" do
      expect(described_class.normalize_user_code("ABCD-EFG")).to be_nil
      expect(described_class.normalize_user_code("ABCD-EFGH-J")).to be_nil
      expect(described_class.normalize_user_code("ABCU-EFGH")).to be_nil
      expect(described_class.normalize_user_code("ABCD_EFGH")).to be_nil
    end
  end

  describe "bearer generation" do
    it "generates distinct 256-bit poll secrets with an explicit prefix" do
      secrets = Array.new(16) { described_class.generate_poll_secret }

      expect(secrets).to all(match(/\Alpt_poll_[A-Za-z0-9_-]{43}\z/))
      expect(secrets).to all(satisfy { |secret| described_class.valid_poll_secret?(secret) })
      expect(secrets.uniq.size).to eq(secrets.size)
    end

    it "generates distinct 256-bit device bearers with an explicit prefix" do
      bearers = Array.new(16) { described_class.generate_device_bearer }

      expect(bearers).to all(match(/\Alpt_device_[A-Za-z0-9_-]{43}\z/))
      expect(bearers).to all(satisfy { |bearer| described_class.valid_device_bearer?(bearer) })
      expect(bearers.uniq.size).to eq(bearers.size)
    end

    it "rejects malformed, non-canonical, and incorrectly prefixed bearers" do
      poll_secret = described_class.generate_poll_secret
      device_bearer = described_class.generate_device_bearer

      expect(described_class.valid_poll_secret?(poll_secret + "A")).to be_false
      expect(described_class.valid_poll_secret?(device_bearer)).to be_false
      expect(described_class.valid_device_bearer?(device_bearer.sub(/.$/, "B"))).to be_false
      expect(described_class.valid_device_bearer?(poll_secret)).to be_false
    end
  end

  describe "digests" do
    it "normalizes user codes before applying a domain-separated HMAC" do
      canonical = described_class.user_code_digest("server key", "0111-ABCD")
      aliased = described_class.user_code_digest("server key", "o1il abcd")

      expect(canonical).to eq(aliased)
      expect(canonical).to match(/\A[0-9a-f]{64}\z/)
      expect(described_class.user_code_digest("another key", "0111-ABCD")).to_not eq(canonical)
      expect(described_class.user_code_digest("server key", "invalid!")).to be_nil
    end

    it "uses a separate HMAC domain for poll secrets" do
      poll_secret = described_class.generate_poll_secret
      poll_digest = described_class.poll_secret_digest("server key", poll_secret)

      expect(poll_digest).to match(/\A[0-9a-f]{64}\z/)
      expect(poll_digest).to_not eq(described_class.user_code_digest("server key", poll_secret))
      expect(described_class.poll_secret_digest("server key", "lpt_poll_short")).to be_nil
    end

    it "hashes and validates a client-generated device bearer" do
      bearer = "lpt_device_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
      digest = described_class.device_bearer_digest(bearer)

      expect(digest).to eq("5289f9a97df5ab15c14b190ee91e0234ee0e86cd3bbd32d1663c5e719b84a792")
      expect(described_class.valid_device_bearer_digest?(digest)).to be_true
      expect(described_class.valid_device_bearer?(bearer, digest)).to be_true
      expect(described_class.valid_device_bearer?(bearer, "0" * 64)).to be_false
      expect(described_class.valid_device_bearer?(bearer, digest.upcase)).to be_false
      expect(described_class.valid_device_bearer_digest?("f" * 63)).to be_false
    end
  end

  describe ".account_display" do
    it "masks email-shaped account identifiers" do
      expect(described_class.account_display(" gav@example.com ")).to eq("ga…@example.com")
      expect(described_class.account_display("x@example.com")).to eq("x…@example.com")
    end

    it "leaves username-style identifiers intact" do
      expect(described_class.account_display("gav")).to eq("gav")
      expect(described_class.account_display("not@an@email")).to eq("not@an@email")
    end
  end
end
