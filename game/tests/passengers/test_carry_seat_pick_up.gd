class_name TestCarrySeatPickUp
extends GdUnitTestSuite
## A shoulder tote picked up off the floor by a gate chair as its walker
## stands up for boarding (floor>shoulder, outside a toilet stall; board item
## a-shoulder-tote-floats-0-39-m-from-the-hand-at-the-end-of-a) is held or
## worn on every drawn frame of the move and after it (the probes' FLOAT
## check, spike/carry_float_check.gd: held within 5 cm of a hand's grip, or
## worn within its gap limits), never in the air. Checked on the drawn bag
## nodes (CarryOnProps through PassengerViews) in the reference terminal, a
## tote alone and a tote as the second bag, frames part-way between ticks as in
## a game drawn faster than it ticks, and at 2 ticks a frame as the probes'
## fast frames.

const FloatCheck := preload("res://spike/carry_float_check.gd")
## [sim ticks per frame, ticks drawn before the first frame]: a 6-tick move
## seen at k = 1/12, 2/12, ..., and at the probes' FAST_TICKS (2 a frame) at
## k = 0.22, 0.56, 0.89 and 0.17, 0.5, 0.83.
const FRAME_STEPS := [[0.5, 0.0], [2.0, 1.0 / 3.0], [2.0, 1.0], [0.75, 0.25]]
## How long the walker is followed after its move began.
const AFTER_TICKS := 20

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


## The views go with the test's world (auto_free frees its sim at the test's
## end), so the next test draws nothing freed.
func after_test() -> void:
	_free_world()


func _free_world() -> void:
	if _views != null:
		_views.free()
		_world.free_all()
	_views = null


## A passenger with `count` bags, the last a shoulder tote, seated by hand at a
## gate chair (as the sim seats one) in a new reference terminal with the
## views drawing, its boarding a few ticks off.
func _sitter(count: int) -> Passenger:
	_free_world()
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	# The test runs the pre-draw fallback itself at the end of each frame.
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while SecurityLooks.bag_kind(p, count - 1) != SecurityLooks.Kind.SHOULDER:
		ToiletTestLayout.calm(p)
		p.carry_on = 0
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = count
	p.cleared = true
	for seat: Dictionary in _world.sim.layout.seats:
		p.stage = Passenger.Stage.SEATED
		p.stage_tick = _world.sim.tick
		p.seat_object = seat["object_id"]
		p.seat_cell = seat["cell"]
		p.seat_front = seat["front"]
		p.at = seat["front"]
		p.clear_path()
		break
	p.boarding_tick = _world.sim.tick + 8
	return p


## One frame `ticks` sim ticks on, as the game draws them.
func _tick(ticks: float) -> void:
	_world.clock.advance(SimClock.STEP * ticks)
	await get_tree().process_frame
	await get_tree().create_timer(0.0, true, false, true).timeout
	_views.carry_on_props()._unposed()


## The FLOAT check over `p`'s stand-up and walk off at `ticks` a frame (the
## first frame `offset` ticks on), until
## AFTER_TICKS after its tote's floor>shoulder move began: {"states": state ->
## frames, "ks": the move's k on each frame it was seen, "floats": the FLOAT
## lines}.
func _pick_up_frames(p: Passenger, ticks: float, offset: float) -> Dictionary:
	var props := _views.carry_on_props()
	await _tick(offset)
	var bag := p.carry_on - 1
	var out := {"states": {}, "ks": [], "floats": []}
	var began := -1
	while _world.clock.tick < 2000:
		await _tick(ticks)
		var move := FloatCheck.move_of(props, p.id, bag)
		if move.begins_with("floor>shoulder") and began < 0:
			began = _world.clock.tick
		if began < 0:
			continue
		if _world.clock.tick - began > AFTER_TICKS:
			break
		var state := FloatCheck.float_state(_world.sim, _views, p.id, bag)
		out["states"][state[0]] = int(out["states"].get(state[0], 0)) + 1
		var k := props.transfer_progress(p.id, bag)
		if move != "":
			out["ks"].append(snappedf(k, 0.01))
		if state[0] == "float":
			out["floats"].append(
				(
					"%s %s k=%.2f hand_gap=%.3f rest_gap=%.3f"
					% [Passenger.Stage.keys()[p.stage], move, k, state[1], state[2]]
				)
			)
	assert_int(began).is_greater(0)
	return out


