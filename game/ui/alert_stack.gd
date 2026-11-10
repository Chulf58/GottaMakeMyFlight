class_name AlertStack
extends VBoxContainer
## The right rail (HUD 3/7, decision hud-grid-and-rails-one-spacing-grid-
## centred-top-row-right-ra, parts 3 and 5): under the clock panel (`above`),
## GROUP_GAP down and RAIL_W wide on the right margin, an Alerts header row,
## then the rail's cards, newest first. At most MAX_CARDS are drawn, and fewer
## when they would run into the build tray; a '+N more' button counts the
## rest and opens the history tray.
##
## Two kinds of card share the rail. Alert cards (HUD 1/7, decision hud-steal-
## list-self-clearing-alert-cards-money-hover-departu) are one per problem that
## is true right now, each clearing itself when its cause is solved
## (AlertBoard). The causes are a full check-in or security queue, passengers
## with no walkable route, passengers waiting for a gate place (AlertSources)
## and a dirty terminal (DirtyAlert). Clicking one glides the camera to the
## problem; the next click goes to the next place with the same problem.
## Notices are cards another part of the HUD posts (post_notice()): the flight
## result card now, the Offers notices later. A notice leaves after its
## seconds of real time (counted every rendered frame, also while the game is
## paused, and at any game speed), on a click, or when its poster drops it, and
## its words stay in the history.
##
## The camera puts its focus in the middle of the screen share the open panels
## leave free (PanelRoom, decision panel-room-as-built-camera-frames-the-
## terminal-in-the-screen), and the rail's drawn cards and open tray count as
## such a panel (room_rect()), so a jump lands beside the rail, not under it.
## They are not one of PanelRoom's open-or-closed panels: a card coming or
## going shifts the view a little and never zooms it.
##
## The "Alerts" button opens the history tray in the cards' place: every card
## that came up and every notice, newest first, and the on/off switch for the
## alert cards (decision optional-hud-pieces-keep-their-on-off-setting-in-user-
## hud-se, key SETTING_KEY, on by default). Off hides the alert cards but not
## the notices; the history still fills. Alerts are never saved: a load or a
## new world starts the rail again (reset()).
##
## The airport-closed banner (StaffPanel's hint card) is not on the rail: it
## guides the opening rather than reporting a problem that comes and goes, and
## sits in its own place away from the right edge.

## A card was clicked and the camera sent to `target`.
signal jumped(target: Vector3)

const SETTING_KEY := "alert_cards"
## The distance a jump zooms in to; a camera already closer keeps its distance.
const JUMP_DISTANCE := 30.0
## The most history lines the tray shows; AlertBoard keeps HISTORY_CAP.
const TRAY_LINES := 12
## The most cards the rail draws; the rest count into '+N more'.
const MAX_CARDS := 4
## A card's rail key and its arrival number (newest is highest), kept on the card.
const META_KEY := &"rail_key"
const META_SEQ := &"rail_seq"

## The passenger sim the causes are read from. A different sim is a different
## world, so the stack starts again.
var sim: PassengerSim:
	set(value):
		sim = value
		_dirty.sim = value
		reset()
## The camera a click sends; without one a click only emits `jumped`.
var camera: TycoonCamera
## The clock panel the rail hangs under; without one the rail starts on the
## top margin.
var above: Control
## Where the on/off choice is kept; tests use their own file.
var settings_path := HudFlagSetting.PATH
## How many times the passengers were scanned for the no-route cause. It is read
## once per sim tick and kept (refresh() runs every rendered frame, also while
## paused); tests count it. The queue-full cause is read on every refresh: it
## is cheap, and a paused build session changes it without a tick.
var scans := 0
## True while something covers the stack's place (the open offer sheet); the
## stack stays down then and comes back when it is false.
var covered := Callable()
## True while the build item tray is open; the rail then stops above the tray
## stack instead of the category bar. PassengerHud sets it from BuildMenu.
var build_tray_open := Callable()

