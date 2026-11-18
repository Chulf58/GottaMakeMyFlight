extends SceneTree
## Renders the airline's opening call portrait: Gotta Air's station manager
## (TCP_Female_Character_07's skirt suit, converted outside game/ by
## tools/blender/manager_portrait_glb.py with the speaker station_manager), in
## Gotta Air's livery, as a 520 px square PNG with a transparent background.
## Framing, light, pose and size are the terminal manager's
## (game/spike/manager_portrait_probe.gd, whose constants this reads), so the two
## portraits read as one cast (decision the-airline-s-opening-phone-call-shows-a-
## new-gotta-air-stati).
##
## The livery: the suit's swatches take the colours of Gotta Air's planes
## (the starter, tp_plane_03a, measured from its atlas): the jacket body takes
## the lime colour, while the skirt, neckerchief and jacket buttons take the
## dark green trim. The white shirt collar keeps its vendor colour. Clothes are
## told apart from skin/hair/shoes by the converter's clothes' mark (COLOR_0),
## the white shirt from the dyed suit/trim swatches by cell brightness, and the
## jacket body from the skirt by each connected vertex island's rest height
## share (they share cell 377 on TCP_Atlas_1A_D).
##
## Windowed (the GPU renders it), from the repo root:
##   Godot_v4.7.2-stable_win64_console.exe --path game --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     -s res://assets/ui/station_manager_portrait_probe.gd -- <station .glb, Windows path>
## Writes res://assets/ui/station_manager_portrait.png; run a Godot import after it.
## Prints PROBE_INVALID and exits 1 when the head or hips fall outside the frame,
## the material rebind misses a surface or the suit is missing jacket or skirt.

const ManagerProbe := preload("res://spike/manager_portrait_probe.gd")
const OUT := "res://assets/ui/station_manager_portrait.png"
const SIZE: int = ManagerProbe.SIZE
const MARGIN: float = ManagerProbe.MARGIN
## Gotta Air's livery, the area-weighted mean colours of tp_plane_03a's lime
## body and dark green trim.
const LIME := Color("65b70f")
const TRIM := Color("306003")
## Clothes cells brighter than SHIRT_ABOVE are the white shirt collar (kept as
## vendor white); cells in SUIT_MIN..DARK_BELOW are the main suit cloth (cell
## 377, split into lime jacket and trim skirt); the remaining non-shirt clothes
## cells (neckerchief cell 370 and buttons cell 338) take TRIM.
const SHIRT_ABOVE := 0.60
const DARK_BELOW: float = PassengerLooks.DARK_BELOW
const SUIT_MIN := 0.25
const SWATCH_PX: Vector2i = PassengerLooks.SWATCH_PX
## Connected suit-cloth islands at or above JACKET_FROM of the body's rest height
## are the jacket (0.76..0.82 -> lime); below it is the skirt (0.44..0.53 -> trim).
const JACKET_FROM := 0.57

var _port: SubViewport
var _camera: Camera3D
var _skeleton: Skeleton3D
var _frames := 0
var _character: Node3D
var _sun: DirectionalLight3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		_invalid("pass the station manager .glb path after --")
		return
	var character := _load_character(args[0])
	if character == null:
		return
	_port = SubViewport.new()
	_camera = Camera3D.new()
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
	if _character == null:
		return true
	_frames += 1
	if _frames == 1:
		_pose(_character, _sun)
	if _frames < ManagerProbe.SETTLE_FRAMES:
		return false
	if not _frame_ok():
		return true
	var image := _port.get_texture().get_image()
	if image == null:
		_invalid("no rendered image (run windowed with vulkan, not headless)")
		return true
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


func _frame_ok() -> bool:
	var head := _bone_world("Head")
	var hips := _bone_world("Hips")
	var inside := Rect2(Vector2.ONE * MARGIN, Vector2.ONE * (SIZE - 2.0 * MARGIN))
	for pair in [["head", head], ["hips", hips]]:
		var p: Vector2 = _camera.unproject_position(pair[1])
		print("PORTRAIT %s world=%s screen=%s" % [pair[0], pair[1], p])
		if pair[0] == "head" and not inside.has_point(p):
			_invalid("head outside the frame")
			return false
		if pair[0] == "hips" and (p.x < MARGIN or p.x > SIZE - MARGIN):
			_invalid("hips outside the frame sideways")
			return false
	return true


