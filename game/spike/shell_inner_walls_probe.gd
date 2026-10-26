extends SceneTree
## Windowed near plates of the Toon terminal shell's inside walls, from inside,
## at two opposite headings: north (yaw 0, the airside wall's inward face) and
## south (yaw PI, the landside wall's). Each frames three facade bays around a
## doorway (Facade_<side>_05..07; Door_2 north, Door_7 south).
##
## The real main scene supplies the light, environment and camera rig; its Toon
## terminal (Airside/Terminal) is hidden and tp_airport_shell.glb is added at
## the same place with the roof nodes (Upper, Canopy, Lights_Upper) hidden, as
## the roof dissolve will leave it. main.tscn is not edited.
##
## Run (one windowed Godot run project-wide; take the slot lock first):
##   timeout 600 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/shell_inner_walls_probe.gd
##
## Each subject (the inward face of its three bays) must project inside the
## frame, clear of the HUD strips, and at least half of the camera rays aimed at
## its solid parts must first hit within 5 cm of the inward-face plane, with
## every visible shell mesh as an occluder; otherwise the probe prints
## PROBE_INVALID and exits 1. A guard thread calls OS.crash() on a stall.
## Plates go to tools/blender/out/shell-inner-walls/.

const OUT_REL := "res://../tools/blender/out/shell-inner-walls"
const SHELL := "res://assets/buildings/tp_airport_shell.glb"
const ROOF := ["Upper", "Canopy", "Lights_Upper"]
const MARGIN_PX := 8.0
const TOP_HUD_PX := 56.0
const BOTTOM_HUD_PX := (
	BuildMenu.MARGIN
	+ BuildMenu.BAR_H
	+ BuildMenu.GAP
	+ BuildMenu.TRAY_H
	+ BuildMenu.GAP
	+ BuildMenu.STATUS_H
)
## Inward-face planes (build_terminal_shell.py: backdrop -95.25 / -64.35, INNER 0.25).
const NORTH_INNER_Z := -95.0
const SOUTH_INNER_Z := -64.6
## Bays 5..7 on the long sides (pilaster centrelines -21.5, -18.5, -15.5, -12.5).
const BAYS_X := Vector2(-21.5, -12.5)
## The doorway in bay 6 (x -18.14..-15.84, floor to 3.80), left out of the rays.
const DOOR_X := Vector2(-18.14, -15.84)
const DOOR_TOP := 3.8
const FLOOR_Y := 0.3
const WALL_TOP := 5.49
const DISTANCES := [12.0, 14.0, 16.0, 18.0, 21.0]
const HANG_MS := 90000

var _out_dir := ""
var _failed := false
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _stop := false


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	var main: Node3D = (load("res://main/main.tscn") as PackedScene).instantiate()
	var clock := main.get_node("SimClock") as SimClock
	var seed := randi()
	clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	root.add_child(main)
	clock.set_paused(true)
	(main.get_node("PassengerHud") as CanvasLayer).visible = false
	var terminal := main.get_node("Airside/Terminal") as Node3D
	terminal.visible = false
	var shell: Node3D = (load(SHELL) as PackedScene).instantiate()
	shell.transform = terminal.transform
	terminal.get_parent().add_child(shell)
	for roof_name in ROOF:
		var node := shell.find_child(roof_name, true, false) as Node3D
		if node == null:
			_invalid("shell has no node %s" % roof_name)
			continue
		node.visible = false
		print("PROBE hid %s" % node.get_path())
	await _frames(3)
	_beat("colliders")
	var occluders := _colliders(shell)
	print("PROBE occluder bodies=%d" % occluders.get_child_count())
	var rig := main.get_node("TycoonCamera") as TycoonCamera
	var cam := rig.get_node("Camera3D") as Camera3D
	cam.make_current()
	print("PROBE viewport=%s" % root.get_visible_rect().size)
	var shots := [
		["north", 0.0, Vector3(-17.0, 0.0, -90.5), NORTH_INNER_Z, "N", Vector3.BACK],
		["south", PI, Vector3(-17.0, 0.0, -69.1), SOUTH_INNER_Z, "S", Vector3.FORWARD],
	]
	var plates: Array[Image] = []
	for shot in shots:
		_beat(shot[0])
		var box := AABB(Vector3(BAYS_X.x, FLOOR_Y, shot[3]), Vector3(BAYS_X.y - BAYS_X.x, 0, 0))
		box = box.expand(Vector3(BAYS_X.y, WALL_TOP, shot[3]))
		var framed := false
		for d in DISTANCES:
			rig.position = shot[2]
			rig.yaw = shot[1]
			rig.distance = d
			rig.zoom(1.0)
			await _frames(6)
			if _in_frame(cam, shot[0], box, false):
				framed = true
				break
		print(
			(
				"CAMERA %s pos=%s distance=%.1f pitch_deg=%.1f yaw=%.2f"
				% [shot[0], cam.global_position, rig.distance, -cam.rotation_degrees.x, rig.yaw]
			)
		)
		if not framed:
			_invalid("%s: no distance frames the bays" % shot[0])
		var ok := _in_frame(cam, shot[0], box, true)
		await physics_frame
		await physics_frame
		ok = _prove_visible(cam, shot[0], shot[3], shot[4], shot[5]) and ok
		var img := await _grab()
		_print_colour(cam, img, shot[0], shot[3])
		if ok:
			_save(img, "near_inside_%s.png" % shot[0])
			plates.append(img)
	if plates.size() == shots.size():
		_save(_contact_sheet(plates), "contact_sheet.png")
	occluders.free()
	print("PROBE done failed=%s" % _failed)
	_finish()
	quit(1 if _failed else 0)


