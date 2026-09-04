module Invidious::Lightious::LibraryAction
  enum Destination
    Library
    Playlist
    LibraryAndPlaylist

    def includes_library? : Bool
      library? || library_and_playlist?
    end

    def includes_playlist? : Bool
      playlist? || library_and_playlist?
    end
  end

  record Video,
    destination : Destination,
    playback_policy : String

  POLICIES = {
    "audio" => "listen_only",
    "video" => "watch_and_listen",
  }

  DESTINATIONS = {
    "library"              => Destination::Library,
    "playlist"             => Destination::Playlist,
    "library_and_playlist" => Destination::LibraryAndPlaylist,
  }

  def self.parse_video(value : String?) : Video?
    parts = value.to_s.split(':', 2)
    return nil unless parts.size == 2

    destination = DESTINATIONS[parts[0]]?
    playback_policy = POLICIES[parts[1]]?
    return nil unless destination && playback_policy

    Video.new(destination, playback_policy)
  end

  def self.parse_channel(value : String?) : String?
    parts = value.to_s.split(':', 2)
    return nil unless parts.size == 2 && parts[0] == "library"

    POLICIES[parts[1]]?
  end
end
