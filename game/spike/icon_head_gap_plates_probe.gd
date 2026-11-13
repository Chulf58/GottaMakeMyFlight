extends SceneTree
## Windowed plates of the need-icon row, the wish bubble and the count badges
## over passengers at the 70 and 38 degree camera steps (board b679fd1d,
## decision need-icons-and-wish-bubbles-sit-a-fixed-screen-gap-above-the).
## Boots main.tscn with NeedFacilityKit's terminal and a gate desk, sends in a
## crowd and steps the clock until SEATED_WANT passengers sit at the gate,
## gives every passenger the toilet need, every other one hunger and one in
## three boredom, then pauses the clock and plates:
##   seated, standing, rising (a seated passenger 12 ticks into its stand-up)
##   and wish (a wish bubble shown on a standing passenger), each alone with
##   clustering off at SUBJECT_M;
##   crowd (the seated gate rows) and queue (QUEUE passengers set standing one
##   cell apart in a line) with clustering on at CROWD_M.
## The nap pod plates come from nap_pod_icon_plates_probe.gd (--steps=both).
##
## For a subject it prints, in viewport pixels: the head top (the Head bone
## moved HEAD_UP_M along the camera's up), the row's bottom edge as laid out,
## the model gap between them, and the MEASURED gap: in the plate and a twin
## with the subject hidden, the clear rows between the icon and the head in a
## band of columns over the head. For a badge plate it prints every badge rect
## and the heads (squares from the bone-measured head top) it overlaps.
## Proofs before a plate is saved: the subject's feet, head top and row anchor
## project inside the frame by MARGIN_PX, a ray from the camera to the head is
## not blocked short of it, and the subject-hidden twin differs by
## MIN_SUBJECT_PX around it; a badge plate needs a badge inside the frame. The
## HUD CanvasLayers are hidden. Otherwise PROBE_INVALID, exit 1.
## PROBE_SEED replays a seed.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/icon_head_gap_plates_probe.gd
## Plates go to tools/blender/out/icon_gap_20261113/.

const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/icon_gap_20261113"
const CROWD := 40
const SPAWN_GAP_TICKS := 20
const SEATED_WANT := 12
const ARRIVE_LIMIT_TICKS := 6000
const FADE_LIMIT_FRAMES := 120
const MARGIN_PX := 12.0
const STEPS: Array[int] = [TycoonCamera.AngleStep.TOP_DOWN, TycoonCamera.AngleStep.LOW]
const SUBJECT_M := 12.0
const CROWD_M := 14.0
const SUBJECT_YAW := 0.35
const HEAD_UP_M := 0.12
const BAND_PX := 2
const MIN_SUBJECT_PX := 200
const QUEUE := 7
const CROP_PX := 200
const RISE_TICKS := 12

var _out_dir := ""
var _failed := false
var _main: Node3D
var _cam: Camera3D
var _rig: TycoonCamera
var _clock: SimClock
var _sim: PassengerSim
var _views: PassengerViews
var _sheets := {}
var _crops: Array[Image] = []
var _badges_on_heads := 0


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=%s" % _out_dir)
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _run() -> void:
	if await _boot():
		await _plates()
	for step: int in _sheets:
		_save(_sheet(_sheets[step], 3, 640), "sheet_%ddeg.png" % _pitch_of(step))
	if not _crops.is_empty():
		_save(_sheet(_crops, 4, 400), "sheet_crops.png")
	print("PROBE done failed=%s badges_on_heads=%d" % [_failed, _badges_on_heads])
	quit(1 if _failed else 0)