func _in_frame(cam: Camera3D, label: String, box: AABB, report: bool) -> bool:
	var size := root.get_visible_rect().size
	var rect := Rect2(
		Vector2(MARGIN_PX, TOP_HUD_PX), size - Vector2(MARGIN_PX * 2, TOP_HUD_PX + BOTTOM_HUD_PX)
	)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var behind := false
	for i in 8:
		var p := box.get_endpoint(i)
		behind = behind or cam.is_position_behind(p)
		var s := cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := not behind and rect.has_point(lo) and rect.has_point(hi)
	if report:
		print(
			(
				"INFRAME %s bays screen=(%.0f,%.0f)-(%.0f,%.0f) size_px=(%.0f,%.0f) ok=%s"
				% [label, lo.x, lo.y, hi.x, hi.y, hi.x - lo.x, hi.y - lo.y, ok]
			)
		)
		if not ok:
			_invalid("%s: the bays leave the frame" % label)
	return ok


## Rays from the camera to a grid on the inward face of the three bays, the
## doorway opening left out. At least half must first hit a face of one of the
## bays' own meshes (Facade_<side>_05..07) whose normal points inward, within
## 5 cm of the inward-face plane, between the bay ends and below the wall top.
func _prove_visible(
	cam: Camera3D, label: String, plane_z: float, side: String, inward: Vector3
) -> bool:
	var space := cam.get_world_3d().direct_space_state
	var bays := []
	for bay in [5, 6, 7]:
		bays.append("Facade_%s_%02d" % [side, bay])
	var hits := 0
	var total := 0
	var first_hits := {}
	for i in 10:
		var x := lerpf(BAYS_X.x + 0.3, BAYS_X.y - 0.3, i / 9.0)
		for j in 5:
			var y := lerpf(FLOOR_Y + 0.4, WALL_TOP - 0.3, j / 4.0)
			if x > DOOR_X.x - 0.1 and x < DOOR_X.y + 0.1 and y < DOOR_TOP + 0.1:
				continue
			total += 1
			var target := Vector3(x, y, plane_z)
			var from := cam.global_position
			var q := PhysicsRayQueryParameters3D.create(
				from, target + (target - from).normalized() * 0.3
			)
			var hit := space.intersect_ray(q)
			var owner := ""
			if hit:
				owner = str((hit.collider as Node).get_meta("mesh", ""))
			first_hits[owner] = first_hits.get(owner, 0) + 1
			if (
				hit
				and bays.has(owner)
				and (hit.normal as Vector3).dot(inward) > 0.99
				and absf(hit.position.z - plane_z) < 0.05
				and hit.position.x > BAYS_X.x - 0.05
				and hit.position.x < BAYS_X.y + 0.05
				and hit.position.y < WALL_TOP + 0.05
			):
				hits += 1
	var ok := hits > 0 and hits * 2 >= total
	print(
		(
			"VISIBLE %s inward_face ray_hits=%d/%d ok=%s first_hit_meshes=%s"
			% [label, hits, total, ok, first_hits]
		)
	)
	if not ok:
		_invalid("%s: inward face occluded or not hit (%d of %d rays)" % [label, hits, total])
	return ok


## The rendered colour where the middle of bay 5's inward face lands on screen
## (a 5x5 pixel mean). A pointer for the reader of the plate, not a verdict.
func _print_colour(cam: Camera3D, img: Image, label: String, plane_z: float) -> void:
	var s := cam.unproject_position(Vector3(-20.0, 2.9, plane_z))
	var sum := Color(0, 0, 0)
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			sum += img.get_pixel(int(s.x) + dx, int(s.y) + dy)
	var c := sum / 25.0
	print(
		(
			"COLOUR %s bay5 inward face at screen (%.0f,%.0f) rgb=(%d,%d,%d)"
			% [label, s.x, s.y, c.r * 255, c.g * 255, c.b * 255]
		)
	)


## The plates side by side at half size.
func _contact_sheet(plates: Array[Image]) -> Image:
	var w := plates[0].get_width() / 2
	var h := plates[0].get_height() / 2
	var sheet := Image.create(w * plates.size(), h, false, Image.FORMAT_RGBA8)
	for i in plates.size():
		var small := plates[i].duplicate() as Image
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * i, 0))
	return sheet


## One static body per visible shell mesh, in world space.
func _colliders(shell: Node3D) -> Node3D:
	var holder := Node3D.new()
	holder.name = "ProbeColliders"
	root.add_child(holder)
	for mi in shell.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if not inst.is_visible_in_tree():
			continue
		var local_faces := inst.mesh.get_faces()
		if local_faces.is_empty():
			continue
		var faces := PackedVector3Array()
		var at := inst.global_transform
		for p in local_faces:
			faces.append(at * p)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var shape_node := CollisionShape3D.new()
		shape_node.shape = shape
		var body := StaticBody3D.new()
		body.set_meta("mesh", inst.name)
		body.add_child(shape_node)
		holder.add_child(body)
	return holder


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
		_beat(_stage)
	await RenderingServer.frame_post_draw


func _grab() -> Image:
	await _frames(4)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


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
			OS.crash("shell_inner_walls_probe: main thread stalled in %s" % stage)
