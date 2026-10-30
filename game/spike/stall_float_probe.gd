extends SceneTree
## Windowed probe of carry-on moves in a toilet stall (board item c7b0e7be;
## decision carry-on-bags-stay-in-the-hand-during-every-move-no-overhead,
## "every move") in the real main scene. Boots main/main.tscn with a new random
## sim seed (printed; ++ --seed=N to replay), builds ToiletTestLayout's two
## toilet rooms (three stalls each) on the reference terminal, staffs it and
## opens the airport, then sends visitors one at a time (VISITORS: a case, a
## backpack, a shoulder tote, a roller, a roller with a second bag), each with a
## pressing toilet need, and drives the clock by hand, FRAME_TICKS a frame
## (frames fall part-way between ticks, as in a game drawn faster than it
## ticks). A visitor not on its way to a stall RESEND_TICKS after it was sent
## (late in the day it may not fit a visit before its flight) is replaced by
## another of the same kind (printed).
##
## Every frame: the FLOAT check (spike/carry_float_check.gd) on every drawn
## bag of every passenger, and the stall's own tally of it for the visitor
## inside a stall (STALL_FLOAT); its control once. Every frame the visitor is
## inside a stall: SELF, the drawn body's vertices inside each of its bags'
## meshes (left out per bag: the hands holding that bag, reaching for it or
## letting go of it; a hand holding one bag still counts against the other),
## and GRIP: every frame a hand holds a moving bag in the stall, how far straight
## down from its grip the bag's mesh is and how far its nearest face is (a hard
## case is held from above, its mesh GRIP_OVER_M at most under the grip, so a
## hand beside it has none under it; a roller by its bar, its mesh GRIP_NEAR_M
## at most from the grip, which may be inside the bar), with its control: the
## same on a hard case's old stall grip point, its bounds' top corner
## (CarryOnProps.grip_anchor), which must miss on its set-downs. One
## bag of each visitor (VISITORS) has its set-down and pick-up in the stall
## caught as they start (the clock pauses with no time over) and plated at each
## MOMENTS window, the paused clock stepped there a third of a tick a
## frame: a close plate from over the stall (the partitions are 2.22 m tall,
## so a camera beside them sees nothing inside), and a detail plate of the bag
## from the side with every toilet stall hidden (a cutaway, so the hand on the
## bag can be seen). Each plate proves the body and the bag are in frame (their
## drawn bounds projected inside the viewport less MARGIN_PX), that sight
## lines land on them with no blocker (the exceptions are in _lines_on), and
## that it is not dark, or tries the
## next camera; each moment prints the bag's FLOAT state and SELF_HEAD (head
## and neck points inside the bag). Any FLOAT, a control not caught, SELF or
## SELF_HEAD over 0, a GRIP miss or its control not caught, a move not
## hand-led or a plate missing prints PROBE_INVALID and exits 1. A guard thread
## calls OS.crash() on a stalled main thread.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 1200 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/stall_float_probe.gd [-- --seed=N --run=NAME]
## Plates go to tools/blender/out/stall-bags/[NAME/].

