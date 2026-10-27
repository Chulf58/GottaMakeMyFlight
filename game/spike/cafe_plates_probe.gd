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
## landside guest seated. The scene is frozen for each plate. A guest is shown
## when its drawn body (skinned meshes baked in the pose drawn) is in the frame
## with a margin, at least one of nine sight lines (against every visible mesh
## of the shell, the build, the plane and the other passengers) lands on its
## own meshes with no blocker, and the HUD covers none of the landing points
## (the plate against a twin rendered with the HUD's canvas layers hidden).
## The pop ignores depth and has no mesh, so it is measured instead: the plate
## against a twin with the pop hidden must differ, the differing box must sit
## in the frame, no pixel of it may change when the HUD is hidden, and a second
## grab must match the first there. A plate that fails prints PROBE_INVALID and
## the probe exits 1. A guard thread calls OS.crash() on a stall.
##
## Run (one windowed Godot run project-wide; take the slot first); --ui-scale
## overrides the content scale from project.godot, and the plate names carry
## the scale:
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/cafe_plates_probe.gd -- --ui-scale=1.0
##
## Plates go to tools/blender/out/cafe/.

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/cafe"
const MARGIN_PX := 8.0
## Scene nodes whose visible meshes can hide a guest.
const OCCLUDER_OWNERS: Array[String] = [
	"Airside/Terminal", "BuildMode", "PlaneView", "PassengerViews"
]
## A guest drawn shorter than this (layout pixels) is too small to inspect.
const MIN_SUBJECT_PX := 16.0
## Half the size of the box searched for the pop's pixels, in layout pixels.
const POP_SEARCH_PX := Vector2(160.0, 80.0)
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
var _scale_tag := ""


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-scale="):
			root.content_scale_factor = float(arg.get_slice("=", 1))
	_scale_tag = "_s%.2f" % root.content_scale_factor
	print("PROBE ui_scale=%.2f" % root.content_scale_factor)
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
	_balance_seen = _wallet.balance
	_sim.cafes.paid.connect(_on_paid)
	_sim.stage_changed.connect(_on_stage)
	# Six get hungry at once (landside, after check-in) and six about 15 s
	# later (mostly airside); the flight's own 24 arrive at random.
	for i in 12:
		var id := _sim.spawn_now(FlightSim.DEFAULT_ID)
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
		_save(_contact_sheet(_images), "contact_sheet%s.png" % _scale_tag)
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
			"CAMERA %s%s pos=%s distance=%.1f pitch_deg=%.1f yaw=%.2f"
			% [
				shot,
				_scale_tag,
				cam.global_position,
				rig.distance,
				-cam.rotation_degrees.x,
				rig.yaw
			]
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
	# Freeze the scene, so the plate and its twins differ only by what each hides.
	paused = true
	var img: Image = await PlateSight.grab(self, 4)
	if shot == "pop":
		ok = await _pop_shown(main, cam, views, img, subject, id) and ok
	else:
		ok = await _guest_shown(main, cam, views, img, id, shot) and ok
	paused = false
	if ok:
		_save(img, "cafe_%s%s.png" % [shot, _scale_tag])
		_images.append(img)
	else:
		_invalid("%s: the subject is out of frame, hidden or under the HUD" % shot)
		_save(img, "cafe_%s_INVALID%s.png" % [shot, _scale_tag])


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


func _frame_rect() -> Rect2:
	return Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)


func _in_frame(cam: Camera3D, point: Vector3, label: String, report: bool) -> bool:
	var rect := _frame_rect()
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


