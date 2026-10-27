class_name TestCafeSnapshotChecks
extends GdUnitTestSuite
## A cafe save the game could not have reached is refused (article cafe-visits,
## acceptance cafe-save). An order in progress ends after the saved tick and
## started ORDER_TICKS before that end; a seated guest's dwell does the same
## with DWELL_TICKS. A save taken between an edit and the next tick brings the
## cafe in line with the grid first, so a save never holds stale cafe state
## and every seat, counter and room it names is in the cafe layout rebuilt
## from the saved grid: a removed piece, of any kind or room, is refused.

const HUNGRY := 59

var _world: PassengerTestWorld
## The ids CafeTestLayout.build() gave the pieces.
var _ids: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
	_world = null


## A cafe world (a flight boarding at 1500, so several guests overlap) run
## until one guest is seated, one orders and one queues; its
## save as through JSON.
func _busy_save() -> Dictionary:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid, true)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(1500, 4000), 4242)
	for i in 12:
		_world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT)).hunger = HUNGRY
	var wanted := [
		Passenger.Stage.CAFE_SEATED, Passenger.Stage.CAFE_ORDER, Passenger.Stage.CAFE_QUEUE
	]
	var found := false
	while not found and _world.clock.tick < 1400:
		_world.step()
		var stages := {}
		for id in _world.sim.cafes.visit_ids():
			stages[_world.passenger(id).stage] = true
		found = true
		for stage in wanted:
			found = found and stages.has(stage)
	print("saved at tick %d" % _world.clock.tick)
	assert_bool(found).is_true()
	return JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))


## The index in a save's cafe visits of the first guest in `stage`.
func _visit_index(save: Dictionary, stage: Passenger.Stage) -> int:
	var stages := {}
	for record in save["passengers"]:
		stages[int(record["id"])] = int(record["stage"])
	var visits: Array = save["cafe"]["visits"]
	for i in visits.size():
		if stages[int(visits[i]["passenger"])] == stage:
			return i
	return -1


func _record(save: Dictionary, id: int) -> Dictionary:
	for record in save["passengers"]:
		if int(record["id"]) == id:
			return record
	return {}


## Sets a visit's field. For "room" and "counter" it sets the field of its
## queue and of every visit in that queue too, so the save stays consistent
## apart from the change.
func _change(save: Dictionary, index: int, field: String, value: Variant) -> Dictionary:
	var bad: Dictionary = save.duplicate(true)
	var visits: Array = bad["cafe"]["visits"]
	var guest: int = int(visits[index]["passenger"])
	visits[index][field] = value
	if not field in ["room", "counter"]:
		return bad
	for queue in bad["cafe"]["queues"]:
		var lane: Array = queue["lane"]
		if not lane.has(guest):
			continue
		queue[field] = value
		for visit: Dictionary in visits:
			if lane.has(visit["passenger"]):
				visit[field] = value
	return bad


## Refuses every case, leaving the world as it was, then loads `good`; the
## loading world has the saved world's grid.
func _assert_refused(cases: Array, good: Dictionary) -> void:
	var fresh := BuildGrid.new()
	assert_bool(fresh.from_snapshot(_world.grid.to_snapshot())).is_true()
	var other := PassengerTestWorld.make(fresh, PassengerTestWorld.starts_with(1500, 4000), 4242)
	var before_ids := other.sim.passenger_ids()
	for case in cases:
		assert_bool(other.sim.from_snapshot(case[1])).override_failure_message(case[0]).is_false()
		assert_array(other.sim.passenger_ids()).is_equal(before_ids)
	assert_bool(other.sim.from_snapshot(good)).override_failure_message("the good save").is_true()
	other.free_all()


