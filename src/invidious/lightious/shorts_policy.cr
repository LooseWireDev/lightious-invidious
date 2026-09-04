module Invidious::Lightious::ShortsPolicy
  extend self

  # YouTube currently limits Shorts to three minutes. Duration alone is not
  # enough to classify a video: ordinary brief landscape videos remain valid.
  MAX_SHORT_SECONDS = 180

  def short?(video : SearchVideo) : Bool
    video.badges.shorts?
  end

  def short?(video : Video) : Bool
    return true if video.info["isShort"]?.try(&.as_bool?) == true
    return false if video.live_now || video.video_type == VideoType::Scheduled

    duration = video.length_seconds
    return false unless duration.in?(1..MAX_SHORT_SECONDS)

    (video.video_streams + video.fmt_stream).any? do |format|
      width = format["width"]?.try(&.as_i?)
      height = format["height"]?.try(&.as_i?)
      short_dimensions?(width, height)
    end
  end

  # Shorts are square or portrait. Keeping this separate makes the fail-closed
  # playback rule testable without reaching YouTube.
  def short_dimensions?(width : Int?, height : Int?) : Bool
    return false unless width && height
    width > 0 && height > 0 && height >= width
  end

  def reject_from(items : Array(SearchItem)) : Array(SearchItem)
    items.reject do |item|
      item.is_a?(SearchVideo) && short?(item)
    end
  end

  def reject_from(videos : Array(SearchVideo)) : Array(SearchVideo)
    videos.reject { |video| short?(video) }
  end
end
