extends SceneTree
## Renders the intro dialogue's portrait: the airport manager (TCP_Male_Character_02,
## converted outside game/ by tools/blender/manager_portrait_glb.py) in the game's own
## toon material, lit by main.tscn's sun and environment, as a 520 px square PNG with a
## transparent background. 520 px is the size IntroDialogue shows it at on a 1080p
## screen, so the outline keeps its in-game pixel width.
##
## Windowed (the GPU renders it), from the repo root:
##   Godot_v4.7.2-stable_win64_console.exe --path game --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     -s res://spike/manager_portrait_probe.gd -- <manager .glb, Windows path>
## Writes res://assets/ui/intro_manager_portrait.png; run a Godot import after it.
## Prints PROBE_INVALID and exits 1 when the head or hips fall outside the frame or
## the material rebind misses a surface.

const OUT := "res://assets/ui/intro_manager_portrait.png"
const TOON := "res://assets/materials/tcp_atlas_toon.tres"
const MATERIAL_NAME := "TCP_Atlas_1A_D"
const SIZE := 520
const MARGIN := 12.0
## Seconds into the idle clip: a settled, upright frame.
const POSE_TIME := 1.0
## The face turns this far from the sun's side toward the camera's left.
const FACE_YAW_DEG := 22.0
const FOV := 24.0
const SETTLE_FRAMES := 12

var _port := SubViewport.new()
var _camera := Camera3D.new()
var _skeleton: Skeleton3D
var _frames := 0
var _character: Node3D
var _sun: DirectionalLight3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		_invalid("pass the manager .glb path after --")
		return
	var character := _load_character(args[0])
	if character == null:
		return
	_port.size = Vector2i(SIZE, SIZE)
	_port.transparent_bg = true
	_port.own_world_3d = true
	_port.msaa_3d = Viewport.MSAA_4X
	_port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_port)
	var main: Node = load("res://main/main.tscn").instantiate()
	var env := (main.get_node("WorldEnvironment") as WorldEnvironment).environment.duplicate()
	var sun := (main.get_node("Sun") as DirectionalLight3D).duplicate() as DirectionalLight3D
	main.free()
	# The sky still lights the scene (ambient source SKY); only the backdrop is cleared.
	env.background_mode = Environment.BG_CLEAR_COLOR
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_port.add_child(world_env)
	_port.add_child(sun)
	_port.add_child(character)
	_port.add_child(_camera)
	_character = character
	_sun = sun


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		# Global transforms exist only once the nodes are inside the tree.
		_pose(_character, _sun)
	if _frames < SETTLE_FRAMES:
		return false
	var head := _bone_world("Head")
	var hips := _bone_world("Hips")
	for pair in [["head", head], ["hips", hips]]:
		var p: Vector2 = _camera.unproject_position(pair[1])
		print("PORTRAIT %s world=%s screen=%s" % [pair[0], pair[1], p])
		var inside := Rect2(Vector2.ONE * MARGIN, Vector2.ONE * (SIZE - 2.0 * MARGIN))
		if pair[0] == "head" and not inside.has_point(p):
			_invalid("head outside the frame")
			return true
		if pair[0] == "hips" and (p.x < MARGIN or p.x > SIZE - MARGIN):
			_invalid("hips outside the frame sideways")
			return true
	var image := _port.get_texture().get_image()
	var opaque := 0
	var top_row_opaque := 0
	for y in SIZE:
		for x in SIZE:
			if image.get_pixel(x, y).a > 0.5:
				opaque += 1
				if y == 0:
					top_row_opaque += 1
	var share := float(opaque) / float(SIZE * SIZE)
	print("PORTRAIT opaque_share=%.3f top_row_opaque=%d" % [share, top_row_opaque])
	if share < 0.15 or top_row_opaque > 0:
		_invalid("the figure is too small or cut at the top")
		return true
	var err := image.save_png(OUT)
	print("PORTRAIT saved %s err=%d size=%s" % [OUT, err, image.get_size()])
	_port.queue_free()
	quit(0 if err == OK else 1)
	return true


func _load_character(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		_invalid("cannot read %s (error %d)" % [path, err])
		return null
	var scene := doc.generate_scene(state) as Node3D
	var toon := load(TOON) as Material
	var bound := 0
	var missed := 0
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		for i in mesh_node.mesh.get_surface_count():
			var source := mesh_node.mesh.surface_get_material(i)
			if source != null and source.resource_name == MATERIAL_NAME:
				mesh_node.set_surface_override_material(i, toon)
				bound += 1
			else:
				missed += 1
	print("PORTRAIT rebind bound=%d missed=%d" % [bound, missed])
	if bound == 0 or missed > 0:
		_invalid("the toon material rebind missed surfaces")
		return null
	var skeletons := scene.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() != 1:
		_invalid("expected one skeleton, found %d" % skeletons.size())
		return null
	_skeleton = skeletons[0] as Skeleton3D
	for bone in ["Head", "Hips"]:
		if _skeleton.find_bone(bone) < 0:
			_invalid("the skeleton has no %s bone" % bone)
			return null
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	if players.size() != 1 or not (players[0] as AnimationPlayer).has_animation("idle"):
		_invalid("expected one AnimationPlayer with an idle clip")
		return null
	return scene


## Plays the idle clip at POSE_TIME, turns the face toward the sun's side and puts
## the camera in front of it, framing the head to the hips.
func _pose(character: Node3D, sun: DirectionalLight3D) -> void:
	var players := character.find_children("*", "AnimationPlayer", true, false)
	var player := players[0] as AnimationPlayer
	player.play("idle")
	player.seek(POSE_TIME, true)
	player.pause()
	print(
		(
			"PORTRAIT pose clip=%s at=%.2f"
			% [player.assigned_animation, player.current_animation_position]
		)
	)
	var to_sun := sun.global_transform.basis.z
	to_sun.y = 0.0
	to_sun = to_sun.normalized()
	var face := to_sun.rotated(Vector3.UP, deg_to_rad(FACE_YAW_DEG))
	# A glTF character faces +Z.
	character.rotation.y = atan2(face.x, face.z)
	_skeleton.force_update_all_bone_transforms()
	var head := _bone_world("Head")
	var hips := _bone_world("Hips")
	var centre := Vector3(head.x, lerpf(hips.y, head.y, 0.62), head.z)
	var height := (head.y - hips.y) + 0.55
	var distance := height / (2.0 * tan(deg_to_rad(FOV / 2.0)))
	var view_dir := to_sun.rotated(Vector3.UP, deg_to_rad(-8.0))
	_camera.fov = FOV
	_camera.position = centre + view_dir * distance + Vector3.UP * 0.12
	_camera.look_at(centre, Vector3.UP)
	print("PORTRAIT head=%s hips=%s distance=%.2f" % [head, hips, distance])


func _bone_world(bone_name: String) -> Vector3:
	# _load_character refused a skeleton without the bones this probe reads.
	var bone := _skeleton.find_bone(bone_name)
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(bone).origin


func _invalid(why: String) -> void:
	print("PROBE_INVALID %s" % why)
	quit(1)
