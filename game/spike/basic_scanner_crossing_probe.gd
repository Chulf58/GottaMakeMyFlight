extends SceneTree
## Live windowed crossing of the basic security scanner (the interior kit's
## security_scanner booth) by passengers carrying their carry-on (board item
## basic-security-scanner-booth-is-narrower-than-the-walking-ch). Boots
## main/main.tscn with a new random sim seed (printed), builds the starter
## terminal through the HUD (two basic scanners), staffs it and opens the
## airport, then sends passengers with chosen carry-on (each bag kind, two
## bags, an alarm and a liquids repack) to security while the game runs.
##
## Every frame, every passenger near a booth is checked in the booth's own
## frame: points of its drawn body and of every bag it holds or has on the
## floor, against each booth mesh (a point is inside when a ray from it
## crosses the mesh an odd number of times). The floor mat is left out: a
## sole or a bag standing on a 1.2 cm mat is not a clip. Clearance is the gap
## from each point to the nearest part beside it (side parts) or above it
## (beam, lamp), at the same height and depth (a diagnostic on part bounds,
## not a penetration depth). The contact count is a sampled check: body
## vertices and bag surface points 4 cm apart, so a part thinner than that
## crossing a triangle between its points is not seen. Any contact fails the
## probe; so does a sent passenger that never crossed mid-booth, an alarm or
## liquids passenger that never repacked, or a bag kind never carried through. Control: a bag set
## into a side panel must be inside its meshes. Two plates of one crossing
## (mid-booth, leaving) prove the passenger is in frame and
## unblocked before they are saved. Any failure prints PROBE_INVALID and
## exits 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/basic_scanner_crossing_probe.gd [-- --seed=N]
## Plates go to tools/blender/out/security-booth/.

