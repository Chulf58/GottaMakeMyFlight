class_name TestNeedsPolicy
extends GdUnitTestSuite
## NeedsPolicy (decision toilet-design-queue-free-reservable-stalls-per-stall-
## daily-u, point 5): with the toilet need and hunger both high, the priority
## table decides, not the order the facility sims run their beats in. The
## toilet wins when both visits are viable; with no viable toilet visit the
## passenger falls back to the cafe; the sims' beats start no visit, so
## running them in either order gives the same choice.

## A floored world with the exit on the north edge, a cafe in the north-east
## and a toilet room with one stall south of it, everyone airside. With no
## gate seats a passenger waits standing at the gate until boarding.
const SIZE := Vector2i(30, 20)
const CAFE_ROOM := Rect2i(16, 2, 6, 6)
const TOILET_ROOM := Rect2i(16, 10, 4, 4)
const GUEST_CELL := Vector2i(12, 8)
const BOARDING := 5000
const DOORS := 6000

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(SIZE)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(2, 0), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(2, 19), 2)
	assert_bool(grid.apply(BuildEdit.place_room(CAFE_ROOM, &"cafe")).ok).is_true()
	PassengerTestWorld.place(grid, &"cafe_counter", Vector2i(17, 2), 0)
	PassengerTestWorld.place(grid, &"cafe_table", Vector2i(18, 5), 0)
	assert_bool(grid.apply(BuildEdit.place_room(TOILET_ROOM, &"toilet")).ok).is_true()
	PassengerTestWorld.place(grid, &"toilet_stall", Vector2i(17, 10), 0)
	PassengerTestWorld.place(grid, &"toilet_sink", Vector2i(19, 10), 0)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(BOARDING, DOORS))
	_world.sim.apron_waypoints = PackedVector3Array()
	_world.run_to(10)


func after_test() -> void:
	_world.free_all()
	_world = null


## A cleared passenger standing at GUEST_CELL heading for the gate, with
## hunger and toilet need both high and both cooldowns over.
func _needy() -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _world.clock.tick
	p.at = GUEST_CELL
	p.clear_path()
	p.hunger = 90
	p.cafe_cooldown = 0
	p.toilet_need = 90
	p.toilet_cooldown = 0
	return p


func _name(need: NeedsPolicy.Need) -> String:
	return NeedsPolicy.Need.keys()[need]


func test_both_high_and_both_viable_picks_the_toilet() -> void:
	assert_array(NeedsPolicy.ORDER).is_equal(
		[NeedsPolicy.Need.TOILET, NeedsPolicy.Need.HUNGER, NeedsPolicy.Need.BROWSE]
	)
	var p := _needy()
	# Both visits are viable on their own.
	assert_dict(_world.sim.toilets.plan_visit(p)).is_not_empty()
	assert_dict(_world.sim.cafes.plan_visit(p)).is_not_empty()
	var choice := NeedsPolicy.choose(_world.sim, p)
	print("both viable: %s, refused %s" % [_name(choice["need"]), choice["refused"]])
	assert_int(choice["need"]).is_equal(NeedsPolicy.Need.TOILET)
	assert_array(choice["refused"]).is_empty()
	# Choosing started nothing.
	assert_object(_world.sim.toilets.visit_of(p.id)).is_null()
	assert_object(_world.sim.cafes.visit_of(p.id)).is_null()
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.TOILET)
	assert_object(_world.sim.toilets.visit_of(p.id)).is_not_null()
	assert_object(_world.sim.cafes.visit_of(p.id)).is_null()
	# The cafe was never asked, so its cooldown did not start.
	assert_int(p.cafe_cooldown).is_equal(0)


func test_both_high_with_no_viable_toilet_visit_falls_back_to_the_cafe() -> void:
	# The only stall is held by a passenger walking to it.
	var holder := _needy()
	holder.hunger = 0
	assert_bool(_world.sim.toilets.try_visit(holder)).is_true()
	var p := _needy()
	assert_dict(_world.sim.toilets.plan_visit(p)).is_empty()
	var choice := NeedsPolicy.choose(_world.sim, p)
	print("no stall free: %s, refused %s" % [_name(choice["need"]), choice["refused"]])
	assert_int(choice["need"]).is_equal(NeedsPolicy.Need.HUNGER)
	assert_array(choice["refused"]).is_equal([NeedsPolicy.Need.TOILET])
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.HUNGER)
	assert_object(_world.sim.cafes.visit_of(p.id)).is_not_null()
	assert_object(_world.sim.toilets.visit_of(p.id)).is_null()
	# The toilet it wanted starts its retry cooldown.
	assert_int(p.toilet_cooldown).is_equal(_world.clock.tick + ToiletSim.RETRY_TICKS)


func test_the_order_the_sims_beat_in_does_not_change_the_winner() -> void:
	var first := _needy()
	var second := _needy()
	_world.sim.toilets.beat(first)
	_world.sim.cafes.beat(first)
	_world.sim.cafes.beat(second)
	_world.sim.toilets.beat(second)
	# The beats raised the needs and started no visit.
	for p in [first, second]:
		assert_int(p.hunger).is_equal(91)
		assert_int(p.toilet_need).is_equal(91)
		assert_int(StageKinds.visit_facility(_world.sim, p)).is_equal(StageKinds.Facility.NONE)
	var a := NeedsPolicy.choose(_world.sim, first)
	var b := NeedsPolicy.choose(_world.sim, second)
	print("toilet first: %s, cafe first: %s" % [_name(a["need"]), _name(b["need"])])
	assert_int(a["need"]).is_equal(NeedsPolicy.Need.TOILET)
	assert_int(b["need"]).is_equal(NeedsPolicy.Need.TOILET)


func test_with_no_need_high_nothing_is_chosen_or_refused() -> void:
	var p := _needy()
	p.hunger = 0
	p.toilet_need = 0
	var choice := NeedsPolicy.choose(_world.sim, p)
	assert_int(choice["need"]).is_equal(NeedsPolicy.Need.NONE)
	assert_array(choice["refused"]).is_empty()
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.NONE)
	assert_int(p.cafe_cooldown).is_equal(0)
	assert_int(p.toilet_cooldown).is_equal(0)
