class_name TestFacilitySlots
extends GdUnitTestSuite
## FacilitySlots, the core ToiletSim and ShopSim share (decision
## boredom-and-shops-design-boredom-need-while-waiting-kiosk-sh, point 5): a
## slot is held by the visit that reserved it and freed only by that visit;
## visits are walked in passenger id order; a load rebuilds the holders; an
## edit makes the layout and the deadlines stale; reconcile() forecasts only
## the visits it keeps; nearest() takes the free slot nearest by path; and
## piece_inside() is the rule RoomRules counts pieces by.


## A visit as FacilitySlots sees one.
class FakeVisit:
	extends RefCounted
	var passenger := 0
	var deadline := 0
	var key: Variant

	func _init(id: int, slot: Variant, until := 0) -> void:
		passenger = id
		key = slot
		deadline = until

	func slot_key() -> Variant:
		return key


## A layout that counts its rebuilds.
class FakeLayout:
	extends RefCounted
	var rebuilds := 0

	func rebuild(_grid: BuildGrid) -> void:
		rebuilds += 1


var _world: PassengerTestWorld
var _ids: Dictionary
var _layout: FakeLayout
var _core: FacilitySlots


func before() -> void:
	PassengerTestWorld.tracker = self
	var grid := BuildGrid.new()
	_ids = ToiletTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)


func after() -> void:
	_world.free_all()
	_world = null
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_layout = FakeLayout.new()
	_core = FacilitySlots.new()
	_core.bind(_world.sim, _layout)


func test_a_slot_is_freed_only_by_the_visit_that_holds_it() -> void:
	var first := FakeVisit.new(4, "7:0")
	var second := FakeVisit.new(9, "7:0")
	_core.reserve(first)
	assert_int(_core.holder("7:0")).is_equal(4)
	assert_bool(_core.is_free("7:0")).is_false()
	_core.reserve(second)
	_core.release(first)
	assert_object(_core.visit_of(4)).is_null()
	assert_int(_core.holder("7:0")).is_equal(9)
	_core.release(second)
	assert_bool(_core.is_free("7:0")).is_true()
	assert_int(_core.holder("7:0")).is_equal(0)


func test_visits_are_listed_in_passenger_id_order() -> void:
	for id in [5, 2, 9]:
		_core.reserve(FakeVisit.new(id, id * 10))
	assert_array(_core.ids()).is_equal([2, 5, 9])
	assert_int(_core.holder(50)).is_equal(5)


func test_a_load_rebuilds_the_layout_and_the_holders_from_the_visits() -> void:
	_core.refresh()
	var built := _layout.rebuilds
	_core.restore({3: FakeVisit.new(3, 31), 1: FakeVisit.new(1, 11)}, true)
	assert_bool(_core.deadlines_stale).is_true()
	assert_bool(_core.is_free(31)).is_true()
	_core.rederive()
	assert_int(_layout.rebuilds).is_equal(built + 1)
	assert_int(_core.holder(11)).is_equal(1)
	assert_int(_core.holder(31)).is_equal(3)
	assert_array(_core.ids()).is_equal([1, 3])


func test_an_edit_makes_the_layout_and_every_deadline_stale() -> void:
	_core.refresh()
	_core.refresh()
	assert_int(_layout.rebuilds).is_equal(1)
	assert_bool(_core.deadlines_stale).is_false()
	var result := _world.grid.apply(
		BuildEdit.paint_floor(Vector2i(28, 16), BuildGrid.FLOOR_TILE, 1)
	)
	assert_bool(result.ok).is_true()
	assert_bool(_core.deadlines_stale).is_true()
	_core.refresh()
	assert_int(_layout.rebuilds).is_equal(2)


func test_reconcile_walks_in_id_order_and_forecasts_only_the_visits_it_keeps() -> void:
	for id in [8, 3, 6]:
		_core.reserve(FakeVisit.new(id, id, 100))
	_core.deadlines_stale = true
	var seen: Array[int] = []
	var keep := func(_p: Passenger, visit: FakeVisit) -> bool:
		seen.append(visit.passenger)
		return visit.passenger != 6
	var forecast := func(_p: Passenger, _visit: FakeVisit) -> int: return 777
	_core.reconcile(keep, forecast)
	assert_array(seen).is_equal([3, 6, 8])
	assert_int(_core.visit_of(3).deadline).is_equal(777)
	assert_int(_core.visit_of(6).deadline).is_equal(100)
	assert_int(_core.visit_of(8).deadline).is_equal(777)
	assert_bool(_core.deadlines_stale).is_false()
	_core.visit_of(3).deadline = 100
	_core.reconcile(keep, forecast)
	assert_int(_core.visit_of(3).deadline).is_equal(100)


