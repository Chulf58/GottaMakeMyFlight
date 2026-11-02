extends SceneTree
## Windowed plates of activity visitors' carry-on bags (decision
## activity-poses-sit-on-the-lounge-sofa-recline-in-the-nap-pod, board item
## e9a2fdaf) in the real main scene: set down on the floor beside the lounge
## sofa or nap pod seat, standing outside the shower door, and picked up again.
## For each piece the probe boots main.tscn, builds the reference terminal on
## the shell with a ready room of that type (ActivityTestLayout, the piece in
## the room's north-west corner facing south), opens the airport and sends
## bored passengers with chosen bags into the room, stepping the clock by
## hand. A 1 m reference cube stands on the floor beside the piece.
##
## Plates (the orthographic ones true scale, 3 m tall):
##   lounge: a roller alone on one seat, two bags on the other;
##     lounge_set_down, lounge_pick_up: strips of the roller visitor, every
##     STRIP_STEP ticks
##   pod (a hard case alone): pod_set_down, pod_pick_up
##   shower (a roller alone): shower_set_down, shower_pick_up
##   and for each of lounge, pod and shower (_stills): _front, _back (a section
##   through the piece's middle), _right, _left (the west wall cut away), _top,
##   _game and _distance. No bottom view: the floor hides everything from below.
## Proofs before a save: the body (feet and chest) and every bag project inside
## the frame with a margin, a twin with the visitors hidden differs from the
## plate, a twin with only one passenger's body hidden differs for each
## passenger (and for the strip's visitor on every strip frame), and sight
## lines (PlateSight, against the meshes drawn) land on every bag in a still
## plate (but the back and left ones) and on each bag in at least half of a
## strip's frames.
## Otherwise PROBE_INVALID, exit 1. Each plate prints where every bag is in
## the piece's frame (+z out of its front) and its home.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/activity_bags_plates_probe.gd [-- --seed=N]
##
## Plates go to tools/blender/out/activity-bags/.

const StarterFlight := preload("res://spike/starter_flight.gd")
const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/activity-bags"
const MARGIN_PX := 8.0
const MIN_DIFF_PX := 300
## Each passenger alone must change this many pixels of a plate (its twin with
## only that passenger hidden).
const MIN_PERSON_PX := 40
## The orthographic cameras stand this far from the point they look at.
const ORTHO_BACK_M := 3.2
## The left view's near plane cuts this far inside the piece's cell edge: past
## the wall's inner face (BuildView.WALL_THICKNESS / 2 = 0.07 m), short of the
## piece (0.08 m in from the edge).
const WALL_CUT_M := 0.075
## The shower's back section cuts this far behind its middle (_back_cut).
const SHOWER_BACK_CUT_M := -0.22
const ORTHO_M := 3.0
const HANG_MS := 120000
const CUBE_CELL := Vector2i(24, 5)
const STRIP_FRAMES := 10
const STRIP_STEP := 2
const LIMIT_TICKS := 3000
const OCCLUDER_OWNERS: Array[String] = ["Airside/Terminal", "BuildMode", "PassengerViews"]

var _out_dir := ""
var _failed := false
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _stop := false
var _seed := 0

var _main: Node3D
var _sim: PassengerSim
var _clock: SimClock
var _mode: BuildMode
var _views: PassengerViews
var _ids := {}
var _sheet: Array[Image] = []
## Passenger id -> [clip, ticks since it started], to seek clips while frozen.
var _clips := {}


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_seed = randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
	print("PROBE sim_seed=%d out_dir=%s" % [_seed, _out_dir])
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	var types: Array[StringName] = [&"lounge", &"nap_pod", &"shower"]
	for type: StringName in types:
		if not await _boot(type):
			continue
		match type:
			&"lounge":
				await _seat("lounge", [[1, SecurityLooks.Kind.ROLLER], [2, -1]])
			&"nap_pod":
				await _seat("pod", [[1, SecurityLooks.Kind.CASE]])
			&"shower":
				await _shower()
		_main.queue_free()
		await _frames(3)
	if not _sheet.is_empty():
		_save(_contact_sheet(_sheet), "contact_sheet.png")
	print("PROBE done plates=%d failed=%s" % [_sheet.size(), _failed])
	_finish()
	quit(1 if _failed else 0)


