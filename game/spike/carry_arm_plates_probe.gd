extends SceneTree
## Windowed plates of hand-held carry-on bags: the carry arm turns out 12
## degrees (CarrySwap.HAND_OUT_DEGREES) in every hand carry but a roller held
## by its bar beside the stalls, which turns out StallCarry.BAR_OUT_DEGREES (6),
## and a roller leaving a toilet stall stays in the hand until
## StallCarry.LIFT_LEAD_M clear of the stalls (board item a791eb90). Each plate's
## log line prints the holding arm's turn (arm_out). Boots main.tscn with a new random sim seed
## (printed; ++ --seed=N to replay), builds ToiletTestLayout's two toilet rooms
## on the reference terminal, opens the airport and sends two visitors with a
## pressing toilet need, one at a time, the clock stepped by hand:
##   a hard case: on its walk to the stall, the bag hanging at the side, plated
##     from the bag's side, from the front and from behind (case_side, case_front,
##     case_back) with the palm in the side plate;
##   a roller: as it leaves the stall along the row, held in the hand, the frame
##     where its box is nearest the stall front plane while over the stall's
##     column (roller_leaving_top / _front / _row: from over, from out in the
##     aisle and along the row), and the swap from the hand to the pull after
##     StallCarry.LIFT_LEAD_M (roller_swap_k20/k50/k85 each _top and _row).
## Then a crowd of bag-carrying passengers at the game camera's usual distance
## (crowd_walking).
## Every plate proves its points in frame (the bag, the hip, the feet, and for a
## stall plate the partition's front corners; projected through the camera with
## a margin), that sight lines land on the bag (PlateSteps.lines_on_bag), that
## the palm is seen where asked and that it is not dark, or tries the next
## camera; none passing prints PROBE_INVALID and exits 1. A guard thread calls
## OS.crash() on a stalled main thread.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --path game \
##     --display-driver windows --rendering-driver vulkan --audio-driver Dummy \
##     -s res://spike/carry_arm_plates_probe.gd [-- --seed=N --out=C:/dir --only=crowd]
## Plates go to tools/blender/out/carry-arm-scoped/ unless --out is given.

