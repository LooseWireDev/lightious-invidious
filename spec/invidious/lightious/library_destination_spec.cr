require "spectator"
require "../../../src/invidious/lightious/library_destination"

Spectator.describe Invidious::Lightious::LibraryDestination do
  describe ".from_wire" do
    it "parses only the three supported destinations" do
      expect(described_class.from_wire("library_only")).to eq(Invidious::Lightious::LibraryDestination::LibraryOnly)
      expect(described_class.from_wire("playlist_only")).to eq(Invidious::Lightious::LibraryDestination::PlaylistOnly)
      expect(described_class.from_wire("library_and_playlist")).to eq(Invidious::Lightious::LibraryDestination::LibraryAndPlaylist)
      expect(described_class.from_wire("channel")).to be_nil
    end
  end

  it "keeps library and playlist placement independent" do
    library = Invidious::Lightious::LibraryDestination::LibraryOnly
    playlist = Invidious::Lightious::LibraryDestination::PlaylistOnly
    both = Invidious::Lightious::LibraryDestination::LibraryAndPlaylist

    expect(library.library_visible?).to be_true
    expect(library.playlist_membership?).to be_false
    expect(playlist.library_visible?).to be_false
    expect(playlist.playlist_membership?).to be_true
    expect(both.library_visible?).to be_true
    expect(both.playlist_membership?).to be_true
  end

  it "never hides an already-visible item during a playlist-only save" do
    destination = Invidious::Lightious::LibraryDestination::PlaylistOnly

    expect(destination.merge_library_visibility(true)).to be_true
    expect(destination.merge_library_visibility(false)).to be_false
  end

  it "retains hidden items only while a playlist still references them" do
    expect(described_class.retain_item?(true, 0)).to be_true
    expect(described_class.retain_item?(false, 2)).to be_true
    expect(described_class.retain_item?(false, 1)).to be_true
    expect(described_class.retain_item?(false, 0)).to be_false
  end
end