const PlateSight := preload("res://spike/plate_sight.gd")
const CarryContact := preload("res://spike/carry_contact.gd")
const CarryChecks := preload("res://spike/carry_probe_checks.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/security-booth"
const MAIN_SCENE := "res://main/main.tscn"
const RAY := Vector3(0.0013, 1.0, 0.0007)
const MARGIN_PX := 8.0
const MIN_SUBJECT_PX := 60.0
const RUN_LIMIT_MS := 240000
const SEND_GAP_TICKS := 20
const MAX_SPAWNS := 40
## Near a booth: inside this half-size around its origin, in its own frame.
const NEAR := Vector3(0.9, 3.0, 2.2)
## [first bag's kind or -1 for any, bags, liquids, alarm].
const ROLES := [
	[SecurityLooks.Kind.CASE, 1, false, false],
	[SecurityLooks.Kind.BACKPACK, 1, false, false],
	[SecurityLooks.Kind.SHOULDER, 1, false, false],
	[SecurityLooks.Kind.ROLLER, 1, false, false],
	[SecurityLooks.Kind.CASE, 2, false, false],
	[SecurityLooks.Kind.ROLLER, 2, false, false],
	[-1, 1, false, true],
	[-1, 2, true, false],
]
const KIND_NAMES := ["case", "backpack", "shoulder", "roller"]

var _out_dir := ""
var _failed := false
var _main: Node3D
var _cam: Camera3D
var _rig: TycoonCamera
var _clock: SimClock
var _sim: PassengerSim
var _views: PassengerViews
## [node, inverse global transform, parts]; parts are [name, local AABB,
## inverse mesh transform, faces, mesh AABB].
var _booths: Array = []
var _roles: Array = []
var _sent: Array[int] = []
## Passenger id -> stats Dictionary.
var _stats := {}
var _kinds_crossed := {}
var _plated := false
var _plates_saved := 0
## True while the crossing plates are being taken.
var _plate_task := false
## Passenger id -> its role (ROLES entry).
var _role_of := {}


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	return false


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	await _boot()
	if not _failed:
		await _cross()
	_report()
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _boot() -> void:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var seed := randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = int(arg.get_slice("=", 1))
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
	for child in (build.get_node("BuildView") as BuildView).get_children():
		var record: Dictionary = child.get_meta("record", {})
		if StringName(record.get("def", "")) == &"security_scanner":
			_booths.append(_booth(child))
	if _booths.is_empty():
		_invalid("no basic scanner booth is drawn")
		return
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(_clock, _main.get_node("FlightSim"), staff)
	print("PROBE booths=%d hired=%d doors_tick=%d" % [_booths.size(), hired, doors])
	if doors < 0:
		_invalid("the airport did not open")
	_control()
	hud.press_speed(1)
	await _frames(10)


## The booth's drawn parts in its own frame. The kit merges a piece into one
## mesh, so the mesh is split into its connected parts (triangles that share
## a corner), each a closed box tested on its own. The floor mat (a part no
## higher than 2 cm) is left out.
func _booth(node: Node3D) -> Array:
	var to_booth := node.global_transform.affine_inverse()
	var parts := []
	var side_in := INF
	var mats := 0
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var local := to_booth * mi.global_transform
		for faces: PackedVector3Array in _components(mi.mesh.get_faces()):
			var mesh_box := AABB(faces[0], Vector3.ZERO)
			for v in faces:
				mesh_box = mesh_box.expand(v)
			var box := local * mesh_box
			if box.end.y < 0.02:
				if box.position.x < 0.0 and box.end.x > 0.0:
					mats += 1
					continue
				_invalid("a booth part below 2 cm that is not the centred mat: %s" % box)
			var name := (
				"x%.2f..%.2f,y%.2f..%.2f,z%.2f..%.2f"
				% [box.position.x, box.end.x, box.position.y, box.end.y, box.position.z, box.end.z]
			)
			parts.append([name, box, mi.global_transform.affine_inverse(), faces, mesh_box])
			if box.position.x > 0.0:
				side_in = minf(side_in, box.position.x)
			elif box.end.x < 0.0:
				side_in = minf(side_in, -box.end.x)
	print(
		(
			"BOOTH at=%s parts=%d mats_left_out=%d clear_width_m=%.3f"
			% [node.global_position, parts.size(), mats, side_in * 2.0]
		)
	)
	if mats != 1:
		_invalid("expected one floor mat in the booth, found %d" % mats)
	for part in parts:
		print("BOOTH_PART ", part[0])
	return [node, to_booth, parts]


## Triangle soup `faces` split into connected parts: triangles sharing a
## corner (to the millimetre) are one part.
func _components(faces: PackedVector3Array) -> Array:
	var tris := faces.size() / 3
	var parent := PackedInt32Array()
	parent.resize(tris)
	for t in tris:
		parent[t] = t
	var owner_of := {}
	for t in tris:
		for k in 3:
			var key := Vector3i((faces[t * 3 + k] * 1000.0).round())
			if owner_of.has(key):
				var a := _find(parent, t)
				var b := _find(parent, owner_of[key])
				parent[a] = b
			else:
				owner_of[key] = t
	var groups := {}
	for t in tris:
		var r := _find(parent, t)
		if not groups.has(r):
			groups[r] = PackedVector3Array()
		var g: PackedVector3Array = groups[r]
		g.append_array([faces[t * 3], faces[t * 3 + 1], faces[t * 3 + 2]])
		groups[r] = g
	return groups.values()


func _find(parent: PackedInt32Array, t: int) -> int:
	while parent[t] != t:
		t = parent[t]
	return t


## Control: a bag sunk into the middle of a side panel lies inside its meshes,
## so a zero contact count means clear, not blind.
func _control() -> void:
	var booth: Array = _booths[0]
	var node: Node3D = booth[0]
	var best: AABB
	var tallest := 0.0
	for part in booth[2]:
		var box: AABB = part[1]
		if box.position.x > 0.0 and box.size.y > tallest:
			tallest = box.size.y
			best = box
	var at := node.global_transform * best.get_center()
	var sunk := CarryContact.bag_points(Transform3D(Basis.IDENTITY, at - Vector3.UP * 0.1))
	var hits := _contacts(sunk, booth)
	print("CONTROL bag_in_side_panel_points=%d" % hits)
	if hits == 0:
		_invalid("the control bag in a side panel found no contact, so the check is blind")


func _cross() -> void:
	_roles = ROLES.duplicate(true)
	var spawns := 0
	var next_send := _clock.tick
	var stop := Time.get_ticks_msec() + RUN_LIMIT_MS
	while Time.get_ticks_msec() < stop:
		await RenderingServer.frame_post_draw
		if not _roles.is_empty() and _clock.tick >= next_send and spawns < MAX_SPAWNS:
			_send()
			spawns += 1
			next_send = _clock.tick + SEND_GAP_TICKS
		for id in _sim.passenger_ids():
			_check(id)
		if _roles.is_empty() and _sent.all(_done) and _plated and not _plate_task:
			break
	if not _roles.is_empty():
		_invalid("roles never filled after %d spawns: %s" % [spawns, _roles])
	for id in _sent:
		if not _done(id):
			_invalid("passenger %d never cleared security" % id)


func _done(id: int) -> bool:
	var p := _sim.get_passenger(id)
	return _stats.has(id) and (p == null or p.stage > Passenger.Stage.SECURITY)


func _send() -> void:
	var id := _sim.spawn_now(StarterFlight.first_flight())
	var p := _sim.get_passenger(id)
	var kind := SecurityLooks.bag_kind(p, 0)
	var at := _roles.find_custom(func(r: Array) -> bool: return r[0] == kind)
	if at < 0:
		at = _roles.find_custom(func(r: Array) -> bool: return r[0] == -1)
	if at < 0:
		return
	var traits: Array = _roles.pop_at(at)
	p.carry_on = traits[1]
	p.liquids = traits[2]
	p.alarm = traits[3]
	p.hunger = 0
	p.apron = []
	p.apron_mm = 0
	p.stage = Passenger.Stage.TO_SECURITY
	p.clear_path()
	_sent.append(id)
	_role_of[id] = traits
	print("SEND passenger=%d kinds=%s role=%s" % [id, [kind, SecurityLooks.bag_kind(p, 1)], traits])


## One frame of passenger `id` against every booth it is near.
func _check(id: int) -> void:
	var body := _views.node_for(id)
	if body == null or not body.is_visible_in_tree():
		return
	for booth in _booths:
		var local: Vector3 = (booth[1] as Transform3D) * body.global_position
		if absf(local.x) > NEAR.x or absf(local.z) > NEAR.z:
			continue
		var p := _sim.get_passenger(id)
		var points := CarryContact.body_points(body, [])
		var bag_points := PackedVector3Array()
		var props: Dictionary = _views.carry_on_props().props_of(id)
		var bags: Array[Node3D] = props["bags"]
		var homes := SecurityLooks.bag_homes(_sim, p)
		var hand_kinds := []
		for i in bags.size():
			if homes[i] == SecurityLooks.Home.TRAY and p.station != 0:
				_invalid("passenger %d has a tray bag at a basic scanner" % id)
			if bags[i].is_visible_in_tree():
				bag_points.append_array(CarryChecks.surface(bags[i]))
				if homes[i] == SecurityLooks.Home.HAND:
					hand_kinds.append(props["kinds"][i])
		var s: Dictionary = _stats.get(id, {})
		if s.is_empty():
			s = {
				"frames": 0,
				"mid": 0,
				"body_contacts": 0,
				"bag_contacts": 0,
				"body_gap": INF,
				"bag_gap": INF,
				"head_gap": INF,
				"reach": 0.0,
				"bag_reach": 0.0,
				"parts": {},
				"kinds": props["kinds"],
				"phases": {},
				"sent": _sent.has(id),
			}
			_stats[id] = s
		s["frames"] += 1
		s["phases"][p.security_phase] = true
		s["body_contacts"] += _contacts(points, booth, s["parts"])
		s["bag_contacts"] += _contacts(bag_points, booth, s["parts"])
		var gaps := _gaps(points, booth)
		var bag_gaps := _gaps(bag_points, booth)
		s["body_gap"] = minf(s["body_gap"], gaps.x)
		s["head_gap"] = minf(s["head_gap"], gaps.y)
		s["reach"] = maxf(s["reach"], gaps.z)
		s["bag_gap"] = minf(s["bag_gap"], bag_gaps.x)
		s["bag_reach"] = maxf(s["bag_reach"], bag_gaps.z)
		var inside := absf(local.z) < 0.6 and absf(local.x) < 0.3
		if inside:
			s["mid"] += 1
			for k in hand_kinds:
				_kinds_crossed[KIND_NAMES[k]] = true
		if (
			not _plated
			and inside
			and absf(local.z) < 0.2
			and props["kinds"].has(SecurityLooks.Kind.CASE)
		):
			_plated = true
			_plate_crossing.call_deferred(id, booth)


## Points inside a booth mesh, counted per part into `parts` when given.
func _contacts(points: PackedVector3Array, booth: Array, parts := {}) -> int:
	var count := 0
	for pt in points:
		for part in booth[2]:
			var lp: Vector3 = (part[2] as Transform3D) * pt
			var faces: PackedVector3Array = part[3]
			if not (part[4] as AABB).grow(0.001).has_point(lp):
				continue
			if _odd(lp, faces):
				count += 1
				parts[part[0]] = parts.get(part[0], 0) + 1
				break
	return count


## x: the smallest side gap of `points` to a part beside them at their height
## and depth; y: the smallest gap up to a part above them; z: the widest
## reach from the centre line among points within the booth's length.
func _gaps(points: PackedVector3Array, booth: Array) -> Vector3:
	var side := INF
	var up := INF
	var reach := 0.0
	for pt in points:
		var lp: Vector3 = (booth[1] as Transform3D) * pt
		if absf(lp.z) <= 0.95:
			reach = maxf(reach, absf(lp.x))
		for part in booth[2]:
			var box: AABB = part[1]
			if lp.z < box.position.z or lp.z > box.end.z:
				continue
			if box.position.x > 0.0 or box.end.x < 0.0:
				if lp.y < box.position.y or lp.y > box.end.y:
					continue
				var gap := box.position.x - lp.x if box.position.x > 0.0 else lp.x - box.end.x
				side = minf(side, gap)
			elif lp.x >= box.position.x and lp.x <= box.end.x:
				up = minf(up, box.position.y - lp.y)
	return Vector3(side, up, reach)


func _odd(p: Vector3, faces: PackedVector3Array) -> bool:
	var crossings := 0
	for i in range(0, faces.size() - 2, 3):
		if Geometry3D.ray_intersects_triangle(p, RAY, faces[i], faces[i + 1], faces[i + 2]) != null:
			crossings += 1
	return crossings % 2 == 1


## Plates of passenger `id` crossing `booth`: mid-booth now, then as it
## leaves past the booth's back. Each plate keeps the first of four headings
## where the passenger is in frame and unblocked.
func _plate_crossing(id: int, booth: Array) -> void:
	_plate_task = true
	await _plate_both(id, booth)
	_plate_task = false


func _plate_both(id: int, booth: Array) -> void:
	if not await _plate_best(id, booth, "booth_crossing_0_mid"):
		_invalid("crossing plate: passenger %d not shown mid-booth from any heading" % id)
		return
	var stop := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < stop:
		await process_frame
		var body := _views.node_for(id)
		if body == null:
			break
		var local: Vector3 = (booth[1] as Transform3D) * body.global_position
		if absf(local.z) > 0.8:
			if not await _plate_best(id, booth, "booth_crossing_1_leaving"):
				_invalid("crossing plate: passenger %d not shown leaving" % id)
			return
	_invalid("crossing plate: passenger %d never left the booth" % id)


func _plate_best(id: int, booth: Array, name: String) -> bool:
	var node: Node3D = booth[0]
	var owners: Array[Node] = [_main.get_node("Airside/Terminal"), _main.get_node("BuildMode")]
	for yaw in [0.5, 0.5 + PI / 2.0, 0.5 + PI, 0.5 - PI / 2.0]:
		_rig.stop_follow()
		_rig.position = Vector3(node.global_position.x, 0.0, node.global_position.z)
		_rig.yaw = yaw
		_rig.distance = 4.5
		var holder := PlateSight.colliders(root, owners, {})
		await physics_frame
		await physics_frame
		await _frames(2)
		var body := _views.node_for(id)
		var ok := body != null and _shown(body, "%s yaw %.2f" % [name, yaw])
		ok = ok and _bags_in_frame(id, name)
		if ok:
			var along := ((booth[1] as Transform3D) * body.global_position).z
			var placed := absf(along) < 0.6 if name.ends_with("mid") else absf(along) > 0.8
			print("INFRAME %s along_booth_m=%.2f placed=%s" % [name, along, placed])
			ok = placed
		var img := root.get_texture().get_image()
		holder.free()
		if ok:
			_save(img, name)
			_plates_saved += 1
			return true
	return false


## Whether every visible bag of `id` projects inside the frame, in front of
## the camera.
func _bags_in_frame(id: int, tag: String) -> bool:
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)
	var bags: Array[Node3D] = _views.carry_on_props().props_of(id)["bags"]
	var shown := 0
	for bag in bags:
		if not bag.is_visible_in_tree():
			continue
		var at := bag.global_position
		if _cam.is_position_behind(at) or not frame.has_point(_cam.unproject_position(at)):
			print("INFRAME %s bag at %s is out of frame" % [tag, at])
			return false
		shown += 1
	print("INFRAME %s bags_in_frame=%d" % [tag, shown])
	return shown > 0


