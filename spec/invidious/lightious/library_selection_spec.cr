require "spectator"
require "../../../src/invidious/lightious/library_selection"

Spectator.describe Invidious::Lightious::LibrarySelection do
  describe ".parse" do
    it "parses typed video and channel selections" do
      video = described_class.parse("video:dQw4w9WgXcQ")
      channel = described_class.parse("channel:UC_x5XG1OV2P6uZZ5FSM9Ttw")

      expect(video.try(&.kind)).to eq(Invidious::Lightious::LibrarySelection::Kind::Video)
      expect(video.try(&.id)).to eq("dQw4w9WgXcQ")
      expect(video.try(&.key)).to eq("video:dQw4w9WgXcQ")
      expect(channel.try(&.kind)).to eq(Invidious::Lightious::LibrarySelection::Kind::Channel)
      expect(channel.try(&.id)).to eq("UC_x5XG1OV2P6uZZ5FSM9Ttw")
    end

    it "rejects unknown, malformed, and oversized selections" do
      expect(described_class.parse("playlist:PL1234567890")).to be_nil
      expect(described_class.parse("video:short")).to be_nil
      expect(described_class.parse("channel:UC-short")).to be_nil
      expect(described_class.parse("video:" + "a" * 65)).to be_nil
    end
  end
end
