class_name TestStaffPanelOpenCue
extends GdUnitTestSuite
## When the airport opens, the staff panel's "Airport closed" hint is replaced
## once by a line naming the starter contract (decision starter-flight-cue-a-
## one-time-open-starter-contract-line-repl). It is built from the contract
## the gate accepted, and goes when the starter's first flight departs, or when
## a save is loaded.

## More than the one-off flight's 2580 ticks plus the starter's lead.
const ISSUE_LIMIT := 6000
const CUE := "Open! Starter contract: Gotta Air to Oslo, daily"

var _first := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
var _w: PassengerTestWorld
var _gate: AirportGate
var _panel: StaffPanel


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


## A closed airport on a plain floor with the default one-off flight; the gate
## finds the starter a gate C minute after it.
func _make() -> void:
	_w = PassengerTestWorld.make(
		PassengerTestWorld.floored(Vector2i(12, 12)), FlightSim.schedule_starts(0)
	)
	_w.auto_staff = false
	_gate = auto_free(AirportGate.new())
	_gate.bind(_w.flights, _w.staff)
	_panel = auto_free(StaffPanel.new())
	_panel.staff = _w.staff
	_panel.gate = _gate
	add_child(_panel)


## Steps until the starter's first occurrence is issued, so its states are known.
func _issue_first_flight() -> void:
	while not _w.flights.flight_ids().has(_first) and _w.clock.tick < ISSUE_LIMIT:
		_w.step()
	assert_bool(_w.flights.flight_ids().has(_first)).is_true()


func _depart_first_flight() -> void:
	_issue_first_flight()
	var departs := _w.flights.state_start(_first, FlightSim.State.DEPARTED)
	assert_int(departs).is_greater(0)
	_w.run_to(departs - 1)
	assert_str(_panel.hint_label().text).is_equal(CUE)
	_w.step()
	assert_int(_w.flights.state_of(_first)).is_equal(FlightSim.State.DEPARTED)


func test_opening_replaces_the_closed_line_with_the_starter_contract() -> void:
	_make()
	assert_str(_panel.hint_label().text).starts_with("Airport closed: ")
	assert_bool(_gate.open()).is_true()
	assert_str(_panel.hint_label().text).is_equal(CUE)
	assert_str(_panel.hint_text()).is_equal(CUE)
	assert_bool(_panel.hint_label().visible).is_true()


func test_the_line_is_built_from_the_accepted_contract() -> void:
	_make()
	_gate.open()
	var contract := _w.flights.contract_of(FlightSim.DEFAULT_ID)
	assert_str(_panel.hint_label().text).is_equal(
		"Open! Starter contract: %s to %s, daily" % [contract["airline"], contract["destination"]]
	)


func test_the_line_goes_when_the_starters_first_flight_departs() -> void:
	_make()
	_gate.open()
	_depart_first_flight()
	assert_str(_panel.hint_label().text).is_equal("")
	assert_bool(_panel.hint_label().visible).is_false()


func test_the_line_stays_while_the_starter_has_not_departed() -> void:
	_make()
	_gate.open()
	_issue_first_flight()
	_w.run_to(_w.flights.state_start(_first, FlightSim.State.BOARDING))
	assert_str(_panel.hint_label().text).is_equal(CUE)


## Loading a save refreshes the hint with no opening seen: no cue.
func test_loading_an_open_save_shows_no_cue() -> void:
	_make()
	var data := _w.flights.to_snapshot()
	data["opened_tick"] = 0
	assert_bool(_w.flights.from_snapshot(data)).is_true()
	assert_bool(_gate.is_open()).is_true()
	assert_bool(_panel.hint_label().text.contains("Open!")).is_false()


func test_loading_a_save_clears_a_showing_cue() -> void:
	_make()
	_gate.open()
	var data := _w.flights.to_snapshot()
	assert_bool(_w.flights.from_snapshot(data)).is_true()
	assert_bool(_panel.hint_label().text.contains("Open!")).is_false()


func test_a_panel_made_after_the_opening_shows_no_cue() -> void:
	_make()
	_gate.open()
	var late: StaffPanel = auto_free(StaffPanel.new())
	late.staff = _w.staff
	late.gate = _gate
	add_child(late)
	assert_bool(late.hint_label().text.contains("Open!")).is_false()
