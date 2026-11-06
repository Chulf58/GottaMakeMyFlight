class_name TestStepOffWalk
extends GdUnitTestSuite
## A passenger with a roller that steps off its seat after it has stood up and
## picked the roller up (a sofa or nap pod visitor's step off, ActivityPoses.
## up_tail(); a cafe guest's last CafeSim.SHUFFLE_TICKS of CAFE_STANDING_UP)
## plays the walk clip at the drawn step's speed, not idle or a stand_up clip
## held on its last frame while the body slides (board c0707a22 part 3). A
## cafe guest with no roller steps out under its stand_up clip and every
## sit-down shuffle plays sit_down: both stay as they were.

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _world != null:
		_world.free_all()
		_world = null


func _make(grid: BuildGrid, starts: Array[int]) -> void:
	_world = PassengerTestWorld.make(grid, starts)
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)


## A spawned passenger whose first bag is a roller (`roller`) or not, carrying
## one bag. Spawns until the kind matches (a bag's kind is a hash of the id);
## the others are kept from every visit.
func _passenger(roller: bool) -> Passenger:
	for attempt in 200:
		var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		if (SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER) == roller:
			p.carry_on = 1
			return p
		p.cafe_cooldown = 1000000
		p.shop_cooldown = 1000000
		p.hunger = 0
		p.boredom = 0
	assert_bool(false).override_failure_message("no passenger in 200").is_true()
	return null


## A cafe guest seated at CafeTestLayout's airside table.
func _cafe_guest(roller: bool) -> Passenger:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	_make(grid, PassengerTestWorld.starts_with(1500, 4000))
	var p := _passenger(roller)
	p.hunger = 0
	p.cafe_cooldown = 1000000
	var started := false
	while p.stage != Passenger.Stage.CAFE_TO_SEAT and _world.clock.tick < 1400:
		_world.step()
		if not started and p.stage == Passenger.Stage.TO_GATE:
			started = _world.sim.cafes.try_visit(p)
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_TO_SEAT)
	return p


## A bored airside visitor with a roller at the start of its stay at the piece
## of a ready `type` room (ActivityTestLayout).
func _activity_guest(type: StringName) -> Passenger:
	var grid := BuildGrid.new()
	ActivityTestLayout.build(grid, type)
	_make(grid, FlightSim.schedule_starts(0))
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_world.run_to(10)
	var p := _passenger(true)
	ShopTestLayout.to_airside(_world, p, 80)
	p.carry_on = 1
	p.mood = 50
	while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < 1500:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)
	return p


## One row per tick while `p` is in `stage`: [clip, drawn step mm, base speed],
## and with `hand_back` one more for the tick it has left `stage` (the stage
## the sim hands it back to), whose drawn step is the last of the step off.
func _rows(p: Passenger, stage: Passenger.Stage, hand_back := false) -> Array:
	var rows: Array = []
	while p.stage == stage and _world.clock.tick < 4000:
		_world.step()
		if p.stage != stage and not hand_back:
			break
		var node := _views.node_for(p.id)
		var step := _views.tick_position(p.id, true) - _views.tick_position(p.id, false)
		var mm := roundi(step.length() * 1000.0)
		rows.append([node.get_meta(&"clip"), mm, node.get_meta(&"base_speed")])
	return rows


## The walk clip's speed for a drawn step of `mm` a tick on `p`'s body.
func _walk_base(p: Passenger, mm: int) -> float:
	var body: int = _views.node_for(p.id).get_meta(&"body")
	return mm * SimClock.TICK_RATE / 1000.0 / PassengerLooks.CLIP_WALK_MPS[body]


## Every row from `from` on whose body moved plays walk at its step's speed,
## and there are some.
func _assert_walks(p: Passenger, rows: Array, from: int) -> void:
	var moved := 0
	for row: Array in rows.slice(from):
		if row[1] > 0:
			moved += 1
			assert_str(row[0]).is_equal("walk")
			assert_float(row[2]).is_equal_approx(_walk_base(p, row[1]), 0.001)
	assert_int(moved).is_greater(3)


