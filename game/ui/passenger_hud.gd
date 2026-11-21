class_name PassengerHud
extends CanvasLayer
## The passenger HUD. Top-right: one row with the in-game day and clock and the
## speed buttons (Space toggles the pause, Shift+1/2/3 set the speed, shown as
## the buttons' tooltips). The
## flight rows and the made, missed and in-terminal counts live in the
## Departures list instead (decision top-right-clock-panel-slims-to-day-time-
## and-speed-flight-row). While the clock fast-forwards a quiet night, a
## "Quiet night: fast-forwarding" chip shows under that panel (QuietNight).
## On the left edge, the optional DeparturesBoard (B
## shows and hides it), which steps aside while the inspect card shows. Under
## the clock panel, the right rail (AlertStack): alert cards, which clear
## themselves and jump the camera when clicked, and the flight result card.
## Bottom-left: the followed passenger's inspect card (PassengerInspect:
## live status, its thoughts, and a pin where a clicked thought happened), or
## the followed vehicle's story, kept left of BuildMenu's centre column and
## growing upward when it wraps. Bottom-right: a collapsed
## Debug panel (a 300-passenger batch, a starter terminal on the Toon doors B
## and C, the batch seed and their status). Clicking a passenger while no
## build tool is active follows it: the selection is a stable passenger id,
## and the camera follows PassengerViews.follow_anchor, never a pooled node.
## Clicking a car or taxi on the landside (LandsideViews) follows it instead
## and the text shows its passengers, their flight and the drop-off delay so
## far (VehicleInspect); a click inside a vehicle's drawn box picks the vehicle
## before any passenger near it. One selection at a time.
## When a flight's doors close, a FlightResultPanel (green, cream or coral)
## goes on the rail: made, missed, close-call saves and the main reasons; a
## later closing flight replaces it, and it leaves after
## FlightResultPanel.SHOW_SECONDS of real time or on a click, staying in the
## alerts history. On
## ready the camera frames the built area (StartView) inside the screen share
## the open panels leave free (PanelRoom, which keeps telling the camera as
## panels open and close). A new game opens paused under the
## IntroDialogue (once per session, never in a probe, a test or a playtest);
## closing it starts the clock at 1x.
##
## Economy policy of the Debug panel (Economy 7/8): its actions are debug aids
## and are labelled so. The starter terminal is written straight to the grid,
## so it costs nothing and pays no refund when a piece comes down; spawned
## passengers are normal ones and pay their airline fee when they board.

## The PlaytestHook autoload's script, for its static switch check.
const PLAYTEST_HOOK := preload("res://debug/playtest_hook.gd")
## Above BuildMenu's layer, so the intro's backdrop covers the build bar too.
const INTRO_LAYER := 10
const DEBUG_BATCH := 300
const DEBUG_POLICY_TEXT := "Debug only: the terminal is free with no refunds; passengers pay fees."
## Where the follow text's bottom edge sits, up from the bottom of the screen.
const FOLLOW_BOTTOM := BuildMenu.MARGIN + BuildMenu.BAR_H + BuildMenu.GAP
const FOLLOW_TOP := FOLLOW_BOTTOM + HudLayout.CHIP_H
const SPEED_KEYS := {KEY_1: 1, KEY_2: 2, KEY_3: 3}
## The speed buttons' icon files and node names by speed (0 is Pause), and the key names
## their tooltips show.
const SPEED_ICON := "res://assets/ui/icons/speed_%s.svg"
const SPEED_NAMES: Array[String] = ["pause", "1", "2", "3"]
const SPEED_BUTTON_W := 36.0
const PAUSE_KEY := "Space"
const SPEED_KEY_PREFIX := "Shift+"
## The Debug panel's fixed width; its labels wrap inside it.
const DEBUG_W := 260.0
## Frames from a click that selected a built item to the camera deciding on a pan.
const REVEAL_FRAMES := 2
## The flight result card's key on the rail.
const RESULT_KEY := &"flight_result"

@export var clock: SimClock
@export var flights: FlightSim
@export var sim: PassengerSim:
	set(value):
		sim = value
		_alerts.sim = value
@export var views: PassengerViews
## The landside's vehicles, for clicking a car or taxi; optional.
@export var landside_views: LandsideViews
@export var camera: TycoonCamera
## Its loaded signal re-frames the start view on the loaded world.
@export var save_game: SaveGame
@export var build_mode: BuildMode
## Where the departures board keeps its on/off choice; tests use their own.
var departures_settings_path := DeparturesBoard.SETTINGS_PATH
## Where the alert cards keep their on/off choice; tests use their own.
var alert_settings_path := HudFlagSetting.PATH
## Whether the Debug toggle and its panel are built: dev builds only (decision
## debug-panel-is-for-dev-builds-only-the-hud-s-debug-toggle-an). A test sets it
## before add_child to build or leave out the debug tools.
var debug_tools := OS.is_debug_build()
## End-of-demo Day 5 summary card (DemoEndCard); active only in demo builds.
var demo_end_card := DemoEndCard.new()

