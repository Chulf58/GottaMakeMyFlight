extends SceneTree
## Windowed frame-strip plates of passengers going through security inside the
## real main scene (Security 7/8; SecurityLooks, CarryOnProps). Boots
## main/main.tscn with a new random sim seed (printed), builds the starter
## terminal through the HUD, swaps its east basic scanner for a whole security
## lane (arch on the divider, LEFT mirror, facing 0, the divider walls under
## the lane removed) and keeps the west basic scanner. Staff are hired as the
## panel hires them (one per station, plus a second officer who becomes the
## lane's helper) and walk to their posts (StaffPosts), and the two lane
## officers are plated on their spots with the way each faces. Then
## passengers with chosen carry-on are sent to security and each moment below
## is plated the first time it happens:
##   lane:  queue front held back, unpack (bags into the tray), the tray riding
##          the belt at three points of the arch walk, pickup, leaving
##   alarm: stepping aside, repack at the berth, the walk back, the second
##          pass through the arch, pickup
##   basic: carry-on through the scanner, the repack that holds it
##   whole: the checkpoint from 30 m
##   kinds: each carry-on kind (decision carry-on-bag-kinds-backpack-shoulder-
##          or-tote-bag-small-rolle) carried, in the tray, on the berth floor,
##          in the alarm corridor and on the floor at a gate seat; the alarm
##          walk-back of each kind checked every frame
## Passengers are spawned and matched to roles (ROLES) by the kind of their
## first bag (SecurityLooks.bag_kind), so every kind has its alarm passenger.
## Each plate tries four headings and keeps the first where the subject
## passenger is shown (game/spike/plate_sight.gd: in frame, sight lines on its
## upper body with no blocker, no HUD over it, tall enough) and every tray and
## bag of it is in frame, big enough and hit by a sight line. Clearance: no
## vertex of the subject's drawn body may lie inside a lane part (kit bounds
## of the tray table, X-ray belt and pickup table, the arch's posts), and no
## vertex inside one of its own bags' meshes (the hand holding a case, a
## roller's grip or a strap left out), and no bag inside another. The bench
## first sweeps the crowd: every frame of a walk (half of them late, so they
## run) and queue, each carrier's body against its bags, per kind and
## character, with a control per kind, and watches every hand bag before each
## frame is drawn: placed once per draw, its grip on the hand's final pose
## (carry_grip_watch.gd). Any failure prints PROBE_INVALID and exits 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/security_visuals_plates_probe.gd
## Plates go to tools/blender/out/security-lane-visuals/.