func _boot() -> bool:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var seed := randi()
	if OS.has_environment("PROBE_SEED"):
		seed = OS.get_environment("PROBE_SEED").to_int()
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	var mode := _main.get_node("BuildMode") as BuildMode
	mode.starter_shell = false
	root.add_child(_main)
	_clock.set_paused(true)
	await _frames(5)
	NeedFacilityKit.build(mode.grid)
	if not StarterFlight.add_gate_desk(mode.grid):
		_invalid("the gate desk was refused")
		return false
	(mode.get_node("BuildView") as BuildView).refresh(mode.grid)
	mode.set_tool(BuildMode.Tool.NONE)
	mode.set_process(false)
	(mode.get_node("Ghost") as Node3D).visible = false
	await _frames(20)
	_clock.set_process(false)
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_sim = _main.get_node("PassengerSim")
	_views = _main.get_node("PassengerViews")
	var staff := _main.get_node("Staff") as StaffSim
	StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(_clock, _main.get_node("FlightSim"), staff)
	if doors < 0:
		_invalid("the airport did not open")
		return false
	_clock.set_paused(false)
	var spawned := 0
	var ticks := 0
	while ticks < ARRIVE_LIMIT_TICKS and _seated().size() < SEATED_WANT:
		if spawned < CROWD and ticks % SPAWN_GAP_TICKS == 0:
			_sim.spawn_now(StarterFlight.first_flight())
			spawned += 1
		_clock.advance(SimClock.STEP)
		ticks += 1
		for id in _sim.passenger_ids():
			var p := _sim.get_passenger(id)
			p.hunger = 0
			p.toilet_need = 0
			p.boredom = 0
	print("PROBE arrive ticks=%d spawned=%d seated=%d" % [ticks, spawned, _seated().size()])
	if _seated().size() < SEATED_WANT:
		_invalid("only %d seated at the gate" % _seated().size())
		return false
	var i := 0
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		p.toilet_need = ToiletSim.NEED_MAX
		p.hunger = CafeSim.HUNGER_MAX if i % 2 == 0 else 0
		p.boredom = BoredomSim.MAX if i % 3 == 0 else 0
		i += 1
	_clock.advance(SimClock.STEP)
	_clock.set_paused(true)
	if _main.get_node("PlaneFleet").has_method("update_views"):
		_main.get_node("PlaneFleet").call("update_views")
	await _frames(30)
	return true


func _seated() -> Array[int]:
	var out: Array[int] = []
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node != null and node.get_meta(&"icon_seated", false):
			out.append(id)
	return out


## A drawn passenger standing on its feet (not seated, reclined or rising), or 0.
func _standing(skip: Array) -> int:
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node == null or not node.visible or skip.has(id):
			continue
		if node.get_meta(&"seated", false) or node.get_meta(&"icon_reclined", false):
			continue
		if node.get_meta(&"icon_rise", NeedIcons.Rise.NONE) != NeedIcons.Rise.NONE:
			continue
		return id
	return 0


func _plates() -> void:
	for node in _main.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	var seated := _seated()
	var centre := Vector3.ZERO
	for id in seated:
		centre += _views.node_for(id).global_position
	centre /= seated.size()
	var sitter: int = seated[0]
	var riser: int = seated[seated.size() / 2]
	var stander := _standing([])
	var wisher := _standing([stander])
	if stander == 0 or wisher == 0:
		_invalid("no standing passenger to plate")
		return
	var rising := _sim.get_passenger(riser)
	rising.stage = Passenger.Stage.STANDING_UP
	rising.stage_tick = _clock.tick - RISE_TICKS
	_views.snap()
	await _frames(10)
	var wish := _views.node_for(wisher)
	_views.cluster_needs = false
	for step in STEPS:
		_rig.angle_step = step as TycoonCamera.AngleStep
		await _subject("seated", sitter, step)
		await _subject("standing", stander, step)
		await _subject("rising", riser, step)
		WishIconView.show_wish(wish, [&"kiosk", WishTable.State.WANTED])
		await _subject("wish", wisher, step)
	_views.cluster_needs = true
	for step in STEPS:
		_rig.angle_step = step as TycoonCamera.AngleStep
		await _aim(centre, CROWD_M, SUBJECT_YAW)
		await _badge_plate("crowd", step)
	var line: Vector3 = await _queue(stander)
	if line == Vector3.INF:
		return
	for step in STEPS:
		_rig.angle_step = step as TycoonCamera.AngleStep
		await _aim(line, CROWD_M, 0.0)
		await _badge_plate("queue", step)


## Sets QUEUE standing passengers in a line one cell apart from `first`'s
## cell, running away from the camera, and returns the line's centre.
func _queue(first: int) -> Vector3:
	var start := _sim.get_passenger(first).at
	var ids: Array[int] = []
	for id in _sim.passenger_ids():
		if ids.size() < QUEUE and not _seated().has(id):
			ids.append(id)
	if ids.size() < QUEUE:
		_invalid("only %d passengers for the queue" % ids.size())
		return Vector3.INF
	for i in ids.size():
		var p := _sim.get_passenger(ids[i])
		p.at = start + Vector2i(0, -i)
		p.clear_path()
		p.stage = Passenger.Stage.STANDING
		p.stage_tick = _clock.tick
		p.toilet_need = ToiletSim.NEED_MAX
	_views.sync()
	_views.snap()
	await _frames(20)
	var centre := Vector3.ZERO
	for id in ids:
		centre += _views.node_for(id).global_position
	print("PROBE queue ids=%s start=%s" % [ids, start])
	return centre / ids.size()


