module Invidious::Lightious::VideoInput
  VIDEO_ID_PATTERN = /^[A-Za-z0-9_-]{11}$/
  MAX_INPUT_BYTES  = 2048

  def self.extract_video_id(input : String) : String?
    value = input.strip
    return nil if value.empty? || value.bytesize > MAX_INPUT_BYTES
    return value if valid_video_id?(value)

    uri = URI.parse(value)
    if query = uri.query
      video_id = HTTP::Params.parse(query)["v"]?
      return video_id if video_id && valid_video_id?(video_id)
    end

    segments = uri.path.split('/').reject(&.empty?)
    host = uri.host.try &.downcase
    candidate = if host && {"youtu.be", "www.youtu.be"}.includes?(host)
                  segments[0]?
                elsif segments.size >= 2 && {"embed", "shorts", "live", "v"}.includes?(segments[-2])
                  segments[-1]?
                end

    candidate if candidate && valid_video_id?(candidate)
  rescue URI::Error
    nil
  end

  def self.valid_video_id?(video_id : String) : Bool
    video_id.matches?(VIDEO_ID_PATTERN)
  end
end
