require "spectator"
require "../../../src/invidious/lightious/channel_feed"

alias LightiousChannelFeed = Invidious::Lightious::ChannelFeed

module ChannelFeedSpecHelpers
  extend self

  def entry(id : String, published : Int64, *, live = false, upcoming = false)
    LightiousChannelFeed::Entry.new(
      id: id,
      title: "Video #{id}",
      author: "Channel",
      author_id: "UC_x5XG1OV2P6uZZ5FSM9Ttw",
      published: Time.unix(published),
      views: 1_i64,
      length_seconds: 60,
      premiere_timestamp: upcoming ? Time.unix(published + 60) : nil,
      live_now: live,
    )
  end
end

Spectator.describe Invidious::Lightious::ChannelFeed do
  it "round-trips compact cursor state and rejects malformed state" do
    cursor = LightiousChannelFeed::Cursor.new(
      LightiousChannelFeed::Position.new(false, "uploads-next", 12),
      LightiousChannelFeed::Position.initial,
    )

    encoded = described_class.encode(cursor)
    expect(JSON.parse(encoded).as_h.has_key?("s")).to be_false
    expect(described_class.decode(encoded)).to eq(cursor)
    expect(described_class.decode(%({"v":1,"u":{"d":true,"o":1,"c":null}}))).to be_nil
    expect(described_class.decode("x" * 6_001)).to be_nil
  end

  it "replays oversized source pages before advancing their continuation" do
    first = described_class.page_window(75, LightiousChannelFeed::Position.initial, "next-page")
    second = described_class.page_window(75, first.next_position, "next-page")
    third = described_class.page_window(75, second.next_position, "next-page")

    expect({first.start, first.size, first.next_position.offset}).to eq({0, 30, 30})
    expect({second.start, second.size, second.next_position.offset}).to eq({30, 30, 60})
    expect({third.start, third.size}).to eq({60, 15})
    expect(third.next_position.continuation).to eq("next-page")
    expect(third.next_position.offset).to eq(0)
  end

  it "deduplicates, prefers live metadata, and orders newest first" do
    duplicate_upload = ChannelFeedSpecHelpers.entry("AAAAAAAAAAA", 100)
    duplicate_live = ChannelFeedSpecHelpers.entry("AAAAAAAAAAA", 90, live: true)
    newest_upload = ChannelFeedSpecHelpers.entry("BBBBBBBBBBB", 200)

    merged = described_class.merge([
      [duplicate_live],
      [newest_upload],
      [duplicate_upload],
    ])

    expect(merged.map(&.id)).to eq(["BBBBBBBBBBB", "AAAAAAAAAAA"])
    expect(merged.last.live_now).to be_true
  end

  it "bounds every unified response" do
    entries = Array.new(100) do |index|
      ChannelFeedSpecHelpers.entry("video-#{index}", index.to_i64)
    end

    expect(described_class.merge([entries]).size).to eq(60)
  end

  it "disables cursor sources when the channel no longer exposes their tabs" do
    cursor = described_class.initial_cursor(true, true)
    constrained = described_class.constrain(cursor, true, false)

    expect(constrained.uploads.complete).to be_false
    expect(constrained.streams.complete).to be_true
  end
end
