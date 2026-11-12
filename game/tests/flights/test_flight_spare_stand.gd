class_name TestFlightSpareStand
extends GdUnitTestSuite
## "No gate free at this time: build another gate" shows only where the player
## could build another stand (board 544f4270, SpareStand), judged with the
## rules a gate desk is refused by: owned land, the existing stands' swing
## squares and a clear envelope. One gate A, whose exit is at (32, 112) in the
## second plot of the row (cells 22 to 43), is booked at 10:00; an offer at
## 11:00 meets A1 at the gate, and its taxi plan clashes there too, so only a
## second gate would take it.

const SITE := preload("res://build/terminal_site.tres")
const SHIFT := Vector2i(12, 0)
const EXIT_AT := Vector2i(20, 112) + SHIFT
const DESK_AT := Vector2i(19, 115) + SHIFT
## The plot (column, row) holding the exit, and the one east of it.
const PLOT_HOME := [1, 4]
const PLOT_EAST := [2, 4]

var _grid: SiteGrid
var _flights: FlightSim
var _gates: GateDesks


func before_test() -> void:
	_grid = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset + SHIFT)).is_true()
	_flights = auto_free(FlightSim.new()) as FlightSim
	_flights.open_airport()
	_gates = auto_free(GateDesks.new()) as GateDesks
	_gates.bind(_grid, _flights)
	_grid.guard = _gates.edit_problem
	assert_bool(_grid.apply(BuildEdit.place_object(GateDesks.DESK, DESK_AT, 0)).ok).is_true()
	assert_bool(_flights.accept_contract(TestFlightFit.terms("A1", 600))).is_true()


func _own(plots: Array) -> void:
	var land := LandPlots.for_site(SITE)
	assert_bool(land.from_snapshot({"plot_counts": [4, 6], "owned": plots, "bought": 0})).is_true()
	_grid.land = land


func _later_offer() -> Dictionary:
	return FlightFit.assess(_flights, TestFlightFit.terms("X", 660))


## Control: with the plot east of the gate owned as well, a stand fits there,
## and the hint fires.
func test_land_for_another_stand_keeps_the_hint() -> void:
	_own([PLOT_HOME, PLOT_EAST])
	var spare := _gates.spare_stand(PlaneClasses.SMALL)
	var assessment := _later_offer()
	print("spare %s, assessment %s" % [spare, assessment])
	assert_bool(StandPlacement.is_stand(spare)).is_true()
	assert_float(float(spare["x"])).is_greater(float(_gates.stands["A"]["x"]) + 18.0)
	assert_str(assessment["blocker"]).is_equal(FlightSim.BLOCKER_GATE)
	assert_bool(assessment["another_gate_helps"]).is_true()
	assert_str(FlightFit.text(assessment, PlaneClasses.SMALL)).is_equal(FlightFit.ANOTHER_GATE_TEXT)


## Only the plot the gate stands in is owned, and every exit cell in it is
## within the gate's swing square: no stand could be built, so no hint. The
## control above shows the same grid and flight with the east plot owned.
func test_no_room_for_another_stand_drops_the_hint() -> void:
	_own([PLOT_HOME])
	var spare := _gates.spare_stand(PlaneClasses.SMALL)
	var assessment := _later_offer()
	print("spare %s, assessment %s" % [spare, assessment])
	assert_dict(spare).is_empty()
	assert_str(assessment["blocker"]).is_equal(FlightSim.BLOCKER_GATE)
	assert_bool(assessment["another_gate_helps"]).is_false()
	assert_str(FlightFit.text(assessment, PlaneClasses.SMALL)).is_equal(
		FlightFit.GATE_AND_TAXI_TEXT
	)


## The spare stand is the first the rules accept: it stands on owned land, its
## small swing square meets gate A's, and its envelope for the class is clear.
func test_the_spare_stand_obeys_the_gate_desk_rules() -> void:
	_own([PLOT_HOME, PLOT_EAST])
	var spare := _gates.spare_stand(PlaneClasses.MEDIUM)
	print("spare %s" % [spare])
	assert_bool(StandPlacement.is_stand(spare)).is_true()
	assert_bool(GateDesks.stands_overlap(spare, _gates.stands["A"])).is_false()
	var blocked := StandEnvelope.blocked_part(_grid, _grid.site, spare, PlaneClasses.MEDIUM)
	assert_int(blocked).is_equal(StandEnvelope.Part.CLEAR)


## The answer is kept between asks but follows the land: buying the east plot
## after an empty answer finds the stand.
func test_buying_land_after_an_empty_answer_finds_a_stand() -> void:
	_own([PLOT_HOME])
	assert_dict(_gates.spare_stand(PlaneClasses.SMALL)).is_empty()
	assert_dict(_gates.spare_stand(PlaneClasses.SMALL)).is_empty()
	_own([PLOT_HOME, PLOT_EAST])
	var spare := _gates.spare_stand(PlaneClasses.SMALL)
	print("after buying: %s" % [spare])
	assert_bool(StandPlacement.is_stand(spare)).is_true()
	assert_dict(_gates.spare_stand(PlaneClasses.SMALL)).is_equal(spare)
