extends SceneTree
## Windowed plate probe for Economy 7/8 on the real main.tscn, at 1920x1080 with
## the UI scale at 1.0 and at 1.25 (Window.content_scale_factor):
##   a_start    new game: money slot, live prices, cost line "Cost 25", one
##              departure, Debug panel open with its policy label
##   b_grey     balance 60, Door picked: Glass and Door cards greyed with a
##              neutral price, cost line with the shortfall
##   c_drag     balance 60, a 4x3 Floor rectangle dragged: cost and shortfall
##              with the slab in frame
##   d_three    three departures and the worst-case result panel open: the
##              flight panel clears the result panel, which clears the status line
## Before each save it proves the subjects: label texts equal what they must,
## every HUD rect lies inside the window and none overlap, the real mouse over
## each tray card reaches it, and (plate c) the dragged cells project inside the
## window in front of the camera. Otherwise it prints PROBE_INVALID and exits 1.
## A guard thread prints PROBE_INVALID and calls OS.crash() past LIMIT_MS.
##
## Run (one windowed Godot run project-wide):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/.claude/worktrees/<lane>/game \
##     -s res://spike/money_hud_plates_probe.gd

const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/money_hud"
const LIMIT_MS := 180000
const WINDOW := Vector2i(1920, 1080)
const SCALES := [1.0, 1.25]
const DRAG_FROM := Vector2i(12, 12)
const DRAG_TO := Vector2i(15, 14)

var _out_dir := ""
var _failed := false
var _start_ms := 0
var _guard := Thread.new()
var _lock := Mutex.new()
var _stop := false
var _scale := 1.0
var _main: Node3D
var _menu: BuildMenu
var _hud: PassengerHud
var _mode: BuildMode
var _finances: Finances
var _flights: FlightSim
var _sim: PassengerSim


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_start_ms = Time.get_ticks_msec()
	_guard.start(_watch)
	_run.call_deferred()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_lock.lock()
		var stop := _stop
		_lock.unlock()
		if stop:
			return
		if Time.get_ticks_msec() - _start_ms > LIMIT_MS:
			print("PROBE_INVALID: the probe ran past %d ms" % LIMIT_MS)
			OS.crash("money_hud_plates_probe: no finish within %d ms" % LIMIT_MS)


func _finish() -> void:
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()


func _run() -> void:
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	DisplayServer.window_set_size(WINDOW)
	await _frames(5)
	if root.size != WINDOW:
		_invalid("the window is %s, not %s" % [root.size, WINDOW])
	for scale: float in SCALES:
		_scale = scale
		root.content_scale_factor = scale
		await _frames(5)
		print(
			"PROBE scale=%s window=%s layout=%s" % [scale, root.size, root.get_visible_rect().size]
		)
		await _boot(world_seed)
		await _scene_a()
		await _scene_b()
		await _scene_c()
		await _scene_d()
		_main.queue_free()
		await _frames(3)
	print("PROBE done failed=%s" % _failed)
	_finish()
	quit(1 if _failed else 0)


func _boot(world_seed: int) -> void:
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(world_seed)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	root.add_child(_main)
	_menu = _main.get_node("BuildMenu") as BuildMenu
	_hud = _main.get_node("PassengerHud") as PassengerHud
	_mode = _main.get_node("BuildMode") as BuildMode
	_finances = _main.get_node("Finances") as Finances
	_flights = _main.get_node("FlightSim") as FlightSim
	_sim = _main.get_node("PassengerSim") as PassengerSim
	await _frames(8)
	# A new game boots closed with no flight; open the airport directly (these
	# plates are about money, not staffing), which accepts the starter and issues
	# its first occurrence on the next tick, stepped by hand.
	_expect((_main.get_node("AirportGate") as AirportGate).open(), "the airport did not open")
	var starter := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	StarterFlight.advance_until(
		_main.get_node("SimClock"), func() -> bool: return _flights.flight_ids().has(starter), 200
	)
	await _frames(4)
	_hud.set_debug_open(true)
	await _frames(4)