const PlateSight := preload("res://spike/plate_sight.gd")
const CarryContact := preload("res://spike/carry_contact.gd")
const CarryChecks := preload("res://spike/carry_probe_checks.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const Staged := preload("res://spike/security_probe_stage.gd")
const OUT_REL := "res://../tools/blender/out/security-lane-visuals"
const MAIN_SCENE := "res://main/main.tscn"
const ARCH_AT := Vector2i(20, ReferenceTerminal.DIVIDER_Y)
const OLD_SCANNERS: Array[Vector2i] = [Vector2i(17, 8), Vector2i(19, 8)]
const BASIC_AT := Vector2i(16, ReferenceTerminal.DIVIDER_Y - 1)
const MIRROR := SecurityLanes.LEFT
const OCCLUDER_OWNERS: Array[String] = ["Airside/Terminal", "BuildMode", "PassengerViews"]
const MARGIN_PX := 8.0
const MIN_SUBJECT_PX := 16.0
const MIN_PROP_PX := 6.0
const HANG_LIMIT_MS := 90000
const RUN_LIMIT_TICKS := 6000
const SEND_GAP_TICKS := 14
const DISTANCE_M := 7.0
## [first bag's kind or -1 for any, bags, liquids, alarm] of the passengers
## sent, in order.
const ROLES := [
	[-1, 2, false, false],
	[SecurityLooks.Kind.CASE, 1, false, true],
	[-1, 0, false, false],
	[-1, 1, true, false],
	[-1, 2, false, true],
	[-1, 1, false, false],
	[SecurityLooks.Kind.SHOULDER, 1, false, true],
	[SecurityLooks.Kind.BACKPACK, 1, false, true],
	[-1, 2, false, false],
	[SecurityLooks.Kind.ROLLER, 1, false, true],
	[SecurityLooks.Kind.CASE, 2, false, true],
	[SecurityLooks.Kind.CASE, 2, false, true],
	[SecurityLooks.Kind.CASE, 1, false, true],
	[SecurityLooks.Kind.CASE, 1, false, true],
	[SecurityLooks.Kind.SHOULDER, 1, false, false],
	[SecurityLooks.Kind.BACKPACK, 1, false, false],
	[SecurityLooks.Kind.ROLLER, 1, false, false],
	[SecurityLooks.Kind.SHOULDER, 1, false, true],
	[SecurityLooks.Kind.BACKPACK, 1, false, true],
	[SecurityLooks.Kind.ROLLER, 1, false, true],
]
const KIND_NAMES := ["case", "backpack", "shoulder", "roller"]
## The corridor is plated by the live walk-back (its second plate).
const KIND_MOMENTS := ["carried", "tray", "berth", "seat", "live_walk_back"]
## The crowd sweep: frames checked (every other frame).
const SWEEP_FRAMES := 40
## A carried bag counts as in the hand while the grip is this near its bounds.
const GRIP_REACH_M := 0.06
## The frame-cost check: this many passengers spawned, frames timed.
## The bench crowd: this many passengers drawn in all, as in Security 7/8.
const BENCH_CROWD := 110
const BENCH_FRAMES := 240
## The most ticks the bench waits for the lane to empty of the moments' passengers.
const BENCH_DRAIN_TICKS := 600

var _out_dir := ""
var _seed := 0
## --sweep-only: boot, then the crowd sweep and the bench, no moments.
var _sweep_only := false
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
var _main: Node3D
var _cam: Camera3D
var _rig: TycoonCamera
var _clock: SimClock
var _sim: PassengerSim
var _views: PassengerViews
var _arch := 0
var _lane := {}
var _part_boxes: Array = []
## The lane part nodes the build view draws (tray table, X-ray belt, pickup
## table, arch), for bag-against-mesh checks.
var _part_nodes: Array[Node3D] = []
var _body_control_done := false
## The basic scanner's drawn node (its booth is reported, not failed: below).
var _basic_node: Node3D = null
## Moment name -> its group (see _hit()); removed once plated.
var _moments := {}
## Roles still to fill (ROLES).
var _roles: Array = []
## Passenger id -> its role, while a kind role's passenger has not reached the
## lane (one that goes to the basic scanner gives its role back).
var _role_of := {}
var _sheets := {}


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_beat("init")
	_guard = Thread.new()
	_guard.start(_watch)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_beat(_stage)
	return false


func _beat(stage: String) -> void:
	_guard_mutex.lock()
	_stage = stage
	_heartbeat_ms = Time.get_ticks_msec()
	_guard_mutex.unlock()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_guard_mutex.lock()
		var stop := _guard_stop
		var idle_ms := Time.get_ticks_msec() - _heartbeat_ms
		var stage := _stage
		_guard_mutex.unlock()
		if stop:
			return
		if idle_ms > HANG_LIMIT_MS:
			print("PROBE_INVALID hang stage=%s no heartbeat for %d ms" % [stage, idle_ms])
			OS.crash("security visuals probe hung")


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	await _boot()
	if not _sweep_only:
		_define_moments()
		await _play()
	for name in _moments:
		_invalid("moment %s never happened" % name)
	await _benchmark()
	for group in _sheets:
		_save(_sheet(_sheets[group]), "%s_strip" % group, "")
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


# ------------------------------------------------------------------ setup


func _boot() -> void:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	# --seed=N replays a run; otherwise a new random seed.
	var seed := randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = int(arg.get_slice("=", 1))
	_clock.seed_rng(seed)
	_seed = seed
	_sweep_only = OS.get_cmdline_user_args().has("--sweep-only")
	print("PROBE sim_seed=", seed)
	root.add_child(_main)
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_sim = _main.get_node("PassengerSim")
	_views = _main.get_node("PassengerViews")
	var hud := _main.get_node("PassengerHud") as PassengerHud
	await _frames(5)
	hud.press_starter_terminal()
	var build := _main.get_node("BuildMode") as BuildMode
	build.set_tool(BuildMode.Tool.NONE)
	_build_lane(build)
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	hired += int(staff.hire(StaffMember.Role.SECURITY) != 0)
	var flights := _main.get_node("FlightSim") as FlightSim
	var doors := StarterFlight.advance_until_open(_clock, flights, staff)
	print(
		(
			"PROBE hired=%d doors_tick=%d lane_open=%s primary=%d helper=%d"
			% [
				hired,
				doors,
				staff.is_open(_arch),
				staff.staff_at(_arch),
				staff.staff_at(_arch, StaffMember.Slot.HELPER)
			]
		)
	)
	if doors < 0 or not staff.is_open(_arch):
		_invalid("the airport did not open or the lane is not staffed")
	hud.press_speed(1)
	await _frames(10)
	await _plate_officers(staff)


func _build_lane(build: BuildMode) -> void:
	var grid := build.grid
	# The starter's scanners stand on x 17 and 19; the officer spot of the one
	# on 17 is where the lane's primary officer stands, so the basic scanner
	# moves one cell west.
	for cell in OLD_SCANNERS:
		var old := grid.object_at(cell)
		if old != 0:
			_must(grid.apply(BuildEdit.remove_object(old)), "remove the scanner at %s" % cell)
	var gap := Vector2i(BASIC_AT.x, ARCH_AT.y)
	_must(grid.apply(BuildEdit.remove_wall(gap, BuildGrid.Side.NORTH)), "open the divider")
	_must(grid.apply(BuildEdit.place_object(&"security_scanner", BASIC_AT, 0)), "basic scanner")
	_lane = SecurityLanes.geometry(ARCH_AT, 0, MIRROR)
	for x in range(ARCH_AT.x - 2, ARCH_AT.x + 2):
		if grid.has_wall(Vector2i(x, ARCH_AT.y), BuildGrid.Side.NORTH):
			_must(
				grid.apply(BuildEdit.remove_wall(Vector2i(x, ARCH_AT.y), BuildGrid.Side.NORTH)),
				"open the divider at x %d" % x
			)
	_must(grid.apply(BuildEdit.place_object(SecurityLanes.ARCH, ARCH_AT, 0)), "arch")
	for part in [SecurityLanes.TRAY_TABLE, SecurityLanes.XRAY_BELT, SecurityLanes.PICKUP_TABLE]:
		_must(grid.apply(BuildEdit.place_object(part, _lane[part], 0)), str(part))
	(build.get_node("BuildView") as BuildView).refresh(grid)
	_arch = grid.object_at(ARCH_AT)
	var lanes := _sim.layout.security_lanes
	print(
		(
			"LANE arch=%d status=%s scanners=%s cells=%s"
			% [_arch, lanes.status_text(_arch), _sim.layout.scanners, _lane]
		)
	)
	if not lanes.is_complete(_arch):
		_invalid("the lane is not whole: %s" % lanes.status_text(_arch))
	_lane = lanes.lane(_arch)
	for part in [SecurityLanes.TRAY_TABLE, SecurityLanes.XRAY_BELT, SecurityLanes.PICKUP_TABLE]:
		var cells: Array[Vector2i] = [_lane[part]]
		var xf := BuildView.object_transform(grid, cells, 0)
		_part_boxes.append([str(part), xf, _piece_box(part)])
	var arch_cells: Array[Vector2i] = [ARCH_AT]
	var arch_xf := BuildView.object_transform(grid, arch_cells, 0)
	var arch_node: Node3D = null
	for child in (build.get_node("BuildView") as BuildView).get_children():
		if not child.has_meta("record"):
			continue
		# The probe's grid holds one lane, so every lane part drawn is one of it.
		var def := StringName(child.get_meta("record")["def"])
		if SecurityLanes.is_part(def):
			_part_nodes.append(child)
		if def == SecurityLanes.ARCH:
			arch_node = child
		if def == &"security_scanner":
			_basic_node = child
	var inner := _arch_clear_half(arch_node) if arch_node != null else 0.0
	var outer := _piece_box(SecurityLanes.ARCH).end.x
	print("ARCH clear_width_m=%.3f outer_width_m=%.3f" % [inner * 2.0, outer * 2.0])
	if arch_node == null or inner < 0.3:
		_invalid("the arch's posts were not found")
	# Each post as drawn: its 0.04 m feet 0.84 m deep, the panels above them
	# as deep as the arch's meshes reach there (read like the clear width).
	var deep := CarryChecks.arch_post_half_depth(arch_node) if arch_node != null else 0.42
	print("ARCH post_depth_m=%.3f above the feet" % [deep * 2.0])
	for sign in [-1.0, 1.0]:
		var x := inner if sign > 0 else -outer
		var feet := AABB(Vector3(x, 0.0, -0.42), Vector3(outer - inner, 0.045, 0.84))
		var posts := AABB(
			Vector3(x, 0.045, -deep), Vector3(outer - inner, 2.42 - 0.045, deep * 2.0)
		)
		_part_boxes.append(["arch_post", arch_xf, feet])
		_part_boxes.append(["arch_post", arch_xf, posts])
	_wall_boxes(grid)
	_controls(grid)


## Negative controls for the clearance checks, so a zero count means clear
## and not blind: a bag sunk into the tray table's cabinet must be inside its
## meshes, and a bag on a wall edge must hit the wall boxes.
func _controls(grid: BuildGrid) -> void:
	var table: Node3D = null
	for part in _part_nodes:
		if StringName(part.get_meta("record")["def"]) == SecurityLanes.TRAY_TABLE:
			table = part
	var sunk := Transform3D(
		Basis.IDENTITY, grid.cell_to_world(_lane["tray_table"]) + Vector3.UP * 0.3
	)
	var in_table := CarryContact.inside_meshes(CarryContact.bag_points(sunk), table) if table else 0
	var wall_hits := 0
	for entry in _part_boxes:
		if entry[0] == "wall":
			var wall_box: AABB = entry[2]
			var base := wall_box.get_center()
			base.y = wall_box.position.y
			var on_wall := Transform3D(Basis.IDENTITY, base)
			wall_hits = _box_hits(CarryContact.bag_points(on_wall)).get("wall", 0)
			break
	print("CONTROL bag_in_tray_table_cabinet=%d bag_on_wall=%d" % [in_table, wall_hits])
	if in_table == 0 or wall_hits == 0:
		_invalid("a clearance control found no contact, so the checks are blind")


func _must(result: BuildResult, what: String) -> void:
	if not result.ok:
		_invalid("%s refused: %s" % [what, result.reason_text()])


func _piece_box(piece: StringName) -> AABB:
	var node := InteriorKit.instantiate(piece)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var b := mi.transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	node.free()
	return box


## Spawns a passenger and gives it the first open role its first bag's kind
## fits (a role for that kind first, then one for any kind); with none it
## goes through without bags.
func _send() -> int:
	var id := _sim.spawn_now(StarterFlight.first_flight())
	var p := _sim.get_passenger(id)
	var kind := SecurityLooks.bag_kind(p, 0)
	var traits: Array = [-1, 0, false, false]
	for want in [kind, -1]:
		var at := _roles.find_custom(func(r: Array) -> bool: return r[0] == want)
		if at >= 0:
			traits = _roles.pop_at(at)
			break
	print("SEND passenger=%d kinds=%s role=%s" % [id, [kind, SecurityLooks.bag_kind(p, 1)], traits])
	if traits[0] >= 0:
		_role_of[id] = traits
	p.carry_on = traits[1]
	p.liquids = traits[2]
	p.alarm = traits[3]
	p.hunger = 0
	p.apron = []
	p.apron_mm = 0
	p.stage = Passenger.Stage.TO_SECURITY
	p.clear_path()
	return id


# ---------------------------------------------------------------- moments


func _define_moments() -> void:
	for name in [
		"lane_1_queue_hold",
		"lane_2_unpack",
		"lane_3_ride_in",
		"lane_4_ride_scan",
		"lane_5_ride_out",
		"lane_6_pickup",
		"lane_7_leave",
		"alarm_1_to_berth",
		"alarm_2_repack",
		"alarm_3_walk_back",
		"alarm_4_second_pass",
		"alarm_5_pickup",
		"basic_1_scan",
		"basic_2_repack",
		"lane_8_live_crossing",
		"alarm_7_front_one_bag",
		"alarm_8_front_two_bags",
	]:
		_moments[name] = name.get_slice("_", 0)
	for kind in KIND_NAMES:
		for moment in KIND_MOMENTS:
			_moments["kind_%s_%s" % [kind, moment]] = "kinds"
	_moments["kind_backpack_from_behind"] = "kinds"
	_roles = ROLES.duplicate(true)


## Whether passenger `p` shows moment `name` now.
func _hit(name: String, p: Passenger) -> bool:
	if name == "lane_1_queue_hold":
		return (
			p.stage == Passenger.Stage.SECURITY_QUEUE
			and p.station == _arch
			and _views.security_offset(p.id).length() > 0.3
		)
	if p.stage != Passenger.Stage.SECURITY or p.station == 0:
		return false
	var done := SecurityRuntime.work_for(p.security_phase, p) - p.security_work
	if name.begins_with("basic"):
		if p.station == _arch or p.carry_on == 0:
			return false
		if name == "basic_1_scan":
			return p.security_phase == SecurityRuntime.Phase.SCAN and p.is_moving()
		return p.security_phase == SecurityRuntime.Phase.REPACK and done >= 20
	return p.station == _arch and _lane_hit(name, p, done)


func _lane_hit(name: String, p: Passenger, done: int) -> bool:
	var first := not p.incident_resolved
	var phase := p.security_phase
	var hit := false
	match name:
		"alarm_7_front_one_bag", "alarm_8_front_two_bags":
			# Carried in front through the corridor, the turn finished.
			var bags := 1 if name == "alarm_7_front_one_bag" else 2
			hit = (
				phase == SecurityRuntime.Phase.RETURN
				and p.carry_on == bags
				and (
					SecurityLooks.Kind.CASE
					in [SecurityLooks.bag_kind(p, 0), SecurityLooks.bag_kind(p, 1)]
				)
				and p.at == _lane["return_route"][0]
				and _views.carry_on_props().front_weight_of(p.id) >= 1.0
			)
		"lane_8_live_crossing":
			hit = phase == SecurityRuntime.Phase.UNPACK and first
		"lane_2_unpack":
			hit = Staged.lift_ends(_sim, p, _progress(p))
		"lane_3_ride_in":
			hit = _riding(p, first, 0.2)
		"lane_4_ride_scan":
			hit = _riding(p, first, 0.5)
		"lane_5_ride_out":
			hit = _riding(p, first, 0.8)
		"lane_6_pickup":
			hit = first and phase == SecurityRuntime.Phase.PICKUP and p.carry_on > 0
		"lane_7_leave":
			hit = first and phase == SecurityRuntime.Phase.LEAVE and p.carry_on > 0
		"alarm_1_to_berth":
			hit = phase == SecurityRuntime.Phase.TO_BERTH
		"alarm_2_repack":
			hit = phase == SecurityRuntime.Phase.REPACK and done >= 20
		"alarm_3_walk_back":
			hit = phase == SecurityRuntime.Phase.RETURN and p.is_moving()
		"alarm_4_second_pass":
			hit = _riding(p, not first, 0.4)
		"alarm_5_pickup":
			hit = not first and phase == SecurityRuntime.Phase.PICKUP
	return hit


## A kind moment (KIND_MOMENTS) for a passenger whose first bag is that kind.
func _kind_hit(name: String, p: Passenger) -> bool:
	var kind := KIND_NAMES.find(name.get_slice("_", 1))
	if p.carry_on == 0 or SecurityLooks.bag_kind(p, 0) != kind:
		return false
	var homes := SecurityLooks.bag_homes(_sim, p)
	var all_in := func(home: SecurityLooks.Home) -> bool:
		return homes.all(func(h: SecurityLooks.Home) -> bool: return h == home)
	var lane := p.stage == Passenger.Stage.SECURITY and p.station == _arch
	var phase := p.security_phase
	var hit := false
	match name.trim_prefix("kind_%s_" % KIND_NAMES[kind]):
		"carried", "from_behind":
			hit = (
				lane
				and phase == SecurityRuntime.Phase.LEAVE
				and all_in.call(SecurityLooks.Home.HAND)
			)
		"tray":
			hit = (
				_riding(p, not p.incident_resolved, 0.1)
				and _progress(p) < 0.45
				and all_in.call(SecurityLooks.Home.TRAY)
			)
		"berth":
			hit = lane and p.carry_on == 1 and _repacked(p)
		"seat":
			hit = p.stage == Passenger.Stage.SEATED and all_in.call(SecurityLooks.Home.FLOOR)
		"live_walk_back":
			hit = lane and p.carry_on == 1 and _repacked(p) and not p.incident_resolved
	return hit


## A lane passenger repacking at the berth, its bags down a while.
func _repacked(p: Passenger) -> bool:
	var done := SecurityRuntime.work_for(p.security_phase, p) - p.security_work
	return p.security_phase == SecurityRuntime.Phase.REPACK and done >= 20


func _riding(p: Passenger, pass_ok: bool, at: float) -> bool:
	return pass_ok and p.security_phase == SecurityRuntime.Phase.ARCH and _progress(p) >= at


## A lane passenger's drawn progress from the unpack cell to the pickup cell.
func _progress(p: Passenger) -> float:
	var node := _views.node_for(p.id)
	if node == null:
		return -1.0
	var unpack := _sim.grid.cell_to_world(_lane["unpack"])
	var along := _sim.grid.cell_to_world(_lane["pickup"]) - unpack
	return (node.global_position - unpack).dot(along) / along.length_squared()


func _play() -> void:
	var sent := 0
	var next_send := _clock.tick
	var whole_done := false
	var stop := _clock.tick + RUN_LIMIT_TICKS
	while not _moments.is_empty() and _clock.tick < stop:
		_beat("play tick %d" % _clock.tick)
		for id in _role_of.keys():
			var at := _sim.get_passenger(id)
			if at == null:
				# Left the sim before reaching security: its role goes back.
				print("ROLE back passenger=%d left the sim" % id)
				_roles.append(_role_of[id])
				_role_of.erase(id)
			elif at.stage == Passenger.Stage.SECURITY and at.station != 0:
				if at.station != _arch:
					print("ROLE back passenger=%d went to the basic scanner" % id)
					_roles.append(_role_of[id])
				_role_of.erase(id)
		if not _roles.is_empty() and _clock.tick >= next_send:
			_send()
			sent += 1
			next_send = _clock.tick + SEND_GAP_TICKS
		await process_frame
		for name in _moments.keys():
			var found := _match(name)
			if found == 0:
				continue
			var group: String = _moments[name]
			if name == "lane_8_live_crossing":
				await _plate_live(found)
				_moments.erase(name)
			elif name.ends_with("live_walk_back"):
				await _plate_live_walk_back(found, name)
				_moments.erase(name)
			elif await _plate(name, group, found, DISTANCE_M):
				_moments.erase(name)
			break
		if not whole_done and _in_security() >= 4:
			whole_done = await _plate_whole()
	print("PROBE play ended tick=%d sent=%d left=%s" % [_clock.tick, sent, _moments.keys()])


func _match(name: String) -> int:
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		var hit := _kind_hit(name, p) if name.begins_with("kind_") else _hit(name, p)
		if _views.node_for(id) == null or not _settled(id) or not hit:
			continue
		# A passenger the sim walks through another one (they share cells) is
		# not a fair plate subject: wait for a moment with room around it.
		if name == "lane_1_queue_hold" or _room_around(id) >= 0.5:
			return id
	return 0


## Whether every bag of passenger `id` has finished moving to its home.
func _settled(id: int) -> bool:
	var props := _views.carry_on_props()
	var turning := props.front_weight_of(id)
	if turning > 0.0 and turning < 1.0:
		return false
	for i in props.props_of(id)["bags"].size():
		if props.transfer_progress(id, i) < 1.0:
			return false
	return true


## The distance from passenger `id` to the nearest other drawn passenger.
func _room_around(id: int) -> float:
	var me := _views.node_for(id).global_position
	var nearest := INF
	for other in _sim.passenger_ids():
		var node := _views.node_for(other)
		if other != id and node != null:
			nearest = minf(nearest, node.global_position.distance_to(me))
	return nearest


func _in_security() -> int:
	var count := 0
	for id in _sim.passenger_ids():
		count += int(_sim.get_passenger(id).stage == Passenger.Stage.SECURITY)
	return count


func _aim(at: Vector3, distance: float, yaw: float) -> void:
	_rig.stop_follow()
	_rig.position = Vector3(at.x, 0.0, at.z)
	_rig.yaw = yaw
	_rig.distance = distance


# ------------------------------------------------------------------ plates


## Plates passenger `id` with its props from the first of four headings where
## everything is shown. Returns whether a plate was saved.
func _plate(name: String, group: String, id: int, distance: float) -> bool:
	paused = true
	var p := _sim.get_passenger(id)
	print(
		(
			"MOMENT %s tick=%d passenger=%d stage=%d phase=%d bags=%d liquids=%s alarm=%s"
			% [name, _clock.tick, id, p.stage, p.security_phase, p.carry_on, p.liquids, p.alarm]
		)
	)
	var body := _views.node_for(id)
	var ok := false
	for turn in 4:
		var yaw := wrapf(0.6 + turn * PI / 2.0, -PI, PI)
		_beat("%s turn %d" % [name, turn])
		_aim(body.global_position, distance, yaw)
		paused = false
		var keep := _clock.paused
		_clock.set_paused(true)
		await _frames(20)
		paused = true
		_clock.set_paused(keep)
		var result: Dictionary = await _check(name, id, yaw)
		if name.ends_with("_from_behind"):
			# Only a heading that looks at the passenger's back counts.
			var look := body.global_position - _cam.global_position
			look.y = 0.0
			var ahead := Basis(Vector3.UP, body.rotation.y) * Vector3.BACK
			var behind := look.normalized().dot(ahead)
			print("BEHIND %s yaw=%.2f look_dot_forward=%.2f" % [name, yaw, behind])
			result["ok"] = result["ok"] and behind > 0.5
		if result["ok"]:
			_save(result["image"], name, group)
			ok = true
			break
		if turn == 3:
			_save(result["image"], name + "_INVALID", "")
	_check_clearance(name, id)
	paused = false
	if not ok:
		_invalid("%s: passenger %d or its props not shown from any heading" % [name, id])
	return true


func _check(name: String, id: int, yaw: float) -> Dictionary:
	var img: Image = await PlateSight.grab(self)
	var subjects := {}
	var body := _views.node_for(id)
	subjects[body] = str(id)
	var props := _views.carry_on_props().props_of(id)
	var prop_tags := {}
	if props["tray"] != null:
		subjects[props["tray"]] = "tray"
		prop_tags["tray"] = props["tray"]
	for i in props["bags"].size():
		subjects[props["bags"][i]] = "bag%d" % i
		prop_tags["bag%d" % i] = props["bags"][i]
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		owners.append(_main.get_node(path))
	var holder := PlateSight.colliders(root, owners, subjects)
	var bounds: Dictionary = holder.get_meta("bounds")
	var unbaked: Array = holder.get_meta("unbaked")
	await physics_frame
	await physics_frame
	var twin: Dictionary = await PlateSight.hud_twin(self, _main)
	var bare: Image = twin["image"]
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)
	var box: AABB = bounds.get(str(id), AABB())
	var seen := PlateSight.person_shown(_cam, box, str(id), frame, img, bare, MIN_SUBJECT_PX)
	var ok: bool = seen["ok"] and unbaked.is_empty()
	if not unbaked.is_empty():
		print("UNBAKED %s %s" % [name, unbaked])
	print(
		(
			(
				"INFRAME %s yaw=%.2f passenger=%d px=%s height_px=%.0f on=%d"
				+ " blockers=%s in_frame=%s hud_px=%d ok=%s"
			)
			% [
				name,
				yaw,
				id,
				seen.get("px"),
				seen.get("height_px", 0.0),
				seen["on"],
				seen["blockers"],
				seen.get("in_frame"),
				seen.get("hud_px", 0),
				seen["ok"]
			]
		)
	)
	var space := _cam.get_world_3d().direct_space_state
	var blocker_checked := false
	for tag in prop_tags:
		var prop_box: AABB = bounds.get(tag, AABB())
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for i in 8:
			var s := _cam.unproject_position(prop_box.get_endpoint(i))
			lo = lo.min(s)
			hi = hi.max(s)
		var in_frame := frame.has_point(lo) and frame.has_point(hi)
		var size := maxf(hi.x - lo.x, hi.y - lo.y)
		var targets := _facing_points(prop_tags[tag])
		var lines := PlateSight.sight_lines(space, _cam.global_position, targets, tag)
		var hits: int = (lines["on_subject"] as Array).size()
		# A tray inside the X-ray tunnel is hidden by design. Every other prop,
		# a carried bag included, must be hit by a sight line from this heading;
		# a heading where a bag is behind its carrier fails and the next is tried.
		var tunnel := name == "lane_4_ride_scan"
		var prop_ok := _prop_shown(in_frame, size, hits, tunnel)
		var homes := SecurityLooks.bag_homes(_sim, _sim.get_passenger(id))
		var carried: bool = (
			tag.begins_with("bag") and homes[int(tag.trim_prefix("bag"))] == SecurityLooks.Home.HAND
		)
		if carried and prop_ok and not blocker_checked:
			# Negative control: an opaque box between the camera and the bag
			# must leave the same check with no hit, so a pass means seen.
			blocker_checked = true
			var blocked := await _blocked_hits(holder, prop_box, targets, tag)
			print("CONTROL %s %s sight_hits_with_blocker=%d" % [name, tag, blocked])
			if _prop_shown(in_frame, size, blocked, tunnel):
				_invalid(
					(
						"%s: %s still passed with an opaque blocker in front (blind check)"
						% [name, tag]
					)
				)
		print(
			(
				(
					"PROP %s %s screen=(%.0f,%.0f)-(%.0f,%.0f) size_px=%.0f sight_hits=%d/%d"
					+ " past=%d blockers=%s ok=%s"
				)
				% [
					name,
					tag,
					lo.x,
					lo.y,
					hi.x,
					hi.y,
					size,
					hits,
					targets.size(),
					lines["past"],
					lines["blockers"],
					prop_ok
				]
			)
		)
		ok = ok and prop_ok
	holder.free()
	return {"ok": ok, "image": img}


