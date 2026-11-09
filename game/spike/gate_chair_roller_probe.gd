extends SceneTree
## Windowed plates of rollers laid down at gate chairs (GateRoller.spot(),
## board 1fe04f01): a male and a female guest each with the roller on the
## right and on the left, and two pairs of male guests at neighbouring chair
## fronts, one pair with one roller toward the neighbour (hands set), one with
## the hands ParkSide.gap_hand() chooses (GAP: never both in the gap between
## them). With --two-bag the singles are a male and a female two-bag guest
## instead (the roller drawn at SecurityLooks.TWO_BAG_SCALE and laid at
## GateRoller.TWO_BAG_SIDE_M), and a third pair is two male two-bag guests
## whose rollers' bags face one gap (GAP: both rollers in it, apart by
## GAP_CLEAR); the reference terminal's 12 seats hold one set or the other.
## Boots main.tscn with no starter shell, builds the
## reference terminal and its gate desk, hires a member per station and opens
## the airport (anti-pattern a-main-tscn-probe-that-builds-its-own-terminal-at-raw-cells).
## Each subject is put at its chair front with one roller, its body variant
## and its hand set (the hand through ParkSide's stamp), and sits down. The
## clock runs a third of a tick a frame.
##
## Checks, each printing the values it compared:
##   SPOT: the lying roller's origin against the chair front, across (x) and
##     ahead (z), with GateRoller.side() for the subject's body, hand and bag
##     scale.
##   GAP_CLEAR: for the two-bag pair, how far apart (m, across) the two lying
##     rollers' shells are in the gap between their fronts: 1 m less both
##     measured spots and both scaled half widths (GateRoller.SHELL_HALF_M).
##   BODY_IN_BAG: body points (CarryContact, drawn in this window, no hand left
##     out) inside the lying roller's meshes, the most on any frame the walker
##     stands at the chair front with the roller down ("stand"), shuffles from
##     the front onto its chair ("shuffle") and is seated; also the neighbour's
##     body points for the pairs. Control: the same count for the roller drawn
##     on the walker's own feet is > 0.
##   HIT: on every frame with body points in the walker's own roller, which of
##     the roller's meshes hold them (rods and pull grip marked "rod"), the
##     bones they are skinned to most, where they lie in the chair front's frame,
##     and the body's clip, crossfade weight, offset and turn off that frame.
##   RUN: a subject's pulled roller against every other subject's lying
##     roller along the row (_roller_run(), board 11922532): frames near, frames
##     with the pulled roller's points inside the lying one's meshes, with a
##     twin control. Measured, not failed on.
## Plates: stand_<subject> (the first frame the roller is down with the walker
## still standing at the front), shuffle_<subject> (the first shuffle frame with
## SHUFFLE_SHOT body points or more in its roller, or mid-shuffle onto a middle
## chair), seated_<subject>, pair_<n> (top-down over both guests of a pair,
## seated), row (top-down over the first two pairs) and a contact sheet. Before
## a save the feet, head and roller of each guest in it project inside the
## frame by MARGIN_PX, and at
## least MIN_ON of five sight lines to each roller land on it with nothing in
## front (PlateSight, its own body not a blocker), aimed at the roller's body
## with its rods and pull grip left out (_bag_box()). Otherwise PROBE_INVALID,
## exit 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 600 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/gate_chair_roller_probe.gd [-- --seed=N] [--no-plates]
##     [--two-bag]
##
## Plates go to tools/blender/out/gate-chair-turned/ (gate-chair-turned-two-bag/
## with --two-bag), or tools/blender/out/<dir>/ with --out=<dir>.

const StarterFlight := preload("res://spike/starter_flight.gd")
const PlateSight := preload("res://spike/plate_sight.gd")
const CarryContact := preload("res://spike/carry_contact.gd")
const FloatCheck := preload("res://spike/carry_float_check.gd")
const OUT_ROOT := "res://../tools/blender/out"
const OUT_REL := OUT_ROOT + "/gate-chair-turned"
## A pulled roller whose body box middle is this close (m) to another
## subject's lying roller's is near it (RUN's control that the pair met).
const RUN_NEAR_M := 1.0
const MARGIN_PX := 8.0
const MIN_BODY_PX := 120.0
const MIN_ON := 3
const BAG_TAG := "bag"
const LIMIT_TICKS := 200
## Ticks after every subject is seated with its roller down before the seated plates.
const SETTLE_TICKS := 12
## A body drawn this close (m, flat) to its chair front stands there.
const STAND_AT_M := 0.1
## A shuffle frame with this many body points or more in the walker's own
## roller gets a plate, shuffle_<subject> (the first such frame).
const SHUFFLE_SHOT := 20
## A subject on a chair whose seat lies this far across from its front (the
## seat row's middle chair, GateRoller.slide()) gets the shuffle plate anyway,
## on the first frame it is MID_SHUFFLE_M or more off its front.
const FAR_SLIDE_M := 0.2
const MID_SHUFFLE_M := 0.2
## How many views _plate() tries for one subject (_try_plate()).
const VIEWS := 3
## The subjects that walk in from STRIP_CELLS cells off their chair front and
## get the hand strip (_hand_watch()): pair1_a's left hand is gap_hand()'s, sent
## left by the rollers on its right.
const STRIP_SUBJECTS := ["male_right", "female_right", "pair1_a"]
const STRIP_CELLS := 3
## A change of the drawn hand this close (m, the sim's spot to the chair front)
## before the guest sits fails HAND_CHANGE.
const LAST_M := 1.0
## Ticks the strip subjects are watched after boarding opens for them (the
## stand-up, the pick-up and the walk off).
const PICK_TICKS := 90
const CELL := Vector2i(640, 360)
## [name, variant (0 male, 1 female), hand (0 right, 1 left)] for the singles.
## [name, variant, hand, carry-on bags]; a two-bag guest's roller is the bag
## of its hand's index (SecurityLooks.hand_of()).
const SINGLES := [
	["male_right", 0, 0, 1],
	["male_left", 0, 1, 1],
	["female_right", 1, 0, 1],
	["female_left", 1, 1, 1],
]
## The singles with --two-bag.
const TWO_BAG_SINGLES := [["two_male_left", 0, 1, 2], ["two_female_right", 1, 0, 2]]

