module Invidious::Lightious
  # A small, process-local sliding-window limiter for opaque caller-supplied
  # keys. Callers are responsible for deriving keys that do not retain raw
  # user identifiers or addresses.
  class SlidingWindowRateLimiter
    private class Bucket
      getter events : Array(Time)
      property last_recorded : UInt64

      def initialize(@last_recorded : UInt64)
        @events = [] of Time
      end
    end

    getter limit : Int32
    getter window : Time::Span
    getter max_keys : Int32

    @buckets = {} of String => Bucket
    @mutex = Mutex.new
    @record_sequence = 0_u64

    def initialize(@limit : Int32, @window : Time::Span, @max_keys : Int32)
      raise ArgumentError.new("limit must be positive") unless @limit > 0
      raise ArgumentError.new("window must be positive") unless @window > Time::Span.zero
      raise ArgumentError.new("max_keys must be positive") unless @max_keys > 0
    end

    # Returns the maximum number of whole seconds before all supplied keys are
    # below the limit, or nil when an attempt is currently allowed.
    def retry_after(keys : Enumerable(String), now : Time = Time.utc) : Int32?
      normalized_keys = normalize_keys(keys)
      return nil if normalized_keys.empty?

      @mutex.synchronize do
        longest_retry : Int32? = nil

        normalized_keys.each do |key|
          bucket = @buckets[key]?
          next unless bucket

          prune_bucket(bucket, now)
          if bucket.events.empty?
            @buckets.delete(key)
            next
          end
          next if bucket.events.size < @limit

          # If a caller records while already limited, enough of the newest
          # retained events must expire to bring the count below the limit.
          blocking_event = bucket.events[bucket.events.size - @limit]
          remaining = blocking_event + @window - now
          seconds = remaining.total_seconds.ceil.clamp(1.0, Int32::MAX.to_f64).to_i32
          longest_retry = seconds if longest_retry.nil? || seconds > longest_retry.not_nil!
        end

        longest_retry
      end
    end

    # Records one event for each unique, non-empty key. Storage is bounded by
    # max_keys * limit; when the key capacity is full, the least recently
    # recorded live bucket is evicted after expired buckets are removed.
    def record(keys : Enumerable(String), now : Time = Time.utc) : Nil
      normalized_keys = normalize_keys(keys)
      return if normalized_keys.empty?

      @mutex.synchronize do
        prune_expired_buckets(now)

        normalized_keys.each do |key|
          bucket = @buckets[key]?
          unless bucket
            evict_oldest_bucket if @buckets.size >= @max_keys
            bucket = Bucket.new(0_u64)
            @buckets[key] = bucket
          end

          prune_bucket(bucket, now)
          bucket.events << now
          bucket.events.sort!
          while bucket.events.size > @limit
            bucket.events.shift
          end
          bucket.last_recorded = next_record_sequence
        end
      end
    end

    # Login callers can use the more descriptive name without making the
    # limiter itself specific to authentication failures.
    def record_failure(keys : Enumerable(String), now : Time = Time.utc) : Nil
      record(keys, now)
    end

    def clear(key : String) : Nil
      return if key.empty?

      @mutex.synchronize { @buckets.delete(key) }
    end

    private def normalize_keys(keys : Enumerable(String)) : Array(String)
      normalized = [] of String
      keys.each do |key|
        next if key.empty? || normalized.includes?(key)
        normalized << key
      end
      normalized
    end

    private def prune_bucket(bucket : Bucket, now : Time) : Nil
      cutoff = now - @window
      bucket.events.reject! { |recorded_at| recorded_at <= cutoff }
    end

    private def prune_expired_buckets(now : Time) : Nil
      expired_keys = [] of String
      @buckets.each do |key, bucket|
        prune_bucket(bucket, now)
        expired_keys << key if bucket.events.empty?
      end
      expired_keys.each { |key| @buckets.delete(key) }
    end

    private def evict_oldest_bucket : Nil
      oldest_key : String? = nil
      oldest_sequence = UInt64::MAX

      @buckets.each do |key, bucket|
        if bucket.last_recorded < oldest_sequence
          oldest_key = key
          oldest_sequence = bucket.last_recorded
        end
      end

      @buckets.delete(oldest_key.not_nil!) if oldest_key
    end

    private def next_record_sequence : UInt64
      @record_sequence &+= 1_u64
    end
  end
end
