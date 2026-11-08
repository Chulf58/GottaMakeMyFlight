extends SceneTree
## Windowed plates of rollers laid down at gate chairs (GateRoller.spot(),
## board 1fe04f01): a male and a female guest each with the roller on the
## right and on the left, and two pairs of male guests at neighbouring chair
## fronts, one pair with one roller toward the neighbour (hands set), one with
## the hands ParkSide.gap_hand() chooses (GAP: never both in the gap between
## them). Boots main.tscn with no starter shell, builds the
## reference terminal and its gate desk, hires a member per station and opens
## the airport (anti-pattern a-main-tscn-probe-that-builds-its-own-terminal-at-raw-cells).
## Each subject is put at its chair front with one roller, its body variant
## and its hand set (the hand through ParkSide's stamp), and sits down. The
## clock runs a third of a tick a frame.
##
## Checks, each printing the values it compared:
##   SPOT: the lying roller's origin against the chair front, across (x) and
##     ahead (z), with GateRoller.side() for the subject's body and hand.
##   BODY_IN_BAG: body points (CarryContact, drawn in this window, no hand left
##     out) inside the lying roller's meshes, the most on any frame the walker
##     stands at the chair front with the roller down ("stand") and seated; also
##     the neighbour's body points for the pairs. Control: the same count for the
##     roller drawn on the walker's own feet is > 0.
## Plates: stand_<subject> (the first frame the roller is down with the walker
## still standing at the front), seated_<subject>, pair_<n> (top-down over both
## guests of a pair, seated) and a contact sheet. Before a save the feet, head
## and roller of each guest in it project inside the frame by MARGIN_PX, and at
## least MIN_ON of five sight lines to each roller land on it with nothing in
## front (PlateSight, its own body not a blocker). Otherwise PROBE_INVALID, exit 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 600 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/gate_chair_roller_probe.gd [-- --seed=N] [--no-plates]
##
## Plates go to tools/blender/out/gate-chair-roller/.

const StarterFlight := preload("res://spike/starter_flight.gd")
const PlateSight := preload("res://spike/plate_sight.gd")
const CarryContact := preload("res://spike/carry_contact.gd")
const OUT_REL := "res://../tools/blender/out/gate-chair-roller"
const MARGIN_PX := 8.0
const MIN_BODY_PX := 120.0
const MIN_ON := 3
const BAG_TAG := "bag"
const LIMIT_TICKS := 200
## Ticks after every subject is seated with its roller down before the seated plates.
const SETTLE_TICKS := 12
## A body drawn this close (m, flat) to its chair front stands there.
const STAND_AT_M := 0.1
const CELL := Vector2i(640, 360)
## [name, variant (0 male, 1 female), hand (0 right, 1 left)] for the singles.
const SINGLES := [
	["male_right", 0, 0], ["male_left", 0, 1], ["female_right", 1, 0], ["female_left", 1, 1]
]

var _seed := 0
var _no_plates := false
var _out_dir := ""
var _failed := false
var _main: Node3D
var _clock: SimClock
var _mode: BuildMode
var _sim: PassengerSim
var _views: PassengerViews
var _cam: Camera3D
var _saved: Array[String] = []
var _sheet: Array[Image] = []
## Subject records: name, p, seat, hand, stand_max, seated_max, stood_shot,
## neighbour (another record's index or -1).
var _subjects: Array[Dictionary] = []
## Pairs: [index of the left guest's record, index of the right guest's].
var _pairs: Array = []


func _initialize() -> void:
	Engine.max_fps = SimClock.TICK_RATE * 3
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	_seed = randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
		elif arg == "--no-plates":
			_no_plates = true
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE sim_seed=%d out_dir=%s" % [_seed, _out_dir])
	_run.call_deferred()


func _run() -> void:
	if await _boot() and _place():
		await _watch()
		await _seated_plates()
		_summary()
	if not _sheet.is_empty():
		_save_sheet()
	print("PROBE done plates=%d failed=%s" % [_saved.size(), _failed])
	quit(1 if _failed else 0)


