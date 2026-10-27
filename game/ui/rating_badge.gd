class_name RatingBadge
extends CanvasLayer
## The airport rating in the HUD (Rating 2a, decision airport-rating-1-5-stars-
## over-a-rolling-3-days-mostly-made-o): five stars in half steps with the
## number beside them, and a tooltip with the parts (made share, mood, days
## counted). It sits top-left right of the money slot (BuildMenu's MoneySlot),
## as the decision asks: stars "next to money". Until a passenger has made or
## missed a flight (AirportRating.has_data), it shows empty stars and "No
## flights yet" instead of the rating's starting value.
##
## It reads AirportRating.stars() and parts() on the rating's changed signal,
## which also fires when the day rolls over, so it never polls.

## Left edge: the money slot's 16 px margin, its 220 px width, and a gap.
const LEFT := 248.0
## The money slot's top edge.
const TOP := 12.0
const STAR_COUNT := 5
const STAR_SIZE := 24.0
const STAR_GAP := 3.0
const NO_DATA_TEXT := "No flights yet"
const NO_DATA_TIP := "No flights yet: the rating starts when passengers make or miss a flight."
## A star's colours from the Toon palette the HUD theme uses: sunny yellow
## fill, a pale card tone when empty, the theme's dark navy outline.
const STAR_FILL := Color(1.0, 0.82, 0.25)
const STAR_EMPTY := Color(0.87, 0.85, 0.81)
const STAR_OUTLINE := Color(0.1, 0.13, 0.26)

@export var rating: AirportRating

var _card := PanelContainer.new()
var _star_row := StarRow.new()
var _label := Label.new()


func _ready() -> void:
	_build()
	if rating == null:
		push_error("RatingBadge: no AirportRating is set")
		return
	watch(rating)


## Follows `with_rating` and shows it at once; a rating followed before is let
## go, and following the same one again does nothing.
func watch(with_rating: AirportRating) -> void:
	if rating != null and rating != with_rating and rating.changed.is_connected(refresh):
		rating.changed.disconnect(refresh)
	rating = with_rating
	if not rating.changed.is_connected(refresh):
		rating.changed.connect(refresh)
	refresh()


func card() -> PanelContainer:
	return _card


## The stars drawn: the rating's, or 0 while it has no data.
func shown_stars() -> float:
	return rating.stars() if rating.has_data() else 0.0


## The number beside the stars, or "No flights yet".
func summary_text() -> String:
	return "%.1f" % rating.stars() if rating.has_data() else NO_DATA_TEXT


## The card's tooltip: made share, mood and days counted over the window.
func tooltip_text() -> String:
	if not rating.has_data():
		return NO_DATA_TIP
	var parts := rating.parts()
	return (
		(
			"Airport rating: %.1f of 5\nMade it: %d%% (%d of %d passengers)\nMood: %d of %d\n"
			% [
				parts["stars"],
				roundi(parts["made_share"] * 100.0),
				parts["made"],
				parts["passengers"],
				roundi(parts["mood_avg"]),
				PassengerSim.MOOD_MAX,
			]
		)
		+ "Days counted: %d of %d" % [parts["days"], RatingFormula.WINDOW_DAYS]
	)


func refresh() -> void:
	_star_row.fills = star_fills(shown_stars())
	_star_row.queue_redraw()
	_label.text = summary_text()
	_card.tooltip_text = tooltip_text()


## How full each of the five stars is for `value` stars: 1.0, 0.5 or 0.0.
static func star_fills(value: float) -> Array[float]:
	var fills: Array[float] = []
	for i in STAR_COUNT:
		fills.append(clampf(value - i, 0.0, 1.0))
	return fills


func _build() -> void:
	_card.name = "RatingCard"
	_card.theme = BuildMenu.HUD_THEME
	_card.position = Vector2(LEFT, TOP)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(row)
	_star_row.fills = star_fills(0.0)
	_star_row.custom_minimum_size = Vector2(
		STAR_COUNT * STAR_SIZE + (STAR_COUNT - 1) * STAR_GAP, STAR_SIZE
	)
	_star_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_star_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_star_row)
	_label.name = "RatingText"
	_label.theme_type_variation = &"HudLarge"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_label)


## Draws the five stars from `fills`: an empty star under, the filled part
## clipped to its left half for a half step, the outline on top.
class StarRow:
	extends Control

	var fills: Array[float] = []

	func _draw() -> void:
		for i in fills.size():
			var shape := _star(Vector2(i * (STAR_SIZE + STAR_GAP) + STAR_SIZE / 2.0, size.y / 2.0))
			draw_colored_polygon(shape, STAR_EMPTY)
			if fills[i] >= 1.0:
				draw_colored_polygon(shape, STAR_FILL)
			elif fills[i] > 0.0:
				var half := PackedVector2Array(
					[
						Vector2(shape[0].x - STAR_SIZE, -STAR_SIZE),
						Vector2(shape[0].x, -STAR_SIZE),
						Vector2(shape[0].x, size.y + STAR_SIZE),
						Vector2(shape[0].x - STAR_SIZE, size.y + STAR_SIZE),
					]
				)
				for piece in Geometry2D.intersect_polygons(shape, half):
					draw_colored_polygon(piece, STAR_FILL)
			var outline := shape.duplicate()
			outline.append(shape[0])
			draw_polyline(outline, STAR_OUTLINE, 2.0, true)

	## A five-point star around `centre`, point up, starting at the top point.
	static func _star(centre: Vector2) -> PackedVector2Array:
		var points := PackedVector2Array()
		for k in 10:
			var radius := STAR_SIZE / 2.0 if k % 2 == 0 else STAR_SIZE / 2.0 * 0.42
			var angle := -PI / 2.0 + k * PI / 5.0
			points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
		return points
