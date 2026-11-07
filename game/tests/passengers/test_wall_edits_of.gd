class_name TestWallEditsOf
extends GdUnitTestSuite
## CarryPlace.WallEdits.of() keeps one WallEdits on a CarryOnProps (its META):
## the first call makes and stores it, the next returns the same object. The
## read must not ask Object.get_meta() for a missing key, which prints the
## "does not have any 'meta'" engine error even with a default (board d977abf9).

var _world: PassengerTestWorld


func before_test() -> void:
	PassengerTestWorld.tracker = self
	_world = PassengerTestWorld.make(BuildGrid.new(), FlightSim.schedule_starts(0))


func after_test() -> void:
	_world.free_all()
	PassengerTestWorld.tracker = null


func _props() -> CarryOnProps:
	var props: CarryOnProps = auto_free(CarryOnProps.new())
	props.sim = _world.sim
	props.clock = _world.clock
	return props


func test_of_stores_edits_on_the_props_at_the_first_call() -> void:
	var props := _props()
	assert_bool(props.has_meta(CarryPlace.WallEdits.META)).is_false()
	var first := CarryPlace.WallEdits.of(props)
	assert_object(first).is_not_null()
	assert_bool(props.has_meta(&"carry_wall_edits")).is_true()
	assert_bool(is_same(props.get_meta(CarryPlace.WallEdits.META), first)).is_true()


## The first call finds no meta; reading it must print no engine error.
func test_the_first_call_prints_no_engine_error() -> void:
	var props := _props()
	await assert_error(func() -> void: CarryPlace.WallEdits.of(props)).is_success()


func test_of_returns_the_same_edits_twice() -> void:
	var props := _props()
	var first := CarryPlace.WallEdits.of(props)
	var second := CarryPlace.WallEdits.of(props)
	assert_bool(is_same(first, second)).is_true()
	assert_bool(is_same(first.grid, _world.sim.grid)).is_true()
