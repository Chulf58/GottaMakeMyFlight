extends SceneTree
## Windowed plate probe for the spur paving (board airside-all-around-s4).
##
## Run (one windowed Godot run project-wide):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://tests/flights/tools/spur_paving_plates_probe.gd [-- --seed=N]
##
## Boots main.tscn with a new random world seed (printed), gives Airside a
## synthetic west gate (sill 0, -149.5) and east gate (sill 0, -129.5), hides
## the HUD layers and the airside props (side-stand bridges are slice S8), and
## shoots top-down plates of both spur corners (where the lane meets the stub
## and spur), both connector junctions, the whole layout, and a distance shot of
## each corner. Each plate projects its marks with unproject_position(), asserts
## each lies inside the viewport with a margin and prints the coordinates, then
## casts a ray at each and requires it to hit TaxiPaving first; otherwise
## PROBE_INVALID and exit 1. After each camera move it waits for the roof fade
## to end (anti_pattern 9a6c0290) before the sight test. At each corner it
## prints the plate's luminance along the spur's outer edge and centre line, so
## a step in the band there shows as numbers.

const OUT_REL := "res://../tools/blender/out/s4-paving"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const SETTLE_FRAMES := 6
const FADE_LIMIT_FRAMES := 600
const CORNER_VIEW_M := 90.0
const CONNECTOR_VIEW_M := 110.0
const DISTANCE_OFFSET := Vector3(70.0, 120.0, 110.0)

var _out_dir := ""
var _failed := false
var _main: Node3D
var _cam: Camera3D
var _airside: Airside


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_run.call_deferred()


func _run() -> void:
	var world_seed := randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			world_seed = int(arg.get_slice("=", 1))
	_main = load(MAIN_SCENE).instantiate()
	var clock: SimClock = _main.get_node("SimClock")
	clock.seed_rng(world_seed)
	print("PROBE world_seed=%d" % world_seed)
	root.add_child(_main)
	clock.set_process(false)
	await _frames(10)
	_airside = _main.get_node("Airside") as Airside
	var west := StandPlacement.make(0, 0.0, -149.5, StandPlacement.WEST)
	var east := StandPlacement.make(0, 0.0, -129.5, StandPlacement.EAST)
	_airside.set_gate_classes({"W": PlaneClasses.LARGE, "E": PlaneClasses.LARGE})
	if not _airside.set_gate_stands({"W": west, "E": east}):
		_invalid("the side gate stands were refused")
	await _frames(SETTLE_FRAMES)
	if not _airside.gate_stands.has("W") or not _airside.gate_stands.has("E"):
		_invalid("the side gate stands did not stay set: %s" % _airside.gate_stands)
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_airside.props.visible = false
	var paving := _airside.paving
	for strip in paving.shown:
		print("STRIP %s" % strip)
	for pad in paving.pads:
		print("PAD rect=%s" % pad)
	for hold in _airside.hold_points():
		print("HOLD at=%s" % hold)
	for mi in _main.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := mi as MeshInstance3D
		if mesh_node.mesh != null and mesh_node.is_visible_in_tree():
			mesh_node.create_trimesh_collision()
	await physics_frame
	await physics_frame
	_cam = Camera3D.new()
	_cam.far = 3000.0
	_main.add_child(_cam)
	_cam.make_current()
	var lane_z := StandPlacement.TAXI_LANE_Z
	var x := StandPlacement.SIDE_LANE_X
	for side: float in [-1.0, 1.0]:
		var name := "west" if side < 0.0 else "east"
		var corner := Vector3(side * x, 0.0, lane_z)
		var marks := _square_marks(corner, 11.0)
		marks.append(corner + Vector3(-side * 30.0, 0.0, 0.0))
		marks.append(corner + Vector3(0.0, 0.0, 30.0))
		await _top("spur_%s_corner_top" % name, _view(corner, CORNER_VIEW_M), marks, corner)
		await _distance("spur_%s_corner_distance" % name, corner, marks)
		var stand := west if side < 0.0 else east
		var join := StandPlacement.lane_join(stand)
		var near := _square_marks(join, 11.0)
		near.append(join + Vector3(-side * 40.0, 0.0, 0.0))
		near.append(join + Vector3(0.0, 0.0, -40.0))
		await _top("spur_%s_connector_top" % name, _view(join, CONNECTOR_VIEW_M), near, join)
	var everything: Array[Vector3] = []
	for strip in paving.shown:
		var rect: Rect2 = strip["rect"]
		everything.append(Vector3(rect.get_center().x, 0.0, rect.get_center().y))
	var box := Rect2(Vector2(everything[0].x, everything[0].z), Vector2.ZERO)
	for p in everything:
		box = box.expand(Vector2(p.x, p.z))
	var marks: Array[Vector3] = [
		Vector3(-x, 0.0, lane_z + 10.0), Vector3(x, 0.0, lane_z + 10.0), Vector3(0.0, 0.0, lane_z)
	]
	await _top("spur_layout_top", box.grow(40.0), marks, Vector3(0.0, 0.0, lane_z))
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