func _boot(type: StringName) -> bool:
	_beat("boot " + type)
	_clips.clear()
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	_clock.seed_rng(_seed)
	# The probe builds its own terminal on an empty grid: the starter shell
	# main.tscn places on the reference cells would refuse its first wall.
	(_main.get_node("BuildMode") as BuildMode).starter_shell = false
	root.add_child(_main)
	_clock.set_process(false)
	_clock.set_paused(false)
	await _frames(3)
	_mode = _main.get_node("BuildMode") as BuildMode
	_mode.set_process(false)
	_mode.set_tool(BuildMode.Tool.NONE)
	(_mode.get_node("Ghost") as Node3D).visible = false
	_sim = _main.get_node("PassengerSim") as PassengerSim
	_views = _main.get_node("PassengerViews") as PassengerViews
	_ids = ActivityTestLayout.build(_mode.grid, type)
	if not StarterFlight.add_gate_desk(_mode.grid):
		_invalid("the gate desk was refused")
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	await _frames(4)
	_sim.shops.refresh()
	_sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE %s ids=%s hired=%d opened tick=%d" % [type, _ids, hired, _clock.tick])
	if hired == 0 or doors < 0:
		_invalid("%s: the airport did not open" % type)
		return false
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var cube := MeshInstance3D.new()
	var box := BoxMesh.new()
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.55, 0.55, 0.6)
	box.material = grey
	cube.mesh = box
	cube.position = (
		_mode.grid.cell_to_world(CUBE_CELL + ReferenceTerminal.offset_on(_mode.grid))
		+ Vector3(0.0, 0.5, 0.0)
	)
	_main.add_child(cube)
	return true


## A bored passenger with `count` bags, the last of `kind` (any when -1), that
## commits to the room's piece. Spawns until the last bag's kind matches (a
## bag's kind is a hash of the passenger's id); the others keep no bags.
func _visitor(count: int, kind: int) -> Passenger:
	var p: Passenger = null
	for attempt in 200:
		var id := _sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
		p = _sim.get_passenger(id)
		if kind < 0 or SecurityLooks.bag_kind(p, count - 1) == kind:
			break
		p.carry_on = 0
	ToiletTestLayout.calm(p)
	p.carry_on = count
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _clock.tick
	p.at = ShopTestLayout.AIRSIDE_CELL + ReferenceTerminal.offset_on(_mode.grid)
	p.clear_path()
	p.boredom = 80
	p.shop_cooldown = 0
	NeedsPolicy.arbitrate(_sim, p)
	var visit := _sim.shops.visit_of(p.id)
	var kinds: Array = []
	for i in count:
		kinds.append(SecurityLooks.Kind.keys()[SecurityLooks.bag_kind(p, i)])
	print(
		"VISITOR %d bags=%s visit=%s" % [p.id, kinds, "none" if visit == null else visit.slot_key()]
	)
	if visit == null:
		_invalid("passenger %d did not commit to the room" % p.id)
	return p


## The sofa or the pod: visitors with `bags` ([count, kind] each), the first
## followed through its set-down and pick-up.
func _seat(prefix: String, bags: Array) -> void:
	var people: Array[Passenger] = []
	for want: Array in bags:
		people.append(_visitor(want[0], want[1]))
	var a := people[0]
	var near_seat := func() -> bool:
		return a.stage == Passenger.Stage.SHOP_BROWSE and _spent(a) >= 8
	if not await _until(near_seat):
		_invalid("%s: the visitor never reached the seat" % prefix)
		return
	await _strip(prefix + "_set_down", a)
	var all_down := func() -> bool:
		for p in people:
			if not ActivityPoses.bags_down(_sim, p) or _spent(p) < 45:
				return false
		return true
	if not await _until(all_down):
		_invalid("%s: the bags were never all down" % prefix)
		return
	var ids: Array[int] = []
	for p in people:
		ids.append(p.id)
	await _stills(prefix, ids)
	if not await _until(func() -> bool: return _left(a) <= ActivityPoses.SHUFFLE_TICKS + 3):
		_invalid("%s: the visitor never got up" % prefix)
		return
	await _strip(prefix + "_pick_up", a)


