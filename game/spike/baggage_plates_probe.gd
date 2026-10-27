extends SceneTree
## Windowed plate probe for Baggage B3: bags riding the belt as BaggageViews
## draws them in the real main scene (article baggage-sim, board item "Baggage
## B3 windowed plate").
##
## Boots main.tscn with a new random sim seed (printed), builds the starter
## terminal with the HUD button, then a 3 x 3 bag room (RoomTool, as the Bag
## room tool marks it) at x 10..12, y 13..15 and one Belt line laid through
## BuildMode.lay_belt from (15, 10) to (10, 13). The line shapes itself into a
## corner behind desk A (14, 11), straights, a merge behind desk B (11, 11)
## that desk B feeds, a corner, straights and an end inside the bag room. It
## hires one check-in agent per desk and one officer per scanner (AirportGate
## opens the airport) and runs the real flights at 3x.
##
## Plates, each taken with the scene paused:
##   context_close  the whole line through the TycoonCamera, close, at the first
##                  moment with a bag resting on the end and two riding
##   context_far    the same moment from 40 m
##   six_axis_<kind>  for each of corner, merge, straight and rest, the first
##                  bag drawn on that piece (on a corner, only half way through
##                  it, where it turns): six orthographic views at true scale
##                  of the bag, its belt piece and the pieces it links to, and a
##                  1 m cube, drawn alone through a render layer (the HUD hidden)
## Checks printed for every plate: each bag's projected bounds inside the frame
## with a margin, sight lines that land on it (PlateSight, decision plates-
## probes-share-game-spike-plate-sight-gd-a-passenger-co), the gap between the
## bag's bottom and the belt and desk surfaces under a 5 x 5 grid on it,
## the spacing between riding bags, and that no bag waiting at its desk has a
## node. A failed check prints PROBE_INVALID and the probe exits 1. A guard
## thread calls OS.crash() on a stall (anti-pattern a-frame-counting-watchdog-
## cannot-catch-a-stuck-main-thread).
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/baggage_plates_probe.gd
##
## Plates go to tools/blender/out/baggage_plates/.

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/baggage_plates"
const MAIN_SCENE := "res://main/main.tscn"
const ROOM := Rect2i(10, 13, 3, 3)
const LINE_FROM := Vector2i(15, 10)
const LINE_TO := Vector2i(10, 13)
## The piece each belt cell must have taken.
const SHAPES := {
	Vector2i(15, 10): &"baggage_belt_corner",
	Vector2i(14, 10): &"baggage_belt",
	Vector2i(13, 10): &"baggage_belt",
	Vector2i(12, 10): &"baggage_belt_feed",
	Vector2i(11, 10): &"baggage_belt",
	Vector2i(10, 10): &"baggage_belt_corner",
	Vector2i(10, 11): &"baggage_belt",
	Vector2i(10, 12): &"baggage_belt",
	Vector2i(10, 13): &"baggage_belt_end",
}
const KIND_OF := {
	&"baggage_belt_corner": "corner",
	&"baggage_belt_feed": "merge",
	&"baggage_belt": "straight",
}
const KINDS: Array[String] = ["corner", "merge", "straight", "rest"]
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 60000
const TOTAL_LIMIT_MS := 600000
const WAIT_LIMIT_MS := 300000
const STALL_LIMIT_MS := 8000
const TICK_LIMIT := 30000
## A bag this close to a corner's centre along the sim's path is plated as the
## corner subject.
const CORNER_NEAR_MM := 100
## Render layer 20: the six-axis camera sees only the subject.
const SUBJECT_LAYER := 1 << 19
## Physics layer 21: the bodies the sit check's rays may hit.
const SIT_LAYER := 1 << 20
const ORTHO_SIZE := 3.6
## The cube's centre from the bag's cell centre: off both axes, so no axis view
## puts it in front of the bag.
const CUBE_OFFSET := Vector3(1.25, 0.5, 1.25)
const SIX_AXIS := {
	"front": Vector3(0, 0, 1),
	"back": Vector3(0, 0, -1),
	"left": Vector3(-1, 0, 0),
	"right": Vector3(1, 0, 0),
	"top": Vector3(0, 1, 0),
	"bottom": Vector3(0, -1, 0),
}
const TILE := Vector2i(960, 540)
## A bag drawn shorter than this in the close context plate cannot be judged.
const MIN_BAG_PX := 10.0
## A bag's bottom may sit this far above or below the belt surface under it.
const SIT_TOLERANCE_M := 0.02
const OCCLUDER_OWNERS: Array[String] = [
	"Airside/Terminal", "BuildMode", "PlaneView", "PassengerViews", "BaggageViews"
]

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
var _hud: PassengerHud
var _build: BuildMode
var _sim: BaggageSim
var _views: BaggageViews
var _grid: BuildGrid
var _done := {}
var _sheet: Array[Image] = []
var _at_desk_max := 0
var _at_desk_drawn := 0


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
		# The total limit also ends a run whose coroutine died on a script error
		# while _process kept beating.
		var total_ms := Time.get_ticks_msec()
		if idle_ms > HANG_LIMIT_MS or total_ms > TOTAL_LIMIT_MS:
			print(
				(
					"PROBE_INVALID hang stage=%s no heartbeat for %d ms, %d ms in all"
					% [stage, idle_ms, total_ms]
				)
			)
			OS.crash("baggage plates probe hung")


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	await _boot()
	if not _failed:
		await _plates()
	print(
		(
			"DESK_HIDDEN at_desk_max=%d at_desk_drawn=%d ok=%s"
			% [_at_desk_max, _at_desk_drawn, _at_desk_max > 0 and _at_desk_drawn == 0]
		)
	)
	# Control: a bag must have been seen waiting, or the check proved nothing.
	if _at_desk_max == 0 or _at_desk_drawn != 0:
		_invalid("no bag seen waiting at a desk, or one waiting was drawn")
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	if not _sheet.is_empty():
		_save(_contact_sheet(), "contact_sheet", false)
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _boot() -> void:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var seed := randi()
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	root.add_child(_main)
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_hud = _main.get_node("PassengerHud")
	_build = _main.get_node("BuildMode")
	_sim = _main.get_node("BaggageSim")
	_views = _main.get_node("BaggageViews")
	_grid = _build.grid
	await _frames(5)
	_hud.press_starter_terminal()
	var room := RoomTool.mark(_grid, ROOM, &"bag_room", _build.wallet())
	print("BUILD bag_room ok=%s reason=%s" % [room.ok, room.reason_text()])
	if not room.ok:
		_invalid("the bag room was refused")
		return
	(_build.get_node("BuildView") as BuildView).refresh(_grid)
	_build.set_tool(BuildMode.Tool.BELT)
	var belt := _build.lay_belt(LINE_FROM, LINE_TO)
	_build.set_tool(BuildMode.Tool.NONE)
	print("BUILD belt ok=%s reason=%s" % [belt.ok, belt.reason_text()])
	if not belt.ok:
		_invalid("the belt line was refused")
		return
	for cell in SHAPES:
		var def := StringName(_grid.get_object(_grid.object_at(cell)).get("def", ""))
		print("SHAPE %s %s" % [cell, def])
		if def != SHAPES[cell]:
			_invalid("%s took %s, expected %s" % [cell, def, SHAPES[cell]])
	var status := RoomRules.status(_grid, _grid.room_at(ROOM.position))
	print("ROOM bag_room headline=%s" % status.headline())
	if not status.ok:
		_invalid("the bag room is not ready")
	await _frames(2)
	var staff := _main.get_node("Staff") as StaffSim
	# An unstaffed desk or scanner is closed: one member per station.
	var desks := 0
	var scanners := 0
	for object_id in _grid.object_ids():
		match StringName(_grid.get_object(object_id)["def"]):
			&"checkin_desk":
				desks += 1
				staff.hire(StaffMember.Role.CHECKIN)
			&"security_scanner":
				scanners += 1
				staff.hire(StaffMember.Role.SECURITY)
	print("PROBE desks=%d scanners=%d hired=%d" % [desks, scanners, staff.member_ids().size()])
	if desks != 2 or staff.member_ids().is_empty():
		_invalid("expected two desks and hired staff")
	_hud.press_speed(3)


