class_name ChecklistCard
extends VBoxContainer
## The checklist card's contents (decision checklist-card-shows-what-the-airport-
## still-needs): a title, then one row per Checklist line still to do, each with
## an empty box, in the HUD's attention colour. A ticked line is folded away, so
## only the unmet needs show (decision checklist-card-moves-to-the-top-left-
## column-slim-at-304-px-t). StaffPanel puts this in its card in the top-left
## column and fills it on each refresh. The rows take the card's width and wrap.

const BOX := 18.0
## Space between a row's tick box and its text.
const ROW_GAP := 8.0
const BOX_COLOUR := Color(0.6, 0.38, 0.0)
## The row text's width before the card has been laid out: the card's LIST_W less its
## padding and the tick column.
const FALLBACK_TEXT_W := 250.0
const MORE_TEXT := "+%d more"

var _title := Label.new()
var _rows := VBoxContainer.new()
## The "+N more" line under the rows a short column folded away (fit()).
var _more := Label.new()
## Bumped when the rows are rebuilt, so fit() knows its last answer is stale.
var _revision := 0
## What the last fit() worked from, and how many times it worked at all.
var _fit_key: Array = []
var _fit_runs := 0
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
	_more.name = "ChecklistMore"
	_more.theme_type_variation = &"HudAttentionText"
	_more.add_theme_font_size_override("font_size", HudLayout.CAPTION)
	_more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_more.visible = false
	add_child(_more)


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
	_revision += 1
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for entry in lines:
		if not entry["done"]:
			_rows.add_child(_row(entry["text"]))


## Shows as many of the unmet rows as fit in `room` px of card content (the title
## and the rows), top first, and folds the rest into one "+N more" line, the way
## the alert rail does (decision hud-grid-and-rails-one-spacing-grid-centred-top-
## row-right-ra). Heights come from the font, so a row that is folded away costs
## nothing to measure; every row shows again when `room` grows.
func fit(room: float) -> void:
	var text_w := FALLBACK_TEXT_W
	if _rows.size.x > 0.0:
		text_w = _rows.size.x - BOX - ROW_GAP
	# The same room, width, rows and title as the last call give the same answer.
	var key := [room, text_w, _revision, _title.visible, _title.text]
	if key == _fit_key:
		return
	_fit_key = key
	_fit_runs += 1
	var rows := _rows.get_children()
	var gap := float(get_theme_constant("separation"))
	var spent := 0.0
	if _title.visible:
		spent = _title.get_combined_minimum_size().y + gap
	var more_h := _more.get_combined_minimum_size().y + gap
	var rows_sep := float(_rows.get_theme_constant("separation"))
	var shown := 0
	for row in rows:
		var needed := spent + _row_height(row, text_w) + (rows_sep if shown > 0 else 0.0)
		var left_over := rows.size() - shown - 1
		if needed + (more_h if left_over > 0 else 0.0) > room:
			break
		spent = needed
		shown += 1
	for i in rows.size():
		(rows[i] as Control).visible = i < shown
	_more.text = MORE_TEXT % (rows.size() - shown)
	_more.visible = shown < rows.size()


## How many times fit() measured the rows rather than returning early, for tests.
func fit_runs() -> int:
	return _fit_runs


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


## The height `row` takes when its text wraps at `text_w`.
func _row_height(row: Control, text_w: float) -> float:
	var label := row.get_node("Text") as Label
	var font := label.get_theme_font("font")
	var size := HudLayout.CAPTION
	var text_h := (
		font
		. get_multiline_string_size(
			label.text,
			HORIZONTAL_ALIGNMENT_LEFT,
			text_w,
			size,
			-1,
			TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		)
		. y
	)
	var line_count := maxi(1, roundi(text_h / font.get_height(size)))
	return maxf(BOX, text_h + (line_count - 1) * label.get_theme_constant("line_spacing"))


func _row(text: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(ROW_GAP))
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
