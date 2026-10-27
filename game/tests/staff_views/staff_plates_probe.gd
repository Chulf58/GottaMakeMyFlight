extends SceneTree
## Windowed plate probe for the staff characters (StaffCharacters, Staff S3b).
##
## Studio stage: six-axis orthographic plates of each staff model at true scale
## beside a 1 m cube, in the idle pose, plus a front line-up of the two
## passenger models and the two staff models with the cube.
## Game stage: boots the real main scene with a new random sim seed (printed),
## builds ReferenceTerminal through the HUD's starter-terminal button, hires one
## agent alone for the walk strips, then one member per desk and scanner in all,
## and plates, at the HUD's own scale:
##   walk_strip       a check-in agent walking to its desk, four frames
##   arrive_strip     the same agent's last steps and the snap onto its post
##   desk_duty        an agent on duty behind a desk with a passenger being served
##   scanner_duty     an officer on duty at a scanner
##   distance         every on-duty member in one wide shot
## A staff member counts as shown when PlateSight.person_shown() passes (nine
## sight lines to the upper body against every visible mesh of the shell, the
## build, the plane, the passengers and the staff, skinned meshes in the pose
## drawn; landing points in frame; none under the HUD). Its drawn feet must be
## within FEET_TOLERANCE_M of the floor. A plate that fails prints PROBE_INVALID
## and the probe exits 1. A guard thread calls OS.crash() on a stall.
##
## Run (one windowed Godot run project-wide; this probe holds the slot):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path <repo>/game -s res://tests/staff_views/staff_plates_probe.gd -- --ui-scale=1.0
##
## Plates go to tools/blender/out/staff_views/.

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/staff_views"
const MAIN_SCENE := "res://main/main.tscn"
const PASSENGER_MODELS := [
	"res://assets/people/tcp_female_character_01.glb",
	"res://assets/people/tcp_male_character_01.glb",
]
const TOON_MATERIAL := "res://assets/materials/tcp_atlas_toon.tres"
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 60000
const WAIT_LIMIT_MS := 150000
const STALL_LIMIT_MS := 5000
const LIMIT_TICK := 4000
const MIN_SUBJECT_PX := 16.0
const FEET_TOLERANCE_M := 0.05
const OCCLUDER_OWNERS: Array[String] = [
	"Airside/Terminal", "BuildMode", "PlaneView", "PassengerViews", "StaffCharacters"
]
const SIX_AXIS := {
	"front": Vector3(0, 0, 1),
	"back": Vector3(0, 0, -1),
	"left": Vector3(-1, 0, 0),
	"right": Vector3(1, 0, 0),
	"top": Vector3(0, 1, 0),
	"bottom": Vector3(0, -1, 0),
}

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
var _staff: StaffSim
var _views: StaffCharacters
var _hud: PassengerHud
var _scale_tag := ""
var _saved: Array[Image] = []
## What _strip() saw at each captured frame: {state, clip, clip_pos, at}.
var _captured: Array[Dictionary] = []


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-scale="):
			root.content_scale_factor = float(arg.get_slice("=", 1))
	_scale_tag = "_s%.2f" % root.content_scale_factor
	print("PROBE ui_scale=%.2f" % root.content_scale_factor)
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


## Guard thread: a frozen main thread never reaches _process, so check from here.
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
			OS.crash("staff plates probe hung")


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _run() -> void:
	for role in StaffCharacters.CHARACTERS.size():
		await _plate_six_axis(StaffCharacters.CHARACTERS[role].resource_path)
	await _plate_lineup()
	await _boot()
	await _plate_walk_and_arrival()
	_hire_the_rest()
	await _plate_duty("desk_duty", StaffMember.Role.CHECKIN)
	await _plate_duty("scanner_duty", StaffMember.Role.SECURITY)
	await _plate_distance()
	_main.queue_free()
	await _frames(3)
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	if not _saved.is_empty():
		_save(_sheet(), "contact_sheet", false)
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


# ------------------------------------------------------------ studio


func _studio() -> Node3D:
	var studio := Node3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.86, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	studio.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	studio.add_child(sun)
	root.add_child(studio)
	return studio