var _departures_board := DeparturesBoard.new()
## The full-screen flight planner and its toggle on the Departures row; built
## only when the HUD has a FlightSim and a clock.
var _planner := FlightPlanner.new()
var _alerts := AlertStack.new()
var _pa_ticker := PaTicker.new()
var _hints := Hints.new()
## The new-tier dialog and the "New" card marks (UnlockGuide); on in a normal
## launch only, like the hints.
var _unlock_guide := UnlockGuide.new()
var _seed_label := Label.new()
var _follow_card := FollowCard.new()
var _follow_label := Label.new()
## The followed passenger's card; the follow text then hides.
var _inspect := PassengerInspect.new()
## The clicked built item (BuiltSelection) and its gold floor outline; the
## inspect card shows its info in place of a passenger's.
var _built := BuiltSelection.new()
var _outline := BuiltOutline.new()
## Frames until a click that selected a built item decides whether the camera
## must pan to show it: the inspect window that opens is laid out a frame late.
var _reveal_frames := 0
## The camera serial of the glide _reveal_built() began, so Esc stops that one and no later glide.
var _reveal_glide := 0
var _status_label := Label.new()
var _status := ""
## True after a refused debug batch, until the next spawned one: the earlier
## batch's seed line is then stale and stays hidden.
var _batch_refused := false
var _time_label := Label.new()
var _speed_buttons: Array[Button] = []
var _clock_panel: Control
## Shown GROUP_GAP under the clock panel while the clock fast-forwards; the
## clock panel itself stays one row (decision top-right-clock-panel-slims-to-
## day-time-and-speed-flight-row), and the rail hangs under the chip instead.
var _quiet_chip := PanelContainer.new()
var _debug_panel := PanelContainer.new()
var _panel_room := PanelRoom.new()
## Flights whose doors closed and whose result is not summarized yet, oldest
## first. The sim marks the passengers missed after the doors_closed signal,
## so a result waits for the next refresh.
var _unreported: Array[String] = []
var _intro_layer: CanvasLayer
var _intro: IntroDialogue
## The intro's hold on the clock (SimClock.holds), which does not give way to
## the player: the clock starts when the intro closes, as its text says.
var _intro_hold := ClockHolds.NONE
## The game menu, which also asks the new-game incidents question; null in a
## scene without one.
var _game_menu: GameMenu
var _debug_docks: Array[VBoxContainer] = []
## The camera's input state when the intro opened, restored when it closes.
var _camera_was_processing := true
var _camera_was_taking_input := true
## How many dialogs hold the camera now. A queued dialog opens inside the close
## of the one ahead of it, before that one says it closed, so two can overlap.
var _camera_gates := 0


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.name = "FlightPanel"
	panel.theme = BuildMenu.HUD_THEME
	panel.theme_type_variation = &"HudTopCard"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-HudLayout.MARGIN - HudLayout.RAIL_W, HudLayout.MARGIN)
	panel.custom_minimum_size = Vector2(HudLayout.RAIL_W, 0.0)
	add_child(panel)
	var row := HBoxContainer.new()
	panel.add_child(row)
	_time_label.name = "Clock"
	_time_label.theme_type_variation = &"HudLarge"
	_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A longer translation shortens the clock text with an ellipsis rather than push the speed
	# buttons off the right edge: the label gives way, the buttons keep their size.
	_time_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_time_label)
	for value in [0, 1, 2, 3]:
		var button := Button.new()
		_dress_speed_button(button, value)
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(SPEED_BUTTON_W, HudLayout.BUTTON_H)
		button.focus_mode = Control.FOCUS_NONE
		if value == 0:
			button.pressed.connect(press_pause_toggle)
		else:
			button.pressed.connect(press_speed.bind(value))
		row.add_child(button)
		_speed_buttons.append(button)
	_clock_panel = panel
	_build_quiet_chip()
	_departures_board.flights = flights
	_departures_board.clock = clock
	_departures_board.passengers = sim
	_departures_board.settings_path = departures_settings_path
	_departures_board.menu = get_node_or_null("../BuildMenu") as BuildMenu
	_departures_board.follow_late_requested.connect(_on_follow_late_requested)
	add_child(_departures_board)
	if flights != null and clock != null:
		_planner.flights = flights
		_planner.clock = clock
		_planner.build_mode = build_mode
		add_child(_planner)
		_planner.sheet().visibility_changed.connect(
			func() -> void:
				if _planner.is_open():
					_pa_ticker.clear_now()
		)
	# Only hide the rail when a top-row sheet actually overlaps it (narrow viewports).
	_alerts.covered = func() -> bool:
		return TopRow.sheet_overlaps(get_tree(), _alerts.get_global_rect())
	_alerts.above = panel
	_alerts.camera = camera
	_alerts.settings_path = alert_settings_path
	add_child(_alerts)
	_pa_ticker.bottom_provider = _pa_bottom
	_pa_ticker.modal_check = _pa_modal_open
	add_child(_pa_ticker)
	if flights != null:
		flights.doors_closed.connect(_on_doors_closed)
	if debug_tools:
		_build_debug()
	else:
		_drop_debug_nodes()
	_follow_card.name = "FollowCard"
	_follow_card.theme = BuildMenu.HUD_THEME
	_follow_card.theme_type_variation = &"HudTopCard"
	_follow_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_follow_card.visible = false
	_follow_card.add_to_group(BottomDocks.LEFT_FLOOR_GROUP)
	_follow_label.name = "FollowText"
	_follow_label.theme_type_variation = &"HudSmall"
	_follow_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_follow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_follow_card.label = _follow_label
	_follow_card.add_child(_follow_label)
	add_child(_follow_card)
	_inspect.sim = sim
	_inspect.views = views
	_inspect.camera = camera
	_inspect.flights = flights
	_inspect.clock = clock
	_inspect.baggage = get_node_or_null("../BaggageSim") as BaggageSim
	_inspect.built_card.sim = sim
	_inspect.built_card.selection = _built
	_inspect.built_card.build_mode = build_mode
	_inspect.built_card.gates = get_node_or_null("../GateDesks") as GateDesks
	# Delete starts build mode through the bar's session (BuiltItemActions).
	var menu := get_node_or_null("../BuildMenu") as BuildMenu
	if menu != null:
		_inspect.actions.session = menu.build_session
		_alerts.build_tray_open = func() -> bool:
			return is_instance_valid(menu) and menu.is_node_ready() and menu.is_tray_open()
		_alerts.build_stack_top = menu.stack_top
		menu.bar().minimum_size_changed.connect(_fit_follow)
	_outline.selection = _built
	_outline.build_mode = build_mode
	add_child(_outline)
	add_child(_inspect)
	add_child(_inspect.marker)
	_fit_follow()
	get_viewport().size_changed.connect(_fit_follow)
	if IntroDialogue.should_show(
		IntroDialogue.shown_this_session, _in_current_scene(), _playtest_switch_on()
	):
		open_intro()
	if save_game != null:
		save_game.loaded.connect(_on_save_loaded)
	_panel_room.name = "PanelRoom"
	_panel_room.camera = camera
	_panel_room.scene_root = get_parent()
	_panel_room.banner_rect = _banner_rect
	_panel_room.alert_stack = _alerts
	add_child(_panel_room)
	_hints.hud = self
	_hints.scene_root = get_parent()
	add_child(_hints)
	_wire_unlock_guide()
	_wire_dialog_gates()
	_wire_demo_end_card()
	_frame_start_view()
	refresh()