var _seed := 0
var _no_plates := false
## --two-bag: the two-bag singles and the two-bag pair (TWO_BAG_SINGLES).
var _two_bag := false
## --trace=<subject>: a TRACE row for that subject on every frame of the watch.
var _trace := ""
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
## RUN records by "<pulled subject>><lying subject>" (_roller_run()).
var _runs: Dictionary = {}
## [plain walk m, walk round the fronts m] per subject (_add()).
var _walks: Array = []


func _initialize() -> void:
	Engine.max_fps = SimClock.TICK_RATE * 3
	_seed = randi()
	_two_bag = "--two-bag" in OS.get_cmdline_user_args()
	var out_rel := OUT_REL + ("-two-bag" if _two_bag else "")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var dir := arg.get_slice("=", 1)
			if not _out_ok(dir):
				print("PROBE_INVALID --out=%s is not a relative folder under %s" % [dir, OUT_ROOT])
				quit(1)
				return
			out_rel = OUT_ROOT.path_join(dir)
		elif arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
		elif arg == "--no-plates":
			_no_plates = true
		elif arg.begins_with("--trace="):
			_trace = arg.get_slice("=", 1)
	_out_dir = ProjectSettings.globalize_path(out_rel).simplify_path()
	var under := ProjectSettings.globalize_path(OUT_ROOT).simplify_path() + "/"
	if not _out_dir.begins_with(under):
		print("PROBE_INVALID plate folder %s is not under %s" % [_out_dir, under])
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE sim_seed=%d out_dir=%s" % [_seed, _out_dir])
	_run.call_deferred()


## Whether `dir` (--out=) names a folder under OUT_ROOT: not empty, not
## absolute, no drive or backslash, no ".." part.
static func _out_ok(dir: String) -> bool:
	if dir.is_empty() or dir.is_absolute_path() or ":" in dir or "\\" in dir:
		return false
	return ".." not in dir.split("/")


func _run() -> void:
	if await _boot() and _place():
		await _watch()
		await _seated_plates()
		await _pick_up()
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
	var count := 3 if _two_bag else 2
	var used := {}
	var pairs: Array = []
	for a: Dictionary in seats:
		for b: Dictionary in seats:
			if pairs.size() == count:
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
	if pairs.size() < count:
		_invalid(
			(
				"fewer than %d neighbouring seat pairs (%d of %d seats)"
				% [count, pairs.size(), seats.size()]
			)
		)
		return false
	# Pair 0: the right guest's roller toward the neighbour (right hand), his away
	# (right hand too), set: b on a seat row's middle chair lays it away from
	# his shuffle (decision gate-chair-roller-lies-opposite-the-sit-down-shuffle-
	# on-a-ch); set left, as before board 4da2e8ff, the rule sent every roller
	# along the row to the left with it. Pair 1: the hands ParkSide.gap_hand()
	# chooses (-1). Pair 2: two-bag guests, a's roller bag 1 (left, into the
	# gap), b's bag 0 (right, into the same gap).
	var hands := [[0, 0], [-1, -1], [1, 0]]
	for n in count:
		var first := _subjects.size()
		for m in 2:
			_add("pair%d_%s" % [n, ["a", "b"][m]], pairs[n][m], 0, hands[n][m], 2 if n == 2 else 1)
		_pairs.append([first, first + 1])
	# A single's roller side (the seat beside it that way) holds no subject, and
	# no subject's roller points at it.
	var toward := {}
	for s: Dictionary in _subjects:
		# Pair 1 is left to gap_hand(): its right gap, as it chooses at free gaps.
		var way := _left(s["seat"]) * (1 if int(s["hand"]) == 1 else -1)
		toward[(s["seat"]["cell"] as Vector2i) + way] = true
	for single: Array in TWO_BAG_SINGLES if _two_bag else SINGLES:
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
		_add(single[0], seat, single[1], single[2], single[3])
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


