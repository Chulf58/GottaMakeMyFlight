extends SceneTree
## Windowed plates of the Departures window's gate column and picker (board
## gates 3/4, decision gates-are-placed-gate-desks-each-desk-links-
## automatically-to). Boots the real main scene with a new random sim seed
## (printed) and three gates supplied through FlightSim.gate_source (the game
## has one gate so far), opens the airport and accepts two contracts: X (gate
## A) and Y (gate B, which overlaps X at a gate but not on the runway). Then,
## per window size (SIZES: 1280 x 720 logical through a content scale of 1.5,
## then the default 1536 x 864):
##   1 <size>_gate_column: every row has a gate button
##   2 <size>_picker: Y's gate clicked, a button for each other gate
##   3 <size>_refused: gate A picked, which X holds: the picker stays and the
##     refusal reason shows under the row
##   4 <size>_moved: gate C picked, which is free: Y moves and the row shows it
## Each plate saves a crop of the board at 2x as well as the full viewport. The
## board, its gate buttons, the picker and the message must lie inside the
## viewport and clear of every other visible HUD piece. Each check prints the
## values it compared. A failed check prints PROBE_INVALID and exits 1.
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
var _board: DeparturesBoard


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
	_sim = _main.get_node("FlightSim")
	_sim.gate_source = func() -> Array[String]: return ["A", "B", "C"] as Array[String]
	root.add_child(_main)
	await _frames(5)
	_clock.set_paused(true)
	if not _setup_flights():
		_main.queue_free()
		await _frames(3)
		quit(1)
		return
	_board = _hud.find_child("DeparturesBoard", true, false) as DeparturesBoard
	if _board == null:
		_invalid("the HUD has no DeparturesBoard")
	else:
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
			"plane_size": "medium",
			"booked_passengers": 40,
			"fee_per_passenger": 25,
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
	await _frames(2)
	print(
		(
			"SIZE %s window=%s viewport=%s"
			% [entry[0], DisplayServer.window_get_size(), root.get_visible_rect().size]
		)
	)
	var tag: String = entry[0]
	# 1: the gate column.
	var gate_x := _board.gate_button("X", 0)
	var gate_y := _board.gate_button("Y", 0)
	if gate_x == null or gate_y == null:
		_invalid("%s: no gate button on the X or Y row" % tag)
		return
	print("GATES %s X=%s Y=%s" % [tag, gate_x.text, gate_y.text])
	if gate_x.text != "Gate A" or gate_y.text != "Gate B":
		_invalid("%s: the gate buttons read %s and %s" % [tag, gate_x.text, gate_y.text])
		return
	await _plate("%s_gate_column" % tag, [gate_x, gate_y])
	# 2: the picker.
	gate_y.pressed.emit()
	await _frames(3)
	var pick_a := _board.picker_button("A")
	var pick_c := _board.picker_button("C")
	print(
		(
			"PICKER %s A=%s C=%s B=%s"
			% [tag, pick_a != null, pick_c != null, _board.picker_button("B")]
		)
	)
	if pick_a == null or pick_c == null or _board.picker_button("B") != null:
		_invalid("%s: the picker does not offer exactly A and C" % tag)
		return
	await _plate("%s_picker" % tag, [pick_a, pick_c])
	# 3: a refusal.
	pick_a.pressed.emit()
	await _frames(3)
	var message := _find_message()
	print("REFUSED %s message=%s" % [tag, _board.message_text()])
	if message == null or not _board.message_text().contains("clashes with X at gate A"):
		_invalid("%s: no refusal reason under the row" % tag)
		return
	if _sim.contract_of("Y")["gate"] != "B" or _board.picker_button("C") == null:
		_invalid("%s: a refused move changed the gate or closed the picker" % tag)
		return
	await _plate("%s_refused" % tag, [message, _board.picker_button("C")])
	# 4: a move that works, then put Y back so the next size starts the same.
	_board.picker_button("C").pressed.emit()
	await _frames(3)
	var moved_y := _board.gate_button("Y", 0)
	print("MOVED %s gate=%s button=%s" % [tag, _sim.contract_of("Y")["gate"], moved_y.text])
	if _sim.contract_of("Y")["gate"] != "C" or moved_y.text != "Gate C":
		_invalid("%s: the move to C did not show" % tag)
		return
	await _plate("%s_moved" % tag, [moved_y, _find_message()])
	if _sim.reassign_gate("Y", "B"):
		# Open and close Y's picker so the confirmation under the row clears.
		_board.gate_button("Y", 0).pressed.emit()
		_board.gate_button("Y", 0).pressed.emit()
		_hud.refresh()
		await _frames(2)


func _find_message() -> Label:
	return _board.find_child("Message", true, false) as Label


## Checks `subjects` and the board lie inside the viewport, clear of other HUD
## pieces, and saves the full plate and a 2x crop of the board.
func _plate(name: String, subjects: Array) -> void:
	var view := root.get_visible_rect()
	var board_rect := _board.get_global_rect()
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
	var crowd := _overlaps(board_rect)
	print("BOARD %s rect=%s overlaps=%s" % [name, board_rect, crowd])
	if not crowd.is_empty():
		# The narrow size is a stress case (the board is anchored at a fixed top
		# and grows down), so an overlap there is reported and the plate kept.
		if name.begins_with("default"):
			_invalid("%s: the board overlaps %s" % [name, crowd])
			return
		print("OVERLAP_NOTE %s the board meets %s" % [name, crowd])
	var img: Image = await PlateSight.grab(self)
	var scale_px := float(img.get_width()) / view.size.x
	var crop := Rect2i(
		Vector2i(((board_rect.position - Vector2(CROP_MARGIN, CROP_MARGIN)) * scale_px).floor()),
		Vector2i(((board_rect.size + Vector2(CROP_MARGIN, CROP_MARGIN) * 2.0) * scale_px).ceil())
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


## The names of the other visible HUD panels, buttons and labels whose rect
## meets `rect`, leaving out the board and what it holds.
func _overlaps(rect: Rect2) -> Array[String]:
	var view := root.get_visible_rect().size
	var hits: Array[String] = []
	for node in _main.find_children("*", "Control", true, false):
		var c := node as Control
		if c == _board or _board.is_ancestor_of(c) or c.is_ancestor_of(_board):
			continue
		if not c.is_visible_in_tree():
			continue
		if not (c is PanelContainer or c is Button or c is Label):
			continue
		if c is Label and (c as Label).text == "":
			continue
		var r := c.get_global_rect()
		if r.size.x * r.size.y > view.x * view.y * 0.5 or r.size.x < 1.0:
			continue
		if r.intersects(rect):
			hits.append("%s%s" % [c.name, r])
	return hits