func _process(_delta: float) -> void:
	refresh()
	if _reveal_frames > 0:
		_reveal_frames -= 1
		if _reveal_frames == 0:
			_reveal_built()


## A followed passenger the sim has retired, or whose view is released on
## boarding, is gone: clear the selection and let the camera go where it stands,
## instead of following the frozen anchor.
func _drop_retired_selection() -> void:
	_settle_built_selection()
	if landside_views != null and landside_views.selected_id != 0:
		if not landside_views.has_vehicle(landside_views.selected_id):
			landside_views.selected_id = 0
			if camera != null:
				camera.stop_follow()
	if views == null or views.selected_id == 0:
		return
	var followed := sim.get_passenger(views.selected_id)
	if followed != null and views.shows(followed):
		return
	views.selected_id = 0
	if camera != null:
		camera.stop_follow()


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if views == null or camera == null or build_mode == null:
		return
	# A tool, a template paste or save, or a room move owns the click: it selects
	# nothing, whatever stands under it.
	if BuiltSelection.clicks_taken(build_mode):
		return
	var eye := camera.get_node("Camera3D") as Camera3D
	var vehicle := landside_views.pick(eye, click.position) if landside_views != null else 0
	if landside_views != null:
		landside_views.select(vehicle)
	views.selected_id = 0
	_built.clear()
	if vehicle == 0:
		_pick_built(eye, click.position)
		views.selected_id = _passenger_at(eye, click.position)
		if views.selected_id != 0:
			_built.clear()
	_reveal_frames = REVEAL_FRAMES if _built.is_selected() else 0
	if vehicle != 0:
		camera.follow(landside_views.follow_anchor)
	elif views.selected_id != 0:
		camera.follow(views.follow_anchor)
	else:
		camera.stop_follow()


## Selects the built object `object_id` as a click on it does: a vehicle,
## passenger and the camera follow end, the item is selected and revealed. A
## station sign that takes the click calls this (HoverTarget).
func _select_built_object(object_id: int) -> void:
	if landside_views != null:
		landside_views.select(0)
	if views != null:
		views.selected_id = 0
	_built.select_object(object_id)
	_reveal_frames = REVEAL_FRAMES
	if camera != null:
		camera.stop_follow()


## Pans the camera just far enough to show the selected built item when it is off
## screen or under the inspect window or another panel; an item in plain view
## leaves the camera alone (decision clicking-a-built-desk-outside-build-mode-
## moves-the-camera-on).
func _reveal_built() -> void:
	if camera == null or build_mode == null or not _built.is_selected():
		return
	var eye := camera.get_node("Camera3D") as Camera3D
	var panels := _panel_room.open_rects()
	if _inspect.visible:
		panels.append(_inspect.get_global_rect())
	var target: Variant = SelectReveal.focus_target(
		eye,
		camera.position,
		_built.outline_rect(build_mode.grid, build_mode.landside_placement()),
		build_mode.grid.origin.y,
		eye.get_viewport().get_visible_rect(),
		panels
	)
	if target != null:
		_reveal_glide = camera.glide_to(target)


## Picks the built item under a click that met no vehicle and no passenger.
func _pick_built(eye: Camera3D, at: Vector2) -> void:
	var view := build_mode.get_node_or_null("BuildView") as BuildView
	if view != null:
		_built.pick(build_mode.grid, view, build_mode.landside_placement(), eye, at)


## The passenger a click selects, after _pick_built() has looked under it. Over a
## built object only a passenger whose body the click ray passes through counts,
## so a queue beside a desk never steals a click on the desk. Anywhere else,
## room floor included (passengers stand on it everywhere), the 40 px circle.
func _passenger_at(eye: Camera3D, at: Vector2) -> int:
	if _built.kind == BuiltSelection.Kind.OBJECT:
		return views.pick_body(eye, at)
	return views.pick(eye, at)


