class_name ChecklistCard
extends VBoxContainer
## The checklist card's contents (decision checklist-card-shows-what-the-airport-
## still-needs): a title, then one row per Checklist line, each with a tick box
## that is ticked when the line is done. A done line is dimmed; a line still to
## do is in the HUD's attention colour, as the status banner was. StaffPanel
## puts this in its banner card at the top centre (decision status-banner-and-
## first-time-hints-sit-at-the-top-centre) and fills it on each refresh.
## The Nunito HUD font has no check mark glyph, so the tick is drawn.

## Width of a row's text, in layout pixels.
const TEXT_W := 520.0
const BOX := 18.0
## Opacity of a done row.
const DONE_ALPHA := 0.55
const TICK_COLOUR := Color(0.12, 0.55, 0.5)
const BOX_COLOUR := Color(0.6, 0.38, 0.0)

var _title := Label.new()
var _rows := VBoxContainer.new()
## The lines shown now, so an unchanged refresh rebuilds nothing.
var _shown: Array[Dictionary] = []


func _init() -> void:
	name = "Checklist"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	_title.name = "ChecklistTitle"
	_title.theme_type_variation = &"HudCardName"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.custom_minimum_size = Vector2(TEXT_W + BOX + 8.0, 0.0)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_rows.name = "ChecklistRows"
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override("separation", 4)
	add_child(_rows)


func title_label() -> Label:
	return _title


## Shows `title` over `lines` (Checklist lines). An empty title hides the title.
func show_lines(title: String, lines: Array[Dictionary]) -> void:
	_title.text = title
	_title.visible = title != ""
	if lines == _shown:
		return
	_shown = lines.duplicate(true)
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for entry in lines:
		_rows.add_child(_row(entry["text"], entry["done"]))


func lines() -> Array[Dictionary]:
	return _shown


## The rows' controls, in order, for probes and tests.
func rows() -> Array[Node]:
	return _rows.get_children()


## The text label of each row, in order: what the card shows on screen.
func row_labels() -> Array[Label]:
	var out: Array[Label] = []
	for row in _rows.get_children():
		out.append(row.get_node("Text") as Label)
	return out


## The text of each row, in order.
func row_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for label in row_labels():
		out.append(label.text)
	return out


func _row(text: String, done: bool) -> Control:
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	var tick := Tick.new()
	tick.done = done
	row.add_child(tick)
	var label := Label.new()
	label.name = "Text"
	label.text = text
	label.theme_type_variation = &"HudSmall" if done else &"HudAttentionText"
	label.custom_minimum_size = Vector2(TEXT_W, 0.0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	if done:
		row.modulate.a = DONE_ALPHA
	return row


## A tick box: an outline, filled with a check mark when done.
class Tick:
	extends Control

	var done := false

	func _init() -> void:
		name = "Tick"
		custom_minimum_size = Vector2(BOX, BOX)
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var box := Rect2(Vector2(1.0, 2.0), Vector2(BOX - 2.0, BOX - 2.0))
		if done:
			draw_rect(box, TICK_COLOUR)
			var points := PackedVector2Array(
				[Vector2(4.5, 10.5), Vector2(8.0, 14.0), Vector2(14.0, 6.0)]
			)
			draw_polyline(points, Color.WHITE, 2.5, true)
		else:
			draw_rect(box, BOX_COLOUR, false, 2.0)