const FloatCheck := preload("res://spike/carry_float_check.gd")
const PlateSteps := preload("res://spike/carry_plate_steps.gd")
const PlateSight := preload("res://spike/plate_sight.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/carry-arm-scoped"
const HANG_MS := 90000
const LAST_TICKS := 3000
const RESEND_TICKS := 900
const MAX_RESENDS := 3
const MIN_LEAD_TICKS := 1800
const ADVANCE_LIMIT_TICKS := 40000
const FRAME_TICKS := 0.5
const FAST_TICKS := 2.0
const MARGIN_PX := 8.0
const FILL := 0.75
## The case is plated on the walk to the stall at least this far from it (mm).
const WALK_MIN_MM := 3000
## The stall front's outer plane (StallCarry.DOOR_M) and its column's half
## width across (the partitions' outer faces, test_carry_stall_front_margin.gd).
const COLUMN_HALF_M := 0.53
## A leaving roller is plated when its box is within this of the front plane.
const NEAR_FRONT_M := 0.12
## The swap's plated move windows (progress of the hand to pull move).
const SWAP_MOMENTS := [[0.15, 0.25], [0.45, 0.55], [0.8, 0.9]]
const CAMERA_HEIGHT_M := 6.0
const CROWD_DISTANCE := 16.0
const CROWD_MIN := 4
const CROWD_MIN_PX := 60.0
const OCCLUDER_OWNERS: Array[String] = [
	"Airside/Terminal", "BuildMode", "StaffCharacters", "BaggageViews"
]

var _out_dir := ""
var _failed := false
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _stop := false
var _main: Node3D
var _sim: PassengerSim
var _clock: SimClock
var _views: PassengerViews
var _visited := false
var _after := false
var _swap_pending := false
var _stall := {}
var _visitor: Passenger
var _top_done := false
var _swap_pending_done := false
var _hidden: Array[CanvasLayer] = []
var _plates := 0
var _wanted := 0


func _initialize() -> void:
	var out := ProjectSettings.globalize_path(OUT_REL).simplify_path()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	_out_dir = out
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=%s" % _out_dir)
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	var seed := randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = int(arg.trim_prefix("--seed="))
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	(_main.get_node("BuildMode") as BuildMode).starter_shell = false
	root.add_child(_main)
	_clock.set_process(false)
	_clock.set_paused(false)
	await _frames(3)
	var mode := _main.get_node("BuildMode") as BuildMode
	mode.set_process(false)
	mode.set_tool(BuildMode.Tool.NONE)
	(mode.get_node("Ghost") as Node3D).visible = false
	_sim = _main.get_node("PassengerSim") as PassengerSim
	_views = _main.get_node("PassengerViews") as PassengerViews
	var ids := ToiletTestLayout.build(mode.grid, 3)
	if not StarterFlight.add_gate_desk(mode.grid):
		_invalid("the gate desk was refused")
	(mode.get_node("BuildView") as BuildView).refresh(mode.grid)
	await _frames(4)
	_sim.toilets.refresh()
	print("PROBE ids=%s usable_stalls=%d" % [ids, _sim.toilets.layout.stalls.size()])
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE staff hired=%d opened tick=%d doors_close_tick=%d" % [hired, _clock.tick, doors])
	if hired == 0 or doors < 0 or _sim.toilets.layout.stalls.size() != 6:
		_invalid("the airport did not open, or not six usable stalls")
	else:
		_clock.ticked.connect(_on_tick)
		if not OS.get_cmdline_user_args().has("--only=crowd"):
			await _visit("case", SecurityLooks.Kind.CASE)
			await _visit("roller", SecurityLooks.Kind.ROLLER)
		await _crowd()
	print("PLATES saved=%d wanted=%d" % [_plates, _wanted])
	if _plates != _wanted or _wanted == 0:
		_invalid("plates saved %d of %d" % [_plates, _wanted])
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()
	print("PROBE exit=%d" % (1 if _failed else 0))
	quit(1 if _failed else 0)


## Sends one visitor (one bag of `kind`) and follows it until its plates are taken.
func _visit(label: String, kind: SecurityLooks.Kind) -> void:
	_visited = false
	_after = false
	_swap_pending = false
	_stall = {}
	_top_done = false
	_swap_pending_done = false
	var p := _spawn(kind)
	if p == null:
		return
	_visitor = p
	print("VISITOR %s passenger=%d" % [label, p.id])
	var sent := _clock.tick
	var last := sent + LAST_TICKS
	var resent := 0
	var done := false
	while _clock.tick < last and not done:
		_beat("%s tick %d" % [label, _clock.tick])
		if not Passenger.in_toilet(p.stage) and not _visited and _clock.tick - sent > RESEND_TICKS:
			resent += 1
			print("LATE %s passenger=%d stage=%s" % [label, p.id, Passenger.Stage.keys()[p.stage]])
			if resent > MAX_RESENDS:
				_invalid("%s never reached a stall" % label)
				return
			p = _spawn(kind)
			_visitor = p
			sent = _clock.tick
			last = sent + LAST_TICKS
		if not _swap_pending:
			_clock.advance(SimClock.STEP * _ticks_now(p))
		await process_frame
		await RenderingServer.frame_post_draw
		var visit := _sim.toilets.visit_of(p.id)
		if visit != null:
			_stall = visit.stall
		_visited = _visited or p.stage == Passenger.Stage.TOILET_EXIT
		_after = _visited and not Passenger.in_toilet(p.stage)
		if kind == SecurityLooks.Kind.CASE:
			done = await _case_frame(p)
		else:
			done = await _roller_frame(p)
	_visitor = null
	_after = false
	if not done:
		_invalid("%s: its plates were not reached by tick %d" % [label, last])


func _ticks_now(p: Passenger) -> float:
	if p.stage == Passenger.Stage.TOILET_USE:
		var sat := _sim.tick - p.stage_tick
		return FAST_TICKS if sat < ToiletSim.USE_TICKS - 4 else FRAME_TICKS
	if StallCarry.in_stall(p) or StallCarry.held_by_hand(_sim, p, 2.0):
		return FRAME_TICKS
	return FAST_TICKS


func _spawn(kind: SecurityLooks.Kind) -> Passenger:
	var flight := _open_flight()
	if flight == "":
		_invalid("no flight with its doors closing %d or more ticks ahead" % MIN_LEAD_TICKS)
		return null
	while true:
		var p := _sim.get_passenger(_sim.spawn_now(flight))
		ToiletTestLayout.calm(p)
		p.carry_on = 0
		if SecurityLooks.bag_kind(p, 0) == kind:
			p.carry_on = 1
			p.toilet_need = 95
			p.toilet_cooldown = 0
			return p
	return null


func _open_flight() -> String:
	var flights := _main.get_node("FlightSim") as FlightSim
	var best := _flight_with_lead(flights)
	if best == "":
		var done := func() -> bool: return _flight_with_lead(flights) != ""
		StarterFlight.advance_until(_clock, done, ADVANCE_LIMIT_TICKS)
		best = _flight_with_lead(flights)
	print("FLIGHT %s now=%d" % [best, _clock.tick])
	return best


func _flight_with_lead(flights: FlightSim) -> String:
	var best := ""
	var best_close := 0
	for id in flights.flight_ids():
		var close := flights.doors_close_tick(id)
		if close >= _clock.tick + MIN_LEAD_TICKS and (best == "" or close < best_close):
			best = id
			best_close = close
	return best


## At each tick: a roller about to go from the hand to the pull after the visit
## pauses the clock, so the loop plates it from its first drawn frame.
func _on_tick(_tick: int) -> void:
	if not _after or _swap_pending or _clock.paused or _visitor == null:
		return
	var move := PlateSteps.pending_move(_views.carry_on_props(), _visitor.id, 0)
	if move.begins_with("hand") and move.contains(">pull"):
		_clock.set_paused(true)
		_clock._accumulator = 0.0
		_swap_pending = true


## The case on its walk to the stall, hanging at the side: three plates.
func _case_frame(p: Passenger) -> bool:
	if p.stage != Passenger.Stage.TOILET_WALK or p.remaining_mm() < WALK_MIN_MM:
		return false
	var props := _views.carry_on_props()
	var body := _views.node_for(p.id)
	if body == null or not p.is_moving() or not _in_side_hand(props, p.id):
		return false
	var held: Array = props.props_of(p.id)["bags"]
	var bag: Node3D = held[0]
	var step := Vector2(p.path[p.path_index + 1] - p.path[p.path_index]).normalized()
	var ahead := Vector3(step.x, 0.0, step.y)
	var out := bag.global_position - body.global_position
	var side := Vector3(out.x, 0.0, out.z)
	if side.length() < 0.08:
		return false
	side = side.normalized()
	var state := FloatCheck.float_state(_sim, _views, p.id, 0)
	print(
		(
			"CASE walk passenger=%d remaining_mm=%d ahead=%s bag_side=%s side_offset_m=%.3f state=%s %s"
			% [p.id, p.remaining_mm(), ahead, side, out.length(), state, _arm(p)]
		)
	)
	_clock.set_paused(true)
	var box := _bounds(bag)
	var palm := PlateSteps.palm_of(body, box)
	var points := {
		"bag": box.get_center(),
		"hip": body.global_position + Vector3.UP * 0.9,
		"feet": body.global_position,
	}
	if palm.is_finite():
		points["palm"] = palm
	else:
		_invalid("case: no palm within reach of the bag")
	var fit := _lower_body(body, box)
	var views := {
		"side": side,
		"front": ahead,
		"back": -ahead,
		"front_out": (ahead + side).normalized(),
		"back_out": (side - ahead).normalized(),
	}
	for view: String in views:
		var dir: Vector3 = views[view]
		var eyes: Array[Vector3] = []
		var aim := fit.get_center()
		for h: float in [0.5, 1.0, 1.6]:
			for d: float in [2.0, 2.8, 1.5]:
				eyes.append(Vector3(aim.x, 0.0, aim.z) + dir * d + Vector3.UP * h)
		_wanted += 1
		await _shoot("case_" + view, body, bag, eyes, aim, Vector3.UP, fit, points, view == "side")
	_clock.set_paused(false)
	return true


## Whether bag 0 of `id` is in a hand at the side (a case, no move running).
func _in_side_hand(props: CarryOnProps, id: int) -> bool:
	var bag := props.bag_state(id, 0)
	if not bag.has("place") or props.transfer_progress(id, 0) < 1.0:
		return false
	return (
		int(bag["place"]) / 4 == SecurityLooks.Home.HAND
		and int(bag["carry"]) == SecurityLooks.Carry.HAND
	)


## The roller after the visit: plate the frame nearest the stall front while
## over the stall's column, and the swap to the pull. True when both are done.
func _roller_frame(p: Passenger) -> bool:
	var props := _views.carry_on_props()
	var body := _views.node_for(p.id)
	var bags: Array = props.props_of(p.id).get("bags", [])
	if not _after or _stall.is_empty() or body == null or bags.is_empty():
		return false
	if _swap_pending:
		await _plate_swap(p, body, bags[0])
	elif _in_side_hand(props, p.id):
		await _plate_leaving(p, body, bags[0])
	return _swap_pending_done


## Plates the frame nearest the stall front while over the stall's column.
func _plate_leaving(p: Passenger, body: Node3D, bag: Node3D) -> void:
	var m := _margin(bag, _stall)
	if not m[0]:
		return
	print("ROLLER over column margin_m=%.3f tick=%d %s" % [m[1], _clock.tick, _leaving(p)])
	if float(m[1]) > NEAR_FRONT_M or _top_done:
		return
	_top_done = true
	_clock.set_paused(true)
	await _stall_plates("roller_leaving", p, body, bag)
	_clock.set_paused(false)


func _leaving(p: Passenger) -> String:
	return (
		"leaving=%s leaving_with_lead=%s %s"
		% [
			StallCarry.leaving(_sim, p),
			StallCarry.leaving(_sim, p, StallCarry.LIFT_LEAD_M),
			_arm(p)
		]
	)


## The out turn of the arm holding bag 0 of `p`, as drawn.
func _arm(p: Passenger) -> String:
	var props := _views.carry_on_props()
	var body := _views.node_for(p.id)
	var held: Dictionary = props._held.get(p.id, {})
	if body == null or held.is_empty():
		return "arm_out=none"
	var arm: CarryArm = props._rig(body)["arms"][held["hands"][0]]
	return "arm_out=%.2f" % arm.angle_degrees


## [over the stall's column, metres of the bag's box beyond the front plane].
func _margin(bag: Node3D, stall: Dictionary) -> Array:
	var out := SecurityLooks.world_dir(stall["front"])
	var across := out.cross(Vector3.UP)
	var centre: Vector3 = stall["use"] - out * ToiletLayout.USE_M
	var box := _bounds(bag)
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in 8:
		var corner := box.get_endpoint(i) - centre
		var local := Vector3(corner.dot(across), corner.y, corner.dot(out))
		lo = lo.min(local)
		hi = hi.max(local)
	var over: bool = (
		lo.x < COLUMN_HALF_M and hi.x > -COLUMN_HALF_M and lo.z < StallCarry.DOOR_M + 1.0
	)
	return [over, lo.z - StallCarry.DOOR_M]


## The swap from the hand to the pull, plated at SWAP_MOMENTS.
func _plate_swap(p: Passenger, body: Node3D, bag: Node3D) -> void:
	var props := _views.carry_on_props()
	var move := FloatCheck.move_of(props, p.id, 0)
	print("SWAP start move=%s %s" % [move, _leaving(p)])
	_clock.set_paused(true)
	for m in SWAP_MOMENTS.size():
		var lo: float = SWAP_MOMENTS[m][0]
		var hi: float = SWAP_MOMENTS[m][1]
		await PlateSteps.step_to(self, _clock, props, p.id, 0, lo, hi)
		await _frames(1)
		var k := props.transfer_progress(p.id, 0)
		if FloatCheck.move_of(props, p.id, 0) != move or k < lo or k > hi:
			_invalid("swap moment %d missed at k %.2f (move %s)" % [m, k, move])
			break
		print(
			(
				"SWAP moment=%d k=%.2f state=%s %s"
				% [m, k, FloatCheck.float_state(_sim, _views, p.id, 0), _leaving(p)]
			)
		)
		await _stall_plates("roller_swap_k%02d" % roundi(k * 100.0), p, body, bag, false)
	_swap_pending = false
	_swap_pending_done = true
	_clock.set_paused(false)


## Plates of the roller by the stall column: from over, from out in the aisle
## and (`front_row`) along the row; the partition's front corners must be in
## frame too.
func _stall_plates(
	name: String, _p: Passenger, body: Node3D, bag: Node3D, front_row := true
) -> void:
	var out := SecurityLooks.world_dir(_stall["front"])
	var across := out.cross(Vector3.UP)
	var centre: Vector3 = _stall["use"] - out * ToiletLayout.USE_M
	var box := _bounds(bag)
	var corners := {}
	var fit := box.merge(_bounds(body))
	for side in [-1.0, 1.0] if front_row else []:
		for h in [0.0, 1.2]:
			var at: Vector3 = (
				Vector3(centre.x, h, centre.z)
				+ out * StallCarry.DOOR_M
				+ across * COLUMN_HALF_M * side
			)
			corners["corner %d %.1f" % [side, h]] = at
	for at: Vector3 in corners.values():
		fit = fit.expand(at)
	var points := {
		"bag": box.get_center(),
		"feet": body.global_position,
	}
	points.merge(corners)
	var aim := fit.get_center()
	var tops: Array[Vector3] = []
	for off: Vector2 in [Vector2(0, 0.3), Vector2(0.4, 0), Vector2(-0.4, 0), Vector2(0, -0.5)]:
		tops.append(Vector3(aim.x, CAMERA_HEIGHT_M, aim.z) + across * off.x + out * off.y)
	for a in 8:
		tops.append(
			Vector3(aim.x, 4.0, aim.z) + Vector3.RIGHT.rotated(Vector3.UP, a * PI / 4.0) * 2.0
		)
	_wanted += 1
	await _shoot(name + "_top", body, bag, tops, aim, out, fit, points, false)
	var aisle: Array[Vector3] = []
	for d: float in [2.5, 3.2, 2.0]:
		for s: float in [0.0, 0.7, -0.7]:
			aisle.append(Vector3(aim.x, 1.3, aim.z) + out * d + across * s)
	if front_row:
		_wanted += 1
		await _shoot(name + "_front", body, bag, aisle, aim, Vector3.UP, fit, points, false)
	var row: Array[Vector3] = []
	for s: float in [-1.0, 1.0]:
		for d: float in [3.0, 4.0, 2.4]:
			row.append(Vector3(aim.x, 0.7, aim.z) + across * d * s + out * 0.6)
	if front_row:
		_wanted += 1
		await _shoot(name + "_row", body, bag, row, aim, Vector3.UP, fit, points, false)
		return
	var ring: Array[Vector3] = []
	for h: float in [1.0, 2.0]:
		for a in 8:
			ring.append(
				Vector3(aim.x, h, aim.z) + Vector3.RIGHT.rotated(Vector3.UP, a * PI / 4.0) * 2.4
			)
	_wanted += 1
	await _shoot(name + "_ring", body, bag, ring, aim, Vector3.UP, fit, points, false)


## A crowd of bag-carrying passengers at the game camera's usual distance.
func _crowd() -> void:
	var flight := _open_flight()
	for i in 14:
		_sim.spawn_now(flight)
	var rig := _main.get_node("TycoonCamera") as TycoonCamera
	var cam := rig.get_node("Camera3D") as Camera3D
	var shown: Array[Passenger] = []
	var tries := 0
	while shown.size() < CROWD_MIN and tries < 60:
		tries += 1
		for i in 40:
			_clock.advance(SimClock.STEP * 2.0)
			await process_frame
		var walkers: Array[Passenger] = []
		for id in _sim.passenger_ids():
			var p := _sim.get_passenger(id)
			if p.carry_on > 0 and p.is_moving() and _views.node_for(p.id) != null:
				walkers.append(p)
		if tries % 10 == 0:
			print("CROWD scan try=%d tick=%d walkers=%d" % [tries, _clock.tick, walkers.size()])
		if walkers.size() < CROWD_MIN:
			continue
		var centre := Vector3.ZERO
		for p in walkers:
			centre += _views.node_for(p.id).global_position
		centre /= walkers.size()
		rig.stop_follow()
		rig.position = Vector3(centre.x, 0.0, centre.z)
		rig.yaw = 0.0
		rig.distance = CROWD_DISTANCE
		_hide_hud()
		_clock.set_paused(true)
		await _frames(20)
		var img := await PlateSight.grab(self)
		var subjects := {}
		for p in walkers:
			subjects[_views.node_for(p.id)] = str(p.id)
		var owners: Array[Node] = []
		for path in OCCLUDER_OWNERS:
			owners.append(_main.get_node(path))
		owners.append(_views)
		var holder := PlateSight.colliders(root, owners, subjects)
		await physics_frame
		await physics_frame
		var bounds: Dictionary = holder.get_meta("bounds")
		var frame := Rect2(
			Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
		)
		shown.clear()
		for p in walkers:
			var seen := PlateSight.person_shown(
				cam, bounds.get(str(p.id), AABB()), str(p.id), frame, img, img, CROWD_MIN_PX
			)
			print(
				(
					"CROWD passenger=%d bags=%d px=%s height_px=%.0f on=%d in_frame=%s ok=%s"
					% [
						p.id,
						p.carry_on,
						seen.get("px"),
						seen.get("height_px", 0.0),
						seen["on"],
						seen.get("in_frame"),
						seen["ok"]
					]
				)
			)
			if seen["ok"]:
				shown.append(p)
		holder.free()
		_clock.set_paused(false)
		if shown.size() >= CROWD_MIN:
			_wanted += 1
			_save(img, "crowd_walking")
		else:
			_restore_hud()
	if shown.size() < CROWD_MIN:
		_invalid("crowd: fewer than %d bag carriers shown" % CROWD_MIN)
	_restore_hud()


func _hide_hud() -> void:
	for node in _main.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		if layer.visible:
			layer.visible = false
			_hidden.append(layer)


func _restore_hud() -> void:
	for layer in _hidden:
		layer.visible = true
	_hidden.clear()


## Saves the first of `eyes` that frames every point of `points`, sees the bag
## and (`show_palm`) prints whether the palm is seen. The cameras look at `aim` with `up`, fitted
## to `fit`. Otherwise PROBE_INVALID, and the last view is kept as _INVALID.
func _shoot(
	name: String,
	body: Node3D,
	bag: Node3D,
	eyes: Array[Vector3],
	aim: Vector3,
	up: Vector3,
	fit: AABB,
	points: Dictionary,
	show_palm: bool
) -> void:
	_hide_hud()
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		owners.append(_main.get_node(path))
	owners.append(_views)
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)
	var core := _core(bag)
	var saved := false
	var img: Image
	for n in eyes.size():
		cam.fov = 30.0
		cam.global_position = eyes[n]
		cam.look_at(aim, up)
		cam.fov = _fitted_fov(cam, fit)
		await _frames(2)
		img = root.get_texture().get_image()
		var holder := PlateSight.colliders(root, owners, {body: "subject", bag: "bag"})
		PlateSteps.see_both_sides(holder)
		await physics_frame
		await physics_frame
		var tag := "%s cam %d" % [name, n]
		var ok := (holder.get_meta("unbaked") as Array).is_empty()
		for key: String in points:
			ok = _in_frame(cam, points[key], frame, "%s %s" % [tag, key]) and ok
		var on := PlateSteps.lines_on_bag(cam, core)
		var dark := PlateSteps.dark_share(img)
		print("INFRAME %s bag_lines_on=%d/5 dark=%.2f" % [tag, on, dark])
		var need := 2 if name.begins_with("case") else 1
		ok = ok and on >= need and dark < PlateSteps.DARK_SHARE
		if ok and show_palm:
			PlateSteps.palm_seen(cam, points["palm"], frame, tag)
		holder.free()
		if ok:
			saved = _save(img, name)
			break
	cam.queue_free()
	_restore_hud()
	if not saved:
		_invalid("%s: no camera framed the subject, the bag and the points" % name)
		if img != null:
			img.save_png(_out_dir.path_join(name + "_INVALID.png"))
	await _frames(1)