## A built item stays selected only while no build interaction owns the clicks
## (BuiltSelection.clicks_taken()), no passenger or vehicle is selected, and the
## item still stands.
func _settle_built_selection() -> void:
	var other := views != null and views.selected_id != 0
	other = other or (landside_views != null and landside_views.selected_id != 0)
	if build_mode == null or other or BuiltSelection.clicks_taken(build_mode):
		_built.clear()
	else:
		_built.prune(build_mode.grid, build_mode.landside_placement())


## Esc with a card open: drops the selected built item and the followed passenger
## or vehicle, lets the camera go and returns true. False when nothing is selected,
## and Esc then opens the game menu.
func _close_selection() -> bool:
	var vehicle := landside_views != null and landside_views.selected_id != 0
	var passenger := views != null and views.selected_id != 0
	var item := _built.is_selected()
	if not (vehicle or passenger or item):
		return false
	if landside_views != null:
		landside_views.select(0)
	if views != null:
		views.selected_id = 0
	_built.clear()
	_reveal_frames = 0
	if camera != null:
		camera.stop_follow()
		# A built item's reveal glide is heading for the card just dismissed.
		if item:
			camera.stop_glide(_reveal_glide)
	return true


## Space toggles the pause; Shift+1/2/3 set the speed. A held key's repeats
## are swallowed without acting again.
func _shortcut_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or clock == null:
		return
	if key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return
	if key.physical_keycode == KEY_SPACE and not key.shift_pressed:
		if not key.echo:
			press_pause_toggle()
		get_viewport().set_input_as_handled()
	elif key.shift_pressed and SPEED_KEYS.has(key.physical_keycode):
		if not key.echo:
			press_speed(SPEED_KEYS[key.physical_keycode])
		get_viewport().set_input_as_handled()


## The dirty-terminal alert, one of the alert cards' causes, for tests and probes.
func dirty_alert() -> DirtyAlert:
	return _alerts.dirty_source()


func refresh() -> void:
	_drop_retired_selection()
	# The card always shows the latest flight to close, replacing an open one.
	if not _unreported.is_empty():
		_note_results(_unreported)
		show_result_for(_unreported.back())
		_unreported.clear()
	_time_label.text = time_text()
	_departures_board.refresh()
	# Before the rail, so it hangs under the chip on the frame the chip shows.
	_refresh_quiet_chip()
	_alerts.refresh()
	if _pa_modal_open():
		_pa_ticker.clear_now()
	elif _pa_ticker.visible:
		_pa_ticker.place()
	if _seed_label != null:
		_seed_label.text = seed_text()
		_seed_label.visible = _seed_label.text != ""
		_status_label.text = _status
		_status_label.visible = _status != ""
	_follow_label.text = follow_text()
	_inspect.refresh()
	_follow_label.visible = not _inspect.visible
	_follow_card.sync()
	# A passenger card takes the board's place on the left edge (decision 500fd5a0,
	# point 6); a desk, room or car-park card leaves the list showing.
	_departures_board.step_aside(_inspect.shows_passenger())
	if clock != null:
		for i in _speed_buttons.size():
			var on := clock.paused if i == 0 else not clock.paused and clock.speed == i
			_speed_buttons[i].set_pressed_no_signal(on)


func _build_quiet_chip() -> void:
	_quiet_chip.name = "QuietNightChip"
	_quiet_chip.theme = BuildMenu.HUD_THEME
	_quiet_chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_quiet_chip.custom_minimum_size = Vector2(HudLayout.RAIL_W, 0.0)
	_quiet_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quiet_chip.visible = false
	var label := Label.new()
	label.text = tr("Quiet night: fast-forwarding")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quiet_chip.add_child(label)
	add_child(_quiet_chip)


## Shows the chip while the clock fast-forwards, under the clock panel's real
## bottom, and hangs the rail under the chip while it shows.
func _refresh_quiet_chip() -> void:
	var fast := clock != null and clock.is_fast_forwarding()
	_quiet_chip.visible = fast
	var top := _clock_panel.position.y + _clock_panel.size.y + HudLayout.GROUP_GAP
	_quiet_chip.position = Vector2(_clock_panel.position.x, top)
	_alerts.above = _quiet_chip if fast else _clock_panel


## The in-game day and 24-hour clock, "Day 1  06:00" (GameCalendar).
func time_text() -> String:
	return tr("Day {day}  {time}", "clock").format(
		{
			"day": GameCalendar.day_of(clock.tick, clock.epoch) + 1,
			"time": GameCalendar.clock_text(clock.tick, clock.epoch)
		}
	)


func seed_text() -> String:
	if sim.last_batch_seed == 0 or _batch_refused:
		return ""
	return "Debug batch: %d passengers, seed %d" % [DEBUG_BATCH, sim.last_batch_seed]


func status_text() -> String:
	return _status


## What `p` is doing, for the follow line: its stage's text, naming the shop
## it is visiting when it has a visit under way (store_name() is empty when
## there is no visit or its room is gone, so the room is there below), or the
## venue's words for a visit to the stall, bar or restaurant.
static func stage_text(passenger_sim: PassengerSim, p: Passenger) -> String:
	return StageWords.text(passenger_sim, p)


