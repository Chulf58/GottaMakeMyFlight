extends SceneTree
## Windowed plate probe for the runway upgrade (Runway R9, board 48f9bf52): the
## drawn runway of a new game, then the runway after bought works have run.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path <worktree>/game -s res://tests/airside/runway_works_plates_probe.gd \
##     -- --out=<dir>
##
## The scene boots with a new random world seed (printed). The airport is opened
## directly, the unlock tier is set, RunwayWorks.buy() books the works and the
## clock is stepped by hand until the runway changes size. Both plates use the
## same top-down camera over the runway line. Each proves the drawn runway's
## end points are inside the viewport with a margin and that the pieces drawn
## are the size's (RunwayView), printing the numbers it compared; failures print
## PROBE_INVALID and exit 1. The HUD layers are hidden for the plates, so no
## panel covers the subject. In frame is not visible: a ray from the camera to
## each checked point must meet no collider and no other mesh first (_occluder),
## and a plate that fails to write is invalid. Plates go to
## tools/blender/out/runway_r9/.

const OUT_REL := "res://../tools/blender/out/runway_r9"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 24.0
const CAMERA_HEIGHT := 600.0
## The view's width in metres, set so the large runway (768 m) fits with room.
const VIEW_WIDTH_M := 900.0
const RUNWAY_Z := -338.0
## The checked points sit this far above the ground so the ground itself is not
## an occluder.
const POINT_HEIGHT_M := 0.5

var _out_dir := ""
var _main: Node3D
var _clock: SimClock
var _flights: FlightSim
var _cam: Camera3D
var _failed := false


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var world_seed := randi()
	_clock.seed_rng(world_seed)
	print("PROBE world_seed=%d out_dir=%s" % [world_seed, _out_dir])
	_clock.set_process(false)
	root.add_child(_main)
	_clock.set_process(false)
	_flights = _main.get_node("FlightSim")
	for child in _main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.size = VIEW_WIDTH_M
	_cam.far = 2000.0
	_main.add_child(_cam)
	_cam.global_position = Vector3(0.0, CAMERA_HEIGHT, RUNWAY_Z)
	_cam.look_at(Vector3(0.0, 0.0, RUNWAY_Z), Vector3(0.0, 0.0, -1.0))
	_cam.make_current()
	await _frames(10)
	_control_occluder()
	await _plate("small", PlaneClasses.SMALL)
	_flights.open_airport()
	(_main.get_node("BuildUnlocks") as BuildUnlocks).from_snapshot(
		{"tier": 2, "made": 50, "shown": [], "seen": []}
	)
	var wallet: Wallet = (_main.get_node("Finances") as Finances).wallet
	var refusal := RunwayWorks.buy(_flights, _main.get_node("BuildUnlocks"), wallet)
	if refusal != "":
		_invalid("buy refused: %s" % refusal)
	else:
		var works := _flights.runway.works
		print("PROBE works %s from tick %d to %d" % [works.target, works.start, works.finish])
		var steps := 0
		while _flights.runway.size == PlaneClasses.SMALL and steps < 5000:
			_step()
			steps += 1
		print("PROBE stepped %d ticks, runway now %s" % [steps, _flights.runway.size])
		await _frames(6)
		await _plate("medium", PlaneClasses.MEDIUM)
	quit(1 if _failed else 0)


func _step() -> void:
	_clock.set_paused(false)
	_clock.advance(SimClock.STEP)
	_clock.set_paused(true)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _plate(label: String, size: String) -> void:
	var view := _main.get_node("Airside/RunwayView") as RunwayView
	if view.shown_size() != size:
		_invalid("the view shows %s, expected %s" % [view.shown_size(), size])
		return
	var pieces := view.get_child(0).get_child_count()
	if pieces != Runway.pieces(size).size():
		_invalid("%d pieces drawn for %s" % [pieces, size])
		return
	var half := Runway.length_m(size) / 2.0
	var viewport := root.get_viewport().get_visible_rect().size
	for x in [-half, half]:
		var at := _cam.unproject_position(Vector3(x, 0.0, RUNWAY_Z))
		print("PROBE %s end x=%.0f -> screen (%.1f, %.1f) of %s" % [label, x, at.x, at.y, viewport])
		if (
			at.x < MARGIN_PX
			or at.y < MARGIN_PX
			or at.x > viewport.x - MARGIN_PX
			or at.y > viewport.y - MARGIN_PX
		):
			_invalid("%s runway end %.0f is outside the viewport" % [label, x])
			return
		var blocker := _occluder(Vector3(x, POINT_HEIGHT_M, RUNWAY_Z), view)
		print("PROBE %s end x=%.0f occluder: '%s'" % [label, x, blocker])
		if blocker != "":
			_invalid("%s runway end %.0f is hidden behind %s" % [label, x, blocker])
			return
	await _frames(4)
	await RenderingServer.frame_post_draw
	var path := "%s/runway_%s.png" % [_out_dir, label]
	var image := root.get_viewport().get_texture().get_image()
	var saved := image.save_png(path)
	print("PROBE plate %s: %d pieces, %s, save_png=%d" % [label, pieces, path, saved])
	if saved != OK or not FileAccess.file_exists(path):
		_invalid("the %s plate was not written to %s (error %d)" % [label, path, saved])


## Control: the occlusion check must see a box dropped between the camera and a
## runway point, so a clear result elsewhere means something.
func _control_occluder() -> void:
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	_main.add_child(box)
	box.global_position = Vector3(0.0, CAMERA_HEIGHT / 2.0, RUNWAY_Z)
	var found := _occluder(
		Vector3(0.0, POINT_HEIGHT_M, RUNWAY_Z), _main.get_node("Airside/RunwayView")
	)
	print("PROBE control occluder: '%s'" % found)
	if found == "":
		_invalid("the occlusion check missed a box between the camera and the runway")
	box.free()


## The name of whatever lies between the camera and `point`, or "": a collider
## the physics ray meets, or a mesh outside the runway view whose bounds the
## segment crosses.
func _occluder(point: Vector3, view: Node) -> String:
	var from := _cam.global_position
	var query := PhysicsRayQueryParameters3D.create(from, point)
	var hit := root.world_3d.direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return "collider %s" % hit["collider"]
	for node in _main.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree() or view.is_ancestor_of(mesh):
			continue
		var local := mesh.global_transform.affine_inverse()
		if mesh.mesh.get_aabb().intersects_segment(local * from, local * point):
			return "mesh %s" % mesh.get_path()
	return ""


func _invalid(why: String) -> void:
	print("PROBE_INVALID %s" % why)
	_failed = true
