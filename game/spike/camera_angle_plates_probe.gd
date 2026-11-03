extends SceneTree
## Windowed plate probe for the three camera angle steps at the home zoom
## (board 64cd3243, decision camera-angle-is-a-player-setting-fixed-while-zooming).
##
## Run (one windowed Godot run project-wide):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path <game> -s res://spike/camera_angle_plates_probe.gd
##
## Boots main.tscn with the clock stopped. For each angle step (low, medium,
## top-down) it sets the step on the rig directly (so the player's saved
## setting is not touched), returns Home, and saves a plate under
## tools/blender/out/camera-angle/. Each plate prints the step, pitch, distance
## and focus, proves the focus point is inside the viewport with a margin and
## that the camera tilt is the step's pitch. Occlusion is not asserted (the
## world has no colliders here): open every plate and look.
## A fourth plate zooms to the farthest distance on the low step, the view that
## shows most sky. Any failed proof prints PROBE_INVALID and the probe
## exits 1.

const OUT_REL := "res://../tools/blender/out/camera-angle"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 24.0
const FRAME_LIMIT := 4000
const STEP_NAMES := ["low", "medium", "top_down"]

var _failed := false
var _main: Node3D
var _rig: TycoonCamera
var _cam: Camera3D
var _out_dir := ""
var _frames_seen := 0


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_frames_seen += 1
	if _frames_seen > FRAME_LIMIT:
		_invalid("frame budget spent before the plates were done")
		return true
	return false


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate()
	var clock: SimClock = _main.get_node("SimClock")
	var world_seed := randi()
	clock.seed_rng(world_seed)
	print("PROBE seed=", world_seed)
	root.add_child(_main)
	# Processing turns on when the clock becomes ready; only this probe steps it.
	clock.set_process(false)
	_rig = _main.get_node("TycoonCamera")
	_cam = _main.get_node("TycoonCamera/Camera3D")
	await _frames(20)
	for step in 3:
		await _plate(step, STEP_NAMES[step], false)
	await _plate(TycoonCamera.AngleStep.LOW, "low_farthest", true)
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _plate(step: int, name: String, farthest: bool) -> void:
	_rig.angle_step = step as TycoonCamera.AngleStep
	_rig.go_home()
	for i in 240:
		await process_frame
		if not _rig.is_gliding():
			break
	if farthest:
		_rig.distance = _rig.max_distance
	await _frames(6)
	var focus := Vector3(_rig.position.x, 0.0, _rig.position.z)
	var at := _cam.unproject_position(focus)
	var size := root.get_visible_rect().size
	var in_frame := (
		at.x > MARGIN_PX
		and at.y > MARGIN_PX
		and at.x < size.x - MARGIN_PX
		and at.y < size.y - MARGIN_PX
	)
	var tilt := rad_to_deg(-_cam.rotation.x)
	print(
		(
			"PROBE %s step=%d pitch=%.2f tilt=%.2f distance=%.1f focus=%s screen=%s viewport=%s"
			% [name, step, _rig.pitch_degrees(), tilt, _rig.distance, focus, at, size]
		)
	)
	if not in_frame:
		_invalid("%s: the focus point is outside the viewport margin" % name)
	if not is_equal_approx(tilt, TycoonCamera.STEP_PITCH_DEGREES[step]):
		_invalid("%s: the camera tilt is not the step's pitch" % name)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join("angle_%s.png" % name)
	img.save_png(path)
	print("PROBE plate ", path)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true
