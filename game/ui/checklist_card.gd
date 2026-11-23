class_name ChecklistCard
extends VBoxContainer
## The checklist card's contents (decision checklist-card-shows-what-the-airport-
## still-needs): a title, optional pre-open prep note, then one row per
## Checklist line still to do (with optional 1-line "why" sub-line and click
## jump), and an optional Tier-2 milestone line. A ticked line is folded away,
## so only unmet needs show (decision checklist-card-moves-to-the-top-left-
## column-slim-at-304-px-t).

signal row_activated(action: Dictionary)

const BOX := 18.0
## Space between a row's tick box and its text.
const ROW_GAP := 8.0
const WHY_GAP := 1
const BOX_COLOUR := Color(0.6, 0.38, 0.0)
const HOVER_BG := Color(0.95, 0.85, 0.55, 0.28)
## The row text's width before the card has been laid out: the card's LIST_W less its
## padding and the tick column.
const FALLBACK_TEXT_W := 250.0

var _title := Label.new()
var _prep_note := Label.new()
var _rows := VBoxContainer.new()
## The "+N more" line under the rows a short column folded away (fit()).
var _more := Label.new()
var _milestone := Label.new()
## Bumped when the rows are rebuilt, so fit() knows its last answer is stale.
var _revision := 0
## What the last fit() worked from, and how many times it worked at all.
var _fit_key: Array = []
var _fit_runs := 0
## The lines shown now, so an unchanged refresh rebuilds nothing.
var _shown: Array[Dictionary] = []
var _click_through := false


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
	_prep_note.name = "ChecklistPrepNote"
	_prep_note.theme_type_variation = &"HudHint"
	_prep_note.add_theme_font_size_override("font_size", HudLayout.FIT_STEP)
	_prep_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prep_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prep_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prep_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prep_note.visible = false
	add_child(_prep_note)
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
	_milestone.name = "ChecklistMilestone"
	_milestone.theme_type_variation = &"HudHint"
	_milestone.add_theme_font_size_override("font_size", HudLayout.FIT_STEP)
	_milestone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_milestone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_milestone.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_milestone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_milestone.visible = false
	add_child(_milestone)


func title_label() -> Label:
	return _title


func prep_note_label() -> Label:
	return _prep_note


func milestone_label() -> Label:
	return _milestone


func set_prep_note(text: String) -> void:
	if _prep_note.text == text and _prep_note.visible == (text != ""):
		return
	_prep_note.text = text
	_prep_note.visible = text != ""


func set_milestone(text: String) -> void:
	if _milestone.text == text and _milestone.visible == (text != ""):
		return
	_milestone.text = text
	_milestone.visible = text != ""


func has_visible_content() -> bool:
	return (
		_title.visible
		or _prep_note.text != ""
		or _rows.get_child_count() > 0
		or _milestone.text != ""
	)


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
			_rows.add_child(_row(entry))