func _spawn(path: String, parent: Node, pos: Vector3) -> Node3D:
	var node: Node3D = load(path).instantiate()
	node.position = pos
	parent.add_child(node)
	var wrong := 0
	var count := 0
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			if mat != null and mat.resource_path == TOON_MATERIAL:
				count += 1
			else:
				wrong += 1
	print("MATERIALS %s toon_surfaces=%d wrong=%d" % [path.get_file(), count, wrong])
	if count == 0 or wrong > 0:
		_invalid("%s: surfaces without the toon material" % path.get_file())
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	player.play("idle")
	player.seek(0.0, true)
	player.pause()
	return node


func _cube(parent: Node, pos: Vector3) -> MeshInstance3D:
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.1)
	cube.material_override = mat
	cube.position = pos
	cube.name = "ReferenceCube1m"
	parent.add_child(cube)
	return cube


func _corners(box: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 8:
		out.append(box.get_endpoint(i))
	return out


func _prove_in_frame(cam: Camera3D, label: String, points: Array[Vector3]) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		if cam.is_position_behind(p):
			_invalid("%s: point %s is behind the camera" % [label, p])
			return false
		var s := cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := rect.has_point(lo) and rect.has_point(hi)
	print("INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s" % [label, lo.x, lo.y, hi.x, hi.y, ok])
	if not ok:
		_invalid("%s: projected bounds leave the viewport" % label)
	return ok


## Orthographic sight lines, parallel to the camera's view, to a 3 x 3 grid over
## the subject's bounds as the camera sees them. At least PlateSight.MIN_ON land
## on the subject and none is blocked in front of it.
func _ortho_shown(cam: Camera3D, label: String, box: AABB, tag: String) -> bool:
	var space := cam.get_world_3d().direct_space_state
	var right := cam.global_basis.x
	var up := cam.global_basis.y
	var back := cam.global_basis.z
	var half_r := 0.0
	var half_u := 0.0
	for p in _corners(box):
		half_r = maxf(half_r, absf((p - box.get_center()).dot(right)))
		half_u = maxf(half_u, absf((p - box.get_center()).dot(up)))
	var on := 0
	var blockers: Array[String] = []
	for i in 3:
		for j in 3:
			var at := (
				box.get_center() + right * half_r * 0.3 * (i - 1) + up * half_u * 0.5 * (j - 1)
			)
			var from := at + back * 500.0
			var target: Array[Vector3] = [at]
			var lines := PlateSight.sight_lines(space, from, target, tag)
			on += (lines["on_subject"] as Array).size()
			blockers.append_array(lines["blockers"])
	var ok := on >= PlateSight.MIN_ON and blockers.is_empty()
	print("VISIBLE %s lines=9 on=%d blockers=%s ok=%s" % [label, on, blockers, ok])
	if not ok:
		_invalid("%s: the subject is hidden or not hit" % label)
	return ok


## Bounds of the drawn (baked) meshes per tag, with a fresh collider holder.
func _colliders(owners: Array[Node], subjects: Dictionary) -> Node3D:
	var holder := PlateSight.colliders(root, owners, subjects)
	var unbaked: Array = holder.get_meta("unbaked")
	if not unbaked.is_empty():
		_invalid("skinned meshes not baked: %s" % [unbaked])
	await physics_frame
	await physics_frame
	return holder


func _feet(label: String, box: AABB, floor_y: float) -> void:
	var gap := box.position.y - floor_y
	print(
		(
			"FEET %s lowest_y=%.3f floor_y=%.3f gap_m=%.3f height_m=%.3f"
			% [label, box.position.y, floor_y, gap, box.size.y]
		)
	)
	if absf(gap) > FEET_TOLERANCE_M:
		_invalid("%s: drawn feet %.3f m off the floor" % [label, gap])


func _plate_six_axis(path: String) -> void:
	var label := path.get_file().get_basename()
	_beat("six_axis_" + label)
	var studio := _studio()
	var subject := _spawn(path, studio, Vector3.ZERO)
	await _frames(2)
	var only: Array[Node] = [subject]
	var holder: Node3D = await _colliders(only, {subject: "s"})
	var box: AABB = (holder.get_meta("bounds") as Dictionary).get("s", AABB())
	holder.free()
	_feet(label, box, 0.0)
	var cube := _cube(studio, Vector3(box.end.x + 0.9, 0.5, box.end.z + 0.9))
	var whole := box.merge(AABB(cube.position - Vector3.ONE * 0.5, Vector3.ONE))
	await _frames(2)
	var scene: Array[Node] = [studio]
	holder = await _colliders(scene, {subject: "s"})
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.far = 1000.0
	studio.add_child(cam)
	cam.make_current()
	var sheet := Image.create(1920, 720, false, Image.FORMAT_RGBA8)
	var slot := 0
	for view in SIX_AXIS:
		var dir: Vector3 = SIX_AXIS[view]
		var up := Vector3.FORWARD if absf(dir.y) > 0.5 else Vector3.UP
		cam.look_at_from_position(whole.get_center() + dir * 200.0, whole.get_center(), up)
		cam.size = _ortho_size(cam, whole)
		var tag := "%s_%s" % [label, view]
		await _frames(3)
		if not _prove_in_frame(cam, tag, _corners(whole)):
			continue
		if not _ortho_shown(cam, tag, box, "s"):
			continue
		var img: Image = await PlateSight.grab(self)
		_save(img, "six_axis_%s" % tag, false)
		img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(
			img, Rect2i(0, 0, 640, 360), Vector2i((slot % 3) * 640, floori(slot / 3.0) * 360)
		)
		slot += 1
	_save(sheet, "six_axis_%s_sheet" % label)
	holder.free()
	studio.queue_free()
	await _frames(2)


## Front view of the passenger models and the staff models in a row, with the cube.
func _plate_lineup() -> void:
	_beat("lineup")
	var studio := _studio()
	var paths: Array[String] = []
	paths.append_array(PASSENGER_MODELS)
	for scene in StaffCharacters.CHARACTERS:
		paths.append(scene.resource_path)
	var subjects := {}
	var x := -2.4
	for path in paths:
		subjects[_spawn(path, studio, Vector3(x, 0, 0))] = path.get_file().get_basename()
		x += 1.2
	var cube := _cube(studio, Vector3(x, 0.5, 0))
	await _frames(2)
	var scene: Array[Node] = [studio]
	var holder: Node3D = await _colliders(scene, subjects)
	var bounds: Dictionary = holder.get_meta("bounds")
	var whole := AABB(cube.position - Vector3.ONE * 0.5, Vector3.ONE)
	for tag in bounds:
		whole = whole.merge(bounds[tag])
		_feet("lineup_" + str(tag), bounds[tag], 0.0)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.far = 1000.0
	studio.add_child(cam)
	cam.make_current()
	cam.look_at_from_position(whole.get_center() + Vector3(0, 0, 200), whole.get_center())
	cam.size = _ortho_size(cam, whole)
	await _frames(3)
	var ok := _prove_in_frame(cam, "lineup", _corners(whole))
	for tag in bounds:
		ok = _ortho_shown(cam, "lineup_" + str(tag), bounds[tag], str(tag)) and ok
	if ok:
		_save(await PlateSight.grab(self), "lineup_passengers_then_staff")
	holder.free()
	studio.queue_free()
	await _frames(2)


func _ortho_size(cam: Camera3D, box: AABB) -> float:
	var inv := cam.global_transform.affine_inverse()
	var w := 0.0
	var h := 0.0
	for p in _corners(box):
		var local := inv * p - inv * box.get_center()
		w = maxf(w, absf(local.x) * 2.0)
		h = maxf(h, absf(local.y) * 2.0)
	var aspect := root.get_visible_rect().size.x / root.get_visible_rect().size.y
	return maxf(h, w / aspect) * 1.15


# ------------------------------------------------------------ game


func _boot() -> void:
	_beat("boot")
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var seed := randi()
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	root.add_child(_main)
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_sim = _main.get_node("PassengerSim")
	_staff = _main.get_node("Staff")
	_views = _main.get_node("StaffCharacters")
	_hud = _main.get_node("PassengerHud")
	await _frames(5)
	_hud.press_starter_terminal()
	var build := _main.get_node("BuildMode") as BuildMode
	build.set_tool(BuildMode.Tool.NONE)
	await _frames(2)
	if build.tool != BuildMode.Tool.NONE or (build.get_node("Ghost") as Node3D).visible:
		_invalid("the build tool or its ghost is still on after clearing it")
	# One agent first, alone, for the walk strips: members hired together enter
	# on the same cell and walk on top of each other (see _hire_the_rest()).
	_staff.hire(StaffMember.Role.CHECKIN)
	_hud.press_speed(1)


## Hires the rest of the staff: one member per desk and scanner in all.
func _hire_the_rest() -> void:
	for i in _sim.layout.desks.size() - 1:
		_staff.hire(StaffMember.Role.CHECKIN)
	for scanner in _sim.layout.scanners:
		_staff.hire(StaffMember.Role.SECURITY)
	print(
		(
			"PROBE desks=%d scanners=%d hired checkin=%d security=%d"
			% [
				_sim.layout.desks.size(),
				_sim.layout.scanners.size(),
				_staff.count(StaffMember.Role.CHECKIN),
				_staff.count(StaffMember.Role.SECURITY)
			]
		)
	)
	_hud.press_speed(1)


## Steps frames until `done` holds; fails through _invalid() on LIMIT_TICK, on
## WAIT_LIMIT_MS or when the clock stalls.
func _until(stage: String, done: Callable) -> bool:
	_beat(stage)
	var start_ms := Time.get_ticks_msec()
	var moved_ms := start_ms
	var last_tick := _clock.tick
	while not done.call():
		var now_ms := Time.get_ticks_msec()
		if _clock.tick != last_tick:
			last_tick = _clock.tick
			moved_ms = now_ms
		if _clock.tick >= LIMIT_TICK:
			_invalid("%s: not met by tick %d" % [stage, LIMIT_TICK])
			return false
		if now_ms - start_ms > WAIT_LIMIT_MS:
			_invalid("%s: not met in %d ms" % [stage, WAIT_LIMIT_MS])
			return false
		if now_ms - moved_ms > STALL_LIMIT_MS and not _clock.paused:
			_invalid("%s: clock stalled at tick %d" % [stage, last_tick])
			return false
		await process_frame
	return true


func _aim(at: Vector3, distance: float, yaw: float) -> void:
	_rig.stop_follow()
	_rig.position = Vector3(at.x, 0.0, at.z)
	_rig.yaw = yaw
	_rig.distance = distance


## The first member (lowest id) of `role` in `state` with more than `min_left`
## path cells still ahead, serving a passenger when `serving`; null if none.
func _find(role: int, state: int, min_left := 0, serving := false) -> StaffMember:
	for id in _staff.member_ids():
		var m := _staff.get_member(id)
		if m.role != role or m.state != state:
			continue
		if m.path.size() - m.path_index <= min_left:
			continue
		if serving and not _serving(m.station):
			continue
		return m
	return null


func _all_on_duty() -> bool:
	for id in _staff.member_ids():
		if _staff.get_member(id).state != StaffMember.State.ON_DUTY:
			return false
	return true


func _describe(m: StaffMember) -> String:
	var node := _views.node_for(m.id)
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	return (
		(
			"member=%d role=%d state=%d at=%s drawn=%s yaw_deg=%.0f clip=%s playing=%s"
			+ " clip_pos=%.2f speed_scale=%.2f model=%s"
		)
		% [
			m.id,
			m.role,
			m.state,
			m.at,
			node.position,
			rad_to_deg(node.rotation.y),
			player.current_animation,
			player.is_playing(),
			player.current_animation_position,
			player.speed_scale,
			node.scene_file_path.get_file()
		]
	)


## Grabs the plate with the scene paused and checks every member in `ids` with
## PlateSight.person_shown() and its feet. Returns {shown, image}.
func _check(label: String, ids: Array[int]) -> Dictionary:
	paused = true
	var img: Image = await PlateSight.grab(self)
	var subjects := {}
	for id in ids:
		subjects[_views.node_for(id)] = str(id)
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		owners.append(_main.get_node(path))
	var holder: Node3D = await _colliders(owners, subjects)
	var bounds: Dictionary = holder.get_meta("bounds")
	var twin: Dictionary = await PlateSight.hud_twin(self, _main)
	var bare: Image = twin["image"]
	var changed := PlateSight.differing(img, bare, Rect2i(Vector2i.ZERO, img.get_size()), 4)
	print("HUD %s layers_hidden=%d plate_px_changed=%d" % [label, twin["layers"], changed])
	if changed == 0:
		_invalid("%s: hiding the HUD changed no pixel, so the HUD check proves nothing" % label)
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)
	var shown := 0
	for id in ids:
		var box: AABB = bounds.get(str(id), AABB())
		var seen := PlateSight.person_shown(_cam, box, str(id), frame, img, bare, MIN_SUBJECT_PX)
		print(
			(
				"VISIBLE %s %s px=%s height_px=%.0f on=%d past=%d blockers=%s in_frame=%s hud_px=%d ok=%s"
				% [
					label,
					_describe(_staff.get_member(id)),
					seen.get("px"),
					seen.get("height_px", 0.0),
					seen["on"],
					seen["past"],
					seen["blockers"],
					seen.get("in_frame"),
					seen.get("hud_px", 0),
					seen["ok"]
				]
			)
		)
		_feet("%s_member%d" % [label, id], box, _sim.grid.origin.y)
		shown += int(seen["ok"])
	holder.free()
	paused = false
	return {"shown": shown, "image": img}


