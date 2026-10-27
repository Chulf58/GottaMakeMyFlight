extends SceneTree
## Windowed probe of the cafe in the real main scene (Cafe 2/2). The reference
## terminal stands on the Toon shell's doors B and C with a landside and an
## airside cafe beside it (CafeTestLayout, two tables each), built through the
## grid's own edits so the passenger sim sees them. Hungry passengers are
## spawned and the clock is stepped by hand; every CafeSim.paid is checked
## against the wallet (the balance must grow by exactly the amount paid, and
## the guest must have been served and seated first).
##
## Plates, each taken the first tick its moment happens: a guest ordering at a
## counter, a guest seated at a table, the '+$' pop over a counter, and a
## landside guest seated. Before a plate is saved its subject (the guest, or
## the pop) is projected into the frame clear of the HUD strips and a ray from
## the camera must reach it past the shell and the build pieces; otherwise the
## probe prints PROBE_INVALID and exits 1. A guard thread calls OS.crash() on
## a stall.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/cafe_plates_probe.gd
##
## Plates go to tools/blender/out/cafe/.

const OUT_REL := "res://../tools/blender/out/cafe"
const MARGIN_PX := 8.0
const TOP_HUD_PX := 56.0
const BOTTOM_HUD_PX := (
	BuildMenu.MARGIN
	+ BuildMenu.BAR_H
	+ BuildMenu.GAP
	+ BuildMenu.TRAY_H
	+ BuildMenu.GAP
	+ BuildMenu.STATUS_H
)
const DISTANCES := [9.0, 11.0, 13.0, 16.0, 20.0]
const TICKS_PER_FRAME := 4
const LAST_TICK := 1100
const HANG_MS := 90000
## Head height of a standing guest, and of a seated one.
const HEAD_M := 1.6
const SEATED_HEAD_M := 1.15
const SHOTS := ["order", "seated", "pop", "landside"]

var _out_dir := ""
var _failed := false
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _stop := false

var _sim: PassengerSim
var _wallet: Wallet
## Per paid visit: [passenger, room, amount, balance before, balance after,
## served, was seated, airside].
var _payments: Array = []
var _balance_seen := 0
## Passenger ids that reached CAFE_SEATED.
var _seated := {}
var _plates := {}
var _images: Array[Image] = []
## The passenger id the "pop" plate is about, set when a payment lands.
var _fresh_pop := 0


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	var main: Node3D = (load("res://main/main.tscn") as PackedScene).instantiate()
	var clock := main.get_node("SimClock") as SimClock
	var seed := randi()
	clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	root.add_child(main)
	clock.set_process(false)
	clock.set_paused(false)
	await _frames(3)
	var mode := main.get_node("BuildMode") as BuildMode
	mode.set_process(false)
	mode.set_tool(BuildMode.Tool.NONE)
	(mode.get_node("Ghost") as Node3D).visible = false
	_sim = main.get_node("PassengerSim") as PassengerSim
	_wallet = (main.get_node("Finances") as Finances).wallet
	print(
		"PROBE wallet_is_finances=%s start_balance=%d" % [_sim.wallet == _wallet, _wallet.balance]
	)
	if _sim.wallet != _wallet:
		_invalid("PassengerSim does not pay into the Finances wallet")
	_beat("build")
	var ids := CafeTestLayout.build(mode.grid, true, mode.shell)
	# Direct grid edits, like the starter terminal button: redraw the pieces.
	(mode.get_node("BuildView") as BuildView).refresh(mode.grid)
	await _frames(4)
	_sim.cafes.refresh()
	print("PROBE ids=%s usable_cafes=%d" % [ids, _sim.cafes.layout.cafes.size()])
	if _sim.cafes.layout.cafes.size() != 2:
		_invalid("expected two usable cafes")
	_sim.cafes.paid.connect(_on_paid)
	_sim.stage_changed.connect(_on_stage)
	# Six get hungry at once (landside, after check-in) and six about 15 s
	# later (mostly airside); the flight's own 24 arrive at random.
	for i in 12:
		var id := _sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
		_sim.get_passenger(id).hunger = 59 if i % 2 == 0 else 45
	var rig := main.get_node("TycoonCamera") as TycoonCamera
	var cam := rig.get_node("Camera3D") as Camera3D
	cam.make_current()
	print("PROBE viewport=%s" % root.get_visible_rect().size)
	while clock.tick < LAST_TICK and not (_plates.size() == SHOTS.size() and _both_sides_paid()):
		_beat("tick %d" % clock.tick)
		for i in TICKS_PER_FRAME:
			clock.advance(SimClock.STEP)
			var moment := _moment()
			if not moment.is_empty():
				await _plate(main, rig, cam, moment)
		await process_frame
	_report(ids)
	if _images.size() == SHOTS.size():
		_save(_contact_sheet(_images), "contact_sheet.png")
	print("PROBE done tick=%d failed=%s" % [clock.tick, _failed])
	_finish()
	quit(1 if _failed else 0)


