extends SceneTree
## Windowed plates of a worn backpack before (0d3a71d: the top of its panel
## 0.175 m behind and 0.06 m over the Spine_03 bone, a fixed 10 degree lean)
## and after (CarryWorn.worn_back(), its per-body BACK_ON_SPINE_M) the fix for
## board 4af10dd0, on male_01 and female_05 with one bag and two
## (SecurityLooks.TWO_BAG_SCALE), the body in its idle clip at the origin
## facing +z:
## - six orthographic views at one true scale (ORTHO_M tall), a 1 m reference
##   cube beside the body;
## - a close side view of the pack against the back (CLOSE_M tall);
## - a walking strip from the side (STRIP frames over the walk clip);
## - a distance shot of all 12 bodies in a row from behind, one bag on the even
##   bodies, two on the odd.
## Before a plate is saved, the pack's bounds (the bodies' too in the distance
## shot) are projected through its camera and must be MARGIN_PX inside the
## viewport, and sight lines (PlateSight, against colliders of every drawn mesh)
## to the pack must land on it. From the front the body hides the pack: there
## the lines to the pack must be blocked (the control). Any failure prints
## PROBE_INVALID and exits 1. The pack is placed here from the drawn Spine_03
## attachment (CarryOnProps' carry rig), as CarryPlace places it. Plates and a
## contact sheet per state go to tools/blender/out/worn-backpack/.
##
## Run (one windowed Godot run project-wide; take the lock first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/worn_back_plates_probe.gd

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/worn-backpack"
const SIZE := Vector2i(720, 900)
const MARGIN_PX := 8.0
const ORTHO_M := 3.2
const CLOSE_M := 0.9
const STRIP := 6
const SUBJECTS: Array[int] = [0, 9]
const SCALES: Array[float] = [1.0, 0.55]
const STATES: Array[String] = ["before", "after"]
## View name -> the direction the camera sits in from the subject.
const VIEWS := {
	"side_px": Vector3.RIGHT,
	"side_nx": Vector3.LEFT,
	"front_pz": Vector3.BACK,
	"back_nz": Vector3.FORWARD,
	"top_py": Vector3.UP,
	"bottom_ny": Vector3.DOWN,
}
const NO_TAG := "nothing-carries-this-tag"

var _failed := false
var _cam: Camera3D
var _floor: MeshInstance3D
var _cube: MeshInstance3D
var _props: CarryOnProps
var _sheets := {}


func _initialize() -> void:
	print("PROBE worn_back_plates (no sim, no random world seed: fixed poses)")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_REL))
	DisplayServer.window_set_size(SIZE)
	_stage()
	_run.call_deferred()


func _invalid(why: String) -> void:
	_failed = true
	print("PROBE_INVALID ", why)


func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.68, 0.74)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.environment.ambient_light_energy = 0.7
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	root.add_child(sun)
	_floor = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16.0, 16.0)
	_floor.mesh = plane
	root.add_child(_floor)
	_cube = MeshInstance3D.new()
	_cube.mesh = BoxMesh.new()
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.45, 0.45, 0.48)
	_cube.material_override = grey
	_cube.position = Vector3(0.72, 0.5, 0.72)
	root.add_child(_cube)
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.make_current()
	_props = CarryOnProps.new()
	root.add_child(_props)


## Body `b` at `at` facing +z, `clip` held at `seconds`, its carry rig made.
func _body(b: int, clip: String, seconds: float, at := Vector3.ZERO) -> Node3D:
	var body := PassengerLooks.SCENES[b].instantiate() as Node3D
	body.set_meta(&"body", b)
	body.position = at
	root.add_child(body)
	var player := body.get_node("AnimationPlayer") as AnimationPlayer
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(clip)
	player.seek(fmod(seconds, player.current_animation_length), true)
	_props._rig(body)
	return body


func _pack() -> Node3D:
	var pack := InteriorKit.instantiate(SecurityLooks.KIND_PIECES[SecurityLooks.Kind.BACKPACK])
	root.add_child(pack)
	return pack


## Where the pack is worn on `body` in `state`.
func _place(pack: Node3D, body: Node3D, scale_by: float, state: String) -> void:
	var spine := _props._spine_of(body)
	if state == "before":
		pack.global_transform = CarryWorn.worn_back_at(
			spine, 0.0, scale_by, Vector2(0.175, 0.06), false
		)
	else:
		pack.global_transform = CarryWorn.worn_back(spine, 0.0, scale_by, body.get_meta(&"body"))