func _load_character(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		_invalid("cannot read %s (error %d)" % [path, err])
		return null
	var scene := doc.generate_scene(state) as Node3D
	if not _bind_and_dress(scene) or not _check_rig(scene):
		scene.free()
		return null
	return scene


func _bind_and_dress(scene: Node3D) -> bool:
	var toon := load(ManagerProbe.TOON) as ShaderMaterial
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	var bound := 0
	var missed := 0
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		for i in mesh_node.mesh.get_surface_count():
			var source := mesh_node.mesh.surface_get_material(i)
			if source != null and source.resource_name == ManagerProbe.MATERIAL_NAME:
				mesh_node.set_surface_override_material(i, toon)
				bound += 1
			else:
				missed += 1
	print("PORTRAIT rebind bound=%d missed=%d" % [bound, missed])
	if bound != 1 or missed > 0 or meshes.size() != 1:
		_invalid("expected one mesh with one toon surface")
		return false
	return _dress(meshes[0] as MeshInstance3D, toon)


func _check_rig(scene: Node3D) -> bool:
	var skeletons := scene.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() != 1:
		_invalid("expected one skeleton, found %d" % skeletons.size())
		return false
	_skeleton = skeletons[0] as Skeleton3D
	for bone in ["Head", "Hips"]:
		if _skeleton.find_bone(bone) < 0:
			_invalid("the skeleton has no %s bone" % bone)
			return false
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	if players.size() != 1 or not (players[0] as AnimationPlayer).has_animation("idle"):
		_invalid("expected one AnimationPlayer with an idle clip")
		return false
	return true


## Splits the body mesh into surface 0 (skin, hair, shoes and white shirt on
## the vendor atlas), surface 1 (jacket in LIME) and surface 2 (skirt in TRIM).
## False when jacket or skirt is missing.
func _dress(mesh_node: MeshInstance3D, toon: ShaderMaterial) -> bool:
	var plain := mesh_node.mesh as ArrayMesh
	var arrays := plain.surface_get_arrays(0)
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	if colors.is_empty():
		_invalid("the body has no clothes' mark (COLOR_0)")
		return false
	var atlas := (toon.get_shader_parameter("albedo_texture") as Texture2D).get_image()
	atlas.decompress()
	var size := Vector2(atlas.get_width(), atlas.get_height())
	var cols := atlas.get_width() / SWATCH_PX.x
	var low := INF
	var high := -INF
	for v in verts:
		low = minf(low, v.y)
		high = maxf(high, v.y)
	var parent := _cloth_islands(verts.size(), index, colors)
	var island_y := {}
	var cells := {}
	var tri_cell := PackedInt32Array()
	var tri_root := PackedInt32Array()
	for t in range(0, index.size(), 3):
		if colors[index[t]].r <= 0.5:
			tri_cell.append(-1)
			tri_root.append(-1)
			continue
		var r := _uf_find(parent, index[t])
		var uv := (uvs[index[t]] + uvs[index[t + 1]] + uvs[index[t + 2]]) / 3.0
		var px := Vector2i((uv * size).floor()).clamp(Vector2i.ZERO, Vector2i(size) - Vector2i.ONE)
		var cell := (px.y / SWATCH_PX.y) * cols + px.x / SWATCH_PX.x
		var y := (verts[index[t]].y + verts[index[t + 1]].y + verts[index[t + 2]].y) / 3.0
		var y_share := (y - low) / (high - low)
		cells[cell] = cells.get(cell, Vector2.ZERO) + Vector2(atlas.get_pixelv(px).v, 1.0)
		island_y[r] = island_y.get(r, Vector2.ZERO) + Vector2(y_share, 1.0)
		tri_cell.append(cell)
		tri_root.append(r)
	var suit_cells := {}
	var dyed_cells := {}
	for cell: int in cells:
		var mean_v: float = cells[cell].x / cells[cell].y
		if mean_v < SHIRT_ABOVE:
			dyed_cells[cell] = mean_v
			if mean_v >= SUIT_MIN and mean_v < DARK_BELOW:
				suit_cells[cell] = mean_v
		print("PORTRAIT cell=%d value=%.2f triangles=%d" % [cell, mean_v, int(cells[cell].y)])
	var parts: Array[PackedInt32Array] = [
		PackedInt32Array(),
		PackedInt32Array(),
		PackedInt32Array(),
	]
	for i in tri_cell.size():
		var into := 0
		var c := tri_cell[i]
		if suit_cells.has(c):
			var h: float = island_y[tri_root[i]].x / island_y[tri_root[i]].y
			into = 1 if h >= JACKET_FROM else 2
		elif dyed_cells.has(c):
			into = 2
		parts[into].append_array(index.slice(i * 3, i * 3 + 3))
	var jacket_tris := parts[1].size() / 3
	var trim_tris := parts[2].size() / 3
	print(
		(
			"PORTRAIT split rest=%d jacket=%d trim=%d triangles"
			% [parts[0].size() / 3, jacket_tris, trim_tris]
		)
	)
	if jacket_tris == 0 or trim_tris == 0:
		_invalid("the suit has no jacket or no trim triangles")
		return false
	var flags: int = plain.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var mesh := ArrayMesh.new()
	for i in 3:
		arrays[Mesh.ARRAY_INDEX] = parts[i]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	mesh_node.mesh = mesh
	mesh_node.set_surface_override_material(0, toon)
	mesh_node.set_surface_override_material(1, _livery(toon, atlas, suit_cells, LIME))
	mesh_node.set_surface_override_material(2, _livery(toon, atlas, dyed_cells, TRIM))
	return true


func _cloth_islands(
	vert_count: int, index: PackedInt32Array, colors: PackedColorArray
) -> PackedInt32Array:
	var parent := PackedInt32Array()
	parent.resize(vert_count)
	for i in vert_count:
		parent[i] = i
	for t in range(0, index.size(), 3):
		if colors[index[t]].r <= 0.5:
			continue
		var a := _uf_find(parent, index[t])
		var b := _uf_find(parent, index[t + 1])
		var c := _uf_find(parent, index[t + 2])
		parent[b] = a
		parent[c] = a
	return parent


func _uf_find(parent: PackedInt32Array, x: int) -> int:
	var root_idx := x
	while parent[root_idx] != root_idx:
		root_idx = parent[root_idx]
	while parent[x] != root_idx:
		var next := parent[x]
		parent[x] = root_idx
		x = next
	return root_idx


## The toon material on a copy of `atlas` whose `cells` (cell -> mean value) are
## `colour`, each texel scaled by its value over its cell's mean, so the
## swatch's gradient stays a gradient. Only the cells' own surface samples it.
func _livery(
	toon: ShaderMaterial, atlas: Image, cells: Dictionary, colour: Color
) -> ShaderMaterial:
	var out := atlas.duplicate() as Image
	if out.has_mipmaps():
		out.clear_mipmaps()
	var cols := out.get_width() / SWATCH_PX.x
	for cell: int in cells:
		var x0: int = (cell % cols) * SWATCH_PX.x
		var y0: int = (cell / cols) * SWATCH_PX.y
		for y in range(y0, y0 + SWATCH_PX.y):
			for x in range(x0, x0 + SWATCH_PX.x):
				var c := out.get_pixel(x, y)
				var k := clampf(c.v / maxf(cells[cell], 0.01), 0.6, 1.4)
				out.set_pixel(x, y, Color(colour.r * k, colour.g * k, colour.b * k, c.a))
	out.generate_mipmaps()
	var made := toon.duplicate() as ShaderMaterial
	made.set_shader_parameter("albedo_texture", ImageTexture.create_from_image(out))
	return made


## The terminal manager's pose and camera (ManagerProbe._pose), the same
## numbers: the idle clip at POSE_TIME, the face turned toward the sun's side,
## the camera framing the head to the hips.
func _pose(character: Node3D, sun: DirectionalLight3D) -> void:
	var players := character.find_children("*", "AnimationPlayer", true, false)
	var player := players[0] as AnimationPlayer
	player.play("idle")
	player.seek(ManagerProbe.POSE_TIME, true)
	player.pause()
	var to_sun := sun.global_transform.basis.z
	to_sun.y = 0.0
	to_sun = to_sun.normalized()
	var face := to_sun.rotated(Vector3.UP, deg_to_rad(ManagerProbe.FACE_YAW_DEG))
	character.rotation.y = atan2(face.x, face.z)
	_skeleton.force_update_all_bone_transforms()
	var head := _bone_world("Head")
	var hips := _bone_world("Hips")
	var centre := Vector3(head.x, lerpf(hips.y, head.y, 0.62), head.z)
	var height := (head.y - hips.y) + 0.55
	var fov: float = ManagerProbe.FOV
	var distance := height / (2.0 * tan(deg_to_rad(fov / 2.0)))
	var view_dir := to_sun.rotated(Vector3.UP, deg_to_rad(-8.0))
	_camera.fov = fov
	_camera.position = centre + view_dir * distance + Vector3.UP * 0.12
	_camera.look_at(centre, Vector3.UP)
	print("PORTRAIT head=%s hips=%s distance=%.2f" % [head, hips, distance])


func _bone_world(bone_name: String) -> Vector3:
	var bone := _skeleton.find_bone(bone_name)
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(bone).origin


func _invalid(why: String) -> void:
	print("PROBE_INVALID %s" % why)
	if _port != null:
		_port.queue_free()
	quit(1)