## A passenger with `bags` carry-on bags at `seat`'s front, of `variant`, its
## roller in `hand`: one bag, the roller, held in `hand` by ParkSide's stamp;
## two, the roller as bag `hand` (SecurityLooks.hand_of()). Kept on time on
## every tick.
func _add(label: String, seat: Dictionary, variant: int, hand: int, bags := 1) -> void:
	var p: Passenger = null
	var roller := 0 if bags == 1 else hand
	for attempt in 400:
		p = _sim.get_passenger(_sim.spawn_now(StarterFlight.first_flight()))
		if SecurityLooks.bag_kind(p, roller) == SecurityLooks.Kind.ROLLER:
			break
		p.carry_on = 0
	ToiletTestLayout.calm(p)
	p.variant = variant
	p.carry_on = bags
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _clock.tick
	# Every subject walks in, so the view draws it with its roller in hand before
	# it sits: placed sitting at its front, its roller was drawn on the floor at
	# once (no park).
	p.at = _walk_start(seat, STRIP_CELLS if label in STRIP_SUBJECTS else 1)
	print("PROBE %s walks in from %s" % [label, p.at])
	# The seat claimed and the path to its front set as GateCapacity._take_seat()
	# does: left at seat_object 0 the sim claimed the nearest free seat for the
	# guest itself mid-watch (GateCapacity.claim_seat()), drew it at the seat
	# and laid its roller there (pair1_b, tick 122).
	_sim._seat_claims[seat["key"]] = p.id
	p.seat_object = seat["object_id"]
	p.seat_cell = seat["cell"]
	p.seat_front = seat["front"]
	p.seat_piece = Relocation.placement(_sim.grid, seat["object_id"])
	var path: Array[Vector2i] = [p.at]
	if p.at != seat["front"]:
		# The walk GateCapacity gives a seat claim, round the other fronts.
		path.assign(GateRowWalk.path(_sim, p.at, seat["front"], seat["cell"]))
		var plain := _sim.grid.find_path(p.at, seat["front"])
		_walks.append([_walk_m(plain), _walk_m(path)])
		print(
			(
				"WALK %s plain %.2f m %s, round the fronts %.2f m %s"
				% [label, _walk_m(plain), plain, _walk_m(path), path]
			)
		)
	p.set_path(path)
	p.boarding_tick = _clock.tick + 100000
	_clock.ticked.connect(func(_t: int) -> void: p.late = false)
	if hand >= 0 and bags == 1:
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
				"bag": roller,
				"look": look,
				"stand_max": -1,
				"seated_max": -1,
				"neighbour_max": -1,
				"stood_shot": false,
				"spot": Vector3.INF,
				"strip": label in STRIP_SUBJECTS,
			}
		)
	)
	print(
		(
			"PROBE subject %s id %d body %s hand %d bags %d seat %s front %s"
			% [label, p.id, PassengerLooks.BODIES[look], hand, bags, seat["cell"], seat["front"]]
		)
	)


func _watch() -> void:
	var limit := _clock.tick + LIMIT_TICKS
	var settled := -1
	while _clock.tick < limit:
		await _step()
		_trace_row()
		await _roller_run()
		var all_down := true
		for i in _subjects.size():
			await _hand_watch(i)
			var down := await _measure(i)
			all_down = all_down and down
		if all_down and settled < 0:
			settled = _clock.tick
		if settled >= 0 and _clock.tick >= settled + SETTLE_TICKS:
			return
	_invalid("not every roller lay down and its guest sat within %d ticks" % LIMIT_TICKS)


## One TRACE row for the --trace subject: stage, sim cell and spot against its
## chair front, the drawn body, the bag's place and progress, and the hand.
func _trace_row() -> void:
	for s: Dictionary in _subjects:
		if s["name"] != _trace:
			continue
		var p: Passenger = s["p"]
		var front := _sim.grid.cell_to_world(p.seat_front)
		var sim_at := _sim.world_position(p)
		var drawn := _views.node_for(p.id).global_position
		var props := _views.carry_on_props()
		var bag := props.bag_state(p.id, s["bag"])
		print(
			(
				"TRACE %s tick %d stage %d at %s seat_obj %d sim %.3f drawn %.3f place %d k %.3f hand %d"
				% [
					s["name"],
					_clock.tick,
					p.stage,
					p.at,
					p.seat_object,
					Vector2(sim_at.x - front.x, sim_at.z - front.z).length(),
					Vector2(drawn.x - front.x, drawn.z - front.z).length(),
					int(bag.get("place", -1)),
					props.transfer_progress(p.id, s["bag"]),
					SecurityLooks.hand_of(_sim, p, s["bag"])
				]
			)
		)


## Measures subject `i` this frame; whether its roller is down and it is seated.
func _measure(i: int) -> bool:
	var s := _subjects[i]
	var p: Passenger = s["p"]
	var props := _views.carry_on_props()
	var bag := props.bag_state(p.id, s["bag"])
	var place := int(bag.get("place", -1))
	if place / 4 != SecurityLooks.Home.FLOOR or props.transfer_progress(p.id, s["bag"]) < 1.0:
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
	var node: Node3D = props.props_of(p.id)["bags"][s["bag"]]
	var front := _sim.grid.cell_to_world(p.seat_front)
	var frame: Transform3D = RollerPark.chair_front(_sim, p, SecurityLooks.Kind.ROLLER)
	s["spot"] = frame.affine_inverse() * node.global_position
	var count := CarryContact.inside_meshes(CarryContact.body_points(body, []), node)
	var flat := Vector2(body.global_position.x - front.x, body.global_position.z - front.z)
	if not s.has("down_tick"):
		s["down_tick"] = _clock.tick
		s["hand"] = SecurityLooks.hand_of(_sim, p, s["bag"])
		print(
			(
				"PROBE %s roller down tick %d, body %.3f m off its front, stage %d"
				% [s["name"], _clock.tick, flat.length(), p.stage]
			)
		)
	# Drawn at the front (SitHold holds it there through the park and let-go,
	# whatever the sim's stage) is standing beside the roller.
	var standing := flat.length() < STAND_AT_M
	if count > 0:
		var phase := "seated" if p.stage == Passenger.Stage.SEATED else "shuffle"
		_hit_row(s, body, node, frame, "stand" if standing else phase)
	if standing:
		s["stand_max"] = maxi(s["stand_max"], count)
		if not s.has("control"):
			s["control"] = CarryContact.inside_meshes(
				CarryContact.body_points(body, []), _on_feet(node, body)
			)
			print(
				(
					"PROBE %s stands %.3f m off its front, stage %d"
					% [s["name"], flat.length(), p.stage]
				)
			)
		if not s["stood_shot"]:
			# Tried on each frame it stands there: a neighbour walking past with
			# its roller can hide this one for a frame or two (pair1_a past pair1_b).
			s["stood_shot"] = await _plate("stand_%s" % s["name"], [i], false, false)
	elif p.stage == Passenger.Stage.SEATED:
		s["seated_max"] = maxi(s["seated_max"], count)
	else:
		# Off the front and not yet seated: the shuffle back onto the chair.
		s["shuffle_max"] = maxi(int(s.get("shuffle_max", 0)), count)
		var far := absf(GateRoller.slide_of(p)) >= FAR_SLIDE_M and flat.length() >= MID_SHUFFLE_M
		if (count >= SHUFFLE_SHOT or far) and not s.has("shuffle_shot"):
			s["shuffle_shot"] = _clock.tick
			print(
				(
					"PROBE %s shuffles %.3f m off its front, slide %+.2f, %d body points in its roller"
					% [s["name"], flat.length(), GateRoller.slide_of(p), count]
				)
			)
		# Tried on each shuffle frame from the first one wanted until a view
		# proves it: a guest walking past with its roller can hide this one for
		# a frame or two (pair1_a's rods past pair1_b). _summary() fails a
		# shuffle that never proved one.
		if s.has("shuffle_shot") and not s.get("shuffle_ok", false):
			s["shuffle_ok"] = await _plate("shuffle_%s" % s["name"], [i], false, false)
	for pair: Array in _pairs:
		if i in pair:
			var other: Dictionary = _subjects[pair[0] if pair[1] == i else pair[1]]
			var them := _views.node_for((other["p"] as Passenger).id)
			var theirs := CarryContact.inside_meshes(CarryContact.body_points(them, []), node)
			# Walking in along the row past this front (pair1_a, from three
			# fronts off) counts apart from standing or sitting at its own.
			var key := (
				"passing_max" if other["p"].stage == Passenger.Stage.TO_GATE else "neighbour_max"
			)
			s[key] = maxi(int(s.get(key, 0)), theirs)
	return p.stage == Passenger.Stage.SEATED


