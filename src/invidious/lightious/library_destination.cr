enum Invidious::Lightious::LibraryDestination
  LibraryOnly
  PlaylistOnly
  LibraryAndPlaylist

  def self.from_wire(value : String) : self?
    case value
    when "library_only"         then LibraryOnly
    when "playlist_only"        then PlaylistOnly
    when "library_and_playlist" then LibraryAndPlaylist
    end
  end

  def library_visible? : Bool
    self != PlaylistOnly
  end

  def playlist_membership? : Bool
    self != LibraryOnly
  end

  # Adding a video to a playlist must never remove an existing explicit
  # top-level library selection.
  def merge_library_visibility(existing : Bool) : Bool
    existing || library_visible?
  end

  # Hidden records exist only to back one or more playlist memberships.
  def self.retain_item?(library_visible : Bool, playlist_count : Int) : Bool
    library_visible || playlist_count > 0
  end
end
