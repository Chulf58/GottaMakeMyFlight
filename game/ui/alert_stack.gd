class_name AlertStack
extends VBoxContainer
## The alert cards (HUD 1/7, decision hud-steal-list-self-clearing-alert-cards-
## money-hover-departu): a stack of small cards under the top HUD row, one per
## problem that is true right now, each clearing itself when its cause is
## solved (AlertBoard). The causes are a full check-in or security queue and
## passengers with no walkable route (AlertSources) and a dirty terminal
## (DirtyAlert). Clicking a card glides the camera to the problem; the next
## click goes to the next place with the same problem (the next full desk, the
## next stuck passenger). The camera puts its focus in the middle of the screen
## share the open panels leave free (PanelRoom, decision panel-room-as-built-
## camera-frames-the-terminal-in-the-screen), and the drawn cards and the open
## tray count as such a panel (room_rect()), so a jump lands below the stack,
## not under it. They are not one of PanelRoom's open-or-closed panels: a card
## coming or going shifts the view a little, like a banner line, and never
## zooms it.
##
## An "Alerts" button opens the history tray: every card that came up, newest
## first, with when it came up and when it cleared, and the on/off switch for
## the cards (decision optional-hud-pieces-keep-their-on-off-setting-in-user-
## hud-se, key SETTING_KEY, on by default). Off hides the cards; the history
## still fills, so a player who turned them off can look back. Alerts are never
## saved: a load or a new world starts the stack again (reset()).
##
## The airport-closed banner (StaffPanel's hint card) is not in the stack: it
## is ruled as its own card docked above the bar (decision staff-panel-behind-a-
## staff-button-at-the-end-of-the-bottom-bar), PanelRoom makes room for it, and
## it guides the opening rather than reporting a problem that comes and goes.

## A card was clicked and the camera sent to `target`.
signal jumped(target: Vector3)

const SETTING_KEY := "alert_cards"
## The distance a jump zooms in to; a camera already closer keeps its distance.
const JUMP_DISTANCE := 30.0
## The most history lines the tray shows; AlertBoard keeps HISTORY_CAP.
const TRAY_LINES := 12
## Below the top row (money, rating, offers, day panel), right edge a gap left
## of the flight panel (which spans the right 460 px less its 20 px margin), so
## the stack sits in the free space beside it. It is WIDTH wide, or narrower
## (the text wraps) when the viewport leaves less than that, down to MIN_WIDTH.
const TOP := 76.0
const WIDTH := 420.0
const MIN_WIDTH := 240.0
const RIGHT_GAP := 480.0
const LEFT_MARGIN := 16.0

## The passenger sim the causes are read from. A different sim is a different
## world, so the stack starts again.
var sim: PassengerSim:
	set(value):
		sim = value
		_dirty.sim = value
		reset()
## The camera a click sends; without one a click only emits `jumped`.
var camera: TycoonCamera
## Where the on/off choice is kept; tests use their own file.
var settings_path := HudFlagSetting.PATH
## True while something covers the stack's place (the open offer sheet); the
## stack stays down then and comes back when it is false.
var covered := Callable()

var _board := AlertBoard.new()
var _dirty := DirtyAlert.new()
var _cards_on := true
var _cards := VBoxContainer.new()
var _tray := PanelContainer.new()
var _tray_lines := VBoxContainer.new()
var _tray_button := Button.new()
var _toggle := CheckButton.new()
var _shown_revision := -1
## Key -> how many clicks its card has had, to step through its targets.
var _clicks: Dictionary = {}


## The stack's width for a viewport `viewport_w` wide: WIDTH, or what is left of
## it between LEFT_MARGIN and the flight panel, never under MIN_WIDTH.
static func width_for(viewport_w: float) -> float:
	return clampf(viewport_w - RIGHT_GAP - LEFT_MARGIN, MIN_WIDTH, WIDTH)


func _ready() -> void:
	name = "AlertStack"
	theme = BuildMenu.HUD_THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	offset_top = TOP
	grow_vertical = Control.GROW_DIRECTION_END
	_cards_on = HudFlagSetting.load_flag(settings_path, SETTING_KEY, true, "AlertStack")
	_fit()
	get_viewport().size_changed.connect(_fit)
	_build()


## The DirtyAlert cause, for tests and probes.
func dirty_source() -> DirtyAlert:
	return _dirty