## Shows as many of the unmet rows as fit in `room` px of card content (the title
## and the rows), top first, and folds the rest into one "+N more" line, the way
## the alert rail does (decision hud-grid-and-rails-one-spacing-grid-centred-top-
## row-right-ra). Heights come from the font, so a row that is folded away costs
## nothing to measure; every row shows again when `room` grows.
func fit(room: float) -> void:
	var full_w := FALLBACK_TEXT_W + BOX + ROW_GAP
	if _rows.size.x > 0.0:
		full_w = _rows.size.x
	var text_w := maxf(40.0, full_w - BOX - ROW_GAP)
	var reserve := LeftColumn.hint_reserve(get_tree() if is_inside_tree() else null)
	var avail := maxf(0.0, room - reserve)
	# The same available room, width, rows and labels as the last call give the same answer.
	var key := [
		avail,
		text_w,
		_revision,
		_title.visible,
		_title.text,
		_prep_note.text,
		_milestone.text,
	]
	if key == _fit_key:
		return
	_fit_key = key
	_fit_runs += 1
	var rows := _rows.get_children()
	var gap := float(get_theme_constant("separation"))
	var show_prep := _prep_note.text != ""
	var show_mile := _milestone.text != ""
	var title_h := (
		_label_height(_title, full_w, _title.get_theme_font_size("font_size")) + gap
		if _title.visible
		else 0.0
	)
	var prep_h := _label_height(_prep_note, full_w, HudLayout.FIT_STEP) + gap if show_prep else 0.0
	var mile_h := _label_height(_milestone, full_w, HudLayout.FIT_STEP) + gap if show_mile else 0.0
	var more_h := _more_height(full_w) + gap
	var min_row_h := (
		_row_height(rows[0], text_w) + (more_h if rows.size() > 1 else 0.0)
		if not rows.is_empty()
		else 0.0
	)
	if avail <= 0.0 or title_h + prep_h + mile_h + min_row_h > avail:
		show_mile = false
		mile_h = 0.0
	if avail <= 0.0 or title_h + prep_h + min_row_h > avail:
		show_prep = false
		prep_h = 0.0
	_prep_note.visible = show_prep
	_milestone.visible = show_mile
	var spent := title_h + prep_h + mile_h
	var rows_sep := float(_rows.get_theme_constant("separation"))
	var shown := 0
	for row in rows:
		var needed := spent + _row_height(row, text_w) + (rows_sep if shown > 0 else 0.0)
		var left_over := rows.size() - shown - 1
		if needed + (more_h if left_over > 0 else 0.0) > avail:
			break
		spent = needed
		shown += 1
	for i in rows.size():
		(rows[i] as Control).visible = i < shown
	_rows.visible = shown > 0
	_more.text = tr("+{count} more").format({"count": rows.size() - shown})
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


## The causal "why" sub-line label of each row, in order.
func why_labels() -> Array[Label]:
	var out: Array[Label] = []
	for row in _rows.get_children():
		out.append(row.get_node("Why") as Label)
	return out


## The causal "why" text of each visible sub-line on each visible row, in order.
func why_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for row in _rows.get_children():
		var control := row as Control
		if control == null or not control.visible:
			continue
		var label := row.get_node_or_null("Why") as Label
		if label != null and label.visible:
			out.append(label.text)
	return out


## Lets all rows pass mouse clicks through while the card is faded under a
## build ghost, and restores actionable rows when clear.
func set_click_through(faded: bool) -> void:
	if _click_through == faded:
		return
	_click_through = faded
	for row in _rows.get_children():
		var rc := row as RowControl
		if rc != null:
			rc.set_click_through(faded)


## Simulates clicking unmet row `index` for tests; returns false if out of range,
## click-through is active, or the row has no jump action.
func press_row(index: int) -> bool:
	if _click_through:
		return false
	var row_list := _rows.get_children()
	if index < 0 or index >= row_list.size():
		return false
	var row := row_list[index] as RowControl
	if row == null or row.action.is_empty():
		return false
	row_activated.emit(row.action)
	return true


func _more_height(width: float) -> float:
	var font := _more.get_theme_font("font")
	var sample := _more.text if _more.text != "" else "+00 more"
	var paragraph := TextParagraph.new()
	paragraph.break_flags = (
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	)
	paragraph.width = width
	paragraph.add_string(sample, font, HudLayout.CAPTION)
	var line_h := maxf(
		font.get_height(HudLayout.CAPTION),
		paragraph.get_line_size(0).y if paragraph.get_line_count() > 0 else 0.0
	)
	return ceilf(line_h)


