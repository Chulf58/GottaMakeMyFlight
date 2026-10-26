extends SceneTree
## Windowed plates of the Toon terminal shell's cutaway (Shell 3/4) in the
## real main scene: the roof dithering out as the camera zooms in and the
## camera-side facade squashed to a kerb (ShellCutaway, ShellView).
##
## Static plates: far (roof drawn) at two opposite headings, the full-zoom
## distance shot, near (roof gone) at five headings, a 40 m facade cut, both
## doorways close up, two corners. Frame strips (grabbed in memory, saved after
## the strip): the roof fading out (zoom 140 -> 70 m), fading in (70 -> 140 m),
## a reversal half way, and a held-key turn across the dead band (one side
## rising while its neighbour drops). Then a forced roof level 0.5 up close
## (thick outlines), the diagonal with the roof gate on and off at 220, 130 and
## 105 m, and a facade bay hidden once and watched through a cut cycle.
##
## Run (one windowed Godot run project-wide; take the slot lock first):
##   timeout 600 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/shell_dissolve_plates_probe.gd
## Add `-- --only=far_h0,strip_out_h0,...` to shoot only the named plates and
## strips (strip_turn, forced, gate and removed_bay name their groups).
##
## The sim clock is paused and the HUD and build menu hidden. Every plate
## projects its subject points inside the frame with a margin (and in front of
## the camera). Visibility is checked with rays against bodies baked from every
## drawn shell mesh at its current transform (glass left out): far plates must
## hit the roof, near and doorway plates must reach the interior floor, and the
## far plates' interior rays must be blocked by the roof (the control). Strip
## frames are checked for framing only. Rays are structural evidence: a
## dithered pixel is not a collider. On a
## failure the probe prints PROBE_INVALID and exits 1. A guard thread calls
## OS.crash() on a stall. Plates go to tools/blender/out/shell-dissolve/.

const OUT_REL := "res://../tools/blender/out/shell-dissolve"
const MARGIN_PX := 16.0
const HANG_MS := 60000
const SETTLE_MAX_FRAMES := 180
## The shell's footprint centre in its own frame (the facade bounds' centre).
const CENTRE := Vector3(-0.5, 0.0, 0.2)
const TILE := Vector2i(480, 270)
const ROOF_NAMES := ["Upper", "Canopy", "Lights_Upper", "Poles"]
const GLASS := "res://assets/materials/tp_glass.tres"