## Whether a prop is shown: in frame, big enough and hit by a sight line (a
## tray in the X-ray tunnel is hidden by design).
func _prop_shown(in_frame: bool, size: float, hits: int, tunnel: bool) -> bool:
	return in_frame and size >= MIN_PROP_PX and (hits >= 1 or tunnel)


## The sight lines to a prop's `targets` that land on it with a 1 m opaque box
## standing between the camera and the prop (0 when the box hides it). The box
## is removed again.
func _blocked_hits(holder: Node3D, prop_box: AABB, targets: Array[Vector3], tag: String) -> int:
	var centre := prop_box.get_center()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE
	var shape_node := CollisionShape3D.new()
	shape_node.shape = shape
	var blocker := StaticBody3D.new()
	blocker.set_meta("mesh", "control_blocker")
	blocker.add_child(shape_node)
	holder.add_child(blocker)
	blocker.global_position = centre + (_cam.global_position - centre).normalized() * 0.9
	await physics_frame
	await physics_frame
	var space := _cam.get_world_3d().direct_space_state
	var lines := PlateSight.sight_lines(space, _cam.global_position, targets, tag)
	blocker.free()
	return (lines["on_subject"] as Array).size()


## Up to twelve midpoints of a prop's triangles that face the camera, nudged
## 1 cm out along the line to the camera so a sight line lands on the surface.
func _facing_points(prop: Node3D) -> Array[Vector3]:
	var mids: Array[Vector3] = []
	for mi: MeshInstance3D in prop.find_children("*", "MeshInstance3D", true, false):
		var faces := mi.mesh.get_faces()
		for i in range(0, faces.size() - 2, 3):
			var a := mi.global_transform * faces[i]
			var b := mi.global_transform * faces[i + 1]
			var c := mi.global_transform * faces[i + 2]
			var mid := (a + b + c) / 3.0
			var to_cam := (_cam.global_position - mid).normalized()
			if (b - a).cross(c - a).dot(to_cam) < 0.0:
				mids.append(mid + to_cam * 0.01)
	var out: Array[Vector3] = []
	var step := maxi(1, floori(mids.size() / 12.0))
	for i in range(0, mids.size(), step):
		out.append(mids[i])
	return out


