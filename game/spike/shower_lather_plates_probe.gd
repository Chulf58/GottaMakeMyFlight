extends SceneTree
## Windowed coverage numbers and plates of the shower lather (ShowerFoam;
## board item bfe19c1e, decision
## activity-poses-sit-on-the-lounge-sofa-recline-in-the-nap-pod: no bare skin
## below the shoulders under a full lather; anti-pattern
## a-cover-shape-fitted-to-one-animation-clip-leaks-when-anothe). Bodies stand
## alone at the origin on the cubicle's tray, bare (ActivityPoses.bare_mesh),
## facing +z, the looping "shower" clip seeked by hand, a full lather on.
##
## Coverage: every body of PassengerLooks.BODIES at SAMPLES times through the
## clip, seen from the views in COVER_VIEWS (orthographic, COVER_PX square),
## in an unlit world: the body's torso and legs drawn flat red (every vertex
## whose strongest bone is none of NOT_BODY), its arms, hands, neck and head
## flat green, the lather black (no light reaches it). The red pixels left
## are bare skin below the shoulders showing through the lather. A twin with
## the lather hidden counts the red pixels the body has in that view, the
## control that proves each view sees the body.
## Prints COVER <body> <view> worst=<px> at=<s> twin=<px> per body and view,
## and COVER_TOTAL.
##
## Plates (lit, the real look): for a male and a female body at PLATE_TIMES
## through the clip, front, back, right, left and top orthographic views at
## true scale (ORTHO_M tall, a 1 m cube beside the body), and the game view
## from the front right and above in the cubicle; one sheet per body and
## time. Front, back and side views leave the cubicle out (its back panel
## hides the body); the top and game views stand the body in it, to show the
## lather inside the glass. Each plate proves the feet, chest and lather top
## in frame and that a twin with the body hidden differs; otherwise
## PROBE_INVALID, exit 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/shower_lather_plates_probe.gd \
##     [-- --cover-only] [--quick] [--sub=<folder under the out dir>]
## (--quick measures only the plated bodies)
##
## Plates go to tools/blender/out/shower-lather/.

const OUT_REL := "res://../tools/blender/out/shower-lather"
## Clip times measured per body.
const SAMPLES := 40
const COVER_PX := 360
const COVER_M := 2.1
## Bones whose vertices are not counted as skin to cover (a lower-case match
## anywhere in the bone's name): arms, hands, shoulders, neck and head. The
## feet ("foot" and "toes" bones, and every vertex below ActivityPoses.FEET_M
## at rest, where the shoes were) are not counted either and draw blue: they
## are bare by design, the lather starting above them.
const NOT_BODY: Array[String] = [
	"arm", "hand", "finger", "thumb", "shoulder", "clavicle", "neck", "head", "eye", "jaw"
]
## Coverage views: name, direction from the body to the camera.
const COVER_VIEWS := [
	["front", Vector3(0, 0, 1)],
	["back", Vector3(0, 0, -1)],
	["right", Vector3(1, 0, 0)],
	["left", Vector3(-1, 0, 0)],
	["top", Vector3(0, 1, 0)],
	["game_fr", Vector3(1.6, 2.4, 2.9)],
	["game_fl", Vector3(-1.6, 2.4, 2.9)],
	["game_br", Vector3(1.6, 2.4, -2.9)],
	["game_bl", Vector3(-1.6, 2.4, -2.9)],
]
## The bodies plated: tcp_male_character_01 and tcp_female_character_01.
const PLATE_BODIES: Array[int] = [0, 6]
## Shares of the clip plated: the start, each quarter, the end, and 0.33
## (1.63 s, where the old lather showed the most from above).
const PLATE_TIMES: Array[float] = [0.0, 0.25, 0.33, 0.5, 0.75, 0.95]
const PLATE_W := 640
const PLATE_H := 720
const ORTHO_M := 2.4
const MARGIN_PX := 8.0
const MIN_DIFF_PX := 300
const TRAY_M := 0.10

