extends SceneTree
## Live windowed walk of security officers through a security lane's arch,
## narrowed to 0.76 m clear (board item staff-tuck-their-arms-through-
## security-arches-staff-walk-thr). Boots main/main.tscn with a new random sim
## seed (printed), builds the starter terminal through the HUD, swaps its
## basic scanners for one lane on the divider (as the basic scanner crossing
## probe's --lane mode does) and drives the staff through the arch with the
## game's own rules, while the game runs:
## 1. two officers are hired: the first opens the lane (primary spot, beside
##    the X-ray belt), the second becomes its helper and walks through the
##    arch to the helper spot beside the repack berth;
## 2. the primary is sent out through StaffSim's own walk-out (StaffSim.fire()
##    always picks a helper first), so the helper is promoted (StaffPosts rule
##    1) and walks back through the arch to the primary spot, as an officer;
## 3. a third officer is hired and walks through the arch as the new helper;
## 4. one officer is fired: the helper walks out through the arch.
## In 2 and 4 the game's own way back runs through the lane's open return
## route cell beside the arch, so the probe sets the path through the arch
## (_through_arch()).
## The seed picks the game speed (1 to 3), so the frames sample each walk at
## other moments; the staff walks themselves follow from the layout.
##
## Every frame, every staff body near the arch is checked in the arch's own
## frame: the skinned vertices of its hands and forearms (dominant bone named
## Forearm, Hand, Finger or Thumb) against the boxes of the arch's drawn parts
## (the kit merges a piece into one mesh, so it is split into connected parts;
## the floor mat is left out). The posts are 3 to 4 cm thick, thinner than a
## hand, so for a body standing between the posts a point past a side part's
## inner face, within that part's height and depth, counts as well: the hand
## went through the post. A frame with any such point is a contact frame. Each
## crossing prints the tuck weight mid-arch (StaffCharacters.tuck_of(), -1
## when the build has none). Controls: an idle officer posed 12 cm in from a
## post's inner face must put arm points through it, so a zero count means
## clear, not blind; the same officer centred in the arch is printed beside it.
##
## --expect-clear fails the run on any contact. --plates takes close plates of
## an officer and a helper mid-arch, with the clock paused, each kept only when
## the body's bounds project inside the viewport and sight lines land on it
## with no blocker (PlateSight.person_shown()). Any failure prints
## PROBE_INVALID and exits 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/staff_arch_arm_probe.gd [-- --seed=N --expect-clear --plates]
## Plates go to tools/blender/out/staff_tuck/.

