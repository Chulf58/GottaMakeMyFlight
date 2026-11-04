extends SceneTree
## Windowed plates of a backpack taken out of its tray at a security lane's
## pickup table and put on the back (board 41c159bc), on SecurityTestWorld's
## lane built LEFT (the pickup table on the walker's left, as in the crossing
## probe's --lane run). Case "one": a passenger with the backpack alone, plated
## at k 0.25, 0.5 and 0.75 of the move; case "two": a passenger with two bags,
## the backpack one of them, plated at k 0.5 (its hand still crosses the body,
## CarryLead.back_lead). Each moment is plated from two cameras round the body:
## front three-quarter on the lead hand's side, and from that side.
##
## The world draws only the passengers and their bags (PassengerViews), a floor
## and a stand-in slab under the tray where the backpack waited: the lane's own
## pieces are not drawn. The sim clock is stepped by the probe (a third of a
## tick a frame, as the crossing probe plates), and each moment is reached
## exactly and held while it is plated.
##
## Before a plate is saved, the pack's bounds and the holding hand's grip are
## projected through the camera and must be MARGIN_PX inside the viewport, the
## pack at least MIN_PACK_PX tall, and sight lines (against colliders of every
## drawn mesh, PlateSight) must land on the pack with none blocked before it.
## Each plate prints the grip in the body's frame, the shoulder joint height,
## the grip's distance to the pack's grab loop, and body points inside the
## pack; each case prints its move's totals (BODY_IN_OWN_BAG). Any failure
## prints PROBE_INVALID and exits 1. Plates and a contact sheet go to
## tools/blender/out/backpack-pickup/.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/backpack_pickup_probe.gd [-- --seed=N]

const PlateSight := preload("res://spike/plate_sight.gd")
const CarryContact := preload("res://spike/carry_contact.gd")
const CarryChecks := preload("res://spike/carry_probe_checks.gd")
const OUT_REL := "res://../tools/blender/out/backpack-pickup"
const MARGIN_PX := 16.0
## (Lying in its tray at k 0.25, seen from the front three-quarter, the pack
## is about 136 px tall.)
const MIN_PACK_PX := 120.0
## Camera distance from the look-at point (m) and its height over it.
const CAM_M := 1.5
const CAM_UP_M := 0.25
## [name, bags, moments].
const CASES := [["one", 1, [0.25, 0.5, 0.75]], ["two", 2, [0.5]]]
const MAX_FRAMES := 9000

var _failed := false
var _seed := 0
var _saved: Array[String] = []
var _world: SecurityTestWorld
var _views: PassengerViews
var _subject: Passenger
var _bag := 0
var _cam: Camera3D


func _initialize() -> void:
	_seed = randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
	print("PROBE sim_seed=", _seed)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_REL))
	_stage()
	_run.call_deferred()


func _invalid(why: String) -> void:
	_failed = true
	print("PROBE_INVALID ", why)


## Light, sky, floor and the camera, once.
func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.68, 0.74)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.78)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(35.0), 0.0)
	root.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	floor_mesh.mesh = plane
	floor_mesh.material_override = _flat(Color(0.5, 0.5, 0.47))
	root.add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	root.add_child(_cam)
	_cam.current = true


