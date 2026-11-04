class_name RectBins
extends RefCounted
## A broad phase for screen rectangles: each rectangle is filed under every
## BIN_PX cell it covers, so a rectangle is compared only with the ones that
## share a cell. `bins` is a Dictionary of Vector2i cell -> Array of indexes
## into the caller's Array[Rect2]. Shared by the station captions
## (MissMarkers) and the passenger speech bubbles (BubbleDeclutter).
##
## A wide rectangle (is_wide()) is filed once under WIDE and compared with
## every rectangle instead, so the work stays bounded at any size. A speech
## bubble just in front of the camera plane is measured at pixel_size / depth,
## millions of pixels wide; filing it under each cell it covered froze the game
## at 22.8 GB (board "The game now froze", playtest 2026-11-03).

## Side of a broad-phase cell, in pixels.
const BIN_PX := 160.0
## A rectangle covering more cells than this is wide.
const MAX_CELLS := 64
## The `bins` key of the wide rectangles' indexes.
const WIDE := &"wide"
## Cell coordinates past this are wide, well inside Vector2i's range.
const MAX_CELL_COORD := 1 << 30


## True when `rect` touches a rectangle in `rects`, found through `bins`.
static func hits(rect: Rect2, bins: Dictionary, rects: Array[Rect2]) -> bool:
	if is_wide(rect):
		for other in rects:
			if rect.intersects(other):
				return true
		return false
	for cell in cells(rect):
		if bins.has(cell):
			for at: int in bins[cell]:
				if rect.intersects(rects[at]):
					return true
	if bins.has(WIDE):
		for at: int in bins[WIDE]:
			if rect.intersects(rects[at]):
				return true
	return false


## Files rectangle number `at` under every broad-phase cell it covers, or once
## under WIDE when it is wide.
static func file(bins: Dictionary, rect: Rect2, at: int) -> void:
	var keys: Array = [WIDE] if is_wide(rect) else cells(rect)
	for key: Variant in keys:
		if not bins.has(key):
			bins[key] = []
		(bins[key] as Array).append(at)


## True when `rect` covers more than MAX_CELLS cells, is not finite or lies
## past MAX_CELL_COORD cells from the origin.
static func is_wide(rect: Rect2) -> bool:
	if not rect.is_finite():
		return true
	var low := (rect.position / BIN_PX).floor()
	var high := (rect.end / BIN_PX).floor()
	if maxf(maxf(absf(low.x), absf(low.y)), maxf(absf(high.x), absf(high.y))) > MAX_CELL_COORD:
		return true
	var span := high - low + Vector2.ONE
	return span.x > 0.0 and span.y > 0.0 and span.x * span.y > MAX_CELLS


## The broad-phase cells a rectangle covers, or none for a wide one.
static func cells(rect: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if is_wide(rect):
		return out
	var low := Vector2i((rect.position / BIN_PX).floor())
	var high := Vector2i((rect.end / BIN_PX).floor())
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			out.append(Vector2i(x, y))
	return out
