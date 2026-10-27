class_name TestCafeSaveControl
extends GdUnitTestSuite
## A save after a cafe edit, checked against an UNSAVED control world (board
## item economy-8-8-whole-world-save-and-save-files-design-decision, the
## carried cafe residual). Four cafe worlds from one seed meet the same edit
## on the same tick, with guests queuing, ordering and seated: the control is
## never saved; the waiting world is saved the way SaveGame saves, after the
## next tick has settled the cafe, and a fourth world loads that save; the
## early world settles the cafe at save time (CafeSim.reconcile() between the
## edit and the tick, which PassengerSim.to_snapshot() used to do). The
## waiting and loaded worlds must match the control on every tick through
## doors close. The early world is the positive control: it drifts, so the
## comparison can see a settle a tick early.

const HUNGRY := 59
const SEED := 4242

var _control: PassengerTestWorld
var _waiting: PassengerTestWorld
var _early: PassengerTestWorld
var _loaded: PassengerTestWorld
var _ids: Dictionary
var _first_bad := {}
var _was_busy := false


func before() -> void:
	PassengerTestWorld.tracker = self
	_control = _busy_world()
	_waiting = _busy_world()
	_early = _busy_world()
	var worlds := [_control, _waiting, _early]
	while not _busy(_control) and _control.clock.tick < 1400:
		_step(worlds)
	_was_busy = _busy(_control)
	for world in worlds:
		for removed in [_ids["air_table"], _ids["land_counter"]]:
			assert_bool(world.grid.apply(BuildEdit.remove_object(removed)).ok).is_true()
	_early.sim.cafes.reconcile()
	assert_bool(_waiting.sim.to_snapshot().is_empty()).is_true()
	_step(worlds)
	_loaded = _load(_save(_waiting))
	worlds.append(_loaded)
	for world in [_waiting, _early, _loaded]:
		_first_bad[world] = -1
	while _control.clock.tick <= _control.flights.doors_close_tick(PassengerTestWorld.FLIGHT):
		_step(worlds)
		var expected := _signature(_control)
		for world in _first_bad:
			if _first_bad[world] < 0 and _signature(world) != expected:
				_first_bad[world] = world.clock.tick


func after() -> void:
	PassengerTestWorld.tracker = null


func _busy_world() -> PassengerTestWorld:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid, true)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(1500, 4000), SEED)
	for i in 12:
		world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT)).hunger = HUNGRY
	return world


## Guests seated, ordering and queuing at once.
static func _busy(world: PassengerTestWorld) -> bool:
	var stages := {}
	for id in world.sim.cafes.visit_ids():
		stages[world.passenger(id).stage] = true
	for stage in [
		Passenger.Stage.CAFE_SEATED, Passenger.Stage.CAFE_ORDER, Passenger.Stage.CAFE_QUEUE
	]:
		if not stages.has(stage):
			return false
	return true


static func _step(worlds: Array) -> void:
	for world in worlds:
		world.step()


static func _save(world: PassengerTestWorld) -> String:
	return (
		JSON
		. stringify(
			{
				"clock": world.clock.to_snapshot(),
				"flights": world.flights.to_snapshot(),
				"grid": world.grid.to_snapshot(),
				"passengers": world.sim.to_snapshot(),
				"wallet": world.sim.wallet.to_snapshot(),
			},
			"",
			true,
			true
		)
	)


func _load(text: String) -> PassengerTestWorld:
	var data: Dictionary = JSON.parse_string(text)
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(1500, 4000), 99)
	assert_bool(world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	assert_bool(world.sim.wallet.from_snapshot(data["wallet"])).is_true()
	return world


## Everything a save of the world would hold: the passenger sim's whole
## snapshot (it only reads, and no edit is pending after a tick) and the wallet.
static func _signature(world: PassengerTestWorld) -> String:
	var state := {"passengers": world.sim.to_snapshot(), "wallet": world.sim.wallet.to_snapshot()}
	return JSON.stringify(state, "", true, true)


func test_the_edit_met_guests_queuing_ordering_and_seated() -> void:
	assert_bool(_was_busy).is_true()
	assert_int(_control.sim.made_count()).is_greater(0)
	assert_int(_first_bad.size()).is_equal(3)


func test_a_world_saved_after_the_next_tick_matches_the_unsaved_control() -> void:
	(
		assert_int(_first_bad[_waiting])
		. override_failure_message("first differing tick %d" % _first_bad[_waiting])
		. is_equal(-1)
	)


func test_the_world_loaded_from_that_save_matches_the_unsaved_control() -> void:
	(
		assert_int(_first_bad[_loaded])
		. override_failure_message("first differing tick %d" % _first_bad[_loaded])
		. is_equal(-1)
	)


func test_a_cafe_settled_at_save_time_drifts_from_the_control() -> void:
	assert_int(_first_bad[_early]).is_greater(0)