## Aims at `at` from the four quarter turns from `yaw` until all of `ids` are
## shown; saves the plate. Returns whether it was saved.
func _plate(name: String, ids: Array[int], at: Vector3, distance: float, yaw: float) -> bool:
	var result := {}
	for turn in 4:
		var view_yaw := wrapf(yaw + turn * PI / 2.0, -PI, PI)
		_aim(at, distance, view_yaw)
		await _frames(25)
		print(
			(
				"PLATE %s%s tick=%d at=%s distance=%.0f yaw=%.2f"
				% [name, _scale_tag, _clock.tick, at, distance, view_yaw]
			)
		)
		result = await _check(name, ids)
		if result["shown"] == ids.size():
			_save(result["image"], name)
			return true
	_invalid("%s: not every staff member shown from any side" % name)
	_save(result["image"], name + "_INVALID", false)
	return false


## A strip of `count` frames of member `id`, the camera following it, one frame
## every `every_ticks` sim ticks while the clock runs. Each frame proves the
## member is in frame. Returns the strip image, or null on failure.
func _strip(
	name: String, id: int, count: int, every_ticks: int, distance: float, yaw: float
) -> Image:
	var frames: Array[Image] = []
	_captured.clear()
	for i in count:
		var node := _views.node_for(id)
		if node == null:
			_invalid("%s: member %d left the floor mid-strip" % [name, id])
			return null
		_aim(node.position, distance, yaw)
		_hud.press_speed(0)
		await _frames(20)
		var one: Array[int] = [id]
		var check: Dictionary = await _check("%s_f%d" % [name, i], one)
		if check["shown"] != 1:
			_invalid("%s: frame %d does not show member %d" % [name, i, id])
			_save(check["image"], "%s_f%d_INVALID" % [name, i], false)
			_hud.press_speed(1)
			return null
		frames.append(check["image"])
		var player := node.get_node("AnimationPlayer") as AnimationPlayer
		(
			_captured
			. append(
				{
					"state": _staff.get_member(id).state,
					"clip": player.current_animation,
					"clip_pos": player.current_animation_position,
					"at": node.position,
				}
			)
		)
		print("CAPTURED %s_f%d %s" % [name, i, _captured[_captured.size() - 1]])
		_hud.press_speed(1)
		if i == count - 1:
			break
		var target := _clock.tick + every_ticks
		if not await _until(name, func() -> bool: return _clock.tick >= target):
			return null
	var w := frames[0].get_width() / 2
	var h := frames[0].get_height() / 2
	var strip := Image.create(w * count, h, false, Image.FORMAT_RGBA8)
	for i in count:
		var small := frames[i].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		strip.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * i, 0))
	_save(strip, name)
	return strip