func _aim(at: Vector3, distance: float, yaw: float) -> void:
	_rig.stop_follow()
	_rig.position = Vector3(at.x, 0.0, at.z)
	_rig.yaw = yaw
	_rig.distance = distance
	await _frames(20)
	var roof := _main.get_node("RoofView") as RoofView
	var fade := 0
	while roof.cutaway.roof_level != roof.cutaway.roof_target and fade < FADE_LIMIT_FRAMES:
		await process_frame
		fade += 1


func _subject(what: String, id: int, step: int) -> void:
	var node := _views.node_for(id)
	(node.get_node("Bubble") as Label3D).text = ""
	await _aim(node.global_position, SUBJECT_M, SUBJECT_YAW)
	await _frames(4)
	var tag := "%s_%ddeg" % [what, _pitch_of(step)]
	var to_output := root.get_stretch_transform().get_scale().y
	var head := _head_point(node)
	var top_m := head + _cam.global_basis.y * HEAD_UP_M
	var sprite := node.get_node(NeedIcons.SPRITES[0]) as Sprite3D
	var size := float(NeedIcons.SIZE)
	var px := NeedIcons.ICON_PX
	if what == "wish":
		sprite = node.get_node(WishIconView.SPRITE) as Sprite3D
		size = float(WishIconView.SIZE)
		px = WishIconView.WISH_PX
	if not sprite.visible:
		_invalid("%s: the subject's row is not drawn" % tag)
		return
	var ok := _in_frame(node.global_position, tag + " feet")
	ok = _in_frame(top_m, tag + " head_top") and ok
	ok = _in_frame(sprite.global_position, tag + " anchor") and ok
	_ray_check(tag, head)
	var top := _cam.unproject_position(top_m) * to_output
	var lift := (sprite.offset.y - size / 2.0) * px / size
	var bottom := _cam.unproject_position(sprite.global_position).y * to_output - lift
	var img := _grab()
	node.visible = false
	await _frames(3)
	var bare := _grab()
	node.visible = true
	await _frames(3)
	var k := img.get_width() / (root.get_visible_rect().size.x * to_output)
	var around := Rect2i(Vector2i((top * k) - Vector2.ONE * CROP_PX / 2.0), Vector2i.ONE * CROP_PX)
	around = around.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var changed := _diff(img, bare, around)
	var measured := _measured_gap(img, bare, int(top.x * k), int((bottom - px / 2.0) * k))
	print(
		(
			(
				"PLATE %s id=%d pitch=%.0f cam_dist_m=%.2f head_top_px=%s row_bottom_y=%.1f"
				+ " model_gap_px=%.1f measured_gap_px=%.1f subject_diff_px=%d in_frame=%s"
				+ " stage=%s rise=%s"
			)
			% [
				tag,
				id,
				_rig.pitch_degrees(),
				_cam.global_position.distance_to(head),
				top.round(),
				bottom,
				top.y - bottom,
				measured / k if measured >= 0 else -1.0,
				changed,
				ok,
				Passenger.Stage.keys()[_sim.get_passenger(id).stage],
				node.get_meta(&"icon_rise", 0)
			]
		)
	)
	if not ok or changed < MIN_SUBJECT_PX:
		_invalid("%s: subject not in frame or not drawn (diff %d)" % [tag, changed])
	_keep(img, tag, step)
	var crop := img.get_region(around)
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
	_save(crop, tag + "_crop.png")
	_crops.append(crop)


func _badge_plate(what: String, step: int) -> void:
	await _frames(4)
	var tag := "%s_%ddeg" % [what, _pitch_of(step)]
	var to_output := root.get_stretch_transform().get_scale().y
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX,
		root.get_visible_rect().size * to_output - Vector2.ONE * MARGIN_PX * 2.0
	)
	var heads := _head_rects(to_output)
	var inside := 0
	for b: Dictionary in _views.need_badges():
		var rect: Rect2 = b["rect"]
		var over: Array = []
		for id: int in heads:
			if rect.intersects(heads[id]):
				over.append(id)
		inside += int(frame.encloses(rect))
		_badges_on_heads += int(not over.is_empty())
		print(
			(
				"BADGE %s pitch=%.0f id=%d count=%d rect=%s centre=%s over_heads=%s in_frame=%s"
				% [
					tag,
					_rig.pitch_degrees(),
					b["id"],
					b["count"],
					rect,
					rect.get_center().round(),
					over,
					frame.encloses(rect)
				]
			)
		)
	if inside == 0:
		_invalid("%s: no badge inside the frame" % tag)
	_keep(_grab(), tag, step)


