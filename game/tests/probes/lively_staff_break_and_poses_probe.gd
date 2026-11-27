extends SceneTree
## Windowed Vulkan plate probe for Lively Staff 2/3 & 3/3
## (game/tests/probes/lively_staff_break_and_poses_probe.gd).
##
## Saves under tools/blender/out/lively_staff/:
##   - break_seat_six_axis.png   6-axis ortho seated character + armchair + 1 m cube
##   - break_room_seated_chat.png  2-3 staff seated in Break Room holding mug/phone/mag + bubble
##   - work_micro_reactions.png  5 work/lull micro-reaction poses side by side + 1 m cube
##   - contact_sheet.png         combined contact sheet
##
## Run (only when holding the single project-wide windowed Godot slot):
##   tools/godot.sh --display-driver windows --rendering-driver vulkan \
##     --audio-driver Dummy --path game -s res://tests/probes/lively_staff_break_and_poses_probe.gd

const PlateSight := preload("res://spike/plate_sight.gd")
const IntroClose := preload("res://spike/intro_close.gd")
const OUT_REL := "res://../tools/blender/out/lively_staff"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 60000
const WAIT_LIMIT_MS := 150000
const STALL_LIMIT_MS := 5000
const LIMIT_TICK := 4000
const MIN_SUBJECT_PX := 16.0
const SIX_AXIS := {
	"front": Vector3(0, 0, 1),
	"back": Vector3(0, 0, -1),
	"left": Vector3(-1, 0, 0),
	"right": Vector3(1, 0, 0),
	"top": Vector3(0, 1, 0),
	"bottom": Vector3(0, -1, 0),
}

var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
var _main: Node3D
var _cam: Camera3D
var _rig: TycoonCamera
var _clock: SimClock
var _sim: PassengerSim
var _staff: StaffSim
var _views: StaffCharacters
var _hud: PassengerHud
var _build: BuildMode
var _saved: Array[Image] = []


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_beat("init")
	_guard = Thread.new()
	_guard.start(_watch)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_beat(_stage)
	return false


func _beat(stage: String) -> void:
	_guard_mutex.lock()
	_stage = stage
	_heartbeat_ms = Time.get_ticks_msec()
	_guard_mutex.unlock()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_guard_mutex.lock()
		var stop := _guard_stop
		var idle_ms := Time.get_ticks_msec() - _heartbeat_ms
		var stage := _stage
		_guard_mutex.unlock()
		if stop:
			return
		if idle_ms > HANG_LIMIT_MS:
			print("PROBE_INVALID hang stage=%s no heartbeat for %d ms" % [stage, idle_ms])
			OS.crash("lively staff probe hung")


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _run() -> void:
	await _plate_break_seat_six_axis()
	await _boot()
	await _plate_break_room_seated_chat()
	await _plate_work_micro_reactions()
	if is_instance_valid(_main):
		_main.queue_free()
	await _frames(3)
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	if not _saved.is_empty():
		_save(_sheet(), "contact_sheet", false)
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _studio() -> Node3D:
	var studio := Node3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.86, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	studio.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	studio.add_child(sun)
	root.add_child(studio)
	return studio


func _cube(parent: Node, pos: Vector3) -> MeshInstance3D:
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.1)
	cube.material_override = mat
	cube.position = pos
	cube.name = "ReferenceCube1m"
	parent.add_child(cube)
	return cube


