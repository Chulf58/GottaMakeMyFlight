class_name TestFlightResultDropOff
extends GdUnitTestSuite
## The flight result panel names the landside miss: passengers still in
## their car or taxi when the doors close show as "Waiting for drop-off" in
## the result PassengerHud opens, counted in Missed (decision landside-
## technical-design-arrival-bookings-landsidesim-vehic). The terminal has
## its entrance, so these are traffic misses, not no-shows; the doors close at
## tick 60, before the first car reaches the curb 94 ticks along the 47 m road
## (as in test_landside_doors_close.gd). The panel keeps
## its three-reason limit: below three larger reasons the drop-off count is
## summed into Other, never lost.

const BOARDING := 30
const DOORS := 60
const BOOKED := 6

var _land: LandsideTestWorld
var _mode: BuildMode
var _hud: PassengerHud


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_land = LandsideTestWorld.make(null, PassengerTestWorld.starts_with(BOARDING, DOORS), 3)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(10, 10)
	add_child(_mode)
	_hud = PassengerHud.new()
	_hud.clock = _land.world.clock
	_hud.flights = _land.world.flights
	_hud.sim = _land.sim
	_hud.build_mode = _mode
	add_child(_hud)


func after_test() -> void:
	_hud.free()
	_mode.free()
	_land.free_all()
	_land = null


func test_passengers_still_on_the_road_at_doors_close_show_waiting_for_drop_off() -> void:
	assert_bool(_land.sim.layout.entrances.is_empty()).is_false()
	_land.schedule(BOOKED)
	_land.run_to(DOORS + 1)
	_hud.refresh()
	var text := _hud.result_text()
	print(text)
	assert_bool(_hud.is_result_open()).is_true()
	assert_str(text).contains("Made 0   Missed %d" % BOOKED)
	assert_str(text).contains("%d  %s" % [BOOKED, FlightResult.WAITING_FOR_DROP_OFF])


func test_below_three_larger_reasons_the_drop_off_count_goes_into_other() -> void:
	var summary := {
		"flight": PassengerTestWorld.FLIGHT,
		"made": 0,
		"missed": 13,
		"reasons":
		[
			{"text": "Still queuing for check-in", "count": 5},
			{"text": "Still queuing for security", "count": 4},
			{"text": "Still walking to the gate", "count": 3},
			{"text": FlightResult.WAITING_FOR_DROP_OFF, "count": 1},
		],
	}
	var text := FlightResultPanel.text_for(summary)
	print(text)
	assert_str(text).not_contains(FlightResult.WAITING_FOR_DROP_OFF)
	assert_str(text).ends_with("1  Other")
