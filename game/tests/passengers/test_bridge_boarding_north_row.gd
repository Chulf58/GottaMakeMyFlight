class_name TestBridgeBoardingNorthRow
extends GdUnitTestSuite
## At a north-row gate the parked plane stands off the paved site, so the jet
## bridge stands on the lower ground under it (JetBridgePose.ground_y()). The
## sim's walk through the bridge and the drawn bridge use that same ground, so
## every walk mount the passengers walk is where the drawn bridge has it
## (board 927ed9e0; decision bridge-boarding-sim-route-chosen-at-departure-
## from-the-fligh).
##
## A terminal two rows in from the site's north edge: rows 2 to 15,
## two north exits 44 m apart on row 2, each with a gate desk, the real
## ApronStand giving each its stand.

const Kit := preload("res://tests/airside/airside_props_kit.gd")
const SITE := preload("res://build/terminal_site.tres")
const EXIT_A := Vector2i(20, 2)
const EXIT_B := Vector2i(64, 2)
const ENTRANCE := Vector2i(24, 15)
const MODEL_05 := "tp_plane_05a"

var _world: PassengerTestWorld
var _exit := 0


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	var floor: Array[BuildEdit] = []
	for y in range(2, 16):
		for x in range(18, 67):
			floor.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(floor)
	PassengerTestWorld.place(grid, &"entrance_door", ENTRANCE, 2)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(23, 11), 0)
	PassengerTestWorld.place(grid, &"security_scanner", Vector2i(24, 6), 0)
	_exit = PassengerTestWorld.place(grid, &"exit_door", EXIT_A, 0)
	PassengerTestWorld.place(grid, &"exit_door", EXIT_B, 0)
	EnclosureKit.close_floor(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.site = SITE
	var gates := auto_free(GateDesks.new()) as GateDesks
	gates.bind(grid, _world.flights)
	PassengerTestWorld.place(grid, GateDesks.DESK, EXIT_A + Vector2i(-1, 2), 0)
	PassengerTestWorld.place(grid, GateDesks.DESK, EXIT_B + Vector2i(-1, 2), 0)
	var apron := auto_free(ApronStand.new()) as ApronStand
	apron.passengers = _world.sim
	apron.bind(grid, SITE, _world.flights, gates)


func after_test() -> void:
	_world.free_all()
	_world = null


func test_a_north_row_bridge_walk_is_where_the_drawn_bridge_has_it() -> void:
	var stand := _world.sim.layout.stand_of(_world.grid, _exit)
	assert_dict(stand).is_not_empty()
	var walk := OutsideWalks.departure(_world.sim, _exit, MODEL_05)
	var airside: Airside = auto_free(Kit.airside_from_main())
	add_child(airside)
	assert_bool(airside.set_gate_stands({"A": stand})).is_true()
	var entry: Dictionary = airside.props.bridges["A"]
	airside.props.dock_plane(1, "A", MODEL_05)
	var old: PackedVector3Array = (
		JetBridgePose.pose_for(stand, MODEL_05, true, SITE.ground_height)["walk"]
	)
	var worst := 0.0
	var old_best := INF
	for k in JetBridgePose.WALK.size():
		var node := entry["node"].find_child(String(JetBridgePose.WALK[k]), true, false) as Node3D
		worst = maxf(worst, node.global_position.distance_to(walk[k + 1]))
		old_best = minf(old_best, node.global_position.distance_to(old[k]))
	var spot := StandPlacement.stand_point(stand)
	print(
		(
			(
				"stand %s, plane at %s (site north edge z %.1f); bridge ground %.3f, root y %.3f;"
				+ " docked %s; walk %s; worst mount %.5f m off; on the site's ground the nearest"
				+ " mount is %.3f m off"
			)
			% [
				stand,
				spot,
				SITE.grid_origin.z,
				JetBridgePose.ground_y(stand),
				(entry["root"] as Transform3D).origin.y,
				entry["docked"],
				walk,
				worst,
				old_best
			]
		)
	)
	assert_float(spot.z).is_less(SITE.grid_origin.z - 4.0)
	assert_bool(entry["docked"]).is_true()
	assert_int(walk.size()).is_equal(1 + JetBridgePose.WALK.size())
	assert_float(worst).is_less(0.001)
	# The control: the walk rooted on the site's ground height floats over the
	# drawn floors by that height.
	assert_float(old_best).is_greater(0.1)
	airside.props.release_plane(1)