## Waits for each moment in turn: first a bag resting on the end with two
## riding (context plates and a six-axis sheet for each kind on show), then
## each kind still missing.
func _plates() -> void:
	var first := func() -> bool: return _kinds().has("rest") and _riding().size() >= 2
	if not await _until("first moment", first):
		return
	await _freeze()
	await _context()
	await _six_axis_all()
	_thaw()
	while _done.size() < KINDS.size():
		var fresh := func() -> bool:
			for kind in _kinds():
				if not _done.has(kind):
					return true
			return false
		if not await _until("kinds %s" % [_done.keys()], fresh):
			return
		await _freeze()
		await _six_axis_all()
		_thaw()


## Steps frames until `done` holds, counting bags waiting at a desk on the way.
## Fails when the sim passes TICK_LIMIT, the wait passes WAIT_LIMIT_MS or the
## clock stalls.
func _until(stage: String, done: Callable) -> bool:
	_beat(stage)
	var start_ms := Time.get_ticks_msec()
	var moved_ms := start_ms
	var last_tick := _clock.tick
	while not done.call():
		_count_desk_bags()
		var now_ms := Time.get_ticks_msec()
		if _clock.tick != last_tick:
			last_tick = _clock.tick
			moved_ms = now_ms
		if _clock.tick >= TICK_LIMIT:
			_invalid("%s: not met by tick %d" % [stage, TICK_LIMIT])
			return false
		if now_ms - start_ms > WAIT_LIMIT_MS:
			_invalid("%s: not met in %d ms (tick %d)" % [stage, WAIT_LIMIT_MS, _clock.tick])
			return false
		if now_ms - moved_ms > STALL_LIMIT_MS:
			_invalid("%s: clock stalled at tick %d" % [stage, last_tick])
			return false
		await process_frame
	_count_desk_bags()
	return true


