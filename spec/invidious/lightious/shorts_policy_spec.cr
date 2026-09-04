require "../../parsers_helper"
require "../../../src/invidious/lightious/shorts_policy"

Spectator.describe Invidious::Lightious::ShortsPolicy do
  it "marks Shorts renderer identities without using duration as a shortcut" do
    short_renderer = JSON.parse(%({
      "videoRenderer": {
        "videoId": "AAAAAAAAAAA",
        "title": {"runs": [{"text": "Short"}]},
        "lengthText": {"simpleText": "0:42"},
        "navigationEndpoint": {
          "commandMetadata": {"webCommandMetadata": {"url": "/shorts/AAAAAAAAAAA"}}
        }
      }
    }))
    regular_renderer = JSON.parse(%({
      "videoRenderer": {
        "videoId": "BBBBBBBBBBB",
        "title": {"runs": [{"text": "Brief landscape video"}]},
        "lengthText": {"simpleText": "0:42"},
        "navigationEndpoint": {
          "commandMetadata": {"webCommandMetadata": {"url": "/watch?v=BBBBBBBBBBB"}}
        }
      }
    }))

    short = parse_item(short_renderer).as(SearchVideo)
    regular = parse_item(regular_renderer).as(SearchVideo)

    expect(described_class.short?(short)).to be_true
    expect(described_class.short?(regular)).to be_false
    expect(described_class.reject_from([short, regular] of SearchItem)).to eq([regular] of SearchItem)
  end

  it "marks the dedicated Shorts lockup renderer" do
    renderer = JSON.parse(%({
      "richItemRenderer": {
        "content": {
          "shortsLockupViewModel": {
            "onTap": {"innertubeCommand": {"reelWatchEndpoint": {"videoId": "CCCCCCCCCCC"}}},
            "overlayMetadata": {
              "primaryText": {"content": "Dedicated Short"},
              "secondaryText": {"content": "1K views"}
            }
          }
        }
      }
    }))

    video = parse_item(renderer, "Channel", "UC_x5XG1OV2P6uZZ5FSM9Ttw").as(SearchVideo)
    expect(described_class.short?(video)).to be_true
  end

  it "recognizes only square or portrait dimensions" do
    expect(described_class.short_dimensions?(720_i64, 1280_i64)).to be_true
    expect(described_class.short_dimensions?(1080_i64, 1080_i64)).to be_true
    expect(described_class.short_dimensions?(1280_i64, 720_i64)).to be_false
    expect(described_class.short_dimensions?(nil, 720_i64)).to be_false
    expect(described_class.short_dimensions?(0_i64, 0_i64)).to be_false
  end
end