const FloatCheck := preload("res://spike/carry_float_check.gd")
const PlateSteps := preload("res://spike/carry_plate_steps.gd")
const PlateSight := preload("res://spike/plate_sight.gd")
const CarryContact := preload("res://spike/carry_contact.gd")
const CarryChecks := preload("res://spike/carry_probe_checks.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/stall-bags"
const HANG_MS := 90000
const LAST_TICKS := 3000
## A visitor not on its way to a stall this long after it was sent is replaced.
const RESEND_TICKS := 900
## Ticks drawn a frame near and in the stall, and while nothing moves (the
## walk there from afar, sitting on the seat).
const FRAME_TICKS := 0.5
const FAST_TICKS := 2.0
## A visit is followed this long after the visitor left the stall (the bags
## go back on the back and to the pull outside it).
const AFTER_TICKS := 60
## [label, first bag's kind, bags, the bag plated (its index; -1 none)].
const VISITORS := [
	["case", SecurityLooks.Kind.CASE, 1, 0],
	["backpack", SecurityLooks.Kind.BACKPACK, 1, 0],
	["shoulder", SecurityLooks.Kind.SHOULDER, 1, 0],
	["roller", SecurityLooks.Kind.ROLLER, 1, 0],
	["roller2", SecurityLooks.Kind.ROLLER, 2, 1],
]
## The plated moments of each move (its progress window): set-down mid-drop,
## landing (a bag from the hand is let go from k 0.45, CarryLead.STALL_LET_GO;
## a tote from 0.75) and let go; pick-up just lifted, rising and turning into
## the carry.
const MOMENTS := {
	"set-down": [[0.2, 0.3], [0.38, 0.44], [0.6, 0.7]],
	"pick-up": [[0.3, 0.4], [0.5, 0.6], [0.68, 0.76]],
	# A backpack taken off the back into the hand before the stall and put back
	# on after it, mid-move (anti-pattern a-float-hand-gap-of-0-does-not-prove-a-
	# carried-bag-is-grippe: the palm on the loop, the pack clear of the body).
	"off-back": [[0.45, 0.55]],
	"on-back": [[0.45, 0.55]],
}
## The close plate's camera: this high over the floor, offset this far across
## and out of the door from the middle of the body and the bag (the door's
## leaves, the rail over the door and the side partitions are under the line to
## the bag), its field of view fitted so the two fill FILL of the frame's height.
const OVER_M := 6.0
const OFFSETS: Array[Vector2] = [
	Vector2(0.35, 0.25),
	Vector2(-0.35, 0.25),
	Vector2(0.35, -0.3),
	Vector2(-0.35, -0.3),
	Vector2(0.3, -0.7),
	Vector2(-0.3, -0.7),
	Vector2(0.6, 0.0),
	Vector2(-0.6, 0.0),
	Vector2(0.0, -1.0),
]
const FILL := 0.6
const MARGIN_PX := 8.0
## The detail plate's camera starts on this side of the bag, this high over its
## middle (PlateSteps.detail_plate turns it about the bag from there).
const DETAIL_SIDE_M := 1.0
const DETAIL_UP_M := 0.45
const SELF_PRINTS := 4
## A hand holding a hard case has the case's mesh this close under its grip: on
## its top FRONT_PALM_M, in front its handle as far under it and the face beside
## the handle (3 cm wide, 3.6 cm proud) 7.6 cm. A hand holding a roller by its
## bar has the roller's mesh this close to its grip (BAR_PALM_M off the bar's
## middle, the bar 3.2 cm thick). A backpack is held by its loop with the grip
## past its face (CarryLead.LOOP_OFFSET) and a tote by its strap, so theirs are
## printed, not judged.
const GRIP_OVER_M := 0.08
const GRIP_NEAR_M := 0.05
const GRIP_PRINTS := 3

var _out_dir := ""
var _failed := false
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _stop := false

var _main: Node3D
var _sim: PassengerSim
var _clock: SimClock
var _views: PassengerViews
var _floats := FloatCheck.float_counts()
var _float_control := []
## The visitor's bags while it is inside a stall: FLOAT frames, frames
## checked, SELF points by move, frames with SELF points, head points.
var _stall_float := 0
var _stall_frames := 0
var _self_by := {}
var _self_frames := 0
var _self_head := 0
var _head_checks := 0
## The visit now: its passenger, whether it is plated, the moves plated (bag
## 0's moves in the stall, by "set-down" or "pick-up") and wanted.
var _visitor: Passenger
var _label := ""
var _plate_bag := -1
var _plated := {}
## Passenger id -> the stall it visited last (_stall_of()).
var _last_stall := {}
var _plate_task := false
var _hold := false
var _plates_saved := 0
var _plates_wanted := 0
var _not_led := 0
## GRIP by "label move bag kind": [frames, misses, nearest, farthest]; the
## control's frames and misses.
var _grip_by := {}
var _grip_misses := 0
var _grip_control := [0, 0]
var _case_sent := false


func _initialize() -> void:
	var run := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--run="):
			run = "/" + arg.get_slice("=", 1)
	_out_dir = ProjectSettings.globalize_path(OUT_REL + run).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=%s" % _out_dir)
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	var seed := randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = int(arg.trim_prefix("--seed="))
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	root.add_child(_main)
	_clock.set_process(false)
	_clock.set_paused(false)
	await _frames(3)
	var mode := _main.get_node("BuildMode") as BuildMode
	mode.set_process(false)
	mode.set_tool(BuildMode.Tool.NONE)
	(mode.get_node("Ghost") as Node3D).visible = false
	_sim = _main.get_node("PassengerSim") as PassengerSim
	_views = _main.get_node("PassengerViews") as PassengerViews
	_beat("build")
	var ids := ToiletTestLayout.build(mode.grid, 3, mode.shell)
	(mode.get_node("BuildView") as BuildView).refresh(mode.grid)
	await _frames(4)
	_sim.toilets.refresh()
	print("PROBE ids=%s usable_stalls=%d" % [ids, _sim.toilets.layout.stalls.size()])
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE staff hired=%d opened tick=%d doors_close_tick=%d" % [hired, _clock.tick, doors])
	if hired == 0 or doors < 0 or _sim.toilets.layout.stalls.size() != 6:
		_invalid("the airport did not open, or not six usable stalls")
	else:
		_clock.ticked.connect(_on_tick)
		# ++ --only=case,roller sends those alone (to iterate; an acceptance run
		# sends every visitor).
		var only := PackedStringArray()
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--only="):
				only = arg.trim_prefix("--only=").split(",")
		for visitor: Array in VISITORS:
			if only.is_empty() or only.has(visitor[0]):
				await _visit(visitor)
	_report()
	_finish()
	print("PROBE exit=%d" % (1 if _failed else 0))
	quit(1 if _failed else 0)


## Sends one visitor and checks every frame of its visit; its plates are
## taken as their moments come (_on_tick, _plate_move).
func _visit(visitor: Array) -> void:
	_label = visitor[0]
	_beat("spawn %s" % _label)
	_visitor = _spawn(visitor[1], visitor[2])
	_plate_bag = visitor[3]
	_case_sent = _case_sent or visitor[1] == SecurityLooks.Kind.CASE
	_plated = {}
	print("VISITOR %s passenger=%d kinds=%s" % [_label, _visitor.id, _kinds(_visitor)])
	var p := _visitor
	var last := _clock.tick + LAST_TICKS
	var sent := _clock.tick
	var visited := false
	var left := -1
	while _clock.tick < last:
		_beat("%s tick %d" % [_label, _clock.tick])
		# One sent late in the day may never fit a toilet visit before its flight:
		# another of the same kind is sent (printed).
		if not Passenger.in_toilet(p.stage) and not visited and _clock.tick - sent > RESEND_TICKS:
			_visitor = _spawn(visitor[1], visitor[2])
			print(
				(
					"RESEND %s passenger=%d (passenger %d at %s)"
					% [_label, _visitor.id, p.id, _name(p)]
				)
			)
			p = _visitor
			sent = _clock.tick
			last = sent + LAST_TICKS
		if not _plate_task and not _hold:
			_clock.advance(SimClock.STEP * _ticks_now(p))
		await process_frame
		await RenderingServer.frame_post_draw
		_check_frame(p)
		visited = visited or StallCarry.in_stall(p)
		if visited and left < 0 and not Passenger.in_toilet(p.stage):
			left = _clock.tick
		if left >= 0 and _clock.tick - left > AFTER_TICKS and not _plate_task:
			break
	if left < 0:
		_invalid("%s never left the stall by tick %d (stage %s)" % [_label, last, _name(p)])
	if _plate_bag >= 0:
		var moves := ["set-down", "pick-up"]
		if visitor[1] == SecurityLooks.Kind.BACKPACK:
			moves.append_array(["off-back", "on-back"])
		for move in moves:
			if not _plated.get(move, false):
				_invalid("%s: the %s was not plated" % [_label, move])
	_visitor = null


## How many ticks the next frame draws: FAST_TICKS far from the stall or
## sitting on the seat, FRAME_TICKS otherwise.
func _ticks_now(p: Passenger) -> float:
	if p.stage == Passenger.Stage.TOILET_USE:
		var sat := _sim.tick - p.stage_tick
		return FAST_TICKS if sat < ToiletSim.USE_TICKS - 4 else FRAME_TICKS
	if StallCarry.in_stall(p) or StallCarry.held_by_hand(_sim, p, 2.0):
		return FRAME_TICKS
	return FAST_TICKS


## A passenger whose first bag is `kind`, with `count` bags and a pressing
## toilet need; the passengers spawned on the way have no bags and no needs.
func _spawn(kind: SecurityLooks.Kind, count: int) -> Passenger:
	var flight := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	while true:
		var p := _sim.get_passenger(_sim.spawn_now(flight))
		ToiletTestLayout.calm(p)
		p.carry_on = 0
		if SecurityLooks.bag_kind(p, 0) == kind:
			p.carry_on = count
			p.toilet_need = 95
			p.toilet_cooldown = 0
			return p
	return null


func _kinds(p: Passenger) -> Array:
	var out := []
	for i in p.carry_on:
		out.append(SecurityLooks.Kind.keys()[SecurityLooks.bag_kind(p, i)])
	return out


## One frame's checks: FLOAT on every bag, its control once, and the
## visitor's stall tally and SELF.
func _check_frame(p: Passenger) -> void:
	FloatCheck.watch_float(_sim, _views, _floats)
	var props := _views.carry_on_props()
	var body := _views.node_for(p.id)
	if body == null or not body.is_visible_in_tree():
		return
	var bags: Array = props.props_of(p.id)["bags"]
	if _float_control.is_empty() and not bags.is_empty() and bags[0].is_visible_in_tree():
		_float_control = FloatCheck.float_control(_sim, _views, p.id)
	if not StallCarry.in_stall(p):
		return
	var any := false
	for i in bags.size():
		_stall_frames += 1
		var state := FloatCheck.float_state(_sim, _views, p.id, i)
		_stall_float += int(state[0] == "float")
		var move := FloatCheck.move_of(props, p.id, i)
		if move != "" and not props.bag_state(p.id, i).get("led", false):
			_not_led += 1
			print("NOT_LED %s bag=%d move=%s" % [_label, i, move])
		_check_grip(p, props, body, bags[i], i, move)
		var grip := _hands_on(p, props, i)
		var own := CarryContact.body_points(body, grip)
		var hits := CarryContact.inside_meshes(own, bags[i])
		if hits == 0:
			continue
		any = true
		var key := "%s %s" % [_label, move if move != "" else "settled"]
		var seen: Array = _self_by.get(key, [0, 0, 0])
		_self_by[key] = [seen[0] + hits, seen[1] + 1, maxi(seen[2], hits)]
		if seen[1] < SELF_PRINTS:
			var bones := CarryChecks.contact_bones(body, grip, bags[i])
			print(
				(
					"SELF %s bag=%d move=%s k=%.2f stage=%s points=%d reach_short_m=%.3f bones=%s"
					% [
						_label,
						i,
						move,
						props.transfer_progress(p.id, i),
						_name(p),
						hits,
						_reach_short(
							props, body, props.bag_state(p.id, i), props.transfer_progress(p.id, i)
						),
						bones
					]
				)
			)
	_self_frames += int(any)


## The hands left out of SELF for bag `i` of `p`: the one holding it by its
## home's carry (CarryProbeChecks.gripping, for this bag alone), the one placing
## it now, and any reaching for it or letting go of it in a hand-led move
## (CarryLead's weights).
func _hands_on(p: Passenger, props: CarryOnProps, i: int) -> Array:
	var hands := []
	if SecurityLooks.bag_homes(_sim, p)[i] == SecurityLooks.Home.HAND:
		match SecurityLooks.carry_of(p, i):
			SecurityLooks.Carry.HAND, SecurityLooks.Carry.PULL:
				hands.append(SecurityLooks.hand_of(_sim, p, i))
			SecurityLooks.Carry.SHOULDER:
				hands.append(SecurityLooks.worn_side(i))
	var bag := props.bag_state(p.id, i)
	hands.append(int(bag.get("held_by", -1)))
	if props.transfer_progress(p.id, i) < 1.0 and bag.has("lead"):
		for hand in 2:
			if float(bag["lead"]["weights"][hand]) > 0.0:
				hands.append(hand)
	var out := []
	for hand: int in hands:
		if hand >= 0 and not out.has([".R", ".L"][hand]):
			out.append([".R", ".L"][hand])
	return out


## GRIP for bag `i` (`node`) of `p` on `move`: while a hand holds it (places
## it from its grip) in a hand-led move, the bag's mesh straight under the grip;
## and the control on a hard case being set down: its old stall grip point.
func _check_grip(
	p: Passenger, props: CarryOnProps, body: Node3D, node: Node3D, i: int, move: String
) -> void:
	var bag := props.bag_state(p.id, i)
	var holder := int(bag.get("held_by", -1))
	if move == "" or holder < 0 or not bag.get("led", false):
		return
	var kind: SecurityLooks.Kind = bag["kind"]
	var k := props.transfer_progress(p.id, i)
	var at := props.grip_of(body, holder)
	var over := _over(node, at)
	var near := _near(node, at)
	var key := "%s %s bag=%d %s" % [_label, move, i, SecurityLooks.Kind.keys()[kind]]
	# [frames, misses, over from, over to, nearest from, nearest to]
	var seen: Array = _grip_by.get(key, [0, 0, INF, 0.0, INF, 0.0])
	var miss := false
	if kind == SecurityLooks.Kind.CASE:
		miss = over > GRIP_OVER_M
	elif kind == SecurityLooks.Kind.ROLLER:
		miss = near > GRIP_NEAR_M
	_grip_by[key] = [
		seen[0] + 1,
		seen[1] + int(miss),
		minf(seen[2], over),
		maxf(seen[3], over),
		minf(seen[4], near),
		maxf(seen[5], near),
	]
	if miss:
		_grip_misses += 1
		if seen[1] < GRIP_PRINTS:
			print("GRIP_MISS %s k=%.2f over_m=%.3f near_m=%.3f" % [key, k, over, near])
	if kind == SecurityLooks.Kind.CASE and move.ends_with(">floor"):
		var old: Vector3 = node.global_transform * CarryOnProps.grip_anchor(kind)
		var old_over := _over(node, old)
		_grip_control[0] += 1
		_grip_control[1] += int(old_over > GRIP_OVER_M)
		if _grip_control[0] <= GRIP_PRINTS:
			print(
				(
					"GRIP_CONTROL %s k=%.2f over_m=%.3f old_over_m=%.3f old_near_m=%.3f"
					% [key, k, over, old_over, _near(node, old)]
				)
			)


## How far straight down from `at` the nearest face of `node`'s meshes is (as
## drawn), or INF when none is under it.
func _over(node: Node3D, at: Vector3) -> float:
	var best := INF
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var faces := mi.mesh.get_faces()
		var xf := mi.global_transform
		for f in range(0, faces.size() - 2, 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(
				at, Vector3.DOWN, xf * faces[f], xf * faces[f + 1], xf * faces[f + 2]
			)
			if hit != null:
				best = minf(best, at.y - (hit as Vector3).y)
	return best


## How far the nearest face of `node`'s meshes (as drawn) is from `at`.
func _near(node: Node3D, at: Vector3) -> float:
	var best := INF
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var faces := mi.mesh.get_faces()
		var xf := mi.global_transform
		for f in range(0, faces.size() - 2, 3):
			best = minf(best, _to_face(at, xf * faces[f], xf * faces[f + 1], xf * faces[f + 2]))
	return best


## How far `at` is from the triangle `a`, `b`, `c`: from its plane when it
## lies over the triangle, else from its nearest edge.
static func _to_face(at: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var n := (b - a).cross(c - a)
	if n.length_squared() > 1e-12:
		n = n.normalized()
		if Geometry3D.ray_intersects_triangle(at + n, -n, a, b, c) != null:
			return absf(n.dot(at - a))
	var best := at.distance_to(Geometry3D.get_closest_point_to_segment(at, a, b))
	best = minf(best, at.distance_to(Geometry3D.get_closest_point_to_segment(at, b, c)))
	return minf(best, at.distance_to(Geometry3D.get_closest_point_to_segment(at, c, a)))


## On each sim tick, after the views' sync: the visitor's bag 0 about to start
## its set-down or pick-up in the stall pauses the clock with no time over, so
## the move is first drawn at k 0, and its plates are taken.
func _on_tick(_tick: int) -> void:
	var p := _visitor
	if p != null and _sim.toilets.visit_of(p.id) != null:
		_stall_of(p)
	if p == null or _plate_bag < 0 or _plate_task or _hold:
		return
	var props := _views.carry_on_props()
	var move := PlateSteps.pending_move(props, p.id, _plate_bag)
	if move == "":
		return
	var which := "set-down" if move.ends_with(">floor") else "pick-up"
	var floor_move := move.ends_with(">floor") or move.begins_with("floor>")
	# A backpack taken off the back before the stall and put back on after it.
	if move.begins_with("back") and move.contains(">hand"):
		which = "off-back"
	elif move.begins_with("hand") and move.contains(">back"):
		which = "on-back"
	elif not (floor_move and StallCarry.in_stall(p)):
		return
	if _plated.has(which):
		return
	_clock.set_paused(true)
	_clock._accumulator = 0.0
	_hold = true
	_plate_task = true
	_plate_move.call_deferred(p, which)


## The plates of one move of the visitor's bag 0 at each MOMENTS window.
func _plate_move(p: Passenger, which: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	_hold = false
	var props := _views.carry_on_props()
	var move := FloatCheck.move_of(props, p.id, _plate_bag)
	var saved := 0
	var moments: Array = MOMENTS[which]
	for m in moments.size():
		var lo: float = moments[m][0]
		var hi: float = moments[m][1]
		_beat("plate %s %s %d" % [_label, which, m])
		_clock.set_paused(true)
		await PlateSteps.step_to(self, _clock, props, p.id, _plate_bag, lo, hi)
		await _frames(1)
		var k := props.transfer_progress(p.id, _plate_bag)
		var body := _views.node_for(p.id)
		var bags: Array = props.props_of(p.id)["bags"]
		if body == null or FloatCheck.move_of(props, p.id, _plate_bag) != move or k < lo or k > hi:
			_invalid("%s %s moment %d missed at k %.2f (move %s)" % [_label, which, m, k, move])
			break
		var state := FloatCheck.float_state(_sim, _views, p.id, _plate_bag)
		var rig: Dictionary = body.get_meta(&"carry_rig", {})
		var stoop: float = (rig["stoop"] as CarryStoop).drawn if rig.has("stoop") else -1.0
		var key := "%s %s" % [_label, which]
		_head_checks += 1
		_self_head += PlateSteps.head_in_bag(body, bags[_plate_bag], key, k)
		var name := "lead_%s_%s_%d_k%03d" % [_label, which, m, roundi(k * 100.0)]
		var bag := props.bag_state(p.id, _plate_bag)
		var short := _reach_short(props, body, bag, k)
		print(
			(
				(
					"LEAD_PLATE %s move=%s moment=%d k=%.2f state=%s hand_gap_m=%.3f stoop=%.2f"
					+ " reach_short_m=%.3f led=%s file=%s"
				)
				% [key, move, m, k, state[0], state[1], stoop, short, bag.get("led", false), name]
			)
		)
		_plates_wanted += 2
		if await _plate_close(p, bags[_plate_bag], name):
			saved += 1
	_plated[which] = saved == moments.size()
	_clock.set_paused(false)
	_plate_task = false


## How far the leading hand's grip is from where the move of `bag` (a
## CarryOnProps record) aims it, or -1 out of a hand-led move (the bag is
## placed from the grip, so a short reach leaves it nearer the body, and at a
## let-go it jumps by as much).
func _reach_short(props: CarryOnProps, body: Node3D, bag: Dictionary, k: float) -> float:
	if not bag.has("lead") or k >= 1.0:
		return -1.0
	var lead: Dictionary = bag["lead"]
	var hand := 0 if float(lead["weights"][0]) >= float(lead["weights"][1]) else 1
	return props.grip_of(body, hand).distance_to(lead["targets"][hand])


## A close plate of `p` and `bag` from over the stall, then the bag's detail
## plate (a cutaway, every toilet stall hidden). Returns whether both saved.
func _plate_close(p: Passenger, bag: Node3D, name: String) -> bool:
	var body := _views.node_for(p.id)
	var layers: Array[CanvasLayer] = []
	for node in _main.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		if layer.visible:
			layer.visible = false
			layers.append(layer)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	var owners: Array[Node] = [_views]
	for path in ["Airside/Terminal", "BuildMode", "StaffCharacters", "BaggageViews"]:
		owners.append(_main.get_node(path))
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)
	var stall := _stall_of(p)
	var saved := false
	for o in OFFSETS.size():
		var tag := "%s over %d" % [name, o]
		var both := _bounds(body).merge(_bounds(bag))
		var mid := both.get_center()
		var eye: Vector3 = (
			Vector3(mid.x, OVER_M, mid.z)
			+ stall["across"] * OFFSETS[o].x
			+ stall["out"] * OFFSETS[o].y
		)
		cam.fov = 30.0
		cam.global_position = eye
		cam.look_at(mid, stall["out"])
		cam.fov = _fitted_fov(cam, both)
		await _frames(2)
		var img := root.get_texture().get_image()
		var holder := PlateSight.colliders(root, owners, {body: "subject", bag: "bag"})
		PlateSteps.see_both_sides(holder)
		await physics_frame
		await physics_frame
		var bounds: Dictionary = holder.get_meta("bounds")
		var ok: bool = bounds.has("subject") and bounds.has("bag")
		ok = ok and (holder.get_meta("unbaked") as Array).is_empty()
		if ok:
			ok = _box_in_frame(cam, bounds["subject"], frame, tag + " body") and ok
			ok = _box_in_frame(cam, bounds["bag"], frame, tag + " bag") and ok
			var door_ok := name.contains("pick-up")
			ok = _lines_on(cam, bounds["subject"], "subject", tag, door_ok) and ok
			ok = _lines_on(cam, bounds["bag"], "bag", tag, door_ok) and ok
			var dark := PlateSteps.dark_share(img)
			print("INFRAME %s dark=%.2f" % [tag, dark])
			ok = ok and dark < PlateSteps.DARK_SHARE
		holder.free()
		if ok:
			saved = _save(img, name)
			break
	if not saved:
		_invalid("%s: no close plate with the body and the bag in frame and seen" % name)
	else:
		_plates_saved += 1
		# The detail: the bag from its side, every toilet stall hidden.
		var stalls := _stall_nodes()
		for node in stalls:
			node.visible = false
		var centre := _bounds(bag).get_center()
		var detail := _out_dir.path_join(name + "_detail_cutaway.png")
		var done := false
		# From the stall's one side, then (the hand on top of a small bag can hide
		# it from every turn about the first) from the other.
		for across: float in [1.0, -1.0]:
			cam.fov = 50.0
			cam.global_position = (
				centre + stall["across"] * DETAIL_SIDE_M * across + Vector3.UP * DETAIL_UP_M
			)
			cam.look_at(centre)
			done = await PlateSteps.detail_plate(self, cam, body, bag, owners, frame, detail)
			if done:
				break
		for node in stalls:
			node.visible = true
		if done:
			_plates_saved += 1
		else:
			_invalid("%s: no detail plate" % name)
		saved = done
	cam.queue_free()
	for layer in layers:
		layer.visible = true
	await _frames(1)
	return saved


## The field of view (degrees) for `cam`, aimed as it is, that makes `box`
## span FILL of the frame's height or width, whichever is tighter.
func _fitted_fov(cam: Camera3D, box: AABB) -> float:
	var to_cam := cam.global_transform.affine_inverse()
	var half := 0.0
	var aspect := root.get_visible_rect().size.x / root.get_visible_rect().size.y
	for c in 8:
		var at := to_cam * box.get_endpoint(c)
		var depth := maxf(-at.z, 0.1)
		half = maxf(half, maxf(absf(at.y), absf(at.x) / aspect) / depth)
	return rad_to_deg(2.0 * atan(half / FILL))


## Whether the corners of `box` all project inside `frame`, in front of `cam`.
## (PlateSteps.detail_plate calls it by name.)
func _box_in_frame(cam: Camera3D, box: AABB, frame: Rect2, tag: String) -> bool:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var ok := true
	for c in 8:
		var corner := box.get_endpoint(c)
		ok = ok and not cam.is_position_behind(corner)
		var px := cam.unproject_position(corner)
		lo = lo.min(px)
		hi = hi.max(px)
	ok = ok and frame.has_point(lo) and frame.has_point(hi)
	print("INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s" % [tag, lo.x, lo.y, hi.x, hi.y, ok])
	return ok


## Whether at least two sight lines from `cam` to `box` first hit a body
## tagged `tag`, and none first hits anything else before reaching it but the
## passenger (its own bag over the body, or the body over its bag, is the
## subject itself). With `door_ok` (a pick-up: the walker steps out through the
## closed door leaves and under the rail over them with its bag, a known
## residual) the stall's own meshes are printed, not counted, and at least
## three lines must land on the body. A bag under its own passenger bending over it passes
## with one line on it when the others land on that passenger (printed). The
## lines go to the bag's middle and four points about it, or (`tag` "subject")
## to nine points over the top fifth of the body, seen from above.
func _lines_on(cam: Camera3D, box: AABB, tag: String, label: String, door_ok: bool) -> bool:
	var space := cam.get_world_3d().direct_space_state
	var targets: Array[Vector3] = []
	if tag == "subject":
		for fx in [0.3, 0.5, 0.7]:
			for fz in [0.3, 0.5, 0.7]:
				targets.append(box.position + box.size * Vector3(fx, 0.85, fz))
	else:
		var right := cam.global_transform.basis.x
		var up := cam.global_transform.basis.y
		var reach := box.size.length() * 0.15
		for off in [Vector3.ZERO, right * reach, -right * reach, up * reach, -up * reach]:
			targets.append(box.get_center() + off)
	var on := 0
	var own := 0
	var blocked: Array[String] = []
	var doors: Array[String] = []
	for at in targets:
		var to := at + (at - cam.global_position).normalized() * 3.0
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(cam.global_position, to))
		if hit.is_empty():
			continue
		var what := str((hit.collider as Node).get_meta("subject", ""))
		var mesh := str((hit.collider as Node).get_meta("mesh", ""))
		if what == tag:
			on += 1
		elif what == "subject":
			own += 1
		elif what == "":
			if cam.global_position.distance_to(hit.position) < cam.global_position.distance_to(at):
				if door_ok and (mesh.begins_with("Door_Leaf") or mesh.begins_with("ToiletStall")):
					doors.append(mesh)
				else:
					blocked.append(mesh)
	print(
		(
			"INFRAME %s %s_lines_on=%d/%d on_own_body=%d blocked=%s stall_door_residual=%s"
			% [label, tag, on, targets.size(), own, blocked, doors]
		)
	)
	var under_body := tag == "bag" and on >= 1 and on + own >= 4
	var need := 3 if door_ok and tag == "subject" else 2
	return (on >= need or under_body) and blocked.is_empty()


## The drawn world bounds of `node`'s meshes.
func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Every drawn toilet stall piece (BuildView's nodes record their def).
func _stall_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node in _main.get_node("BuildMode/BuildView").get_children():
		var record: Dictionary = node.get_meta("record", {})
		if StringName(record.get("def", "")) == &"toilet_stall" and (node as Node3D).visible:
			out.append(node)
	return out


## The stall `p` visits (or last visited: a backpack goes back on after the
## visit, "on-back"): its footprint centre, its way out and across.
func _stall_of(p: Passenger) -> Dictionary:
	var visit := _sim.toilets.visit_of(p.id)
	if visit != null:
		_last_stall[p.id] = visit.stall
	var stall: Dictionary = _last_stall[p.id]
	var out := SecurityLooks.world_dir(stall["front"])
	return {
		"centre": stall["use"] - out * ToiletLayout.USE_M,
		"out": out,
		"across": out.cross(Vector3.UP),
	}


func _report() -> void:
	print(FloatCheck.float_report(_floats))
	print("STALL_FLOAT frames=%d float=%d not_led=%d" % [_stall_frames, _stall_float, _not_led])
	var self_total := 0
	for key: String in _self_by:
		self_total += int(_self_by[key][0])
	print(
		(
			"SELF_TOTAL points=%d frames=%d by_move=[points, frames, most]%s"
			% [self_total, _self_frames, _self_by]
		)
	)
	print("SELF_HEAD_TOTAL checks=%d inside=%d" % [_head_checks, _self_head])
	var grip_frames := 0
	for key: String in _grip_by:
		var g: Array = _grip_by[key]
		grip_frames += int(g[0])
		print(
			(
				"GRIP %s frames=%d misses=%d over_m=%.3f..%.3f near_m=%.3f..%.3f"
				% [key, g[0], g[1], g[2], g[3], g[4], g[5]]
			)
		)
	print(
		(
			(
				"GRIP_TOTAL frames=%d judged_misses=%d over_limit_m=%.2f near_limit_m=%.2f"
				+ " control frames=%d misses=%d"
			)
			% [
				grip_frames,
				_grip_misses,
				GRIP_OVER_M,
				GRIP_NEAR_M,
				_grip_control[0],
				_grip_control[1]
			]
		)
	)
	print("PLATES saved=%d wanted=%d" % [_plates_saved, _plates_wanted])
	PlateSteps.lead_sheet(_out_dir)
	if _floats["float"] > 0 or _stall_float > 0:
		_invalid("bags in the air: %d frames, %d in a stall" % [_floats["float"], _stall_float])
	if _stall_frames == 0:
		_invalid("no bag was checked inside a stall")
	if _float_control.size() != 2 or _float_control[0] != "float" or _float_control[1] == "float":
		_invalid("the FLOAT control was not caught or not let go: %s" % [_float_control])
	if self_total > 0 or _self_head > 0 or _head_checks == 0:
		_invalid(
			(
				"body points inside a bag in the stall: SELF %d, SELF_HEAD %d"
				% [self_total, _self_head]
			)
		)
	if _grip_misses > 0 or grip_frames == 0:
		_invalid("hands not on the bags they hold: %d GRIP misses" % _grip_misses)
	if _grip_control[1] == 0 and _case_sent:
		_invalid("the GRIP control was not caught: %s" % [_grip_control])
	if _not_led > 0:
		_invalid("%d frames of a stall move not hand-led" % _not_led)
	if _plates_saved != _plates_wanted or _plates_wanted == 0:
		_invalid("plates saved %d of %d" % [_plates_saved, _plates_wanted])


func _name(p: Passenger) -> String:
	return Passenger.Stage.keys()[p.stage]


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
		_beat(_stage)
	await RenderingServer.frame_post_draw


func _save(img: Image, name: String) -> bool:
	var path := _out_dir.path_join(name + ".png")
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return false
	print("PLATE saved %s size=%s" % [path, img.get_size()])
	return true


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
			OS.crash("stall_float_probe: main thread stalled in %s" % stage)