var _board := AlertBoard.new()
var _dirty := DirtyAlert.new()
var _cards_on := true
var _header := HBoxContainer.new()
var _cards := VBoxContainer.new()
var _more := Button.new()
var _tray := PanelContainer.new()
var _tray_scroll := ScrollContainer.new()
var _tray_lines := VBoxContainer.new()
var _tray_button := Button.new()
var _toggle := CheckButton.new()
var _shown_revision := -1
## The no-route cause read at _scanned_tick; -1 means none kept.
var _route_causes: Array[Dictionary] = []
var _gate_causes: Array[Dictionary] = []
var _scanned_tick := -1
## Key -> how many clicks its card has had, to step through its targets.
var _clicks: Dictionary = {}
## Key -> {card, left}: each notice up and the real seconds it has left (INF
## for one that stays until clicked).
var _notices: Dictionary = {}
var _next_seq := 0
var _hidden := 0


func _ready() -> void:
	name = "AlertStack"
	theme = BuildMenu.HUD_THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	offset_right = -HudLayout.MARGIN
	offset_left = -HudLayout.MARGIN - HudLayout.RAIL_W
	offset_top = HudLayout.MARGIN
	grow_vertical = Control.GROW_DIRECTION_END
	_cards_on = HudFlagSetting.load_flag(settings_path, SETTING_KEY, true, "AlertStack")
	_build()


func _process(delta: float) -> void:
	advance(delta)


## The DirtyAlert cause, for tests and probes.
func dirty_source() -> DirtyAlert:
	return _dirty


## The rule holding the cards and the history, for tests and probes.
func board() -> AlertBoard:
	return _board


## Drops every card, notice and the history, as for a new world.
func reset() -> void:
	_dirty.reset()
	_board.reset()
	_clicks.clear()
	for key: StringName in _notices.keys():
		drop_notice(key)
	_scanned_tick = -1
	_shown_revision = _board.revision
	_sync_cards()
	_sync_tray()


## Reads every cause, updates the cards and the tray. Does nothing without a sim.
func refresh() -> void:
	if sim == null:
		return
	_dirty.refresh()
	if sim.tick != _scanned_tick:
		_scanned_tick = sim.tick
		scans += 1
		_route_causes = AlertSources.no_route(sim)
		_gate_causes = AlertSources.gate_full(sim)
	var causes: Array[Dictionary] = []
	causes.append_array(AlertSources.queue_full(sim))
	causes.append_array(_route_causes)
	causes.append_array(_gate_causes)
	causes.append_array(_dirty.cause())
	_board.update(causes, sim.tick)
	if _board.revision != _shown_revision:
		_shown_revision = _board.revision
		_sync_cards()
		_sync_tray()
	visible = not (covered.is_valid() and covered.call())
	_place()
	_layout_cards()


## Puts `card` on the rail under `key`, newest first, replacing a notice up
## under the same key. The rail owns the card from here and frees it when it
## leaves: after `seconds` of real time (0 keeps it until clicked), on a left
## click, or on drop_notice(). `title` and `detail` go in the history now.
func post_notice(
	key: StringName, card: Control, seconds: float, title: String, detail: String
) -> void:
	drop_notice(key)
	card.set_meta(META_KEY, key)
	card.set_meta(META_SEQ, _take_seq())
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_notice_input.bind(key))
	# Hidden until _layout_cards() has measured it and found it fits.
	card.visible = false
	_cards.add_child(card)
	_notices[key] = {"card": card, "left": seconds if seconds > 0.0 else INF}
	_board.note(key, title, detail, sim.tick if sim != null else 0)
	_sync_tray()
	_layout_cards()


## Takes the notice under `key` off the rail; its history line stays.
func drop_notice(key: StringName) -> void:
	if not _notices.has(key):
		return
	var card: Control = _notices[key]["card"]
	_notices.erase(key)
	# Hidden and freed at the end of the frame: this may run inside the card's
	# own input callback.
	card.visible = false
	card.queue_free()
	_layout_cards()


## The card of the notice up under `key`, or null when none is up.
func notice_card(key: StringName) -> Control:
	return _notices[key]["card"] if _notices.has(key) else null


