extends SceneTree
## Windowed plates of a roller visitor's pick-up at the lounge sofa and the nap
## pod with a late first draw (board c0707a22): the bag leaves the floor, then
## LATES ticks (9, past the lift's k 0.55; 12, past the roll's decision) run
## with no frame, as a frame running several ticks does. From there a frame a
## tick. The roll is decided on sim ticks (RollerPark.roll_step()), so the
## roller must still be rolled upright beside the body, held by the bar, out
## of the seat, until the body is clear.
##
## For each piece the probe boots main.tscn, builds the reference terminal with
## a ready room of that type (ActivityTestLayout), opens the airport and sends
## one bored roller passenger into the room, stepping the clock by hand.
## Plates at PLATE_TICKS ticks after the bag left the floor, from a camera
## beside and in front of the seat. Before each save: the body (feet, chest)
## and the roller's centre project inside the frame with MARGIN_PX, and a
## sight line (PlateSight, against the meshes drawn) lands on the roller;
## otherwise PROBE_INVALID, exit 1. Each plate prints, for the roller:
##   ROLLER <plate> rolls=<bool> up_dot=<roller's own z against world up>
##     bar_gap=<m, hand to bar, -1 not held by the bar> seat_clear=<m, least
##     signed distance of its box from the seat's box> low=<m, its box's lowest
##     point over the floor> body_moved=<m from where it stood>
## and checks them (_check(): a CHECK line with the value and its range each;
## PROBE_FAIL and exit 1 outside it): a tipped, intersecting, unheld or
## floating roller cannot pass, nor one rolled away from the stood walker's
## side (beside, _beside()).
## Plates: <type>_late<N>_n<tick>.png, and contact_sheet.png (a row a pick-up).
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/activity_roller_park_probe.gd [-- --seed=N]
##
## Plates go to tools/blender/out/roller_roll/.

const StarterFlight := preload("res://spike/starter_flight.gd")
const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/roller_roll"
const LATES: Array[int] = [9, 12]
const PLATE_TICKS: Array[int] = [11, 16, 22, 28]
const MARGIN_PX := 8.0
const LIMIT_TICKS := 3000
const HANG_MS := 120000
const OCCLUDER_OWNERS: Array[String] = ["Airside/Terminal", "BuildMode", "PassengerViews"]
## The seat box (as tests/passengers/test_roller_roll_cadence.gd).
const SEAT_HALF_M := 0.6
const SEAT_FRONT_M := 0.05
const SEAT_DEPTH_M := 0.9
const SEAT_TOP_M := 1.3
## Pass values (_check()): the roller's own z this close to world up (upright
## on its wheels); from HELD_FROM ticks on (past the latest lift and park) its
## bar this close to the hand, and its box's lowest point this far over the
## floor as it stands on its wheels (measured 0.220 m), give or take
## LOW_SLACK_M.
const UPRIGHT_DOT := 0.98
const HELD_FROM := 22
const BAR_GAP_M := 0.03
const WHEELS_LOW_M := 0.22
const LOW_SLACK_M := 0.02
## While it rolls with the walker still where it stood, the drawn roller's axle
## this close to its park beside the walker (_beside()).
const BESIDE_M := 0.02

var _seed := 0
var _main: Node3D
var _sim: PassengerSim
var _clock: SimClock
var _mode: BuildMode
var _views: PassengerViews
var _failed := false
var _out_dir := ""
var _lock := Mutex.new()
var _stage := "boot"
var _beat_ms := 0
var _stop := false
var _guard: Thread
var _sheet: Array[Image] = []


func _initialize() -> void:
	_seed = randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
	print("PROBE sim_seed=%d lates=%s" % [_seed, LATES])
	_out_dir = ProjectSettings.globalize_path(OUT_REL)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_beat_ms = Time.get_ticks_msec()
	_guard = Thread.new()
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	for type: StringName in [&"lounge", &"nap_pod"]:
		for late in LATES:
			if not await _boot(type):
				_failed = true
				break
			await _pick_up(type, late)
			_main.queue_free()
			await process_frame
	if not _sheet.is_empty():
		_save_sheet()
	print("PROBE done failed=%s" % _failed)
	_finish()
	quit(1 if _failed else 0)


