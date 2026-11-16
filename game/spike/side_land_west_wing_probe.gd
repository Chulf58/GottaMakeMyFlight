extends SceneTree
## Airside all around S7c: side land opens (board airside-all-around-s7-side-
## routes-follow-the-build-each-side; decision side-land-columns-ship-locked-
## the-wide-site-grid-lands-first). One windowed run:
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/side_land_west_wing_probe.gd [-- --seed=N]
## Boots main.tscn with a new random world seed (printed), or N to replay a run,
## and declines the new-game incidents question. The starter button fills the
## starter shell (gate A, north). The probe buys the side land plot the west
## wing needs (the first plot west of the first site), builds the wing on it: a
## room west of the starter joined to the starter's airside by a corridor, with
## an exit in its west wall and a gate desk by it (gate B, west). Every cell is
## the starter offset plus a fixed step (anti_patterns 7700a92c, 25dd306b,
## 5067333e). The west spur's x before and after, whether it is pending and its
## forecast release tick are printed; the clock runs until the spur moves (the
## release tick is printed). A contract at gate B is booked and its first
## flight flown tick by tick to DEPARTED: each state's first tick, its stand's
## lane_x, the ticks its drawn plane spent on the new spur and on the old one
## (x -124, south of the lane: a control that must stay 0), and the passengers
## who left by the wing's exit are printed. Plates go under
## tools/blender/out/s7c/: the plane
## parked at the wing mid-boarding (the wing in frame) and the plane taxiing in
## on the moved spur (the old spur's line in frame). Before each save every
## framed point must project inside the window and the plane's top must have
## no mesh between it and the camera (a control under the ground must report
## one), else PROBE_INVALID, exit 1. Then it times, with side land open: the
## RepairPlan whole-grid retry with every plot owned, SpareStand.find with
## every plot owned, and SpareStand.find over a fully floored grid, which scans
## up to the north row (the nearest to a no-room scan of the whole grid).
## A guard thread ends a hang.