## Puts BuildMode's pointer over a cell of the grid through its pointer_override
## hook, so the cost line prices the tool under it instead of reading whatever
## the real mouse happens to cover. A plain warp_mouse plus a motion event at
## window pixels (as hud_click_probe does) left the viewport mouse on the real
## cursor in this probe, so the hover is driven here instead.
func _point_at_world() -> void:
	var camera := _main.get_node("TycoonCamera/Camera3D") as Camera3D
	var screen := camera.unproject_position(_mode.grid.cell_to_world(DRAG_FROM))
	_mode.pointer_override = screen
	await _frames(6)
	print(
		(
			"  POINTER override=%s on_grid=%s tool=%d hovered=%s"
			% [screen, _mode.pointer_on_grid(), _mode.tool, _mode.hover_edit() != null]
		)
	)
	_expect(_mode.pointer_on_grid(), "the overridden pointer is not on the grid")


func _scene_a() -> void:
	await _point_at_world()
	_expect(
		_menu.money_label().text == "Money  20000", "a: money text '%s'" % _menu.money_label().text
	)
	_expect(_menu.card_price_text(BuildMode.Tool.FLOOR) == "25", "a: floor price")
	_expect(
		_menu.preview_label().text == "Cost 25", "a: cost line '%s'" % _menu.preview_label().text
	)
	var departures := _departures()
	var starter := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	var doors := GameCalendar.clock_text(
		_flights.state_start(starter, FlightSim.State.DOORS_CLOSED)
	)
	_expect(
		departures.text == "09:38  Oslo  Gotta Air  doors close " + doors,
		"a: departures '%s'" % departures.text
	)
	var policy := _find_label(_hud, PassengerHud.DEBUG_POLICY_TEXT)
	_expect(policy != null and policy.is_visible_in_tree(), "a: the policy label is not shown")
	if policy != null:
		_expect(
			policy.size.x <= PassengerHud.DEBUG_W + 1.0,
			"a: the policy label is wider than the panel"
		)
		print("  POLICY lines=%d rect=%s" % [policy.get_line_count(), policy.get_global_rect()])
	await _plate("a_start", _tray_cards())


func _scene_b() -> void:
	_finances.wallet.from_snapshot({"balance": "60"})
	_menu.press_card(BuildMode.Tool.DOOR)
	await _point_at_world()
	_expect(
		_menu.money_label().text == "Money  60", "b: money text '%s'" % _menu.money_label().text
	)
	_expect(
		_menu.preview_label().text == "Cost 90   Short by 30",
		"b: cost '%s'" % _menu.preview_label().text
	)
	for tool in [BuildMode.Tool.FLOOR, BuildMode.Tool.WALL]:
		_expect(_menu.card(tool).modulate == Color.WHITE, "b: card %d is greyed" % tool)
	for tool in [BuildMode.Tool.GLASS, BuildMode.Tool.DOOR]:
		_expect(
			_menu.card(tool).modulate == BuildMenu.unaffordable_tint(),
			"b: card %d not greyed" % tool
		)
		var price := _menu.card_price_label(tool)
		_expect(
			price.theme_type_variation == &"HudPrice", "b: price of card %d is not neutral" % tool
		)
		_expect(
			not price.has_theme_color_override("font_color"),
			"b: price of card %d recoloured" % tool
		)
	print(
		(
			"  CARDS prices=%s"
			% [
				[
					_menu.card_price_text(BuildMode.Tool.FLOOR),
					_menu.card_price_text(BuildMode.Tool.WALL),
					_menu.card_price_text(BuildMode.Tool.GLASS),
					_menu.card_price_text(BuildMode.Tool.DOOR)
				]
			]
		)
	)
	await _plate("b_grey", _tray_cards())


func _scene_c() -> void:
	_mode.pointer_override = Vector2(-1.0, -1.0)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	var camera := _main.get_node("TycoonCamera/Camera3D") as Camera3D
	var corners := [
		DRAG_FROM, DRAG_TO, Vector2i(DRAG_FROM.x, DRAG_TO.y), Vector2i(DRAG_TO.x, DRAG_FROM.y)
	]
	var view := root.get_visible_rect().grow(-8.0)
	var end_screen := Vector2.ZERO
	for cell: Vector2i in corners:
		var world := _mode.grid.cell_to_world(cell)
		var screen := camera.unproject_position(world)
		print("  CELL %s -> %s behind=%s" % [cell, screen, camera.is_position_behind(world)])
		_expect(not camera.is_position_behind(world), "c: cell %s is behind the camera" % cell)
		_expect(
			view.has_point(screen), "c: cell %s projects outside the window (%s)" % [cell, screen]
		)
		if cell == DRAG_TO:
			end_screen = screen
	# The pointer goes first, so no HUD control is hovered and the motion does
	# not stretch a rectangle that is not started yet.
	var motion := InputEventMouseMotion.new()
	motion.position = end_screen
	motion.global_position = end_screen
	root.push_input(motion, true)
	await _frames(4)
	_mode.begin_area(_mode.grid.cell_to_world(DRAG_FROM))
	_mode.move_area(_mode.grid.cell_to_world(DRAG_TO))
	await _frames(6)
	_expect(
		root.gui_get_hovered_control() == null,
		"c: the pointer is over %s, not the world" % root.gui_get_hovered_control()
	)
	_expect(
		_menu.preview_label().text == "Cost 300   Short by 240",
		"c: cost '%s'" % _menu.preview_label().text
	)
	_expect(
		_menu.status_label().text.contains("4 x 3"), "c: status '%s'" % _menu.status_label().text
	)
	await _plate("c_drag", [], false)
	_mode.cancel_area()
	await _frames(3)


func _scene_d() -> void:
	_finances.wallet.from_snapshot({"balance": "20000"})
	_mode.set_tool(BuildMode.Tool.NONE)
	for i in 2:
		var terms := FlightSim.STARTER_TERMS.duplicate()
		terms["id"] = "PRB%d" % i
		terms["departure_minute"] = (14 + 3 * i) * 60
		terms["destination"] = ["Rome", "Berlin"][i]
		terms["airline"] = ["Blue Fjord", "Nordic Wing"][i]
		_expect(_flights.accept_contract(terms), "d: contract %d refused" % i)
	var causes := {}
	var stages := [
		Passenger.Stage.CHECKIN_QUEUE,
		Passenger.Stage.SECURITY_QUEUE,
		Passenger.Stage.SEATED,
		Passenger.Stage.APRON
	]
	for stage in stages:
		causes[Vector2i(stage, Passenger.Stuck.NONE)] = 1
	_sim.flight_results["GMF101-d0"] = {"made": 3, "missed": 4, "causes": causes}
	_hud.show_result_for("GMF101-d0")
	await _frames(8)
	var lines := _departures().text.split("\n")
	_expect(lines.size() == 3, "d: %d departure lines" % lines.size())
	_expect(_hud.is_result_open(), "d: the result panel is closed")
	var flight := _hud.find_child("FlightPanel", true, false) as Control
	var result := _hud.find_child("FlightResultPanel", true, false) as Control
	var status_top := _menu.status_label().get_global_rect().position.y
	print(
		(
			"  GAP flight bottom=%.1f result top=%.1f result bottom=%.1f status top=%.1f"
			% [
				flight.get_global_rect().end.y,
				result.get_global_rect().position.y,
				result.get_global_rect().end.y,
				status_top
			]
		)
	)
	_expect(
		flight.get_global_rect().end.y <= result.get_global_rect().position.y,
		"d: the flight panel runs into the result panel"
	)
	_expect(
		result.get_global_rect().end.y <= status_top,
		"d: the result panel runs into the status line"
	)
	await _plate("d_three", [])
	_hud.dismiss_result()


