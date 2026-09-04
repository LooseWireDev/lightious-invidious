require "spectator"
require "../../../src/invidious/lightious/media_capability"

Spectator.describe Invidious::Lightious::MediaCapability do
  let(now) { Time.unix(1_800_000_000) }
  let(device_id) { "a" * 32 }
  let(video_id) { "dQw4w9WgXcQ" }
  let(author_ucid) { "UC_x5XG1OV2P6uZZ5FSM9Ttw" }
  let(source) do
    expiry = (now + 2.hours).to_unix
    "https://lightious.example/videoplayback?expire=#{expiry}&itag=140&host=r1---sn-abcd.googlevideo.com"
  end

  it "mints and verifies a stream-, video-, and device-scoped capability" do
    url = described_class.mint(
      "server key",
      device_id,
      video_id,
      author_ucid,
      "audio",
      source,
      now,
    )
    expect(url).to_not be_nil

    grant = described_class.verify(
      "server key",
      URI.parse(url.not_nil!).query_params,
      now + 1.minute,
    )
    expect(grant.try(&.device_id)).to eq(device_id)
    expect(grant.try(&.video_id)).to eq(video_id)
    expect(grant.try(&.author_ucid)).to eq(author_ucid)
    expect(grant.try(&.kind)).to eq("audio")
    expect(grant.try(&.expires_at)).to eq((now + 2.hours).to_unix)
    expect(grant.try(&.source)).to eq(URI.parse(source).request_target)
  end

  it "rejects expiry, a different key, and tampering with every authorization binding" do
    url = described_class.mint(
      "server key",
      device_id,
      video_id,
      author_ucid,
      "video",
      source,
      now,
    ).not_nil!
    original = URI.parse(url).query_params

    expect(described_class.verify("wrong key", original, now)).to be_nil
    expect(described_class.verify("server key", original, now + 2.hours)).to be_nil

    {
      Invidious::Lightious::MediaCapability::DEVICE_ID_PARAM => "b" * 32,
      Invidious::Lightious::MediaCapability::VIDEO_ID_PARAM  => "aqz-KE-bpKQ",
      Invidious::Lightious::MediaCapability::AUTHOR_ID_PARAM => "UCaaaaaaaaaaaaaaaaaaaaaa",
      Invidious::Lightious::MediaCapability::KIND_PARAM      => "audio",
      Invidious::Lightious::MediaCapability::EXPIRES_PARAM   => (now + 1.hour).to_unix.to_s,
      Invidious::Lightious::MediaCapability::SOURCE_PARAM    => Base64.urlsafe_encode(
        "/videoplayback?itag=18&host=r2---sn-abcd.googlevideo.com",
        padding: false,
      ),
    }.each do |name, value|
      tampered = URI.parse(url).query_params
      tampered[name] = value
      expect(described_class.verify("server key", tampered, now)).to be_nil
    end
  end

  it "rejects non-proxy URLs, invalid proxy hosts, malformed bindings, and stale upstream URLs" do
    expect(described_class.mint("key", device_id, video_id, author_ucid, "audio", "https://example.com/file", now)).to be_nil
    expect(described_class.mint(
      "key",
      device_id,
      video_id,
      author_ucid,
      "audio",
      "/videoplayback?host=googlevideo.com.evil.example",
      now,
    )).to be_nil
    expect(described_class.mint("key", "short", video_id, author_ucid, "audio", source, now)).to be_nil
    expect(described_class.mint("key", device_id, "short", author_ucid, "audio", source, now)).to be_nil
    expect(described_class.mint("key", device_id, video_id, author_ucid, "unknown", source, now)).to be_nil

    stale = "/videoplayback?expire=#{(now - 1.second).to_unix}&host=r1---sn-abcd.googlevideo.com"
    expect(described_class.mint("key", device_id, video_id, author_ucid, "audio", stale, now)).to be_nil
  end
end