func _label_height(label: Label, width: float, font_size: int) -> float:
	var font := label.get_theme_font("font")
	var paragraph := TextParagraph.new()
	paragraph.break_flags = (
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	)
	paragraph.width = width
	paragraph.add_string(label.text, font, font_size)
	var lines := maxi(1, paragraph.get_line_count())
	var line_spacing := float(label.get_theme_constant("line_spacing"))
	var line_h := maxf(
		font.get_height(font_size),
		paragraph.get_line_size(0).y if paragraph.get_line_count() > 0 else 0.0
	)
	return ceilf(float(lines) * line_h + float(lines - 1) * line_spacing)


## The height `row` takes when its text and optional "why" sub-line wrap at `text_w`.
func _row_height(row: Control, text_w: float) -> float:
	var label := row.get_node("Text") as Label
	var main_h := maxf(BOX, _label_height(label, text_w, HudLayout.CAPTION))
	var why := row.get_node_or_null("Why") as Label
	var calc_h := main_h
	if why != null and why.visible and why.text != "":
		var v_sep := float(row.get_theme_constant("v_separation"))
		calc_h += v_sep + _label_height(why, text_w, HudLayout.FIT_STEP)
	if row.size.x > 0.0 and is_equal_approx(row.size.x, text_w + BOX + ROW_GAP):
		return maxf(calc_h, row.get_combined_minimum_size().y)
	return calc_h


func _row(entry: Dictionary) -> Control:
	var row := RowControl.new()
	row.name = "Row"
	row.columns = 2
	row.add_theme_constant_override("h_separation", int(ROW_GAP))
	row.add_theme_constant_override("v_separation", WHY_GAP)
	var action: Dictionary = entry.get("action", {})
	row.set_action(action)
	row.set_click_through(_click_through)
	row.activated.connect(func(act: Dictionary) -> void: row_activated.emit(act))
	row.add_child(Tick.new())
	var label := Label.new()
	label.name = "Text"
	label.text = str(entry.get("text", ""))
	label.theme_type_variation = &"HudAttentionText"
	label.add_theme_font_size_override("font_size", HudLayout.CAPTION)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	var why_text := str(entry.get("why", ""))
	var why_pad := Control.new()
	why_pad.name = "WhyPad"
	why_pad.custom_minimum_size = Vector2(BOX, 0.0)
	why_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	why_pad.visible = why_text != ""
	row.add_child(why_pad)
	var why := Label.new()
	why.name = "Why"
	why.text = why_text
	why.theme_type_variation = &"HudHint"
	why.add_theme_font_size_override("font_size", HudLayout.FIT_STEP)
	why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	why.mouse_filter = Control.MOUSE_FILTER_IGNORE
	why.visible = why_text != ""
	row.add_child(why)
	return row


## A checklist row that highlights on hover and emits `activated` on left click
## when an action is attached; non-actionable rows let clicks pass through.
class RowControl:
	extends GridContainer

	signal activated(action: Dictionary)

	var action: Dictionary = {}
	var _hovered := false
	var _click_through := false

	func set_action(with_action: Dictionary) -> void:
		action = with_action.duplicate(true)
		_sync_mouse_state()

	func set_click_through(faded: bool) -> void:
		if _click_through == faded:
			return
		_click_through = faded
		if faded and _hovered:
			_hovered = false
			queue_redraw()
		_sync_mouse_state()

	func _sync_mouse_state() -> void:
		var clickable := not _click_through and not action.is_empty()
		mouse_filter = Control.MOUSE_FILTER_STOP if clickable else Control.MOUSE_FILTER_IGNORE
		mouse_default_cursor_shape = (
			Control.CURSOR_POINTING_HAND if clickable else Control.CURSOR_ARROW
		)

	func _gui_input(event: InputEvent) -> void:
		if _click_through or action.is_empty():
			return
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			activated.emit(action)
			accept_event()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER:
			_hovered = true
			queue_redraw()
		elif what == NOTIFICATION_MOUSE_EXIT:
			_hovered = false
			queue_redraw()

	func _draw() -> void:
		if _hovered and not _click_through and not action.is_empty():
			draw_rect(Rect2(Vector2.ZERO, size), HOVER_BG)


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