## A HIT row for a frame on which body points of subject `s` lie in its lying
## roller `node`: which of the roller's meshes hold them (a rod or the pull
## grip marked "rod"), the bones they are skinned to most, where they lie in the
## chair front's frame `frame`, and the body's clip, crossfade weight, offset
## and turn off the front's frame.
func _hit_row(s: Dictionary, body: Node3D, node: Node3D, frame: Transform3D, phase: String) -> void:
	var owned := CarryContact.body_points_owned(body, [])
	var points: PackedVector3Array = owned[0]
	var names: PackedStringArray = owned[1]
	var rods: Array = CarryOnProps.REACH_NODES[SecurityLooks.Kind.ROLLER]
	var by_mesh := {}
	var by_bone := {}
	var lo := Vector3.INF
	var hi := -Vector3.INF
	var meshes := []
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		meshes.append([_part_label(mi, node, rods), mi])
	for k in points.size():
		for m: Array in meshes:
			var mi: MeshInstance3D = m[1]
			var lp := mi.global_transform.affine_inverse() * points[k]
			if not mi.mesh.get_aabb().grow(0.001).has_point(lp):
				continue
			if not CarryContact._odd(lp, mi.mesh.get_faces()):
				continue
			by_mesh[m[0]] = int(by_mesh.get(m[0], 0)) + 1
			by_bone[names[k]] = int(by_bone.get(names[k], 0)) + 1
			var at := frame.affine_inverse() * points[k]
			lo = lo.min(at)
			hi = hi.max(at)
			break
	var local := frame.affine_inverse() * body.global_transform
	var turn := rad_to_deg(atan2(local.basis.z.x, local.basis.z.z))
	var fade := body.get_meta(&"crossfade") as ClipCrossfade
	var player := body.get_node("AnimationPlayer") as AnimationPlayer
	print(
		(
			(
				"HIT %s %s tick %d stage %d clip %s at %.2f fade %.2f body at %s turn %.1f deg;"
				+ " meshes %s bones %s; points x %.3f..%.3f y %.3f..%.3f z %.3f..%.3f"
			)
			% [
				s["name"],
				phase,
				_clock.tick,
				(s["p"] as Passenger).stage,
				body.get_meta(&"clip", ""),
				player.current_animation_position,
				fade.weight if fade != null else -1.0,
				local.origin.snapped(Vector3.ONE * 0.001),
				turn,
				by_mesh,
				by_bone,
				lo.x,
				hi.x,
				lo.y,
				hi.y,
				lo.z,
				hi.z,
			]
		)
	)


## The name of roller mesh `mi` under `node`, with " rod" when it is part of the
## rods or the pull grip (`rods`, CarryOnProps.REACH_NODES).
static func _part_label(mi: MeshInstance3D, node: Node3D, rods: Array) -> String:
	var at: Node = mi
	while at != null and at != node:
		if at.name in rods:
			return "%s rod" % mi.name
		at = at.get_parent()
	return String(mi.name)


## A twin of `node` (the lying roller) moved onto `body`'s feet, for the control.
func _on_feet(node: Node3D, body: Node3D) -> Node3D:
	var twin := node.duplicate() as Node3D
	root.add_child(twin)
	twin.global_transform = Transform3D(node.global_transform.basis, body.global_position)
	twin.visible = false
	twin.free.call_deferred()
	return twin


## The seated and pair plates, after any plate before them failed as well (each
## failure is printed and fails the run on its own).
func _seated_plates() -> void:
	for i in _subjects.size():
		if not (_subjects[i]["name"] as String).begins_with("pair"):
			await _plate("seated_%s" % _subjects[i]["name"], [i], false)
	for n in _pairs.size():
		await _plate("pair%d" % n, _pairs[n], true)
	# The row of the first two pairs from above, every roller and seated guest.
	var row: Array = []
	for n in mini(2, _pairs.size()):
		row.append_array(_pairs[n])
	await _plate("row", row, true)