func _flat(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	return mat


func _run() -> void:
	for case: Array in CASES:
		await _case(case[0], case[1], case[2])
	_sheet()
	print("PROBE plates=%d failed=%s" % [_saved.size(), _failed])
	quit(1 if _failed else 0)


## A new LEFT lane world and one passenger with `bags` bags, a backpack among
## them; others are sent on to the gate.
func _send(bags: int) -> bool:
	if _views != null:
		_views.free()
	if _world != null:
		_world.world.free_all()
	_world = SecurityTestWorld.make(true, _seed, SecurityLanes.LEFT)
	_views = PassengerTestWorld.views()
	_views.clock = _world.world.clock
	_views.sim = _world.world.sim
	root.add_child(_views)
	for i in 200:
		var p := _world.world.passenger(_world.send(bags))
		for b in bags:
			if SecurityLooks.bag_kind(p, b) == SecurityLooks.Kind.BACKPACK:
				_subject = p
				_bag = b
				print("SUBJECT bags=%d passenger=%d bag=%d" % [bags, p.id, b])
				return true
		p.cleared = true
		p.stage = Passenger.Stage.TO_GATE
	return false


## Steps the clock by `seconds` and the subject's clips by the same time, and
## draws one frame.
func _step(seconds: float) -> void:
	_world.world.clock.advance(seconds)
	var body := _views.node_for(_subject.id)
	if body != null:
		var player := body.get_node("AnimationPlayer") as AnimationPlayer
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.advance(seconds)
	await process_frame


## Follows case `name`'s backpack from its tray onto the back, plating each of
## `moments` (k) and counting body points inside the pack on every frame.
func _case(name: String, bags: int, moments: Array) -> void:
	if not _send(bags):
		_invalid("%s: no passenger with a backpack" % name)
		return
	var props := _views.carry_on_props()
	var ticks := float(CarryOnProps.TRANSFER_TICKS)
	var was_tray := false
	var in_move := false
	var next := 0
	var frames := 0
	var inside := 0
	var top := -INF
	var slab := false
	for i in MAX_FRAMES:
		var dt := SimClock.STEP / 3.0
		var k := props.transfer_progress(_subject.id, _bag)
		if in_move and next < moments.size():
			dt = clampf((float(moments[next]) - k) * ticks * SimClock.STEP, 0.0, dt) + 0.0001
		await _step(dt)
		var st := props.bag_state(_subject.id, _bag)
		if not st.has("home"):
			continue
		var home := int(st["home"]) / 4
		k = props.transfer_progress(_subject.id, _bag)
		if not in_move:
			if home == SecurityLooks.Home.TRAY and _subject.stage == Passenger.Stage.SECURITY:
				was_tray = true
			elif was_tray and home == SecurityLooks.Home.HAND and k < 1.0:
				in_move = true
			if not in_move:
				continue
		if k >= 1.0:
			break
		var body := _views.node_for(_subject.id)
		var bag: Node3D = props.props_of(_subject.id)["bags"][_bag]
		if not slab:
			slab = true
			_slab(bag)
		var hits := CarryContact.inside_meshes(
			CarryContact.body_points(body, CarryChecks.gripping(_world.world.sim, _subject)), bag
		)
		frames += 1
		inside += hits
		var holder := int(props.bag_state(_subject.id, _bag).get("held_by", -1))
		_print_frame(name, k, hits, body, bag, holder)
		if holder >= 0:
			top = maxf(
				top, (body.global_transform.affine_inverse() * props.grip_of(body, holder)).y
			)
		if next < moments.size() and k >= float(moments[next]) - 0.01:
			for view in ["front34", "side"]:
				await _plate(name, view, k, body, bag)
			next += 1
	print(
		(
			"BODY_IN_OWN_BAG case=%s frames=%d inside=%d grip_top_m=%.3f seed=%d"
			% [name, frames, inside, top, _seed]
		)
	)
	if frames < CarryOnProps.TRANSFER_TICKS * 3 - 1:
		_invalid("%s: the move was followed over %d frames only" % [name, frames])
	if next < moments.size():
		_invalid("%s: plated %d of %d moments" % [name, next, moments.size()])
	if inside > 0:
		_invalid("%s: %d body points inside the pack over the move" % [name, inside])


## One frame of the move: the body points inside the pack and the bones they
## belong to, the holding hand's grip and the pack's middle in the body's frame.
func _print_frame(
	name: String, k: float, hits: int, body: Node3D, bag: Node3D, holder: int
) -> void:
	var props := _views.carry_on_props()
	var to_body := body.global_transform.affine_inverse()
	var hand := holder if holder >= 0 else (1 if _subject.carry_on == 1 else _bag)
	var middle := (
		bag.global_transform * CarryOnProps.bag_box(SecurityLooks.Kind.BACKPACK).get_center()
	)
	var bones := (
		CarryChecks.contact_bones(body, CarryChecks.gripping(_world.world.sim, _subject), bag)
		if hits > 0
		else {}
	)
	print(
		(
			"FRAME %s k=%.2f held_by=%d inside=%d grip=%s pack_mid=%s bones=%s"
			% [
				name,
				k,
				holder,
				hits,
				(to_body * props.grip_of(body, hand)).snapped(Vector3.ONE * 0.01),
				(to_body * middle).snapped(Vector3.ONE * 0.01),
				bones,
			]
		)
	)


## A stand-in table top under the tray the pack waits in (the lane's own pickup
## table is not drawn).
func _slab(bag: Node3D) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.04, 0.7)
	var slab := MeshInstance3D.new()
	slab.mesh = box
	slab.material_override = _flat(Color(0.35, 0.37, 0.42))
	_views.add_child(slab)
	var at := bag.global_transform * CarryOnProps.bag_box(SecurityLooks.Kind.BACKPACK).get_center()
	slab.global_position = Vector3(at.x, bag.global_position.y - 0.02, at.z)


