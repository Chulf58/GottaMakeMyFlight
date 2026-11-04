class_name TestRollerStandUpHold
extends GdUnitTestSuite
## A passenger with a roller standing up from a cafe seat, the lounge sofa or
## the nap pod stands up fully, then picks the roller up standing still, then
## walks off (decision standing-up-with-a-roller-stand-up-then-pick-up-then-
## walk, board 2c659e42), as at a gate chair (test_park_recovery.gd). The cafe
## stand-up lasts CafeSim.up_ticks() and its forecast counts it; an activity
## visitor's hold comes out of its stay, and a save taken in a moved piece's
## longer exit loads. Cafe cases use CafeTestLayout's airside table; activity
## cases ActivityTestLayout's piece (x 22, y 3, moved to x 25).

const MOVED_TO := Vector2i(25, 3)

var _world: PassengerTestWorld
var _ids: Dictionary
var _starts: Array[int] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


## A spawned passenger whose first bag is a roller, carrying only that bag.
## Spawns until the kind matches (a bag's kind is a hash of the id); the others
## are kept from every visit.
func _roller_passenger() -> Passenger:
	for attempt in 200:
		var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER:
			p.carry_on = 1
			return p
		p.cafe_cooldown = 1000000
		p.shop_cooldown = 1000000
		p.hunger = 0
		p.boredom = 0
	assert_bool(false).override_failure_message("no roller passenger in 200").is_true()
	return null


## A cafe guest with a roller, seated at the airside table.
func _cafe_guest() -> Passenger:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid)
	_starts = PassengerTestWorld.starts_with(1500, 4000)
	_world = PassengerTestWorld.make(grid, _starts)
	var p := _roller_passenger()
	p.hunger = 0
	p.cafe_cooldown = 1000000
	var started := false
	while p.stage != Passenger.Stage.CAFE_SEATED and _world.clock.tick < 1400:
		_world.step()
		if not started and p.stage == Passenger.Stage.TO_GATE:
			started = _world.sim.cafes.try_visit(p)
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SEATED)
	return p


## A bored airside visitor with a roller, staying at the piece of a ready
## `type` room.
func _activity_guest(type: StringName) -> Passenger:
	var grid := BuildGrid.new()
	_ids = ActivityTestLayout.build(grid, type)
	_starts = FlightSim.schedule_starts(0)
	_world = PassengerTestWorld.make(grid, _starts)
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_world.run_to(10)
	var p := _roller_passenger()
	ShopTestLayout.to_airside(_world, p, 80)
	p.carry_on = 1
	p.mood = 50
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < 1500:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)
	return p


func test_a_cafe_guest_with_a_roller_stands_up_then_picks_it_up_then_shuffles_out() -> void:
	var p := _cafe_guest()
	var cafes := _world.sim.cafes
	while p.stage == Passenger.Stage.CAFE_SEATED:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_STANDING_UP)
	var up := p.stage_tick
	var positions: Array[Vector3] = []
	var homes: Array[SecurityLooks.Home] = []
	while p.stage == Passenger.Stage.CAFE_STANDING_UP and _world.clock.tick < up + 200:
		positions.append(cafes.seat_position(p))
		homes.append(SecurityLooks.bag_homes(_world.sim, p)[0])
		_world.step()
	var held := PassengerSim.STAND_UP_TICKS + ParkRecovery.UP_HOLD_TICKS
	print("cafe stand-up %d ticks, held %d, homes %s" % [positions.size(), held, homes])
	assert_int(positions.size()).is_equal(CafeSim.up_ticks(p))
	assert_int(CafeSim.up_ticks(p)).is_equal(held + CafeSim.SHUFFLE_TICKS)
	# On the floor while it rises, in the hand from the tick it is up.
	assert_int(homes.find(SecurityLooks.Home.HAND)).is_equal(PassengerSim.STAND_UP_TICKS)
	assert_int(homes.count(SecurityLooks.Home.FLOOR)).is_equal(PassengerSim.STAND_UP_TICKS)
	# Where it sat (the roller lies in the body's frame) until the pick-up is
	# over, then out to the approach cell.
	for n in held:
		assert_vector(positions[n]).is_equal(positions[0])
	var out := positions[positions.size() - 1].distance_to(positions[0])
	print("cafe shuffle out %.3f m" % out)
	assert_float(out).is_greater(0.3)


func test_the_cafe_forecast_counts_the_roller_hold() -> void:
	var p := _cafe_guest()
	var visit := _world.sim.cafes.visit_of(p.id)
	var cell: Vector2i = visit.seat["approach"]
	var resume := visit.resume_stage
	var with_roller := CafeForecast.leave_ticks(_world.sim, p, cell, resume)
	var deadline := CafeForecast.deadline(_world.sim, p, cell, resume)
	p.carry_on = 0
	assert_int(CafeSim.up_ticks(p)).is_equal(PassengerSim.STAND_UP_TICKS)
	var without := CafeForecast.leave_ticks(_world.sim, p, cell, resume)
	var plain_deadline := CafeForecast.deadline(_world.sim, p, cell, resume)
	p.carry_on = 1
	print("leave %d with a roller, %d without" % [with_roller, without])
	var extra := ParkRecovery.UP_HOLD_TICKS + CafeSim.SHUFFLE_TICKS
	assert_int(with_roller - without).is_equal(extra)
	assert_int(plain_deadline - deadline).is_equal(extra)