func test_an_order_or_a_dwell_must_end_after_the_saved_tick() -> void:
	var good := _busy_save()
	var tick := str(good["tick"]).to_int()
	var ordering := _visit_index(good, Passenger.Stage.CAFE_ORDER)
	var seated := _visit_index(good, Passenger.Stage.CAFE_SEATED)
	assert_int(ordering).is_greater_equal(0)
	assert_int(seated).is_greater_equal(0)
	var order_end := int(good["cafe"]["visits"][ordering]["service_end"])
	var dwell_end := int(good["cafe"]["visits"][seated]["dwell_end"])
	print("tick %d: order ends %d, dwell ends %d" % [tick, order_end, dwell_end])
	assert_int(order_end).is_greater(tick)
	assert_int(dwell_end).is_greater(tick)
	var cases := [
		["order ended at the saved tick", _change(good, ordering, "service_end", tick)],
		["order ended before the saved tick", _change(good, ordering, "service_end", tick - 5)],
		["order longer than ORDER_TICKS", _change(good, ordering, "service_end", order_end + 1)],
		["dwell ended at the saved tick", _change(good, seated, "dwell_end", tick)],
		["dwell longer than DWELL_TICKS", _change(good, seated, "dwell_end", dwell_end + 1)],
	]
	# An order or a dwell that starts after the saved tick is never reached.
	var future := good.duplicate(true)
	var orderer := int(future["cafe"]["visits"][ordering]["passenger"])
	_record(future, orderer)["stage_tick"] = tick + 1
	future["cafe"]["visits"][ordering]["service_end"] = tick + 1 + CafeSim.ORDER_TICKS
	cases.append(["order started after the saved tick", future])
	_assert_refused(cases, good)


func test_a_save_names_only_pieces_in_the_saved_cafe_layout() -> void:
	_busy_save()
	var queuing_id := 0
	for id in _world.sim.cafes.visit_ids():
		if _world.passenger(id).stage == Passenger.Stage.CAFE_QUEUE:
			queuing_id = id
			break
	assert_int(queuing_id).is_greater(0)
	# The other cafe loses its counter and a table while the game is paused.
	var airside := _world.sim.cafes.visit_of(queuing_id).room == int(_ids["air_room"])
	var other_counter: int = _ids["land_counter"] if airside else _ids["air_counter"]
	var other_table: int = _ids["land_table_2"] if airside else _ids["air_table_2"]
	for removed in [other_counter, other_table]:
		assert_bool(_world.grid.apply(BuildEdit.remove_object(removed)).ok).is_true()
	assert_bool(_world.sim.cafes.deadlines_stale).is_true()
	# The save brings the cafe in line with the grid first.
	var good: Dictionary = JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))
	assert_bool(_world.sim.cafes.deadlines_stale).is_false()
	assert_bool(good["cafe"]["deadlines_stale"]).is_false()
	var queuing := _visit_index(good, Passenger.Stage.CAFE_QUEUE)
	assert_int(queuing).is_greater_equal(0)
	var visit: Dictionary = good["cafe"]["visits"][queuing]
	var table := int(String(visit["seat_key"]).split(":")[0])
	var counter := int(visit["counter"])
	var never := int(_world.grid.to_snapshot()["next_object_id"])
	var never_room := int(_world.grid.to_snapshot()["next_room_id"])
	assert_int(table).is_greater(0)
	assert_int(counter).is_greater(0)
	var cases := [
		["a table that never existed", _change(good, queuing, "seat_key", "%d:0" % never)],
		["a counter used as a table", _change(good, queuing, "seat_key", "%d:0" % counter)],
		["a seat the table does not have", _change(good, queuing, "seat_key", "%d:7" % table)],
		["a counter that never existed", _change(good, queuing, "counter", never)],
		["a table used as a counter", _change(good, queuing, "counter", table)],
		["a room that never existed", _change(good, queuing, "room", never_room)],
		# Removed pieces: the wrong kind, and the right kind in the other room.
		[
			"a removed counter used as a table",
			_change(good, queuing, "seat_key", "%d:0" % other_counter)
		],
		["a removed table used as a counter", _change(good, queuing, "counter", other_table)],
		[
			"a removed table from the other cafe",
			_change(good, queuing, "seat_key", "%d:0" % other_table)
		],
		["the other cafe's removed counter", _change(good, queuing, "counter", other_counter)],
	]
	var stale := good.duplicate(true)
	stale["cafe"]["deadlines_stale"] = true
	cases.append(["a save that holds stale cafe state", stale])
	_assert_refused(cases, good)