## A cell `cells` (or fewer) off `seat`'s front with a path to it, not a chair
## front: straight out from the chair first, then along the row either way.
func _walk_start(seat: Dictionary, cells: int) -> Vector2i:
	var front: Vector2i = seat["front"]
	var out: Vector2i = front - (seat["cell"] as Vector2i)
	var left := _left(seat)
	var fronts := {}
	for s: Dictionary in _sim.layout.seats:
		fronts[s["front"]] = true
	for n in range(cells, 0, -1):
		for step: Vector2i in [out, -left, left]:
			var at := front + step * n
			if not fronts.has(at) and _sim.grid.find_path(at, front).size() > n:
				return at
	return front


## Boarding opens for the strip subjects: each stands up, picks its roller up
## and walks off, watched for PICK_TICKS (_hand_watch()).
func _pick_up() -> void:
	for s: Dictionary in _subjects:
		if s["strip"]:
			(s["p"] as Passenger).boarding_tick = _clock.tick + 1
	var limit := _clock.tick + PICK_TICKS
	while _clock.tick < limit:
		await _step()
		await _roller_run()
		for i in _subjects.size():
			await _hand_watch(i)


## RUN (board 11922532): on every frame, each subject's roller pulled in a
## hand (no park under way) against every other subject's roller lying on the
## floor (the lay-down over) within RUN_NEAR_M: the frames near ("near", the
## control that they met), the frames with points of the pulled roller's
## meshes (rods and grip in) inside the lying roller's meshes (CarryContact),
## the most points on one frame, and the most the two body boxes (_bag_box())
## overlap on their least axis. Control on the first near frame: the same
## points inside a twin of the lying roller put where the pulled one is (> 0).
## A plate from above, run_<pulled>_<lying>, on the first frame with points in.
func _roller_run() -> void:
	var props := _views.carry_on_props()
	for si in _subjects.size():
		var s := _subjects[si]
		var p: Passenger = s["p"]
		var bag := props.bag_state(p.id, s["bag"])
		var place := int(bag.get("place", -1))
		if place / 4 != SecurityLooks.Home.HAND or place % 2 != 0 or bag.get("park", false):
			continue
		var pulled: Node3D = props.props_of(p.id)["bags"][s["bag"]]
		var points := PackedVector3Array()
		for oi in _subjects.size():
			var o := _subjects[oi]
			var q: Passenger = o["p"]
			var lying_place := int(props.bag_state(q.id, o["bag"]).get("place", -1))
			if oi == si or lying_place / 4 != SecurityLooks.Home.FLOOR:
				continue
			if props.transfer_progress(q.id, o["bag"]) < 1.0:
				continue
			var lying: Node3D = props.props_of(q.id)["bags"][o["bag"]]
			var mine := _bag_box(pulled)
			var theirs := _bag_box(lying)
			if mine.get_center().distance_to(theirs.get_center()) > RUN_NEAR_M:
				continue
			var key := "%s>%s" % [s["name"], o["name"]]
			if not _runs.has(key):
				_runs[key] = {"near": 0, "hit": 0, "most": 0, "box": 0.0, "control": -1}
			var run: Dictionary = _runs[key]
			if points.is_empty():
				points = _mesh_points(pulled)
			run["near"] += 1
			if int(run["control"]) < 0:
				var twin := lying.duplicate() as Node3D
				root.add_child(twin)
				twin.global_transform = pulled.global_transform
				twin.visible = false
				run["control"] = CarryContact.inside_meshes(points, twin)
				twin.free()
			var count := CarryContact.inside_meshes(points, lying)
			var over := mine.intersection(theirs)
			var depth := minf(over.size.x, minf(over.size.y, over.size.z))
			run["box"] = maxf(float(run["box"]), depth if over.has_volume() else 0.0)
			if count <= 0:
				continue
			run["hit"] += 1
			run["most"] = maxi(int(run["most"]), count)
			print(
				(
					"RUN_HIT %s tick %d points %d box overlap %.3f m pulled at %s lying at %s"
					% [key, _clock.tick, count, depth, mine.get_center(), theirs.get_center()]
				)
			)
			if not run.get("shot", false):
				var shot := "run_%s_%s" % [s["name"], o["name"]]
				run["shot"] = await _plate(shot, [si, oi], true, false)


