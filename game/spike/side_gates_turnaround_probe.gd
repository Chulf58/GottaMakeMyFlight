extends SceneTree
## Airside all around S5: a full turnaround at a west gate and at an east gate,
## played by the real game (board airside-all-around-s5-gates-on-west-and-east-
## exits-gatedesks; design airside-all-around-technical-design-one-route-
## source-per-con). One windowed run:
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/side_gates_turnaround_probe.gd [-- --seed=N]
## Boots main.tscn with a new random world seed (printed), or N to replay a run,
## and declines the new-game incidents question. Every cell comes from
## ReferenceTerminal plus the site's starter offset (anti_patterns 7700a92c,
## 25dd306b, 5067333e): in one batch it opens an exit in the starter shell's east
## wall at (21, 4) and one in its west wall at (10, 8); then the starter button
## fills the interior and puts the gate desk at (19, 5), which links to the east
## exit (2 cells, the north exit is 3), so gate A is east; a second desk at
## (12, 7) links to the west exit, so gate B is west. One staff member per
## station is hired (a cashier per shop counter). The starter flies at gate A;
## a second contract at gate B departs as near the starter as it can. When that
## day plans no taxi pause, a third contract (any gate, within SEARCH_MINUTES of
## the starter) is accepted with which FlightSim plans one (a scratch FlightSim
## run ahead finds it). Every contract's occurrence of their first common day is
## flown. Both occurrences of
## that day are flown tick by tick to DEPARTED: the states each reaches, how
## many ticks its drawn plane spent on its side's spur (x within SPUR_M of
## -124 or 124), the passengers who made it out of its gate's exit, and the
## pause's ticks (the plane must stay within STOPPED_M of the hold) are printed;
## every count must be positive. Plates go under tools/blender/out/s5-gates/:
## each plane parked at its stand mid-boarding, and the paused plane mid-pause.
## Before each save every corner of the subject plane's box must project inside
## the window and its top must have no mesh between it and the camera (a control
## under the ground must report one), with the HUD layers hidden, else
## PROBE_INVALID, exit 1. A guard thread ends a hang.