const PlateSight := preload("res://spike/plate_sight.gd")
const CarryContact := preload("res://spike/carry_contact.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/staff_tuck"
const ARCH_AT := Vector2i(20, ReferenceTerminal.DIVIDER_Y)
const OLD_SCANNERS: Array[Vector2i] = [Vector2i(17, 8), Vector2i(19, 8)]
## Bone name prefixes of the counted hand and forearm points.
const ARM_PREFIXES: Array[String] = ["Forearm", "Hand", "Finger", "Thumb"]
## Near the arch: inside this half-size around its origin, in its own frame.
const NEAR := Vector3(1.2, 3.0, 1.6)
## Mid-arch: the drawn body this close to the arch's origin across the floor.
const MID_M := 0.15
const STAGE_LIMIT_MS := 120000
const MARGIN_PX := 8.0
const CLOSE_M := 3.4
const CLOSE_HEIGHT_M := 1.6
const AIM_M := 1.0
const CLOSE_MIN_PX := 300.0
const SECURITY := StaffMember.Role.SECURITY
const PRIMARY := StaffMember.Slot.PRIMARY
const HELPER := StaffMember.Slot.HELPER

var _failed := false
var _expect_clear := false
var _plates := false
var _out_dir := ""
var _main: Node3D
var _cam: Camera3D
var _clock: SimClock
var _sim: PassengerSim
var _staff: StaffSim
var _views: StaffCharacters
var _arch: Node3D
var _arch_id := 0
var _to_arch := Transform3D()
## The arch's drawn parts as boxes in its own frame, the floor mat left out.
var _parts: Array[AABB] = []
## Half the clear width between the posts.
var _side_in := INF
## Member id -> {near, contact_frames, points}.
var _stats := {}
## Member id -> true while it is counted as in its current crossing.
var _in_mid := {}
## Each crossing: [member id, what it was doing, tuck weight mid-arch].
var _crossings: Array = []
## A crossing waiting for its close plate: [member id, plate name].
var _plate_ask: Array = []
var _plated := {}
var _contact_frames := 0
var _contact_points := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_expect_clear = args.has("--expect-clear")
	_plates = args.has("--plates")
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=%s expect_clear=%s plates=%s" % [_out_dir, _expect_clear, _plates])
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
		await _control()
	if not _failed:
		await _walk()
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
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# LEFT only: on the starter terminal's divider a RIGHT lane here has its
	# primary spot blocked ("Clear the officer's spot by the X-ray belt").
	var mirror := SecurityLanes.LEFT
	var speed := rng.randi_range(1, 3)
	print("PROBE sim_seed=%d mirror=%s speed=%d" % [seed, mirror, speed])
	root.add_child(_main)
	_cam = _main.get_node("TycoonCamera/Camera3D")
	_sim = _main.get_node("PassengerSim")
	_staff = _main.get_node("Staff")
	_views = _main.get_node("StaffCharacters")
	var hud := _main.get_node("PassengerHud") as PassengerHud
	await _frames(5)
	hud.press_starter_terminal()
	var build := _main.get_node("BuildMode") as BuildMode
	build.set_tool(BuildMode.Tool.NONE)
	_build_lane(build, mirror)
	await _frames(2)
	for child in (build.get_node("BuildView") as BuildView).get_children():
		if child.is_queued_for_deletion():
			continue
		var record: Dictionary = child.get_meta("record", {})
		if StringName(record.get("def", "")) == SecurityLanes.ARCH:
			_arch = child
	if _arch == null:
		_invalid("no arch is drawn")
		return
	_arch_parts()
	hud.press_speed(speed)


## Both basic scanners go and a lane on the divider takes the east one's
## place on the `mirror` side, the divider walls under its row removed.
func _build_lane(build: BuildMode, mirror: int) -> void:
	var grid := build.grid
	for cell in OLD_SCANNERS:
		var old := grid.object_at(cell)
		if old != 0 and not grid.apply(BuildEdit.remove_object(old)).ok:
			_invalid("could not remove the scanner at %s" % cell)
	var lane := SecurityLanes.geometry(ARCH_AT, 0, mirror)
	# The row through the arch: the X-ray belt, the arch, the return route
	# and the primary spot (side -1 to 2 at this mirror).
	for k in range(-1, 3):
		var cell: Vector2i = ARCH_AT + (lane["side"] as Vector2i) * k
		if grid.has_wall(cell, BuildGrid.Side.NORTH):
			if not grid.apply(BuildEdit.remove_wall(cell, BuildGrid.Side.NORTH)).ok:
				_invalid("could not open the divider at %s" % cell)
	if not grid.apply(BuildEdit.place_object(SecurityLanes.ARCH, ARCH_AT, 0)).ok:
		_invalid("could not place the arch")
	for part in [SecurityLanes.TRAY_TABLE, SecurityLanes.XRAY_BELT, SecurityLanes.PICKUP_TABLE]:
		if not grid.apply(BuildEdit.place_object(part, lane[part], 0)).ok:
			_invalid("could not place %s" % part)
	(build.get_node("BuildView") as BuildView).refresh(grid)
	_arch_id = grid.object_at(ARCH_AT)
	var lanes := _sim.layout.security_lanes
	print("LANE arch=%d status=%s mirror=%d" % [_arch_id, lanes.status_text(_arch_id), mirror])
	if not lanes.is_complete(_arch_id):
		_invalid("the lane is not whole")


## The arch's parts in its own frame, each connected part of a mesh a box.
func _arch_parts() -> void:
	_to_arch = _arch.global_transform.affine_inverse()
	var mats := 0
	for mi: MeshInstance3D in _arch.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var local := _to_arch * mi.global_transform
		for faces: PackedVector3Array in _components(mi.mesh.get_faces()):
			var box := AABB(faces[0], Vector3.ZERO)
			for v in faces:
				box = box.expand(v)
			box = local * box
			if box.end.y < 0.02:
				mats += 1
				continue
			_parts.append(box)
			print("ARCH_PART %s" % box)
			if box.position.x > 0.0:
				_side_in = minf(_side_in, box.position.x)
			elif box.end.x < 0.0:
				_side_in = minf(_side_in, -box.end.x)
	_cam.make_current()
	print(
		(
			"ARCH at=%s parts=%d mats_left_out=%d clear_width_m=%.3f"
			% [_arch.global_position, _parts.size(), mats, _side_in * 2.0]
		)
	)
	if _parts.is_empty() or _side_in == INF:
		_invalid("the arch has no side parts")


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
				parent[_find(parent, t)] = _find(parent, owner_of[key])
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


## The skinned hand and forearm vertices of `body`, in world space.
func _arm_points(body: Node3D) -> PackedVector3Array:
	var owned: Array = CarryContact.body_points_owned(body, [])
	var points: PackedVector3Array = owned[0]
	var names: PackedStringArray = owned[1]
	var out := PackedVector3Array()
	for i in points.size():
		for prefix in ARM_PREFIXES:
			if names[i].begins_with(prefix):
				out.append(points[i])
				break
	return out


## How many of `points` (world) clip the arch: inside one of its parts, or,
## for a body standing between the posts (`passing`), past a side part's inner
## face within its height and depth.
func _clips(points: PackedVector3Array, passing: bool) -> int:
	var n := 0
	for p in points:
		var q := _to_arch * p
		for box in _parts:
			if box.has_point(q) or (passing and _past_side(box, q)):
				n += 1
				break
	return n


## Whether `q` (arch frame) lies past the inner face of side part `box`, within
## its height and depth. A part across the middle (the beam) is no side part.
func _past_side(box: AABB, q: Vector3) -> bool:
	if q.y < box.position.y or q.y > box.end.y or q.z < box.position.z or q.z > box.end.z:
		return false
	if box.position.x > 0.0:
		return q.x >= box.position.x
	if box.end.x < 0.0:
		return q.x <= box.end.x
	return false


## Control: an officer standing 12 cm in from the +x post's inner face, idle,
## puts arm points inside the post.
func _control() -> void:
	var dummy := StaffCharacters.CHARACTERS[StaffMember.Role.SECURITY].instantiate() as Node3D
	root.add_child(dummy)
	(dummy.get_node("AnimationPlayer") as AnimationPlayer).play("idle")
	var offset := Transform3D(Basis.IDENTITY, Vector3(_side_in - 0.12, 0.0, 0.0))
	dummy.global_transform = _arch.global_transform * offset
	await _frames(3)
	var arm := _arm_points(dummy)
	var hits := _clips(arm, true)
	dummy.global_transform = _arch.global_transform
	await _frames(3)
	var centred := _clips(_arm_points(dummy), true)
	print(
		(
			"CONTROL arm_points=%d clips_12cm_from_post=%d clips_centred=%d"
			% [arm.size(), hits, centred]
		)
	)
	if arm.is_empty() or hits == 0:
		_invalid("the control officer by the post found no contact, so the check is blind")
	dummy.free()


func _walk() -> void:
	_staff.hire(SECURITY)
	_staff.hire(SECURITY)
	var both := func() -> bool: return _on_duty(PRIMARY) != 0 and _on_duty(HELPER) != 0
	if not await _until(both, "two on duty"):
		return
	var primary := _on_duty(PRIMARY)
	var helper := _on_duty(HELPER)
	print("STAGE two_on_duty primary=%d helper=%d tick=%d" % [primary, helper, _clock.tick])
	_staff._send_out(_staff.get_member(primary))
	_staff.staff_changed.emit()
	var m := _staff.get_member(helper)
	var walking := func() -> bool: return m.state == StaffMember.State.TO_STATION
	if not await _until(walking, "helper sent to the primary spot"):
		return
	_through_arch(m)
	if not await _until(func() -> bool: return _on_duty(PRIMARY) == helper, "helper promoted"):
		return
	print("STAGE promoted tick=%d" % _clock.tick)
	_staff.hire(SECURITY)
	if not await _until(func() -> bool: return _on_duty(HELPER) != 0, "new helper"):
		return
	m = _staff.get_member(_on_duty(HELPER))
	print("STAGE new_helper=%d tick=%d" % [m.id, _clock.tick])
	_staff.fire(SECURITY)
	if m.state != StaffMember.State.WALKING_OUT:
		_invalid("the fired officer is not the helper")
		return
	_through_arch(m)
	await _until(func() -> bool: return _staff.member_ids().size() == 1, "helper walked out")
	print("STAGE walked_out tick=%d" % _clock.tick)


## Sends `m`, on the airside past the arch, to the end of its path through
## the arch: its own way runs through the lane's open return route cell
## instead, which is shorter. Staff may walk through the arch (decision
## staff-may-walk-through-security-scanners-and-lanes-so-shop-s), so this is a
## way the game allows, taken on purpose to measure an officer and a walk-out.
func _through_arch(m: StaffMember) -> void:
	var lane := _sim.layout.security_lanes.lane(_arch_id)
	var grid := _sim.grid
	var path := grid.find_staff_path(m.at, lane["pickup"])
	path.append(lane["arch"])
	var rest := grid.find_staff_path(lane["unpack"], m.path_end())
	path.append_array(rest)
	print("REROUTE member=%d state=%d path=%s" % [m.id, m.state, path])
	if path.size() < 4 or rest.is_empty() or path[0] != m.at:
		_invalid("no way through the arch for member %d" % m.id)
		return
	m.set_path(path)


## The member on duty at the arch's `slot` post, or 0.
func _on_duty(slot: StaffMember.Slot) -> int:
	for id in _staff.member_ids():
		var m := _staff.get_member(id)
		if m.station == _arch_id and m.slot == slot and m.state == StaffMember.State.ON_DUTY:
			return id
	return 0


## Runs frames, checking each, until `done` holds; false on time out.
func _until(done: Callable, label: String) -> bool:
	var start := Time.get_ticks_msec()
	while not done.call():
		if Time.get_ticks_msec() - start > STAGE_LIMIT_MS:
			_invalid("stage '%s' did not finish in %d ms" % [label, STAGE_LIMIT_MS])
			return false
		await process_frame
		_check()
		if not _plate_ask.is_empty():
			var ask: Array = _plate_ask
			_plate_ask = []
			await _plate(ask[0], ask[1])
	return true


func _check() -> void:
	for id in _staff.member_ids():
		var m := _staff.get_member(id)
		var body := _views.node_for(id)
		if m == null or body == null or not body.visible:
			continue
		var local := _to_arch * body.global_position
		if absf(local.x) > NEAR.x or absf(local.z) > NEAR.z:
			_in_mid.erase(id)
			continue
		var s: Dictionary = _stats.get_or_add(id, {"near": 0, "contact_frames": 0, "points": 0})
		s["near"] += 1
		var hits := _clips(_arm_points(body), absf(local.x) < _side_in)
		if hits > 0:
			s["contact_frames"] += 1
			s["points"] += hits
			_contact_frames += 1
			_contact_points += hits
			print(
				(
					"CONTACT member=%d slot=%d state=%d at_local=(%.2f,%.2f) points=%d tuck=%.2f"
					% [id, m.slot, m.state, local.x, local.z, hits, _tuck(id)]
				)
			)
		var mid := Vector2(local.x, local.z).length() <= MID_M
		if mid and not _in_mid.has(id):
			_in_mid[id] = true
			var doing := "walkout"
			if m.state == StaffMember.State.TO_STATION:
				doing = "helper" if m.slot == HELPER else "officer"
			_crossings.append([id, doing, _tuck(id)])
			print("CROSSING member=%d doing=%s tuck_mid=%.2f" % [id, doing, _tuck(id)])
			if _plates and doing != "walkout" and not _plated.has(doing):
				_plate_ask = [id, doing + "_mid_arch"]
		elif Vector2(local.x, local.z).length() > 0.6:
			_in_mid.erase(id)


func _tuck(id: int) -> float:
	return _views.call("tuck_of", id) if _views.has_method("tuck_of") else -1.0


## A close plate of member `id` mid-arch, the clock paused: a camera of the
## probe's own CLOSE_M out and CLOSE_HEIGHT_M high, aimed AIM_M over the floor
## at the body, tries eight headings round it (facing it first) with the HUD
## hidden, and keeps the first whose body bounds project inside the viewport
## by MARGIN_PX and where the body is shown (sight lines land, none blocked).
func _plate(id: int, name: String) -> void:
	var was_paused := _clock.paused
	_clock.set_paused(true)
	await _frames(2)
	var body := _views.node_for(id)
	var layers: Array[CanvasLayer] = []
	for node in _main.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		if layer.visible:
			layer.visible = false
			layers.append(layer)
	var cam := Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	cam.make_current()
	var owners: Array[Node] = [_views, _main.get_node("PassengerViews")]
	for path in ["Airside/Terminal", "BuildMode", "BaggageViews"]:
		owners.append(_main.get_node(path))
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)
	print("PLATE_ASK %s member=%d tuck=%.2f" % [name, id, _tuck(id)])
	for h in 8:
		var look := body.global_position + Vector3(0.0, AIM_M, 0.0)
		var yaw := body.global_rotation.y + h * PI / 4.0
		var out := Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, CLOSE_M)
		cam.global_position = body.global_position + out + Vector3(0.0, CLOSE_HEIGHT_M, 0.0)
		cam.look_at(look)
		await _frames(2)
		var img := root.get_texture().get_image()
		var holder := PlateSight.colliders(root, owners, {body: "subject"})
		await physics_frame
		await physics_frame
		var bounds: Dictionary = holder.get_meta("bounds")
		var tag := "%s heading %d" % [name, h]
		var ok := (holder.get_meta("unbaked") as Array).is_empty() and bounds.has("subject")
		if ok:
			ok = _box_in_frame(cam, bounds["subject"], frame, tag)
			var shown := PlateSight.person_shown(
				cam, bounds["subject"], "subject", frame, img, img, CLOSE_MIN_PX
			)
			print("INFRAME %s person=%s" % [tag, shown])
			ok = ok and shown["ok"]
		holder.free()
		if ok:
			var path := _out_dir.path_join(name + ".png")
			if img.save_png(path) != OK:
				_invalid("could not save %s" % path)
			else:
				print("PLATE saved %s size=%s tuck=%.2f" % [path, img.get_size(), _tuck(id)])
				_plated[name.get_slice("_", 0)] = path
			break
	_cam.make_current()
	cam.queue_free()
	for layer in layers:
		layer.visible = true
	_clock.set_paused(was_paused)
	await _frames(1)