## Counts `seconds` of real time off every timed notice and takes down those
## whose time is up. _process calls it each frame; tests call it by hand.
func advance(seconds: float) -> void:
	for key: StringName in _notices.keys():
		var notice: Dictionary = _notices[key]
		notice["left"] -= seconds
		if notice["left"] <= 0.0:
			drop_notice(key)


## The rail keys of the cards drawn now, top to bottom (an alert card's cause
## key, a notice's key).
func shown_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for card in _live_cards():
		if card.visible:
			keys.append(card.get_meta(META_KEY))
	return keys


## How many cards are on the rail but not drawn, as '+N more' shows.
func more_count() -> int:
	return _hidden


## The screen rectangle of the drawn cards, '+N more' and the open history
## tray, which the camera keeps its focus clear of (PanelRoom); empty while
## none is drawn. The header row is left out: it is always there and small.
func room_rect() -> Rect2:
	var rect := Rect2()
	if not is_visible_in_tree():
		return rect
	var parts: Array[Control] = [_tray, _more]
	parts.append_array(_live_cards())
	for part in parts:
		if part.is_visible_in_tree():
			var r := part.get_global_rect()
			rect = r if not rect.has_area() else rect.merge(r)
	return rect


## The keys of the alert cards up, in the order they came up (also while the
## cards are switched off).
func card_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for alert in _board.active():
		keys.append(alert["key"])
	return keys


## The drawn card for `key`, or null.
func card_node(key: StringName) -> Control:
	return _cards.get_node_or_null(NodePath(_card_name(key))) as Control


## The card's title and detail as drawn, one per line; "" without a card.
func card_text(key: StringName) -> String:
	var card := card_node(key)
	if card == null:
		return ""
	var title := card.find_child("Title", true, false) as Label
	var detail := card.find_child("Detail", true, false) as Label
	return "%s\n%s" % [title.text, detail.text]


## A click on the card for `key`: glides the camera to its next target and
## emits `jumped`. False when no card is up for it or it has no place.
func press_card(key: StringName) -> bool:
	var alert := _board.alert(key)
	if alert.is_empty() or (alert["targets"] as Array).is_empty():
		return false
	var targets: Array = alert["targets"]
	var clicks: int = _clicks.get(key, 0)
	_clicks[key] = clicks + 1
	var target: Vector3 = targets[clicks % targets.size()]
	if camera != null:
		camera.glide_to(target, minf(camera.distance, JUMP_DISTANCE))
	jumped.emit(target)
	return true


func cards_on() -> bool:
	return _cards_on


## Shows or hides the alert cards and saves the choice. The history fills
## either way, and notices show either way.
func set_cards_on(value: bool) -> void:
	_cards_on = value
	_toggle.set_pressed_no_signal(value)
	HudFlagSetting.save_flag(settings_path, SETTING_KEY, value, "AlertStack")
	_layout_cards()


func is_tray_open() -> bool:
	return _tray.visible


## Opens or closes the history tray, which takes the cards' place while open.
func set_tray_open(value: bool) -> void:
	_tray.visible = value
	_tray_button.set_pressed_no_signal(value)
	_layout_cards()


## The history as the tray words it, newest first: when the card came up, its
## title and when it cleared ("still up" while it is); a notice's title and
## its words.
func history_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for entry in _board.history():
		var raised: int = entry["raised_tick"]
		var cleared: int = entry["cleared_tick"]
		var when := "Day %d %s" % [GameCalendar.day_of(raised) + 1, GameCalendar.clock_text(raised)]
		if entry.get("notice", false):
			lines.append("%s  %s\n%s" % [when, entry["title"], entry["detail"]])
			continue
		var end := "still up" if cleared < 0 else "cleared %s" % GameCalendar.clock_text(cleared)
		lines.append("%s  %s, %s" % [when, entry["title"], end])
	return lines