## Per tick of an activity visitor's stay to its end: [pose, bags down, share].
func _stay_rows(p: Passenger) -> Array:
	var rows: Array = []
	while p.stage == Passenger.Stage.SHOP_BROWSE and _world.clock.tick < 3000:
		(
			rows
			. append(
				[
					ActivityPoses.pose(_world.sim, p),
					ActivityPoses.bags_down(_world.sim, p),
					ActivityPoses.share(_world.sim, p),
				]
			)
		)
		_world.step()
	return rows


func _assert_held_stand_up(type: StringName) -> void:
	var p := _activity_guest(type)
	var hold := ActivityPoses.SEAT_HOLD_TICKS
	var tail := hold + ActivityPoses.SHUFFLE_TICKS
	assert_int(ActivityPoses.up_tail(_world.sim, p)).is_equal(tail)
	var rows := _stay_rows(p)
	var stand := PassengerSim.STAND_UP_TICKS
	var end := rows.size()
	print("%s stay %d ticks, last rows %s" % [type, end, rows.slice(end - tail - stand)])
	# The stand-up, at the seat: the bags still down all through.
	for row: Array in rows.slice(end - tail - stand, end - tail):
		assert_int(row[0]).is_equal(StageKinds.Pose.STANDING_UP)
		assert_bool(row[1]).is_true()
		assert_float(row[2]).is_equal(1.0)
	# Then the hold, still at the seat, and the step off: standing, bags in hand.
	for row: Array in rows.slice(end - tail):
		assert_int(row[0]).is_equal(StageKinds.Pose.UPRIGHT)
		assert_bool(row[1]).is_false()
	for row: Array in rows.slice(end - tail, end - tail + hold):
		assert_float(row[2]).is_equal(1.0)
	assert_float(rows[end - 1][2]).is_less(0.1)
	var seated: Array = rows[end - tail - stand - 1]
	assert_int(seated[0]).is_equal(StageKinds.Pose.SEATED)


func test_a_sofa_sitter_with_a_roller_stands_up_then_picks_it_up_at_the_seat() -> void:
	_assert_held_stand_up(&"lounge")


func test_a_nap_pod_sitter_with_a_roller_stands_up_then_picks_it_up_at_the_seat() -> void:
	_assert_held_stand_up(&"nap_pod")


## Control: with no roller the bags come up as the sitter steps off its seat,
## part way through the stand-up, and the stay has no hold.
func test_a_sofa_sitter_without_a_roller_has_no_hold() -> void:
	var p := _activity_guest(&"lounge")
	p.carry_on = 0
	assert_int(ActivityPoses.up_tail(_world.sim, p)).is_equal(0)
	assert_int(ActivityPoses.exit_ticks(&"lounge_sofa", 0)).is_equal(PassengerSim.STAND_UP_TICKS)
	var rows := _stay_rows(p)
	var end := rows.size()
	var last: Array = rows[end - 1]
	assert_int(last[0]).is_equal(StageKinds.Pose.STANDING_UP)
	assert_int(rows[end - PassengerSim.STAND_UP_TICKS][0]).is_equal(StageKinds.Pose.STANDING_UP)


## A sofa whose room moves while its roller visitor sits: the exit at the old
## spot is the stand-up and the hold (ActivityPoses.exit_ticks()), and a save
## taken in it, longer than a plain stand-up, loads (ShopSnapshot).
func test_a_save_in_a_roller_sitters_exit_from_a_moved_sofa_loads() -> void:
	var p := _activity_guest(&"lounge")
	for i in 80:
		_world.step()
	var exit := ActivityPoses.exit_ticks(&"lounge_sofa", 1, true)
	assert_int(exit).is_equal(
		PassengerSim.STAND_UP_TICKS + ParkRecovery.UP_HOLD_TICKS + ActivityPoses.SHUFFLE_TICKS
	)
	ShopMoveKit.move_piece(_world, _ids["use"], MOVED_TO)
	_world.step()
	var moved_at := _world.clock.tick
	var visit := _world.sim.shops.visit_of(p.id)
	assert_bool(visit.relocation != null and visit.relocation.exiting).is_true()
	var type := RoomTypes.get_type(_world.grid.get_room(visit.room)["type"])
	var ends := p.stage_tick + ShopSim.browse_ticks(type) - _world.clock.tick
	print("exit ticks %d, %d to run at the save" % [exit, ends])
	assert_int(ends).is_greater(PassengerSim.STAND_UP_TICKS)
	assert_bool(_loads(_save())).is_true()
	while p.stage == Passenger.Stage.SHOP_BROWSE and _world.clock.tick < moved_at + 200:
		_world.step()
	assert_int(_world.clock.tick - moved_at).is_equal(exit)


func _save() -> Dictionary:
	var text := (
		JSON
		. stringify(
			{
				"clock": _world.clock.to_snapshot(),
				"flights": _world.flights.to_snapshot(),
				"grid": _world.grid.to_snapshot(),
				"passengers": _world.sim.to_snapshot(),
			}
		)
	)
	return JSON.parse_string(text)


## Whether `data` loads into a fresh world, which is freed again.
func _loads(data: Dictionary) -> bool:
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var twin := PassengerTestWorld.make(grid, _starts, 99)
	assert_bool(twin.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(twin.flights.from_snapshot(data["flights"])).is_true()
	var loaded := twin.sim.from_snapshot(data["passengers"])
	twin.free_all()
	return loaded