## The rule holding the cards and the history, for tests and probes.
func board() -> AlertBoard:
	return _board


## Drops every card and the history, as for a new world.
func reset() -> void:
	_dirty.reset()
	_board.reset()
	_clicks.clear()
	_shown_revision = _board.revision
	_sync_cards()
	_sync_tray()


## Reads every cause, updates the cards and the tray. Does nothing without a sim.
func refresh() -> void:
	if sim == null:
		return
	_dirty.refresh()
	var causes: Array[Dictionary] = []
	causes.append_array(AlertSources.queue_full(sim))
	causes.append_array(AlertSources.no_route(sim))
	causes.append_array(_dirty.cause())
	_board.update(causes, sim.tick)
	if _board.revision != _shown_revision:
		_shown_revision = _board.revision
		_sync_cards()
		_sync_tray()
	visible = not (covered.is_valid() and covered.call())
	_cards.visible = _cards_on


## The screen rectangle of the drawn cards and the open history tray, which the
## camera keeps its focus clear of (PanelRoom); empty while none is drawn. The
## Alerts button alone is left out: it is always there and small.
func room_rect() -> Rect2:
	var rect := Rect2()
	if not is_visible_in_tree():
		return rect
	var parts: Array[Node] = [_tray]
	parts.append_array(_cards.get_children())
	for part: Control in parts:
		if part.is_visible_in_tree():
			var r := part.get_global_rect()
			rect = r if not rect.has_area() else rect.merge(r)
	return rect


## The keys of the cards up, in the order they came up (also while the cards
## are switched off).
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
		camera.glide_to(target, minf(camera.target_distance, JUMP_DISTANCE))
	jumped.emit(target)
	return true


func cards_on() -> bool:
	return _cards_on


## Shows or hides the cards and saves the choice. The history fills either way.
func set_cards_on(value: bool) -> void:
	_cards_on = value
	_cards.visible = value
	_toggle.set_pressed_no_signal(value)
	HudFlagSetting.save_flag(settings_path, SETTING_KEY, value, "AlertStack")


func is_tray_open() -> bool:
	return _tray.visible


func set_tray_open(value: bool) -> void:
	_tray.visible = value
	_tray_button.set_pressed_no_signal(value)


## The history as the tray words it, newest first: when the card came up, its
## title and when it cleared ("still up" while it is).
func history_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for entry in _board.history():
		var raised: int = entry["raised_tick"]
		var cleared: int = entry["cleared_tick"]
		var end := "still up" if cleared < 0 else "cleared %s" % GameCalendar.clock_text(cleared)
		(
			lines
			. append(
				(
					"Day %d %s  %s, %s"
					% [
						GameCalendar.day_of(raised) + 1,
						GameCalendar.clock_text(raised),
						entry["title"],
						end,
					]
				)
			)
		)
	return lines


func _build() -> void:
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_END
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_cards.visible = _cards_on
	add_child(_cards)
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
	_tray_lines.name = "AlertHistoryLines"
	column.add_child(_tray_lines)
	_sync_tray()


## Makes the drawn cards match the board's: new ones added, gone ones removed
## at once, words updated, in the order they came up.
func _sync_cards() -> void:
	var keep := {}
	var index := 0
	for alert in _board.active():
		var key: StringName = alert["key"]
		keep[_card_name(key)] = true
		var card := card_node(key)
		if card == null:
			card = _new_card(key)
			_cards.add_child(card)
		(card.find_child("Title", true, false) as Label).text = alert["title"]
		(card.find_child("Detail", true, false) as Label).text = alert["detail"]
		_cards.move_child(card, index)
		index += 1
	for child in _cards.get_children():
		if not keep.has(String(child.name)):
			_cards.remove_child(child)
			child.queue_free()
	for key: StringName in _clicks.keys():
		if _board.alert(key).is_empty():
			_clicks.erase(key)
	var count := _board.active().size()
	_tray_button.text = "Alerts" if count == 0 else "Alerts (%d)" % count


func _new_card(key: StringName) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = _card_name(key)
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
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		press_card(key)


static func _card_name(key: StringName) -> String:
	return "AlertCard_%s" % key


func _fit() -> void:
	var width := width_for(get_viewport().get_visible_rect().size.x)
	offset_right = -RIGHT_GAP
	offset_left = -RIGHT_GAP - width