var _out_dir := ""
var _failed := false
var _cover_vps: Array[SubViewport] = []
var _cover_root: Node3D
## The coverage views as last drawn.
var _last: Array[Image] = []
var _plate_vp: SubViewport
var _plate_root: Node3D


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sub="):
			_out_dir = _out_dir.path_join(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print(
		(
			"PROBE out_dir=%s lather=%d parts=%s"
			% [_out_dir, ShowerFoam.lather_count(), ShowerFoam.PARTS]
		)
	)
	_run.call_deferred()


func _run() -> void:
	_build_cover_world()
	await _cover()
	if not "--cover-only" in OS.get_cmdline_user_args():
		_build_plate_world()
		for body in PLATE_BODIES:
			for share in PLATE_TIMES:
				await _plates(body, share)
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


## One unlit world drawn by one viewport per coverage view.
func _build_cover_world() -> void:
	var world := World3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = env
	for view: Array in COVER_VIEWS:
		var vp := SubViewport.new()
		vp.size = Vector2i(COVER_PX, COVER_PX)
		vp.world_3d = world
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.msaa_3d = Viewport.MSAA_DISABLED
		root.add_child(vp)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = COVER_M
		vp.add_child(cam)
		_aim(cam, view[1], Vector3(0.0, TRAY_M + 0.9, 0.0), 4.0)
		cam.make_current()
		_cover_vps.append(vp)
	_cover_root = Node3D.new()
	_cover_vps[0].add_child(_cover_root)


func _aim(cam: Camera3D, dir: Vector3, target: Vector3, back: float) -> void:
	var d := dir.normalized()
	var up := Vector3.FORWARD if absf(d.y) > 0.99 else Vector3.UP
	cam.look_at_from_position(target + d * back, target, up)


## Every body through the clip in every coverage view.
func _cover() -> void:
	var total := 0
	var twin_total := 0
	var worst_all := 0
	var quick := "--quick" in OS.get_cmdline_user_args()
	for body in PassengerLooks.BODIES.size():
		if quick and not body in PLATE_BODIES:
			continue
		var node := PassengerLooks.SCENES[body].instantiate() as Node3D
		node.position.y = TRAY_M
		_cover_root.add_child(node)
		var mi := PassengerLooks.body_mesh(node)
		var counted := _flag(mi, body)
		var flat := StandardMaterial3D.new()
		flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flat.vertex_color_use_as_albedo = true
		mi.material_override = flat
		var foam := _foam(node, false)
		var player := _player(node)
		var length := player.get_animation("shower").length
		var worst: Array[int] = []
		var worst_at: Array[float] = []
		var twin: Array[int] = []
		worst.resize(COVER_VIEWS.size())
		worst_at.resize(COVER_VIEWS.size())
		twin.resize(COVER_VIEWS.size())
		var masks: Array[Image] = []
		masks.resize(COVER_VIEWS.size())
		for i in SAMPLES:
			var t := length * i / SAMPLES
			player.seek(t, true)
			(foam.get_node("Lather") as Node3D).visible = true
			var shown := await _counts()
			var shown_images := _last.duplicate()
			(foam.get_node("Lather") as Node3D).visible = false
			var bare := await _counts()
			for v in COVER_VIEWS.size():
				total += shown[v]
				twin_total += bare[v]
				twin[v] = maxi(twin[v], bare[v])
				if shown[v] > worst[v]:
					worst[v] = shown[v]
					worst_at[v] = t
					masks[v] = shown_images[v]
		for v in COVER_VIEWS.size():
			worst_all = maxi(worst_all, worst[v])
			print(
				(
					"COVER %s %s worst=%d at=%.2f twin=%d"
					% [
						PassengerLooks.BODIES[body],
						COVER_VIEWS[v][0],
						worst[v],
						worst_at[v],
						twin[v]
					]
				)
			)
			if twin[v] < 200:
				_invalid(
					"%s %s: the body is not seen" % [PassengerLooks.BODIES[body], COVER_VIEWS[v][0]]
				)
		print("COVER_BODY %s counted_vertices=%d" % [PassengerLooks.BODIES[body], counted])
		if body in PLATE_BODIES:
			for v in COVER_VIEWS.size():
				if masks[v] != null:
					var mask_file := (
						"cover_%s_%s.png" % [PassengerLooks.BODIES[body], COVER_VIEWS[v][0]]
					)
					_save(masks[v], mask_file)
		node.free()
	print(
		(
			"COVER_TOTAL bare_px=%d of twin_px=%d worst_single=%d samples=%d views=%d"
			% [total, twin_total, worst_all, SAMPLES, COVER_VIEWS.size()]
		)
	)


## The red pixels (bare torso and legs) each coverage view shows now.
func _counts() -> Array[int]:
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var out: Array[int] = []
	_last.clear()
	for vp in _cover_vps:
		var img := vp.get_texture().get_image()
		_last.append(img.duplicate() as Image)
		img.convert(Image.FORMAT_R8)
		out.append(img.get_data().count(255))
	return out


## Gives `mi` a copy of body `body`'s bare mesh with its vertices coloured:
## red where the strongest bone is none of NOT_BODY, green elsewhere. Returns
## the red vertex count.
func _flag(mi: MeshInstance3D, body: int) -> int:
	var bare := ActivityPoses.bare_mesh(body) as ArrayMesh
	var skeleton := mi.get_node(mi.skeleton) as Skeleton3D
	var names: Array[String] = []
	for b in mi.skin.get_bind_count():
		var bind_name := String(mi.skin.get_bind_name(b))
		if bind_name == "":
			bind_name = skeleton.get_bone_name(mi.skin.get_bind_bone(b))
		names.append(bind_name)
	var mesh := ArrayMesh.new()
	var red := 0
	for s in bare.get_surface_count():
		var arrays := bare.surface_get_arrays(s)
		var format := bare.surface_get_format(s)
		var per := 8 if format & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors := PackedColorArray()
		colors.resize(verts.size())
		for v in verts.size():
			var best := 0
			for k in per:
				if weights[v * per + k] > weights[v * per + best]:
					best = k
			var bone := names[bones[v * per + best]].to_lower()
			var skin := true
			for word in NOT_BODY:
				skin = skin and not word in bone
			var foot := "foot" in bone or "toes" in bone or verts[v].y < ActivityPoses.FEET_M
			skin = skin and not foot
			colors[v] = Color(1, 0, 0) if skin else (Color(0, 0, 1) if foot else Color(0, 1, 0))
			if skin and s == 0:
				red += 1
		arrays[Mesh.ARRAY_COLOR] = colors
		mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		)
	if body == 0 or body == 6:
		print("BONES %s %s" % [PassengerLooks.BODIES[body], names])
	mi.mesh = mesh
	return red