var _out_dir := ""
var _failed := false
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _stop := false
var _cam: Camera3D
var _rig: TycoonCamera
var _view: ShellView
var _shell: Node3D
## Static bodies baked from every drawn shell mesh at its current transform
## (glass left out), rebuilt for each pose.
var _occluders: Node3D
var _plates: Array[Image] = []
var _only := PackedStringArray()
var _strips: Array = []


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	randomize()
	var world_seed := randi()
	seed(world_seed)
	print("PROBE seed=%d" % world_seed)
	var main: Node3D = (load("res://main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	(main.get_node("SimClock") as SimClock).set_paused(true)
	(main.get_node("PassengerHud") as CanvasLayer).visible = false
	(main.get_node("BuildMenu") as CanvasLayer).visible = false
	_rig = main.get_node("TycoonCamera") as TycoonCamera
	_cam = _rig.get_node("Camera3D") as Camera3D
	_cam.make_current()
	_view = main.get_node("ShellView") as ShellView
	_shell = main.get_node("Airside/Terminal") as Node3D
	await _frames(3)
	print("PROBE viewport=%s msaa_3d=%d" % [root.get_visible_rect().size, root.msaa_3d])
	print(
		(
			"PROBE shell=%s ready=%s roof_nodes=%d side_pieces=%s"
			% [
				_shell.scene_file_path,
				_view.is_ready(),
				_view.roof_nodes.size(),
				_view.side_pieces.map(func(a: Array) -> int: return a.size())
			]
		)
	)
	if not _view.is_ready() or not _shell.scene_file_path.ends_with("tp_airport_shell.glb"):
		_invalid("main.tscn does not run ShellView on the shell")
		_end()
		return
	_only = _only_arg()
	print("PROBE only=%s" % (_only if not _only.is_empty() else ["(all)"]))
	await _static_plates()
	await _fade_strips()
	if _wanted("strip_turn"):
		await _turn_strip()
	if _wanted("forced"):
		await _forced_level_plate()
	if _wanted("gate"):
		await _gate_pairs()
	if _wanted("removed_bay"):
		await _removed_bay_plates()
	if not _plates.is_empty():
		_sheet(_plates, "contact_sheet_plates.png", 4)
	var strip_tiles: Array[Image] = []
	for row in _strips:
		strip_tiles.append_array(row)
	if not strip_tiles.is_empty():
		_sheet(strip_tiles, "contact_sheet_strips.png", 5)
	_end()


## The plate and strip names after `--only=` in the user arguments (after
## `--`), comma-separated; empty runs everything.
func _only_arg() -> PackedStringArray:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			return arg.trim_prefix("--only=").split(",", false)
	return PackedStringArray()


func _wanted(name: String) -> bool:
	return _only.is_empty() or _only.has(name)


func _end() -> void:
	print("PROBE done failed=%s" % _failed)
	_finish()
	quit(1 if _failed else 0)


## [name, focus in shell space, yaw degrees, distance, subject]
func _static_poses() -> Array:
	var door6 := _local(_shell.find_child("Doorway_6", true, false) as Node3D)
	var door3 := _local(_shell.find_child("Doorway_3", true, false) as Node3D)
	return [
		["far_h0", CENTRE, 0.0, 220.0, "building"],
		["far_h180", CENTRE, 180.0, 220.0, "building"],
		["distance_300", CENTRE, 35.0, 300.0, "building"],
		["near_h0", CENTRE, 0.0, 70.0, "interior"],
		["near_h180", CENTRE, 180.0, 70.0, "interior"],
		["near_h90", CENTRE, 90.0, 70.0, "interior"],
		["near_diag_se", CENTRE, 45.0, 70.0, "interior"],
		["near_diag_nw", CENTRE, -135.0, 70.0, "interior"],
		["cut_40m_south", Vector3(0.0, 0.0, 10.0), 20.0, 40.0, "south"],
		["door_landside_6", Vector3(door6.x, 0.0, door6.z - 2.0), 0.0, 25.0, "door6"],
		["door_airside_3", Vector3(door3.x, 0.0, door3.z + 2.0), 180.0, 25.0, "door3"],
		["door_landside_6_close", Vector3(door6.x, 0.0, door6.z - 1.0), 15.0, 12.0, "door6"],
		["corner_se", Vector3(30.0, 0.0, 12.0), 45.0, 30.0, "corner_se"],
		["corner_nw", Vector3(-31.0, 0.0, -12.0), -135.0, 30.0, "corner_nw"],
	]


func _static_plates() -> void:
	for pose in _static_poses():
		var label: String = pose[0]
		if not _wanted(label):
			continue
		_beat(label)
		await _place(pose[1], pose[2], pose[3])
		var ok := _prove(label, pose[4])
		var img := await _grab_now()
		_log_state(label)
		var subject: String = pose[4]
		if subject.begins_with("door"):
			var doorway := _view.doorways[(6 if subject == "door6" else 3) - 1]
			ok = _prove_jambs(label, doorway) and ok
			ok = (await _prove_open_doorway(label, doorway, img)) and ok
		if ok:
			_keep(img, label + ".png")


## A world point in a doorway's frame: `along` the facade from its centre,
## `inward` toward the interior, at shell height `y`.
func _doorway_point(doorway: ShellView.Doorway, along: float, inward: float, y: float) -> Vector3:
	var centre := _shell.global_transform.affine_inverse() * doorway.centre_world
	var outward := 1.0 if centre.z > 0.0 else -1.0
	return _world(Vector3(centre.x + along, y, centre.z - outward * inward))


## Rays from the camera to the top of each jamb must first hit that jamb.
func _prove_jambs(label: String, doorway: ShellView.Doorway) -> bool:
	var ok := doorway.jambs.size() == 2
	print("JAMBS %s count=%d" % [label, doorway.jambs.size()])
	for jamb in doorway.jambs:
		var box := _box_of(jamb.find_children("*", "MeshInstance3D"))
		var top := Vector3(box.get_center().x, box.end.y - 0.02, box.get_center().z)
		print("JAMB %s %s visible=%s top=%s" % [label, jamb.name, jamb.is_visible_in_tree(), top])
		ok = jamb.is_visible_in_tree() and ok
		ok = _rays_hit("%s/%s" % [label, jamb.name], [top], [String(jamb.name)], 0.3) and ok
	if not ok:
		_invalid("%s: jambs missing, hidden or occluded" % label)
	return ok


## Rendered proof that the hole drops the door bay's squashed lintel: the
## pixels where the lintel's top would be (over the opening, at the kerb top
## on the doorway line) must look like the floor inside, not like the kerb
## beside the opening. Control: with the bay's holes switched off for one
## render, the same pixels must look like the kerb (the check is engaged).
func _prove_open_doorway(label: String, doorway: ShellView.Doorway, img: Image) -> bool:
	var kerb_top := ShellCutaway.FLOOR_Y + InteriorKit.STUB_HEIGHT - 0.01
	var lintel := _doorway_point(doorway, 0.0, 0.0, kerb_top)
	var kerb := _doorway_point(doorway, 2.3, 0.0, kerb_top)
	var floor_inside := _doorway_point(doorway, 0.0, -2.0, ShellCutaway.FLOOR_Y)
	var lum := [_luma(img, lintel), _luma(img, kerb), _luma(img, floor_inside)]
	var open_ok := absf(lum[0] - lum[2]) < absf(lum[0] - lum[1]) and absf(lum[1] - lum[2]) > 0.1
	print(
		(
			"HOLE %s open lintel_luma=%.3f kerb_luma=%.3f floor_luma=%.3f ok=%s"
			% [label, lum[0], lum[1], lum[2], open_ok]
		)
	)
	var no_holes: Array[AABB] = []
	for mat in doorway.materials:
		ShellView.set_holes(mat, no_holes)
	var shut := await _grab_now()
	doorway.draw_open(true)
	await _frames(2)
	var ctrl := _luma(shut, lintel)
	var ctrl_ok := absf(ctrl - lum[1]) < absf(ctrl - lum[2])
	print("HOLE %s control_holes_off lintel_luma=%.3f ok=%s" % [label, ctrl, ctrl_ok])
	if not (open_ok and ctrl_ok):
		_invalid("%s: lintel over the opening not shown dropped (or control not engaged)" % label)
	return open_ok and ctrl_ok


## Mean luminance of the 3x3 pixels around where `world` projects.
func _luma(img: Image, world: Vector3) -> float:
	var at := Vector2i(_cam.unproject_position(world).round())
	var total := 0.0
	var count := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var p := at + Vector2i(dx, dy)
			if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
				total += img.get_pixelv(p).get_luminance()
				count += 1
	print("  PIXEL world=%s screen=%s count=%d" % [world, at, count])
	return total / maxf(count, 1.0)


## The body name for a baked mesh: the jamb it belongs to, or the mesh's own.
func _piece_name(mi: MeshInstance3D) -> String:
	var node: Node = mi
	while node != null and node != _shell:
		if String(node.name).begins_with("Jamb_"):
			return String(node.name)
		node = node.get_parent()
	return String(mi.name)


## Zoom strips at the real camera easing, captured on the frames where the
## roof level first passes each mark.
func _fade_strips() -> void:
	if _wanted("strip_out_h0"):
		_beat("strip_out")
		await _place(CENTRE, 0.0, 140.0)
		_rig.zoom(0.5)
		var marks := [0.0, 0.25, 0.5, 0.75, 1.0]
		_strips.append(await _capture_levels("strip_out_h0", marks, true, -1.0))
	if _wanted("strip_in_h180"):
		_beat("strip_in")
		await _place(CENTRE, 180.0, 70.0)
		_rig.zoom(2.0)
		var marks := [1.0, 0.75, 0.5, 0.25, 0.0]
		_strips.append(await _capture_levels("strip_in_h180", marks, false, -1.0))
	if _wanted("strip_reverse_h0"):
		_beat("strip_reverse")
		await _place(CENTRE, 0.0, 140.0)
		_rig.zoom(0.5)
		_strips.append(await _capture_levels("strip_reverse_h0", [0.25, 0.5], true, 0.5))


## Captures the frame where the roof level first reaches each mark (rising)
## or drops to it (falling). With `reverse_at` >= 0 the camera zooms back out
## once the level reaches it, and the strip goes on down to 0.
func _capture_levels(label: String, marks: Array, rising: bool, reverse_at: float) -> Array[Image]:
	var shots: Array = []
	var levels: Array[String] = []
	var next := 0
	var reversed := reverse_at < 0.0
	var going_up := rising
	for frame in 600:
		await process_frame
		await RenderingServer.frame_post_draw
		_beat(label)
		var level := _view.cutaway.roof_level
		levels.append("%.2f" % level)
		var hit := false
		if next < marks.size():
			var mark: float = marks[next]
			hit = level >= mark if going_up else level <= mark
		if hit:
			# Grabbed now, saved after the strip, so saving does not stall it.
			var name := "%s_%d_level_%03d" % [label, shots.size(), roundi(level * 100.0)]
			shots.append([root.get_texture().get_image(), name])
			_log_state(name)
			_prove(name, "building_frame")
			next += 1
		if not reversed and level >= reverse_at:
			reversed = true
			going_up = false
			_rig.zoom(2.0)
			marks = [level - 0.01, 0.25, 0.0]
			next = 0
			print("STRIP %s reversed at level=%.2f distance=%.1f" % [label, level, _rig.distance])
		if reversed and next >= marks.size():
			break
	print("STRIP %s levels=%s" % [label, ",".join(levels)])
	if not reversed or next < marks.size():
		_invalid("%s: reached %d of %d marks (reversed=%s)" % [label, next, marks.size(), reversed])
	return _save_shots(shots)


func _save_shots(shots: Array) -> Array[Image]:
	var row: Array[Image] = []
	for shot in shots:
		var img := shot[0] as Image
		img.convert(Image.FORMAT_RGBA8)
		row.append(_keep(img, String(shot[1]) + ".png", false))
	return row


## A continuous turn, as Q held down turns the camera, from yaw 45 (south and
## east cut) to -45 (south and west), crossing the east-west dead band: east
## rises while west drops; frames at east levels 1, 0.75, 0.5, 0.25, 0.
func _turn_strip() -> void:
	var label := "strip_turn_se_to_sw"
	_beat(label)
	await _place(CENTRE, 45.0, 70.0)
	var shots: Array = []
	var marks := [1.0, 0.75, 0.5, 0.25, 0.0]
	var next := 0
	var east := ShellCutaway.Side.EAST
	var west := ShellCutaway.Side.WEST
	var step := -_rig.key_rotate_speed / 60.0
	for frame in 300:
		if _rig.yaw > deg_to_rad(-45.0):
			_rig.rotate_yaw(maxf(step, deg_to_rad(-45.0) - _rig.yaw))
		await process_frame
		await RenderingServer.frame_post_draw
		_beat(label)
		var level: float = _view.cutaway.side_levels[east]
		if next < marks.size() and level <= marks[next]:
			var name := (
				"%s_%d_yaw_%03d_east_%03d_west_%03d"
				% [
					label,
					shots.size(),
					roundi(rad_to_deg(_rig.yaw)),
					roundi(level * 100.0),
					roundi(_view.cutaway.side_levels[west] * 100.0)
				]
			)
			shots.append([root.get_texture().get_image(), name])
			_log_state(name)
			_prove(name, "interior_frame")
			next += 1
		if next >= marks.size():
			break
	if next < marks.size():
		_invalid("%s: reached %d of %d marks" % [label, next, marks.size()])
	_strips.append(_save_shots(shots))


## The roof forced to level 0.5 at 45 m, where the outline is thickest, to
## show the surface and the outline dithering together.
func _forced_level_plate() -> void:
	var label := "forced_roof_050_at_45m"
	_beat(label)
	await _place(CENTRE + Vector3(0.0, 0.0, -4.0), 25.0, 45.0)
	_view.set_process(false)
	_view.cutaway.roof_level = 0.5
	_view.apply()
	await _frames(6)
	await _rebuild_occluders()
	var shadow_off := _view.roof_nodes.all(
		func(mi: MeshInstance3D) -> bool:
			return mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	print("FORCED roof_cast_shadow_off=%s" % shadow_off)
	var upper := _shell.find_child("Upper", true, false) as MeshInstance3D
	var mat := upper.get_surface_override_material(0) as ShaderMaterial
	print(
		(
			"FORCED %s surface_dissolve=%s outline_dissolve=%s upper_visible=%s"
			% [
				label,
				mat.get_shader_parameter("dissolve"),
				mat.next_pass.get_shader_parameter("dissolve"),
				upper.visible
			]
		)
	)
	var points := _roof_points()
	var framed := _framed(points)
	print("FORCED roof_points=%d framed=%d" % [points.size(), framed.size()])
	if framed.size() < 4:
		_invalid("%s: only %d roof points in frame" % [label, framed.size()])
	var inv := _cam.global_transform.affine_inverse()
	var lo := INF
	var hi := -INF
	for p in framed:
		var depth: float = -(inv * (p as Vector3)).z
		lo = minf(lo, depth)
		hi = maxf(hi, depth)
	print(
		(
			"DEPTH %s view_depth=%.1f..%.1f m outline_px=%.2f..%.2f"
			% [label, lo, hi, _outline_width(hi), _outline_width(lo)]
		)
	)
	var ok := _in_frame(label, framed)
	ok = _rays_hit(label, framed, ROOF_NAMES, 0.5) and ok
	var img := await _grab_now()
	if ok:
		_keep(img, label + ".png")
		var c := Vector2i(img.get_width() / 2, img.get_height() / 2)
		var crop := img.get_region(Rect2i(c - Vector2i(160, 90), Vector2i(320, 180)))
		crop.resize(960, 540, Image.INTERPOLATE_NEAREST)
		_keep(crop, label + "_crop_x3.png")
	_view.set_process(true)


## The diagonal with the roof gate on and off, at 220 m and at 130 m and 105 m
## approached from 220 m (so the roof is still drawn): evidence for the gate
## ruling. Only the gate changes within a pair.
func _gate_pairs() -> void:
	for d in [220.0, 130.0, 105.0]:
		await _place(CENTRE, 45.0, 220.0)
		await _place(CENTRE, 45.0, d)
		for gate in [true, false]:
			var label := "gate_%s_diag_%dm" % ["on" if gate else "off", int(d)]
			_beat(label)
			_view.cutaway.cut_only_without_roof = gate
			await _frames(4)
			await _rebuild_occluders()
			var ok := _prove(label, "building")
			if _view.cutaway.roof_level != 0.0:
				_invalid("%s: roof not drawn (level %.2f)" % [label, _view.cutaway.roof_level])
				ok = false
			var img := await _grab_now()
			_log_state(label)
			if ok:
				_keep(img, label + ".png")
		_view.cutaway.cut_only_without_roof = true
	await _frames(3)


## Facade_S_10 hidden (as a later permanent removal would) through a cut
## cycle: shown before, hidden at h180, cut at h0, and back at h180.
func _removed_bay_plates() -> void:
	var bay := _shell.find_child("Facade_S_10", true, false) as MeshInstance3D
	var steps := [
		["removed_bay_0_present_h180", 180.0, true],
		["removed_bay_1_hidden_h180", 180.0, false],
		["removed_bay_2_hidden_h0_cut", 0.0, false],
		["removed_bay_3_hidden_h180_back", 180.0, false],
	]
	for s in steps:
		var label: String = s[0]
		_beat(label)
		# Hidden once, before the first hidden step; never written again, so a
		# bay that came back would show.
		if label == "removed_bay_1_hidden_h180":
			bay.visible = false
		await _place(Vector3(-3.0, 0.0, 6.0), s[1], 40.0)
		var box := _box_of([bay])
		var ok := _in_frame(label, _corners(box))
		print("BAY %s visible=%s box_top_y=%.2f" % [label, bay.visible, box.end.y])
		if bay.visible != s[2]:
			_invalid("%s: bay visible=%s, wanted %s" % [label, bay.visible, s[2]])
			ok = false
		var img := await _grab_now()
		if ok:
			_keep(img, label + ".png")
	bay.visible = true


## Moves the rig with no easing and waits until every cutaway level has
## reached its target.
func _place(focus_local: Vector3, yaw_deg: float, d: float) -> void:
	_rig.stop_follow()
	_rig.position = _shell.global_transform * focus_local * Vector3(1.0, 0.0, 1.0)
	_rig.position.y = 0.0
	_rig.yaw = deg_to_rad(yaw_deg)
	_rig.distance = d
	_rig.zoom(1.0)
	for i in SETTLE_MAX_FRAMES:
		await process_frame
		_beat(_stage)
		if _settled() and i > 4:
			break
	await RenderingServer.frame_post_draw
	if not _settled():
		_invalid("cutaway did not settle at yaw %.0f distance %.0f" % [yaw_deg, d])
	await _rebuild_occluders()


func _settled() -> bool:
	var c := _view.cutaway
	if c.roof_level != c.roof_target:
		return false
	for side in 4:
		if c.side_levels[side] != c.side_target(side):
			return false
	return true


## Bakes one static body per drawn shell mesh from its faces at their current
## world positions (so squashed pieces block as squashed), glass surfaces left
## out. Hidden meshes (the gone roof, a removed bay) get none.
func _rebuild_occluders() -> void:
	if _occluders != null:
		_occluders.free()
	_occluders = Node3D.new()
	_occluders.name = "ProbeOccluders"
	root.add_child(_occluders)
	var bodies := 0
	for node in _shell.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.is_visible_in_tree():
			continue
		var faces := PackedVector3Array()
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			if mat != null and mat.resource_path == GLASS:
				continue
			var arrays := mi.mesh.surface_get_arrays(i)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if index.is_empty():
				for v in verts:
					faces.append(mi.global_transform * v)
			else:
				for k in index:
					faces.append(mi.global_transform * verts[k])
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var shape_node := CollisionShape3D.new()
		shape_node.shape = shape
		var body := StaticBody3D.new()
		body.set_meta("piece", _piece_name(mi))
		body.add_child(shape_node)
		_occluders.add_child(body)
		bodies += 1
	await physics_frame
	await physics_frame
	print("OCCLUDERS bodies=%d" % bodies)


## In-frame and visibility proof for a subject; prints what it compared.
## `subject` names the points that must be in frame and, for most, the floor
## points the camera must see.
func _prove(label: String, subject: String) -> bool:
	var framed: Array = []
	var floor_points: Array = []
	match subject:
		"building", "building_frame":
			framed = _corners(_building_box())
		"interior_frame":
			framed = _interior_points()
		"interior":
			framed = _interior_points()
			floor_points = framed
		"south":
			framed = _corners(
				_named_box(["Facade_S_09", "Facade_S_10", "Facade_S_11", "Facade_S_12"])
			)
			floor_points = [_world(Vector3(-5.0, 0.3, 11.0)), _world(Vector3(0.0, 0.3, 11.0))]
		"door6", "door3":
			# The visible jambs, both of them, not the hidden door and porch.
			var doorway := _view.doorways[(6 if subject == "door6" else 3) - 1]
			for jamb in doorway.jambs:
				framed.append_array(_corners(_box_of(jamb.find_children("*", "MeshInstance3D"))))
			var inside := _doorway_point(doorway, 0.0, -1.5, ShellCutaway.FLOOR_Y)
			floor_points = [inside]
		"corner_se":
			framed = _corners(_named_box(["Facade_E_12", "Facade_S_22"]))
		"corner_nw":
			framed = _corners(_named_box(["Facade_W_01", "Facade_N_01"]))
		_:
			_invalid("unknown subject %s" % subject)
			return false
	var ok := _in_frame(label, framed)
	if not floor_points.is_empty():
		ok = _rays_hit(label, floor_points, ["Lot"], 0.5) and ok
	if subject == "building" and _view.cutaway.roof_level == 0.0:
		ok = _rays_hit(label, _roof_points(), ROOF_NAMES, 0.5) and ok
		# Control: with the roof drawn the interior floor is not seen.
		var reached := _count_hits(_interior_points(), ["Lot"], 0.5)
		print("CONTROL %s interior_rays_reaching_floor=%d (roof drawn)" % [label, reached])
		if reached > 0:
			_invalid("%s: rays reach the floor through a drawn roof" % label)
			ok = false
	return ok


func _named_box(names: Array) -> AABB:
	var parts: Array = []
	for n in names:
		parts.append(_shell.find_child(n, true, false))
	return _box_of(parts)


func _in_frame(label: String, points: Array) -> bool:
	var size := root.get_visible_rect().size
	var rect := Rect2(Vector2(MARGIN_PX, MARGIN_PX), size - Vector2(MARGIN_PX, MARGIN_PX) * 2.0)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var behind := false
	for p in points:
		behind = behind or _cam.is_position_behind(p)
		var s := _cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := not behind and rect.has_point(lo) and rect.has_point(hi)
	print(
		(
			"INFRAME %s points=%d screen=(%.0f,%.0f)-(%.0f,%.0f) size_px=(%.0f,%.0f) ok=%s"
			% [label, points.size(), lo.x, lo.y, hi.x, hi.y, hi.x - lo.x, hi.y - lo.y, ok]
		)
	)
	if not ok:
		_invalid("%s: subject leaves the frame" % label)
	return ok


## At least half the rays from the camera to `points` must first hit one of
## `names` within `tolerance` of the point.
func _rays_hit(label: String, points: Array, names: Array, tolerance: float) -> bool:
	var hits := _count_hits(points, names, tolerance)
	var ok := hits > 0 and hits * 2 >= points.size()
	print("VISIBLE %s %s ray_hits=%d/%d ok=%s" % [label, "/".join(names), hits, points.size(), ok])
	if not ok:
		_invalid("%s: %s occluded or not hit" % [label, "/".join(names)])
	return ok


func _count_hits(points: Array, names: Array, tolerance: float) -> int:
	var space := _cam.get_world_3d().direct_space_state
	var hits := 0
	for p in points:
		var from := _cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, p + (p - from).normalized() * 0.3)
		var hit := space.intersect_ray(q)
		if hit and hit.position.distance_to(p) < tolerance:
			var owner_name := String((hit.collider as Node).get_meta("piece", ""))
			if owner_name in names:
				hits += 1
	return hits


## Interior floor points: a 3x3 grid over the middle of the footprint.
func _interior_points() -> Array:
	var out: Array = []
	for x in [-24.0, 0.0, 24.0]:
		for z in [-9.0, 0.0, 9.0]:
			out.append(_world(Vector3(x, 0.3, z)))
	return out


## Roof points: vertical rays over a 7x7 grid onto the Upper and Canopy
## colliders.
func _roof_points() -> Array:
	var space := _cam.get_world_3d().direct_space_state
	var box := _building_box()
	var out: Array = []
	for i in 7:
		for j in 7:
			var x := lerpf(box.position.x, box.end.x, 0.1 + 0.8 * i / 6.0)
			var z := lerpf(box.position.z, box.end.z, 0.1 + 0.8 * j / 6.0)
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(x, box.end.y + 5.0, z), Vector3(x, 6.0, z)
			)
			var hit := space.intersect_ray(q)
			if hit:
				out.append(hit.position)
	return out


func _framed(points: Array) -> Array:
	var size := root.get_visible_rect().size
	var rect := Rect2(Vector2(MARGIN_PX, MARGIN_PX), size - Vector2(MARGIN_PX, MARGIN_PX) * 2.0)
	return points.filter(
		func(p: Vector3) -> bool:
			return not _cam.is_position_behind(p) and rect.has_point(_cam.unproject_position(p))
	)


## Mirrors width_at() in toon_outline_common.gdshaderinc with its defaults.
func _outline_width(depth: float) -> float:
	var d := maxf(depth, 60.0)
	var t := clampf(log(d / 60.0) / log(240.0 / 60.0), 0.0, 1.0)
	return 1.5 * (1.0 - smoothstep(0.0, 1.0, t))


func _building_box() -> AABB:
	var parts: Array = [_shell.find_child("Upper", true, false)]
	parts.append_array(_shell.find_children("Facade_*", "MeshInstance3D", true, false))
	return _box_of(parts)


func _box_of(parts: Array) -> AABB:
	var box := AABB()
	var first := true
	for part in parts:
		var mi := part as MeshInstance3D
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _corners(box: AABB) -> Array:
	var out: Array = []
	for i in 8:
		out.append(box.get_endpoint(i))
	return out


func _local(node: Node3D) -> Vector3:
	return _shell.global_transform.affine_inverse() * node.global_position


func _world(local: Vector3) -> Vector3:
	return _shell.global_transform * local


func _log_state(label: String) -> void:
	var c := _view.cutaway
	print(
		(
			"CAMERA %s focus=%s yaw_deg=%.1f distance=%.1f pitch_deg=%.1f cam_pos=%s"
			% [
				label,
				_rig.position,
				rad_to_deg(_rig.yaw),
				_rig.distance,
				-_cam.rotation_degrees.x,
				_cam.global_position
			]
		)
	)
	print(
		(
			"CUT %s roof_level=%.2f roof_target=%.0f sides(N,S,E,W)=%s cuts=%s gate=%s"
			% [
				label,
				c.roof_level,
				c.roof_target,
				c.side_levels.map(func(v: float) -> String: return "%.2f" % v),
				[0, 1, 2, 3].map(func(s: int) -> String: return "%.2f" % c.cut(s)),
				c.cut_only_without_roof
			]
		)
	)


func _grab_now() -> Image:
	await _frames(2)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Saves `img` and keeps a tile of it for a contact sheet. Returns the tile.
func _keep(img: Image, file: String, to_plates := true) -> Image:
	_save(img, file)
	var tile := img.duplicate() as Image
	tile.resize(TILE.x, TILE.y, Image.INTERPOLATE_BILINEAR)
	if to_plates:
		_plates.append(tile)
		print("TILE plates[%d] %s" % [_plates.size() - 1, file])
	return tile


func _sheet(tiles: Array[Image], file: String, per_row: int) -> void:
	if tiles.is_empty():
		_invalid("no tiles for %s" % file)
		return
	var rows := ceili(float(tiles.size()) / per_row)
	var sheet := Image.create(
		per_row * (TILE.x + 6), rows * (TILE.y + 6), false, Image.FORMAT_RGBA8
	)
	sheet.fill(Color.WHITE)
	for i in tiles.size():
		var at := Vector2i((i % per_row) * (TILE.x + 6), (i / per_row) * (TILE.y + 6))
		sheet.blit_rect(tiles[i], Rect2i(Vector2i.ZERO, TILE), at)
	_save(sheet, file)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
		_beat(_stage)
	await RenderingServer.frame_post_draw


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
			OS.crash("shell_dissolve_plates_probe: main thread stalled in %s" % stage)