func _boot(type: StringName) -> bool:
	_beat("boot %s" % type)
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	_clock.seed_rng(_seed)
	(_main.get_node("BuildMode") as BuildMode).starter_shell = false
	root.add_child(_main)
	_clock.set_process(false)
	_clock.set_paused(false)
	for i in 3:
		await process_frame
	_mode = _main.get_node("BuildMode") as BuildMode
	_mode.set_process(false)
	_mode.set_tool(BuildMode.Tool.NONE)
	_sim = _main.get_node("PassengerSim") as PassengerSim
	_views = _main.get_node("PassengerViews") as PassengerViews
	ActivityTestLayout.build(_mode.grid, type)
	if not StarterFlight.add_gate_desk(_mode.grid):
		print("PROBE_INVALID the gate desk was refused")
		return false
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	for i in 4:
		await process_frame
	_sim.shops.refresh()
	_sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	if hired == 0 or doors < 0:
		print("PROBE_INVALID %s: the airport did not open" % type)
		return false
	return true


func _visitor() -> Passenger:
	var p: Passenger = null
	for attempt in 200:
		var id := _sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
		p = _sim.get_passenger(id)
		if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER:
			break
		p.carry_on = 0
	ToiletTestLayout.calm(p)
	p.carry_on = 1
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _clock.tick
	p.at = ShopTestLayout.AIRSIDE_CELL + ReferenceTerminal.offset_on(_mode.grid)
	p.clear_path()
	p.boredom = 80
	p.shop_cooldown = 0
	NeedsPolicy.arbitrate(_sim, p)
	return p


## One tick, then a frame when `frame` (the views sync on every tick).
func _tick(frame := true) -> void:
	_clock.advance(SimClock.STEP)
	if frame:
		await process_frame
		_beat(_stage)


func _pick_up(type: StringName, late: int) -> void:
	var p := _visitor()
	if _sim.shops.visit_of(p.id) == null:
		_invalid("%s: the visitor did not commit to the room" % type)
		return
	var until := _clock.tick + LIMIT_TICKS
	while p.stage != Passenger.Stage.SHOP_BROWSE and _clock.tick < until:
		await _tick()
	while not ActivityPoses.bags_down(_sim, p) and _clock.tick < until:
		await _tick()
	while ActivityPoses.bags_down(_sim, p) and _clock.tick < until:
		await _tick()
	if p.stage != Passenger.Stage.SHOP_BROWSE:
		_invalid("%s: no pick-up at the seat" % type)
		return
	var seat := _seat_of(p)
	var stood := _views.node_for(p.id).global_position
	var picked := _clock.tick
	print("PICKUP %s tick=%d late=%d" % [type, picked, late])
	for i in late:
		await _tick(false)
	await process_frame
	for n in range(late, PLATE_TICKS[-1] + 1):
		if n > late:
			await _tick()
		if n == late or (n > late and PLATE_TICKS.has(n)):
			await _plate("%s_late%02d_n%02d" % [type, late, n], n, p, seat, stood)


## The seat of the piece `p` stays at: {"frame" (its seat frame, world), "box"
## (the bounds in it of the piece's mesh vertices near the seat)}.
func _seat_of(p: Passenger) -> Dictionary:
	var frame := ActivityPoses.stay_frame(_sim, p)
	var record := _sim.grid.get_object(_sim.shops.visit_of(p.id).display)
	var def := BuildCatalog.get_def(record["def"])
	var cells := def.footprint(record["anchor"], record["facing"])
	var piece := BuildView.object_transform(_sim.grid, cells, record["facing"])
	var to_seat := frame.affine_inverse() * piece
	var scene := (load("res://assets/interior/%s.glb" % record["def"]) as PackedScene).instantiate()
	var box := AABB()
	var count := 0
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var xf := mi.transform
		var parent := mi.get_parent()
		while parent != null and parent != scene:
			xf = (parent as Node3D).transform * xf
			parent = parent.get_parent()
		for v in mi.mesh.get_faces():
			var at := to_seat * xf * v
			var near := absf(at.x) <= SEAT_HALF_M and at.y <= SEAT_TOP_M
			if near and at.z <= SEAT_FRONT_M and at.z >= -SEAT_DEPTH_M:
				box = AABB(at, Vector3.ZERO) if count == 0 else box.expand(at)
				count += 1
	scene.free()
	if count == 0:
		_invalid("no seat vertices for %s" % record["def"])
	return {"frame": frame, "box": box}