func _plate_walk_and_arrival() -> void:
	var checkin := StaffMember.Role.CHECKIN
	var to_station := StaffMember.State.TO_STATION
	var walking := func() -> bool: return _find(checkin, to_station, 5) != null
	if not await _until("walking", walking):
		return
	var agent := _find(checkin, to_station, 5)
	print("WALK %s" % _describe(agent))
	if await _strip("walk_strip", agent.id, 4, 6, 9.0, PI) == null:
		return
	# Every frame walking, each drawn somewhere new and at a new point of the clip.
	for i in range(1, _captured.size()):
		var was: Dictionary = _captured[i - 1]
		var now: Dictionary = _captured[i]
		var moved: float = (now["at"] as Vector3).distance_to(was["at"])
		if (
			now["clip"] != "walk"
			or moved < 0.2
			or is_equal_approx(now["clip_pos"], was["clip_pos"])
		):
			_invalid("walk_strip: frame %d is not a walking step on from frame %d" % [i, i - 1])
	var near := func() -> bool:
		return agent.state == to_station and agent.path.size() - agent.path_index <= 2
	if not await _until("near_desk", near):
		return
	if await _strip("arrive_strip", agent.id, 4, 10, 9.0, PI) == null:
		return
	var first: Dictionary = _captured[0]
	var last: Dictionary = _captured[_captured.size() - 1]
	print("ARRIVE first=%s last=%s post=%s" % [first, last, _views.post_position(agent.station)])
	if first["state"] != to_station or first["clip"] != "walk":
		_invalid("arrive_strip: the first frame is not the agent walking")
	if last["state"] != StaffMember.State.ON_DUTY or last["clip"] != "idle":
		_invalid("arrive_strip: the last frame is not the agent idle on duty")
	elif (last["at"] as Vector3).distance_to(_views.post_position(agent.station)) > 0.001:
		_invalid("arrive_strip: the last frame does not draw the agent on its post")


