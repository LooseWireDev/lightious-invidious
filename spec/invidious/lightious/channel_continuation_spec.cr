require "spectator"
require "../../../src/invidious/lightious/channel_continuation"

Spectator.describe Invidious::Lightious::ChannelContinuation do
  let(now) { Time.unix(1_800_000_000) }
  let(device_id) { "a" * 32 }
  let(channel_id) { "UC_x5XG1OV2P6uZZ5FSM9Ttw" }
  let(raw_continuation) { "4qmFsgKrAQ==" }

  it "round-trips only for the issuing device and channel" do
    token = described_class.mint(
      "server key",
      device_id,
      channel_id,
      raw_continuation,
      now,
    ).not_nil!

    expect(described_class.verify("server key", device_id, channel_id, token, now)).to eq(raw_continuation)
    expect(described_class.verify("server key", "b" * 32, channel_id, token, now)).to be_nil
    expect(described_class.verify("server key", device_id, "UCaaaaaaaaaaaaaaaaaaaaaa", token, now)).to be_nil
  end

  it "rejects tampering, expiry, malformed bindings, and oversized values" do
    token = described_class.mint(
      "server key",
      device_id,
      channel_id,
      raw_continuation,
      now,
    ).not_nil!

    expect(described_class.verify("wrong key", device_id, channel_id, token, now)).to be_nil
    expect(described_class.verify("server key", device_id, channel_id, token + "x", now)).to be_nil
    expect(described_class.verify("server key", device_id, channel_id, token, now + 6.hours)).to be_nil
    expect(described_class.mint("key", "short", channel_id, raw_continuation, now)).to be_nil
    expect(described_class.mint("key", device_id, "short", raw_continuation, now)).to be_nil
    expect(described_class.mint("key", device_id, channel_id, "", now)).to be_nil
    expect(described_class.mint("key", device_id, channel_id, "x" * 6_001, now)).to be_nil
  end
end