func _boot() -> bool:
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	_clock.seed_rng(_seed)
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
	var refused := 0
	for result in _mode.grid.apply_batch(
		ReferenceTerminal.edits(ReferenceTerminal.offset_on(_mode.grid))
	):
		refused += int(not result.ok)
	print("PROBE terminal edits refused=%d" % refused)
	if refused > 0 or not StarterFlight.add_gate_desk(_mode.grid):
		_invalid("the reference terminal or its gate desk was refused")
		return false
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	await _frames(4)
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE hired=%d opened tick=%d doors=%d" % [hired, _clock.tick, doors])
	if hired == 0 or doors < 0:
		_invalid("the airport did not open")
		return false
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	return true


## Picks the seats: two pairs of seats whose fronts are one cell apart along
## the row (same facing), then four more seats for the singles, none next to
## another subject's front.
func _place() -> bool:
	var seats: Array = _sim.layout.seats
	var used := {}
	var pairs: Array = []
	for a: Dictionary in seats:
		for b: Dictionary in seats:
			if pairs.size() == 2:
				break
			var step: Vector2i = (b["front"] as Vector2i) - (a["front"] as Vector2i)
			var out: Vector2i = (a["front"] as Vector2i) - (a["cell"] as Vector2i)
			var same: bool = (b["front"] as Vector2i) - (b["cell"] as Vector2i) == out
			# b on a's left: a's left (hand 1) is +x in a frame facing `out`.
			if not same or step != _left(a) or used.has(a["cell"]) or used.has(b["cell"]):
				continue
			if _near_used(a, used) or _near_used(b, used):
				continue
			pairs.append([a, b])
			used[a["cell"]] = true
			used[b["cell"]] = true
	if pairs.size() < 2:
		_invalid(
			"fewer than two neighbouring seat pairs (%d of %d seats)" % [pairs.size(), seats.size()]
		)
		return false
	# Pair 0: the left guest's roller toward the neighbour (left hand), his away
	# (left hand too), set. Pair 1: the hands ParkSide.gap_hand() chooses (-1).
	var hands := [[1, 1], [-1, -1]]
	for n in 2:
		var first := _subjects.size()
		for m in 2:
			_add("pair%d_%s" % [n, ["a", "b"][m]], pairs[n][m], 0, hands[n][m])
		_pairs.append([first, first + 1])
	# A single's roller side (the seat beside it that way) holds no subject, and
	# no subject's roller points at it.
	var toward := {}
	for s: Dictionary in _subjects:
		# Pair 1 is left to gap_hand(): its right gap, as it chooses at free gaps.
		var way := _left(s["seat"]) * (1 if s["hand"] == 1 else -1)
		toward[(s["seat"]["cell"] as Vector2i) + way] = true
	for single: Array in SINGLES:
		var seat: Dictionary = {}
		for s: Dictionary in seats:
			var way := _left(s) * (1 if single[2] == 1 else -1)
			var beside: Vector2i = (s["cell"] as Vector2i) + way
			if not used.has(s["cell"]) and not toward.has(s["cell"]) and not used.has(beside):
				seat = s
				toward[beside] = true
				break
		if seat.is_empty():
			_invalid("no free seat for %s (%d seats)" % [single[0], seats.size()])
			return false
		used[seat["cell"]] = true
		_add(single[0], seat, single[1], single[2])
	return not _failed


## The cell step to the left of a guest at `seat`'s front facing out of it
## (+x of RollerPark.chair_front()'s frame, the left hand's side).
static func _left(seat: Dictionary) -> Vector2i:
	var out: Vector2i = (seat["front"] as Vector2i) - (seat["cell"] as Vector2i)
	return Vector2i(out.y, -out.x)


func _near_used(seat: Dictionary, used: Dictionary) -> bool:
	for cell: Vector2i in used:
		if (cell - (seat["cell"] as Vector2i)).length_squared() <= 2:
			return true
	return false