func _serving(station: int) -> bool:
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		if (
			p.station == station
			and (p.stage == Passenger.Stage.CHECKIN or p.stage == Passenger.Stage.SECURITY)
		):
			return true
	return false


func _plate_duty(name: String, role: StaffMember.Role) -> void:
	_hud.press_speed(3)
	var on_duty := StaffMember.State.ON_DUTY
	var serving := func() -> bool: return _find(role, on_duty, -1, true) != null
	if not await _until(name, serving):
		return
	_hud.press_speed(0)
	var m := _find(role, on_duty, -1, true)
	print("DUTY %s %s post=%s" % [name, _describe(m), _views.post_position(m.station)])
	var one: Array[int] = [m.id]
	await _plate(name, one, _views.post_position(m.station), 8.0, PI)
	_hud.press_speed(1)


func _plate_distance() -> void:
	_hud.press_speed(3)
	if not await _until("all_on_duty", _all_on_duty):
		return
	_hud.press_speed(0)
	var ids: Array[int] = []
	var centre := Vector3.ZERO
	for id in _staff.member_ids():
		ids.append(id)
		centre += _views.node_for(id).position
	centre /= ids.size()
	await _plate("distance", ids, centre, 26.0, PI)


func _save(img: Image, name: String, sheet := true) -> void:
	var path := _out_dir.path_join(name + _scale_tag + ".png")
	var err := img.save_png(path)
	if err != OK:
		_invalid("could not save %s (error %d)" % [path, err])
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
	if sheet:
		var copy := img.duplicate() as Image
		copy.convert(Image.FORMAT_RGBA8)
		_saved.append(copy)


## Every saved plate scaled to 640 wide, two to a row.
func _sheet() -> Image:
	var w := 640
	var rows := (_saved.size() + 1) / 2
	var heights: Array[int] = []
	for img in _saved:
		heights.append(int(img.get_height() * w / float(img.get_width())))
	var row_h := 0
	for h in heights:
		row_h = maxi(row_h, h)
	var sheet := Image.create(w * 2, row_h * rows, false, Image.FORMAT_RGBA8)
	for i in _saved.size():
		var small := _saved[i].duplicate() as Image
		small.resize(w, heights[i], Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, heights[i]), Vector2i(w * (i % 2), row_h * (i / 2)))
	return sheet