## One plate of the subject at `k` from `view`: the camera aimed between the
## hand and the pack, the subject proved in frame and in sight before saving.
func _plate(name: String, view: String, k: float, body: Node3D, bag: Node3D) -> void:
	var props := _views.carry_on_props()
	var holder := int(props.bag_state(_subject.id, _bag).get("held_by", -1))
	# Not held yet (k 0.25): the hand reaching for it, the table side for one bag.
	var lead := holder if holder >= 0 else (1 if _subject.carry_on == 1 else _bag)
	var to_body := body.global_transform.affine_inverse()
	var box := _world_box(bag)
	var grip := props.grip_of(body, lead)
	var aim := box.get_center().lerp(grip, 0.4)
	var out := 1.0 if lead == 1 else -1.0
	var turn := deg_to_rad(40.0) if view == "front34" else deg_to_rad(90.0)
	var dir := Vector3(out * sin(turn), 0.0, cos(turn))
	var from := aim + body.global_transform.basis.orthonormalized() * (dir * CAM_M)
	_cam.global_position = from + Vector3.UP * CAM_UP_M
	_cam.look_at(aim, Vector3.UP)
	await process_frame
	await process_frame
	var tag := "%s_k%03d_%s" % [name, roundi(k * 100.0), view]
	var rect := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * 2.0 * MARGIN_PX
	)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var ok := true
	for corner in 8:
		var px := _cam.unproject_position(box.get_endpoint(corner))
		lo = lo.min(px)
		hi = hi.max(px)
		ok = ok and rect.has_point(px) and not _cam.is_position_behind(box.get_endpoint(corner))
	var grip_px := _cam.unproject_position(grip)
	ok = ok and rect.has_point(grip_px)
	print(
		(
			"INFRAME %s pack=(%s)-(%s) grip=%s ok=%s"
			% [tag, lo.round(), hi.round(), grip_px.round(), ok]
		)
	)
	var owners: Array[Node] = [_views]
	var holder_node := PlateSight.colliders(root, owners, {bag: "pack"})
	await physics_frame
	await physics_frame
	var targets: Array[Vector3] = [box.get_center()]
	for f in [
		Vector3(0.3, 0.0, 0.0),
		Vector3(-0.3, 0.0, 0.0),
		Vector3(0.0, 0.3, 0.0),
		Vector3(0.0, -0.3, 0.0)
	]:
		targets.append(box.get_center() + _cam.global_basis * (f * box.size.length() * 0.5))
	var lines := PlateSight.sight_lines(
		_cam.get_world_3d().direct_space_state, _cam.global_position, targets, "pack"
	)
	holder_node.free()
	var on: int = (lines["on_subject"] as Array).size()
	print("INFRAME %s sight on_pack=%d/5 blockers=%s" % [tag, on, lines["blockers"]])
	ok = ok and on >= 2 and hi.y - lo.y >= MIN_PACK_PX
	var loop := bag.global_transform * CarryOnProps.BACKPACK_LOOP
	var own := CarryContact.body_points(body, CarryChecks.gripping(_world.world.sim, _subject))
	print(
		(
			"PLATE_AT %s k=%.2f held_by=%d grip_body=%s shoulder_y=%.3f grip_to_loop_m=%.3f inside=%d"
			% [
				tag,
				k,
				holder,
				(to_body * grip).snapped(Vector3.ONE * 0.01),
				(to_body * props._shoulder_of(body, lead)).y,
				grip.distance_to(loop),
				CarryContact.inside_meshes(own, bag),
			]
		)
	)
	if not ok:
		_invalid("%s: subject not in frame or not in sight" % tag)
		return
	var img := await PlateSight.grab(self, 1)
	var path := ProjectSettings.globalize_path(OUT_REL + "/" + tag + ".png")
	img.save_png(path)
	_saved.append(path)
	print("PLATE saved ", path)


## The world bounds of every mesh of `bag` as drawn.
func _world_box(bag: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in bag.find_children("*", "MeshInstance3D", true, false):
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## One contact sheet of the saved plates, three across at a third of their size.
func _sheet() -> void:
	if _saved.is_empty():
		_invalid("no plate saved")
		return
	var first := Image.load_from_file(_saved[0])
	var w := first.get_width() / 3
	var h := first.get_height() / 3
	var rows := ceili(_saved.size() / 3.0)
	var sheet := Image.create(w * 3, h * rows, false, Image.FORMAT_RGBA8)
	for i in _saved.size():
		var img := Image.load_from_file(_saved[i])
		img.convert(Image.FORMAT_RGBA8)
		img.resize(w, h)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % 3) * w, (i / 3) * h))
	var path := ProjectSettings.globalize_path(OUT_REL + "/contact_sheet.png")
	sheet.save_png(path)
	print("PLATE sheet ", path)
