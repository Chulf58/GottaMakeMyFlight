class_name TestBoothRollerTurnBack
extends GdUnitTestSuite
## A booth guest with a roller whose booth moves early in its step-in hold
## (CafeSim._relocates()) stays at the approach cell until its roller is down
## and lifted back into the pull before it sets off, even for the longest
## set-down, one that turns first (RollerPark.mark_turn_first(), forced here on
## the drawn record): turned back at once 6 ticks in, it set off before the
## lift was over (Sol review of 11c61e7, board 2eaa9bc4). Drawn by real
## PassengerViews, a tick a frame.

## Ticks into the sit-down the booth is moved.
const MOVED_AT := 6

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


## A guest pulling a roller to the restaurant's booth, drawn from its visit's
## start, stepped to the first tick of its sit-down.
func _sitting() -> Passenger:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid, false, &"restaurant", true, &"cafe_counter", &"restaurant_booth")
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var p: Passenger = null
	for attempt in 200:
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.cafe_cooldown = 1000000
		p.hunger = 30
		p.carry_on = 1
		if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER:
			break
		p.carry_on = 0
		ToiletTestLayout.calm(p)
	p.liquids = false
	p.alarm = false
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 1500:
		_world.step()
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	assert_bool(_world.sim.cafes.try_visit(p)).override_failure_message("visit refused").is_true()
	while p.stage != Passenger.Stage.CAFE_SITTING_DOWN and _world.clock.tick < 3000:
		_world.step()
		_views.draw()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SITTING_DOWN)
	return p


## Moves the guest's booth to the first of three neighbouring cells the grid
## accepts, as a room move does (removed and placed again under its id).
func _move_booth(p: Passenger) -> void:
	var id := int(_world.sim.cafes.visit_of(p.id).seat["object_id"])
	var record := _world.grid.get_object(id)
	for shift: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0)]:
		var place := BuildEdit.place_object(
			record["def"], record["anchor"] + shift, record["facing"]
		)
		place.object_id = id
		place.paid = int(record.get("paid", 0))
		if _world.grid.apply_batch([BuildEdit.remove_object(id), place])[1].ok:
			return
		var back := BuildEdit.place_object(record["def"], record["anchor"], record["facing"])
		back.object_id = id
		back.paid = place.paid
		_world.grid.apply_batch([back])
	fail("the booth could not be moved")


## Moved MOVED_AT ticks into a set-down that turns first, the guest is at the
## approach cell until it sets off, and then its roller's pick-up is past its
## lift (RollerPark.LIFT_END) with the roller in the hand; no tick moves the
## drawn roller further than the same booth move does to a plain set-down
## (moving the booth moves where the roller lies: 1.5 m in a tick, on main as
## well). Control: the guest turned back and set off both times.
func test_a_booth_moved_early_in_a_turn_first_set_down_waits_for_the_lift() -> void:
	var plain := _run(false)
	after_test()
	var turned := _run(true)
	print("booth turn-back: plain %s, turn first %s" % [plain, turned])
	for run: Dictionary in [plain, turned]:
		assert_bool(run["turned_back"]).is_true()
		assert_bool(run["set_off"]).is_true()
		assert_int(int(run["place"]) / 4).is_equal(SecurityLooks.Home.HAND)
		assert_float(run["lifted"]).is_greater_equal(RollerPark.LIFT_END)
		assert_float(run["off_approach"]).is_less(0.01)
	assert_float(turned["most"]).is_less_equal(plain["most"] + 0.01)


## One guest moved MOVED_AT ticks into its set-down, made to turn first with
## `turn_first`, played until it sets off: {"turned_back", "set_off", "place",
## "lifted" (the pick-up's k in TICKS_UP units when it set off), "off_approach",
## "most" (the drawn roller's largest move in a tick from the move on)}.
func _run(turn_first: bool) -> Dictionary:
	var p := _sitting()
	var props := _views.carry_on_props()
	_world.step()
	_views.draw()
	var bag: Dictionary = props._held[p.id]["bags"][0]
	assert_bool(bag.get("park", false)).override_failure_message("no set-down").is_true()
	if turn_first:
		bag["turn_first"] = true
		bag["ticks"] = RollerPark.TICKS_DOWN + RollerPark.TURN_FIRST_TICKS
	var sat_from := p.stage_tick
	while _world.clock.tick < sat_from + MOVED_AT:
		_world.step()
		_views.draw()
	_move_booth(p)
	var approach := _world.grid.cell_to_world(_world.sim.cafes.visit_of(p.id).seat["approach"])
	var node: Node3D = props._held[p.id]["bags"][0]["node"]
	var last := node.global_position
	var most := 0.0
	var off_approach := 0.0
	var turned_back := false
	var stop := _world.clock.tick + 200
	while _world.clock.tick < stop:
		_world.step()
		_views.draw()
		node = props._held[p.id]["bags"][0]["node"]
		most = maxf(most, node.global_position.distance_to(last))
		last = node.global_position
		turned_back = turned_back or p.stage == Passenger.Stage.CAFE_STANDING_UP
		if turned_back and p.stage != Passenger.Stage.CAFE_STANDING_UP:
			break
		var at := _world.sim.cafes.seat_position(p)
		off_approach = maxf(off_approach, Vector2(at.x - approach.x, at.z - approach.z).length())
	var now: Dictionary = props.bag_state(p.id, 0)
	var k := props.transfer_progress(p.id, 0)
	var place := int(now.get("place", -1))
	var lifted := RollerPark.up_k(now, k) if now.get("park", false) else 1.0
	return {
		"turned_back": turned_back,
		"set_off": p.stage != Passenger.Stage.CAFE_STANDING_UP,
		"at": _world.clock.tick - sat_from,
		"place": place,
		"lifted": snappedf(lifted, 0.001),
		"off_approach": snappedf(off_approach, 0.001),
		"most": snappedf(most, 0.001),
	}