## The first plate whose moment is happening now: [name, passenger id], or [].
func _moment() -> Array:
	var cafes := _sim.cafes
	for id in cafes.visit_ids():
		var p := _sim.get_passenger(id)
		var visit := cafes.visit_of(id)
		var long_seated := p.stage == Passenger.Stage.CAFE_SEATED and _sim.tick - p.stage_tick >= 10
		if not _plates.has("order") and p.stage == Passenger.Stage.CAFE_ORDER:
			return ["order", id]
		var landside := visit.resume_stage == Passenger.Stage.TO_SECURITY
		if not _plates.has("seated") and long_seated and not landside:
			return ["seated", id]
		if not _plates.has("landside") and long_seated and landside:
			return ["landside", id]
	if not _plates.has("pop") and _fresh_pop != 0:
		return ["pop", _fresh_pop]
	return []


func _plate(main: Node3D, rig: TycoonCamera, cam: Camera3D, moment: Array) -> void:
	var shot: String = moment[0]
	var id: int = moment[1]
	_plates[shot] = id
	_beat(shot)
	var views := _sim.get_parent().get_node("PassengerViews") as PassengerViews
	var subject := _subject_point(views, shot, id)
	var framed := false
	for d in DISTANCES:
		rig.position = subject * Vector3(1, 0, 1) + Vector3(0, 0, 0.5)
		rig.yaw = 0.35
		rig.distance = d
		rig.zoom(1.0)
		await _frames(8)
		subject = _subject_point(views, shot, id)
		if _in_frame(cam, subject, shot, false):
			framed = true
			break
	print(
		(
			"CAMERA %s pos=%s distance=%.1f pitch_deg=%.1f yaw=%.2f"
			% [shot, cam.global_position, rig.distance, -cam.rotation_degrees.x, rig.yaw]
		)
	)
	var p := _sim.get_passenger(id)
	print(
		(
			"SUBJECT %s passenger=%d stage=%s at=%s point=%s"
			% [shot, id, Passenger.Stage.keys()[p.stage], p.at, subject]
		)
	)
	var ok := framed and _in_frame(cam, subject, shot, true)
	# Built now, with the walls and shell cut away for this camera.
	var occluders := _colliders(main)
	await physics_frame
	await physics_frame
	ok = _visible(cam, subject, shot) and ok
	occluders.free()
	var img := await _grab()
	if ok:
		_save(img, "cafe_%s.png" % shot)
		_images.append(img)


## Where to look: the guest's head, or the pop label.
func _subject_point(views: PassengerViews, shot: String, id: int) -> Vector3:
	if shot == "pop":
		var labels := views.cafe_pops().live_labels()
		if labels.is_empty():
			_invalid("pop: no '+$' label on screen")
			return Vector3.ZERO
		return labels.back().global_position
	var node := views.node_for(id)
	if node == null:
		_invalid("%s: passenger %d has no view node" % [shot, id])
		return Vector3.ZERO
	var seated := shot != "order"
	return node.global_position + Vector3(0.0, SEATED_HEAD_M if seated else HEAD_M, 0.0)


func _in_frame(cam: Camera3D, point: Vector3, label: String, report: bool) -> bool:
	var size := root.get_visible_rect().size
	var rect := Rect2(
		Vector2(MARGIN_PX, TOP_HUD_PX), size - Vector2(MARGIN_PX * 2, TOP_HUD_PX + BOTTOM_HUD_PX)
	)
	var behind := cam.is_position_behind(point)
	var screen := cam.unproject_position(point)
	var ok := not behind and rect.has_point(screen)
	if report:
		print(
			(
				"INFRAME %s screen=(%.0f,%.0f) frame=%s behind=%s ok=%s"
				% [label, screen.x, screen.y, rect, behind, ok]
			)
		)
		if not ok:
			_invalid("%s: the subject leaves the frame" % label)
	return ok


## A ray from the camera to the subject must not hit the shell or a build
## piece more than 5 cm before it.
func _visible(cam: Camera3D, point: Vector3, label: String) -> bool:
	var space := cam.get_world_3d().direct_space_state
	var from := cam.global_position
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, point))
	var blocked := hit and from.distance_to(hit.position) < from.distance_to(point) - 0.05
	var blocker := str((hit.collider as Node).get_meta("mesh", "")) if blocked else ""
	print("VISIBLE %s clear=%s blocker=%s" % [label, not blocked, blocker])
	if blocked:
		_invalid("%s: the subject is hidden behind %s" % [label, blocker])
	return not blocked


func _on_stage(id: int, stage: Passenger.Stage) -> void:
	if stage == Passenger.Stage.CAFE_SEATED:
		_seated[id] = true