func _shower() -> void:
	var p := _visitor(1, SecurityLooks.Kind.ROLLER)
	if not await _until(func() -> bool: return p.stage == Passenger.Stage.SHOP_BROWSE):
		_invalid("shower: the visitor never reached the shower")
		return
	await _strip("shower_set_down", p)
	var washing := func() -> bool: return ActivityPoses.washing(_sim, p) and _spent(p) >= 60
	if not await _until(washing):
		_invalid("shower: the visitor never washed")
		return
	await _stills("shower", [p.id])
	if not await _until(func() -> bool: return _left(p) <= ActivityPoses.DOOR_OUT_TICKS + 4):
		_invalid("shower: the visitor never stepped out")
		return
	await _strip("shower_pick_up", p)


func _spent(p: Passenger) -> int:
	return _clock.tick - p.stage_tick


## Ticks the stay of `p` has left (as ActivityPoses counts them); -1 once over.
func _left(p: Passenger) -> int:
	if p.stage != Passenger.Stage.SHOP_BROWSE:
		return -1
	var visit := _sim.shops.visit_of(p.id)
	var room := _sim.grid.get_room(visit.room)
	var type := RoomTypes.get_type(room["type"])
	return mini(p.stage_tick + ShopSim.browse_ticks(type), visit.deadline) - 1 - _clock.tick


## Where the room's piece is drawn, on the floor.
func _spot() -> Vector3:
	return _piece_frame().origin


## The piece's frame: at its middle on the floor, +z out of its front.
func _piece_frame() -> Transform3D:
	var record := _mode.grid.get_object(_ids["use"])
	var def := BuildCatalog.get_def(record["def"])
	var frame := BuildView.object_transform(
		_mode.grid, def.footprint(record["anchor"], record["facing"]), record["facing"]
	)
	var out := TerminalLayout.front_of(record["facing"])
	return Transform3D(Basis(Vector3.UP, atan2(out.x, out.y)), frame.origin)


## Steps the clock by hand until `done` holds; false when LIMIT_TICKS pass.
func _until(done: Callable, limit := LIMIT_TICKS) -> bool:
	_clock.set_paused(false)
	var until := _clock.tick + limit
	while not done.call() and _clock.tick < until:
		_tick()
		if _clock.tick % 10 == 0:
			_beat("tick %d" % _clock.tick)
			await process_frame
	return done.call()


func _tick() -> void:
	_clock.set_paused(false)
	_clock.advance(SimClock.STEP)
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node == null:
			continue
		var clip: String = node.get_meta(&"clip", "")
		var was: Array = _clips.get(id, ["", 0])
		_clips[id] = [clip, 0 if was[0] != clip else int(was[1]) + 1]


func _seek_clips() -> void:
	for id in _clips:
		var node := _views.node_for(id)
		if node == null:
			continue
		var player := node.get_node("AnimationPlayer") as AnimationPlayer
		var base: float = node.get_meta(&"base_speed", 1.0)
		if player.current_animation != "":
			player.seek(_clips[id][1] * SimClock.STEP * base, true)


