class_name TestCarryStallLead
extends GdUnitTestSuite
## Carry-on moves inside a toilet stall are hand-led (board item c7b0e7be;
## decision carry-on-bags-stay-in-the-hand-during-every-move-no-overhead,
## "every move"): on every drawn frame of a toilet visit, from the step into
## the stall to the step out, every bag of every kind is held (within 5 cm of
## a hand's grip), worn or resting on the floor (the probes' FLOAT check,
## spike/carry_float_check.gd), never in the air. Checked on the drawn bag
## nodes (CarryOnProps through PassengerViews), frames part-way between ticks
## as in a game drawn faster than it ticks.

const FloatCheck := preload("res://spike/carry_float_check.gd")
## Sim ticks per frame: a 6-tick move is seen at k = 0.125, 0.25, ...
const FRAME_TICKS := 0.75
## [first bag's kind, bags].
const VISITS := [
	[SecurityLooks.Kind.CASE, 1],
	[SecurityLooks.Kind.BACKPACK, 1],
	[SecurityLooks.Kind.SHOULDER, 1],
	[SecurityLooks.Kind.ROLLER, 1],
	[SecurityLooks.Kind.ROLLER, 2],
]

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	_free_world()
	PassengerTestWorld.tracker = null


func _free_world() -> void:
	if _views != null:
		_views.free()
		_world.free_all()
	_views = null


## A passenger with `count` bags, the first of `kind`, sent to a stall in a
## new world with the views drawing (as TestCarryInStall does).
func _visitor(kind: SecurityLooks.Kind, count: int) -> Passenger:
	_free_world()
	var grid := BuildGrid.new()
	ToiletTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	# The test runs the pre-draw fallback itself at the end of each frame.
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while SecurityLooks.bag_kind(p, 0) != kind:
		ToiletTestLayout.calm(p)
		p.carry_on = 0
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = count
	p.liquids = false
	p.alarm = false
	p.stage = Passenger.Stage.TO_SECURITY
	p.at = Vector2i(20, 14)
	p.clear_path()
	assert_bool(_world.sim.toilets.try_visit(p)).is_true()
	return p


## One frame `ticks` sim ticks on, as the game draws them.
func _tick(ticks: float) -> void:
	_world.clock.advance(SimClock.STEP * ticks)
	await get_tree().process_frame
	await get_tree().create_timer(0.0, true, false, true).timeout
	_views.carry_on_props()._unposed()


## The FLOAT check over `p`'s visit while it is in the stall: {"states": state
## -> frames, "moving": move -> [held frames, resting or worn frames],
## "floats": the FLOAT lines}.
func _stall_frames(p: Passenger) -> Dictionary:
	var props := _views.carry_on_props()
	var out := {"states": {}, "moving": {}, "floats": []}
	var visited := false
	while _world.clock.tick < 20000:
		var sat := _world.clock.tick - p.stage_tick
		if p.stage == Passenger.Stage.TOILET_USE and sat < ToiletSim.USE_TICKS - 4:
			_world.step()
			continue
		await _tick(FRAME_TICKS)
		if not StallCarry.in_stall(p):
			if visited:
				break
			continue
		visited = true
		for b in (props.props_of(p.id)["bags"] as Array).size():
			var state := FloatCheck.float_state(_world.sim, _views, p.id, b)
			out["states"][state[0]] = int(out["states"].get(state[0], 0)) + 1
			var move := FloatCheck.move_of(props, p.id, b)
			if state[0] == "float":
				out["floats"].append(
					(
						"%s bag %d %s k=%.2f hand_gap=%.3f rest_gap=%.3f"
						% [
							Passenger.Stage.keys()[p.stage],
							b,
							move,
							props.transfer_progress(p.id, b),
							state[1],
							state[2]
						]
					)
				)
			if move != "":
				var key := move.replace(".R", "").replace(".L", "")
				var seen: Array = out["moving"].get(key, [0, 0])
				seen[0 if state[0] == "held" else 1] += 1
				out["moving"][key] = seen
	assert_bool(visited).is_true()
	return out


## Every bag kind, one bag and two rollers: no drawn frame in the stall has a
## bag in the air, and each bag's set-down and pick-up are carried in the hand
## (frames held while it moves). Control: both moves were seen, with held
## frames, and frames resting on the floor.
func test_every_bag_in_a_stall_is_held_or_resting_on_every_frame() -> void:
	for visit: Array in VISITS:
		var kind: SecurityLooks.Kind = visit[0]
		var seen := await _stall_frames(_visitor(kind, visit[1]))
		var floats: Array = seen["floats"]
		print(
			(
				"%s x%d in the stall: states %s, moves [held, resting or worn] %s, float %d"
				% [
					SecurityLooks.Kind.keys()[kind],
					visit[1],
					seen["states"],
					seen["moving"],
					floats.size()
				]
			)
		)
		for line: String in floats.slice(0, 6):
			print("  FLOAT ", line)
		var down := 0
		var up := 0
		for move: String in seen["moving"]:
			var counts: Array = seen["moving"][move]
			if move.ends_with(">floor"):
				down += counts[0]
			elif move.begins_with("floor>"):
				up += counts[0]
		assert_int(down).is_greater(0)
		assert_int(up).is_greater(0)
		assert_int(int(seen["states"].get("resting", 0))).is_greater(0)
		assert_int(floats.size()).is_equal(0)