## A full lather on `node`, with or without its steam.
func _foam(node: Node3D, steam: bool) -> ShowerFoam:
	var foam := ShowerFoam.new()
	node.add_child(foam)
	foam.set_amount(1.0)
	(foam.get_node("Haze") as Node3D).visible = steam
	(foam.get_node("Steam") as Node3D).visible = steam
	return foam


func _player(node: Node3D) -> AnimationPlayer:
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.get_animation("shower").loop_mode = Animation.LOOP_LINEAR
	player.play("shower")
	return player


## The lit world the plates are drawn in: sky colour, sun, floor, a 1 m cube.
func _build_plate_world() -> void:
	_plate_vp = SubViewport.new()
	_plate_vp.size = Vector2i(PLATE_W, PLATE_H)
	_plate_vp.own_world_3d = true
	_plate_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_plate_vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(_plate_vp)
	_plate_root = Node3D.new()
	_plate_vp.add_child(_plate_root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.65, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	_plate_root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	_plate_root.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.42, 0.42, 0.45)
	plane.material = grey
	floor_mi.mesh = plane
	_plate_root.add_child(floor_mi)
	var cube := MeshInstance3D.new()
	var box := BoxMesh.new()
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.3, 0.32, 0.4)
	box.material = stone
	cube.mesh = box
	cube.position = Vector3(-0.95, 0.5, -0.95)
	_plate_root.add_child(cube)


## The plates of body `body` at `share` of the clip: five orthographic views
## and the game view, each saved, and one sheet of all six.
func _plates(body: int, share: float) -> void:
	var node := PassengerLooks.SCENES[body].instantiate() as Node3D
	node.position.y = TRAY_M
	_plate_root.add_child(node)
	PassengerLooks.paint_body(node, body, 0)
	PassengerLooks.body_mesh(node).mesh = ActivityPoses.bare_mesh(body)
	_foam(node, false)
	var player := _player(node)
	var t := player.get_animation("shower").length * share
	player.seek(t, true)
	var cubicle := (load(InteriorKit.piece_path("shower_cubicle")) as PackedScene).instantiate()
	_plate_root.add_child(cubicle)
	var stem := "%s_t%03d" % [PassengerLooks.BODIES[body].trim_prefix("tcp_"), roundi(share * 100)]
	var views := [
		["front", Vector3(0, 0, 1), false],
		["back", Vector3(0, 0, -1), false],
		["right", Vector3(1, 0, 0), false],
		["left", Vector3(-1, 0, 0), false],
		["top", Vector3(0, 1, 0), true],
		["game", Vector3(1.6, 3.0, 3.5), true],
	]
	var images: Array[Image] = []
	for view: Array in views:
		cubicle.visible = view[2]
		var foam := node.get_node("ShowerFoam") as ShowerFoam
		(foam.get_node("Haze") as Node3D).visible = view[0] == "game"
		(foam.get_node("Steam") as Node3D).visible = view[0] == "game"
		var cam := Camera3D.new()
		_plate_root.add_child(cam)
		if view[0] == "game":
			cam.fov = 40.0
			cam.look_at_from_position(
				Vector3(1.6, 3.0, 3.5) * 0.9, Vector3(0.0, 0.95, 0.0), Vector3.UP
			)
		else:
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = ORTHO_M
			_aim(
				cam,
				view[1],
				Vector3(-0.35, 1.05, 0.0) if view[0] != "top" else Vector3(-0.3, 1.0, -0.3),
				4.0
			)
		cam.make_current()
		player.seek(t, true)
		var img := await _grab()
		var ok := true
		for point: Vector3 in [Vector3(0, 0.15, 0), Vector3(0, 1.3, 0), Vector3(0, 1.62, 0)]:
			ok = _in_frame(cam, point, "%s_%s" % [stem, view[0]]) and ok
		node.visible = false
		var without := await _grab()
		node.visible = true
		var diff := _diff(img, without)
		print("VISIBLE %s_%s diff_px=%d need=%d t=%.2f" % [stem, view[0], diff, MIN_DIFF_PX, t])
		if not ok or diff < MIN_DIFF_PX:
			_invalid("%s_%s: subject not shown (in_frame=%s diff=%d)" % [stem, view[0], ok, diff])
		_save(img, "%s_%s.png" % [stem, view[0]])
		images.append(img)
		cam.free()
	_save(_sheet(images), "%s_sheet.png" % stem)
	node.free()
	cubicle.free()


func _grab() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return _plate_vp.get_texture().get_image()


func _in_frame(cam: Camera3D, point: Vector3, label: String) -> bool:
	var rect := Rect2(Vector2.ZERO, Vector2(PLATE_W, PLATE_H)).grow(-MARGIN_PX)
	var screen := cam.unproject_position(point)
	var ok := not cam.is_position_behind(point) and rect.has_point(screen)
	print("INFRAME %s point=%s screen=(%.0f,%.0f) ok=%s" % [label, point, screen.x, screen.y, ok])
	return ok


func _diff(a: Image, b: Image) -> int:
	var count := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
				count += 4
	return count


## Six plates, three to a row.
func _sheet(plates: Array[Image]) -> Image:
	var sheet := Image.create(PLATE_W * 3, PLATE_H * 2, false, Image.FORMAT_RGBA8)
	for i in plates.size():
		var img := plates[i].duplicate() as Image
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(
			img,
			Rect2i(Vector2i.ZERO, img.get_size()),
			Vector2i(PLATE_W * (i % 3), PLATE_H * (i / 3))
		)
	return sheet


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s" % path)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true
