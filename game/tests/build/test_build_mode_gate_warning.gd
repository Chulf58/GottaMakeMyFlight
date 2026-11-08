class_name TestBuildModeGateWarning
extends GdUnitTestSuite
## The build ghost warns before an allowed edit lowers a gate's biggest plane
## (decision runway-and-taxi-technical-design-movement-plan-analytic-bookings-
## planned-pauses, section 3, and the user's "Allowed, gate size drops"
## answer): hovering the floor tool over gate A's large-only space puts "Gate A
## will then take planes up to medium" on the status line, through
## BuildStatus.front_warning() and the site grid's GateDesks warner. A control
## cell outside every envelope shows no gate warning.
##
## The starter shell on the airport site, with its gate desk at (19, 115) by the
## exit at (20, 112); the cells are those of test_stand_envelope.gd.

const SITE := preload("res://build/terminal_site.tres")
const DESK := Vector2i(19, 115)
const LARGE_CELL := Vector2i(45, 100)
const FREE_CELL := Vector2i(60, 100)
const WARNING := "Gate A will then take planes up to medium"

var _finances: Finances
var _mode: BuildMode
var _flights: FlightSim
var _gates: GateDesks


func before() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.site = SITE
	_mode.finances = _finances
	add_child(_mode)
	_mode.set_process(false)
	LandKit.own_all(_mode.land_tool.land)
	assert_bool(StarterShell.place(_mode.grid, SITE.starter_offset)).is_true()
	_flights = FlightSim.new()
	_flights.open_airport()
	_gates = GateDesks.new()
	_gates.bind(_mode.grid, _flights)
	var grid := _mode.grid as SiteGrid
	grid.guard = _gates.edit_problem
	grid.warner = _gates.edit_warning
	assert_bool(grid.apply(BuildEdit.place_object(GateDesks.DESK, DESK, 0)).ok).is_true()
	assert_str(_gates.max_class("A")).is_equal("large")
	_mode.set_tool(BuildMode.Tool.FLOOR)


func after() -> void:
	_mode.free()
	_finances.free()
	_gates.free()
	_flights.free()


func _hover(cell: Vector2i) -> String:
	_mode._update_ghost(_mode.grid.cell_to_world(cell))
	return _mode.status_text()


func test_hovering_the_large_only_space_warns_that_the_gate_takes_medium_at_most() -> void:
	var over_large := _hover(LARGE_CELL)
	var over_free := _hover(FREE_CELL)
	print("status over the large-only cell '%s'; over the free cell '%s'" % [over_large, over_free])
	assert_str(over_large).contains(WARNING)
	# The control: outside every envelope there is no gate warning.
	assert_str(over_free).not_contains("Gate A")
	# The warning goes with the pointer, and nothing was built by hovering.
	assert_int(_mode.grid.floor_at(LARGE_CELL)).is_equal(BuildGrid.FLOOR_NONE)
	assert_str(_gates.max_class("A")).is_equal("large")


func test_the_warning_is_the_front_warning_for_the_edit() -> void:
	var edit := BuildEdit.paint_floor(LARGE_CELL, BuildGrid.FLOOR_TILE, 1)
	var free := BuildEdit.paint_floor(FREE_CELL, BuildGrid.FLOOR_TILE, 1)
	assert_str(BuildStatus.front_warning(_mode.grid, edit)).is_equal(WARNING)
	assert_str(BuildStatus.front_warning(_mode.grid, free)).is_empty()
	assert_str(BuildStatus.front_warning(_mode.grid, null)).is_empty()