## Clearance of the subject in its drawn pose: body points (both hands
## included) inside a lane part, an arch post or a wall; carried and floor bag
## points inside a part, a post or a wall; and body points inside one of its
## own bags' meshes (the gripping hand left out, CarryContact). Prints every
## count; any contact fails the probe.
func _check_clearance(name: String, id: int) -> void:
	var body := _views.node_for(id)
	var p := _sim.get_passenger(id)
	var homes := SecurityLooks.bag_homes(_sim, p)
	var points := CarryContact.body_points(body, [])
	var part_hits := _box_hits(points)
	var own := CarryContact.body_points(body, CarryChecks.gripping(_sim, p))
	if not _body_control_done:
		# Control: a bag at the hips must hold body points.
		var at_hips := Transform3D(Basis.IDENTITY, body.global_position + Vector3.UP * 0.85)
		var control := CarryContact.inside_bag(own, at_hips)
		print("CONTROL body_points_in_a_bag_at_the_hips=%d" % control)
		if control == 0:
			_invalid("the bag-body check found no contact in its control")
		_body_control_done = true
	var bags: Array[Node3D] = _views.carry_on_props().props_of(id)["bags"]
	var bag_body := 0
	var bag_parts := {}
	for i in bags.size():
		if homes[i] == SecurityLooks.Home.TRAY:
			continue
		bag_body += CarryContact.inside_meshes(own, bags[i])
		var bag_points := CarryChecks.surface(bags[i])
		var hits := _box_hits(bag_points)
		for key in hits:
			if key == "wall" or key == "arch_post":
				bag_parts[key] = bag_parts.get(key, 0) + hits[key]
		for part in _part_nodes:
			var inside := CarryContact.inside_meshes(bag_points, part)
			if inside > 0:
				bag_parts[part.name] = bag_parts.get(part.name, 0) + inside
	var nearest := INF
	for other in _sim.passenger_ids():
		var node := _views.node_for(other)
		if other != id and node != null:
			nearest = minf(nearest, node.global_position.distance_to(body.global_position))
	bag_body += CarryChecks.bag_bag(bags)
	if bag_body > 0:
		for bag in bags:
			print(
				(
					"CONTACT %s bones=%s bag_bag=%d"
					% [
						name,
						CarryChecks.contact_bones(body, CarryChecks.gripping(_sim, p), bag),
						CarryChecks.bag_bag(bags)
					]
				)
			)
	print(
		(
			(
				"CLEARANCE %s passenger=%d body_points=%d body_part_contacts=%s"
				+ " bag_part_contacts=%s bag_body_or_bag_contacts=%d bags=%s kinds=%s"
				+ " nearest_passenger_m=%.2f"
			)
			% [
				name,
				id,
				points.size(),
				part_hits,
				bag_parts,
				bag_body,
				homes,
				_views.carry_on_props().props_of(id)["kinds"],
				nearest
			]
		)
	)
	if _basic_node != null and p.station == _sim.grid.object_at(BASIC_AT):
		# The basic scanner's 0.70 m booth is another asset (the interior
		# kit's security_scanner), outside this lane's work: its contacts are
		# printed for the report and do not fail the probe.
		var in_booth := CarryContact.inside_meshes(points, _basic_node)
		var bags_in_booth := 0
		for i in bags.size():
			bags_in_booth += CarryContact.inside_meshes(CarryChecks.surface(bags[i]), _basic_node)
		print(
			(
				"BASIC_SCANNER %s body_points_in_booth=%d bag_points_in_booth=%d (reported, not failed)"
				% [name, in_booth, bags_in_booth]
			)
		)
	if points.is_empty():
		_invalid("%s: no drawn body points to check" % name)
	if not part_hits.is_empty() or not bag_parts.is_empty() or bag_body > 0:
		_invalid("%s: passenger %d or its bags clip a lane part, a wall or the body" % [name, id])