## A tote alone and a tote as the second bag, at each frame step: no drawn
## frame of its pick-up or after has it in the air. Control: the move was seen
## on frames late in it (k past the hand's let go at 0.75), and both held and
## worn frames were seen.
func test_a_tote_picked_up_by_a_gate_chair_is_held_or_worn_on_every_frame() -> void:
	var late := 0
	for count in [1, 2]:
		for step: Array in FRAME_STEPS:
			var ticks: float = step[0]
			var seen := await _pick_up_frames(_sitter(count), ticks, step[1])
			var floats: Array = seen["floats"]
			print(
				(
					"tote as bag %d of %d, %.2f ticks a frame from %.2f: states %s, k seen %s, float %d"
					% [count - 1, count, ticks, step[1], seen["states"], seen["ks"], floats.size()]
				)
			)
			for line: String in floats.slice(0, 8):
				print("  FLOAT ", line)
			late += (seen["ks"] as Array).filter(func(k: float) -> bool: return k > 0.75).size()
			assert_int(int(seen["states"].get("held", 0))).is_greater(0)
			assert_int(int(seen["states"].get("worn", 0))).is_greater(0)
			assert_int(floats.size()).is_equal(0)
	assert_int(late).is_greater(0)


## A tote picked up off the floor onto the left shoulder (floor>shoulder.L,
## outside a stall), stepped through CarryLead.plan() over k 0 to 1 (0.01
## apart) with the shoulder joint where it stands upright and where it was
## drawn leaning in (stall_float_probe, seed 2486925799, passenger 3114: the
## other hand reaching low drew the left Arm bone 0.09 m from the centre line):
## at every k the bag rests at its start, is placed from the holding hand, or is
## worn, its drawn strap bar (Strap_Top, the strap stretched as CarryOnProps
## stretches it) within the FLOAT check's 0.2 m of the joint. Worn by a joint
## leaning in, it tilts about its strap's root with its bottom no nearer the
## hip than upright. Control: the worn end is reached and checked.
func test_a_tote_put_on_the_shoulder_from_the_floor_is_worn_at_every_k() -> void:
	var kind := SecurityLooks.Kind.SHOULDER
	var node := InteriorKit.instantiate(SecurityLooks.KIND_PIECES[kind])
	var reach_node := node.find_child("Strap_Reach", true, false) as Node3D
	var top_node := node.find_child("Strap_Top", true, false) as Node3D
	var base := reach_node.position
	var top_base := CarryOnProps._in_piece(top_node, node).origin
	node.free()
	var box := CarryOnProps.bag_box(kind)
	var bag := {
		"kind": kind,
		"was": (SecurityLooks.Home.FLOOR * 2 + 1) * 2,
		"home": (SecurityLooks.Home.HAND * 2 + 1) * 2,
		"carry": SecurityLooks.Carry.SHOULDER,
		"carry_from": SecurityLooks.Carry.SHOULDER,
		"from": Transform3D(),
	}
	var flags := {
		"in_stall": false,
		"hand_carry": false,
		"from_floor": true,
		"to_floor": false,
		"hand": 1,
		"clear": CarryOnProps.TRANSFER_CLEAR_M,
		"yaw": 0.0,
	}
	var start := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0.2, 0.0, 0.55))
	var upright_inner := 0.0
	var worn := 0
	for joint: Vector3 in [Vector3(0.206, 1.644, -0.06), Vector3(0.0896, 1.5005, -0.107)]:
		var hung := CarryWorn.shoulder(joint, Vector3.ZERO, 0.0, 1, 1.0, base)
		var want: Transform3D = hung[0]
		var length: float = hung[1]
		# Strap_Top as CarryOnProps._set_reach moves it.
		var bar := top_base + Vector3(0.0, 0.0, length - CarryOnProps.REACH_BUILT_M)
		var body := {
			"hand": 1,
			"grips": [Vector3(-0.25, 0.8, 0.05), Vector3(0.25, 0.8, 0.05)],
			"shoulders_y": [joint.y, joint.y],
			"bar_z": 0.0,
			"scale": 1.0,
			"strap_top": bar,
		}
		var gaps := []
		for step in 101:
			var k := step / 100.0
			var plan := CarryLead.plan(bag, k, start, want, Transform3D(), flags, body)
			if plan["holder"] >= 0:
				continue
			var xf: Transform3D = plan["xf"]
			if xf.is_equal_approx(start):
				continue
			assert_bool(xf.is_equal_approx(want)).is_true()
			var gap := maxf(0.0, (xf * bar).distance_to(joint) - 0.2)
			gaps.append(snappedf(gap, 0.001))
			assert_float(gap).is_equal(0.0)
			worn += 1
		var inner := (want * Vector3(0.0, 0.0, box.position.z)).x
		if joint.x > 0.2:
			upright_inner = inner
		print(
			(
				"joint %s: bar %s, worn gaps %s, inner bottom at %.3f"
				% [joint, want * bar, gaps, inner]
			)
		)
		assert_float(inner).is_greater_equal(upright_inner - 0.0001)
	assert_int(worn).is_greater(20)
