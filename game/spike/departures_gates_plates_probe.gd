extends SceneTree
## Windowed plates of FlightPlanner's gate rows and Move-to actions (board
## gates 3/4, decision departures-live-ops-drawer-and-actionable-on-time-hud-stat).
## Boots the real main scene with a new random sim seed (printed) and three gates
## supplied through FlightSim.gate_source (the game has one gate so far), opens
## the airport and accepts two contracts: X (gate A) and Y (gate B, which
## overlaps X at a gate but not on the runway). Then, per window size (SIZES:
## 1280 x 720 logical through a content scale of 1.5, then the default 1536 x 864):
##   1 <size>_gate_rows: X and Y bars appear on their gate rows
##   2 <size>_actions: Y's bar clicked, Move to C offered while clashed gate A is not
##   3 <size>_moved: gate C picked, which is free: Y moves and the message shows it
## Each plate saves a crop of the planner sheet at 2x as well as the full viewport.
## The sheet, its bars, the move choice, and the message must lie inside the
## viewport (matching the FlightPlanner full-screen overlay). Each check prints
## the values it compared. A failed check prints PROBE_INVALID and exits 1.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/departures_gates_plates_probe.gd
##
## Plates go to tools/blender/out/departures-gates/.

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/departures-gates"
const MAIN_SCENE := "res://main/main.tscn"
const SETTINGS := "user://departures_gates_probe.cfg"
const MARGIN_PX := 4.0
const CROP_MARGIN := 12
const SIZES := [["1280", Vector2i(1920, 1080), 1.5], ["default", Vector2i(1920, 1080), 1.25]]