func follow_text() -> String:
	if landside_views != null and landside_views.selected_id != 0:
		var v: LandsideVehicle = null
		if sim.landside != null:
			v = sim.landside.get_vehicle(landside_views.selected_id)
		return VehicleInspect.text(sim.arrivals, flights, v, clock.tick) if v != null else ""
	if views == null or views.selected_id == 0:
		return ""
	var p := sim.get_passenger(views.selected_id)
	if p == null:
		return ""
	var parts := PackedStringArray(
		[
			tr("Passenger {id}", "follow line").format({"id": p.id}),
			stage_text(sim, p),
			tr("mood {value}", "follow line").format({"value": p.mood}),
			tr("hunger {value}", "follow line").format({"value": p.hunger}),
			tr("toilet {value}", "follow line").format({"value": p.toilet_need}),
		]
	)
	var bubble := BubbleWords.say(sim.bubble_text(p))
	if bubble != "":
		parts.append(tr('"{text}"', "passenger speech").format({"text": bubble}))
	return "   ".join(parts)


## A speed button is an icon (pause bars, one, two or three play arrows) with the
## action and its key in the tooltip, so the clock keeps the width the buttons
## would have taken for translated words. `value` 0 is Pause.
func _dress_speed_button(button: Button, value: int) -> void:
	button.name = "Speed" + SPEED_NAMES[value].capitalize()
	button.text = ""
	button.icon = load(SPEED_ICON % SPEED_NAMES[value])
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	if value == 0:
		button.tooltip_text = tr("Pause ({key})", "speed button").format({"key": PAUSE_KEY})
	else:
		button.tooltip_text = tr("Speed {speed}x ({key})", "speed button").format(
			{"speed": value, "key": SPEED_KEY_PREFIX + str(value)}
		)


## Spawns the debug batch through normal spawning. The seed comes from the
## cosmetic RNG, so pressing the button leaves the saved sim RNG untouched.
## With no flight open (every one has closed its doors) the press is refused
## here, quietly, and the old batch's seed line is hidden.
func press_debug_spawn() -> void:
	if not _has_open_flight():
		_batch_refused = true
		_status = "Spawn refused: no flight is open for passengers"
		return
	var seed := randi() + 1
	if not sim.spawn_batch(DEBUG_BATCH, seed):
		_batch_refused = true
		_status = "Spawn refused: no flight is open for passengers"
		return
	_batch_refused = false
	_status = "Spawned %d passengers" % DEBUG_BATCH
	print("DEBUG_BATCH spawn %d passengers seed=%d tick=%d" % [DEBUG_BATCH, seed, clock.tick])


## Posts a flight's result card to the rail, from the passengers' recorded
## fates, replacing the one up; its full text goes in the alerts history.
func show_result_for(flight_id: String) -> void:
	var card := FlightResultPanel.new()
	card.show_result(_result_summary(flight_id))
	card.dismissed.connect(dismiss_result)
	var lines := card.result_text().split("\n")
	var detail := "\n".join(lines.slice(1))
	_alerts.post_notice(RESULT_KEY, card, FlightResultPanel.SHOW_SECONDS, lines[0], detail)


## Every flight that closed since the last refresh goes in the quit log, not
## only the one whose card is shown.
func _note_results(flight_ids: Array[String]) -> void:
	if QuitLog.current == null:
		return
	for flight_id in flight_ids:
		var summary := FlightResult.summarize(sim, flight_id)
		QuitLog.note("flight_result", {"made": summary["made"], "missed": summary["missed"]})


## The flight's FlightResult summary, titled with its contract's name.
func _result_summary(flight_id: String) -> Dictionary:
	var summary := FlightResult.summarize(sim, flight_id)
	summary["title"] = FlightResultPanel.title_for(flights, flight_id)
	return summary


func dismiss_result() -> void:
	_alerts.drop_notice(RESULT_KEY)


func is_result_open() -> bool:
	return _alerts.notice_card(RESULT_KEY) != null


func result_text() -> String:
	var card := _alerts.notice_card(RESULT_KEY) as FlightResultPanel
	return "" if card == null else card.result_text()


## 0 pauses; 1 to 3 run at that speed.
func press_speed(value: int) -> void:
	clock.set_paused(value == 0)
	if value > 0:
		clock.set_speed(value)


## Pauses, or resumes at the speed the clock had. It acts on the player's own
## pause: on a clock a hold pauses (build mode, the Offers sheet, a dialog) it
## resumes, which ends the pause of the holds that give way; a dialog's hold
## keeps the clock paused until the dialog closes, and the game then runs.
func press_pause_toggle() -> void:
	clock.set_paused(not clock.paused)


## Gives the unlock guide the tiers and the clock, holds the camera still while
## its dialog is open, and hands it to the build menu for the "New" marks.
func _wire_unlock_guide() -> void:
	var user_args := OS.get_cmdline_user_args()
	var env_hints := OS.get_environment(Hints.SWITCH_ENV)
	if (
		user_args.has(Hints.SWITCH_ARG)
		or env_hints == "1"
		or (_in_current_scene() and not Hints.launched_by_script(OS.get_cmdline_args()))
	):
		_unlock_guide.mode = UnlockGuide.mode_for(user_args, env_hints, _playtest_switch_on())
	if build_mode != null:
		_unlock_guide.unlocks = build_mode.unlocks
	_unlock_guide.clock = clock
	_unlock_guide.save_game = save_game
	if flights != null:
		_unlock_guide.runway = flights.runway
	_unlock_guide.director = get_node_or_null("../IncidentDirector") as IncidentDirector
	_unlock_guide.dialog_changed.connect(_gate_camera)
	add_child(_unlock_guide)
	var menu := get_node_or_null("../BuildMenu") as BuildMenu
	if menu != null:
		menu.watch_guide(_unlock_guide)


