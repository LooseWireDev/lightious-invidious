require "json"

module Invidious::Lightious::ChannelFeed
  extend self

  PER_SOURCE_PAGE_SIZE          = 30
  MAX_PAGE_ITEMS                = PER_SOURCE_PAGE_SIZE * 2
  MAX_CURSOR_BYTES              =     6_000
  MAX_SOURCE_CONTINUATION_BYTES =     5_500
  MAX_SOURCE_OFFSET             = 1_000_000

  record Position,
    complete : Bool,
    continuation : String?,
    offset : Int32 do
    def self.initial : self
      new(false, nil, 0)
    end

    def self.finished : self
      new(true, nil, 0)
    end
  end

  record Cursor,
    uploads : Position,
    streams : Position do
    def complete? : Bool
      uploads.complete && streams.complete
    end
  end

  record Window,
    start : Int32,
    size : Int32,
    next_position : Position

  record Entry,
    id : String,
    title : String,
    author : String,
    author_id : String,
    published : Time,
    views : Int64,
    length_seconds : Int32,
    premiere_timestamp : Time?,
    live_now : Bool do
    def upcoming? : Bool
      premiere_timestamp.try { |value| value.to_unix > 0 } || false
    end
  end

  def initial_cursor(has_uploads : Bool, has_streams : Bool) : Cursor
    Cursor.new(
      has_uploads ? Position.initial : Position.finished,
      has_streams ? Position.initial : Position.finished,
    )
  end

  def constrain(cursor : Cursor, has_uploads : Bool, has_streams : Bool) : Cursor
    Cursor.new(
      has_uploads ? cursor.uploads : Position.finished,
      has_streams ? cursor.streams : Position.finished,
    )
  end

  # A source page is replayed with an offset when it contains more than the
  # per-source allowance. This keeps the public response bounded without
  # silently dropping items before advancing the upstream continuation.
  def page_window(total : Int32, position : Position, next_continuation : String?) : Window
    return Window.new(0, 0, Position.finished) if position.complete

    start = Math.min(position.offset, total)
    size = Math.min(PER_SOURCE_PAGE_SIZE, total - start)
    consumed = start + size
    next_position = if consumed < total
                      Position.new(false, position.continuation, consumed)
                    elsif continuation = normalized_continuation(next_continuation)
                      Position.new(false, continuation, 0)
                    else
                      Position.finished
                    end

    Window.new(start, size, next_position)
  end

  def merge(pages : Array(Array(Entry))) : Array(Entry)
    by_id = {} of String => Entry
    pages.each do |page|
      page.each do |entry|
        if existing = by_id[entry.id]?
          by_id[entry.id] = entry if preferred?(entry, existing)
        else
          by_id[entry.id] = entry
        end
      end
    end

    by_id.values.sort! do |left, right|
      published_order = right.published <=> left.published
      published_order == 0 ? left.id <=> right.id : published_order
    end.first(MAX_PAGE_ITEMS)
  end

  def encode(cursor : Cursor) : String
    JSON.build do |json|
      json.object do
        json.field "v", 1
        write_position(json, "u", cursor.uploads)
        write_position(json, "l", cursor.streams)
      end
    end
  end

  def decode(raw : String) : Cursor?
    return nil if raw.empty? || raw.bytesize > MAX_CURSOR_BYTES

    object = JSON.parse(raw).as_h?
    return nil unless object
    return nil unless object["v"]?.try(&.as_i?) == 1

    uploads = read_position(object["u"]?)
    streams = read_position(object["l"]?)
    return nil unless uploads && streams

    Cursor.new(uploads, streams)
  rescue JSON::ParseException
    nil
  end

  private def write_position(json : JSON::Builder, name : String, position : Position)
    json.field name do
      json.object do
        json.field "d", position.complete
        json.field "o", position.offset
        json.field "c" do
          if continuation = position.continuation
            json.string continuation
          else
            json.null
          end
        end
      end
    end
  end

  private def read_position(value : JSON::Any?) : Position?
    object = value.try(&.as_h?)
    return nil unless object

    complete = object["d"]?.try(&.as_bool?)
    raw_offset = object["o"]?.try(&.as_i?)
    return nil if complete.nil? || raw_offset.nil?
    return nil unless raw_offset >= 0 && raw_offset <= MAX_SOURCE_OFFSET

    continuation_value = object["c"]?
    continuation = continuation_value.try(&.as_s?)
    return nil if continuation && (continuation.empty? || continuation.bytesize > MAX_SOURCE_CONTINUATION_BYTES)
    return nil if complete && (continuation || raw_offset != 0)

    Position.new(complete, continuation, raw_offset.to_i32)
  end

  private def normalized_continuation(value : String?) : String?
    value unless value.nil? || value.empty?
  end

  private def preferred?(candidate : Entry, existing : Entry) : Bool
    candidate_priority = candidate.live_now ? 2 : (candidate.upcoming? ? 1 : 0)
    existing_priority = existing.live_now ? 2 : (existing.upcoming? ? 1 : 0)
    candidate_priority > existing_priority
  end
end