func _departures() -> Label:
	return _hud.find_child("Departures", true, false) as Label


func _tray_cards() -> Array:
	var out: Array = []
	for tool in [
		BuildMode.Tool.FLOOR, BuildMode.Tool.WALL, BuildMode.Tool.GLASS, BuildMode.Tool.DOOR
	]:
		out.append(_menu.card(tool))
	return out


func _find_label(parent: Node, text: String) -> Label:
	for label in parent.find_children("*", "Label", true, false):
		if (label as Label).text == text:
			return label
	return null


## The on-screen rect of every visible HUD piece.
func _rects() -> Dictionary:
	var out := {}
	out["bar"] = _menu.bar().get_global_rect()
	if _menu.is_tray_open():
		out["tray"] = _menu.tray().get_global_rect()
	out["money"] = (_menu.find_child("MoneySlot", true, false) as Control).get_global_rect()
	out["flight"] = (_hud.find_child("FlightPanel", true, false) as Control).get_global_rect()
	out["debug"] = (_hud.find_child("DebugCorner", true, false) as Control).get_global_rect()
	if _menu.preview_label().visible:
		out["cost"] = _menu.preview_label().get_global_rect()
	if _menu.status_label().text != "":
		out["status"] = _menu.status_label().get_global_rect()
	if _hud.is_result_open():
		out["result"] = (
			(_hud.find_child("FlightResultPanel", true, false) as Control).get_global_rect()
		)
	var offers := _main.get_node("OfferPanel") as OfferPanel
	out["offers_button"] = offers.toggle_button().get_global_rect()
	return out


## Checks the HUD layout, proves the real mouse reaches each of `buttons`, then
## saves the plate. `mouse_to_bottom` parks the mouse over the HUD afterwards.
func _plate(label: String, buttons: Array, park_mouse := true) -> void:
	var name := "%s_%s" % [label, str(_scale).replace(".", "p")]
	var view := root.get_visible_rect()
	var rects := _rects()
	var ok := true
	print("PLATE %s scale=%s" % [name, _scale])
	for key in rects:
		var rect: Rect2 = rects[key]
		var inside := view.grow(-2.0).encloses(rect)
		print("  RECT %s %s inside=%s" % [key, rect, inside])
		ok = ok and inside
	var keys := rects.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			if (rects[keys[i]] as Rect2).intersects(rects[keys[j]]):
				print("  OVERLAP %s with %s" % [keys[i], keys[j]])
				ok = false
	print(
		(
			"  TEXT money='%s' cost='%s' status='%s'"
			% [_menu.money_label().text, _menu.preview_label().text, _menu.status_label().text]
		)
	)
	print(
		(
			"  TEXT clock='%s' departures='%s'"
			% [
				(_hud.find_child("Clock", true, false) as Label).text,
				_departures().text.replace("\n", " | ")
			]
		)
	)
	for button: Button in buttons:
		var centre := button.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = centre
		motion.global_position = centre
		root.push_input(motion, true)
		await process_frame
		await process_frame
		var hit := root.gui_get_hovered_control()
		print("  HIT %s at %s -> %s reached=%s" % [button.name, centre, hit, hit == button])
		ok = ok and hit == button
	if park_mouse:
		root.warp_mouse(Vector2(view.size.x / 2.0, view.size.y - 4.0))
	await process_frame
	if not ok:
		_invalid("%s: a rect or button check failed" % name)
		name += "_INVALID"
	await RenderingServer.frame_post_draw
	var path := _out_dir.path_join(name + ".png")
	var err := root.get_texture().get_image().save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	if err != OK:
		_invalid("%s: the plate was not saved (error %d)" % [name, err])


func _expect(condition: bool, why: String) -> void:
	if not condition:
		_invalid(why)


func _invalid(why: String) -> void:
	_failed = true
	print("PROBE_INVALID: ", why)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