const MAIN := "res://main/main.tscn"
const IntroClose := preload("res://spike/intro_close.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const SITE := preload("res://build/terminal_site.tres")
const OUT_REL := "res://../tools/blender/out/s7c"
const TICKS_PER_FRAME := 40
const OPEN_LIMIT := 6000
const MOVE_LIMIT := 4000
const FLY_LIMIT := 40000
const HANG_LIMIT_MS := 60000
const TOTAL_LIMIT_MS := 900000
const MARGIN_PX := 8.0
const OCCLUSION_STOP_M := 0.3
const SETTLE_FRAMES := 40
const SECOND := "GMF702"
const SEARCH_MINUTES := 300
## The wing, the corridor and the wing's exit and desk, as steps from the
## starter offset (ReferenceTerminal cells; its west wall is at x 10, its
## airside rows 2 to 8). The wing's cells x -20 to -9 lie on the side plot
## west of the first site (x -63 to -52), so its exit's sill is at x -63.
const WING := Rect2i(-20, 4, 12, 8)
const CORRIDOR := Rect2i(-8, 7, 18, 2)
const WING_EXIT := Vector2i(-20, 8)
const WING_DESK := Vector2i(-18, 7)
## A plane is on a spur when its drawn x is this close to the spur's.
const SPUR_M := 1.0
## How far south of the lane a taxiing plane must be for the spur plate.
const SPUR_PLATE_SOUTH_M := 60.0
const FIT_DISTANCES: Array[float] = [60.0, 80.0, 110.0, 140.0, 180.0, 240.0]
const FIT_FRAMES := 4
const FIT_MARGIN_PX := 100.0
const VIEW_YAW_DEGREES := 200.0
const FINDS := 5
const MOVING: Array[int] = [
	FlightSim.State.TAXI_IN, FlightSim.State.PUSHBACK, FlightSim.State.TAXI_OUT
]

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false

var _out_dir := ""
var _main: Node
var _clock: SimClock
var _flights: FlightSim
var _staff: StaffSim
var _sim: PassengerSim
var _grid: BuildGrid
var _mode: BuildMode
var _hud: PassengerHud
var _rig: TycoonCamera
var _cam: Camera3D
var _gates: GateDesks
var _fleet: PlaneFleet
var _at := Vector2i.ZERO
var _wing_exit := 0
var _old_x := 0.0
var _new_x := 0.0
var _moved_tick := -1
## {"id", "states": {state: first tick}, "new_spur", "old_spur", "made", "spur_plate"}.
var _watch: Dictionary = {}


func _initialize() -> void:
	_beat("boot")
	_guard.start(_watchdog)
	var world_seed := IntroClose.seed_or_random()
	print("PROBE world_seed=%d" % world_seed)
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=%s" % _out_dir)
	_main = load(MAIN).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	_flights = _main.get_node("FlightSim")
	_staff = _main.get_node("Staff")
	root.add_child(_main)
	current_scene = _main
	_clock.set_paused(true)
	_run.call_deferred()


func _run() -> void:
	await _frames(3)
	_mode = _main.get_node("BuildMode")
	_grid = _mode.grid
	_hud = _main.get_node("PassengerHud")
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_gates = _main.get_node("GateDesks")
	_fleet = _main.get_node("PlaneFleet")
	_sim = _main.get_node("PassengerSim")
	var id := await _prepare()
	if id == "":
		return
	await _fly(id)
	if _done or not _report(id):
		return
	_budgets()
	print("PROBE_PASS side land west wing")
	_finish(0)


## Closes the intro, builds the wing, opens the airport, waits for the spur to
## move and books the flight. Its occurrence id, or "" (after _fail).
func _prepare() -> String:
	var intro_problem := IntroClose.close(_main)
	if intro_problem != "":
		_fail(intro_problem)
		return ""
	_clock.set_paused(true)
	_at = ReferenceTerminal.offset_on(_grid)
	print("PROBE side land open %s" % SiteDefinition.SIDE_LAND_OPEN)
	if not _build_wing() or not await _open() or not await _wait_for_move():
		return ""
	return await _book()


## Fills the starter (gate A, north), buys the side plots under the wing, then
## builds the wing and corridor in one batch and the gate desk by its exit (gate
## B, west). False (after _fail) when any of it is refused.
func _build_wing() -> bool:
	_hud.press_starter_terminal()
	if _gates.gate_ids() != ["A"]:
		_fail("the starter gate desk made no gate: %s" % _hud._status)
		return false
	_old_x = float(_gates.spur_x[StandPlacement.WEST])
	var cells := _wing_cells()
	if not _buy_under(cells.keys()):
		return false
	var edits: Array[BuildEdit] = []
	for cell: Vector2i in cells:
		edits.append(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1))
	var exit := WING_EXIT + _at
	for cell: Vector2i in cells:
		for side in 4:
			var next: Vector2i = cell + BuildGrid.SIDE_STEP[side]
			if cells.has(next) or (cell == exit and side == BuildGrid.Side.WEST):
				continue
			if _grid.floor_at(next) != BuildGrid.FLOOR_NONE:
				# The starter's west wall where the corridor meets it: opened.
				edits.append(BuildEdit.remove_wall(next, (side + 2) % 4))
				continue
			edits.append(BuildEdit.place_wall(cell, side))
	edits.append(BuildEdit.place_object(&"exit_door", exit, 3))
	var refused := 0
	for result in _grid.apply_batch(edits):
		if not result.ok:
			refused += 1
			if refused == 1:
				_fail("a wing edit was refused: %s" % result.reason_text())
	if refused > 0:
		return false
	_wing_exit = _grid.object_at(exit)
	var desk := _grid.apply(BuildEdit.place_object(GateDesks.DESK, WING_DESK + _at, 0))
	if not desk.ok:
		_fail("the wing gate desk was refused: %s" % desk.reason_text())
		return false
	return _check_gates(cells.size())