## Whether the corners of `box` all project inside `frame`, in front of `cam`.
func _box_in_frame(cam: Camera3D, box: AABB, frame: Rect2, tag: String) -> bool:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var ok := true
	for c in 8:
		var corner := box.get_endpoint(c)
		ok = ok and not cam.is_position_behind(corner)
		var px := cam.unproject_position(corner)
		lo = lo.min(px)
		hi = hi.max(px)
	ok = ok and frame.has_point(lo) and frame.has_point(hi)
	print("INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s" % [tag, lo.x, lo.y, hi.x, hi.y, ok])
	return ok


func _report() -> void:
	for id in _stats:
		print("MEMBER %d %s" % [id, _stats[id]])
	var kinds := {}
	for c: Array in _crossings:
		kinds[c[1]] = true
	print(
		(
			"RESULT crossings=%d kinds=%s contact_frames=%d contact_points=%d"
			% [_crossings.size(), kinds.keys(), _contact_frames, _contact_points]
		)
	)
	if _failed:
		return
	for kind in ["helper", "officer", "walkout"]:
		if not kinds.has(kind):
			_invalid("no %s crossed mid-arch" % kind)
	if _expect_clear and _contact_frames > 0:
		_invalid("%d frames with hand or forearm points in the arch" % _contact_frames)
	if _plates:
		for kind in ["helper", "officer"]:
			if not _plated.has(kind):
				_invalid("no %s plate was saved" % kind)