func _in_frame(cam: Camera3D, at: Vector3, frame: Rect2, tag: String) -> bool:
	var px := cam.unproject_position(at)
	var ok := not cam.is_position_behind(at) and frame.has_point(px)
	print("INFRAME %s screen=(%.0f,%.0f) ok=%s" % [tag, px.x, px.y, ok])
	return ok


## The field of view for `cam`, aimed as it is, that makes `box` span FILL of
## the frame's height or width, whichever is tighter.
func _fitted_fov(cam: Camera3D, box: AABB) -> float:
	var to_cam := cam.global_transform.affine_inverse()
	var half := 0.0
	var aspect := root.get_visible_rect().size.x / root.get_visible_rect().size.y
	for c in 8:
		var at := to_cam * box.get_endpoint(c)
		var depth := maxf(-at.z, 0.1)
		half = maxf(half, maxf(absf(at.y), absf(at.x) / aspect) / depth)
	return clampf(rad_to_deg(2.0 * atan(half / FILL)), 5.0, 100.0)


## `body`'s drawn bounds from its feet (or the bag's lowest point, if lower) up to
## 0.4 m over the bag's top, joined with the bag's: the hand, the bag, the thigh
## and the feet (a plate asks for the feet in frame).
func _lower_body(body: Node3D, bag: AABB) -> AABB:
	var whole := _bounds(body)
	var lo := minf(bag.position.y, whole.position.y) - 0.05
	var hi := bag.end.y + 0.4
	var cut := AABB(
		Vector3(whole.position.x, lo, whole.position.z),
		Vector3(whole.size.x, maxf(hi - lo, 0.1), whole.size.z)
	)
	return cut.merge(bag)


## The biggest mesh of `bag`, world (the case itself, not the rods' air).
func _core(bag: Node3D) -> AABB:
	var core := AABB()
	for mi: MeshInstance3D in bag.find_children("*", "MeshInstance3D", true, false):
		var b := mi.global_transform * mi.get_aabb()
		core = b if b.get_volume() > core.get_volume() else core
	return core


func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
		_beat(_stage)
	await RenderingServer.frame_post_draw


func _save(img: Image, name: String) -> bool:
	var path := _out_dir.path_join(name + ".png")
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return false
	_plates += 1
	print("PLATE saved %s size=%s" % [path, img.get_size()])
	return true


func _beat(stage: String) -> void:
	_lock.lock()
	_stage = stage
	_beat_ms = Time.get_ticks_msec()
	_lock.unlock()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_lock.lock()
		var stop := _stop
		var stage := _stage
		var silent := Time.get_ticks_msec() - _beat_ms
		_lock.unlock()
		if stop:
			return
		if silent > HANG_MS:
			print("PROBE_INVALID hang: stage=%s silent_ms=%d" % [stage, silent])
			OS.crash("carry_arm_plates_probe: main thread stalled in %s" % stage)