## Points inside each solid box (lane parts, arch posts, walls), by its name.
func _box_hits(points: PackedVector3Array) -> Dictionary:
	var hits := {}
	for entry in _part_boxes:
		var inv: Transform3D = (entry[1] as Transform3D).affine_inverse()
		var box: AABB = (entry[2] as AABB).grow(-0.002)
		for v in points:
			if box.has_point(inv * v):
				hits[entry[0]] = hits.get(entry[0], 0) + 1
	return hits


## The arch's clear half-width, read from its drawn meshes: the nearest
## vertex to the centre line, between the floor mat and the beam, that is
## off the centre (the posts' inner face).
func _arch_clear_half(arch: Node3D) -> float:
	var inner := INF
	var inv := arch.global_transform.affine_inverse()
	for mi: MeshInstance3D in arch.find_children("*", "MeshInstance3D", true, false):
		for v in mi.mesh.get_faces():
			var local := inv * (mi.global_transform * v)
			if local.y > 0.05 and local.y < 2.15 and absf(local.x) > 0.2:
				inner = minf(inner, absf(local.x))
	return inner


## Solid boxes for every wall edge near the lane (0.12 m thick, 2.6 m tall).
func _wall_boxes(grid: BuildGrid) -> void:
	var count := 0
	for y in range(ARCH_AT.y - 4, ARCH_AT.y + 5):
		for x in range(ARCH_AT.x - 5, ARCH_AT.x + 3):
			var cell := Vector2i(x, y)
			for side in [
				BuildGrid.Side.NORTH, BuildGrid.Side.EAST, BuildGrid.Side.SOUTH, BuildGrid.Side.WEST
			]:
				if not grid.has_wall(cell, side):
					continue
				var step: Vector2i = BuildGrid.SIDE_STEP[side]
				var centre := grid.cell_to_world(cell) + Vector3(step.x, 0.0, step.y) * 0.5
				var size := Vector3(1.0 if step.x == 0 else 0.12, 2.6, 1.0 if step.y == 0 else 0.12)
				var box := AABB(centre - Vector3(size.x / 2.0, 0.0, size.z / 2.0), size)
				_part_boxes.append(["wall", Transform3D.IDENTITY, box])
				count += 1
	print("WALLS boxes=%d near the lane" % count)


