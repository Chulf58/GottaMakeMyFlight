extends SceneTree
## Windowed frame-strip plates of passengers going through security inside the
## real main scene (Security 7/8; SecurityLooks, SecurityProps). Boots
## main/main.tscn with a new random sim seed (printed), builds the starter
## terminal through the HUD, swaps its east basic scanner for a whole security
## lane (arch on the divider, LEFT mirror, facing 0, the divider walls under
## the lane removed) and keeps the west basic scanner. Every station is staffed
## with StaffTestKit.staff_all, a stand-in for lane staffing until Security
## 5/8, so the lane's officers do not stand on their real spots here. Then
## passengers with chosen carry-on are sent to security and each moment below
## is plated the first time it happens:
##   lane:  queue front held back, unpack (bags into the tray), the tray riding
##          the belt at three points of the arch walk, pickup, leaving
##   alarm: stepping aside, repack at the berth, the walk back, the second
##          pass through the arch, pickup
##   basic: carry-on through the scanner, the repack that holds it
##   whole: the checkpoint from 30 m
## Each plate tries four headings and keeps the first where the subject
## passenger is shown (game/spike/plate_sight.gd: in frame, sight lines on its
## upper body with no blocker, no HUD over it, tall enough) and every tray and
## bag of it is in frame, big enough and hit by a sight line. Clearance: no
## vertex of the subject's drawn body may lie inside a lane part (kit bounds
## of the tray table, X-ray belt and pickup table, the arch's posts), and no
## vertex below a carried or floor bag's top inside that bag. Any failure
## prints PROBE_INVALID and exits 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/security_visuals_plates_probe.gd
## Plates go to tools/blender/out/security-lane-visuals/.

const PlateSight := preload("res://spike/plate_sight.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
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
## [bags, liquids, alarm] of the passengers sent, in order.
const TRAITS := [
	[2, false, false],
	[1, false, true],
	[0, false, false],
	[1, true, false],
	[2, false, true],
	[1, false, false],
	[2, false, false],
	[1, false, true],
	[1, false, false],
	[2, false, true],
]
## The arch's posts in its own frame (a 0.70 m clear opening across x).
const POST_X := Vector2(0.35, 0.42)
const POST_Z := 0.42
## Body vertices this near a carried bag's grip are the hand that holds it.
const GRIP_HAND_M := 0.12

var _out_dir := ""
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
## Moment name -> its group (see _hit()); removed once plated.
var _moments := {}
var _sheets := {}


func _initialize() -> void:
	SecurityLanes.enabled = true  # Lanes are off in this tree until Security 5/8.
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
	_define_moments()
	await _play()
	for name in _moments:
		_invalid("moment %s never happened" % name)
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
	var seed := randi()
	_clock.seed_rng(seed)
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
	var seated := StaffTestKit.staff_all(staff)
	print("PROBE staffed=%d lane_open=%s" % [seated, staff.is_open(_arch)])
	var flights := _main.get_node("FlightSim") as FlightSim
	var issued := func() -> bool: return flights.flight_ids().has(StarterFlight.first_flight())
	if not StarterFlight.advance_until(_clock, issued, 4000):
		_invalid("the starter's first flight was never issued")
	if not staff.is_open(_arch):
		_invalid("the lane is not open")
	hud.press_speed(1)
	await _frames(10)


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
	for sign in [-1.0, 1.0]:
		var lo := Vector3(POST_X.x if sign > 0 else -POST_X.y, 0.0, -POST_Z)
		var post := AABB(lo, Vector3(POST_X.y - POST_X.x, 2.42, POST_Z * 2.0))
		_part_boxes.append(["arch_post", arch_xf, post])


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


func _send(traits: Array) -> int:
	var id := _sim.spawn_now(StarterFlight.first_flight())
	var p := _sim.get_passenger(id)
	p.carry_on = traits[0]
	p.liquids = traits[1]
	p.alarm = traits[2]
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
	]:
		_moments[name] = name.get_slice("_", 0)


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
		"lane_2_unpack":
			hit = (
				phase == SecurityRuntime.Phase.UNPACK
				and p.carry_on > 0
				and done >= SecurityRuntime.LANE_UNPACK_TICKS + 4
			)
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
		if sent < TRAITS.size() and _clock.tick >= next_send:
			_send(TRAITS[sent])
			sent += 1
			next_send = _clock.tick + SEND_GAP_TICKS
		await process_frame
		for name in _moments.keys():
			var found := _match(name)
			if found == 0:
				continue
			var group: String = _moments[name]
			if await _plate(name, group, found, DISTANCE_M):
				_moments.erase(name)
			break
		if not whole_done and _in_security() >= 4:
			whole_done = await _plate_whole()
	print("PROBE play ended tick=%d sent=%d left=%s" % [_clock.tick, sent, _moments.keys()])