## Checks the desks made a north gate A and a west gate B on the wing's exit,
## and that the wing pushed the west spur out. False (after _fail) when not.
func _check_gates(wing_cells: int) -> bool:
	var sides := {}
	for gate: String in _gates.stands:
		sides[gate] = StandPlacement.side_of(_gates.stands[gate])
	print(
		(
			"PROBE gates %s, sides %s, wing exit %d, wing cells %d"
			% [_gates.bindings, sides, _wing_exit, wing_cells]
		)
	)
	if sides != {"A": StandPlacement.NORTH, "B": StandPlacement.WEST}:
		_fail("the desks did not make a north gate A and a west gate B")
		return false
	if _gates.binding_of("B")["exit"] != _wing_exit:
		_fail("gate B is not linked to the wing's exit")
		return false
	_new_x = float(_gates.spur_wanted[StandPlacement.WEST])
	print(
		(
			"PROBE west spur x before %.3f, wanted %.3f, pending %s, forecast release tick %d (now %d)"
			% [
				_old_x,
				_new_x,
				_flights.spur_pending(StandPlacement.WEST),
				_flights.spur_release_tick(StandPlacement.WEST),
				_clock.tick
			]
		)
	)
	if not _new_x < _old_x:
		_fail("the west wing did not push the west spur out")
		return false
	return true


## The wing's and corridor's cells (cell -> true).
func _wing_cells() -> Dictionary:
	var cells := {}
	for rect in [WING, CORRIDOR]:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				cells[Vector2i(x, y) + _at] = true
	return cells


## Buys, free, the plots under `cells`, each toward the nearest buyable plot.
func _buy_under(cells: Array) -> bool:
	var land := _mode.land_tool.land
	var wanted := {}
	for cell: Vector2i in cells:
		wanted[land.plot_of(cell)] = true
	var bought: Array[Vector2i] = []
	for plot: Vector2i in wanted:
		while not land.is_owned(plot):
			var best := Vector2i(-1, -1)
			var best_d := 1 << 30
			for candidate in land.buyable_plots():
				var d := absi(candidate.x - plot.x) + absi(candidate.y - plot.y)
				if d < best_d:
					best_d = d
					best = candidate
			var result := land.buy(best, null) if best != Vector2i(-1, -1) else null
			if result == null or not result.ok:
				_fail("the land toward plot %s could not be bought" % plot)
				return false
			bought.append(best)
	var side_plots := bought.filter(
		func(plot: Vector2i) -> bool:
			return (
				plot.x < SITE.centre_columns.x
				or plot.x >= SITE.centre_columns.x + SITE.centre_columns.y
			)
	)
	print("PROBE bought plots %s, side land among them %s" % [bought, side_plots])
	if side_plots.is_empty():
		_fail("no side land plot was bought")
		return false
	return true


## Hires a member per station and runs the clock until the airport opens.
func _open() -> bool:
	print("PROBE hired %d" % StarterFlight.hire_per_station(_sim, _staff))
	var hired_at := _clock.tick
	while _flights.opened_tick < 0:
		await _ticks(TICKS_PER_FRAME)
		if _clock.tick - hired_at > OPEN_LIMIT:
			_fail("the airport did not open %d ticks after hiring" % OPEN_LIMIT)
			return false
	print("PROBE opened at tick %d" % _flights.opened_tick)
	return true


## Runs the clock tick by tick until the west spur moves (spur_moved), and
## checks it moved to the wanted x.
func _wait_for_move() -> bool:
	if not _flights.spur_pending(StandPlacement.WEST):
		_moved_tick = _clock.tick
	else:
		_flights.spur_moved.connect(
			func(side: String) -> void:
				if side == StandPlacement.WEST and _moved_tick < 0:
					_moved_tick = _clock.tick
		)
	var limit := _clock.tick + MOVE_LIMIT
	while _moved_tick < 0:
		if _clock.tick > limit:
			_fail("the west spur did not move within %d ticks" % MOVE_LIMIT)
			return false
		_step()
		if _clock.tick % TICKS_PER_FRAME == 0:
			await _frames(1)
	var now := float(_gates.spur_x[StandPlacement.WEST])
	var stand_x := StandPlacement.lane_x_of(_gates.stands["B"])
	print(
		(
			"PROBE west spur moved at tick %d: x %.3f -> %.3f, gate B stand lane_x %.3f"
			% [_moved_tick, _old_x, now, stand_x]
		)
	)
	if not is_equal_approx(now, _new_x) or not is_equal_approx(stand_x, _new_x):
		_fail("the west spur or gate B's stand is not on the wanted x")
		return false
	return true


