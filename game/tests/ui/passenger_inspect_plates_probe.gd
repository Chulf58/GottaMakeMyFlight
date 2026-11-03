extends SceneTree
## Windowed probe of the passenger inspect card and its thought pin in the real
## main.tscn (HUD 4/7, decision passenger-inspect-thoughts-recorded-at-sim-
## outcomes-saved-pin-marks-where).
##
## Run (one windowed Godot run project-wide; this probe holds the slot while it runs):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://tests/ui/passenger_inspect_plates_probe.gd
##
## main.tscn boots with a random sim seed (printed), the starter terminal (the
## HUD's debug button), a check-in agent and a security officer hired, and two
## plant pots put straight on the grid beside the first gate seats (a forced
## fixture that skips the wallet), then the 300-passenger debug batch as soon
## as a flight opens for passengers (it is refused before that). The sim
## is stepped by the clock's own advance() until one passenger has a long-queue
## thought and one a nice-decor thought. Plates, each proving its subject in
## frame (projected inside the viewport with a margin) and, for the floor spot,
## hit by a camera ray first (colliders on every visible mesh), else
## PROBE_INVALID:
##   card      the queued passenger selected: the card bottom-left with its
##             thoughts, clear of BuildMenu's centre column
##   coral     its long-queue thought clicked: the camera glides there and a
##             coral pin and floor spot mark where it was
##   green     the decor passenger's nice-decor thought clicked: a green pin
##   zoomed    the green pin from twice the home distance, still PIN_PX tall
##   roof      the same from far enough out that the roof shows: the pin is
##             drawn through it; the spot's ray result is printed, not required
##   panels    the card with the departures board shown and any alert cards up
## Plates go to tools/blender/out/passenger_inspect/.

const OUT_REL := "res://../tools/blender/out/passenger_inspect"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 120000
const TICK_LIMIT := 40000
const TICKS_PER_FRAME := 100
const GLIDE_FRAMES := 240

var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
var _plates: Array[Image] = []
var _main: Node3D
var _clock: SimClock
var _sim: PassengerSim
var _views: PassengerViews
var _hud: PassengerHud
var _inspect: PassengerInspect
var _rig: TycoonCamera
var _cam: Camera3D


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


## Guard thread: a frozen main thread never reaches _process, so check from here.
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
			OS.crash("passenger inspect probe hung")


func _run() -> void:
	await _boot()
	var found := await _thinkers()
	if not found.is_empty():
		await _plate_card(found["queue"])
		await _plate_pin("coral", found["queue"], PassengerThoughts.Kind.LONG_QUEUE, false)
		await _plate_pin("green", found["decor"], PassengerThoughts.Kind.NICE_DECOR, true)
		await _plate_far("zoomed", 2.0, true)
		await _plate_far("roof", 4.0, false)
		await _plate_panels()
	_sheet()
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _grab(file: String) -> void:
	await _frames(4)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	_plates.append(img)
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


# ------------------------------------------------------------ the world


func _boot() -> void:
	_beat("boot")
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_clock = _main.get_node("SimClock")
	var sim_seed := randi()
	_clock.seed_rng(sim_seed)
	print("PROBE sim_seed=", sim_seed)
	root.add_child(_main)
	_clock.set_process(false)
	_sim = _main.get_node("PassengerSim")
	_views = _main.get_node("PassengerViews")
	_hud = _main.get_node("PassengerHud")
	_inspect = _hud.find_child("PassengerInspect", true, false) as PassengerInspect
	_rig = _main.get_node("TycoonCamera")
	_cam = _main.get_node("TycoonCamera/Camera3D")
	var mode: BuildMode = _main.get_node("BuildMode")
	(mode.get_node("Ghost") as Node3D).visible = false
	_hud.press_starter_terminal()
	var staff: StaffSim = _main.get_node("Staff")
	staff.hire(StaffMember.Role.CHECKIN)
	staff.hire(StaffMember.Role.SECURITY)
	await _frames(4)
	_place_plants()
	await _frames(10)


## Two plant pots beside the first gate seats, put straight on the grid.
func _place_plants() -> void:
	var placed := 0
	var steps := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for seat: Dictionary in _sim.layout.seats:
		for step: Vector2i in steps:
			if placed >= 2:
				break
			var cell: Vector2i = seat["front"] + step
			var result := _sim.grid.apply(BuildEdit.place_object(&"plant_pot_1a", cell, 0))
			if result.ok:
				placed += 1
				print("PLANT at %s, calm there %d" % [cell, _sim.decor.net_calm_at(seat["front"])])
	if placed == 0:
		_invalid("no plant pot fits beside the gate seats")


