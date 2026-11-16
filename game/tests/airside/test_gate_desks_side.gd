class_name TestGateDesksSide
extends GdUnitTestSuite
## Gate desks link to west and east exits (slice S5 of design airside-all-
## around-technical-design-one-route-source-per-con): a desk links to the
## nearest free exit within LINK_CELLS whichever of the three sides it faces;
## a second gate round a corner of the shell from another is refused when its
## small swing square meets that gate's private ground (GateDesks.
## stands_overlap(), the rule north gates keep); and a side gate's binding and
## stand pass the save checks.
##
## Cells are the starter shell's (ReferenceTerminal coordinates), moved onto the
## grid by the site's starter offset. The shell's own exit is in its north wall
## at (20, 2); the gate desk cell (19, 5) is 3 cells from it and 2 from the
## east wall at (21, 4).

const SITE := preload("res://build/terminal_site.tres")
## Low in the airside half of the west wall: its small swing square stays south
## of gate A's (north exit) private ground.
const WEST_EXIT := Vector2i(10, 6)
## Two rows from the north-east corner.
const EAST_EXIT := Vector2i(21, 4)
const SOUTH_EXIT := Vector2i(12, 17)
const WEST_DESK := Vector2i(12, 5)
## 4 cells from the east exit, 6 from the north one.
const EAST_DESK := Vector2i(19, 8)

var _base: SiteGrid
var _grid: SiteGrid
var _flights: FlightSim
var _gates: GateDesks


func before() -> void:
	_base = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_base, SITE.starter_offset)).is_true()


func before_test() -> void:
	_grid = _base.clone() as SiteGrid
	_flights = auto_free(FlightSim.new()) as FlightSim
	_flights.open_airport()
	_gates = auto_free(GateDesks.new()) as GateDesks
	_gates.bind(_grid, _flights)
	_grid.guard = _gates.edit_problem


func _at(cell: Vector2i) -> Vector2i:
	return cell + SITE.starter_offset


func _add_exit(cell: Vector2i, side: int, facing: int) -> int:
	assert_bool(_grid.apply(BuildEdit.remove_wall(_at(cell), side)).ok).is_true()
	var placed := _grid.apply(BuildEdit.place_object(&"exit_door", _at(cell), facing))
	assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()
	return placed.object_id


func _desk(cell: Vector2i) -> BuildResult:
	return _grid.apply(BuildEdit.place_object(GateDesks.DESK, _at(cell), 0))


func test_a_desk_links_to_a_west_exit_within_reach() -> void:
	var west := _add_exit(WEST_EXIT, BuildGrid.Side.WEST, 3)
	var desk := _desk(WEST_DESK)
	print("desk %s, bindings %s, stands %s" % [desk.reason_text(), _gates.bindings, _gates.stands])
	assert_bool(desk.ok).is_true()
	var footprint := GateDesks.desk_footprint(_grid, desk.object_id)
	assert_int(GateDesks.reach_cells(_grid, footprint, west)).is_less_equal(GateDesks.LINK_CELLS)
	assert_array(_gates.bindings).is_equal([{"gate": "A", "desk": desk.object_id, "exit": west}])
	assert_str(StandPlacement.side_of(_gates.stands["A"])).is_equal(StandPlacement.WEST)
	assert_str(_gates.max_class("A")).is_not_equal("")
	assert_array(_flights.gate_ids()).is_equal(["A"])


## The gate desk cell is nearer the east wall than the shell's north exit, so
## with an east exit there the desk links east.
func test_a_desk_nearer_an_east_exit_than_the_north_one_links_east() -> void:
	var east := _add_exit(EAST_EXIT, BuildGrid.Side.EAST, 1)
	var desk := _desk(ReferenceTerminal.GATE_DESK_CELL)
	print("bindings %s, stands %s" % [_gates.bindings, _gates.stands])
	assert_bool(desk.ok).is_true()
	assert_int(_gates.bindings[0]["exit"]).is_equal(east)
	assert_str(StandPlacement.side_of(_gates.stands["A"])).is_equal(StandPlacement.EAST)


## Gate A holds the north exit. An east exit two rows from the north-east
## corner has its small swing square over gate A's (the plane parks with its
## port side, and so its body, to the north), so a desk for it is refused,
## naming gate A. A west exit low in the west wall is clear of gate A, and its
## desk links: the corner rule refuses only what meets.
func test_a_second_gate_round_the_corner_from_another_is_refused() -> void:
	var north := _grid.object_at(_at(ReferenceTerminal.EXIT_CELL))
	assert_bool(_desk(ReferenceTerminal.GATE_DESK_CELL).ok).is_true()
	assert_int(_gates.bindings[0]["exit"]).is_equal(north)
	var east := _add_exit(EAST_EXIT, BuildGrid.Side.EAST, 1)
	var on_east := StandPlacement.for_exit(_grid, east)
	assert_bool(GateDesks.stands_overlap(on_east, _gates.stands["A"])).is_true()
	var refused := _desk(EAST_DESK)
	print("corner desk: %s (%s)" % [refused.reason_text(), refused.detail])
	assert_int(refused.reason).is_equal(BuildResult.Reason.GATE_STAND_OVERLAP)
	assert_str(refused.detail).is_equal("gate A is too close")
	assert_array(_gates.gate_ids()).is_equal(["A"])
	# Control: a west gate low in the shell is clear of gate A.
	var west := _add_exit(WEST_EXIT, BuildGrid.Side.WEST, 3)
	var on_west := StandPlacement.for_exit(_grid, west)
	assert_bool(GateDesks.stands_overlap(on_west, _gates.stands["A"])).is_false()
	var desk := _desk(WEST_DESK)
	print("west desk: %s, bindings %s" % [desk.reason_text(), _gates.bindings])
	assert_bool(desk.ok).is_true()
	assert_array(_gates.gate_ids()).is_equal(["A", "B"])
	assert_int(_gates.binding_of("B")["exit"]).is_equal(west)


## The gates part and the apron's stands of a west and an east gate pass the
## load checks; a gate saved on a road-side exit is refused.
func test_side_gates_pass_the_save_checks_and_a_road_exit_does_not() -> void:
	var west := _add_exit(WEST_EXIT, BuildGrid.Side.WEST, 3)
	var east := _add_exit(EAST_EXIT, BuildGrid.Side.EAST, 1)
	assert_bool(_desk(WEST_DESK).ok).is_true()
	assert_bool(_desk(ReferenceTerminal.GATE_DESK_CELL).ok).is_true()
	var exits := _gates.bindings.map(func(b: Dictionary) -> int: return b["exit"])
	assert_array(exits).contains_exactly_in_any_order([west, east])
	var data: Dictionary = JSON.parse_string(JSON.stringify(_gates.to_snapshot()))
	var loaded := GateDesks.checked(data, _grid)
	print("checked: %s" % [loaded])
	assert_dict(loaded).not_contains_keys(["error"])
	assert_array(loaded["gates"]).is_equal(_gates.bindings)
	var stands := {}
	for gate: String in _gates.stands:
		stands[gate] = StandPlacement.from_saved(
			JSON.parse_string(JSON.stringify(_gates.stands[gate]))
		)
	assert_str(ApronStand.stands_problem(stands, _gates.bindings, _grid)).is_equal("")
	var south := _add_exit(SOUTH_EXIT, BuildGrid.Side.SOUTH, 2)
	data["gates"][0]["exit"] = south
	var refused := GateDesks.checked(data, _grid)
	print("road exit: %s" % [refused])
	assert_str(refused.get("error", "")).contains("is not an exit facing west, north or east")