func _on_paid(id: int, room: int, amount: int) -> void:
	var visit := _sim.cafes.visit_of(id)
	var before := _balance_seen
	_balance_seen = _wallet.balance
	var airside := visit.resume_stage == Passenger.Stage.TO_GATE
	_payments.append(
		[id, room, amount, before, _wallet.balance, visit.served, _seated.has(id), airside]
	)
	print(
		(
			(
				"PAID passenger=%d room=%d amount=%d wallet_before=%d wallet_after=%d"
				+ " grew_by=%d served=%s seated=%s side=%s outcome=%s"
			)
			% [
				id,
				room,
				amount,
				before,
				_wallet.balance,
				_wallet.balance - before,
				visit.served,
				_seated.has(id),
				"airside" if airside else "landside",
				CafeVisit.Outcome.keys()[visit.outcome],
			]
		)
	)
	if _fresh_pop == 0:
		_fresh_pop = id


func _both_sides_paid() -> bool:
	var sides := {}
	for row in _payments:
		if row[5] and row[6]:
			sides[row[7]] = true
	return sides.size() == 2


func _report(ids: Dictionary) -> void:
	var full := 0
	var sides := {}
	for row in _payments:
		var grew: int = row[4] - row[3]
		var exact: bool = grew == row[2] and row[2] > 0
		if not exact:
			_invalid("passenger %d paid %d but the wallet grew by %d" % [row[0], row[2], grew])
		if exact and row[5] and row[6]:
			full += 1
			sides["airside" if row[7] else "landside"] = true
	print(
		(
			"PROBE summary payments=%d bought_sat_paid=%d sides=%s wallet=%d plates=%s rooms=%s"
			% [
				_payments.size(),
				full,
				sides.keys(),
				_wallet.balance,
				_plates,
				[ids["air_room"], ids["land_room"]],
			]
		)
	)
	if full == 0:
		_invalid("no passenger bought, sat and paid")
	if not (sides.has("airside") and sides.has("landside")):
		_invalid("expected paid visits on both sides, got %s" % [sides.keys()])
	for shot in SHOTS:
		if not _plates.has(shot):
			_invalid("no '%s' moment happened by tick %d" % [shot, LAST_TICK])


## The plates in a 2 x 2 sheet at half size.
func _contact_sheet(plates: Array[Image]) -> Image:
	var w := plates[0].get_width() / 2
	var h := plates[0].get_height() / 2
	var sheet := Image.create(w * 2, h * 2, false, Image.FORMAT_RGBA8)
	for i in plates.size():
		var small := plates[i].duplicate() as Image
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * (i % 2), h * (i / 2)))
	return sheet


## One static body per visible mesh of the shell and the build view (walls,
## counters, tables), in world space, for the visibility rays.
func _colliders(main: Node) -> Node3D:
	var holder := Node3D.new()
	holder.name = "ProbeColliders"
	root.add_child(holder)
	for owner_node in [main.get_node("Airside/Terminal"), main.get_node("BuildMode")]:
		for mi in owner_node.find_children("*", "MeshInstance3D", true, false):
			var inst := mi as MeshInstance3D
			if inst.is_visible_in_tree() and inst.mesh != null:
				_add_body(holder, inst.name, inst.mesh, [inst.global_transform])
		for mmi in owner_node.find_children("*", "MultiMeshInstance3D", true, false):
			var multi := mmi as MultiMeshInstance3D
			if not multi.is_visible_in_tree() or multi.multimesh == null:
				continue
			var mm := multi.multimesh
			var at: Array[Transform3D] = []
			var count := mm.instance_count
			if mm.visible_instance_count >= 0:
				count = mm.visible_instance_count
			for i in count:
				at.append(multi.global_transform * mm.get_instance_transform(i))
			_add_body(holder, multi.name, mm.mesh, at)
	print("PROBE occluder bodies=%d" % holder.get_child_count())
	return holder


func _add_body(holder: Node3D, label: String, mesh: Mesh, transforms: Array) -> void:
	if mesh == null:
		return
	var local_faces := mesh.get_faces()
	if local_faces.is_empty() or transforms.is_empty():
		return
	var faces := PackedVector3Array()
	for at: Transform3D in transforms:
		for p in local_faces:
			faces.append(at * p)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var shape_node := CollisionShape3D.new()
	shape_node.shape = shape
	var body := StaticBody3D.new()
	body.set_meta("mesh", label)
	body.add_child(shape_node)
	holder.add_child(body)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
		_beat(_stage)
	await RenderingServer.frame_post_draw


func _grab() -> Image:
	await _frames(4)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _beat(stage: String) -> void:
	_lock.lock()
	_stage = stage
	_beat_ms = Time.get_ticks_msec()
	_lock.unlock()


func _finish() -> void:
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_lock.lock()
		var stop := _stop
		var stage := _stage
		var silent := Time.get_ticks_msec() - _beat_ms
		_lock.unlock()
		if stop:
			return
		if silent > HANG_MS:
			print("PROBE_INVALID hang: stage=%s silent_ms=%d" % [stage, silent])
			OS.crash("cafe_plates_probe: main thread stalled in %s" % stage)