## The roller's box points drawn at `xf` (world): centre, corners, face centres.
func _box_points(xf: Transform3D) -> Array[Vector3]:
	var local := CarryOnProps.bag_box(SecurityLooks.Kind.ROLLER)
	var points: Array[Vector3] = [xf * local.get_center()]
	for i in 8:
		points.append(xf * local.get_endpoint(i))
	for axis in 3:
		for side in [0.0, 1.0]:
			var face := local.get_center()
			face[axis] = local.position[axis] + local.size[axis] * side
			points.append(xf * face)
	return points


static func _signed(box: AABB, point: Vector3) -> float:
	var out := Vector3(
		maxf(box.position.x - point.x, point.x - box.end.x),
		maxf(box.position.y - point.y, point.y - box.end.y),
		maxf(box.position.z - point.z, point.z - box.end.z)
	)
	if out.x > 0.0 or out.y > 0.0 or out.z > 0.0:
		return Vector3(maxf(out.x, 0.0), maxf(out.y, 0.0), maxf(out.z, 0.0)).length()
	return maxf(out.x, maxf(out.y, out.z))


func _plate(file: String, n: int, p: Passenger, seat: Dictionary, stood: Vector3) -> void:
	_beat(file)
	var body := _views.node_for(p.id)
	var props := _views.carry_on_props()
	var bag: Node3D = props.props_of(p.id)["bags"][0]
	var frame: Transform3D = seat["frame"]
	# Beside and in front of the seat, on the roller's side, looking at the body.
	var aim := body.global_position + Vector3.UP * 0.7
	var side := (bag.global_position - body.global_position).normalized()
	var eye := aim + frame.basis.z * 2.6 + side * 1.4 + Vector3.UP * 1.0
	var cam := Camera3D.new()
	cam.fov = 45.0
	_main.add_child(cam)
	cam.look_at_from_position(eye, aim)
	cam.make_current()
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var ok := true
	for up in [0.1, 1.3]:
		ok = (
			_in_frame(cam, body.global_position + Vector3.UP * up, "%s body+%.1f" % [file, up])
			and ok
		)
	var centre := (
		bag.global_transform * CarryOnProps.bag_box(SecurityLooks.Kind.ROLLER).get_center()
	)
	ok = _in_frame(cam, centre, "%s roller" % file) and ok
	var seen := await _roller_seen(cam, p)
	var rec := props.bag_state(p.id, 0)
	var to_seat := frame.affine_inverse()
	var clear := INF
	var low := INF
	for point in _box_points(bag.global_transform):
		clear = minf(clear, _signed(seat["box"], to_seat * point))
		low = minf(low, point.y)
	var up_dot := bag.global_basis.z.normalized().dot(Vector3.UP)
	var line := "ROLLER %s tick=%d rolls=%s up_dot=%.3f bar_gap=%.3f seat_clear=%.3f low=%.3f"
	line += " body_moved=%.3f seen=%s"
	print(
		(
			line
			% [
				file,
				_clock.tick,
				RollerPark.rolls(rec),
				up_dot,
				props.bar_gap_of(p.id, 0),
				clear,
				low,
				body.global_position.distance_to(stood),
				seen,
			]
		)
	)
	if not ok or not seen:
		_invalid("%s: subject not shown (in_frame=%s seen=%s)" % [file, ok, seen])
	# Pass values: upright and out of the seat on every plate, not sunk into
	# the floor; rolled once the sim decided (ROLL_TO); from HELD_FROM held by
	# the bar and on its wheels (not floating).
	_check(file, "up_dot", up_dot, UPRIGHT_DOT, 1.01)
	_check(file, "seat_clear", clear, 0.0, INF)
	_check(file, "low", low, WHEELS_LOW_M - LOW_SLACK_M, INF)
	if n >= RollerPark.ROLL_TO:
		_check(file, "rolls", 1.0 if RollerPark.rolls(rec) else 0.0, 1.0, 1.0)
	if n >= HELD_FROM:
		_check(file, "bar_gap", props.bar_gap_of(p.id, 0), 0.0, BAR_GAP_M)
		_check(file, "low", low, WHEELS_LOW_M - LOW_SLACK_M, WHEELS_LOW_M + LOW_SLACK_M)
	var beside := _beside(n, p, rec, bag)
	if beside >= 0.0:
		_check(file, "beside", beside, 0.0, BESIDE_M)
	var img := root.get_texture().get_image()
	var path := _out_dir.path_join(file + ".png")
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
	else:
		print("PLATE saved %s size=%s" % [path, img.get_size()])
	_sheet.append(img)
	cam.queue_free()


