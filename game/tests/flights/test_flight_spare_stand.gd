class_name TestFlightSpareStand
extends GdUnitTestSuite
## "No gate free at this time: build another gate" shows only where the player
## could build another stand (board 544f4270, SpareStand), judged with the
## rules a gate desk is refused by: owned land, the existing stands' swing
## squares and a clear envelope. One gate A, whose exit is at (117, 112) in the
## second plot of the first site's row (cells 107 to 128), is booked at 10:00; an offer at
## 12:00 meets A1 only at the gate (its ground route is free), so another
## gate would take it.
##
## SpareStand tries west and east stands too (slice S5 of design airside-all-
## around-technical-design-one-route-source-per-con). A west plane parked from
## the shell's west wall, or an east one from the open cells east of it, fits
## in the home plot, so the no-room cases wall off the sides first
## (_wall_off_the_sides()): two floor strips outside the home plot that every
## west and east plane from it would park over. The control with the east plot
## owned has the strips as well, so it differs from the no-room case only in
## the land.

const SITE := preload("res://build/terminal_site.tres")
const SHIFT := Vector2i(12, 0)
## The plot (column, row) holding the exit, and the one east of it.
const PLOT_HOME := [5, 4]
const PLOT_EAST := [6, 4]
## The floor strips' columns: in the plot west of the home plot, clear of gate
## A's small envelope; and in the east plot, past the nose gap of an east plane
## from the home plot's last column. Their rows cover every side plane's swing
## square from the home plot's rows (100 to 124).
const STRIP_WEST := 103
const STRIP_EAST := 131
const STRIP_ROWS := Vector2i(85, 149)

var _exit_at := ReferenceTerminal.EXIT_CELL + SHIFT + SITE.starter_offset
var _desk_at := ReferenceTerminal.GATE_DESK_CELL + SHIFT + SITE.starter_offset
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
	assert_bool(_grid.apply(BuildEdit.place_object(GateDesks.DESK, _desk_at, 0)).ok).is_true()
	assert_bool(_flights.accept_contract(TestFlightFit.terms("A1", 600))).is_true()


func _own(plots: Array) -> void:
	var land := LandPlots.for_site(SITE)
	assert_bool(land.from_snapshot({"plot_counts": [12, 6], "owned": plots, "bought": 0})).is_true()
	_grid.land = land


## Floor strips at STRIP_WEST and STRIP_EAST, so no west or east plane from
## the home plot has room (painted before the land is set, as the shell is).
func _wall_off_the_sides() -> void:
	var edits: Array[BuildEdit] = []
	for y in range(STRIP_ROWS.x, STRIP_ROWS.y + 1):
		for x in [STRIP_WEST, STRIP_EAST]:
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for result in _grid.apply_batch(edits):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()


## The land plot of the exit cell `stand` is straight out from.
func _plot_of(stand: Dictionary) -> Vector2i:
	var step := StandPlacement.out_step(stand)
	var sill := Vector3(stand["x"], 0.0, stand["wall_z"])
	return _grid.land.plot_of(_grid.world_to_cell(sill - Vector3(step.x, 0.0, step.y) * 0.5))


func _later_offer() -> Dictionary:
	return FlightFit.assess(_flights, TestFlightFit.terms("X", 720))


## Control: with the plot east of the gate owned as well, a stand fits there,
## and the hint fires.
func test_land_for_another_stand_keeps_the_hint() -> void:
	_wall_off_the_sides()
	_own([PLOT_HOME, PLOT_EAST])
	var spare := _gates.spare_stand(PlaneClasses.SMALL)
	var assessment := _later_offer()
	print("spare %s in plot %s, assessment %s" % [spare, _plot_of(spare), assessment])
	assert_bool(StandPlacement.is_stand(spare)).is_true()
	assert_vector(_plot_of(spare)).is_equal(Vector2i(PLOT_EAST[0], PLOT_EAST[1]))
	assert_str(assessment["blocker"]).is_equal(FlightSim.BLOCKER_GATE)
	assert_bool(assessment["another_gate_helps"]).is_true()
	assert_str(FlightFit.text(assessment, PlaneClasses.SMALL)).is_equal(FlightFit.ANOTHER_GATE_TEXT)


## Only the plot the gate stands in is owned, every north stand from it is
## within the gate's swing square or over the shell, and the strips leave no
## west or east plane room: no stand could be built, so no hint. The control
## above shows the same grid and flight with the east plot owned.
func test_no_room_for_another_stand_drops_the_hint() -> void:
	_wall_off_the_sides()
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
	_wall_off_the_sides()
	_own([PLOT_HOME])
	assert_dict(_gates.spare_stand(PlaneClasses.SMALL)).is_empty()
	assert_dict(_gates.spare_stand(PlaneClasses.SMALL)).is_empty()
	_own([PLOT_HOME, PLOT_EAST])
	var spare := _gates.spare_stand(PlaneClasses.SMALL)
	print("after buying: %s" % [spare])
	assert_bool(StandPlacement.is_stand(spare)).is_true()
	assert_dict(_gates.spare_stand(PlaneClasses.SMALL)).is_equal(spare)