## Accepts a contract at gate B departing as near the starter as
## SEARCH_MINUTES allows and runs the clock until its first flight is issued.
## Its occurrence id, or "" (after _fail).
func _book() -> String:
	var minute: int = _flights.contract_of(FlightSim.DEFAULT_ID)["departure_minute"]
	var accepted := false
	for step in 2 * SEARCH_MINUTES + 1:
		var later := (step + 1) / 2 * (1 if step % 2 == 1 else -1)
		var terms := FlightSim.starter_terms(0)
		terms["id"] = SECOND
		terms["departure_minute"] = minute + later
		_beat("search %d" % later)
		if _flights.accept_gate(terms) == "B" and _flights.accept_contract(terms):
			print("PROBE %s accepted %d minutes from the starter at gate B" % [SECOND, later])
			accepted = true
			break
	if not accepted:
		_fail("no departure near the starter's got gate B")
		return ""
	var day := int(_flights.start_days[SECOND])
	var id := FlightTimetable.occurrence_id(SECOND, day)
	_sim.outcome.connect(_on_outcome)
	_watch = {"id": id, "states": {}, "new_spur": 0, "old_spur": 0, "made": 0, "spur_plate": false}
	var limit := _clock.tick + FLY_LIMIT
	while not _flights.flight_ids().has(id):
		if _clock.tick > limit:
			_fail("%s was not issued within %d ticks" % [id, FLY_LIMIT])
			return ""
		_step()
		if _clock.tick % TICKS_PER_FRAME == 0:
			await _frames(1)
	var stand := _flights.flight_stand(id)
	print(
		(
			"PROBE %s issued at tick %d at gate %s, stand lane_x %.3f"
			% [id, _clock.tick, _flights.flight_gate(id), StandPlacement.lane_x_of(stand)]
		)
	)
	if (
		_flights.flight_gate(id) != "B"
		or not is_equal_approx(StandPlacement.lane_x_of(stand), _new_x)
	):
		_fail("%s is not at gate B on the moved spur" % id)
		return ""
	return id


## Flies `id` tick by tick until it has departed, recording its states and spur
## ticks and saving the plates.
func _fly(id: String) -> void:
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var boarding := _flights.state_start(id, FlightSim.State.BOARDING)
	var closed := _flights.state_start(id, FlightSim.State.DOORS_CLOSED)
	var parked_tick := (boarding + closed) / 2
	print("PROBE parked plate at tick %d" % parked_tick)
	var limit := _clock.tick + FLY_LIMIT
	_record(id)
	while _flights.flight_ids().has(id) and _flights.state_of(id) < FlightSim.State.DEPARTED:
		if _clock.tick > limit:
			_fail("%s did not depart within %d ticks" % [id, FLY_LIMIT])
			return
		_advance()
		var spur_view := _record(id)
		if spur_view != null:
			await _frames(1)
			await _spur_plate(id, spur_view)
		elif _clock.tick == parked_tick:
			await _parked_plate(id)
		elif _clock.tick % TICKS_PER_FRAME == 0:
			await _frames(1)
		if _done:
			return
	_watch["states"][FlightSim.State.DEPARTED] = _watch["states"].get(
		FlightSim.State.DEPARTED, _clock.tick
	)