func _bounds(node: Node3D) -> AABB:
	if not node.find_children("*", "Skeleton3D", true, false).is_empty():
		# A skinned body's own AABB is its bind pose's (arms out); bake the pose.
		var baked := PlateSight.colliders(root, [node] as Array[Node], {node: "drawn"})
		var posed: AABB = baked.get_meta("bounds")["drawn"]
		baked.free()
		return posed
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var part := mi.global_transform * mi.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


func _aim(from_dir: Vector3, centre: Vector3, ortho_m: float) -> void:
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = ortho_m
	_cam.near = 0.05
	_cam.far = 40.0
	_cam.global_position = centre + from_dir * 8.0
	var up := Vector3.FORWARD if absf(from_dir.y) > 0.5 else Vector3.UP
	_cam.look_at(centre, up)


## Whether every corner of `box` projects MARGIN_PX inside the viewport.
func _in_frame(box: AABB, label: String) -> bool:
	var rect := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size)).grow(-MARGIN_PX)
	var lo := Vector2(INF, INF)
	var hi := -lo
	for i in 8:
		var p := _cam.unproject_position(box.get_endpoint(i))
		lo = lo.min(p)
		hi = hi.max(p)
	var ok := rect.has_point(lo) and rect.has_point(hi)
	print("FRAME %s px %s..%s in %s: %s" % [label, lo.round(), hi.round(), rect, ok])
	return ok


## Sight lines from the camera to points of `pack`: [landed, blocked, whether
## every blocker is a mesh of owners[0] (the wearer's own body)].
func _sight(owners: Array[Node], pack: Node3D) -> Array:
	var own := {}
	for mi in owners[0].find_children("*", "MeshInstance3D", true, false):
		own[str(mi.name)] = true
	var holder := PlateSight.colliders(root, owners, {pack: "pack"})
	await physics_frame
	await physics_frame
	var box := _bounds(pack)
	var targets: Array[Vector3] = [box.get_center()]
	for k in [-0.3, 0.3]:
		targets.append(box.get_center() + Vector3(0.0, box.size.y * k, 0.0))
		targets.append(box.get_center() + Vector3(box.size.x * k, 0.0, box.size.z * k))
	var space := _cam.get_world_3d().direct_space_state
	var got := PlateSight.sight_lines(space, _cam.global_position, targets, "pack")
	holder.queue_free()
	var own_only: bool = not got["blockers"].is_empty()
	for name in got["blockers"]:
		own_only = own_only and own.has(name)
	print("SIGHT_BLOCKERS %s" % [got["blockers"]])
	return [got["on_subject"].size(), got["blockers"].size(), own_only]


func _shoot(name: String) -> Image:
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_REL, name]))
	print("PLATE %s.png" % name)
	return img


func _sheet(state: String, img: Image) -> void:
	var list: Array = _sheets.get(state, [])
	var small := img.duplicate() as Image
	small.resize(img.get_width() / 3, img.get_height() / 3)
	list.append(small)
	_sheets[state] = list


