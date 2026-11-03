class_name RectBins
extends RefCounted
## A broad phase for screen rectangles: each rectangle is filed under every
## BIN_PX cell it covers, so a rectangle is compared only with the ones that
## share a cell. `bins` is a Dictionary of Vector2i cell -> Array of indexes
## into the caller's Array[Rect2]. Shared by the station captions
## (MissMarkers) and the passenger speech bubbles (BubbleDeclutter).

## Side of a broad-phase cell, in pixels.
const BIN_PX := 160.0


## True when `rect` touches a rectangle in `rects`, found through `bins`.
static func hits(rect: Rect2, bins: Dictionary, rects: Array[Rect2]) -> bool:
	for cell in cells(rect):
		if bins.has(cell):
			for at: int in bins[cell]:
				if rect.intersects(rects[at]):
					return true
	return false


## Files rectangle number `at` under every broad-phase cell it covers.
static func file(bins: Dictionary, rect: Rect2, at: int) -> void:
	for cell in cells(rect):
		if not bins.has(cell):
			bins[cell] = []
		(bins[cell] as Array).append(at)


## The broad-phase cells a rectangle covers.
static func cells(rect: Rect2) -> Array[Vector2i]:
	var low := Vector2i((rect.position / BIN_PX).floor())
	var high := Vector2i((rect.end / BIN_PX).floor())
	var out: Array[Vector2i] = []
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			out.append(Vector2i(x, y))
	return out