## World points covering every mesh of `node` as drawn (CarryContact.SAMPLE_M
## apart or finer over each triangle).
static func _mesh_points(node: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var faces := mi.mesh.get_faces()
		var xf := mi.global_transform
		for i in range(0, faces.size() - 2, 3):
			var a := xf * faces[i]
			var ab := xf * faces[i + 1] - a
			var ac := xf * faces[i + 2] - a
			var n := maxi(1, ceili(maxf(ab.length(), ac.length()) / CarryContact.SAMPLE_M))
			for u in n + 1:
				for v in n + 1 - u:
					out.append(a + ab * (u / float(n)) + ac * (v / float(n)))
	return out


## The hand strip of strip subject `i` this frame: a HAND row each tick (its
## spot's distance to the chair front, the hand SecurityLooks.hand_of() names
## and the hand the roller is drawn in, the move's progress and the grip's gap
## to the roller's own grip point, FloatCheck.grip_on_gap()); a change of the
## drawn hand within LAST_M of the front before it sits; the largest grip gap
## while a hand holds it in a park; and a plate at k 0, 0.5 and 1 of the lay-down
## and of the pick-up, printing the grip's distance to the carry handle.
func _hand_watch(i: int) -> void:
	var s := _subjects[i]
	if not s["strip"]:
		return
	var p: Passenger = s["p"]
	var props := _views.carry_on_props()
	var body := _views.node_for(p.id)
	if body == null:
		return
	var bag := props.bag_state(p.id, 0)
	var place := int(bag.get("place", -1))
	var drawn := CarryLead.hand_of(place) if place >= 0 else -1
	var k := props.transfer_progress(p.id, 0)
	var front := _sim.grid.cell_to_world(p.seat_front)
	var at := _sim.world_position(p)
	var dist := Vector2(at.x - front.x, at.z - front.z).length()
	var gap: Array = FloatCheck.grip_on_gap(props, p.id, 0, body)
	var node: Node3D = props.props_of(p.id)["bags"][0]
	var gh := INF
	if drawn >= 0:
		var handle := node.global_transform * CarryOnProps.ROLLER_HANDLE
		gh = props.grip_of(body, drawn).distance_to(handle)
	var held := int(bag.get("held_by", -1))
	# The lay itself (RollerPark: from PARK_END the hand on the carry handle lays
	# the bag down, and lets go once it is on the floor).
	var laying: bool = (
		bag.get("park", false)
		and place / 4 == SecurityLooks.Home.FLOOR
		and k >= RollerPark.PARK_END
	)
	if laying and held >= 0:
		if not s.has("lay_take_gh"):
			s["lay_take_gh"] = gh
		s["lay_held"] = true
	elif laying and s.get("lay_held", false) and not s.has("letgo_gh"):
		s["letgo_gh"] = gh
		s["letgo_k"] = k
	if _clock.tick != int(s.get("row_tick", -1)):
		s["row_tick"] = _clock.tick
		print(
			(
				(
					"HAND %s tick %d stage %d dist %.2f hand sim %d drawn %d place %d k %.3f"
					+ " held %d grip-handle %.3f grip_on %.3f (<= %.3f)"
				)
				% [
					s["name"],
					_clock.tick,
					p.stage,
					dist,
					SecurityLooks.hand_of(_sim, p, 0),
					drawn,
					place,
					k,
					held,
					gh,
					gap[0],
					gap[1]
				]
			)
		)
	var to_seat := p.stage in [Passenger.Stage.TO_GATE, Passenger.Stage.SITTING_DOWN]
	if to_seat and dist < LAST_M and drawn >= 0:
		if int(s.get("last_hand", -1)) < 0:
			s["last_hand"] = drawn
		elif drawn != int(s["last_hand"]):
			s["changes"] = int(s.get("changes", 0)) + 1
	var parking: bool = bag.get("park", false)
	if parking and int(bag.get("held_by", -1)) >= 0 and is_finite(float(gap[0])):
		s["grip_max"] = maxf(float(s.get("grip_max", 0.0)), float(gap[0]))
		s["grip_limit"] = gap[1]
	if not parking or drawn < 0:
		return
	var move := "lay" if place / 4 == SecurityLooks.Home.FLOOR else "pick"
	for mark: int in [0, 50, 100]:
		var key := "%s%03d" % [move, mark]
		if s.has(key) or k < mark / 100.0 - 0.0001:
			continue
		s[key] = true
		print(
			(
				"HANDPLATE %s %s k %.3f grip-handle %.3f grip_on %.3f (<= %.3f) held_by %d"
				% [s["name"], key, k, gh, gap[0], gap[1], held]
			)
		)
		await _plate("strip_%s_%s" % [s["name"], key], [i], false)
		break


## The length (m) of the walk along cells `path`: 1 a straight step, sqrt(2)
## a diagonal one.
static func _walk_m(path: Array[Vector2i]) -> float:
	var m := 0.0
	for i in range(1, path.size()):
		m += Vector2(path[i] - path[i - 1]).length()
	return m


func _summary() -> void:
	var sums := [0.0, 0.0]
	var most := [0.0, 0.0]
	for walk: Array in _walks:
		for k in 2:
			sums[k] += float(walk[k])
			most[k] = maxf(float(most[k]), float(walk[k]))
	var n := maxi(_walks.size(), 1)
	print(
		(
			"WALK_SUMMARY %d walks: plain mean %.2f m max %.2f m; round the fronts mean %.2f m max %.2f m"
			% [_walks.size(), sums[0] / n, most[0], sums[1] / n, most[1]]
		)
	)
	var near := 0
	var hits := 0
	for key: String in _runs:
		var run: Dictionary = _runs[key]
		near += int(run["near"])
		hits += int(run["hit"])
		print(
			(
				(
					"RUN %s near %d frames (> 0), points inside on %d frames (0), most %d,"
					+ " body boxes overlap most %.3f m; control twin %d (> 0)"
				)
				% [key, run["near"], run["hit"], run["most"], run["box"], run["control"]]
			)
		)
		if int(run["control"]) <= 0:
			_invalid("RUN %s: the twin control found no points inside" % key)
	print("RUN_TOTAL near %d frames (> 0), points inside on %d frames (0)" % [near, hits])
	if near <= 0:
		_invalid("RUN: no pulled roller came near another subject's lying roller")
	for s: Dictionary in _subjects:
		if not s["strip"]:
			continue
		var marks: Array[String] = []
		for key in ["lay000", "lay050", "lay100", "pick000", "pick050", "pick100"]:
			if not s.has(key):
				marks.append(key)
		print(
			(
				(
					"HAND_CHANGE %s drawn hand changes within %.1f m of the front %d (0),"
					+ " hand there %d; GRIP most %.3f m (<= %.3f) in park holds; marks missing %s"
				)
				% [
					s["name"],
					LAST_M,
					s.get("changes", 0),
					s.get("last_hand", -1),
					s.get("grip_max", -1.0),
					s.get("grip_limit", -1.0),
					marks
				]
			)
		)
		print(
			(
				(
					"LETGO %s lay-down: the hand takes the carry handle %.3f m from it, lets go"
					+ " at k %.3f with its grip %.3f m from it (<= RollerPark.TAKE_M %.2f)"
				)
				% [
					s["name"],
					s.get("lay_take_gh", INF),
					s.get("letgo_k", -1.0),
					s.get("letgo_gh", INF),
					RollerPark.TAKE_M
				]
			)
		)
		if float(s.get("letgo_gh", INF)) > RollerPark.TAKE_M:
			_invalid("%s's hand is off the handle when it lets go of the roller" % s["name"])
		if int(s.get("changes", 0)) > 0:
			_invalid("%s changed hand within %.1f m of its chair front" % [s["name"], LAST_M])
		if float(s.get("grip_max", INF)) > float(s.get("grip_limit", 0.0)):
			_invalid("%s's grip left the roller's grip point in a park" % s["name"])
		if not marks.is_empty() or int(s.get("last_hand", -1)) < 0:
			_invalid("%s's hand strip is short: %s" % [s["name"], marks])
	for pair: Array in _pairs:
		var a: Dictionary = _subjects[pair[0]]
		var b: Dictionary = _subjects[pair[1]]
		# b's front is a's front plus a's left step: a's left and b's right share the gap.
		var shared := int(a["hand"] == 1 and b["hand"] == 0)
		var two := (a["p"] as Passenger).carry_on > 1 and (b["p"] as Passenger).carry_on > 1
		print(
			(
				"GAP %s hand %d, %s hand %d: both rollers in the gap between them %d (%d)"
				% [a["name"], a["hand"], b["name"], b["hand"], shared, int(two)]
			)
		)
		if two:
			# Two two-bag rollers whose bags face one gap: they must lie apart.
			var reach := 0.0
			for t: Dictionary in [a, b]:
				var tp: Passenger = t["p"]
				var tspot: Vector3 = t["spot"]
				reach += absf(tspot.x) + GateRoller.SHELL_HALF_M * SecurityLooks.bag_scale(tp)
			var clear := 1.0 - reach
			print("GAP_CLEAR %s and %s: shells %.3f m apart (> 0)" % [a["name"], b["name"], clear])
			if shared != 1 or clear <= 0.0:
				_invalid("%s and %s two-bag rollers do not lie apart" % [a["name"], b["name"]])
		elif shared > 0:
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
					(
						out
						* GateRoller.side(
							s["look"], s["hand"], SecurityLooks.bag_scale(s["p"] as Passenger)
						)
					),
					RollerPark.FEET_AHEAD_M
				]
			)
		)
		print(
			(
				(
					"BODY_IN_BAG %s stand %d shuffle %d seated %d neighbour %d (0 each);"
					+ " neighbour walking past %d; control on the feet %d (> 0)"
				)
				% [
					s["name"],
					s["stand_max"],
					s.get("shuffle_max", 0),
					s["seated_max"],
					s["neighbour_max"],
					s.get("passing_max", 0),
					s.get("control", -1)
				]
			)
		)
		if s["stand_max"] < 0 or s["seated_max"] < 0 or s.get("control", 0) <= 0:
			_invalid("%s was not measured standing and seated, or its control is 0" % s["name"])
		if s.has("shuffle_shot") and not s.get("shuffle_ok", false):
			_invalid("shuffle_%s: no shuffle frame proved it in sight" % s["name"])
		if not s["stood_shot"]:
			_invalid("stand_%s: no frame standing at the front proved it in sight" % s["name"])