## A passenger with one roller at `seat`'s front, of `variant`, its roller in
## `hand` (ParkSide's stamp), kept on time on every tick.
func _add(label: String, seat: Dictionary, variant: int, hand: int) -> void:
	var p: Passenger = null
	for attempt in 200:
		p = _sim.get_passenger(_sim.spawn_now(StarterFlight.first_flight()))
		if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER:
			break
		p.carry_on = 0
	ToiletTestLayout.calm(p)
	p.variant = variant
	p.carry_on = 1
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _clock.tick
	p.seat_object = 0
	p.seat_cell = seat["cell"]
	p.seat_front = seat["front"]
	p.at = seat["front"]
	p.clear_path()
	p.boarding_tick = _clock.tick + 100000
	_clock.ticked.connect(func(_t: int) -> void: p.late = false)
	if hand >= 0:
		var stamps: Dictionary = _sim.get_meta(ParkSide.STAMPS, {})
		stamps[p.id] = ["gate %s" % seat["cell"], hand]
		_sim.set_meta(ParkSide.STAMPS, stamps)
	var look := PassengerLooks.body_of(p.id, p.variant)
	(
		_subjects
		. append(
			{
				"name": label,
				"p": p,
				"seat": seat,
				"hand": hand,
				"look": look,
				"stand_max": -1,
				"seated_max": -1,
				"neighbour_max": -1,
				"stood_shot": false,
				"spot": Vector3.INF,
			}
		)
	)
	print(
		(
			"PROBE subject %s id %d body %s hand %d seat %s front %s"
			% [label, p.id, PassengerLooks.BODIES[look], hand, seat["cell"], seat["front"]]
		)
	)


func _watch() -> void:
	for n in 6:
		await _step()
	for s: Dictionary in _subjects:
		var p: Passenger = s["p"]
		p.seat_object = s["seat"]["object_id"]
		p.stage = Passenger.Stage.SITTING_DOWN
		p.clear_path()
		p.stage_tick = _sim.tick
	var limit := _clock.tick + LIMIT_TICKS
	var settled := -1
	while _clock.tick < limit:
		await _step()
		var all_down := true
		for i in _subjects.size():
			var down := await _measure(i)
			all_down = all_down and down
		if all_down and settled < 0:
			settled = _clock.tick
		if settled >= 0 and _clock.tick >= settled + SETTLE_TICKS:
			return
	_invalid("not every roller lay down and its guest sat within %d ticks" % LIMIT_TICKS)


## Measures subject `i` this frame; whether its roller is down and it is seated.
func _measure(i: int) -> bool:
	var s := _subjects[i]
	var p: Passenger = s["p"]
	var props := _views.carry_on_props()
	var bag := props.bag_state(p.id, 0)
	var place := int(bag.get("place", -1))
	if place / 4 != SecurityLooks.Home.FLOOR or props.transfer_progress(p.id, 0) < 1.0:
		s["was_up"] = true
		return false
	if not s.get("was_up", false):
		# Down before it was ever seen in the hand: not a lay-down at the chair.
		if not s.has("down_early"):
			s["down_early"] = _clock.tick
			print(
				(
					"PROBE %s roller on the floor before any lay-down, tick %d"
					% [s["name"], _clock.tick]
				)
			)
		return false
	var body := _views.node_for(p.id)
	var node: Node3D = props.props_of(p.id)["bags"][0]
	var front := _sim.grid.cell_to_world(p.seat_front)
	var frame: Transform3D = RollerPark.chair_front(_sim, p, SecurityLooks.Kind.ROLLER)
	s["spot"] = frame.affine_inverse() * node.global_position
	var count := CarryContact.inside_meshes(CarryContact.body_points(body, []), node)
	var flat := Vector2(body.global_position.x - front.x, body.global_position.z - front.z)
	if not s.has("down_tick"):
		s["down_tick"] = _clock.tick
		s["hand"] = SecurityLooks.hand_of(_sim, p, 0)
		print(
			(
				"PROBE %s roller down tick %d, body %.3f m off its front, stage %d"
				% [s["name"], _clock.tick, flat.length(), p.stage]
			)
		)
	# Drawn at the front (SitHold holds it there through the park and let-go,
	# whatever the sim's stage) is standing beside the roller.
	if flat.length() < STAND_AT_M:
		s["stand_max"] = maxi(s["stand_max"], count)
		if not s["stood_shot"]:
			s["stood_shot"] = true
			s["control"] = CarryContact.inside_meshes(
				CarryContact.body_points(body, []), _on_feet(node, body)
			)
			print(
				(
					"PROBE %s stands %.3f m off its front, stage %d"
					% [s["name"], flat.length(), p.stage]
				)
			)
			await _plate("stand_%s" % s["name"], [i], false)
	elif p.stage == Passenger.Stage.SEATED:
		s["seated_max"] = maxi(s["seated_max"], count)
	for pair: Array in _pairs:
		if i in pair:
			var other: Dictionary = _subjects[pair[0] if pair[1] == i else pair[1]]
			var them := _views.node_for((other["p"] as Passenger).id)
			var theirs := CarryContact.inside_meshes(CarryContact.body_points(them, []), node)
			s["neighbour_max"] = maxi(s["neighbour_max"], theirs)
	return p.stage == Passenger.Stage.SEATED