func _build() -> void:
	var header := _header
	header.name = "AlertsHeader"
	header.alignment = BoxContainer.ALIGNMENT_END
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.custom_minimum_size = Vector2(0.0, HudLayout.BUTTON_H)
	add_child(header)
	_tray_button.name = "AlertHistoryButton"
	_tray_button.text = "Alerts"
	_tray_button.toggle_mode = true
	_tray_button.focus_mode = Control.FOCUS_NONE
	_tray_button.tooltip_text = "Alert history and the on/off switch for alert cards"
	_tray_button.toggled.connect(set_tray_open)
	header.add_child(_tray_button)
	_cards.name = "AlertCards"
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cards)
	_more.name = "AlertsMore"
	_more.visible = false
	_more.focus_mode = Control.FOCUS_NONE
	_more.size_flags_horizontal = Control.SIZE_SHRINK_END
	_more.custom_minimum_size = Vector2(0.0, HudLayout.BUTTON_H)
	_more.tooltip_text = "Open the alert history"
	_more.pressed.connect(set_tray_open.bind(true))
	add_child(_more)
	_tray.name = "AlertHistory"
	_tray.visible = false
	add_child(_tray)
	var column := VBoxContainer.new()
	_tray.add_child(column)
	var title := Label.new()
	title.text = "Alert history"
	title.theme_type_variation = &"HudCardName"
	column.add_child(title)
	_toggle.name = "AlertCardsToggle"
	_toggle.text = "Show alert cards"
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.set_pressed_no_signal(_cards_on)
	_toggle.toggled.connect(set_cards_on)
	column.add_child(_toggle)
	_tray_scroll.name = "AlertHistoryScroll"
	_tray_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_tray_scroll)
	_tray_lines.name = "AlertHistoryLines"
	_tray_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tray_scroll.add_child(_tray_lines)
	_sync_tray()


## Makes the drawn alert cards match the board's: new ones added, gone ones
## removed at once, words updated. Notices are left alone.
func _sync_cards() -> void:
	var keep := {}
	for alert in _board.active():
		var key: StringName = alert["key"]
		keep[_card_name(key)] = true
		var card := card_node(key)
		if card == null:
			card = _new_card(key)
			_cards.add_child(card)
		(card.find_child("Title", true, false) as Label).text = alert["title"]
		(card.find_child("Detail", true, false) as Label).text = alert["detail"]
	for child in _cards.get_children():
		if not keep.has(String(child.name)) and not _notices.has(child.get_meta(META_KEY)):
			_cards.remove_child(child)
			child.queue_free()
	for key: StringName in _clicks.keys():
		if _board.alert(key).is_empty():
			_clicks.erase(key)
	var count := _board.active().size()
	_tray_button.text = "Alerts" if count == 0 else "Alerts (%d)" % count
	_layout_cards()


func _new_card(key: StringName) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = _card_name(key)
	card.visible = false
	card.set_meta(META_KEY, key)
	card.set_meta(META_SEQ, _take_seq())
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = "Click to look at it"
	card.gui_input.connect(_on_card_input.bind(key))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)
	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"HudProblemText"
	var detail := Label.new()
	detail.name = "Detail"
	detail.theme_type_variation = &"HudSmall"
	for label in [title, detail]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(label)
	return card


func _sync_tray() -> void:
	for child in _tray_lines.get_children():
		_tray_lines.remove_child(child)
		child.queue_free()
	var lines := history_lines()
	if lines.is_empty():
		lines.append("No alerts yet")
	for line in lines.slice(0, TRAY_LINES):
		var label := Label.new()
		label.text = line
		label.theme_type_variation = &"HudHint"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tray_lines.add_child(label)


func _on_card_input(event: InputEvent, key: StringName) -> void:
	if _is_left_press(event):
		press_card(key)


func _on_notice_input(event: InputEvent, key: StringName) -> void:
	if _is_left_press(event):
		drop_notice(key)


static func _is_left_press(event: InputEvent) -> bool:
	var click := event as InputEventMouseButton
	return click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT


static func _card_name(key: StringName) -> String:
	return "AlertCard_%s" % key


## A card's height at the rail's width, drawn or not. A hidden card is never
## laid out, and a wrapped label measures at its own current width, so each
## control down the card is given its width first (a panel's children lose its
## style's margins; a column's children fill it) and its minimum size taken
## afresh. A row (HBoxContainer) that splits its width is not modelled: keep
## wrapped text in columns.
static func _card_height(card: Control) -> float:
	_widen(card, HudLayout.RAIL_W)
	return card.get_combined_minimum_size().y


