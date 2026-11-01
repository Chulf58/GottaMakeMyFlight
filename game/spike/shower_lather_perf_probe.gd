extends SceneTree
## Windowed frame time of the shower lather (ShowerFoam; board item bfe19c1e):
## four shower cubicles in a row, a passenger standing in each playing the
## washing clip, and 0, 1 or 4 of them showering (bare under a full lather
## with its steam). The real TycoonCamera looks at the row from its home zoom
## (80 m) and from its closest (6 m). Vsync is off. For each case it waits
## WARM frames, then over FRAMES frames prints the mean wall time per frame
## and the main viewport's measured GPU and CPU render times.
## Prints PERF lather=<bubbles> zoom=<m> showering=<n> wall_ms= gpu_ms= cpu_ms=
## for each case, and runs the whole set ROUNDS times to show the noise.
## Compare runs on two versions of shower_foam.gd by swapping the file.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/shower_lather_perf_probe.gd

const CAMERA := preload("res://camera/tycoon_camera.tscn")
const WARM := 60
const FRAMES := 240
const ROUNDS := 2
const ZOOMS: Array[float] = [80.0, 6.0]
const SHOWERING: Array[int] = [0, 1, 4]
## Bodies in the four cubicles: two males, two females.
const BODIES: Array[int] = [0, 6, 1, 7]
const TRAY_M := 0.10

var _people: Array[Node3D] = []
var _cam: TycoonCamera


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	_build()
	print("PROBE lather=%d size=%s" % [ShowerFoam.lather_count(), root.size])
	for round_i in ROUNDS:
		for zoom in ZOOMS:
			_cam.distance = zoom
			_cam.target_distance = zoom
			for n in SHOWERING:
				_shower(n)
				for i in WARM:
					await process_frame
				var wall := 0.0
				var gpu := 0.0
				var cpu := 0.0
				var last := Time.get_ticks_usec()
				for i in FRAMES:
					await process_frame
					var now := Time.get_ticks_usec()
					wall += (now - last) / 1000.0
					last = now
					gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
					cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
				print(
					(
						"PERF lather=%d round=%d zoom=%.0f showering=%d wall_ms=%.3f gpu_ms=%.3f cpu_ms=%.3f"
						% [
							ShowerFoam.lather_count(),
							round_i,
							zoom,
							n,
							wall / FRAMES,
							gpu / FRAMES,
							cpu / FRAMES
						]
					)
				)
	print("PROBE done")
	quit(0)


## Floor, sun, sky, the four cubicles and their people, and the camera.
func _build() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.65, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	root.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	floor_mi.mesh = plane
	root.add_child(floor_mi)
	var piece := load(InteriorKit.piece_path("shower_cubicle")) as PackedScene
	for i in BODIES.size():
		var at := Vector3(i * 1.0 - 1.5, 0.0, 0.0)
		var cubicle := piece.instantiate() as Node3D
		cubicle.position = at
		root.add_child(cubicle)
		var node := PassengerLooks.SCENES[BODIES[i]].instantiate() as Node3D
		node.position = at + Vector3(0.0, TRAY_M, 0.0)
		node.set_meta(&"body", BODIES[i])
		PassengerLooks.paint_body(node, BODIES[i], 0)
		root.add_child(node)
		var player := node.get_node("AnimationPlayer") as AnimationPlayer
		player.get_animation("shower").loop_mode = Animation.LOOP_LINEAR
		player.play("shower")
		player.seek(i * 1.1, true)
		_people.append(node)
	_cam = CAMERA.instantiate() as TycoonCamera
	_cam.home_position = Vector3(0.0, 0.9, 0.0)
	root.add_child(_cam)


## Puts the first `n` people in a full lather, bare, and the others dressed.
func _shower(n: int) -> void:
	for i in _people.size():
		ActivityPoses.dress(_people[i], 0.0, 1.0 if i < n else 0.0, i < n)