func _match(name: String) -> int:
	for id in _sim.passenger_ids():
		if _views.node_for(id) != null and _hit(name, _sim.get_passenger(id)):
			return id
	return 0


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
	var props := _views.security_props().props_of(id)
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
		# A tray inside the X-ray tunnel is hidden by design.
		var tunnel := name == "lane_4_ride_scan"
		var prop_ok := in_frame and size >= MIN_PROP_PX and (hits >= 1 or tunnel)
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


## Body vertices of the subject inside a lane part, and inside its own carried
## (away from the holding hand) or floor bags.
func _check_clearance(name: String, id: int) -> void:
	var verts := _body_vertices(_views.node_for(id))
	var part_hits := {}
	for entry in _part_boxes:
		var inv: Transform3D = (entry[1] as Transform3D).affine_inverse()
		var box: AABB = entry[2]
		for v in verts:
			var local := inv * v
			if box.grow(-0.005).has_point(local):
				part_hits[entry[0]] = part_hits.get(entry[0], 0) + 1
				if entry[0] == "arch_post":
					# How far into the post, from the 0.70 m opening's edge.
					var depth := absf(local.x) - POST_X.x
					part_hits["arch_depth_m"] = maxf(part_hits.get("arch_depth_m", 0.0), depth)
					part_hits["arch_at_y"] = snappedf(v.y, 0.01)
	# A carried bag may touch the hand that holds it; the rest of the body and
	# a floor bag's whole volume must stay out.
	var bag_hits := 0
	var homes := SecurityLooks.bag_homes(_sim, _sim.get_passenger(id))
	var body := _views.node_for(id)
	var bags: Array[Node3D] = _views.security_props().props_of(id)["bags"]
	for i in bags.size():
		if homes[i] == SecurityLooks.Home.TRAY:
			continue
		var inv := bags[i].global_transform.affine_inverse()
		var bag_box := AABB(Vector3.ZERO, SecurityProps.bag_size())
		bag_box.position = Vector3(-bag_box.size.x / 2.0, 0.0, -bag_box.size.z / 2.0)
		var grip := _views.security_props().grip_of(body, i)
		var carried := homes[i] == SecurityLooks.Home.HAND
		for v in verts:
			if carried and v.distance_to(grip) < GRIP_HAND_M:
				continue
			if bag_box.grow(-0.005).has_point(inv * v):
				bag_hits += 1
	var nearest := INF
	var me := _views.node_for(id).global_position
	for other in _sim.passenger_ids():
		var node := _views.node_for(other)
		if other != id and node != null:
			nearest = minf(nearest, node.global_position.distance_to(me))
	print(
		(
			(
				"CLEARANCE %s passenger=%d body_vertices=%d part_contacts=%s"
				+ " bag_body_contacts=%d nearest_passenger_m=%.2f"
			)
			% [name, id, verts.size(), part_hits, bag_hits, nearest]
		)
	)
	if verts.is_empty():
		_invalid("%s: no drawn body vertices to check" % name)
	if not part_hits.is_empty() or bag_hits > 0:
		_invalid("%s: passenger %d clips a lane part or its own bag" % [name, id])


func _body_vertices(body: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree():
			continue
		var mesh: Mesh = mi.bake_mesh_from_current_skeleton_pose() if mi.skin != null else mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for k in range(0, verts.size(), 2):
				out.append(mi.global_transform * verts[k])
	return out


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