func _corners(box: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 8:
		out.append(box.get_endpoint(i))
	return out


func _prove_in_frame(cam: Camera3D, label: String, points: Array[Vector3]) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		if cam.is_position_behind(p):
			_invalid("%s: point %s is behind camera" % [label, p])
			return false
		var s := cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := rect.has_point(lo) and rect.has_point(hi)
	print("INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s" % [label, lo.x, lo.y, hi.x, hi.y, ok])
	if not ok:
		_invalid("%s: projected bounds leave viewport" % label)
	return ok


func _ortho_shown(cam: Camera3D, label: String, box: AABB, tag: String) -> bool:
	var space := cam.get_world_3d().direct_space_state
	var right := cam.global_basis.x
	var up := cam.global_basis.y
	var back := cam.global_basis.z
	var half_r := 0.0
	var half_u := 0.0
	for p in _corners(box):
		half_r = maxf(half_r, absf((p - box.get_center()).dot(right)))
		half_u = maxf(half_u, absf((p - box.get_center()).dot(up)))
	var on := 0
	var blockers: Array[String] = []
	for i in 3:
		for j in 3:
			var at := (
				box.get_center() + right * half_r * 0.3 * (i - 1) + up * half_u * 0.5 * (j - 1)
			)
			var lines := PlateSight.sight_lines(space, at + back * 500.0, [at], tag)
			on += (lines["on_subject"] as Array).size()
			blockers.append_array(lines["blockers"])
	var ok := on >= PlateSight.MIN_ON and blockers.is_empty()
	print("VISIBLE %s lines=9 on=%d blockers=%s ok=%s" % [label, on, blockers, ok])
	if not ok:
		_invalid("%s: subject occluded or missed" % label)
	return ok


func _ortho_size(cam: Camera3D, box: AABB) -> float:
	var inv := cam.global_transform.affine_inverse()
	var w := 0.0
	var h := 0.0
	for p in _corners(box):
		var local := inv * p - inv * box.get_center()
		w = maxf(w, absf(local.x) * 2.0)
		h = maxf(h, absf(local.y) * 2.0)
	var aspect := root.get_visible_rect().size.x / root.get_visible_rect().size.y
	return maxf(h, w / aspect) * 1.15


func _colliders(owners: Array[Node], subjects: Dictionary) -> Node3D:
	var holder := PlateSight.colliders(root, owners, subjects)
	var unbaked: Array = holder.get_meta("unbaked")
	if not unbaked.is_empty():
		_invalid("skinned meshes not baked: %s" % [unbaked])
	await physics_frame
	await physics_frame
	return holder


func _plate_break_seat_six_axis() -> void:
	_beat("break_seat_six_axis")
	var studio := _studio()
	var chair := BuildView.make_object_node(BuildCatalog.get_def(&"lounge_armchair"), null)
	chair.position = Vector3.ZERO
	studio.add_child(chair)
	var sitter: Node3D = StaffCharacters.CHARACTERS[0].instantiate()
	var root_off: Vector2 = ActivityPoses.ROOTS[&"lounge_armchair"][0]
	sitter.position = Vector3(root_off.x, 0.0, root_off.y)
	studio.add_child(sitter)
	var anim := sitter.get_node("AnimationPlayer") as AnimationPlayer
	anim.play("sit_idle")
	anim.seek(0.25, true)
	anim.speed_scale = 0.0
	(
		StaffStationPose
		. pose(
			sitter,
			StaffStationPose.Mode.BREAK_SEATED,
			1.0,
			60.0,
			Vector2.ZERO,
			1,
			StaffStationPose.SubMode.BREAK_COFFEE,
			0.0,
			StaffStationPose.Mode.NONE,
			StaffStationPose.SubMode.NONE,
			0.0,
			StaffMember.Role.CHECKIN,
		)
	)
	(
		StaffHandProps
		. update(
			sitter,
			StaffStationPose.Mode.BREAK_SEATED,
			StaffStationPose.SubMode.BREAK_COFFEE,
			1.0,
			60.0,
			1,
			false,
			false,
			StaffMember.Role.CHECKIN,
		)
	)
	await _frames(3)
	var holder := await _colliders([sitter], {sitter: "sitter"})
	var box: AABB = (holder.get_meta("bounds") as Dictionary).get("sitter", AABB())
	holder.free()
	var cube := _cube(studio, Vector3(1.5, 0.5, 1.5))
	var whole := box.merge(AABB(cube.position - Vector3.ONE * 0.5, Vector3.ONE))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.far = 1000.0
	studio.add_child(cam)
	cam.make_current()
	var keys := SIX_AXIS.keys()
	var sheet := Image.create(1920, 720, false, Image.FORMAT_RGBA8)
	var holder_sitter := await _colliders([studio], {sitter: "sitter"})
	for view_name: String in ["front", "top"]:
		var slot := keys.find(view_name)
		var dir: Vector3 = SIX_AXIS[view_name]
		var up := Vector3.FORWARD if absf(dir.y) > 0.5 else Vector3.UP
		cam.look_at_from_position(whole.get_center() + dir * 200.0, whole.get_center(), up)
		cam.size = _ortho_size(cam, whole)
		await _frames(3)
		var tag := "break_seat_" + view_name
		if _prove_in_frame(cam, tag, _corners(whole)) and _ortho_shown(cam, tag, box, "sitter"):
			var img := await PlateSight.grab(self)
			img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
			(
				sheet
				. blit_rect(
					img,
					Rect2i(0, 0, 640, 360),
					Vector2i((slot % 3) * 640, floori(slot / 3.0) * 360),
				)
			)
	holder_sitter.free()
	var holder_asm := await _colliders([studio], {sitter: "sitter", chair: "sitter"})
	var asm_box: AABB = (holder_asm.get_meta("bounds") as Dictionary).get("sitter", box)
	for view_name: String in ["back", "left", "right", "bottom"]:
		var slot := keys.find(view_name)
		var dir: Vector3 = SIX_AXIS[view_name]
		var up := Vector3.FORWARD if absf(dir.y) > 0.5 else Vector3.UP
		cam.look_at_from_position(whole.get_center() + dir * 200.0, whole.get_center(), up)
		cam.size = _ortho_size(cam, whole)
		await _frames(3)
		var tag := "break_seat_" + view_name
		if _prove_in_frame(cam, tag, _corners(whole)) and _ortho_shown(cam, tag, asm_box, "sitter"):
			var img := await PlateSight.grab(self)
			img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
			(
				sheet
				. blit_rect(
					img,
					Rect2i(0, 0, 640, 360),
					Vector2i((slot % 3) * 640, floori(slot / 3.0) * 360),
				)
			)
	_save(sheet, "break_seat_six_axis", true)
	holder_asm.free()
	studio.queue_free()
	await _frames(2)


func _boot() -> void:
	_beat("boot")
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var seed_val := IntroClose.seed_or_random()
	_clock.seed_rng(seed_val)
	print("PROBE sim_seed=", seed_val)
	root.add_child(_main)
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_sim = _main.get_node("PassengerSim")
	_staff = _main.get_node("Staff")
	_views = _main.get_node("StaffCharacters")
	_hud = _main.get_node("PassengerHud")
	_build = _main.get_node("BuildMode") as BuildMode
	await _frames(5)
	var err := IntroClose.close(_main)
	if err != "":
		_invalid(err)
	_hud.press_starter_terminal()
	_build.set_tool(BuildMode.Tool.NONE)
	var guide := _hud.get_node_or_null("UnlockGuide") as UnlockGuide
	if guide != null:
		guide.mode = UnlockGuide.Mode.OFF
		guide.close_for_modal()
	var offers := _main.get_node_or_null("OfferPanel") as OfferPanel
	if offers != null:
		offers.has_been_opened = true
		offers.close()
	await _frames(3)


func _build_break_room(rect: Rect2i) -> int:
	var grid := _build.grid
	var edits: Array[BuildEdit] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if grid.floor_at(Vector2i(x, y)) == BuildGrid.FLOOR_NONE:
				edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	edits.append(BuildEdit.place_room(rect, &"break_room"))
	for dx in range(0, rect.size.x - 1):
		edits.append(BuildEdit.place_wall(rect.position + Vector2i(dx, 0), BuildGrid.Side.NORTH))
	edits.append(BuildEdit.place_object(&"lounge_sofa", rect.position + Vector2i(0, 1), 0))
	edits.append(BuildEdit.place_object(&"lounge_armchair", rect.position + Vector2i(3, 1), 0))
	var room_id := 0
	for res: BuildResult in grid.apply_batch(edits):
		if not res.ok:
			_invalid("break room build failed: %s" % res.reason_text())
		if res.room_id != 0:
			room_id = res.room_id
	return room_id


func _until(stage: String, done: Callable) -> bool:
	_beat(stage)
	var start_ms := Time.get_ticks_msec()
	var moved_ms := start_ms
	var last_tick := _clock.tick
	while not done.call():
		var now_ms := Time.get_ticks_msec()
		if _clock.tick != last_tick:
			last_tick = _clock.tick
			moved_ms = now_ms
		if _clock.tick >= LIMIT_TICK:
			_invalid("%s: not met by tick %d" % [stage, LIMIT_TICK])
			return false
		if now_ms - start_ms > WAIT_LIMIT_MS:
			_invalid("%s: timeout" % stage)
			return false
		if now_ms - moved_ms > STALL_LIMIT_MS and not _clock.paused:
			_invalid("%s: clock stalled at %d" % [stage, last_tick])
			return false
		await process_frame
	return true


func _aim(at: Vector3, distance: float, yaw: float, step := TycoonCamera.AngleStep.LOW) -> void:
	_rig.stop_follow()
	_rig.angle_step = step
	_rig.set_pitch_degrees(TycoonCamera.STEP_PITCH_DEGREES[step], false)
	_rig.position = Vector3(at.x, 0.0, at.z)
	_rig.yaw = yaw
	_rig.distance = distance


func _plate_break_room_seated_chat() -> void:
	_beat("break_room_seated_chat")
	var off := ReferenceTerminal.offset_on(_build.grid)
	var rect := Rect2i(off + Vector2i(11, 13), Vector2i(5, 4))
	_build_break_room(rect)
	var ids: Array[int] = [
		_staff.hire(StaffMember.Role.CHECKIN),
		_staff.hire(StaffMember.Role.SECURITY),
		_staff.hire(StaffMember.Role.GATE),
	]
	_hud.press_speed(3)
	if not await _until(
		"break_hire_duty",
		func() -> bool:
			for id in ids:
				if _staff.get_member(id).state != StaffMember.State.ON_DUTY:
					return false
			return true
	):
		return
	for id in ids:
		_staff.get_member(id).energy = StaffMember.TIRED_THRESHOLD
	var room_center := _build.grid.cell_to_world(rect.position + Vector2i(2, 1))
	_aim(room_center + Vector3(0.0, 0.0, 0.8), 8.0, 0.28)
	if not await _until(
		"break_all_seated_chat",
		func() -> bool:
			for id in ids:
				if not bool(_views._break_views.get(id, {}).get("seated", false)):
					return false
				var clip := String(_views.node_for(id).get_meta(&"clip", ""))
				if clip != StaffCharacters.BREAK_SIT_IDLE_CLIP:
					return false
			for id in ids:
				if bool(_views._chat_state.get(id, {}).get("show_icon", false)):
					return true
			return false
	):
		return
	_hud.press_speed(0)
	var centre := Vector3.ZERO
	var subjects := {}
	for id in ids:
		var node := _views.node_for(id)
		centre += node.position
		subjects[node] = "staff_%d" % id
	centre /= float(ids.size())
	var cube := _cube(_main, centre + Vector3(-2.3, 0.5, 0.2))
	_aim(centre + Vector3(-0.3, 0.0, 0.7), 8.2, 0.22, TycoonCamera.AngleStep.LOW)
	await _frames(40)
	var saw_bubble := false
	for id in ids:
		var b := _views.node_for(id).get_node_or_null(StaffChatBubbles.SPRITE) as Sprite3D
		if b != null and b.visible:
			saw_bubble = true
			break
	if not saw_bubble:
		_invalid("break_room_seated_chat: no coworker chat bubble visible")
	_close_hud_popups()
	await _frames(2)
	paused = true
	var img := await PlateSight.grab(self)
	var twin := await PlateSight.hud_twin(self, _main)
	var bare: Image = twin["image"]
	var owners: Array[Node] = [_main.get_node("BuildMode"), _views]
	var holder := await _colliders(owners, subjects)
	var bounds: Dictionary = holder.get_meta("bounds")
	var frame := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	for id in ids:
		var tag := "staff_%d" % id
		var shown := PlateSight.person_shown(
			_cam, bounds.get(tag, AABB()), tag, frame, img, bare, MIN_SUBJECT_PX
		)
		print("BREAK_SHOWN %s %s" % [tag, shown])
		if not bool(shown.get("ok", false)):
			_invalid("break_room_seated_chat: %s not cleanly shown (%s)" % [tag, shown])
	var cube_box := AABB(cube.global_position - Vector3.ONE * 0.5, Vector3.ONE)
	_prove_in_frame(_cam, "break_room_cube", _corners(cube_box))
	_save(bare, "break_room_seated_chat", true)
	paused = false
	holder.free()
	cube.queue_free()


func _plate_work_micro_reactions() -> void:
	_beat("work_micro_reactions")
	var base := Vector3(-12.0, 0.0, 42.0)
	var cube := _cube(_main, base + Vector3(-1.8, 0.5, 0.2))
	var showcase := Node3D.new()
	showcase.name = "WorkReactionShowcase"
	_main.add_child(showcase)
	var floor_parts := InteriorKit.meshes("floor_tile")
	for gx in range(-2, 13):
		for gz in range(-2, 3):
			for part in floor_parts:
				var ft := MeshInstance3D.new()
				ft.mesh = part[0]
				ft.transform = (
					Transform3D(Basis.IDENTITY, base + Vector3(float(gx), 0.0, float(gz))) * part[1]
				)
				showcase.add_child(ft)
	var specs := [
		[
			StaffMember.Role.CHECKIN,
			StaffStationPose.Mode.REACTION_WAVE,
			StaffStationPose.SubMode.NONE,
			0.0,
			&"checkin_desk",
		],
		[
			StaffMember.Role.SHOP,
			StaffStationPose.Mode.REACTION_WIPE,
			StaffStationPose.SubMode.NONE,
			2.65,
			&"cafe_counter",
		],
		[
			StaffMember.Role.SECURITY,
			StaffStationPose.Mode.REACTION_STRETCH,
			StaffStationPose.SubMode.NONE,
			4.6,
			&"",
		],
		[
			StaffMember.Role.RAMP,
			StaffStationPose.Mode.REACTION_CLIPBOARD,
			StaffStationPose.SubMode.REACT_CLIPBOARD,
			6.1,
			&"",
		],
		[
			StaffMember.Role.GATE,
			StaffStationPose.Mode.REACTION_CHEER,
			StaffStationPose.SubMode.NONE,
			7.8,
			&"gate_desk",
		],
	]
	var actors: Array[Node3D] = []
	var subjects := {}
	for i in specs.size():
		var spec: Array = specs[i]
		var role := int(spec[0])
		var x_off := float(spec[3])
		var desk_id := StringName(spec[4])
		var actor: Node3D = StaffCharacters.CHARACTERS[role].instantiate()
		if StaffCharacters.UNIFORM_TINTS.has(role):
			StaffCharacters._apply_role_uniform(actor, role)
		actor.position = base + Vector3(x_off, 0.0, 0.0)
		showcase.add_child(actor)
		if desk_id != &"":
			var desk := BuildView.make_object_node(BuildCatalog.get_def(desk_id), null)
			var desk_off := Vector3(0.45, 0.0, 1.0)
			if desk_id == &"gate_desk":
				desk_off = Vector3(2.2, 0.0, 0.0)
			elif desk_id == &"cafe_counter":
				desk_off = Vector3(0.52, 0.0, 1.02)
			desk.position = actor.position + desk_off
			showcase.add_child(desk)
		var p := actor.get_node("AnimationPlayer") as AnimationPlayer
		p.play("idle")
		p.seek(0.0, true)
		p.speed_scale = 0.0
		(
			StaffStationPose
			. pose(
				actor,
				spec[1],
				1.0,
				52.0,
				Vector2.ZERO,
				i + 1,
				spec[2],
				0.0,
				StaffStationPose.Mode.NONE,
				StaffStationPose.SubMode.NONE,
				0.0,
				role,
			)
		)
		(
			StaffHandProps
			. update(
				actor,
				spec[1],
				spec[2],
				1.0,
				52.0,
				i + 1,
				false,
				false,
				role,
			)
		)
		actors.append(actor)
		subjects[actor] = "react_%d" % i
	var center := base + Vector3(3.4, 0.0, 0.7)
	_aim(center, 11.2, 0.0, TycoonCamera.AngleStep.MEDIUM)
	await _frames(40)
	_close_hud_popups()
	await _frames(2)
	paused = true
	var img := await PlateSight.grab(self)
	var twin := await PlateSight.hud_twin(self, _main)
	var bare: Image = twin["image"]
	var holder := await _colliders([showcase], subjects)
	var bounds: Dictionary = holder.get_meta("bounds")
	var frame := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	for i in actors.size():
		var tag := "react_%d" % i
		var shown := PlateSight.person_shown(
			_cam, bounds.get(tag, AABB()), tag, frame, img, bare, MIN_SUBJECT_PX
		)
		print("REACT_SHOWN %s %s" % [tag, shown])
		if not bool(shown.get("ok", false)):
			_invalid("work_micro_reactions: %s not cleanly shown (%s)" % [tag, shown])
	var cube_box := AABB(cube.global_position - Vector3.ONE * 0.5, Vector3.ONE)
	_prove_in_frame(_cam, "work_reactions_cube", _corners(cube_box))
	_save(bare, "work_micro_reactions", true)
	paused = false
	holder.free()
	showcase.queue_free()
	cube.queue_free()


func _close_hud_popups() -> void:
	for node in get_nodes_in_group(TopRow.SHEET_GROUP):
		if node.has_method("close"):
			node.close()
	var guide := _hud.get_node_or_null("UnlockGuide") as UnlockGuide
	if guide != null:
		guide.close_for_modal()


func _save(img: Image, plate_name: String, sheet := true) -> void:
	var path := _out_dir.path_join(plate_name + ".png")
	var err := img.save_png(path)
	if err != OK:
		_invalid("could not save %s (error %d)" % [path, err])
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
	if sheet:
		var copy := img.duplicate() as Image
		copy.convert(Image.FORMAT_RGBA8)
		_saved.append(copy)


func _sheet() -> Image:
	var w := 640
	var rows := (_saved.size() + 1) / 2
	var heights: Array[int] = []
	for img in _saved:
		heights.append(int(img.get_height() * w / float(img.get_width())))
	var row_h := 0
	for h in heights:
		row_h = maxi(row_h, h)
	var sheet := Image.create(w * 2, row_h * rows, false, Image.FORMAT_RGBA8)
	for i in _saved.size():
		var small := _saved[i].duplicate() as Image
		small.resize(w, heights[i], Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, heights[i]), Vector2i(w * (i % 2), row_h * (i / 2)))
	return sheet