## Records `id`'s state and spur ticks at this tick. Returns its drawn plane
## when this is the tick to take the spur plate (taxiing in on the new spur, well
## south of the lane), else null.
func _record(id: String) -> PlaneView:
	_fleet.update_views()
	if not _flights.flight_ids().has(id):
		return null
	var state := _flights.state_of(id)
	if not _watch["states"].has(state):
		_watch["states"][state] = _clock.tick
		print("  STATE %s at tick %d" % [FlightSim.State.keys()[state], _clock.tick])
	if not MOVING.has(state):
		return null
	var view := _view_of_flight(id)
	if view == null:
		return null
	var x := view.global_position.x
	var south := view.global_position.z - StandPlacement.TAXI_LANE_Z
	# On a spur means south of the lane: the old spur's x is also the west
	# runway stub's, which every taxi-out runs along north of the lane.
	if south > SPUR_M and absf(x - _new_x) <= SPUR_M:
		_watch["new_spur"] += 1
	if south > SPUR_M and absf(x - _old_x) <= SPUR_M:
		_watch["old_spur"] += 1
	if (
		state == FlightSim.State.TAXI_IN
		and not _watch["spur_plate"]
		and absf(x - _new_x) <= SPUR_M
		and south >= SPUR_PLATE_SOUTH_M
	):
		_watch["spur_plate"] = true
		return view
	return null


func _on_outcome(passenger_id: int, made: bool) -> void:
	var p := _sim.get_passenger(passenger_id)
	if p == null or not made or _watch.is_empty() or p.flight_id != _watch["id"]:
		return
	if p.exit_object == _wing_exit:
		_watch["made"] += 1


## Prints each state's first tick and the spur counts; false (after _fail) when
## a state was skipped, the plane was never on the new spur, or it was on the
## old one.
func _report(id: String) -> bool:
	var states: Dictionary = _watch["states"]
	var line := PackedStringArray()
	var ok := true
	for state in range(FlightSim.State.SCHEDULED, FlightSim.State.DEPARTED + 1):
		line.append("%s %d" % [FlightSim.State.keys()[state], int(states.get(state, -1))])
		if state >= FlightSim.State.APPROACH:
			ok = ok and states.has(state)
	print("PROBE %s states: %s" % [id, ", ".join(line)])
	print(
		(
			(
				"PROBE %s on the new spur (x %.3f) %d ticks, on the old spur (x %.3f) %d ticks,"
				+ " passengers out of the wing exit %d"
			)
			% [id, _new_x, _watch["new_spur"], _old_x, _watch["old_spur"], _watch["made"]]
		)
	)
	ok = ok and _watch["new_spur"] > 0 and _watch["old_spur"] == 0 and _watch["spur_plate"]
	if not ok:
		_fail("a state was skipped, the plane was not on the new spur, or it used the old one")
	return ok


## Times, with side land open, the work that grows with the land a player owns.
func _budgets() -> void:
	_beat("budget repair")
	var all_land := LandPlots.for_site(SITE)
	all_land._owned.fill(1)
	var bought_out := SiteGrid.new(SITE)
	bought_out.land = all_land
	var whole := Rect2i(Vector2i.ZERO, bought_out.size)
	var started := Time.get_ticks_usec()
	var made := RepairPlan._made_on(bought_out, whole, SITE, {}, all_land)
	var repair_ms := (Time.get_ticks_usec() - started) / 1000.0
	print(
		(
			"BUDGET RepairPlan whole-grid retry, every plot owned: %.0f ms ok %s (S6: 7101 ms)"
			% [repair_ms, made.ok]
		)
	)
	_beat("budget spare")
	var starter := SiteGrid.new(SITE)
	starter.land = all_land
	StarterShell.place(starter, SITE.starter_offset)
	var stands: Array[Dictionary] = [StandPlacement.starter_stand(starter, SITE)]
	var spare := {}
	started = Time.get_ticks_usec()
	for i in FINDS:
		spare = SpareStand.find(starter, stands, PlaneClasses.SMALL)
	var find_ms := (Time.get_ticks_usec() - started) / 1000.0 / FINDS
	print(
		(
			"BUDGET SpareStand.find, starter, every plot owned: %.3f ms found %s (S6: 11.8 ms)"
			% [find_ms, not spare.is_empty()]
		)
	)
	_beat("budget no room")
	var floored := SiteGrid.new(SITE)
	floored.land = all_land
	var edits: Array[BuildEdit] = []
	for y in floored.size.y:
		for x in floored.size.x:
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	floored.apply_batch(edits)
	_beat("budget no room scan")
	started = Time.get_ticks_usec()
	# Every envelope over the floor is blocked, so the scan runs from the south
	# row up to the north rows, whose envelopes lie north of the grid: the
	# nearest to a no-room scan of the whole owned grid.
	var north := SpareStand.find(floored, [] as Array[Dictionary], PlaneClasses.SMALL)
	var north_ms := (Time.get_ticks_usec() - started) / 1000.0
	print(
		(
			(
				"BUDGET SpareStand.find over %d cells floored and owned: %.1f ms, first fit %s"
				+ " (S5 no-room scan on the first site's land: about 255 ms, cached)"
			)
			% [floored.size.x * floored.size.y, north_ms, north]
		)
	)


