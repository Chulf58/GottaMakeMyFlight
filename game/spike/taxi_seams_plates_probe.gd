extends SceneTree
## Windowed plate probe for the taxi paving seams (board 1d61370e).
##
## Run (one windowed Godot run project-wide; hold the shared windowed lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path <game> -s res://spike/taxi_seams_plates_probe.gd -- --out=<dir> \
##     [--two-gate-19 [--unequal]]
##
## Boots main.tscn with the starter shell and its gate desk, hides the HUD layers and
## shoots: a top-down plate of every paving strip and pad, a distance shot from the
## tycoon camera's side, and a top-down close-up of every seam. A seam is each end of
## every north-south strip: where it meets the taxi lane's edge, where it runs under
## the runway, and where it crosses its stand pad's north edge, unless the site's
## paving covers it (south of PAVING_EDGE_Z). Each seam prints the
## pieces on both sides (a ray hit 3 m each way across it) and the plate's pixel
## luminance there, so a step can be named. Every plate proves its seam points are in
## frame and hit on the paving first; otherwise PROBE_INVALID and exit 1.

const OUT_REL := "res://../tools/blender/out/taxi-seams"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const CLOSE_VIEW_M := 46.0
## How far either side of a seam the pieces and pixels are read.
const SIDE_M := 3.0
## How far east of the seam's middle (the link's centre line) they are read.
const OFF_LINE_M := 4.0
const DISTANCE_OFFSET := Vector3(150.0, 170.0, 200.0)
## The site paving's north edge: it lies over the strips and pads south of here.
const PAVING_EDGE_Z := -210.0

var _out_dir := ""
## --two-gate-19: gates A and B with stands 19 m apart, the closest two gates may
## be (test_gate_envelopes.gd), set on Airside directly instead of the gate desk.
var _two_gate_19 := false
## --unequal (with --two-gate-19): gate A on a wall line 105 m further north, so
## its link is the shorter of the two.
var _unequal := false
var _failed := false
var _main: Node3D
var _cam: Camera3D


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1)
		elif arg == "--two-gate-19":
			_two_gate_19 = true
		elif arg == "--unequal":
			_unequal = true
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_run.call_deferred()


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate()
	var clock: SimClock = _main.get_node("SimClock")
	var world_seed := randi()
	clock.seed_rng(world_seed)
	print("PROBE world_seed=%d" % world_seed)
	root.add_child(_main)
	clock.set_process(false)
	await _frames(10)
	var grid := (_main.get_node("BuildMode") as BuildMode).grid
	if _two_gate_19:
		var stands := {
			"A": {"exit": 2, "x": -22.5, "wall_z": -203.0 if _unequal else -98.0},
			"B": {"exit": 3, "x": -3.5, "wall_z": -98.0},
		}
		if not (_main.get_node("Airside") as Airside).set_gate_stands(stands):
			_invalid("the two gates 19 m apart were refused")
	elif not preload("res://spike/starter_flight.gd").add_gate_desk(grid):
		_invalid("the gate desk was refused")
	await _frames(6)
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var airside := _main.get_node("Airside") as Airside
	var paving := airside.paving
	for mi in airside.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh != null and (mi as MeshInstance3D).is_visible_in_tree():
			(mi as MeshInstance3D).create_trimesh_collision()
	await physics_frame
	await physics_frame
	for strip in paving.shown:
		print("STRIP rect=%s across_x=%s" % [strip["rect"], strip["across_x"]])
	for pad in paving.pads:
		print("PAD rect=%s" % pad)
	_cam = Camera3D.new()
	_cam.far = 3000.0
	_main.add_child(_cam)
	_cam.make_current()
	var seams := _seams(paving, Airside.runway_south())
	var all_marks: Array[Vector3] = []
	for strip in paving.shown:
		var rect: Rect2 = strip["rect"]
		all_marks.append(Vector3(rect.position.x, 0.0, rect.position.y))
		all_marks.append(Vector3(rect.end.x, 0.0, rect.end.y))
	await _top("taxi_top", _bounds(all_marks), all_marks, seams)
	await _distance(all_marks, seams)
	for i in seams.size():
		var seam: Dictionary = seams[i]
		var at: Vector3 = seam["at"]
		var view := Rect2(
			at.x - CLOSE_VIEW_M / 2.0, at.z - CLOSE_VIEW_M / 2.0, CLOSE_VIEW_M, CLOSE_VIEW_M
		)
		await _top("seam_%02d_%s" % [i, seam["kind"]], view, [at], [seam])
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