## Passenger id -> its head's screen rect in output pixels: a square from the
## bone-measured head top on screen down, two HEAD_UP_M across.
func _head_rects(to_output: float) -> Dictionary:
	var out := {}
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node == null or not node.is_visible_in_tree():
			continue
		var head := _head_point(node)
		if _cam.is_position_behind(head):
			continue
		var top := _cam.unproject_position(head + _cam.global_basis.y * HEAD_UP_M) * to_output
		var side := _cam.unproject_position(head + _cam.global_basis.x * HEAD_UP_M) * to_output
		var wide := 2.0 * side.distance_to(_cam.unproject_position(head) * to_output)
		out[id] = Rect2(top - Vector2(wide / 2.0, 0.0), Vector2.ONE * wide)
	return out


func _head_point(node: Node3D) -> Vector3:
	for skeleton in node.find_children("*", "Skeleton3D", true, false):
		var bones := skeleton as Skeleton3D
		var bone := bones.find_bone(NeedIcons.HEAD_BONE)
		if bone >= 0:
			return bones.global_transform * bones.get_bone_global_pose(bone).origin
	_invalid("no head bone on %s" % node.name)
	return node.global_position


func _ray_check(tag: String, head: Vector3) -> void:
	var space := _cam.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(_cam.global_position, head))
	var blocked := not hit.is_empty() and (hit["position"] as Vector3).distance_to(head) > 0.5
	print("PROBE %s ray_to_head blocked=%s" % [tag, blocked])
	if blocked:
		_invalid("%s: the head is behind %s" % [tag, hit["collider"]])


func _in_frame(point: Vector3, label: String) -> bool:
	var to_output := root.get_stretch_transform().get_scale().y
	var size := root.get_visible_rect().size * to_output
	var at := _cam.unproject_position(point) * to_output
	var inside := Rect2(Vector2.ONE * MARGIN_PX, size - Vector2.ONE * MARGIN_PX * 2.0).has_point(at)
	print("FRAME %s at=%s inside=%s" % [label, at.round(), inside])
	return inside and not _cam.is_position_behind(point)


## Clear rows between the subject's icon and its head: from `y` (inside the
## icon) down past the icon's pixels, then the rows where the plate and the
## subject-hidden twin agree in the band round `x`, until they differ again
## (the head). -1 when the band never reaches the head.
func _measured_gap(full: Image, bare: Image, x: int, y: int) -> int:
	var h := full.get_height()
	while y < h and _band(full, bare, x, y):
		y += 1
	var start := y
	while y < h and not _band(full, bare, x, y):
		y += 1
	return y - start if y < h else -1


func _band(a: Image, b: Image, x: int, y: int) -> bool:
	for dx in range(-BAND_PX, BAND_PX + 1):
		var c := a.get_pixel(x + dx, y)
		var d := b.get_pixel(x + dx, y)
		if absf(c.r - d.r) + absf(c.g - d.g) + absf(c.b - d.b) > 0.08:
			return true
	return false


func _diff(a: Image, b: Image, area: Rect2i) -> int:
	var count := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := a.get_pixel(x, y)
			var d := b.get_pixel(x, y)
			if absf(c.r - d.r) + absf(c.g - d.g) + absf(c.b - d.b) > 0.08:
				count += 1
	return count


func _grab() -> Image:
	return root.get_texture().get_image()


func _keep(img: Image, tag: String, step: int) -> void:
	_save(img, tag + ".png")
	if not _sheets.has(step):
		_sheets[step] = [] as Array[Image]
	(_sheets[step] as Array[Image]).append(img)


func _sheet(plates: Array[Image], columns: int, width: int) -> Image:
	var first := plates[0]
	var height := int(width * float(first.get_height()) / first.get_width())
	var rows := ceili(plates.size() / float(columns))
	var sheet := Image.create(width * columns, height * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	for i in plates.size():
		var small := plates[i].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(width, height, Image.INTERPOLATE_BILINEAR)
		var at := Vector2i(i % columns, i / columns) * Vector2i(width, height)
		sheet.blit_rect(small, Rect2i(Vector2i.ZERO, small.get_size()), at)
	return sheet


func _pitch_of(step: int) -> int:
	return int(TycoonCamera.STEP_PITCH_DEGREES[step])


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save " + path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw
