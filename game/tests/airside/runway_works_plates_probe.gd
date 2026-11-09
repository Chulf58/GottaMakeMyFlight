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
## panel covers the subject. Plates go to tools/blender/out/runway_r9/.

const OUT_REL := "res://../tools/blender/out/runway_r9"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 24.0
const CAMERA_HEIGHT := 600.0
## The view's width in metres, set so the large runway (768 m) fits with room.
const VIEW_WIDTH_M := 900.0
const RUNWAY_Z := -338.0

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
	await _plate("small", PlaneClasses.SMALL)
	_flights.open_airport()
	(_main.get_node("BuildUnlocks") as BuildUnlocks).from_snapshot({"tier": 2, "made": 50})
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
	await _frames(4)
	await RenderingServer.frame_post_draw
	var path := "%s/runway_%s.png" % [_out_dir, label]
	var image := root.get_viewport().get_texture().get_image()
	print("PROBE plate %s: %d pieces, %s, saved=%d" % [label, pieces, path, image.save_png(path)])


func _invalid(why: String) -> void:
	print("PROBE_INVALID %s" % why)
	_failed = true