## How far (m, on the floor) the drawn roller `bag` of `p` at tick `n` of its
## pick-up (record `rec`) stands from its park beside the stood walker: its axle
## RollerPark.PARK_SIDE_M out on the leading hand's side and PARK_AHEAD_M ahead
## in the stood frame ("roll_frame"; board bea7e508: it could stand 0.7 m off).
## -1 when not measured: not rolled, past the lift's end not yet, tipping, or
## the walker off its stood point on this tick or the last.
func _beside(n: int, p: Passenger, rec: Dictionary, bag: Node3D) -> float:
	if not RollerPark.rolls(rec) or not rec.has("roll_frame"):
		return -1.0
	if n < RollerPark.up_ends(rec).x * RollerPark.TICKS_UP:
		return -1.0
	if n >= float(rec.get("roll_tip", INF)) * RollerPark.TICKS_UP:
		return -1.0
	var frame: Transform3D = rec["roll_frame"]
	for current in [true, false]:
		if _views.tick_position(p.id, current).distance_to(frame.origin) > RollerPark.MOVED_M:
			return -1.0
	var side := -1.0 if CarryLead.hand_of(rec["home"]) == 0 else 1.0
	var axle := frame.affine_inverse() * (bag.global_transform * CarryOnProps.ROLLER_AXLE)
	var off := Vector2(axle.x - side * RollerPark.PARK_SIDE_M, axle.z - RollerPark.PARK_AHEAD_M)
	print("BESIDE axle x=%.4f z=%.4f in the stood frame" % [axle.x, axle.z])
	return off.length()


## Prints `value` against [`least`, `most`] and fails the probe outside it.
func _check(file: String, name: String, value: float, least: float, most: float) -> void:
	var ok := value >= least and value <= most
	print("CHECK %s %s=%.3f need [%.3f, %.3f] ok=%s" % [file, name, value, least, most, ok])
	if not ok:
		print("PROBE_FAIL %s %s=%.3f" % [file, name, value])
		_failed = true


## Every plate at half size, one pick-up's plates to a row (contact_sheet.png).
func _save_sheet() -> void:
	var w := _sheet[0].get_width() / 2
	var h := _sheet[0].get_height() / 2
	var across := PLATE_TICKS.size() + 1
	var rows := ceili(_sheet.size() / float(across))
	var sheet := Image.create(w * across, h * rows, false, Image.FORMAT_RGBA8)
	for i in _sheet.size():
		var small := _sheet[i].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * (i % across), h * (i / across)))
	var path := _out_dir.path_join("contact_sheet.png")
	if sheet.save_png(path) != OK:
		_invalid("could not save %s" % path)
	else:
		print("PLATE saved %s size=%s" % [path, sheet.get_size()])


## Whether a sight line from the camera lands on the roller of `p` (five lines:
## its centre and four points about it).
func _roller_seen(cam: Camera3D, p: Passenger) -> bool:
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		owners.append(_main.get_node(path))
	var bags: Array = _views.carry_on_props().props_of(p.id)["bags"]
	var holder := PlateSight.colliders(root, owners, {bags[0]: "roller"})
	await physics_frame
	await physics_frame
	var bounds: Dictionary = holder.get_meta("bounds")
	var box: AABB = bounds.get("roller", AABB())
	var c := box.get_center()
	var q := box.size * 0.25
	var targets: Array[Vector3] = [
		c, c + Vector3(q.x, q.y, 0), c - Vector3(q.x, 0, q.z), c + Vector3(0, q.y, q.z), c - q
	]
	var space := cam.get_world_3d().direct_space_state
	var hits := PlateSight.sight_lines(space, cam.global_position, targets, "roller")
	holder.free()
	var on := (hits["on_subject"] as Array).size()
	print("SIGHT on=%d past=%d blockers=%s" % [on, hits["past"], hits["blockers"]])
	return on > 0


func _in_frame(cam: Camera3D, point: Vector3, label: String) -> bool:
	var rect := root.get_visible_rect().grow(-MARGIN_PX)
	var behind := cam.is_position_behind(point)
	var screen := cam.unproject_position(point)
	var ok := not behind and rect.has_point(screen)
	print("INFRAME %s screen=(%.0f,%.0f) frame=%s ok=%s" % [label, screen.x, screen.y, rect, ok])
	return ok


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _beat(stage: String) -> void:
	_lock.lock()
	_stage = stage
	_beat_ms = Time.get_ticks_msec()
	_lock.unlock()


func _finish() -> void:
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()


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
			OS.crash("activity_roller_park_probe: main thread stalled in %s" % stage)