func _tick() -> void:
	_clock.set_paused(false)
	_clock.advance(SimClock.STEP)
	_clock.set_paused(true)


## The ids of a passenger with a long-queue thought and one with a nice-decor
## thought, {"queue", "decor"}, or {} with PROBE_INVALID by TICK_LIMIT.
func _thinkers() -> Dictionary:
	var found := {}
	while _clock.tick < TICK_LIMIT:
		for i in TICKS_PER_FRAME:
			_tick()
		_beat("think %d" % _clock.tick)
		# The batch is refused until a flight opens for passengers.
		if _sim.last_batch_seed == 0:
			_hud.press_debug_spawn()
			if _sim.last_batch_seed != 0:
				print("BATCH tick=%d seed=%d" % [_clock.tick, _sim.last_batch_seed])
		for id in _sim.passenger_ids():
			var p := _sim.get_passenger(id)
			for entry in PassengerThoughts.entries(p):
				if entry["kind"] == PassengerThoughts.Kind.LONG_QUEUE and not found.has("queue"):
					found["queue"] = id
				if entry["kind"] == PassengerThoughts.Kind.NICE_DECOR and not found.has("decor"):
					found["decor"] = id
		if found.size() == 2:
			print("THINKERS tick=%d %s" % [_clock.tick, found])
			return found
		await process_frame
	_invalid("by tick %d found only %s" % [_clock.tick, found])
	return {}


func _select(id: int) -> void:
	_views.selected_id = id
	_rig.follow(_views.follow_anchor)
	_hud.refresh()


func _index_of(id: int, kind: PassengerThoughts.Kind) -> int:
	var entries := PassengerThoughts.entries(_sim.get_passenger(id))
	for i in entries.size():
		if entries[i]["kind"] == kind:
			return i
	return -1


# ------------------------------------------------------------ checks


func _prove_point(label: String, point: Vector3) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	if _cam.is_position_behind(point):
		_invalid("%s: behind the camera" % label)
		return false
	var s := _cam.unproject_position(point)
	var ok := rect.has_point(s)
	print("INFRAME %s screen=(%.0f, %.0f) ok=%s" % [label, s.x, s.y, ok])
	if not ok:
		_invalid("%s: leaves the viewport" % label)
	return ok


func _prove_card(label: String) -> bool:
	var view := root.get_visible_rect().size
	var card := _inspect.get_global_rect()
	var column := Rect2((view.x - BuildMenu.COLUMN_W) / 2.0, 0.0, BuildMenu.COLUMN_W, view.y)
	var inside := Rect2(Vector2.ZERO, view).grow(-MARGIN_PX).encloses(card)
	var dock := _main.get_node("BuildMenu").find_child("TemplatesDock", true, false) as Control
	var dock_rect := dock.get_global_rect() if dock != null else Rect2()
	var clear := not card.intersects(column) and not card.intersects(dock_rect)
	print(
		(
			"CARD %s rect=%s column=%s templates=%s inside=%s clear=%s rows=%s"
			% [label, card, column, dock_rect, inside, clear, _inspect.row_texts()]
		)
	)
	if not (_inspect.visible and inside and clear and _inspect.row_texts().size() > 0):
		_invalid(
			"%s: card hidden, off screen, over the build column or Templates, or empty" % label
		)
		return false
	return true