func _shown(body: Node3D, tag: String) -> bool:
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
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(_cam.global_position, base + Vector3(0.0, h, 0.0))
		)
		clear += int(hit.is_empty())
	var ok := in_frame and clear >= 2 and hi.y - lo.y >= MIN_SUBJECT_PX
	print(
		(
			"INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) unblocked_lines=%d/3 ok=%s"
			% [tag, lo.x, lo.y, hi.x, hi.y, clear, ok]
		)
	)
	return ok


func _save(img: Image, name: String) -> void:
	var path := _out_dir.path_join(name + ".png")
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _report() -> void:
	var totals := {"body": 0, "bag": 0, "frames": 0}
	var worst := Vector4(INF, INF, INF, 0.0)
	for id in _stats:
		var s: Dictionary = _stats[id]
		totals["body"] += s["body_contacts"]
		totals["bag"] += s["bag_contacts"]
		totals["frames"] += s["frames"]
		worst = Vector4(
			minf(worst.x, s["body_gap"]),
			minf(worst.y, s["bag_gap"]),
			minf(worst.z, s["head_gap"]),
			maxf(worst.w, s["bag_reach"])
		)
		print(
			(
				(
					"CROSSING passenger=%d sent=%s kinds=%s frames=%d mid=%d phases=%s body_contacts=%d"
					+ " bag_contacts=%d parts=%s body_gap_m=%.3f bag_gap_m=%.3f head_gap_m=%.3f"
					+ " body_reach_m=%.3f bag_reach_m=%.3f"
				)
				% [
					id,
					s["sent"],
					s["kinds"],
					s["frames"],
					s["mid"],
					s["phases"].keys(),
					s["body_contacts"],
					s["bag_contacts"],
					s["parts"],
					s["body_gap"],
					s["bag_gap"],
					s["head_gap"],
					s["reach"],
					s["bag_reach"]
				]
			)
		)
	print(
		(
			(
				"BOOTH_TOTAL passengers=%d frames=%d body_contacts=%d bag_contacts=%d"
				+ " min_body_gap_m=%.3f min_bag_gap_m=%.3f min_head_gap_m=%.3f"
				+ " max_bag_reach_m=%.3f kinds_crossed=%s"
			)
			% [
				_stats.size(),
				totals["frames"],
				totals["body"],
				totals["bag"],
				worst.x,
				worst.y,
				worst.z,
				worst.w,
				_kinds_crossed.keys()
			]
		)
	)
	for kind in KIND_NAMES:
		if not _kinds_crossed.has(kind):
			_invalid("no %s carried through a booth" % kind)
	if totals["frames"] < 100:
		_invalid("only %d passenger frames near a booth" % totals["frames"])
	if totals["body"] > 0 or totals["bag"] > 0:
		_invalid(
			(
				"a passenger or its bag clips the booth: body=%d bag=%d"
				% [totals["body"], totals["bag"]]
			)
		)
	if _plates_saved < 2:
		_invalid("only %d of 2 crossing plates saved" % _plates_saved)
	for id in _sent:
		var s: Dictionary = _stats.get(id, {})
		var traits: Array = _role_of[id]
		if s.get("mid", 0) == 0:
			_invalid("sent passenger %d never crossed mid-booth" % id)
		elif (traits[2] or traits[3]) and not s["phases"].has(SecurityRuntime.Phase.REPACK):
			_invalid("passenger %d (liquids or alarm) never repacked" % id)
