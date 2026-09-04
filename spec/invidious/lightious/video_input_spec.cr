require "spectator"
require "../../../src/invidious/lightious/video_input"

Spectator.describe Invidious::Lightious::VideoInput do
  describe ".extract_video_id" do
    it "accepts video IDs and common YouTube URLs" do
      expect(described_class.extract_video_id(" dQw4w9WgXcQ ")).to eq("dQw4w9WgXcQ")
      expect(described_class.extract_video_id("https://youtu.be/dQw4w9WgXcQ?t=2")).to eq("dQw4w9WgXcQ")
      expect(described_class.extract_video_id("https://invidious.example/watch?v=dQw4w9WgXcQ")).to eq("dQw4w9WgXcQ")
    end

    it "rejects explicit Shorts URLs" do
      expect(described_class.extract_video_id("https://youtube.com/shorts/dQw4w9WgXcQ")).to be_nil
      expect(described_class.extract_video_id("https://invidious.example/shorts/dQw4w9WgXcQ")).to be_nil
      expect(described_class.extract_video_id("https://youtube.com/shorts/watch?v=dQw4w9WgXcQ")).to be_nil
    end

    it "rejects invalid and oversized input" do
      expect(described_class.extract_video_id("not a video")).to be_nil
      expect(described_class.extract_video_id("https://example.com/watch?v=short")).to be_nil
      expect(described_class.extract_video_id("a" * 2049)).to be_nil
    end
  end
end