## The guest's drawn body against every visible mesh of the occluder owners,
## in the frozen pose (PlateSight.person_shown).
func _guest_shown(
	main: Node3D, cam: Camera3D, views: PassengerViews, img: Image, id: int, shot: String
) -> bool:
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		owners.append(main.get_node(path))
	var subjects := {}
	var node := views.node_for(id)
	if node != null:
		subjects[node] = "guest"
	var holder := PlateSight.colliders(root, owners, subjects)
	var unbaked: Array = holder.get_meta("unbaked")
	var box: AABB = (holder.get_meta("bounds") as Dictionary).get("guest", AABB())
	print("PROBE occluder bodies=%d unbaked=%d" % [holder.get_child_count(), unbaked.size()])
	await physics_frame
	await physics_frame
	var twin: Dictionary = await PlateSight.hud_twin(self, main)
	var bare: Image = twin["image"]
	var changed := PlateSight.differing(img, bare, Rect2i(Vector2i.ZERO, img.get_size()), 4)
	var seen := PlateSight.person_shown(cam, box, "guest", _frame_rect(), img, bare, MIN_SUBJECT_PX)
	holder.free()
	print("HUD %s layers_hidden=%d plate_px_changed=%d" % [shot, twin["layers"], changed])
	print(
		(
			(
				"VISIBLE %s passenger=%d drawn=%s px=%s height_px=%.0f lines=9 on=%d past=%d"
				+ " blockers=%s in_frame=%s hud_px=%d ok=%s"
			)
			% [
				shot,
				id,
				box,
				seen.get("px"),
				seen.get("height_px", 0.0),
				seen["on"],
				seen["past"],
				seen["blockers"],
				seen.get("in_frame"),
				seen.get("hud_px", 0),
				seen["ok"]
			]
		)
	)
	if not unbaked.is_empty():
		print("PROBE skinned meshes not baked: %s" % [unbaked])
	return seen["ok"] and changed > 0 and unbaked.is_empty()


## The newest pop, measured in the plate: a twin with the pop hidden must
## differ inside a box around its anchor, the differing box must sit in the
## frame (and not reach the search box's edge, or the search cut it), none of
## it may change when the HUD is hidden, and a second grab must match the plate
## there (nothing else moved). Its text must be the payer's amount.
func _pop_shown(
	main: Node3D, cam: Camera3D, views: PassengerViews, img: Image, at: Vector3, payer: int
) -> bool:
	var labels := views.cafe_pops().live_labels()
	if labels.is_empty():
		return false
	var label: Label3D = labels.back()
	print("POP live_labels=%d" % labels.size())
	if labels.size() != 1:
		return false
	var per_screen := root.get_visible_rect().size.y / float(img.get_height())
	var anchor := cam.unproject_position(at)
	var search := PlateSight.to_screen(
		Rect2(anchor - POP_SEARCH_PX, POP_SEARCH_PX * 2.0), per_screen, img.get_size()
	)
	var again: Image = await PlateSight.grab(self, 4)
	var drift := PlateSight.differing(img, again, search, 1)
	label.visible = false
	var hidden: Image = await PlateSight.grab(self, 4)
	label.visible = true
	var box := PlateSight.differing_box(img, hidden, search)
	var drawn := PlateSight.differing(img, hidden, box, 1) if box.has_area() else 0
	var twin: Dictionary = await PlateSight.hud_twin(self, main)
	var bare: Image = twin["image"]
	var changed := PlateSight.differing(img, bare, Rect2i(Vector2i.ZERO, img.get_size()), 4)
	var under := PlateSight.differing(img, bare, box, 1) if box.has_area() else 0
	var layout := Rect2(Vector2(box.position) * per_screen, Vector2(box.size) * per_screen)
	var in_frame := box.has_area() and _frame_rect().encloses(layout)
	var cut := (
		box.position.x == search.position.x
		or box.position.y == search.position.y
		or box.end.x == search.end.x
		or box.end.y == search.end.y
	)
	var amount := -1
	for row in _payments:
		if row[0] == payer:
			amount = row[2]
	var text_ok := label.text == "+$%d" % amount
	var ok := drift == 0 and drawn > 0 and in_frame and not cut and under == 0 and changed > 0
	ok = ok and text_ok and label.modulate.a > 0.5
	print(
		(
			(
				'POP text="%s" payer_amount=%d alpha=%.2f search_screen=%s drawn_box_screen=%s'
				+ " drawn_px=%d drift_px=%d cut=%s in_frame=%s hud_px=%d plate_px_changed=%d ok=%s"
			)
			% [
				label.text,
				amount,
				label.modulate.a,
				search,
				box,
				drawn,
				drift,
				cut,
				in_frame,
				under,
				changed,
				ok
			]
		)
	)
	return ok


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


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
		_beat(_stage)
	await RenderingServer.frame_post_draw


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
