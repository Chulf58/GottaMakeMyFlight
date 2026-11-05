class_name TestShopSnapshotTurnBack
extends GdUnitTestSuite
## The load check on how many ticks a moved piece's exit may still have to run
## (ShopSnapshot._relocation_problem(), board 9f0ff737): a roller visitor
## turned back before it had stepped all the way onto its sofa has an exit only
## as long as ActivityPoses.turn_back_ticks() makes it for the step it had made
## (Relocation.reached), not the full ActivityPoses.exit_ticks(). ActivityTest
## Layout's lounge piece stands at x 22, y 3 and is moved to x 25.

const MOVED_TO := Vector2i(25, 3)
const SEAT_DOOR := ActivityPoses.SEAT_DOOR_TICKS

var _world: PassengerTestWorld
var _ids: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


## A roller visitor 5 ticks into its sit-down on a lounge sofa when the sofa
## moves, one tick after the move: leaving the old spot, 5 ticks stepped.
func _exiting_roller() -> Passenger:
	var grid := BuildGrid.new()
	_ids = ActivityTestLayout.build(grid, &"lounge")
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	_world.run_to(10)
	var p: Passenger = null
	for attempt in 200:
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER:
			break
		p.shop_cooldown = 1000000
	assert_int(SecurityLooks.bag_kind(p, 0)).is_equal(SecurityLooks.Kind.ROLLER)
	ShopTestLayout.to_airside(_world, p, 80)
	p.carry_on = 1
	p.mood = 50
	var until := _world.clock.tick + 1500
	while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < until:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)
	for i in SEAT_DOOR + 5:
		_world.step()
	ShopMoveKit.move_piece(_world, _ids["use"], MOVED_TO)
	_world.step()
	var visit := _world.sim.shops.visit_of(p.id)
	assert_bool(visit.relocation.exiting).is_true()
	assert_int(visit.relocation.reached).is_equal(5)
	return p


## Ticks of the stay the saved exit still has to run, as the load counts them.
func _ends(p: Passenger) -> int:
	var visit := _world.sim.shops.visit_of(p.id)
	var type := RoomTypes.get_type(_world.grid.get_room(visit.room)["type"])
	return p.stage_tick + ShopSim.browse_ticks(type) - _world.sim.tick


## Whether the save of the world, with the passenger's exit made to have `ends`
## ticks left and the relocation's step set to `reached`, loads.
func _loads_with(p: Passenger, ends: int, reached: int) -> bool:
	var data: Dictionary = JSON.parse_string(ShopMoveKit.save_text(_world))
	for record: Dictionary in data["passengers"]["passengers"]:
		if int(record["id"]) == p.id:
			record["stage_tick"] = int(record["stage_tick"]) + ends - _ends(p)
	var moving: Dictionary = data["passengers"]["shop"]["visits"][0]["relocation"]
	moving["reached"] = reached
	var twin := ShopMoveKit.load_twin(data)
	if twin != null:
		twin.free_all()
	return twin != null


func test_a_turned_back_exit_loads_with_the_ticks_the_sim_gave_it_and_no_more() -> void:
	var p := _exiting_roller()
	var legal := _ends(p)
	print("roller sofa turned back at reached 5: %d ticks to run" % legal)
	assert_bool(_loads_with(p, legal, 5)).override_failure_message("as played").is_true()
	assert_bool(_loads_with(p, legal + 1, 5)).override_failure_message("one tick more").is_false()


func test_a_roller_exit_with_no_step_made_is_refused_with_20_ticks_left() -> void:
	var p := _exiting_roller()
	assert_bool(_loads_with(p, 20, 0)).is_false()
	assert_bool(_loads_with(p, 1, 0)).override_failure_message("1 tick left").is_true()


func test_a_roller_exit_with_the_whole_step_made_may_run_the_full_exit() -> void:
	var p := _exiting_roller()
	var visit := _world.sim.shops.visit_of(p.id)
	var full := ActivityPoses.exit_ticks(visit.relocation.source["def"], p.carry_on, true)
	var steps := ActivityPoses.SHUFFLE_TICKS
	assert_bool(_loads_with(p, full, steps)).override_failure_message("the full exit").is_true()
	assert_bool(_loads_with(p, full + 1, steps)).override_failure_message("past it").is_false()