## A frozen frame strip of `p` and its bags from a 3/4 camera, every
## STRIP_STEP ticks. Each frame proves the body and each bag in frame; each bag
## must be hit by a sight line in at least half the frames.
func _strip(file: String, p: Passenger) -> void:
	_beat(file)
	var frames: Array[Image] = []
	var cam := _game_cam(_spot(), 3.0)
	var ok := true
	var seen := {}
	for i in STRIP_FRAMES:
		_clock.set_paused(true)
		_seek_clips()
		cam.make_current()
		await _frames(3)
		var node := _views.node_for(p.id)
		var label := "%s[%d]" % [file, i]
		ok = _in_frame(cam, node.global_position + Vector3.UP * 0.9, label + " body") and ok
		var bags: Array = _views.carry_on_props().props_of(p.id)["bags"]
		for b in bags.size():
			var at := _bag_centre(p, b)
			ok = _in_frame(cam, at, "%s bag%d" % [label, b]) and ok
		var hits := await _bags_seen(cam, p)
		for b in hits:
			seen[b] = int(seen.get(b, 0)) + 1
		print(
			(
				"STRIP %s tick=%d spent=%d left=%d clip=%s homes=%s bags=%s seen=%s"
				% [
					label,
					_clock.tick,
					_spent(p),
					_left(p),
					node.get_meta(&"clip", ""),
					SecurityLooks.bag_homes(_sim, p),
					_bag_report(p),
					hits
				]
			)
		)
		var img := _grab()
		ok = await _person_shown(label, p.id, img) and ok
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
		frames.append(img)
		for k in STRIP_STEP:
			_tick()
	cam.queue_free()
	for b in p.carry_on:
		print("STRIP %s bag%d seen in %d of %d frames" % [file, b, seen.get(b, 0), STRIP_FRAMES])
		if int(seen.get(b, 0)) * 2 < STRIP_FRAMES:
			_invalid("%s: bag %d hidden in most frames" % [file, b])
	if not ok:
		_invalid("%s: subject out of frame" % file)
	_save(_row(frames), file + ".png")


## Where bag `b` of `p` is drawn: the middle of its bounds.
func _bag_centre(p: Passenger, b: int) -> Vector3:
	var props := _views.carry_on_props().props_of(p.id)
	var node: Node3D = props["bags"][b]
	return node.global_transform * CarryOnProps.bag_box(props["kinds"][b]).get_center()


## Each bag of `p` in the piece's frame: its middle and its lowest point.
func _bag_report(p: Passenger) -> String:
	var props := _views.carry_on_props().props_of(p.id)
	var frame := _piece_frame()
	var parts: Array[String] = []
	for b in (props["bags"] as Array).size():
		var node: Node3D = props["bags"][b]
		var box: AABB = (
			frame.affine_inverse() * node.global_transform * CarryOnProps.bag_box(props["kinds"][b])
		)
		parts.append(
			(
				"%s mid=(%.2f,%.2f,%.2f) low=%.3f"
				% [
					SecurityLooks.Kind.keys()[props["kinds"][b]],
					box.get_center().x,
					box.get_center().y,
					box.get_center().z,
					box.position.y
				]
			)
		)
	return "[" + "; ".join(parts) + "]"


## The bags of `p` a sight line from the camera lands on (five lines to each:
## its centre and four points about it), as bag indexes.
func _bags_seen(cam: Camera3D, p: Passenger) -> Array[int]:
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		owners.append(_main.get_node(path))
	var bags: Array = _views.carry_on_props().props_of(p.id)["bags"]
	var subjects := {}
	for b in bags.size():
		subjects[bags[b]] = "bag%d" % b
	var holder := PlateSight.colliders(root, owners, subjects)
	await physics_frame
	await physics_frame
	var bounds: Dictionary = holder.get_meta("bounds")
	var space := cam.get_world_3d().direct_space_state
	var out: Array[int] = []
	for b in bags.size():
		var box: AABB = bounds.get("bag%d" % b, AABB())
		var c := box.get_center()
		var q := box.size * 0.25
		var targets: Array[Vector3] = [
			c, c + Vector3(q.x, q.y, 0), c - Vector3(q.x, 0, q.z), c + Vector3(0, q.y, q.z), c - q
		]
		var hits := PlateSight.sight_lines(space, cam.global_position, targets, "bag%d" % b)
		if not (hits["on_subject"] as Array).is_empty():
			out.append(b)
		else:
			print("UNSEEN bag%d blockers=%s past=%s" % [b, hits["blockers"], hits["past"]])
	holder.free()
	return out