## A twin of `node` (the lying roller) moved onto `body`'s feet, for the control.
func _on_feet(node: Node3D, body: Node3D) -> Node3D:
	var twin := node.duplicate() as Node3D
	root.add_child(twin)
	twin.global_transform = Transform3D(node.global_transform.basis, body.global_position)
	twin.visible = false
	twin.free.call_deferred()
	return twin


func _seated_plates() -> void:
	if _failed:
		return
	for i in _subjects.size():
		if not (_subjects[i]["name"] as String).begins_with("pair"):
			await _plate("seated_%s" % _subjects[i]["name"], [i], false)
	for n in _pairs.size():
		await _plate("pair%d" % n, _pairs[n], true)


func _summary() -> void:
	for pair: Array in _pairs:
		var a: Dictionary = _subjects[pair[0]]
		var b: Dictionary = _subjects[pair[1]]
		# b's front is a's front plus a's left step: a's left and b's right share the gap.
		var shared := int(a["hand"] == 1 and b["hand"] == 0)
		print(
			(
				"GAP %s hand %d, %s hand %d: both rollers in the gap between them %d (0)"
				% [a["name"], a["hand"], b["name"], b["hand"], shared]
			)
		)
		if shared > 0:
			_invalid("%s and %s lay their rollers into one gap" % [a["name"], b["name"]])
	for s: Dictionary in _subjects:
		var spot: Vector3 = s["spot"]
		var out := -1.0 if s["hand"] == 0 else 1.0
		print(
			(
				"SPOT %s %s hand %d: across %.3f ahead %.3f (want %.3f, %.3f)"
				% [
					s["name"],
					PassengerLooks.BODIES[s["look"]],
					s["hand"],
					spot.x,
					spot.z,
					out * GateRoller.side(s["look"], s["hand"]),
					RollerPark.FEET_AHEAD_M
				]
			)
		)
		print(
			(
				"BODY_IN_BAG %s stand %d seated %d neighbour %d (0 each); control on the feet %d (> 0)"
				% [
					s["name"],
					s["stand_max"],
					s["seated_max"],
					s["neighbour_max"],
					s.get("control", -1)
				]
			)
		)
		if s["stand_max"] < 0 or s["seated_max"] < 0 or s.get("control", 0) <= 0:
			_invalid("%s was not measured standing and seated, or its control is 0" % s["name"])