func _count_desk_bags() -> void:
	var waiting := 0
	for bag in _sim.bags():
		if bag.state == Bag.State.AT_DESK:
			waiting += 1
			if _views.node_for(bag.id) != null:
				_at_desk_drawn += 1
	_at_desk_max = maxi(_at_desk_max, waiting)


func _freeze() -> void:
	_hud.press_speed(0)
	await _frames(3)
	print(
		(
			"MOMENT tick=%d bags=%d drawn=%d kinds=%s"
			% [_clock.tick, _sim.bags().size(), _views.active_count(), _kinds().keys()]
		)
	)
	_spacing()


func _thaw() -> void:
	_hud.press_speed(3)


## Drawn riding bags (on a belt), by id.
func _riding() -> Array[int]:
	var out: Array[int] = []
	for bag in _sim.bags():
		if bag.on_belt() and _views.node_for(bag.id) != null:
			out.append(bag.id)
	return out


## Kind -> the first drawn bag on show as that kind ("rest" for a bag on an end).
func _kinds() -> Dictionary:
	var out := {}
	for bag in _sim.bags():
		var node := _views.node_for(bag.id)
		if node == null:
			continue
		var kind := "rest"
		if bag.on_belt():
			var cell := _grid.world_to_cell(node.position)
			var record := _grid.get_object(_grid.object_at(cell))
			kind = KIND_OF.get(StringName(record.get("def", "")), "")
			# A corner counts only half way through it on the sim's path (within
			# CORNER_NEAR_MM of its centre), where the bag turns and its body
			# reaches furthest toward the outer rail.
			if kind == "corner":
				var leaving := _grid.get_object(_grid.object_at(bag.cell - bag.from_step))
				var at_centre: bool = (
					(bag.cell == cell and bag.remain_mm <= CORNER_NEAR_MM)
					or (
						bag.cell != cell
						and leaving.get("def", "") == BeltShaper.CORNER
						and bag.remain_mm >= Bag.CELL_MM - CORNER_NEAR_MM
					)
				)
				if not at_centre:
					kind = ""
		if kind != "" and not out.has(kind):
			out[kind] = bag.id
	return out