## The still plates of a stay: five true-scale orthographic views (front, back,
## right, left and top; the bottom is left out, the floor hides everything
## from below), the game view and a distance view. The piece stands in the
## room's north-west corner, so the back view is a section through the
## piece's middle (the near plane cuts away the wall and the back half of the
## piece, as the pod's shell would hide the sitter) and the left view cuts
## away the west wall just outside the piece. Bags must be hit by sight lines
## in every view but the back and left ones, where a bag beside the legs is
## hidden behind them or the piece by design.
func _stills(prefix: String, ids: Array[int]) -> void:
	var spot := _spot()
	var half := _half_width()
	var views := [
		["front", Vector3(0, 0, 1), 0.05, true],
		["back", Vector3(0, 0, -1), ORTHO_BACK_M - 0.5 + _back_cut(prefix), false],
		["right", Vector3(1, 0, 0), 0.05, true],
		["left", Vector3(-1, 0, 0), ORTHO_BACK_M - 0.6 - (half - WALL_CUT_M), false],
		["top", Vector3.UP, 0.05, true],
	]
	for view: Array in views:
		await _plate("%s_%s" % [prefix, view[0]], _ortho(spot, view[1], view[2]), ids, view[3])
	await _plate(prefix + "_game", _game_cam(spot), ids)
	var far := Camera3D.new()
	far.fov = 40.0
	_main.add_child(far)
	far.look_at_from_position(spot + Vector3(5.0, 9.0, 7.5), spot)
	await _plate(prefix + "_distance", far, ids)


## Where the back view's section cuts, out from the piece's middle toward its
## back (negative): the middle for a sofa or pod, whose sitter sits in front
## of it; for the shower, whose visitor stands at its middle and would be cut
## in half there, just behind the body (its back 0.15 m behind the middle):
## cut at 0.36 m, the cubicle's thick back panel hid the body.
func _back_cut(prefix: String) -> float:
	return SHOWER_BACK_CUT_M if prefix == "shower" else 0.0


## Half the piece's width (metres, along x): its footprint's cells.
func _half_width() -> float:
	var record := _mode.grid.get_object(_ids["use"])
	var def := BuildCatalog.get_def(record["def"])
	var xs: Array[int] = []
	for cell: Vector2i in def.footprint(record["anchor"], record["facing"]):
		xs.append(cell.x)
	return (xs.max() - xs.min() + 1) * 0.5