var _out_dir := ""
var _failed := false
var _main: Node
var _clock: SimClock
var _hud: PassengerHud
var _sim: FlightSim
var _planner: FlightPlanner


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	(_main.get_node("BuildMode") as BuildMode).starter_shell = false
	(_main.get_node("BuildMenu") as BuildMenu).grant_hold_s = 0.5
	_hud = _main.get_node("PassengerHud")
	_hud.departures_settings_path = SETTINGS
	root.add_child(_main)
	await _frames(5)
	_sim = _main.get_node("FlightSim")
	_sim.gate_source = func() -> Array[String]: return ["A", "B", "C"] as Array[String]
	_sim.stand_source = Callable()
	_clock.set_paused(true)
	if not _setup_flights():
		_main.queue_free()
		await _frames(3)
		quit(1)
		return
	_planner = _main.find_child("FlightPlanner", true, false) as FlightPlanner
	if _planner == null:
		_invalid("the scene has no FlightPlanner")
	else:
		_planner.open()
		await _frames(3)
		for entry in SIZES:
			if _failed:
				break
			await _size(entry)
	_main.queue_free()
	await _frames(3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _setup_flights() -> bool:
	print("FLIGHTS before: contracts=%s opened=%d" % [_sim.contract_ids(), _sim.opened_tick])
	if _sim.opened_tick < 0:
		_sim.open_airport()
	for spec: Array in [["X", 600, "Oslo"], ["Y", 660, "Rome"]]:
		var terms := {
			"id": spec[0],
			"airline": "Gotta Air",
			"destination": spec[2],
			"departure_minute": spec[1],
			"plane_size": "small",
			"booked_passengers": 6,
			"fee_per_passenger": 50,
		}
		if not _sim.accept_contract(terms):
			_invalid("contract %s refused: %s" % [spec[0], _sim.accept_problem(terms)])
			return false
	print(
		(
			"FLIGHTS gates X=%s Y=%s all=%s"
			% [_sim.contract_of("X")["gate"], _sim.contract_of("Y")["gate"], _sim.gate_ids()]
		)
	)
	return _sim.contract_of("X")["gate"] == "A" and _sim.contract_of("Y")["gate"] == "B"


func _size(entry: Array) -> void:
	DisplayServer.window_set_size(entry[1])
	root.content_scale_factor = entry[2]
	await _frames(4)
	_hud.refresh()
	_planner.refresh()
	await _frames(2)
	print(
		(
			"SIZE %s window=%s viewport=%s"
			% [entry[0], DisplayServer.window_get_size(), root.get_visible_rect().size]
		)
	)
	var tag: String = entry[0]
	# 1: the gate rows and bars.
	var bar_x := _planner.bar_button("X", 0)
	var bar_y := _planner.bar_button("Y", 0)
	if bar_x == null or bar_y == null:
		_invalid("%s: missing X or Y bar in FlightPlanner" % tag)
		return
	print("GATES %s rows=%s" % [tag, _planner.row_gates()])
	await _plate("%s_gate_rows" % tag, [bar_x, bar_y])
	# 2: Move choices (C fits, A clashes).
	bar_y.pressed.emit()
	await _frames(3)
	var move_a := _planner.part("Move_A") as Button
	var move_c := _planner.part("Move_C") as Button
	print(
		(
			"ACTIONS %s A_disabled=%s C_enabled=%s"
			% [tag, move_a != null and move_a.disabled, move_c != null and not move_c.disabled]
		)
	)
	if move_a == null or not move_a.disabled or move_c == null or move_c.disabled:
		_invalid("%s: FlightPlanner did not offer enabled Move_C with disabled Move_A" % tag)
		return
	await _plate("%s_actions" % tag, [move_c])
	# 3: a move that works, then put Y back so the next size starts the same.
	move_c.pressed.emit()
	await _frames(3)
	var moved_y := _planner.bar_button("Y", 0)
	var message := _find_message()
	print(
		(
			"MOVED %s gate=%s message=%s"
			% [tag, _sim.contract_of("Y")["gate"], _planner.message_text()]
		)
	)
	if _sim.contract_of("Y")["gate"] != "C" or moved_y == null or message == null:
		_invalid("%s: the move to C did not show" % tag)
		return
	await _plate("%s_moved" % tag, [moved_y, message])
	if _sim.reassign_gate("Y", "B"):
		_planner.close()
		_planner.open()
		await _frames(2)


func _find_message() -> Label:
	return _planner.part("PlannerMessage") as Label


## Checks `subjects` and the sheet lie inside the viewport, and saves the
## full plate and a 2x crop of the sheet.
func _plate(name: String, subjects: Array) -> void:
	var view := root.get_visible_rect()
	var sheet_rect := _planner.sheet().get_global_rect()
	for node: Control in subjects:
		if node == null or not node.is_visible_in_tree():
			_invalid("%s: a subject is missing or hidden" % name)
			return
		var r := node.get_global_rect()
		var inside := view.grow(-MARGIN_PX).encloses(r)
		print("IN_FRAME %s %s rect=%s viewport=%s inside=%s" % [name, node.name, r, view, inside])
		if not inside or r.size.x < 8.0 or r.size.y < 8.0:
			_invalid("%s: %s is not in frame" % [name, node.name])
			return
	if not view.encloses(sheet_rect):
		_invalid("%s: planner sheet %s leaves viewport %s" % [name, sheet_rect, view])
		return
	var img: Image = await PlateSight.grab(self)
	var scale_px := float(img.get_width()) / view.size.x
	var crop := Rect2i(
		Vector2i(((sheet_rect.position - Vector2(CROP_MARGIN, CROP_MARGIN)) * scale_px).floor()),
		Vector2i(((sheet_rect.size + Vector2(CROP_MARGIN, CROP_MARGIN) * 2.0) * scale_px).ceil())
	)
	crop = crop.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var piece := img.get_region(crop)
	piece.resize(piece.get_width() * 2, piece.get_height() * 2, Image.INTERPOLATE_NEAREST)
	for pair in [[name, img], [name + "_crop", piece]]:
		var path := _out_dir.path_join(pair[0] + ".png")
		var err: int = pair[1].save_png(path)
		if err != OK:
			_invalid("could not save %s (error %d)" % [path, err])
			return
		print("PLATE saved %s size=%s" % [path, pair[1].get_size()])