func test_a_cafe_roller_guest_walks_out_after_its_pick_up() -> void:
	var p := _cafe_guest(true)
	while p.stage != Passenger.Stage.CAFE_STANDING_UP and _world.clock.tick < 3000:
		_world.step()
	var held := PassengerSim.STAND_UP_TICKS + ParkRecovery.UP_HOLD_TICKS
	# The tick it went into CAFE_STANDING_UP was row -1; _rows starts a tick on.
	var rows := _rows(p, Passenger.Stage.CAFE_STANDING_UP, true)
	print("cafe roller stand-up rows %s, then stage %d" % [rows, p.stage])
	# Its last row is the hand-back tick: out of the stand-up, the shuffle's
	# last step drawn.
	assert_int(rows.size()).is_equal(CafeSim.up_ticks(p))
	assert_int(p.stage).is_not_equal(Passenger.Stage.CAFE_STANDING_UP)
	# Rising and holding still at the seat: the stand_up clip, the body still.
	for row: Array in rows.slice(0, held - 1):
		assert_str(row[0]).is_equal("stand_up")
		assert_int(row[1]).is_equal(0)
	_assert_walks(p, rows, held - 1)
	var last: Array = rows[rows.size() - 1]
	assert_int(last[1]).is_greater(0)
	assert_str(last[0]).is_equal("walk")


func _assert_activity_walks_off(type: StringName) -> void:
	var p := _activity_guest(type)
	var tail := ActivityPoses.up_tail(_world.sim, p)
	assert_int(tail).is_equal(ActivityPoses.SEAT_HOLD_TICKS + ActivityPoses.SHUFFLE_TICKS)
	# With the hand-back tick: the walk on from its slot cell, still walk.
	var rows := _rows(p, Passenger.Stage.SHOP_BROWSE, true)
	var end := rows.size() - 1
	print("%s last rows %s, then stage %d" % [type, rows.slice(end - tail - 2), p.stage])
	# The hold at the seat: standing still, idle.
	for row: Array in rows.slice(end - tail + 1, end - ActivityPoses.SHUFFLE_TICKS):
		assert_str(row[0]).is_equal("idle")
		assert_int(row[1]).is_equal(0)
	_assert_walks(p, rows, end - ActivityPoses.SHUFFLE_TICKS)
	assert_str(rows[end - 1][0]).is_equal("walk")


func test_a_sofa_roller_visitor_walks_off_its_seat() -> void:
	_assert_activity_walks_off(&"lounge")


func test_a_nap_pod_roller_visitor_walks_off_its_seat() -> void:
	_assert_activity_walks_off(&"nap_pod")


## Control: with no roller the guest steps out while it rises, under the
## stand_up clip, as before; its body does move.
func test_a_cafe_guest_without_a_roller_steps_out_under_stand_up() -> void:
	var p := _cafe_guest(false)
	while p.stage != Passenger.Stage.CAFE_STANDING_UP and _world.clock.tick < 3000:
		_world.step()
	var rows := _rows(p, Passenger.Stage.CAFE_STANDING_UP)
	var moved := 0
	for row: Array in rows:
		assert_str(row[0]).is_equal("stand_up")
		moved += 1 if row[1] > 0 else 0
	print("cafe stand-up rows %s" % [rows])
	assert_int(moved).is_greater(3)


## Control: a sit-down shuffle onto a cafe seat plays sit_down (or idle while a
## roller is set down standing), never walk, though its body moves.
func test_a_cafe_sit_down_shuffle_keeps_its_clip() -> void:
	for roller: bool in [false, true]:
		var p := _cafe_guest(roller)
		while p.stage == Passenger.Stage.CAFE_TO_SEAT and _world.clock.tick < 3000:
			_world.step()
		var rows := _rows(p, Passenger.Stage.CAFE_SITTING_DOWN)
		var moved := 0
		for row: Array in rows:
			assert_bool(row[0] == "sit_down" or row[0] == "idle").is_true()
			moved += 1 if row[1] > 0 else 0
		print("cafe sit-down rows (roller %s) %s" % [roller, rows])
		assert_int(moved).is_greater(3)
		after_test()


## Control: a sofa visitor's sit-down shuffle keeps sit_down (or idle while
## the roller is set down), though its body moves onto the seat.
func test_a_sofa_sit_down_shuffle_keeps_its_clip() -> void:
	var p := _activity_guest(&"lounge")
	var rows: Array = []
	var seat := ActivityPoses.seat_door(_world.sim, p) + PassengerSim.SIT_DOWN_TICKS
	# The stay's first tick has run (_activity_guest): to its last sit_down tick.
	for i in seat - 1:
		_world.step()
		var node := _views.node_for(p.id)
		var step := _views.tick_position(p.id, true) - _views.tick_position(p.id, false)
		rows.append([node.get_meta(&"clip"), roundi(step.length() * 1000.0)])
	var moved := 0
	for row: Array in rows.slice(ActivityPoses.seat_door(_world.sim, p) - 1):
		assert_bool(row[0] == "sit_down" or row[0] == "idle").is_true()
		moved += 1 if row[1] > 0 else 0
	print("sofa sit-down rows %s" % [rows])
	assert_int(moved).is_greater(3)
