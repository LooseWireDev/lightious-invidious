module Invidious::Lightious::LibrarySelection
  enum Kind
    Video
    Channel
  end

  record Entry,
    kind : Kind,
    id : String do
    def key : String
      "#{kind.to_s.downcase}:#{id}"
    end
  end

  VIDEO_ID_PATTERN   = /^[A-Za-z0-9_-]{11}$/
  CHANNEL_ID_PATTERN = /^UC[A-Za-z0-9_-]{22}$/
  MAX_VALUE_BYTES    = 64

  def self.parse(value : String) : Entry?
    return nil if value.empty? || value.bytesize > MAX_VALUE_BYTES

    parts = value.split(':', 2)
    return nil unless parts.size == 2

    kind = parts[0]
    id = parts[1]
    case kind
    when "video"
      Entry.new(Kind::Video, id) if id.matches?(VIDEO_ID_PATTERN)
    when "channel"
      Entry.new(Kind::Channel, id) if id.matches?(CHANNEL_ID_PATTERN)
    end
  end
end