## The lane's two officers on their spots (primary beside the X-ray belt,
## helper beside the berth), each shown (PlateSight) and in frame, with the
## way each faces printed against the belt, the berth and the arch's front.
func _plate_officers(staff: StaffSim) -> void:
	var characters := _main.get_node("StaffCharacters") as StaffCharacters
	var subjects := {}
	var rows := []
	var ok := true
	for slot in [StaffMember.Slot.PRIMARY, StaffMember.Slot.HELPER]:
		var id := staff.staff_at(_arch, slot)
		var member := staff.get_member(id) if id != 0 else null
		var node := characters.node_for(id) if id != 0 else null
		if member == null or node == null:
			_invalid("lane officer in slot %d is missing" % slot)
			return
		var spot := staff.spot_of(_arch, slot)
		var faces := Vector2(sin(node.global_rotation.y), cos(node.global_rotation.y))
		var to_belt := Vector2(_lane["xray_belt"] - spot).normalized()
		var to_berth := Vector2(_lane["berth"] - spot).normalized()
		var front := Vector2(_lane["front"])
		rows.append(
			(
				(
					"OFFICER slot=%s id=%d at=%s spot=%s on_duty=%s faces=%s"
					+ " dot_belt=%.2f dot_berth=%.2f dot_arch_front=%.2f"
				)
				% [
					"primary" if slot == StaffMember.Slot.PRIMARY else "helper",
					id,
					member.at,
					spot,
					member.state == StaffMember.State.ON_DUTY,
					faces.snapped(Vector2.ONE * 0.01),
					faces.dot(to_belt),
					faces.dot(to_berth),
					faces.dot(front)
				]
			)
		)
		ok = ok and member.at == spot and member.state == StaffMember.State.ON_DUTY
		subjects[node] = "officer%d" % slot
	for row in rows:
		print(row)
	if not ok:
		_invalid("a lane officer is not on duty on its spot")
	paused = true
	var centre := _sim.grid.cell_to_world(ARCH_AT)
	for turn in 4:
		var yaw := wrapf(0.6 + turn * PI / 2.0, -PI, PI)
		_aim(centre, 8.0, yaw)
		paused = false
		_clock.set_paused(true)
		await _frames(20)
		paused = true
		_clock.set_paused(false)
		var img: Image = await PlateSight.grab(self)
		var owners: Array[Node] = []
		for path in OCCLUDER_OWNERS:
			owners.append(_main.get_node(path))
		owners.append(_main.get_node("StaffCharacters"))
		var holder := PlateSight.colliders(root, owners, subjects)
		await physics_frame
		await physics_frame
		var twin: Dictionary = await PlateSight.hud_twin(self, _main)
		var frame := Rect2(
			Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
		)
		var shown := 0
		for node in subjects:
			var tag: String = subjects[node]
			var seen := PlateSight.person_shown(
				_cam,
				holder.get_meta("bounds").get(tag, AABB()),
				tag,
				frame,
				img,
				twin["image"],
				MIN_SUBJECT_PX
			)
			print(
				(
					"INFRAME officers yaw=%.2f %s px=%s on=%d blockers=%s ok=%s"
					% [yaw, tag, seen.get("px"), seen["on"], seen["blockers"], seen["ok"]]
				)
			)
			shown += int(seen["ok"])
		holder.free()
		if shown == subjects.size():
			_save(img, "officers_on_spots", "whole")
			paused = false
			return
	paused = false
	_invalid("the two lane officers are not both shown from any heading")


## A plate strip of one lane passenger crossing the arch while the game runs
## (no pause): the camera is set on the arch while the passenger unpacks, then
## every frame of its first ARCH pass is checked against the posts, and three
## frames are grabbed and checked in frame with sight lines past the static
## scene (the build and the shell).
func _plate_live(id: int) -> bool:
	var p := _sim.get_passenger(id)
	var arch := _sim.grid.cell_to_world(ARCH_AT)
	_aim(arch, DISTANCE_M, 0.6 + PI / 2.0)
	await _frames(30)
	var owners: Array[Node] = [_main.get_node("Airside/Terminal"), _main.get_node("BuildMode")]
	var holder := PlateSight.colliders(root, owners, {})
	await physics_frame
	await physics_frame
	var frames := 0
	var worst := 0
	var marks := [0.5, 0.65, 0.8]
	var grabbed := 0
	var stop := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < stop:
		_beat("live crossing frame %d" % frames)
		await process_frame
		if p.stage != Passenger.Stage.SECURITY or p.security_phase > SecurityRuntime.Phase.ARCH:
			break
		if p.security_phase != SecurityRuntime.Phase.ARCH:
			continue
		var body := _views.node_for(id)
		var hits := _box_hits(CarryContact.body_points(body, []))
		frames += 1
		worst = maxi(worst, hits.get("arch_post", 0) + hits.get("wall", 0))
		var at := _progress(p)
		if grabbed < marks.size() and at >= marks[grabbed]:
			var img := root.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			var ok := _live_shown(body, "live_crossing_%d" % grabbed, at)
			if ok:
				_save(img, "lane_8_live_crossing_%d" % grabbed, "live")
			else:
				_invalid("live crossing frame %d: the passenger is not shown" % grabbed)
			grabbed += 1
	holder.free()
	print(
		(
			"LIVE crossing passenger=%d frames_checked=%d worst_post_or_wall_contacts=%d grabbed=%d"
			% [id, frames, worst, grabbed]
		)
	)
	if frames < 10 or grabbed < marks.size():
		_invalid("live crossing: only %d frames and %d plates" % [frames, grabbed])
	if worst > 0:
		_invalid("live crossing: the walking passenger touches an arch post or wall")
	return true