## A plate of subjects `which` (indices into _subjects): from above for a pair
## (`top`), else from the roller's side, ahead and above, then from the other
## side and from the front (VIEWS) when a view fails its proof.
## Whether a view proved it; with `final` false a failure is only printed (the
## caller tries again on a later frame).
func _plate(shot: String, which: Array, top: bool, final := true) -> bool:
	if _no_plates:
		print("PLATE %s skipped (--no-plates) tick %d" % [shot, _clock.tick])
		return true
	for view in 1 if top else VIEWS:
		if await _try_plate(shot, which, top, view):
			return true
	if final:
		_invalid("%s: no view proved its subjects in frame and in sight" % shot)
	else:
		print(
			"PLATE %s: no view proved it at tick %d, tried again next frame" % [shot, _clock.tick]
		)
	return false


## One view of _plate(): 0 the roller's side, 1 the other side, 2 the front.
## Saves the plate and returns true when it proves its subjects.
func _try_plate(shot: String, which: Array, top: bool, view: int) -> bool:
	var props := _views.carry_on_props()
	var mid := Vector3.ZERO
	var nodes: Array[Node3D] = []
	var bodies: Array[Node3D] = []
	for i: int in which:
		var p: Passenger = _subjects[i]["p"]
		bodies.append(_views.node_for(p.id))
		nodes.append(props.props_of(p.id)["bags"][_subjects[i]["bag"]])
		mid += _sim.grid.cell_to_world(_subjects[i]["seat"]["front"]) / which.size()
	var s := _subjects[which[0]]
	var front: Variant = RollerPark.chair_front(_sim, s["p"], SecurityLooks.Kind.ROLLER)
	# Off its seat (the pick-up's end, walking off) it has no chair front: the
	# seat's own way out instead.
	var out_of: Vector2i = (s["seat"]["front"] as Vector2i) - (s["seat"]["cell"] as Vector2i)
	var frame := Transform3D(Basis(Vector3.UP, atan2(out_of.x, out_of.y)), mid)
	if front != null:
		frame = Transform3D((front as Transform3D).basis, mid)
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 50.0
		root.add_child(_cam)
	var out := -1.0 if s["hand"] == 0 else 1.0
	if view == 1:
		out = -out
	# From above, higher the further the subjects spread from their middle.
	var spread := 0.0
	for i: int in which:
		var at_front := _sim.grid.cell_to_world(_subjects[i]["seat"]["front"])
		spread = maxf(spread, at_front.distance_to(mid))
	var at := Vector3(0.0, 3.2 + spread * 1.6, 0.6) if top else Vector3(out * 1.6, 1.9, 2.6)
	var look := Vector3(0.0, 0.3, 0.0) if top else Vector3(out * 0.25, 0.75, -0.15)
	if view == 2:
		at = Vector3(0.0, 2.6, 2.6)
		look = Vector3(0.0, 0.6, -0.1)
	_cam.look_at_from_position(frame * at, frame * look, Vector3.UP)
	_cam.current = true
	await _frames(2)
	var img := root.get_texture().get_image()
	var size := Vector2(img.get_size())
	var inside := Rect2(Vector2.ONE * MARGIN_PX, size - Vector2.ONE * 2.0 * MARGIN_PX)
	var subjects := {}
	for n in nodes.size():
		# Each roller its own tag: another roller in front of it is a blocker,
		# never a landing that proves this one (two rollers in a RUN plate).
		subjects[nodes[n]] = _bag_tag(n)
		var points := {
			"feet": bodies[n].global_position,
			"head": bodies[n].global_position + Vector3.UP * 1.6,
			"bag": nodes[n].global_position,
		}
		for name: String in points:
			var px := _cam.unproject_position(points[name])
			if _cam.is_position_behind(points[name]) or not inside.has_point(px):
				print(
					(
						"PLATE_REFUSED %s view %d: %s of %d at %s out of frame"
						% [shot, view, name, n, px]
					)
				)
				return false
			print("PLATE %s guest %d %s at %s" % [shot, n, name, px.round()])
		var tall := _cam.unproject_position(points["feet"]).distance_to(
			_cam.unproject_position(points["head"])
		)
		if tall < MIN_BODY_PX and not top:
			print("PLATE_REFUSED %s view %d: guest %d is %.0f px tall" % [shot, view, n, tall])
			return false
	var holder := PlateSight.colliders(root, [_views, _mode.get_node("BuildView")], subjects)
	if not (holder.get_meta("unbaked") as Array).is_empty():
		_invalid("%s: skinned meshes without a sight collider" % shot)
	await physics_frame
	await physics_frame
	var space := _cam.get_world_3d().direct_space_state
	for n in nodes.size():
		var box := _bag_box(nodes[n])
		var c := box.get_center()
		var lines := _bag_lines(space, c, box.end.y - 0.02, _bag_tag(n))
		var on: int = (lines["on_subject"] as Array).size()
		if on < MIN_ON and (lines["blockers"] as Array).is_empty():
			# Nothing in front, but the lines passed over the shell: a roller
			# tilted on its wheels in the pull (the lay-down's k 0) fills only
			# one end of its box's top. Aimed at the box's middle height instead.
			lines = _bag_lines(space, c, c.y, _bag_tag(n))
			on = (lines["on_subject"] as Array).size()
			print(
				"PLATE %s view %d roller %d aimed at its middle height: on %d" % [shot, view, n, on]
			)
		print(
			(
				"PLATE %s view %d roller %d box %s sight on %d past %d blockers %s"
				% [shot, view, n, box, on, lines["past"], lines["blockers"]]
			)
		)
		if on < MIN_ON or not (lines["blockers"] as Array).is_empty():
			holder.free()
			_near_meshes(shot, c)
			print(
				(
					"PLATE_REFUSED %s view %d: roller %d (%s) %d of 5 lines on it"
					% [shot, view, n, _views.get_path_to(nodes[n]), on]
				)
			)
			return false
	holder.free()
	var path := _out_dir.path_join("gate_chair_%s.png" % shot)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return true
	_saved.append(path)
	var small := img.duplicate() as Image
	small.resize(CELL.x, CELL.y)
	_sheet.append(small)
	print("PLATE saved %s view %d" % [path, view])
	return true