func _run() -> void:
	for f in 6:
		await process_frame
	for state in STATES:
		for b in SUBJECTS:
			await _six_and_close(state, b)
			await _strip(state, b)
		await _distance(state)
	for state in _sheets:
		_save_sheet(state, _sheets[state])
	print("PROBE worn_back_plates done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _six_and_close(state: String, b: int) -> void:
	var body := _body(b, "idle", 0.5)
	var pack := _pack()
	await process_frame
	await process_frame
	for scale_by in SCALES:
		_place(pack, body, scale_by, state)
		var tag := "%s_%s_s%.2f" % [state, PassengerLooks.BODIES[b], scale_by]
		var both := _bounds(body).merge(_bounds(pack)).merge(_bounds(_cube))
		for view: String in VIEWS:
			var dir: Vector3 = VIEWS[view]
			_floor.visible = view != "bottom_ny"
			_aim(
				dir,
				Vector3(0.36, 0.95, 0.36) if dir.y == 0.0 else Vector3(0.36, 1.0, 0.36),
				ORTHO_M
			)
			if dir.y != 0.0:
				_cam.size = 2.4
			var owners: Array[Node] = [body, pack, _cube]
			if _floor.visible:
				owners.append(_floor)
			if not _in_frame(both, "%s_%s" % [tag, view]):
				_invalid("%s_%s out of frame" % [tag, view])
			var seen: Array = await _sight(owners, pack)
			print("SIGHT %s_%s landed %d blocked %d" % [tag, view, seen[0], seen[1]])
			if view == "front_pz":
				# Control: the body stands between this camera and the pack.
				if seen[1] == 0:
					_invalid("%s front: no line to the pack was blocked" % tag)
			elif seen[0] == 0 and seen[2]:
				# A small pack narrower than the shoulders is behind the wearer's
				# own arm from the side: the view shows that, not a lost subject.
				print("HIDDEN_BY_OWN_BODY %s_%s" % [tag, view])
			elif seen[0] == 0:
				_invalid("%s_%s: no sight line lands on the pack" % [tag, view])
			_sheet(state, await _shoot("%s_%s" % [tag, view]))
		# The close side view of the pack against the back.
		_floor.visible = true
		var box := _bounds(pack)
		_aim(Vector3.RIGHT, box.get_center() + Vector3(0.0, 0.0, 0.12), CLOSE_M)
		if not _in_frame(box, "%s_close" % tag):
			_invalid("%s close out of frame" % tag)
		var near: Array[Node] = [body, pack, _floor]
		var close: Array = await _sight(near, pack)
		print("SIGHT %s_close landed %d blocked %d" % [tag, close[0], close[1]])
		if close[0] == 0:
			_invalid("%s close: no sight line lands on the pack" % tag)
		_sheet(state, await _shoot("%s_close" % tag))
	body.queue_free()
	pack.queue_free()
	await process_frame


func _strip(state: String, b: int) -> void:
	var frames: Array[Image] = []
	for n in STRIP:
		var body := _body(b, "walk", 0.0)
		var player := body.get_node("AnimationPlayer") as AnimationPlayer
		player.seek(player.current_animation_length * n / STRIP, true)
		var pack := _pack()
		await process_frame
		await process_frame
		_place(pack, body, 1.0, state)
		_aim(Vector3.RIGHT, Vector3(0.0, 0.95, 0.0), 2.2)
		var label := "%s_%s_walk%d" % [state, PassengerLooks.BODIES[b], n]
		if not _in_frame(_bounds(body).merge(_bounds(pack)), label):
			_invalid("%s out of frame" % label)
		var walkers: Array[Node] = [body, pack, _floor]
		var seen: Array = await _sight(walkers, pack)
		print("SIGHT %s landed %d blocked %d" % [label, seen[0], seen[1]])
		if seen[0] == 0:
			_invalid("%s: no sight line lands on the pack" % label)
		frames.append(await _shoot(label))
		body.queue_free()
		pack.queue_free()
		await process_frame
	var w := frames[0].get_width() / 2
	var h := frames[0].get_height() / 2
	var strip := Image.create(w * STRIP, h, false, frames[0].get_format())
	for n in STRIP:
		var small := frames[n].duplicate() as Image
		small.resize(w, h)
		strip.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * n, 0))
	var name := "%s_%s_walk_strip" % [state, PassengerLooks.BODIES[b]]
	strip.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_REL, name]))
	print("PLATE %s.png" % name)


func _distance(state: String) -> void:
	var bodies: Array[Node3D] = []
	var packs: Array[Node3D] = []
	for b in PassengerLooks.BODIES.size():
		bodies.append(_body(b, "idle", 0.5, Vector3((b - 5.5) * 0.9, 0.0, 0.0)))
		packs.append(_pack())
	await process_frame
	await process_frame
	for b in bodies.size():
		_place(packs[b], bodies[b], 1.0 if b % 2 == 0 else SecurityLooks.TWO_BAG_SCALE, state)
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 40.0
	_cam.global_position = Vector3(0.0, 4.0, -24.0)
	_cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	var all := _bounds(bodies[0])
	for n in bodies.size():
		all = all.merge(_bounds(bodies[n])).merge(_bounds(packs[n]))
	if not _in_frame(all, "%s_distance" % state):
		_invalid("%s distance out of frame" % state)
	var owners: Array[Node] = [_floor, _cube]
	owners.append_array(bodies)
	var landed := 0
	for n in packs.size():
		var mine: Array[Node] = owners.duplicate()
		mine.append_array(packs)
		var seen: Array = await _sight(mine, packs[n])
		landed += int(seen[0] > 0)
	print("SIGHT %s_distance packs seen %d of %d" % [state, landed, packs.size()])
	if landed < packs.size():
		_invalid("%s distance: %d packs not in sight" % [state, packs.size() - landed])
	await _shoot("%s_distance" % state)
	for n in bodies.size():
		bodies[n].queue_free()
		packs[n].queue_free()
	await process_frame


func _save_sheet(state: String, list: Array) -> void:
	var w: int = (list[0] as Image).get_width()
	var h: int = (list[0] as Image).get_height()
	var cols := 7
	var rows := ceili(list.size() / float(cols))
	var sheet := Image.create(w * cols, h * rows, false, (list[0] as Image).get_format())
	for i in list.size():
		sheet.blit_rect(list[i], Rect2i(0, 0, w, h), Vector2i(w * (i % cols), h * (i / cols)))
	var name := "%s_contact_sheet" % state
	sheet.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_REL, name]))
	print("PLATE %s.png (%d plates)" % [name, list.size()])