func test_nearest_takes_the_free_slot_nearest_by_path_within_reach() -> void:
	var stalls := _world.sim.toilets
	stalls.refresh()
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.at = Vector2i(20, 14)
	p.clear_path()
	var slots: Array = []
	for stall in stalls.layout.stalls:
		if stall["room"] == _ids["land_room"]:
			slots.append({"key": stall["id"], "order": [stall["id"]], "entry": stall})
	assert_int(slots.size()).is_equal(2)
	var near := _core.nearest(p, slots)
	assert_bool(near.is_empty()).is_false()
	var first: Dictionary = near["entry"]
	var mm := int(near["route"]["mm"])
	assert_int(mm).is_greater(0)
	_core.reserve(FakeVisit.new(p.id, first["id"]))
	var next := _core.nearest(p, slots, 0, true)
	assert_int(next["entry"]["id"]).is_not_equal(first["id"])
	assert_int(int(next["route"]["mm"])).is_greater_equal(mm)
	_core.release(_core.visit_of(p.id))
	assert_bool(_core.nearest(p, slots, mm - 1).is_empty()).is_true()
	assert_int(_core.nearest(p, slots, mm)["entry"]["id"]).is_equal(first["id"])


func test_nearest_skips_a_slot_admit_refuses_for_the_next_one_it_admits() -> void:
	var stalls := _world.sim.toilets
	stalls.refresh()
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.at = Vector2i(20, 14)
	p.clear_path()
	var slots: Array = []
	for stall in stalls.layout.stalls:
		if stall["room"] == _ids["land_room"]:
			slots.append({"key": stall["id"], "order": [stall["id"]], "entry": stall})
	var first: Dictionary = _core.nearest(p, slots)["entry"]
	var asked: Array = []
	var admit := func(entry: Dictionary, route: Dictionary) -> bool:
		asked.append([entry["id"], int(route["mm"])])
		return entry["id"] != first["id"]
	var next := _core.nearest(p, slots, 0, false, admit)
	print("admit asked %s" % [asked])
	assert_bool(next.is_empty()).is_false()
	assert_int(next["entry"]["id"]).is_not_equal(first["id"])
	# Both stalls were asked, the nearer refused one among them.
	assert_int(asked.size()).is_equal(2)
	assert_array([asked[0][0], asked[1][0]]).contains([first["id"]])
	# Nothing admitted: no slot.
	var refuse := func(_entry: Dictionary, _route: Dictionary) -> bool: return false
	assert_bool(_core.nearest(p, slots, 0, false, refuse).is_empty()).is_true()


func test_a_piece_is_inside_only_with_its_interaction_cell() -> void:
	var stall: int = _ids["land_stalls"][0]
	var record := _world.grid.get_object(stall)
	var def := BuildCatalog.get_def(record["def"])
	var cells: Array = def.footprint(record["anchor"], record["facing"])
	var spot := _world.grid.interaction_cell(stall)
	var footprint := _bounds(cells)
	var with_spot := _bounds(cells + [spot])
	assert_bool(footprint.has_point(spot)).is_false()
	assert_bool(FacilitySlots.piece_inside(_world.grid, stall, footprint)).is_false()
	assert_bool(FacilitySlots.piece_inside(_world.grid, stall, with_spot)).is_true()
	var land := ToiletTestLayout.LANDSIDE_ROOM
	assert_bool(FacilitySlots.piece_inside(_world.grid, stall, land)).is_true()
	var air := ToiletTestLayout.AIRSIDE_ROOM
	assert_bool(FacilitySlots.piece_inside(_world.grid, stall, air)).is_false()


## The smallest rectangle holding every cell.
func _bounds(cells: Array) -> Rect2i:
	var low: Vector2i = cells[0]
	var high: Vector2i = cells[0]
	for cell: Vector2i in cells:
		low = low.min(cell)
		high = high.max(cell)
	return Rect2i(low, high - low + Vector2i.ONE)