const MAIN := "res://main/main.tscn"
const IntroClose := preload("res://spike/intro_close.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/s5-gates"
const TICKS_PER_FRAME := 40
const OPEN_LIMIT := 6000
const FLY_LIMIT := 40000
const HANG_LIMIT_MS := 60000
const TOTAL_LIMIT_MS := 600000
const MARGIN_PX := 8.0
const OCCLUSION_STOP_M := 0.3
const SETTLE_FRAMES := 40
const SECOND := "GMF202"
const THIRD := "GMF303"
## How many minutes before and after the starter's departure the second
## contract's departure is searched.
const SEARCH_MINUTES := 300
## ReferenceTerminal cells: the east and west exits and the west gate desk.
const EAST_EXIT := Vector2i(21, 4)
const WEST_EXIT := Vector2i(10, 8)
const WEST_DESK := Vector2i(12, 7)
## A plane is on its spur when its drawn x is this close to the spur's.
const SPUR_M := 1.0
const STOPPED_M := 0.05
const FIT_DISTANCES: Array[float] = [60.0, 80.0, 110.0, 140.0, 180.0, 240.0]
const FIT_FRAMES := 4
const FIT_MARGIN_PX := 100.0
const VIEW_YAW_DEGREES := 200.0
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
var _airside: Airside
## Flight id -> {"gate", "side", "states": {state: true}, "spur_ticks",
## "made", "exit"}.
var _watch: Dictionary = {}
## {"id", "hold", "from", "to", "held", "drift"} of the planned pause.
var _pause: Dictionary = {}


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
	_airside = _main.get_node("Airside")
	_sim = _main.get_node("PassengerSim")
	var intro_problem := IntroClose.close(_main)
	if intro_problem != "":
		_fail(intro_problem)
		return
	_clock.set_paused(true)
	if not _build_gates():
		return
	if not await _open():
		return
	var ids: Array[String] = await _book()
	if ids.is_empty() or not _find_pause(ids):
		return
	await _fly(ids)
	if _done:
		return
	if _report():
		print("PROBE_PASS side gates turnaround")
		_finish(0)


## Accepts the second contract (and the third when needed), runs the clock
## until each contract's occurrence of their first common day is issued and
## sets up _watch for them. Their ids, or none (after _fail).
func _book() -> Array[String]:
	var ids: Array[String] = []
	var contracts: Array[String] = [FlightSim.DEFAULT_ID]
	if not _accept(SECOND, "B", contracts, false):
		return ids
	contracts.append(SECOND)
	if not _pauses_with(_flights.to_snapshot(), {}, contracts):
		if not _accept(THIRD, "", contracts, true):
			return ids
		contracts.append(THIRD)
	var day := _day_of(_flights, contracts)
	for contract_id in contracts:
		ids.append(FlightTimetable.occurrence_id(contract_id, day))
	print("PROBE contracts %s, watched flights %s on day %d" % [contracts, ids, day])
	# Watched from now, tick by tick, so each flight's states are seen from its
	# issue on; its gate is filled in when it is issued.
	_sim.outcome.connect(_on_outcome)
	for id: String in ids:
		_watch[id] = {"gate": "", "side": "", "exit": 0, "states": {}, "spur_ticks": 0, "made": 0}
	var limit := _clock.tick + FLY_LIMIT
	while not ids.all(func(id: String) -> bool: return _flights.flight_ids().has(id)):
		if _clock.tick > limit:
			_fail("the flights %s were not issued within %d ticks" % [ids, FLY_LIMIT])
			return [] as Array[String]
		_step()
		if _clock.tick % TICKS_PER_FRAME == 0:
			await _frames(1)
	return ids


## Checks the gates' sides, hires a member per station and runs the clock
## until the airport opens. False (after _fail) when it does not.
func _open() -> bool:
	var sides := {}
	for gate: String in _gates.stands:
		sides[gate] = StandPlacement.side_of(_gates.stands[gate])
	print("PROBE gates %s, sides %s, classes %s" % [_gates.bindings, sides, _gates.classes])
	if sides != {"A": StandPlacement.EAST, "B": StandPlacement.WEST}:
		_fail("the desks did not make an east gate A and a west gate B")
		return false
	var hired := StarterFlight.hire_per_station(_sim, _staff)
	print("PROBE hired %d" % hired)
	var hired_at := _clock.tick
	while _flights.opened_tick < 0:
		await _ticks(TICKS_PER_FRAME)
		if _clock.tick - hired_at > OPEN_LIMIT:
			_fail("the airport did not open %d ticks after hiring" % OPEN_LIMIT)
			return false
	return true


## Opens the east and west exits in one batch, fills the starter terminal (its
## gate desk links east), and places the west desk. False (after _fail) when
## any of it is refused.
func _build_gates() -> bool:
	var at := ReferenceTerminal.offset_on(_grid)
	var edits: Array[BuildEdit] = [
		BuildEdit.remove_wall(EAST_EXIT + at, BuildGrid.Side.EAST),
		BuildEdit.place_object(&"exit_door", EAST_EXIT + at, 1),
		BuildEdit.remove_wall(WEST_EXIT + at, BuildGrid.Side.WEST),
		BuildEdit.place_object(&"exit_door", WEST_EXIT + at, 3),
	]
	for result in _grid.apply_batch(edits):
		if not result.ok:
			_fail("a side exit was refused: %s" % result.reason_text())
			return false
	_hud.press_starter_terminal()
	if _gates.gate_ids() != ["A"]:
		_fail("the starter gate desk made no gate: %s" % _hud._status)
		return false
	var desk := _grid.apply(BuildEdit.place_object(GateDesks.DESK, WEST_DESK + at, 0))
	if not desk.ok:
		_fail("the west gate desk was refused: %s" % desk.reason_text())
		return false
	return true


## Accepts contract `id` (the starter's terms) departing as few minutes from
## the starter as SEARCH_MINUTES allows, at gate `gate` ("" for any), and with
## `need_pause` only on terms with which FlightSim plans a taxi pause for one
## of the day's occurrences of `contracts` or `id` (_pauses_with()).
func _accept(id: String, gate: String, contracts: Array[String], need_pause: bool) -> bool:
	var minute: int = _flights.contract_of(FlightSim.DEFAULT_ID)["departure_minute"]
	var save := _flights.to_snapshot()
	var gates := {}
	for step in 2 * SEARCH_MINUTES + 1:
		var later := (step + 1) / 2 * (1 if step % 2 == 1 else -1)
		var terms := FlightSim.starter_terms(0)
		terms["id"] = id
		terms["departure_minute"] = minute + later
		_beat("search %s %d" % [id, later])
		var got := _flights.accept_gate(terms)
		gates[got] = int(gates.get(got, 0)) + 1
		if got == "" or (gate != "" and got != gate):
			continue
		if need_pause and not _pauses_with(save, terms, contracts):
			continue
		if not _flights.accept_contract(terms):
			continue
		print("PROBE %s accepted %d minutes from the starter at gate %s" % [id, later, got])
		return true
	_fail(
		"%s: no departure fit (gate '%s', pause %s); gates got %s" % [id, gate, need_pause, gates]
	)
	return false


## The first day every contract of `contracts` flies on `sim`.
static func _day_of(sim: FlightSim, contracts: Array) -> int:
	var day := 0
	for contract_id: String in contracts:
		day = maxi(day, int(sim.start_days[contract_id]))
	return day


## Whether a scratch FlightSim loaded from `save`, given `terms` (none when
## empty), plans a taxi pause for one occurrence of `contracts` (and `terms`)
## on their first common day, run ahead until each is issued.
func _pauses_with(save: Dictionary, terms: Dictionary, contracts: Array[String]) -> bool:
	var scratch := FlightSim.new()
	scratch.gate_source = _flights.gate_source
	scratch.stand_source = _flights.stand_source
	var found := false
	var all := contracts.duplicate()
	if not terms.is_empty():
		all.append(terms["id"])
	var ready := scratch.from_snapshot(save.duplicate(true))
	if ready and not terms.is_empty():
		ready = scratch.accept_contract(terms)
	if ready:
		var day := _day_of(scratch, all)
		var issue := 0
		for contract_id: String in all:
			issue = maxi(issue, FlightTimetable.issue_tick(scratch.contract_of(contract_id), day))
		for t in range(scratch.tick + 1, issue + 1):
			scratch.on_tick(t)
		for contract_id: String in all:
			var plan := scratch.taxi_plan(FlightTimetable.occurrence_id(contract_id, day))
			for pause: Dictionary in plan.values():
				found = found or not pause.is_empty()
	scratch.free()
	return found


## Sets _pause from the first of `ids` whose taxi plan holds a pause.
func _find_pause(ids: Array) -> bool:
	for id: String in ids:
		var plan := _flights.taxi_plan(id)
		for state: int in plan:
			var pause: Dictionary = plan[state]
			if pause.is_empty():
				continue
			var gate := _flights.flight_gate(id)
			var plane_class: String = (
				_flights.contract_of(_flights.flight_contract_id(id))["plane_size"]
			)
			var route := _airside.phase_path(state, gate, plane_class)
			var start := _flights.state_start(id, state)
			var budget := float(_flights.state_start(id, state + 1) - start)
			var moved := MovementPlan.taxi(route, budget, pause)
			var from := ceili(start + float(moved["t1"]))
			_pause = {
				"id": id,
				"state": state,
				"hold": MovementPlan.point_at(route, pause["hold_s"]),
				"from": from,
				"to": from + int(moved["pause_ticks"]) - 1,
				"planned": int(moved["pause_ticks"]),
				"held": 0,
				"drift": 0.0,
			}
			print("PROBE hold point %s on the route of gate %s" % [_pause["hold"], gate])
			print(
				(
					"PROBE %s pauses in state %d: %s, ticks %d to %d"
					% [id, state, pause, from, _pause["to"]]
				)
			)
			return true
	_fail("neither %s has a planned pause" % [ids])
	return false


## Flies `ids` tick by tick until both have departed, recording what _watch
## and _pause hold and saving the plates on their ticks.
func _fly(ids: Array) -> void:
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var plates := {}
	for id: String in ids:
		var boarding := _flights.state_start(id, FlightSim.State.BOARDING)
		var closed := _flights.state_start(id, FlightSim.State.DOORS_CLOSED)
		var label := "parked_%s_%s_%s" % [_watch[id]["gate"], _watch[id]["side"], id]
		plates[(boarding + closed) / 2] = [label, id]
	var middle: int = (int(_pause["from"]) + int(_pause["to"])) / 2
	plates[middle] = ["pause_middle", _pause["id"]]
	print("PROBE plate ticks %s" % [plates])
	var limit := _clock.tick + FLY_LIMIT
	while not ids.all(func(id: String) -> bool: return _departed(id)):
		if _clock.tick > limit:
			_fail("the flights did not depart within %d ticks" % FLY_LIMIT)
			return
		_advance()
		if _near_pause():
			await _frames(1)
		_record()
		if plates.has(_clock.tick):
			var plate: Array = plates[_clock.tick]
			await _plate_of(plate[0], plate[1])
			if _done:
				return
		elif _clock.tick % TICKS_PER_FRAME == 0:
			await _frames(1)


func _departed(id: String) -> bool:
	return not _flights.flight_ids().has(id) or _flights.state_of(id) >= FlightSim.State.DEPARTED


## One tick, then _record().
func _step() -> void:
	_advance()
	_record()


func _advance() -> void:
	_clock.set_paused(false)
	_clock.advance(SimClock.STEP)
	_clock.set_paused(true)
	_beat("tick %d" % _clock.tick)


## Whether the clock is within a few ticks of the pause, where the drawn plane
## must be measured after a frame (PlaneView moves in its own _process).
func _near_pause() -> bool:
	return (
		not _pause.is_empty()
		and _clock.tick >= int(_pause["from"]) - 2
		and _clock.tick <= int(_pause["to"]) + 1
	)


## Each watched flight's state, spur time and pause hold at this tick.
func _record() -> void:
	_fleet.update_views()
	for id: String in _watch:
		if not _flights.flight_ids().has(id):
			continue
		if _watch[id]["gate"] == "":
			var gate := _flights.flight_gate(id)
			_watch[id]["gate"] = gate
			_watch[id]["side"] = StandPlacement.side_of(_gates.stands[gate])
			_watch[id]["exit"] = _gates.binding_of(gate)["exit"]
		var state := _flights.state_of(id)
		_watch[id]["states"][state] = true
		if not MOVING.has(state):
			continue
		var view := _view_of_flight(id)
		if view == null:
			continue
		var spur_x := StandPlacement.SIDE_LANE_X
		if _watch[id]["side"] == StandPlacement.WEST:
			spur_x = -spur_x
		if absf(view.global_position.x - spur_x) <= SPUR_M:
			_watch[id]["spur_ticks"] += 1
		if _pause.is_empty() or id != _pause["id"]:
			continue
		if _clock.tick >= _pause["from"] and _clock.tick <= _pause["to"]:
			var hold: Vector3 = _pause["hold"]
			var off := Vector2(view.global_position.x - hold.x, view.global_position.z - hold.z)
			_pause["drift"] = maxf(_pause["drift"], off.length())
			_pause["held"] += 1
			print(
				(
					"  HOLD tick %d at %s, %.4f m from the hold"
					% [_clock.tick, view.global_position, off.length()]
				)
			)


func _on_outcome(id: int, made: bool) -> void:
	var p := _sim.get_passenger(id)
	if p == null or not made or not _watch.has(p.flight_id):
		return
	if p.exit_object == _watch[p.flight_id]["exit"]:
		_watch[p.flight_id]["made"] += 1


## Prints what each flight reached; false (after _fail) when a count is not
## positive, a state was skipped or the paused plane drifted off its hold.
func _report() -> bool:
	print(
		(
			"PROBE pause %s held %d of %d planned ticks (%d to %d), largest drift %.4f m"
			% [
				_pause["id"],
				_pause["held"],
				_pause["planned"],
				_pause["from"],
				_pause["to"],
				_pause["drift"],
			]
		)
	)
	var ok: bool = _pause["held"] == _pause["planned"] and _pause["held"] > 0
	ok = ok and _pause["drift"] <= STOPPED_M
	for id: String in _watch:
		var entry: Dictionary = _watch[id]
		var reached: Array = (entry["states"] as Dictionary).keys()
		reached.sort()
		var names := PackedStringArray()
		for state: int in reached:
			names.append(FlightSim.State.keys()[state])
		print(
			(
				"PROBE %s gate %s (%s): states %s, spur ticks %d, made out of its exit %d"
				% [
					id,
					entry["gate"],
					entry["side"],
					", ".join(names),
					entry["spur_ticks"],
					entry["made"]
				]
			)
		)
		for state in range(FlightSim.State.APPROACH, FlightSim.State.DEPARTED + 1):
			ok = ok and reached.has(state)
		ok = ok and entry["spur_ticks"] > 0 and entry["made"] > 0
	if not ok:
		_fail("a turnaround count was not positive or a state was skipped")
	return ok


## Frames flight `id`'s drawn plane and saves plate `label`.
func _plate_of(label: String, id: String) -> void:
	var view := _view_of_flight(id)
	if view == null:
		_fail("%s: %s is not drawn at tick %d" % [label, id, _clock.tick])
		return
	var box := _aabb_of(view)
	if not box.has_volume():
		_fail("%s: %s is drawn with no mesh" % [label, id])
		return
	var framed := _corners(box)
	var top := box.get_center() + Vector3.UP * box.size.y * 0.5
	print(
		(
			"PROBE plate %s: %s in state %d at %s"
			% [label, id, _flights.state_of(id), view.global_position]
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


func _ticks(count: int) -> void:
	for i in count:
		_clock.set_paused(false)
		_clock.advance(SimClock.STEP)
		_clock.set_paused(true)
	_beat("tick %d" % _clock.tick)
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
			OS.crash("side gates probe hung")


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