## Centre-to-centre distance from each riding bag to the nearest other one.
func _spacing() -> void:
	var ids := _riding()
	var gaps := PackedStringArray()
	for id in ids:
		var near := INF
		for other in ids:
			if other != id:
				near = minf(
					near, _views.node_for(id).position.distance_to(_views.node_for(other).position)
				)
		gaps.append("%d:%.2f" % [id, near])
	print("SPACING riding=%d nearest_m=%s" % [ids.size(), ", ".join(gaps)])


# ------------------------------------------------------------ context plates


func _context() -> void:
	var ids: Array[int] = []
	for bag in _sim.bags():
		if _views.node_for(bag.id) != null:
			ids.append(bag.id)
	var centre := Vector3.ZERO
	for cell in SHAPES:
		centre += _grid.cell_to_world(cell)
	centre /= SHAPES.size()
	var need := mini(3, ids.size())
	var best := {}
	for turn in 4:
		var yaw := wrapf(PI + turn * PI / 2.0, -PI, PI)
		_aim(centre, 9.0, yaw)
		await _frames(20)
		print("PLATE context_close tick=%d bags=%d yaw=%.2f" % [_clock.tick, ids.size(), yaw])
		var result := await _shown(ids, MIN_BAG_PX)
		print("SHOWN context_close shown=%d need=%d" % [result["shown"], need])
		if best.is_empty() or result["shown"] > best["shown"]:
			best = result
		if result["shown"] >= need:
			break
	_save(best["image"], "context_close")
	if best["shown"] < need:
		_invalid("context_close: %d of %d bags shown from every side" % [best["shown"], need])
	_aim(centre, 40.0, best["yaw"])
	await _frames(20)
	print("PLATE context_far tick=%d bags=%d yaw=%.2f" % [_clock.tick, ids.size(), best["yaw"]])
	var far := await _shown(ids, 0.0)
	print("SHOWN context_far shown=%d need=1" % far["shown"])
	_save(far["image"], "context_far")
	if far["shown"] < 1:
		_invalid("context_far: no bag shown")


func _aim(at: Vector3, distance: float, yaw: float) -> void:
	_rig.stop_follow()
	_rig.position = Vector3(at.x, 0.0, at.z)
	_rig.yaw = yaw
	_rig.distance = distance


