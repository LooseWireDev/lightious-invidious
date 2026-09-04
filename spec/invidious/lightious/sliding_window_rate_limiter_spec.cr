require "spectator"
require "../../../src/invidious/lightious/sliding_window_rate_limiter"

Spectator.describe Invidious::Lightious::SlidingWindowRateLimiter do
  let(now) { Time.utc(2026, 1, 1, 12, 0, 0) }

  it "blocks at the configured limit until the oldest retained event expires" do
    limiter = described_class.new(limit: 3, window: 60.seconds, max_keys: 10)

    limiter.record(["account"], now)
    limiter.record(["account"], now + 10.seconds)
    expect(limiter.retry_after(["account"], now + 20.seconds)).to be_nil

    limiter.record_failure(["account"], now + 20.seconds)
    expect(limiter.retry_after(["account"], now + 20.seconds)).to eq(40)
    expect(limiter.retry_after(["account"], now + 59.1.seconds)).to eq(1)
    expect(limiter.retry_after(["account"], now + 60.seconds)).to be_nil
  end

  it "uses the longest retry across unique supplied keys" do
    limiter = described_class.new(limit: 2, window: 60.seconds, max_keys: 10)

    limiter.record(["account", "account"], now)
    limiter.record(["account"], now + 5.seconds)
    limiter.record(["ip"], now + 10.seconds)
    limiter.record(["ip"], now + 15.seconds)

    expect(limiter.retry_after(["account", "ip", "ip"], now + 20.seconds)).to eq(50)
  end

  it "retains only the newest limit events for a key" do
    limiter = described_class.new(limit: 2, window: 60.seconds, max_keys: 10)

    5.times do |offset|
      limiter.record(["account"], now + offset.seconds)
    end

    expect(limiter.retry_after(["account"], now + 5.seconds)).to eq(58)
    expect(limiter.retry_after(["account"], now + 62.1.seconds)).to eq(1)
    expect(limiter.retry_after(["account"], now + 63.seconds)).to be_nil
  end

  it "orders timestamps recorded concurrently or out of order" do
    limiter = described_class.new(limit: 2, window: 60.seconds, max_keys: 10)

    limiter.record(["account"], now + 20.seconds)
    limiter.record(["account"], now)
    limiter.record(["account"], now + 10.seconds)

    expect(limiter.retry_after(["account"], now + 20.seconds)).to eq(50)
  end

  it "bounds live key storage by evicting the least recently recorded bucket" do
    limiter = described_class.new(limit: 1, window: 60.seconds, max_keys: 2)

    limiter.record(["old"], now)
    limiter.record(["recent"], now + 1.second)
    limiter.record(["old"], now + 2.seconds)
    limiter.record(["new"], now + 3.seconds)

    expect(limiter.retry_after(["recent"], now + 3.seconds)).to be_nil
    expect(limiter.retry_after(["old"], now + 3.seconds)).to eq(59)
    expect(limiter.retry_after(["new"], now + 3.seconds)).to eq(60)
  end

  it "clears only the requested key" do
    limiter = described_class.new(limit: 1, window: 60.seconds, max_keys: 10)
    limiter.record(["account", "ip"], now)

    limiter.clear("account")

    expect(limiter.retry_after(["account"], now)).to be_nil
    expect(limiter.retry_after(["ip"], now)).to eq(60)
  end

  it "ignores empty key collections and rejects unsafe bounds" do
    limiter = described_class.new(limit: 1, window: 60.seconds, max_keys: 1)
    limiter.record(["", ""], now)

    expect(limiter.retry_after([""], now)).to be_nil
    expect { described_class.new(limit: 0, window: 60.seconds, max_keys: 1) }.to raise_error(ArgumentError)
    expect { described_class.new(limit: 1, window: 0.seconds, max_keys: 1) }.to raise_error(ArgumentError)
    expect { described_class.new(limit: 1, window: 60.seconds, max_keys: 0) }.to raise_error(ArgumentError)
  end
end
