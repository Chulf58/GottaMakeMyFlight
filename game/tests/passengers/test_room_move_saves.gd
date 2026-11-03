class_name TestRoomMoveSaves
extends GdUnitTestSuite
## Saves of visitors following a moved piece (decision move-rooms-technical-
## design-roommove-plan-of-existing-edits, part 6): a relocation save loads
## only when the piece it returns to is still in the visit's room and what it
## owes is in range, and a piece removed while its visitor gets up leaves a
## final exit that is drawn, paid nothing and saved. Cafe cases use
## CafeTestLayout's airside table (24,6, moved to 24,5); toilet cases use
## ToiletTestLayout's one landside stall (23,10, moved to 25,10).

var _world: PassengerTestWorld
var _ids: Dictionary
## The flight starts the world was made with, for the twin a load makes.
var _starts: Array[int] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func _at() -> Vector2i:
	return ReferenceTerminal.offset_on(_world.grid)


## Moves object `id` to `anchor` (terminal cells) as a room move does.
func _move(id: int, anchor: Vector2i) -> void:
	var record := _world.grid.get_object(id)
	var place := BuildEdit.place_object(record["def"], anchor + _at(), record["facing"])
	place.object_id = id
	place.paid = int(record.get("paid", 0))
	for result in _world.grid.apply_batch([BuildEdit.remove_object(id), place]):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()


## A cafe guest getting up at its old seat, 5 ticks after its table moved.
func _cafe_exiting() -> Passenger:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid)
	_starts = PassengerTestWorld.starts_with(1500, 4000)
	_world = PassengerTestWorld.make(grid, _starts)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	var started := false
	while p.stage != Passenger.Stage.CAFE_SEATED and _world.clock.tick < 1400:
		_world.step()
		if not started and p.stage == Passenger.Stage.TO_GATE:
			started = _world.sim.cafes.try_visit(p)
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SEATED)
	_move(_ids["air_table"], Vector2i(24, 5))
	for i in 5:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_STANDING_UP)
	return p


## A toilet user leaving its old stall, 30 ticks after the stall moved in use.
func _toilet_exiting() -> Passenger:
	var grid := BuildGrid.new()
	_ids = ToiletTestLayout.build(grid, 1)
	_starts = FlightSim.schedule_starts(0)
	_world = PassengerTestWorld.make(grid, _starts)
	_world.run_to(10)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.stage = Passenger.Stage.TO_SECURITY
	p.stage_tick = _world.clock.tick
	p.at = Vector2i(20, 14) + _at()
	p.clear_path()
	p.toilet_need = 90
	assert_bool(_world.sim.toilets.try_visit(p)).is_true()
	while p.stage != Passenger.Stage.TOILET_USE and _world.clock.tick < 1500:
		_world.step()
	_move(_ids["land_stalls"][0], Vector2i(25, 10))
	for i in 30:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TOILET_EXIT)
	return p


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


## Whether `data` loads into a fresh world, after `change` (a Callable taking
## the loaded grid) when it is set. The fresh world is freed again.
func _loads(data: Dictionary, change := Callable()) -> bool:
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	if change.is_valid():
		change.call(grid)
	var twin := PassengerTestWorld.make(grid, _starts, 99)
	assert_bool(twin.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(twin.flights.from_snapshot(data["flights"])).is_true()
	var loaded := twin.sim.from_snapshot(data["passengers"])
	twin.free_all()
	return loaded


## `data` with the first visit of `facility` ("cafe" or "toilet") given
## relocation fields `fields`.
func _with(data: Dictionary, facility: String, fields: Dictionary) -> Dictionary:
	var out: Dictionary = data.duplicate(true)
	var record: Dictionary = out["passengers"][facility]["visits"][0]["relocation"]
	record.merge(fields, true)
	return out


func _remove(id: int) -> Callable:
	return func(grid: BuildGrid) -> void:
		assert_bool(grid.apply(BuildEdit.remove_object(id)).ok).is_true()


func test_a_cafe_save_returning_to_a_table_no_longer_there_is_refused() -> void:
	_cafe_exiting()
	var data := _save()
	assert_bool(_loads(data)).is_true()
	assert_bool(_loads(data, _remove(_ids["air_table"]))).is_false()


func test_a_cafe_save_owing_no_dwell_or_too_much_is_refused() -> void:
	_cafe_exiting()
	var data := _save()
	var dwell := RoomTypes.get_type(&"cafe").dwell_ticks
	var cases := [
		{"exiting": false, "left": -1},
		{"left": 0},
		{"left": dwell + 1},
		{"left": -2},
	]
	for fields: Dictionary in cases:
		(
			assert_bool(_loads(_with(data, "cafe", fields)))
			. override_failure_message(str(fields))
			. is_false()
		)
	assert_bool(_loads(_with(data, "cafe", {"left": dwell}))).is_true()


func test_a_table_removed_while_its_guest_gets_up_leaves_a_final_unpaid_exit() -> void:
	var p := _cafe_exiting()
	var visit := _world.sim.cafes.visit_of(p.id)
	var cash := _world.sim.wallet.balance
	assert_bool(_world.grid.apply(BuildEdit.remove_object(_ids["air_table"])).ok).is_true()
	# Drawn on the old spot from the moment it is removed, paused or not.
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(1)
	_world.step()
	assert_int(visit.relocation.left).is_equal(-1)
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(1)
	assert_bool(_loads(_save())).is_true()
	while _world.sim.cafes.visit_of(p.id) != null and _world.clock.tick < 3000:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_bool(visit.settled).is_false()
	assert_int(_world.sim.wallet.balance).is_equal(cash)
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(0)


func test_a_toilet_save_returning_to_a_stall_no_longer_there_is_refused() -> void:
	_toilet_exiting()
	var data := _save()
	assert_bool(_loads(data)).is_true()
	assert_bool(_loads(data, _remove(_ids["land_stalls"][0]))).is_false()


func test_a_toilet_save_owing_no_use_or_too_much_is_refused() -> void:
	_toilet_exiting()
	var data := _save()
	var cases := [
		{"exiting": false, "left": -1},
		{"left": 0},
		{"left": ToiletSim.USE_TICKS + 1},
	]
	for fields: Dictionary in cases:
		(
			assert_bool(_loads(_with(data, "toilet", fields)))
			. override_failure_message(str(fields))
			. is_false()
		)
	assert_bool(_loads(_with(data, "toilet", {"left": ToiletSim.USE_TICKS}))).is_true()