## Holds the camera still while the game menu, the new-game question or a major
## incident panel is open, as it is for the intro and the unlock dialog.
func _wire_dialog_gates() -> void:
	_game_menu = get_node_or_null("../GameMenu") as GameMenu
	if _game_menu != null:
		_game_menu.dialog_changed.connect(_gate_camera)
		_game_menu.esc_closes = _close_selection
	var incident_panel := get_node_or_null("../IncidentPanel") as IncidentPanel
	if incident_panel != null:
		incident_panel.dialog_changed.connect(_gate_camera)


func _wire_demo_end_card() -> void:
	demo_end_card.hud = self
	demo_end_card.clock = clock
	demo_end_card.build_mode = build_mode
	demo_end_card.save_game = save_game
	demo_end_card.dialog_changed.connect(_gate_camera)
	demo_end_card.dialog_changed.connect(
		func(open: bool) -> void:
			if open:
				_pa_ticker.clear_now()
	)
	add_child(demo_end_card)


## The unlock guide: its dialog and marks, or null before the HUD is ready.
func unlock_guide() -> UnlockGuide:
	return _unlock_guide


## Pauses the clock and opens the intro dialogue, which stops the camera: at
## once, or, while another exclusive dialog has the turn, when that one closes.
## Refused (false) when it was already shown this session or is open.
func open_intro() -> bool:
	if IntroDialogue.shown_this_session or _intro != null or clock == null:
		return false
	IntroDialogue.shown_this_session = true
	_intro_hold = clock.holds.take_turn(self, _show_intro)
	return true


func _show_intro() -> void:
	_intro_layer = CanvasLayer.new()
	_intro_layer.name = "IntroLayer"
	_intro_layer.layer = INTRO_LAYER
	_intro = IntroDialogue.new()
	_intro_layer.add_child(_intro)
	add_child(_intro_layer)
	# Dismissal, or the dialogue or its layer leaving the tree any other way,
	# runs the same one-time cleanup.
	_intro.dismissed.connect(_close_intro)
	_intro.tree_exiting.connect(_close_intro)
	_intro_layer.tree_exiting.connect(_close_intro)
	_gate_camera(true)


## Closes the intro as Continue would, or drops its queued hold; does nothing
## when neither is active.
func dismiss_intro() -> void:
	if _intro != null:
		_intro.dismiss()
	elif _intro_hold != ClockHolds.NONE:
		if is_instance_valid(clock):
			clock.holds.release(_intro_hold)
		_intro_hold = ClockHolds.NONE


## The open intro dialogue, or null when it is closed.
func intro() -> IntroDialogue:
	return _intro


func is_debug_open() -> bool:
	return _debug_panel != null and _debug_panel.visible


func set_debug_open(value: bool) -> void:
	if _debug_panel != null:
		_debug_panel.visible = value


## The debug starter button, a shortcut for what BuildMode's tools can also
## build. On a pristine build grid (no floor, walls or objects) it builds the
## whole ReferenceTerminal; on any other grid, the new-game shell included, it
## adds the reference interior (divider, desks, scanners, seats) to what
## stands (decision terminal-growth-and-starter-building-move-the-airside-
## north, point 3). Then, with no gate desk on the grid, it adds the gate desk
## by the exit (ReferenceTerminal.gate_desk_edit()). Either outcome is shown in
## the status line; a refusal changes nothing.
func press_starter_terminal() -> void:
	if build_mode == null:
		return
	var grid := build_mode.grid
	var view := build_mode.get_node("BuildView") as BuildView
	if _is_pristine(grid):
		if not ReferenceTerminal.build(grid):
			push_error("PassengerHud: the starter terminal did not fit the grid")
			_status = "Starter terminal failed: it did not fit the grid"
			view.refresh(grid)
			return
		_status = "Starter terminal built"
	else:
		var result := ReferenceTerminal.fill_interior(grid)
		if not result.ok:
			_status = "Starter terminal not filled: %s" % result.reason_text()
			return
		_status = "Starter terminal filled"
	# Its exit becomes a gate, so flights can be given one (GateDesks).
	if GateDesks.desk_ids(grid).is_empty():
		var desk := grid.apply(ReferenceTerminal.gate_desk_edit(ReferenceTerminal.offset_on(grid)))
		if not desk.ok:
			_status += "; no gate desk: %s" % desk.reason_text()
	view.refresh(grid)


## The Debug toggle at the bottom-right corner, with its panel docked above the
## bar's height, so the open panel never reaches over the right end of the
## build bar (smoke playtest 10; HUD 6/7).
func _build_debug() -> void:
	var corner := _bottom_right_dock("DebugCorner", BuildMenu.MARGIN)
	var dock := _bottom_right_dock(
		"DebugPanelDock", BuildMenu.MARGIN + BuildMenu.BAR_H + BuildMenu.GAP
	)
	corner.add_to_group(BottomDocks.RIGHT_FLOOR_GROUP)
	dock.add_to_group(BottomDocks.RIGHT_FLOOR_GROUP)
	_debug_docks = [corner, dock]
	_place_debug_docks()
	get_viewport().size_changed.connect(_place_debug_docks)
	var menu := get_node_or_null("../BuildMenu") as BuildMenu
	if menu != null:
		menu.bar().minimum_size_changed.connect(_place_debug_docks)
	_debug_panel.name = "DebugPanel"
	_debug_panel.visible = false
	_debug_panel.custom_minimum_size = Vector2(DEBUG_W, 0.0)
	dock.add_child(_debug_panel)
	var column := VBoxContainer.new()
	_debug_panel.add_child(column)
	column.add_child(DebugPanelParts.spawn_button(DEBUG_BATCH, press_debug_spawn))
	column.add_child(DebugPanelParts.starter_button(press_starter_terminal))
	var policy := Label.new()
	policy.text = DEBUG_POLICY_TEXT
	for label in [policy, _seed_label, _status_label]:
		label.theme_type_variation = &"HudHint"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(label)
	corner.add_child(DebugPanelParts.toggle(set_debug_open))