## A true-scale orthographic camera ORTHO_M tall looking at `spot` (1 m up)
## from `dir`, ORTHO_BACK_M from that point, its near plane `near` out.
func _ortho(spot: Vector3, dir: Vector3, near: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ORTHO_M
	cam.near = near
	_main.add_child(cam)
	var target := spot + Vector3(0.6, 0.8, 0.5)
	if dir == Vector3.UP:
		cam.look_at_from_position(target + Vector3(0.0, 1.7, 0.001), target)
	else:
		cam.look_at_from_position(target + dir * ORTHO_BACK_M, target)
	return cam


## A camera from the front right and above, at about the game's angle.
func _game_cam(spot: Vector3, back := 3.5) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 40.0
	_main.add_child(cam)
	cam.look_at_from_position(spot + Vector3(1.6, 3.0, back), spot + Vector3(0.0, 0.6, 0.6))
	return cam


## Saves a plate after proving each subject (its body and every bag) in frame,
## each bag hit by a sight line (when `bags_seen`), the subjects drawn (a twin
## with them all hidden differs by MIN_DIFF_PX pixels) and each passenger
## drawn (a twin with only its body hidden differs by MIN_PERSON_PX).
func _plate(file: String, cam: Camera3D, ids: Array[int], bags_seen := true) -> void:
	_beat(file)
	_clock.set_paused(true)
	_seek_clips()
	cam.make_current()
	await _frames(4)
	var ok := true
	var unseen := 0
	for id in ids:
		var node := _views.node_for(id)
		var p := _sim.get_passenger(id)
		for up in [0.1, 1.1]:
			ok = (
				_in_frame(cam, node.global_position + Vector3.UP * up, "%s p%d" % [file, id]) and ok
			)
		for b in p.carry_on:
			ok = _in_frame(cam, _bag_centre(p, b), "%s p%d bag%d" % [file, id, b]) and ok
		var hits := await _bags_seen(cam, p)
		if bags_seen:
			unseen += p.carry_on - hits.size()
		print(
			(
				"BAGS %s p%d homes=%s bags=%s seen=%s required=%s"
				% [file, id, SecurityLooks.bag_homes(_sim, p), _bag_report(p), hits, bags_seen]
			)
		)
	var img := _grab()
	for id in ids:
		ok = await _person_shown(file, id, img) and ok
	for id in ids:
		_views.node_for(id).visible = false
		for bag: Node3D in _views.carry_on_props().props_of(id)["bags"]:
			bag.visible = false
	await _frames(3)
	var bare := _grab()
	for id in ids:
		_views.node_for(id).visible = true
		for bag: Node3D in _views.carry_on_props().props_of(id)["bags"]:
			bag.visible = true
	var diff := _diff(img, bare)
	print(
		(
			"VISIBLE %s subjects=%s diff_px=%d need=%d unseen_bags=%d"
			% [file, ids, diff, MIN_DIFF_PX, unseen]
		)
	)
	if not ok or diff < MIN_DIFF_PX or unseen > 0:
		_invalid("%s: subject not shown (in_frame=%s diff=%d unseen=%d)" % [file, ok, diff, unseen])
	_save(img, file + ".png")
	_sheet.append(img)
	cam.queue_free()


## Whether passenger `id` is drawn in `img` (the frame as it is now): the twin
## with only its body hidden differs by MIN_PERSON_PX pixels or more.
func _person_shown(label: String, id: int, img: Image) -> bool:
	var node := _views.node_for(id)
	node.visible = false
	await _frames(3)
	var without := _grab()
	node.visible = true
	await _frames(2)
	var diff := _diff(img, without)
	print("PERSON %s p%d diff_px=%d need=%d" % [label, id, diff, MIN_PERSON_PX])
	return diff >= MIN_PERSON_PX


func _in_frame(cam: Camera3D, point: Vector3, label: String) -> bool:
	var rect := root.get_visible_rect().grow(-MARGIN_PX)
	var behind := cam.is_position_behind(point)
	var screen := cam.unproject_position(point)
	var ok := not behind and rect.has_point(screen)
	print("INFRAME %s screen=(%.0f,%.0f) frame=%s ok=%s" % [label, screen.x, screen.y, rect, ok])
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


func _grab() -> Image:
	return root.get_texture().get_image()


## Frames in reading order, five to a row.
func _row(frames: Array[Image]) -> Image:
	var w := frames[0].get_width()
	var h := frames[0].get_height()
	var rows := ceili(frames.size() / 5.0)
	var sheet := Image.create(w * 5, h * rows, false, Image.FORMAT_RGBA8)
	for i in frames.size():
		var frame := frames[i]
		frame.convert(Image.FORMAT_RGBA8)
		var at := Vector2i(w * (i % 5), h * (i / 5))
		sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), at)
	return sheet


func _contact_sheet(plates: Array[Image]) -> Image:
	var w := plates[0].get_width() / 3
	var h := plates[0].get_height() / 3
	var rows := ceili(plates.size() / 3.0)
	var sheet := Image.create(w * 3, h * rows, false, Image.FORMAT_RGBA8)
	for i in plates.size():
		var small := plates[i].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * (i % 3), h * (i / 3)))
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
			OS.crash("activity_bags_plates_probe: main thread stalled in %s" % stage)