## The alarm walk-back while the game runs (no pause), with the bag in hand:
## from the repack through the one-cell corridor between the arch and the
## wall to the return route's end. Every frame the body, and each carried
## bag, are checked against the lane parts, the arch posts and the walls, and
## the body against its own bags. Three frames are plated (leaving the
## berth, in the corridor, at the route's end). The check runs on through the
## second pass's walk to the unpack cell while a bag is in hand. Control: the
## carry turns to the front on some frames and back on later ones.
func _plate_live_walk_back(id: int, name: String) -> bool:
	var p := _sim.get_passenger(id)
	var corridor := _sim.grid.cell_to_world(_lane["return_route"][0])
	_aim(corridor, DISTANCE_M, 0.6 + PI / 2.0)
	await _frames(30)
	var owners: Array[Node] = [_main.get_node("Airside/Terminal"), _main.get_node("BuildMode")]
	var holder := PlateSight.colliders(root, owners, {})
	await physics_frame
	await physics_frame
	var props := _views.carry_on_props()
	var frames := 0
	var front_frames := 0
	var side_after := 0
	var detached := 0
	var worst := {}
	var cells: Array[Vector2i] = [
		_lane["berth"], _lane["return_route"][0], _lane["return_route"][1]
	]
	var grabbed := 0
	var stop := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < stop:
		_beat("live walk-back frame %d" % frames)
		await process_frame
		if p.stage != Passenger.Stage.SECURITY:
			break
		if p.security_phase == SecurityRuntime.Phase.REPACK:
			continue
		# On through the second pass's walk to the tray while a bag is in hand,
		# so the turn back to the side carry is seen however short RETURN is.
		var in_hand := SecurityLooks.bag_homes(_sim, p).has(SecurityLooks.Home.HAND)
		var second_pass := p.security_phase == SecurityRuntime.Phase.ARCH and in_hand
		if p.security_phase != SecurityRuntime.Phase.RETURN and not second_pass:
			break
		frames += 1
		var body := _views.node_for(id)
		var homes := SecurityLooks.bag_homes(_sim, p)
		var gripping := CarryChecks.gripping(_sim, p)
		var drawn: Array[Node3D] = props.props_of(id)["bags"]
		var weight := props.front_weight_of(id)
		var carrying := homes.has(SecurityLooks.Home.HAND) and drawn.size() == p.carry_on
		front_frames += int(carrying and weight >= 1.0)
		side_after += int(carrying and front_frames > 0 and weight <= 0.0)
		# Every carried bag stays at the hand that holds it, turns included.
		for i in drawn.size():
			# A bag still moving to the hand (picked up) is not held yet.
			if homes[i] != SecurityLooks.Home.HAND or props.transfer_progress(id, i) < 1.0:
				continue
			var off := CarryChecks.detached(_sim, _views, id, i, body, GRIP_REACH_M)
			if off > 0.0:
				detached += 1
				print(
					(
						"DETACHED walk-back frame=%d at=%s turn=%.2f kind=%s off_m=%.3f"
						% [frames, p.at, weight, props.props_of(id)["kinds"][i], off]
					)
				)
		var counts := _box_hits(CarryContact.body_points(body, []))
		var own := CarryContact.body_points(body, gripping)
		var bag_pair := CarryChecks.bag_bag(drawn)
		if bag_pair > 0:
			counts["bag_bag"] = bag_pair
		for bag: Node3D in drawn:
			var points := CarryChecks.surface(bag)
			for key in _box_hits(points):
				if key == "wall" or key == "arch_post":
					counts["bag_" + key] = counts.get("bag_" + key, 0) + 1
					var where := [
						bag.global_position.snapped(Vector3.ONE * 0.01), body.global_position
					]
					print(
						(
							"CONTACT walk-back frame=%d at=%s %s bag_body=%s"
							% [frames, p.at, key, where]
						)
					)
			for part in _part_nodes:
				if CarryContact.inside_meshes(points, part) > 0:
					counts["bag_" + str(part.name)] = counts.get("bag_" + str(part.name), 0) + 1
			var inside := CarryContact.inside_meshes(own, bag)
			if inside > 0:
				counts["bag_body"] = counts.get("bag_body", 0) + 1
				var bones := CarryChecks.contact_bones(body, gripping, bag)
				print(
					(
						"CONTACT walk-back frame=%d at=%s points=%d bones=%s"
						% [frames, p.at, inside, bones]
					)
				)
		for key in counts:
			worst[key] = worst.get(key, 0) + 1
		if (
			grabbed < cells.size()
			and p.at == cells[grabbed]
			and props.transfer_progress(id, 0) >= 1.0
		):
			var img := root.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			if _live_shown(body, "live_walk_back_%d" % grabbed, float(grabbed)):
				_save(img, "%s_%d" % [name, grabbed], "live")
			else:
				_invalid("live walk-back frame %d: the passenger is not shown" % grabbed)
			grabbed += 1
	holder.free()
	print(
		(
			(
				"LIVE walk-back %s passenger=%d kinds=%s frames_checked=%d front_carry_frames=%d"
				+ " frames_with_contacts=%s grabbed=%d"
			)
			% [name, id, props.props_of(id)["kinds"], frames, front_frames, worst, grabbed]
		)
	)
	print(
		(
			"LIVE walk-back side_carry_after_front_frames=%d detached_bag_frames=%d"
			% [side_after, detached]
		)
	)
	if frames < 10 or grabbed < 3:
		_invalid("live walk-back: only %d frames and %d plates" % [frames, grabbed])
	if front_frames == 0 or side_after == 0:
		_invalid("live walk-back: the bag was not carried in front and back at the side (control)")
	if detached > 0:
		_invalid("live walk-back: a carried bag left the hand")
	if not worst.is_empty():
		_invalid("live walk-back: the passenger or its bag touches a part, a post or a wall")
	return true


func _live_shown(body: Node3D, tag: String, at: float) -> bool:
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)
	var base := body.global_position
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for h in [0.0, 1.0, 1.9]:
		var s := _cam.unproject_position(base + Vector3(0.0, h, 0.0))
		lo = lo.min(s)
		hi = hi.max(s)
	var in_frame := frame.has_point(lo) and frame.has_point(hi)
	var clear := 0
	var space := _cam.get_world_3d().direct_space_state
	for h in [1.0, 1.4, 1.7]:
		var target := base + Vector3(0.0, h, 0.0)
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(_cam.global_position, target)
		)
		clear += int(hit.is_empty())
	var ok := in_frame and clear >= 2 and hi.y - lo.y >= MIN_SUBJECT_PX
	print(
		(
			"INFRAME %s progress=%.2f screen=(%.0f,%.0f)-(%.0f,%.0f) unblocked_lines=%d/3 ok=%s"
			% [tag, at, lo.x, lo.y, hi.x, hi.y, clear, ok]
		)
	)
	return ok


## Frame cost of the carry-on bags with BENCH_CROWD passengers drawn and on
## screen: frame times with their bags, then the same crowd with every bag
## taken away (carry_on 0), as the control.
func _benchmark() -> void:
	# The bench crowd is the spawned one: the moments' own passengers have left
	# the lane first (a tray of one still in it is drawn with no bags).
	var drain := _clock.tick + BENCH_DRAIN_TICKS
	while _in_security() > 0 and _clock.tick < drain:
		_beat("bench drain")
		await process_frame
	if _in_security() > 0:
		_invalid("bench: the lane did not empty within %d ticks" % BENCH_DRAIN_TICKS)
	_beat("bench spawn")
	var flight := StarterFlight.first_flight()
	_sim.spawn_batch(maxi(0, BENCH_CROWD - _views.active_count()), _seed + 1)
	var until := _clock.tick + 240
	while _clock.tick < until:
		_beat("bench walk-in")
		await process_frame
	await _sweep()
	var centre := Vector3.ZERO
	var count := 0
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node != null:
			centre += node.global_position
			count += 1
	_aim(centre / maxi(count, 1), 26.0, 0.6)
	await _frames(30)
	var with_bags := await _frame_times("with bags")
	var flight_ids := _sim.passenger_ids()
	for id in flight_ids:
		_sim.get_passenger(id).carry_on = 0
	await _frames(10)
	var without := await _frame_times("no bags (control)")
	# Bags (not trays) of the passengers zeroed above; the sim spawns new ones.
	var drawn := 0
	for id in flight_ids:
		drawn += _views.carry_on_props().props_of(id)["bags"].size()
	print("BENCH control drawn_bags=%d crowd=%d" % [drawn, _views.active_count()])
	if drawn > 0 or _views.active_count() == 0:
		_invalid("bench: no crowd on screen, or the control still draws bags")
	print(
		(
			"BENCH flight=%s cost_ms_avg=%.2f cost_ms_p95=%.2f"
			% [flight, with_bags[0] - without[0], with_bags[1] - without[1]]
		)
	)