## A ray from the camera to the spot's centre hits the spot first.
func _spot_seen(label: String, required: bool) -> bool:
	for body in _main.find_children("ProbeBody", "StaticBody3D", true, false):
		body.free()
	var bodies := 0
	for mi: MeshInstance3D in _main.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.skin != null or not mi.is_visible_in_tree():
			continue
		var faces := mi.mesh.get_faces()
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var shape_node := CollisionShape3D.new()
		shape_node.shape = shape
		var body := StaticBody3D.new()
		body.name = "ProbeBody"
		body.add_child(shape_node)
		mi.add_child(body)
		bodies += 1
	await physics_frame
	await physics_frame
	var spot := _inspect.marker.get_node("Spot") as MeshInstance3D
	var centre := spot.global_position
	var from := _cam.global_position
	var space := _cam.get_world_3d().direct_space_state
	# The centre and 8 points round the disc: people standing on the cell can
	# cover part of it, so one clear ray is enough.
	var hits := 0
	var blockers := {}
	for i in 9:
		var target := centre
		if i > 0:
			var angle := TAU * (i - 1) / 8.0
			target += Vector3(cos(angle), 0.0, sin(angle)) * ThoughtMarker.SPOT_RADIUS_M * 0.8
		var query := PhysicsRayQueryParameters3D.create(
			from, target + (target - from).normalized() * 0.05
		)
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and spot.is_ancestor_of(hit["collider"]):
			hits += 1
		elif not hit.is_empty():
			var by := str((hit["collider"] as Node).get_parent().name)
			blockers[by] = int(blockers.get(by, 0)) + 1
	var seen := hits > 0
	print(
		"SPOT %s seen=%s hits=%d/9 blocked_by=%s bodies=%d" % [label, seen, hits, blockers, bodies]
	)
	if required and not seen:
		_invalid("%s: the floor spot is hidden behind %s" % [label, blockers])
	return seen


func _settle_glide() -> void:
	for i in GLIDE_FRAMES:
		if not _rig.is_gliding():
			break
		await process_frame
	print("GLIDE done=%s following=%s" % [not _rig.is_gliding(), _rig.is_following()])


# ------------------------------------------------------------ plates


func _plate_card(id: int) -> void:
	_beat("card")
	_select(id)
	await _frames(20)
	_prove_card("card")
	_prove_point("card passenger", _views.follow_anchor.global_position)
	await _grab("inspect_card.png")


func _plate_pin(label: String, id: int, kind: PassengerThoughts.Kind, positive: bool) -> void:
	_beat(label)
	_select(id)
	var index := _index_of(id, kind)
	if index < 0 or not _inspect.press_thought(index):
		_invalid("%s: no %s thought to click" % [label, PassengerThoughts.Kind.keys()[kind]])
		return
	await _settle_glide()
	await _frames(10)
	var want := ThoughtMarker.GREEN if positive else ThoughtMarker.CORAL
	print(
		(
			"PIN %s shown=%s colour=%s want=%s at=%s hint=%s"
			% [
				label,
				_inspect.marker.is_shown(),
				_inspect.marker.pin_colour(),
				want,
				_inspect.marker.global_position,
				_inspect.marked_text()
			]
		)
	)
	if not _inspect.marker.is_shown() or _inspect.marker.pin_colour() != want:
		_invalid("%s: the pin is not shown in its colour" % label)
	_prove_point("%s pin tip" % label, _inspect.marker.global_position)
	_prove_card(label)
	await _spot_seen(label, true)
	await _grab("inspect_pin_%s.png" % label)


func _plate_far(label: String, factor: float, spot_required: bool) -> void:
	_beat(label)
	_rig.target_distance = _rig.home_distance * factor
	for i in GLIDE_FRAMES:
		if absf(_rig.distance - _rig.target_distance) < 0.1:
			break
		await process_frame
	await _frames(10)
	print("DISTANCE %s %.1f (home %.1f)" % [label, _rig.distance, _rig.home_distance])
	_prove_point("%s pin tip" % label, _inspect.marker.global_position)
	await _spot_seen(label, spot_required)
	await _grab("inspect_pin_%s.png" % label)


func _plate_panels() -> void:
	_beat("panels")
	_rig.target_distance = _rig.home_distance
	var board := _hud.find_child("DeparturesBoard", true, false) as DeparturesBoard
	board.set_shown(true)
	_hud.refresh()
	await _frames(20)
	print("BOARD shown=%s rect=%s" % [board.is_shown(), board.get_global_rect()])
	_prove_card("panels")
	if _inspect.get_global_rect().intersects(board.get_global_rect()):
		_invalid("panels: the card overlaps the departures board")
	await _grab("inspect_panels.png")


func _sheet() -> void:
	if _plates.is_empty():
		return
	var sheet := Image.create(1920, 720, false, Image.FORMAT_RGBA8)
	for i in mini(_plates.size(), 6):
		var copy := _plates[i].duplicate() as Image
		copy.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(
			copy,
			Rect2i(Vector2i.ZERO, Vector2i(640, 360)),
			Vector2i((i % 3) * 640, floori(i / 3.0) * 360)
		)
	var path := _out_dir.path_join("inspect_contact_sheet.png")
	if sheet.save_png(path) != OK:
		_invalid("could not save %s" % path)