## Five sight lines from the camera to a roller body box with middle `c`, at
## height `y`: over the middle and 0.08 m either way across x, 0.12 m along z.
## Only a first hit on the roller tagged `tag` (_bag_tag()) lands; a hit on
## any other roller in front of the target is a blocker.
func _bag_lines(space: PhysicsDirectSpaceState3D, c: Vector3, y: float, tag: String) -> Dictionary:
	var targets: Array[Vector3] = [Vector3(c.x, y, c.z)]
	for d in [Vector3(0.08, 0, 0), Vector3(-0.08, 0, 0), Vector3(0, 0, 0.12), Vector3(0, 0, -0.12)]:
		targets.append(Vector3(c.x, y, c.z) + d)
	return PlateSight.sight_lines(space, _cam.global_position, targets, tag)


## The sight tag of the `n`th roller of a plate.
static func _bag_tag(n: int) -> String:
	return "%s%d" % [BAG_TAG, n]


## A NEAR row for each visible mesh drawn by the views within 1 m of `at` (a
## refused roller's box middle): its path and box, to name what the sight
## lines met.
func _near_meshes(shot: String, at: Vector3) -> void:
	for mi: MeshInstance3D in _views.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null or mi.skin != null:
			continue
		var box := mi.global_transform * mi.get_aabb()
		if box.get_center().distance_to(at) < 1.0:
			print("NEAR %s %s box %s" % [shot, _views.get_path_to(mi), box])


## The world box of roller `node`'s body, its rods and pull grip left out
## (CarryOnProps.REACH_NODES): a box with the rods reached past the shell, so
## sight lines aimed at its middle missed the roller.
func _bag_box(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var rods: Array = CarryOnProps.REACH_NODES[SecurityLooks.Kind.ROLLER]
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if _part_label(mi, node, rods).ends_with(" rod"):
			continue
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