## Each end of every north-south strip, as {"at": the seam's middle on the paving,
## "kind", "across": the unit step across the seam (from the strip outwards)}.
func _seams(paving: TaxiPaving, runway_south: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lane_z := StandPlacement.TAXI_LANE_Z
	var half := TaxiPaving.WIDTH_M / 2.0
	for strip in paving.shown:
		if not strip["across_x"] or strip.has("quad"):
			continue
		var rect: Rect2 = strip["rect"]
		var x := rect.get_center().x
		for z: float in [rect.position.y, rect.end.y]:
			var outward := -1.0 if is_equal_approx(z, rect.position.y) else 1.0
			var kind := "end"
			var seam_z := z
			if absf(z - (lane_z - half)) < 0.05 or absf(z - (lane_z + half)) < 0.05:
				kind = "lane"
			elif z < runway_south:
				kind = "runway"
				seam_z = runway_south
				outward = -1.0
			if seam_z > PAVING_EDGE_Z:
				print("SEAM skipped %s at z %.1f: under the site paving" % [kind, seam_z])
				continue
			out.append({"at": Vector3(x, 0.0, seam_z), "kind": kind, "across": outward})
		for pad in paving.pads:
			if pad.position.y > rect.position.y and pad.position.y < rect.end.y:
				if x >= pad.position.x and x <= pad.end.x and pad.position.y < PAVING_EDGE_Z:
					out.append(
						{"at": Vector3(x, 0.0, pad.position.y), "kind": "pad", "across": -1.0}
					)
		# Where two links overlap (closer than a strip is wide), the cut at their
		# midpoint, read across x halfway along the overlap north of the site paving.
		for other in paving.shown:
			var them: Rect2 = other["rect"]
			if not other["across_x"] or them.get_center().x <= x or not rect.intersects(them):
				continue
			var top := maxf(rect.position.y, them.position.y)
			var bottom := minf(minf(rect.end.y, them.end.y), PAVING_EDGE_Z)
			if bottom > top:
				var cut := Vector3((x + them.get_center().x) / 2.0, 0.0, (top + bottom) / 2.0)
				out.append({"at": cut, "kind": "cut", "across": 1.0, "along_x": true})
	return out


func _bounds(points: Array[Vector3]) -> Rect2:
	var rect := Rect2(Vector2(points[0].x, points[0].z), Vector2.ZERO)
	for p in points:
		rect = rect.expand(Vector2(p.x, p.z))
	return rect.grow(10.0)


func _top(label: String, view: Rect2, marks: Array[Vector3], seams: Array[Dictionary]) -> void:
	var aspect := root.get_visible_rect().size.aspect()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.size = maxf(view.size.y, view.size.x / aspect)
	var centre := view.get_center()
	_cam.look_at_from_position(
		Vector3(centre.x, 500.0, centre.y), Vector3(centre.x, 0.0, centre.y), Vector3.FORWARD
	)
	await _shoot(label, marks, seams)


func _distance(marks: Array[Vector3], seams: Array[Dictionary]) -> void:
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 45.0
	var box := _bounds(marks)
	var at := Vector3(box.get_center().x, 0.0, box.get_center().y)
	_cam.look_at_from_position(at + DISTANCE_OFFSET, at, Vector3.UP)
	await _shoot("taxi_distance", marks, seams)


func _shoot(label: String, marks: Array[Vector3], seams: Array[Dictionary]) -> void:
	await _frames(4)
	var frame := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	for p in marks:
		var s := _cam.unproject_position(p)
		if _cam.is_position_behind(p) or not frame.has_point(s):
			_invalid("%s: mark %s at %s is out of frame" % [label, p, s])
			return
	print("INFRAME %s marks=%d ok=true" % [label, marks.size()])
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var space := _cam.get_world_3d().direct_space_state
	# unproject_position() gives the viewport's logical size; the image is the
	# window's pixels, larger by the display scale.
	var to_px := Vector2(img.get_size()) / root.get_visible_rect().size
	for seam in seams:
		# Read off the yellow centre line, which runs along the link's middle.
		var at: Vector3 = seam["at"] + Vector3(OFF_LINE_M, 0.0, 0.0)
		var step := Vector3(0.0, 0.0, SIDE_M * float(seam["across"]))
		if seam.get("along_x", false):
			at = seam["at"]
			step = Vector3(SIDE_M, 0.0, 0.0)
		var line := "SEAM %s %s at=(%.1f,%.1f)" % [label, seam["kind"], at.x, at.z]
		for side: Array in [["in", at - step], ["out", at + step]]:
			var p: Vector3 = side[1]
			var s := _cam.unproject_position(p)
			if not frame.has_point(s):
				line += " %s=offscreen" % side[0]
				continue
			var q := PhysicsRayQueryParameters3D.create(
				_cam.project_ray_origin(s), p + _cam.project_ray_normal(s) * 0.5
			)
			var hit := space.intersect_ray(q)
			var owner := "none"
			if hit:
				owner = str((hit["collider"] as Node).get_parent().name)
			var px := Vector2i(s * to_px)
			var lum := img.get_pixelv(px).get_luminance()
			line += " %s=%s px=(%d,%d) lum=%.3f" % [side[0], owner, px.x, px.y, lum]
			if side[0] == "in" and owner != "TaxiPaving":
				_invalid(
					"%s: the strip side of a %s seam is hit on %s" % [label, seam["kind"], owner]
				)
		print(line)
	var path := _out_dir.path_join(label + ".png")
	if img.save_png(path) != OK:
		_invalid("could not save " + path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw
