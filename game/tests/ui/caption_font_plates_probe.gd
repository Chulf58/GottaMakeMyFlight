extends SceneTree
## Caption font plates (board item L2): the in-world Label3D captions, each made
## by its own game path, before (font cleared, the engine default font every
## caption drew in before L2) and after (the font the path now sets, the HUD
## theme's Nunito through CaptionFont). One windowed run:
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --path game \
##     -s res://tests/ui/caption_font_plates_probe.gd
## The cafe test layout with a guest who has paid (a cafe pop under the cafe's
## room label) and that guest's speech bubble, with an apron stand status
## label, a gate caption, a landside Closed caption, a land price label and a
## need badge count around it. Look-pass camera: 54 degree pitch, 45 degree
## yaw. Every caption must project inside the window with a margin and have no
## collider between it and the camera (a control proves a blocked ray fails),
## else PROBE_INVALID, exit 1. No HUD is built; any CanvasLayer is hidden.
## Plates go to tools/blender/out/l2/ beside the game folder.

const OUT_REL := "res://../tools/blender/out/l2"
const STARTER := preload("res://landside/starter_landside.tres")
const WINDOW := Vector2i(1920, 1080)
const MARGIN_PX := 8.0
const PITCH_DEG := 54.0
const YAW_DEG := 45.0
const DISTANCE_M := 16.0

var _out_dir := ""
var _cam: Camera3D
var _root3d: Node3D
var _labels: Dictionary = {}
var _fonts: Dictionary = {}


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=%s" % _out_dir)
	root.size = WINDOW
	_run.call_deferred()


func _run() -> void:
	_root3d = Node3D.new()
	root.add_child(_root3d)
	_studio()
	var focus := await _cafe_scene()
	_extras(focus)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_root3d.add_child(_cam)
	var pitch := deg_to_rad(PITCH_DEG)
	var yaw := deg_to_rad(YAW_DEG)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	_cam.position = focus + dir * DISTANCE_M
	_cam.look_at(focus)
	_cam.make_current()
	for node in root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	await _frames(10)
	if not await _ray_control():
		return _invalid("ray control: a blocked ray was not caught")
	for kind: String in _labels:
		_fonts[kind] = (_labels[kind] as Label3D).font
	for phase in ["before_default_font", "after_nunito"]:
		for kind: String in _labels:
			var label := _labels[kind] as Label3D
			label.font = null if phase.begins_with("before") else _fonts[kind]
		await _frames(6)
		if not _prove():
			return
		await RenderingServer.frame_post_draw
		var path := _out_dir.path_join("caption_fonts_%s.png" % phase)
		var err := root.get_texture().get_image().save_png(path)
		print("PLATE saved %s err=%d" % [path, err])
		if err != OK:
			return _invalid("plate not saved")
	quit(0)


func _studio() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.47, 0.64, 0.43)
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6
	_root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	_root3d.add_child(sun)


## The cafe layout with one guest who has paid: returns the room label's spot.
func _cafe_scene() -> Vector3:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var views := PassengerTestWorld.views()
	views.clock = world.clock
	views.sim = world.sim
	_root3d.add_child(views)
	var rooms := RoomView.new()
	_root3d.add_child(rooms)
	rooms.watch(world.grid)
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	while p.stage != Passenger.Stage.TO_GATE and world.clock.tick < 900:
		world.step()
	if not world.sim.cafes.try_visit(p):
		_invalid("the guest did not start a cafe visit")
		return Vector3.ZERO
	while p.stage != Passenger.Stage.CAFE_STANDING_UP and world.clock.tick < 1400:
		world.step()
	var visit := world.sim.cafes.visit_of(p.id)
	await _frames(4)
	views.set_process(false)
	views.cafe_pops().set_process(false)
	var room_label := rooms.label_of(visit.room)
	_labels["room label"] = room_label
	_labels["cafe pop"] = views.cafe_pops().live_labels()[0]
	var bubble := views.node_for(p.id).get_node("Bubble") as Label3D
	bubble.text = BubbleWords.say("Where is security?")
	bubble.visible = true
	_labels["passenger bubble"] = bubble
	return room_label.global_position


## The captions that need no world, set out around `focus`.
func _extras(focus: Vector3) -> void:
	var stand := ApronStand.new()
	_root3d.add_child(stand)
	var status := stand.get_node("Status") as Label3D
	status.text = "Gate B: long walk to the plane: 42 m"
	status.visible = true
	status.global_position = focus + Vector3(-4.5, 0.5, -4.5)
	_labels["apron stand"] = status
	var view := GateLinksView.new()
	_root3d.add_child(view)
	var gate := view._make_caption("GateCaption", VERTICAL_ALIGNMENT_BOTTOM, 0.0)
	view.add_child(gate)
	gate.text = GateLinksView.caption_text("A", "large", 12)
	gate.global_position = focus + Vector3(2.0, 1.0, -6.0)
	_labels["gate caption"] = gate
	var places := LandsidePlaces.new()
	var sign := places._new_sign(STARTER, 0)
	_root3d.add_child(sign)
	sign.global_position = focus + Vector3(5.0, 0.5, -1.0)
	_labels["landside closed"] = sign.get_node("Caption")
	places.free()
	var tool := LandTool.new()
	_root3d.add_child(tool)
	tool.visible = true
	var price := tool.price_label()
	price.text = "Buy  $12,000"
	price.visible = true
	price.global_position = focus + Vector3(-6.0, 0.5, 2.0)
	_labels["land price"] = price
	var badge := NeedCluster.make_badge()
	_root3d.add_child(badge)
	badge.visible = true
	badge.global_position = focus + Vector3(-3.0, 0.5, 5.0)
	var count := badge.get_node(NeedCluster.COUNT) as Label3D
	count.text = "3"
	_labels["need count"] = count
	_size_fixed(gate, count)


## Each caption projects inside the window with a margin and no collider stands
## between it and the camera.
func _prove() -> bool:
	var view := Rect2(Vector2.ZERO, Vector2(root.size)).grow(-MARGIN_PX)
	var space := _cam.get_world_3d().direct_space_state
	for kind: String in _labels:
		var label := _labels[kind] as Label3D
		var at := label.global_position
		var p := _cam.unproject_position(at)
		var font := label.font if label.font != null else ThemeDB.fallback_font
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(_cam.global_position, at))
		print(
			(
				"PROBE %s '%s' at %s -> screen %s in_frame=%s shown=%s blocked=%s font=%s"
				% [
					kind,
					label.text.replace("\n", " / "),
					at,
					p,
					view.has_point(p),
					label.is_visible_in_tree(),
					not hit.is_empty(),
					_font_name(font),
				]
			)
		)
		if _cam.is_position_behind(at) or not view.has_point(p):
			_invalid("%s out of frame" % kind)
			return false
		if not label.is_visible_in_tree() or label.text == "" or not hit.is_empty():
			_invalid("%s not visible" % kind)
			return false
	return true


func _font_name(font: Font) -> String:
	if font is FontVariation:
		var base := (font as FontVariation).base_font
		return "FontVariation(%s, %s)" % [base.resource_path.get_file(), font.variation_opentype]
	return "%s (%s)" % [font.get_font_name(), font.resource_path]


## A box between the camera and a point must block the ray, or the occlusion
## check could pass by accident.
func _ray_control() -> bool:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	_root3d.add_child(body)
	var target := _cam.global_position - _cam.global_basis.z * 10.0
	body.global_position = _cam.global_position - _cam.global_basis.z * 5.0
	await physics_frame
	await physics_frame
	var space := _cam.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(_cam.global_position, target))
	print("PROBE ray control blocked=%s" % [not hit.is_empty()])
	body.free()
	await physics_frame
	return not hit.is_empty()


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _invalid(msg: String) -> void:
	print("PROBE_INVALID %s" % msg)
	quit(1)


## The screen sizes the game sets each frame (GateLinksView.update_sizes,
## NeedCluster's badge layout): one window pixel per caption font pixel.
func _size_fixed(gate: Label3D, count: Label3D) -> void:
	var unit := 2.0 * tan(deg_to_rad(50.0) / 2.0) / float(WINDOW.y)
	gate.pixel_size = unit
	count.pixel_size = NeedCluster.COUNT_EM_PX * unit / NeedCluster.COUNT_FONT