## A plate of subjects `which` (indices into _subjects): from above for a pair
## (`top`), else from the roller's side, ahead and above.
func _plate(shot: String, which: Array, top: bool) -> void:
	if _no_plates:
		print("PLATE %s skipped (--no-plates) tick %d" % [shot, _clock.tick])
		return
	var props := _views.carry_on_props()
	var mid := Vector3.ZERO
	var nodes: Array[Node3D] = []
	var bodies: Array[Node3D] = []
	for i: int in which:
		var p: Passenger = _subjects[i]["p"]
		bodies.append(_views.node_for(p.id))
		nodes.append(props.props_of(p.id)["bags"][0])
		mid += _sim.grid.cell_to_world(p.seat_front) / which.size()
	var s := _subjects[which[0]]
	var frame: Transform3D = RollerPark.chair_front(_sim, s["p"], SecurityLooks.Kind.ROLLER)
	frame.origin = mid
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 50.0
		root.add_child(_cam)
	var out := -1.0 if s["hand"] == 0 else 1.0
	var at := Vector3(0.0, 3.2, 0.6) if top else Vector3(out * 1.3, 1.5, 1.9)
	var look := Vector3(0.0, 0.3, 0.0) if top else Vector3(out * 0.2, 0.4, -0.1)
	_cam.look_at_from_position(frame * at, frame * look, Vector3.UP)
	_cam.current = true
	await _frames(2)
	var img := root.get_texture().get_image()
	var size := Vector2(img.get_size())
	var inside := Rect2(Vector2.ONE * MARGIN_PX, size - Vector2.ONE * 2.0 * MARGIN_PX)
	var subjects := {}
	for n in nodes.size():
		subjects[nodes[n]] = BAG_TAG
		var points := {
			"feet": bodies[n].global_position,
			"head": bodies[n].global_position + Vector3.UP * 1.6,
			"bag": nodes[n].global_position,
		}
		for name: String in points:
			var px := _cam.unproject_position(points[name])
			if _cam.is_position_behind(points[name]) or not inside.has_point(px):
				_invalid("%s: %s of %d at %s is out of frame %s" % [shot, name, n, px, size])
				return
			print("PLATE %s guest %d %s at %s" % [shot, n, name, px.round()])
		var tall := _cam.unproject_position(points["feet"]).distance_to(
			_cam.unproject_position(points["head"])
		)
		if tall < MIN_BODY_PX and not top:
			_invalid("%s: guest %d is %.0f px tall (>= %.0f)" % [shot, n, tall, MIN_BODY_PX])
			return
	var holder := PlateSight.colliders(root, [_views, _mode.get_node("BuildView")], subjects)
	if not (holder.get_meta("unbaked") as Array).is_empty():
		_invalid("%s: skinned meshes without a sight collider" % shot)
	await physics_frame
	await physics_frame
	var space := _cam.get_world_3d().direct_space_state
	for n in nodes.size():
		var box := _bag_box(nodes[n])
		var c := box.get_center()
		var top_y := box.end.y - 0.02
		var targets: Array[Vector3] = [Vector3(c.x, top_y, c.z)]
		for d in [
			Vector3(0.08, 0, 0), Vector3(-0.08, 0, 0), Vector3(0, 0, 0.12), Vector3(0, 0, -0.12)
		]:
			targets.append(Vector3(c.x, top_y, c.z) + d)
		var lines := PlateSight.sight_lines(space, _cam.global_position, targets, BAG_TAG)
		var on: int = (lines["on_subject"] as Array).size()
		print(
			(
				"PLATE %s roller %d sight on %d past %d blockers %s"
				% [shot, n, on, lines["past"], lines["blockers"]]
			)
		)
		if on < MIN_ON or not (lines["blockers"] as Array).is_empty():
			holder.free()
			_invalid("%s: roller %d is not in sight (%d of 5 lines on it)" % [shot, n, on])
			return
	holder.free()
	var path := _out_dir.path_join("gate_chair_%s.png" % shot)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	_saved.append(path)
	var small := img.duplicate() as Image
	small.resize(CELL.x, CELL.y)
	_sheet.append(small)
	print("PLATE saved %s" % path)


func _bag_box(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var part := mi.global_transform * mi.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


func _save_sheet() -> void:
	var rows := ceili(_sheet.size() / 3.0)
	var sheet := Image.create(CELL.x * 3, CELL.y * rows, false, Image.FORMAT_RGBA8)
	for n in _sheet.size():
		var img := _sheet[n]
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(n % 3 * CELL.x, n / 3 * CELL.y))
	var path := _out_dir.path_join("gate_chair_sheet.png")
	sheet.save_png(path)
	print("PLATE sheet %d plates saved %s" % [_sheet.size(), path])


func _step() -> void:
	_clock.advance(SimClock.STEP / 3.0)
	await _frames(1)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	if not _no_plates:
		await RenderingServer.frame_post_draw


func _invalid(why: String) -> void:
	_failed = true
	print("PROBE_INVALID %s" % why)