## A build without the debug tools never parents the panel or its two labels, so
## they are freed now and the debug accessors and the refresh skip them.
func _drop_debug_nodes() -> void:
	_debug_panel.free()
	_seed_label.free()
	_status_label.free()
	_debug_panel = null
	_seed_label = null
	_status_label = null


## The Debug toggle beside the bar's right end, or lifted a bar height when the
## bar leaves no room (BottomDocks); its panel stays a gap above the toggle.
func _place_debug_docks() -> void:
	var menu := get_node_or_null("../BuildMenu") as BuildMenu
	var bar_w := 0.0 if menu == null else menu.bar().get_combined_minimum_size().x
	var beside := BottomDocks.beside_bar(get_viewport().get_visible_rect().size.x, bar_w)
	var corner_bottom := BottomDocks.bottom(beside)
	var panel_bottom := BuildMenu.MARGIN + BuildMenu.BAR_H + BuildMenu.GAP
	if not beside:
		panel_bottom = corner_bottom + HudLayout.BUTTON_H + HudLayout.GAP
	for i in 2:
		var bottom := corner_bottom if i == 0 else panel_bottom
		_debug_docks[i].offset_top = -bottom
		_debug_docks[i].offset_bottom = -bottom


## A column anchored to the bottom-right corner, MARGIN in, with its bottom edge
## `bottom` px up; it grows up and to the left.
func _bottom_right_dock(dock_name: String, bottom: float) -> VBoxContainer:
	var dock := VBoxContainer.new()
	dock.name = dock_name
	dock.theme = BuildMenu.HUD_THEME
	dock.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	dock.offset_left = -float(HudLayout.MARGIN)
	dock.offset_right = -float(HudLayout.MARGIN)
	dock.offset_top = -bottom
	dock.offset_bottom = -bottom
	dock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dock.alignment = BoxContainer.ALIGNMENT_END
	add_child(dock)
	return dock


## Keeps the follow card bottom-left, left of BuildMenu's centre column and
## clear of CategoryBar (BottomDocks), growing upward when wrapped.
func _fit_follow() -> void:
	var layer_w := get_viewport().get_visible_rect().size.x
	var menu := get_node_or_null("../BuildMenu") as BuildMenu
	var bar_w := (
		0.0
		if menu == null or not menu.is_node_ready()
		else menu.bar().get_combined_minimum_size().x
	)
	var bottom := BottomDocks.left_floor_bottom(layer_w, bar_w)
	var width := BottomDocks.left_corner_width(layer_w, 160.0, PassengerInspect.MAX_W)
	_follow_card.anchor_left = 0.0
	_follow_card.anchor_right = 0.0
	_follow_card.anchor_top = 1.0
	_follow_card.anchor_bottom = 1.0
	_follow_card.offset_left = float(HudLayout.MARGIN)
	_follow_card.offset_right = float(HudLayout.MARGIN) + width
	_follow_card.offset_top = -bottom - float(HudLayout.CHIP_H)
	_follow_card.offset_bottom = -bottom
	_follow_card.grow_vertical = Control.GROW_DIRECTION_BEGIN


## Ends the intro once, however it ended: frees its layer (unless that is
## already on its way out), gives the camera its input back and releases the
## intro's hold, so the clock runs at the player's own speed unless another
## hold still pauses it. Later calls find nothing open and do nothing.
func _close_intro() -> void:
	if _intro_layer == null:
		return
	var layer := _intro_layer
	var continued := _intro != null and _intro.is_dismissed()
	_intro_layer = null
	_intro = null
	if is_instance_valid(layer) and not layer.is_queued_for_deletion():
		layer.queue_free()
	_gate_camera(false)
	# The new-game question takes its place in line before the intro lets go, so
	# the clock stays held from the welcome page to the answer.
	if continued and is_instance_valid(_game_menu) and _game_menu.is_inside_tree():
		_game_menu.ask_incidents()
	if is_instance_valid(clock):
		clock.holds.release(_intro_hold)
	_intro_hold = ClockHolds.NONE


## A load replaced the world and dropped every hold: the intro ends without
## asking the new-game incident question, so the loaded game keeps its own
## incident setting. Its hold is already gone, as incident_panel's is.
func _end_intro_on_load() -> void:
	if _intro_layer == null:
		return
	var layer := _intro_layer
	_intro_layer = null
	_intro = null
	if is_instance_valid(layer) and not layer.is_queued_for_deletion():
		layer.queue_free()
	_gate_camera(false)
	if is_instance_valid(clock):
		clock.holds.release(_intro_hold)
	_intro_hold = ClockHolds.NONE


