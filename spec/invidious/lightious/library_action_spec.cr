require "spectator"
require "../../../src/invidious/lightious/library_action"

Spectator.describe Invidious::Lightious::LibraryAction do
  describe ".parse_video" do
    it "keeps destination and playback policy independent" do
      playlist_audio = described_class.parse_video("playlist:audio")
      both_video = described_class.parse_video("library_and_playlist:video")

      expect(playlist_audio.try(&.destination.playlist?)).to be_true
      expect(playlist_audio.try(&.destination.includes_library?)).to be_false
      expect(playlist_audio.try(&.playback_policy)).to eq("listen_only")
      expect(both_video.try(&.destination.includes_library?)).to be_true
      expect(both_video.try(&.destination.includes_playlist?)).to be_true
      expect(both_video.try(&.playback_policy)).to eq("watch_and_listen")
    end

    it "rejects unknown and incomplete actions" do
      expect(described_class.parse_video("library")).to be_nil
      expect(described_class.parse_video("channel:audio")).to be_nil
      expect(described_class.parse_video("playlist:automatic")).to be_nil
      expect(described_class.parse_video(nil)).to be_nil
    end
  end

  describe ".parse_channel" do
    it "accepts only explicit library channel actions" do
      expect(described_class.parse_channel("library:audio")).to eq("listen_only")
      expect(described_class.parse_channel("library:video")).to eq("watch_and_listen")
      expect(described_class.parse_channel("playlist:audio")).to be_nil
      expect(described_class.parse_channel("library_and_playlist:video")).to be_nil
    end
  end
end