## Four points `d` metres from `at` along x and z, on the paving around it.
static func _square_marks(at: Vector3, d: float) -> Array[Vector3]:
	return [
		at + Vector3(d, 0.0, 0.0),
		at - Vector3(d, 0.0, 0.0),
		at + Vector3(0.0, 0.0, d),
		at - Vector3(0.0, 0.0, d),
		at,
	]


static func _view(at: Vector3, size: float) -> Rect2:
	return Rect2(at.x - size / 2.0, at.z - size / 2.0, size, size)


func _top(label: String, view: Rect2, marks: Array[Vector3], corner: Vector3) -> void:
	var aspect := root.get_visible_rect().size.aspect()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.size = maxf(view.size.y, view.size.x / aspect)
	var centre := view.get_center()
	_cam.look_at_from_position(
		Vector3(centre.x, 500.0, centre.y), Vector3(centre.x, 0.0, centre.y), Vector3.FORWARD
	)
	await _shoot(label, marks, corner)


func _distance(label: String, at: Vector3, marks: Array[Vector3]) -> void:
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 45.0
	var offset := DISTANCE_OFFSET
	offset.x *= signf(at.x)
	_cam.look_at_from_position(at + offset, at, Vector3.UP)
	await _shoot(label, marks, at)


func _shoot(label: String, marks: Array[Vector3], corner: Vector3) -> void:
	await _frames(SETTLE_FRAMES)
	var roof := _main.get_node_or_null("RoofView") as RoofView
	var fade := 0
	if roof != null:
		while roof.cutaway.roof_level != roof.cutaway.roof_target and fade < FADE_LIMIT_FRAMES:
			fade += 1
			await process_frame
		if roof.cutaway.roof_level != roof.cutaway.roof_target:
			_invalid("%s: the roof fade did not end in %d frames" % [label, FADE_LIMIT_FRAMES])
		await RenderingServer.frame_post_draw
	print("FADE %s waited=%d frames" % [label, fade])
	var frame := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var space := _cam.get_world_3d().direct_space_state
	for p in marks:
		var s := _cam.unproject_position(p)
		if _cam.is_position_behind(p) or not frame.has_point(s):
			_invalid("%s: mark %s at %s is out of frame %s" % [label, p, s, frame])
			return
		var q := PhysicsRayQueryParameters3D.create(
			_cam.project_ray_origin(s), p + _cam.project_ray_normal(s) * 0.5
		)
		var hit := space.intersect_ray(q)
		var owner := "none"
		if hit:
			owner = str((hit["collider"] as Node).get_parent().name)
		print("INFRAME %s mark=%s screen=(%.1f,%.1f) first_hit=%s" % [label, p, s.x, s.y, owner])
		if owner != "TaxiPaving":
			_invalid("%s: mark %s is hit on %s, not the paving" % [label, p, owner])
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var to_px := Vector2(img.get_size()) / root.get_visible_rect().size
	# The spur's outer edge (1 m inside it) and its centre line's side (3 m off
	# the yellow line), north to south through the corner.
	var outer_x := corner.x + signf(corner.x) * (TaxiPaving.WIDTH_M / 2.0 - 1.0)
	for row: Array in [["edge", outer_x], ["middle", corner.x + signf(corner.x) * 3.0]]:
		var line := "LUM %s %s x=%.1f:" % [label, row[0], row[1]]
		for dz in [-24.0, -12.0, -6.0, 0.0, 6.0, 12.0, 24.0]:
			var p := Vector3(row[1], 0.0, corner.z + dz)
			var s := _cam.unproject_position(p)
			if not frame.has_point(s) or _cam.is_position_behind(p):
				line += " %+.0f=off" % dz
				continue
			line += " %+.0f=%.3f" % [dz, img.get_pixelv(Vector2i(s * to_px)).get_luminance()]
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