## The parked plate: the plane at the wing's stand mid-boarding, with the
## wing's corners in frame.
func _parked_plate(id: String) -> void:
	var view := _view_of_flight(id)
	if view == null:
		_fail("parked: %s is not drawn at tick %d" % [id, _clock.tick])
		return
	var box := _aabb_of(view)
	var framed := _corners(box)
	for corner in [WING.position, Vector2i(WING.position.x, WING.end.y), WING.end]:
		var at := _grid.cell_to_world(corner + _at)
		framed.append(Vector3(at.x, SITE.grid_origin.y, at.z))
	await _plate_of("west_wing_parked_%s" % id, id, view, framed)


## The spur plate: the plane taxiing in on the moved spur, with the old spur's
## line beside it in frame.
func _spur_plate(id: String, view: PlaneView) -> void:
	var box := _aabb_of(view)
	var framed := _corners(box)
	framed.append(Vector3(_old_x, 0.0, view.global_position.z))
	framed.append(Vector3(_new_x, 0.0, view.global_position.z + 30.0))
	await _plate_of("moved_spur_taxi_in_%s" % id, id, view, framed)


func _plate_of(label: String, id: String, view: PlaneView, framed: Array) -> void:
	var box := _aabb_of(view)
	if not box.has_volume():
		_fail("%s: %s is drawn with no mesh" % [label, id])
		return
	var top := box.get_center() + Vector3.UP * box.size.y * 0.5
	print(
		(
			"PROBE plate %s: %s in state %s at %s"
			% [label, id, FlightSim.State.keys()[_flights.state_of(id)], view.global_position]
		)
	)
	await _fit(framed)
	await _plate(label, framed, [top, view])


func _fit(points: Array) -> void:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point: Vector3 in points:
		low = Vector2(minf(low.x, point.x), minf(low.y, point.z))
		high = Vector2(maxf(high.x, point.x), maxf(high.y, point.z))
	var middle := (low + high) * 0.5
	var frame := root.get_visible_rect().grow(-FIT_MARGIN_PX)
	for distance in FIT_DISTANCES:
		_rig.position = Vector3(middle.x, 0.0, middle.y)
		_rig.yaw = deg_to_rad(VIEW_YAW_DEGREES)
		_rig.distance = distance
		_rig.zoom(1.0)
		await _frames(FIT_FRAMES)
		var fits := true
		for point: Vector3 in points:
			if (
				_cam.is_position_behind(point)
				or not frame.has_point(_cam.unproject_position(point))
			):
				fits = false
				break
		print("  FIT distance %.0f fits=%s" % [distance, fits])
		if fits:
			return


func _aabb_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for found in node.find_children("*", "MeshInstance3D", true, false):
		var instance := found as MeshInstance3D
		if instance.mesh == null or not instance.is_visible_in_tree():
			continue
		var bounds: AABB = instance.global_transform * instance.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	return box


func _corners(box: AABB) -> Array:
	var out: Array = []
	for i in 8:
		out.append(box.get_endpoint(i))
	return out


func _view_of_flight(id: String) -> PlaneView:
	for view in _fleet.views:
		if view.flight_id == id and view.visible:
			return view
	return null


## Saves a plate once every `framed` point and the `on_plane` point ([point,
## its PlaneView]) project inside the window and no mesh but the plane's own
## hides that point.
func _plate(label: String, framed: Array, on_plane: Array) -> void:
	_stage = "plate %s" % label
	await _frames(SETTLE_FRAMES)
	var view := root.get_visible_rect()
	print(
		(
			"PLATE %s rig %s distance %.1f camera %s"
			% [label, _rig.position, _rig.distance, _cam.global_position]
		)
	)
	var control := _occluder(Vector3(-27.0, -2.0, -90.0))
	print("  CONTROL under the ground: %s" % (control if control != "" else "clear"))
	if control == "":
		_fail("%s: the occlusion control found nothing" % label)
		return
	var ok := true
	var points: Array = framed.duplicate()
	points.append(on_plane[0])
	for point: Vector3 in points:
		var p := _cam.unproject_position(point)
		var in_frame := view.grow(-MARGIN_PX).has_point(p) and not _cam.is_position_behind(point)
		print("  FRAMED %s -> %s in_frame=%s" % [point, p, in_frame])
		ok = ok and in_frame
	var occluder := _occluder(on_plane[0], on_plane[1])
	print("  OCCLUSION plane %s: %s" % [on_plane[0], occluder if occluder != "" else "clear"])
	ok = ok and occluder == ""
	if not ok:
		_fail("%s: a subject check failed" % label)
		return
	await RenderingServer.frame_post_draw
	var path := _out_dir.path_join(label + ".png")
	var err := root.get_texture().get_image().save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	if err != OK:
		_fail("%s: not saved" % label)


func _occluder(subject: Vector3, own: Node = null) -> String:
	var from := _cam.global_position
	var to := subject + (from - subject).normalized() * OCCLUSION_STOP_M
	var ghost := _main.get_node("BuildMode/Ghost")
	var best := ""
	var best_distance := INF
	for node in _main.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null or not instance.is_visible_in_tree() or ghost.is_ancestor_of(node):
			continue
		if own != null and own.is_ancestor_of(node):
			continue
		var material := instance.material_override
		if material == null and instance.mesh.get_surface_count() > 0:
			material = instance.get_active_material(0)
		var base := material as BaseMaterial3D
		if base != null and base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var xform := instance.global_transform
		if (xform * instance.get_aabb()).intersects_segment(from, to) == null:
			continue
		var inverse := xform.affine_inverse()
		var hit: Dictionary = instance.mesh.generate_triangle_mesh().intersect_segment(
			inverse * from, inverse * to
		)
		if hit.is_empty():
			continue
		var world_hit: Vector3 = xform * (hit["position"] as Vector3)
		var distance := from.distance_to(world_hit)
		if distance < best_distance:
			best_distance = distance
			best = "%s at %s" % [instance.get_path(), world_hit]
	return best


func _step() -> void:
	_advance()


func _advance() -> void:
	_clock.set_paused(false)
	_clock.advance(SimClock.STEP)
	_clock.set_paused(true)
	_beat("tick %d" % _clock.tick)


func _ticks(count: int) -> void:
	for i in count:
		_advance()
	await process_frame


func _frames(count: int) -> void:
	for i in count:
		_beat(_stage)
		await process_frame


func _beat(stage: String) -> void:
	_mutex.lock()
	_beat_ms = Time.get_ticks_msec()
	_stage = stage
	_mutex.unlock()


func _watchdog() -> void:
	var started := Time.get_ticks_msec()
	while true:
		OS.delay_msec(500)
		_mutex.lock()
		var done := _done
		var beat := _beat_ms
		var stage := _stage
		_mutex.unlock()
		if done:
			return
		var now := Time.get_ticks_msec()
		if now - beat > HANG_LIMIT_MS or now - started > TOTAL_LIMIT_MS:
			print(
				(
					"PROBE_INVALID hang in stage '%s': %d ms since the last beat, %d ms in all"
					% [stage, now - beat, now - started]
				)
			)
			OS.crash("side land west wing probe hung")


func _fail(reason: String) -> void:
	print("PROBE_INVALID %s" % reason)
	_finish(1)


func _finish(code: int) -> void:
	_mutex.lock()
	_done = true
	_mutex.unlock()
	if _guard.is_started():
		_guard.wait_to_finish()
	if _main != null:
		_main.queue_free()
	quit(code)