## Grabs the plate and checks each bag with PlateSight.person_shown (nine sight
## lines to the bag's upper half, against every visible mesh of the scene).
func _shown(ids: Array[int], min_px: float) -> Dictionary:
	paused = true
	var img: Image = await PlateSight.grab(self)
	var subjects := {}
	for id in ids:
		subjects[_views.node_for(id)] = str(id)
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		owners.append(_main.get_node(path))
	var holder := PlateSight.colliders(root, owners, subjects)
	var bounds: Dictionary = holder.get_meta("bounds")
	await physics_frame
	await physics_frame
	var twin: Dictionary = await PlateSight.hud_twin(self, _main)
	var bare: Image = twin["image"]
	var shown := 0
	for id in ids:
		var box: AABB = bounds.get(str(id), AABB())
		var seen := PlateSight.person_shown(_cam, box, str(id), _frame(), img, bare, min_px)
		print(
			(
				(
					"VISIBLE bag=%d state=%d drawn=%s px=%s height_px=%.0f on=%d past=%d"
					+ " blockers=%s in_frame=%s hud_px=%d ok=%s"
				)
				% [
					id,
					_sim.get_bag(id).state,
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
		shown += int(seen["ok"])
	holder.free()
	paused = false
	return {"shown": shown, "image": img, "yaw": _rig.yaw}


# ------------------------------------------------------------ six-axis plates


func _six_axis_all() -> void:
	var kinds := _kinds()
	for kind in KINDS:
		if kinds.has(kind) and not _done.has(kind):
			_done[kind] = true
			await _six_axis(kind, kinds[kind])


## Six orthographic views of the bag, the piece under it, the pieces it links
## to and a 1 m cube, the HUD hidden and the camera seeing only those.
func _six_axis(kind: String, id: int) -> void:
	_beat("six_axis_" + kind)
	paused = true
	var node := _views.node_for(id)
	var cell := _grid.world_to_cell(node.position)
	var pieces: Array[Node3D] = []
	for step in [Vector2i.ZERO] + BuildGrid.SIDE_STEP:
		var near := _piece_node(cell + step)
		if near != null:
			pieces.append(near)
	if pieces.is_empty() or pieces[0] != _piece_node(cell):
		pieces.clear()
	await _sit(kind, id, node, pieces)
	var subjects: Array[Node3D] = [node]
	subjects.append_array(pieces)
	var cube := _cube(_grid.cell_to_world(cell) + CUBE_OFFSET)
	subjects.append(cube)
	var layers := {}
	for subject in subjects:
		for vi in _visuals(subject):
			layers[vi] = vi.layers
			vi.layers = SUBJECT_LAYER
	var hidden: Array[CanvasLayer] = []
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		if (layer as CanvasLayer).visible:
			(layer as CanvasLayer).visible = false
			hidden.append(layer)
	var owners: Array[Node] = []
	owners.assign(subjects)
	var holder := PlateSight.colliders(root, owners, {node: "bag"})
	var bag_box: AABB = (holder.get_meta("bounds") as Dictionary).get("bag", AABB())
	var cube_box := AABB(cube.global_position - Vector3.ONE * 0.5, Vector3.ONE)
	var eye := Camera3D.new()
	root.add_child(eye)
	eye.projection = Camera3D.PROJECTION_ORTHOGONAL
	eye.size = ORTHO_SIZE
	eye.cull_mask = SUBJECT_LAYER
	eye.near = 0.05
	eye.far = 40.0
	eye.make_current()
	await physics_frame
	await physics_frame
	var sheet := Image.create(TILE.x * 3, TILE.y * 2, false, Image.FORMAT_RGBA8)
	var view_centre := (bag_box.get_center() + cube_box.get_center()) / 2.0
	var slot := 0
	for axis in SIX_AXIS:
		var back: Vector3 = SIX_AXIS[axis]
		eye.global_position = view_centre + back * 10.0
		eye.look_at(view_centre, Vector3.FORWARD if absf(back.y) > 0.5 else Vector3.UP)
		var img: Image = await PlateSight.grab(self, 4)
		var label := "six_axis_%s_%s" % [kind, axis]
		var framed := _in_frame(eye, label + " bag", bag_box)
		framed = _in_frame(eye, label + " cube", cube_box) and framed
		var on := _ortho_lines(eye, label, bag_box, back)
		# From above at least MIN_ON lines must land; from the sides the rails
		# and the end's walls may hide all but the top of the bag, so one does.
		# From below the belt hides it, so that view is printed only.
		var need := PlateSight.MIN_ON if axis == "top" else 1
		if axis != "bottom" and (not framed or on < need):
			_invalid("%s: bag not in frame or not seen (%d lines on it)" % [label, on])
		_save(img, label, false)
		var copy := img.duplicate() as Image
		copy.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(
			copy, Rect2i(Vector2i.ZERO, TILE), Vector2i(slot % 3, floori(slot / 3.0)) * TILE
		)
		slot += 1
	_save(sheet, "six_axis_%s_sheet" % kind)
	holder.free()
	eye.queue_free()
	cube.queue_free()
	_cam.make_current()
	for vi in layers:
		(vi as VisualInstance3D).layers = layers[vi]
	for layer in hidden:
		layer.visible = true
	paused = false
	await _frames(2)


## Nine lines along the view axis to a 3 x 3 grid on the bag's camera-facing
## face; returns how many land on the bag first. In a side view the rails may
## cover the bag's lower part, so blockers are printed, not failed.
func _ortho_lines(eye: Camera3D, label: String, box: AABB, back: Vector3) -> int:
	var space := eye.get_world_3d().direct_space_state
	# The two axes across the view: x and up from the front or back, z and up
	# from the side, x and z from above or below.
	var u := Vector3.RIGHT
	var v := Vector3.UP
	if absf(back.x) > 0.5:
		u = Vector3.BACK
	elif absf(back.y) > 0.5:
		v = Vector3.BACK
	var centre := box.get_center()
	var on := 0
	var past := 0
	var blockers: Array[String] = []
	for i in 3:
		for j in 3:
			var at := (
				centre
				+ u * (0.6 * (i - 1)) * box.size.dot(u) / 2.0
				+ v * (0.6 * (j - 1)) * box.size.dot(v) / 2.0
			)
			var targets: Array[Vector3] = [at]
			var lines := PlateSight.sight_lines(space, at + back * 5.0, targets, "bag")
			on += (lines["on_subject"] as Array).size()
			past += int(lines["past"])
			blockers.append_array(lines["blockers"])
	print("LINES %s on=%d past=%d blockers=%s" % [label, on, past, blockers])
	return on


func _in_frame(eye: Camera3D, label: String, box: AABB) -> bool:
	var rect := _frame()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var s := eye.unproject_position(box.get_endpoint(i))
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := rect.has_point(lo) and rect.has_point(hi)
	print(
		(
			"INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) size_px=(%.0f,%.0f) ok=%s"
			% [label, lo.x, lo.y, hi.x, hi.y, hi.x - lo.x, hi.y - lo.y, ok]
		)
	)
	return ok


## How the bag sits on the piece under it: the bag's drawn bounds against the
## piece's surface straight below the bag's centre (a ray onto the piece alone).
func _sit(kind: String, id: int, node: Node3D, pieces: Array[Node3D]) -> void:
	var owners: Array[Node] = [node]
	var bag_holder := PlateSight.colliders(root, owners, {node: "bag"})
	var box: AABB = (bag_holder.get_meta("bounds") as Dictionary).get("bag", AABB())
	bag_holder.free()
	var floor_y := _grid.origin.y
	var bag := _sim.get_bag(id)
	var tilt := rad_to_deg(node.global_basis.y.angle_to(Vector3.UP))
	var along := node.global_basis.z
	print(
		(
			(
				"BAG %s id=%d state=%d cell=%s step=%s remain=%d origin=%s origin_above_floor=%.3f"
				+ " size=%s length_axis=%s tilt_deg=%.1f"
			)
			% [
				kind,
				id,
				bag.state,
				bag.cell,
				bag.from_step,
				bag.remain_mm,
				node.global_position,
				node.global_position.y - floor_y,
				box.size,
				along,
				tilt
			]
		)
	)
	if pieces.is_empty():
		_invalid("%s: no piece drawn under bag %d" % [kind, id])
		return
	var piece := pieces[0]
	var piece_owners: Array[Node] = []
	piece_owners.assign(pieces)
	# The desks too: a bag coming off a desk still lies half on its outlet.
	for child in _build.get_node("BuildView").get_children():
		if child.has_meta("record") and child.get_meta("record")["def"] == &"checkin_desk":
			piece_owners.append(child)
	var holder := PlateSight.colliders(root, piece_owners, {})
	# Rays below hit only these bodies, never anything else in the world.
	for body in holder.get_children():
		(body as StaticBody3D).collision_layer = SIT_LAYER
	await physics_frame
	await physics_frame
	var space := piece.get_world_3d().direct_space_state
	var centre := box.get_center()
	var hit := space.intersect_ray(_down_ray(centre, floor_y))
	# A 5 x 5 grid over the bag's bottom face (its own frame), each point
	# against the surface straight below it on the belts and desks near the
	# bag: a negative gap past the tolerance is a rail or wall inside the bag,
	# a positive one a bag part held up off its surface, and a point with
	# nothing below it hangs over the floor.
	var local := _local_box(node)
	var profile := PackedStringArray()
	var worst := INF
	var highest := -INF
	var off_piece := 0
	for i in 5:
		for j in 5:
			var at := Vector3(i / 4.0, 0.0, j / 4.0)
			var p: Vector3 = node.global_transform * (local.position + local.size * at)
			var down := space.intersect_ray(_down_ray(p, floor_y))
			if down.is_empty():
				off_piece += 1
				profile.append("(%.2f,%.2f):none" % [at.x, at.z])
				continue
			var under: float = p.y - (down["position"] as Vector3).y
			worst = minf(worst, under)
			highest = maxf(highest, under)
			profile.append("(%.2f,%.2f):%.3f" % [at.x, at.z, under])
	holder.free()
	print(
		(
			"FOOTPRINT %s bag=%d points=25 off_piece=%d lowest=%.3f highest=%.3f gaps=%s"
			% [kind, id, off_piece, worst, highest, ", ".join(profile)]
		)
	)
	if worst < -SIT_TOLERANCE_M or highest > SIT_TOLERANCE_M or off_piece > 0:
		_invalid("%s: bag %d crosses a rail, floats or hangs off the belt" % [kind, id])
	if hit.is_empty():
		_invalid("%s: no piece surface under bag %d" % [kind, id])
		return
	var surface: float = (hit["position"] as Vector3).y
	var gap := box.position.y - surface
	var record: Dictionary = piece.get_meta("record")
	print(
		(
			(
				"SIT %s bag=%d piece=%s facing=%d surface_above_floor=%.3f bag_bottom_above_floor=%.3f"
				+ " gap=%.3f"
			)
			% [
				kind,
				id,
				record["def"],
				record["facing"],
				surface - floor_y,
				box.position.y - floor_y,
				gap
			]
		)
	)
	if kind != "rest" and absf(gap) > SIT_TOLERANCE_M:
		_invalid("%s: bag %d sits %.3f m off the belt surface" % [kind, id, gap])


## A ray straight down through `at` from 2 m above the floor to under it,
## against the sit check's bodies only.
func _down_ray(at: Vector3, floor_y: float) -> PhysicsRayQueryParameters3D:
	var ray := PhysicsRayQueryParameters3D.create(
		Vector3(at.x, floor_y + 2.0, at.z), Vector3(at.x, floor_y - 0.1, at.z)
	)
	ray.collision_mask = SIT_LAYER
	return ray


## The bounds of `node`'s meshes in its own frame.
func _local_box(node: Node3D) -> AABB:
	var to_local := node.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for vi in _visuals(node):
		var mi := vi as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var b: AABB = (to_local * mi.global_transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _piece_node(cell: Vector2i) -> Node3D:
	var view := _build.get_node("BuildView") as BuildView
	for child in view.get_children():
		if child.has_meta("record"):
			var record: Dictionary = child.get_meta("record")
			if record["anchor"] == cell and BuildCatalog.is_belt(record["def"]):
				return child
	return null


func _visuals(node: Node) -> Array[VisualInstance3D]:
	var out: Array[VisualInstance3D] = []
	if node is VisualInstance3D:
		out.append(node)
	for vi in node.find_children("*", "VisualInstance3D", true, false):
		out.append(vi)
	return out


func _cube(centre: Vector3) -> MeshInstance3D:
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.8, 0.78)
	cube.material_override = mat
	root.add_child(cube)
	cube.global_position = Vector3(centre.x, _grid.origin.y + 0.5, centre.z)
	return cube


func _frame() -> Rect2:
	return Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)


func _save(img: Image, name: String, sheet := true) -> void:
	var path := _out_dir.path_join(name + ".png")
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
	if sheet:
		_sheet.append(img)


## Every sheet plate at a third of its width, one per row.
func _contact_sheet() -> Image:
	var w := 960
	var rows: Array[Image] = []
	var h := 0
	for img in _sheet:
		var small := img.duplicate() as Image
		small.resize(
			w, int(img.get_height() * w / float(img.get_width())), Image.INTERPOLATE_BILINEAR
		)
		rows.append(small)
		h += small.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var y := 0
	for small in rows:
		out.blit_rect(small, Rect2i(Vector2i.ZERO, small.get_size()), Vector2i(0, y))
		y += small.get_height()
	return out