static func _widen(control: Control, width: float) -> void:
	control.size.x = width
	var inner := width
	var panel := control as PanelContainer
	if panel != null:
		inner -= panel.get_theme_stylebox("panel").get_minimum_size().x
	for child in control.get_children():
		var part := child as Control
		# Only what fills the width gets it, as the container gives it; a part
		# that shrinks (the Dismiss button) keeps the width it was laid out at.
		if part != null and not part.top_level and part.size_flags_horizontal & Control.SIZE_FILL:
			_widen(part, inner)
	control.update_minimum_size()


static func _newer(a: Control, b: Control) -> bool:
	return int(a.get_meta(META_SEQ)) > int(b.get_meta(META_SEQ))


func _take_seq() -> int:
	_next_seq += 1
	return _next_seq


## The rail's cards still up, alert cards and notices.
func _live_cards() -> Array[Control]:
	var cards: Array[Control] = []
	for child: Control in _cards.get_children():
		if not child.is_queued_for_deletion():
			cards.append(child)
	return cards


## Hangs the rail GROUP_GAP under the clock panel's laid-out bottom, so a
## panel that grows with the day's flights pushes it down.
func _place() -> void:
	var top := float(HudLayout.MARGIN)
	if above != null and above.is_visible_in_tree():
		top = above.get_global_rect().end.y + HudLayout.GROUP_GAP
	if not is_equal_approx(top, offset_top):
		offset_top = top


## The lowest screen y the rail may reach: GROUP_GAP above the category bar, or
## above the build tray's whole stack while the tray is open, so opening it
## sends the cards that would run into it to '+N more'.
func _stop_y() -> float:
	var view := get_viewport().get_visible_rect().size.y
	var below := BuildMenu.MARGIN + BuildMenu.BAR_H
	if build_tray_open.is_valid() and build_tray_open.call():
		below = BuildMenu.tray_stack_top()
	return view - below - HudLayout.GROUP_GAP


## Orders the cards newest first and draws as many as fit: at most MAX_CARDS,
## and only while the next one ends above _stop_y() with room left for '+N
## more' (the newest is always drawn). Each card is measured at the rail's
## width before it is shown (_card_height()), so a card that does not fit is
## never drawn, not even for a frame. None are drawn while the history tray is
## open in their place.
func _layout_cards() -> void:
	if not is_inside_tree():
		return
	var cards := _live_cards()
	cards.sort_custom(_newer)
	for i in cards.size():
		_cards.move_child(cards[i], i)
	var drawable: Array[Control] = []
	for card in cards:
		if _notices.has(card.get_meta(META_KEY)) or _cards_on:
			drawable.append(card)
		else:
			card.visible = false
	var tray_open := _tray.visible
	# The cards' top from the rail's own top, not from the column's laid-out
	# position, which lags a frame behind a move.
	var sep := float(get_theme_constant("separation"))
	var top := global_position.y + _header.get_combined_minimum_size().y + sep
	var room := _stop_y() - top
	sep = float(_cards.get_theme_constant("separation"))
	var heights: Array[float] = []
	var used := 0.0
	for card in drawable:
		var fits := not tray_open and heights.size() < MAX_CARDS
		var height := _card_height(card)
		fits = fits and (heights.is_empty() or used + height <= room)
		if not fits:
			break
		heights.append(height + sep)
		used += height + sep
	while (
		heights.size() > 1 and heights.size() < drawable.size() and used + HudLayout.BUTTON_H > room
	):
		used -= heights.pop_back()
	for i in drawable.size():
		drawable[i].visible = i < heights.size()
	_hidden = 0 if tray_open else drawable.size() - heights.size()
	_more.text = "+%d more" % _hidden
	_more.visible = _hidden > 0
	if tray_open:
		var content := _tray_lines.get_combined_minimum_size().y
		var tray_room := maxf(_stop_y() - _tray_scroll.global_position.y, 0.0)
		_tray_scroll.custom_minimum_size.y = minf(content, tray_room)