## The crowd sweep: each carrier with every bag settled in hand, its drawn
## body (the holding hands left out) against its bags' meshes and its bags
## against each other, every other frame for SWEEP_FRAMES frames of the live
## walk and queue, then SWEEP_FRAMES / 2 poses of the run clip on the paused
## crowd (seeked). Counts per kind, character and clip are printed; any
## contact fails. Control per kind: one of its bags moved to a carrier's hips
## holds body points.
func _sweep() -> void:
	var props := _views.carry_on_props()
	var checks := {}
	var contacts := {}
	var carriers: Array[int] = []
	# Pulled rollers on the live walk: id -> [axle, yaw] last frame.
	var pulled := {}
	var turns := [0, 0]
	# One roller is turned a quarter turn on purpose (Staged), so a sharp turn
	# is always judged, whatever the seed's walks do.
	var staged := Staged.new()
	for frame in SWEEP_FRAMES * 2 + SWEEP_FRAMES / 2:
		_beat("sweep frame %d" % frame)
		var before: int = turns[0]
		staged.step(_views, _sim, pulled, frame)
		var running := frame >= SWEEP_FRAMES * 2
		if running:
			if not _clock.paused:
				# Late walkers run: the views play the run clip and a roller is
				# lifted, as the game draws them (a snap starts every carry in
				# place, with no move to play on the paused clock).
				_clock.set_paused(true)
				for id in carriers:
					_sim.get_passenger(id).late = true
				_views.snap()
			for id in carriers:
				var player := _views.node_for(id).get_node("AnimationPlayer") as AnimationPlayer
				player.seek(fmod(frame * 0.071, player.current_animation_length), true)
		await process_frame
		if not running:
			CarryChecks.watch_pulled(_sim, _views, pulled, turns, _clock.tick + _clock.alpha)
			staged.count(_views, frame, turns[0] - before)
		if not running and frame % 2 == 1:
			continue
		carriers.clear()
		for id in _sim.passenger_ids():
			var body := _views.node_for(id)
			var p := _sim.get_passenger(id)
			var drawn: Array[Node3D] = props.props_of(id)["bags"]
			if body == null or p.carry_on == 0 or drawn.size() != p.carry_on:
				continue
			var homes := SecurityLooks.bag_homes(_sim, p)
			var settled := homes.all(
				func(h: SecurityLooks.Home) -> bool: return h == SecurityLooks.Home.HAND
			)
			for i in drawn.size():
				settled = settled and props.transfer_progress(id, i) >= 1.0
			if not settled:
				continue
			carriers.append(id)
			var clip := (body.get_node("AnimationPlayer") as AnimationPlayer).current_animation
			var own := CarryContact.body_points(body, CarryChecks.gripping(_sim, p))
			var pair := CarryChecks.bag_bag(drawn)
			if pair > 0:
				contacts["bag_bag"] = contacts.get("bag_bag", 0) + pair
			for i in drawn.size():
				var key := "%s/v%d/%s" % [KIND_NAMES[SecurityLooks.bag_kind(p, i)], p.variant, clip]
				checks[key] = checks.get(key, 0) + 1
				var hits := CarryContact.inside_meshes(own, drawn[i])
				if hits > 0:
					if not contacts.has(key) or key.begins_with("roller"):
						var to_body := body.global_transform.affine_inverse()
						var axle := to_body * (drawn[i].global_transform * CarryOnProps.ROLLER_AXLE)
						var grip := to_body * props.grip_of(body, SecurityLooks.hand_of(_sim, p, i))
						print(
							(
								"SWEEP where %s id=%d i=%d hand=%d axle=%s grip=%s at=%s path=%s"
								% [
									key,
									id,
									i,
									SecurityLooks.hand_of(_sim, p, i),
									axle.snapped(Vector3.ONE * 0.01),
									grip.snapped(Vector3.ONE * 0.01),
									p.at,
									p.path.slice(maxi(0, p.path_index - 2), p.path_index + 2)
								]
							)
						)
					if not contacts.has(key):
						print(
							(
								"SWEEP contact %s bones=%s"
								% [
									key,
									CarryChecks.contact_bones(
										body, CarryChecks.gripping(_sim, p), drawn[i]
									)
								]
							)
						)
					contacts[key] = contacts.get(key, 0) + hits
	_clock.set_paused(false)
	print("SWEEP checks=%s" % [checks])
	print("SWEEP pulled rollers: sharp_turns=%d axle_snaps=%d" % turns)
	print(staged.report())
	for problem in staged.problems():
		_invalid("sweep: " + problem)
	if staged.roller == 0 or staged.sharp == 0:
		_invalid("sweep: the staged sharp turn of a pulled roller was not seen (control)")
	if turns[1] > 0:
		_invalid("sweep: a pulled roller's axle jumped between two frames")
	var control := CarryChecks.snap_control()
	print("SWEEP snap control (broken followers must be caught): %s" % [control])
	if not CarryChecks.snap_control_ok(control):
		_invalid("sweep: the snap check missed a broken follower or flagged a good one (control)")
	if checks.is_empty():
		_invalid("sweep: no carrier was checked")
	print("SWEEP contacts=%s" % [contacts])
	var controlled := {}
	for id in carriers:
		var body := _views.node_for(id)
		var own := CarryContact.body_points(body, [])
		var hips := Transform3D(Basis.IDENTITY, body.global_position + Vector3.UP * 0.85)
		for bag: Node3D in props.props_of(id)["bags"]:
			var kind: int = props.props_of(id)["kinds"][props.props_of(id)["bags"].find(bag)]
			if controlled.has(kind):
				continue
			var was := bag.global_transform
			bag.global_transform = hips.scaled_local(was.basis.get_scale())
			controlled[kind] = CarryContact.inside_meshes(own, bag)
			bag.global_transform = was
	print("CONTROL sweep body_points_in_a_bag_at_the_hips by kind=%s" % [controlled])
	for kind in KIND_NAMES.size():
		if controlled.get(kind, 0) == 0:
			_invalid("sweep: no %s control, or it found no contact" % KIND_NAMES[kind])
	if not contacts.is_empty():
		_invalid("sweep: a carried bag touches its carrier's body or another bag")


## [avg ms, p95 ms] over BENCH_FRAMES frames, printing the counts on screen.
func _frame_times(label: String) -> Array:
	var frame := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var on_screen := 0
	var bags_on := 0
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node != null and not _cam.is_position_behind(node.global_position):
			if frame.has_point(_cam.unproject_position(node.global_position + Vector3.UP)):
				on_screen += 1
				bags_on += _views.carry_on_props().props_of(id)["bags"].size()
	var times: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in BENCH_FRAMES:
		_beat("bench %s" % label)
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	times.sort()
	var total := 0.0
	for t in times:
		total += t
	var avg := total / times.size()
	var p95: float = times[int(times.size() * 0.95)]
	print(
		(
			(
				"BENCH %s passengers_drawn=%d on_screen=%d bags_on_screen=%d props_drawn=%d"
				+ " frames=%d avg_ms=%.2f p50_ms=%.2f p95_ms=%.2f"
			)
			% [
				label,
				_views.active_count(),
				on_screen,
				bags_on,
				_views.carry_on_props().drawn_count(),
				times.size(),
				avg,
				times[times.size() / 2],
				p95
			]
		)
	)
	return [avg, p95]


## The whole checkpoint, lane and basic scanner, from 30 m.
func _plate_whole() -> bool:
	paused = true
	var centre := _sim.grid.cell_to_world(Vector2i(ARCH_AT.x - 1, ARCH_AT.y))
	_aim(centre, 30.0, 0.6)
	paused = false
	_clock.set_paused(true)
	await _frames(20)
	paused = true
	_clock.set_paused(false)
	var img: Image = await PlateSight.grab(self)
	var ok := true
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)
	for cell in [_lane["queue_entry"], _lane["exit"], _lane["berth"], _lane["primary_spot"]]:
		var s := _cam.unproject_position(_sim.grid.cell_to_world(cell))
		print("INFRAME whole_30m cell=%s screen=%s" % [cell, s.round()])
		ok = (
			ok and frame.has_point(s) and not _cam.is_position_behind(_sim.grid.cell_to_world(cell))
		)
	var in_view := 0
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node != null and _sim.get_passenger(id).stage == Passenger.Stage.SECURITY:
			var s := _cam.unproject_position(node.global_position + Vector3.UP)
			in_view += int(frame.has_point(s))
	print("INFRAME whole_30m passengers_in_security_in_frame=%d" % in_view)
	if ok and in_view > 0:
		_save(img, "whole_30m", "whole")
	else:
		_invalid("whole_30m: the lane or its passengers are not in frame")
	paused = false
	return true


func _save(img: Image, name: String, group: String) -> void:
	var path := _out_dir.path_join(name + ".png")
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
	if group != "":
		if not _sheets.has(group):
			_sheets[group] = []
		_sheets[group].append(img)


func _sheet(images: Array) -> Image:
	var w: int = images[0].get_width() / 2
	var h: int = images[0].get_height() / 2
	var rows := (images.size() + 1) / 2
	var sheet := Image.create(w * 2, h * rows, false, Image.FORMAT_RGBA8)
	for i in images.size():
		var small := (images[i] as Image).duplicate() as Image
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * (i % 2), h * (i / 2)))
	return sheet