## The camera-input gate. Marking events handled cannot stop TycoonCamera,
## which polls held keys in _process, so while the intro is open its _process
## (WASD, Q/E, easing) and _unhandled_input (wheel, drags, Home) are switched
## off, and switched back to what they were when the last one closes. Only the
## first gate saves the state, so overlapping gates cannot save the gated one.
func _gate_camera(closed: bool) -> void:
	if closed:
		_pa_ticker.clear_now()
		_camera_gates += 1
		if _camera_gates > 1:
			return
		if is_instance_valid(camera):
			_camera_was_processing = camera.is_processing()
			_camera_was_taking_input = camera.is_processing_unhandled_input()
			camera.set_process(false)
			camera.set_process_unhandled_input(false)
	else:
		if _camera_gates == 0:
			return
		_camera_gates -= 1
		if _camera_gates > 0:
			return
		if is_instance_valid(camera):
			camera.set_process(_camera_was_processing)
			camera.set_process_unhandled_input(_camera_was_taking_input)


## True when this HUD belongs to the running scene: a normal launch or a
## change_scene, not a probe or test that adds the scene under root by hand.
func _in_current_scene() -> bool:
	var current := get_tree().current_scene
	return current != null and (current == self or current.is_ancestor_of(self))


## The PlaytestHook's switches (--playtest, GMMF_PLAYTEST=1 or the
## debug/playtest/enabled setting), in any build: a playtest skips the intro.
func _playtest_switch_on() -> bool:
	return PLAYTEST_HOOK.wants_enabled(
		true,
		OS.get_cmdline_user_args(),
		ProjectSettings.get_setting(PLAYTEST_HOOK.SETTING, false),
		OS.get_environment(PLAYTEST_HOOK.ENV)
	)


func _has_open_flight() -> bool:
	for id in flights.flight_ids():
		if not flights.is_doors_closed(id):
			return true
	return false


## A loaded world is a new start: frame the camera on what the save built.
func _on_save_loaded(ok: bool) -> void:
	if ok:
		_end_intro_on_load()
		# A loaded world may reuse the selected id for another item.
		_built.clear()
		# A flight that closed before the load belongs to the old world: its
		# result must not reach the rail after the reset.
		_unreported.clear()
		_alerts.reset()
		_pa_ticker.clear_now()
		_inspect.on_loaded(ok)
		_frame_start_view()


func _pa_bottom() -> float:
	var menu := get_node_or_null("../BuildMenu") as BuildMenu
	if menu != null and menu.is_node_ready() and menu.is_tray_open():
		return menu.stack_top() + HudLayout.GAP
	var staff := get_node_or_null("../StaffPanel") as StaffPanel
	if staff != null and staff.is_node_ready():
		var staff_card := staff.get_node_or_null("StaffCard") as Control
		if staff_card != null and staff_card.visible:
			return (
				BuildMenu.MARGIN
				+ BuildMenu.BAR_H
				+ BuildMenu.GAP
				+ staff_card.size.y
				+ HudLayout.GAP
			)
	return BuildMenu.MARGIN + BuildMenu.BAR_H + HudLayout.GAP


func _pa_modal_open() -> bool:
	if _camera_gates > 0 or demo_end_card.is_open():
		return true
	if _planner != null and _planner.is_node_ready() and _planner.is_open():
		return true
	var offers := get_node_or_null("../OfferPanel") as OfferPanel
	return offers != null and offers.is_node_ready() and offers.is_open()


func _frame_start_view() -> void:
	if camera != null and build_mode != null:
		camera.frame_start_view(StartView.area_for(build_mode.grid), _panel_room.free_fraction())
		_panel_room.mark_sent()


## The banner slot's screen rectangle while the status banner or a first-time
## hint shows there, empty otherwise; PanelRoom cuts it from the camera room.
func _banner_rect() -> Rect2:
	var rect := Rect2()
	var staff := get_parent().get_node_or_null("StaffPanel") as StaffPanel
	var cards: Array[Control] = [_hints.card()]
	if staff != null:
		cards.append(staff.hint_card())
	for card in cards:
		if card.is_visible_in_tree():
			var r := card.get_global_rect()
			rect = r if not rect.has_area() else rect.merge(r)
	return rect


func _on_doors_closed(flight_id: String) -> void:
	_unreported.append(flight_id)


func _on_follow_late_requested(flight_id: String) -> void:
	if sim == null or views == null:
		return
	var id := LateCount.tightest_passenger(sim, flight_id)
	if id == 0:
		return
	var p := sim.get_passenger(id)
	if p == null or not views.shows(p):
		return
	if landside_views != null:
		landside_views.select(0)
	_built.clear()
	_reveal_frames = 0
	views.selected_id = id
	if camera != null:
		camera.follow(views.follow_anchor)
	refresh()


func _is_pristine(grid: BuildGrid) -> bool:
	if not grid.object_ids().is_empty():
		return false
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if grid.floor_at(cell) != BuildGrid.FLOOR_NONE:
				return false
			for side in BuildGrid.SIDE_STEP.size():
				if grid.has_wall(cell, side):
					return false
	return true


## Cream HUD card backing for the selected-vehicle / passenger follow text;
## keeps its visibility synced with `label` even when PassengerHud._process is paused.
class FollowCard:
	extends PanelContainer

	var label: Label

	func _process(_delta: float) -> void:
		sync()

	func sync() -> void:
		if label == null:
			return
		var want := label.visible and label.text != ""
		if visible != want:
			visible = want
