class_name ChecklistCard
extends VBoxContainer
## The checklist card's contents (decision checklist-card-shows-what-the-airport-
## still-needs): a title, then one row per Checklist line still to do, each with
## an empty box, in the HUD's attention colour. A ticked line is folded away, so
## only the unmet needs show (decision checklist-card-moves-to-the-top-left-
## column-slim-at-304-px-t). StaffPanel puts this in its card in the top-left
## column and fills it on each refresh. The rows take the card's width and wrap.

const BOX := 18.0
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
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_rows.name = "ChecklistRows"
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override("separation", 4)
	add_child(_rows)


func title_label() -> Label:
	return _title


## Shows `title` over the `lines` (Checklist lines) not yet done; a done line is
## folded away. An empty title hides the title.
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
		if not entry["done"]:
			_rows.add_child(_row(entry["text"]))


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


func _row(text: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	row.add_child(Tick.new())
	var label := Label.new()
	label.name = "Text"
	label.text = text
	label.theme_type_variation = &"HudAttentionText"
	label.add_theme_font_size_override("font_size", HudLayout.CAPTION)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return row


## A tick box: an empty outline for a line still to do.
class Tick:
	extends Control

	func _init() -> void:
		name = "Tick"
		custom_minimum_size = Vector2(BOX, BOX)
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var box := Rect2(Vector2(1.0, 2.0), Vector2(BOX - 2.0, BOX - 2.0))
		draw_rect(box, BOX_COLOUR, false, 2.0)
