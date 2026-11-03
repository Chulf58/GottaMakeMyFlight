class_name BubbleDeclutter
extends RefCounted
## Which passenger speech bubbles show when they overlap on screen (decision
## passenger-speech-bubbles-that-overlap-on-screen-keep-the-one). Bubbles are
## placed in order: "I'm late!" first, then by place in the queue (front
## first), then by passenger id, so a tie goes to the lower id. A bubble is
## hidden when it overlaps one already placed; a hidden bubble blocks nothing.
## PassengerViews measures the rectangles and applies the result each frame.

## The sim's text for a late passenger (PassengerSim.bubble_text).
const LATE_TEXT := "I'm late!"
## Bubbles closer than this on screen, in pixels, count as overlapping.
const MARGIN_PX := 6.0
## Rank of a passenger in no queue: behind every queued one.
const NO_QUEUE := 1 << 30

static var _text_sizes: Dictionary = {}
static var _placed: Array[Rect2] = []
static var _bins: Dictionary = {}


## 0 for the late bubble, which wins over every other text, else 1.
static func tier_of(text: String) -> int:
	return 0 if text == LATE_TEXT else 1


## Place in a queue, front first: the lane, then the holding area behind it.
static func rank_in(lane: Array[int], holding: Array[int], id: int) -> int:
	var at := lane.find(id)
	if at >= 0:
		return at
	at = holding.find(id)
	return lane.size() + at if at >= 0 else NO_QUEUE


static func rank_of(sim: PassengerSim, p: Passenger) -> int:
	if p.station == 0:
		return NO_QUEUE
	return rank_in(sim.queue_of(p.station), sim.holding_of(p.station), p.id)


static func entry(id: int, text: String, rank: int, rect: Rect2) -> Dictionary:
	return {"id": id, "tier": tier_of(text), "rank": rank, "rect": rect}


## What a bubble covers on screen: its text in the default font plus the
## outline on every side, centred on `point`, with `scale` screen pixels per
## font pixel (the label's pixel_size over its distance times the pixel unit).
static func rect_of(
	point: Vector2, text: String, font_size: int, outline: int, scale: float
) -> Rect2:
	var key := [text, font_size]
	if not _text_sizes.has(key):
		var font := ThemeDB.fallback_font
		var measured := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
		measured.y = font.get_height(font_size)
		_text_sizes[key] = measured
	var size: Vector2 = (_text_sizes[key] + Vector2.ONE * 2.0 * outline) * scale
	return Rect2(point - size / 2.0, size)


## The ids of the entries (see entry()) to hide. Sorts `entries` in place
## (placing order); the rectangles kept so far are found through RectBins, so a
## bubble is compared only with those near it. The working arrays are reused.
static func hidden(entries: Array[Dictionary]) -> Array[int]:
	entries.sort_custom(_placed_before)
	_placed.clear()
	_bins.clear()
	var out: Array[int] = []
	for e: Dictionary in entries:
		var rect: Rect2 = (e["rect"] as Rect2).grow(MARGIN_PX / 2.0)
		if RectBins.hits(rect, _bins, _placed):
			out.append(e["id"])
		else:
			_placed.append(rect)
			RectBins.file(_bins, rect, _placed.size() - 1)
	return out


static func _placed_before(a: Dictionary, b: Dictionary) -> bool:
	if a["tier"] != b["tier"]:
		return a["tier"] < b["tier"]
	if a["rank"] != b["rank"]:
		return a["rank"] < b["rank"]
	return a["id"] < b["id"]
