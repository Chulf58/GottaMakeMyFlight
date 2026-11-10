class_name TestBridgeBoardingWalk
extends GdUnitTestSuite
## Passengers board through the nose-loader jet bridge (board 927ed9e0;
## decisions bridge-boarding-sim-route-chosen-at-departure-from-the-fligh,
## jet-bridge-walk-length-counts-toward-boarding-time-lateness and plane-03-
## boards-on-foot-from-the-apron-plane-04-docks-the-no). A walker of a flight
## drawn with 04 to 07 walks the door cell's centre and then JetBridgePose's
## walk, up the stair and through the cab, never on the open apron; plane 03's
## walkers leave by the apron door; the walk is measured in 3D, so the stair
## costs its climb and the files hold their gap along it; a wall edit leaves a
## bridge walker alone; the doors still close on one left on the bridge; and
## the drawn bridge docks from the same flight model the walk is chosen from.
##
## The terminal is test_passenger_gate_exits.gd's: two north exits 44 m apart
## with a gate desk each, the real ApronStand giving each its stand. Contract
## C05 (Nordic Wing, model 05) and C04 (Meridian Air, model 04) fly medium
## planes; the one-off flight flies the starter's small plane, model 03.

const Kit := preload("res://tests/airside/airside_props_kit.gd")
const SITE := preload("res://build/terminal_site.tres")
const EXIT_A := Vector2i(20, 112)
const EXIT_B := Vector2i(64, 112)
const ENTRANCE := Vector2i(24, 125)
const MODEL_03 := "tp_plane_03a"
const MODEL_04 := "tp_plane_04a"
const MODEL_05 := "tp_plane_05a"
const DOCKING: Array[String] = ["tp_plane_04a", "tp_plane_05a", "tp_plane_06a", "tp_plane_07a"]
const ONE_OFF_LATER_MIN := 600
const ONE_OFF_03 := "ONE_OFF_03"
const ONE_OFF_03_MIN := 900
## Sampling step along a walk, in metres, and how high above the ground a
## sample must be to count as off the apron.
const SAMPLE_M := 0.25
const RAISED_M := 0.3

var _world: PassengerTestWorld
var _gates: GateDesks
var _apron: ApronStand
var _flights := {}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	var floor: Array[BuildEdit] = []
	for y in range(112, 126):
		for x in range(18, 67):
			floor.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(floor)
	PassengerTestWorld.place(grid, &"entrance_door", ENTRANCE, 2)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(23, 121), 0)
	PassengerTestWorld.place(grid, &"security_scanner", Vector2i(24, 116), 0)
	PassengerTestWorld.place(grid, &"exit_door", EXIT_A, 0)
	PassengerTestWorld.place(grid, &"exit_door", EXIT_B, 0)
	EnclosureKit.close_floor(grid)
	var starts := FlightSim.schedule_starts(ONE_OFF_LATER_MIN * GameCalendar.TICKS_PER_MINUTE)
	_world = PassengerTestWorld.make(grid, starts)
	_world.sim.site = SITE
	_gates = auto_free(GateDesks.new()) as GateDesks
	_gates.bind(grid, _world.flights)
	PassengerTestWorld.place(grid, GateDesks.DESK, EXIT_A + Vector2i(-1, 2), 0)
	PassengerTestWorld.place(grid, GateDesks.DESK, EXIT_B + Vector2i(-1, 2), 0)
	_apron = auto_free(ApronStand.new()) as ApronStand
	_apron.passengers = _world.sim
	_apron.bind(grid, SITE, _world.flights, _gates)
	_world.flights.open_airport()
	_flights = {}
	_flights[MODEL_05] = _contract("C05", "Nordic Wing", 0)
	_flights[MODEL_04] = _contract("C04", "Meridian Air", 30)
	# A one-off flight (the starter's plane 03) at the 05's gate, long after.
	var later := FlightSim.schedule_starts(ONE_OFF_03_MIN * GameCalendar.TICKS_PER_MINUTE)
	var gate := _world.flights.flight_gate(_flights[MODEL_05])
	assert_bool(_world.flights.add_flight(ONE_OFF_03, later, gate)).is_true()
	_flights[MODEL_03] = ONE_OFF_03
	for model: String in _flights:
		assert_str(PlaneClasses.flight_model(_world.flights, _flights[model])).is_equal(model)


func after_test() -> void:
	_world.free_all()
	_world = null


func test_a_docking_models_walk_is_the_door_cell_then_the_bridge_and_never_the_apron() -> void:
	var exit := _exit_of(MODEL_05)
	var stand := _world.sim.layout.stand_of(_world.grid, exit)
	var centre := _world.grid.cell_to_world(_world.sim.layout.door_cell(_world.grid, exit))
	var ground_walk := OutsideWalks.departure(_world.sim, exit)
	for model in DOCKING:
		var walk := OutsideWalks.departure(_world.sim, exit, model)
		var pose := JetBridgePose.pose_for(stand, model, true, SITE.ground_height)
		var want: Array[Vector3] = [centre]
		want.append_array(Array(pose["walk"]))
		var on_apron := _on_apron(walk, stand, pose["pose"])
		print(
			(
				(
					"%s: docks_at %s, walk %s; sill %s vs ground walk's outer edge %s; %d of %d samples"
					+ " on the apron"
				)
				% [
					model,
					OutsideWalks.docks_at(_world.sim, exit, model),
					walk,
					walk[1],
					ground_walk[1],
					on_apron.x,
					on_apron.y
				]
			)
		)
		assert_bool(OutsideWalks.docks_at(_world.sim, exit, model)).is_true()
		assert_bool(pose["docked"]).is_true()
		assert_array(walk).is_equal(want)
		assert_int(walk.size()).is_equal(1 + JetBridgePose.WALK.size())
		# The stitch: the sill is the ground walk's outer-edge point on x and z.
		assert_float(walk[1].x).is_equal_approx(ground_walk[1].x, 0.0001)
		assert_float(walk[1].z).is_equal_approx(ground_walk[1].z, 0.0001)
		assert_int(on_apron.y).is_greater(20)
		assert_int(on_apron.x).is_equal(0)
	# The control: the ground walk the bridge replaces is out on the apron.
	var ground_on := _on_apron(ground_walk, stand, _pose_of(MODEL_05)["pose"])
	print("ground walk %s: %d of %d samples on the apron" % [ground_walk, ground_on.x, ground_on.y])
	assert_int(ground_on.x).is_greater(10)


func test_a_plane_03_passenger_leaves_by_the_apron_door() -> void:
	var exit := _exit_of(MODEL_03)
	var stand := _world.sim.layout.stand_of(_world.grid, exit)
	var pose := JetBridgePose.pose_for(stand, MODEL_03, false, SITE.ground_height)
	var apron_door: Vector3 = pose["mounts"][&"Mount_ApronDoor"]
	var p := _stepped_out(MODEL_03)
	var docking := OutsideWalks.departure(_world.sim, _exit_of(MODEL_05), MODEL_05)
	print(
		(
			(
				"03 walk %s, apron door %s, plane door %s; docks_at %s; 05 walk nearest the apron"
				+ " door %.3f m"
			)
			% [
				p.apron,
				apron_door,
				pose["door"],
				OutsideWalks.docks_at(_world.sim, exit, MODEL_03),
				_nearest(docking, _pose_of(MODEL_05)["mounts"][&"Mount_ApronDoor"])
			]
		)
	)
	assert_bool(OutsideWalks.docks_at(_world.sim, exit, MODEL_03)).is_false()
	assert_int(p.apron.size()).is_equal(4)
	assert_vector(p.apron[1]).is_equal(pose["mounts"][&"Mount_ExitSill"])
	assert_vector(p.apron[2]).is_equal(apron_door)
	var door: Vector3 = pose["door"]
	assert_vector(p.apron[3]).is_equal(Vector3(door.x, SITE.ground_height, door.z))
	# The control: a docking walk does not pass the apron door.
	assert_float(_nearest(docking, _pose_of(MODEL_05)["mounts"][&"Mount_ApronDoor"])).is_greater(
		0.5
	)


func test_apron_segments_are_measured_in_3d_and_the_stair_costs_its_climb() -> void:
	var step := Passenger.new()
	step.apron.assign([Vector3.ZERO, Vector3(0.0, 3.0, 4.0)])
	var flat := Passenger.new()
	flat.apron.assign([Vector3.ZERO, Vector3(0.0, 0.0, 4.0)])
	var p := _stepped_out(MODEL_05)
	# Point 2 is the stair foot and point 3 the stair top.
	var stair := p.apron_segment_mm(3)
	var foot := p.apron[2]
	var top := p.apron[3]
	var on_ground := roundi(Vector2(foot.x, foot.z).distance_to(Vector2(top.x, top.z)) * 1000.0)
	print(
		(
			(
				"climb 3 m over 4 m: %d mm, flat 4 m: %d mm; stair %s -> %s: %d mm, %d mm on the"
				+ " ground; walk %d mm"
			)
			% [
				step.apron_segment_mm(1),
				flat.apron_segment_mm(1),
				foot,
				top,
				stair,
				on_ground,
				p.apron_total_mm(),
			]
		)
	)
	assert_int(step.apron_segment_mm(1)).is_equal(5000)
	assert_int(flat.apron_segment_mm(1)).is_equal(4000)
	assert_int(stair).is_equal(roundi(foot.distance_to(top) * 1000.0))
	assert_int(stair - on_ground).is_greater(200)
	# The files and the forecast price the same 3D walk.
	var own := JourneyForecast.own_times(_world.sim, p, 0, true)
	assert_int(own["plane_tick"]).is_equal(JourneyForecast.walk_ticks(p.apron_total_mm()))
	var apron := _world.sim.files.apron_of(_world.sim, p.exit_object, p)
	assert_int(apron["mm"]).is_equal(p.apron_total_mm())
	assert_that(apron["plane"]).is_equal(BoardingFiles.plane_key(p.apron.back()))


## Two walkers on the stair: the one behind is held GAP_MM back along the 3D
## walk, although on the ground they stand closer than that.
func test_the_apron_file_holds_its_gap_along_the_3d_stair() -> void:
	var lead := _stepped_out(MODEL_05)
	var mid_stair := (
		lead.apron_segment_mm(1) + lead.apron_segment_mm(2) + lead.apron_segment_mm(3) / 2
	)
	lead.apron_mm = mid_stair
	var next := _world.passenger(_world.sim.spawn_now(_flights[MODEL_05]))
	next.stage = Passenger.Stage.TO_EXIT
	next.exit_object = lead.exit_object
	next.at = _world.sim.layout.door_cell(_world.grid, lead.exit_object)
	assert_bool(_world.sim.files.join_plane(_world.sim, next)).is_true()
	next.apron = lead.apron.duplicate()
	next.stage = Passenger.Stage.APRON
	var free_mm := 100
	next.apron_mm = mid_stair - BoardingFiles.GAP_MM - free_mm
	var room := _world.sim.files.allowed(_world.sim, next, 1000)
	next.apron_mm = mid_stair - BoardingFiles.GAP_MM
	var held := _world.sim.files.allowed(_world.sim, next, 1000)
	var a := lead.apron_position()
	var b := next.apron_position()
	var flat := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	print(
		(
			(
				"lead at %s, next at %s: %.3f m apart, %.3f m on the ground; room %d mm with %d free,"
				+ " %d mm at the gap"
			)
			% [a, b, a.distance_to(b), flat, room, free_mm, held]
		)
	)
	assert_array(_world.sim.files.plane_file_of(next.id)).is_equal([lead.id, next.id])
	assert_int(room).is_equal(free_mm)
	assert_int(held).is_equal(0)
	assert_float(a.y - b.y).is_greater(0.1)
	assert_float(a.distance_to(b)).is_equal_approx(BoardingFiles.GAP_MM / 1000.0, 0.002)
	assert_float(flat).is_less(BoardingFiles.GAP_MM / 1000.0 - 0.02)


## Floor laid across the apron under the bridge: a walker on the 03's walk
## out of the apron door cannot go on, while one in the bridge walks on
## untouched and makes its flight.
func test_a_build_edit_leaves_a_bridge_walker_untouched() -> void:
	var bridge := _stepped_out(MODEL_05)
	bridge.apron_mm = 3000
	var on_foot := _stepped_out(MODEL_03)
	on_foot.apron_mm = 1500
	var walk := bridge.apron.duplicate()
	var foot_walk := on_foot.apron.duplicate()
	var row: Array[BuildEdit] = []
	for x in SITE.grid_size.x:
		row.append(BuildEdit.paint_floor(Vector2i(x, EXIT_A.y - 4), BuildGrid.FLOOR_TILE, 1))
	var searched := OutsideWalks.fields_searched
	_world.grid.apply_batch(row)
	print(
		(
			(
				"bridge walker %s at %d mm, stuck %s; on-foot walker stuck %s, walk %s -> %s; fields"
				+ " searched %d"
			)
			% [
				bridge.apron,
				bridge.apron_mm,
				Passenger.Stuck.keys()[bridge.stuck],
				Passenger.Stuck.keys()[on_foot.stuck],
				foot_walk,
				on_foot.apron,
				OutsideWalks.fields_searched - searched
			]
		)
	)
	assert_array(bridge.apron).is_equal(walk)
	assert_int(bridge.apron_mm).is_equal(3000)
	assert_int(bridge.stuck).is_equal(Passenger.Stuck.NONE)
	# The control: the same edit stops the walker out on the apron.
	assert_int(on_foot.stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	assert_int(OutsideWalks.fields_searched - searched).is_greater(0)
	var ticks := 0
	while bridge.stage == Passenger.Stage.APRON and ticks < 400:
		_world.step()
		ticks += 1
	print("bridge walker %s after %d ticks" % [Passenger.Stage.keys()[bridge.stage], ticks])
	assert_int(bridge.stage).is_equal(Passenger.Stage.MADE)


func test_a_walker_still_on_the_bridge_when_the_doors_close_misses_its_flight() -> void:
	var flight: String = _flights[MODEL_05]
	var doors := _world.flights.doors_close_tick(flight)
	_world.run_to(doors - 400)
	var early := _put_on_walk(MODEL_05)
	_world.run_to(doors - 30)
	var late := _put_on_walk(MODEL_05)
	var total := late.apron_total_mm()
	_world.run_to(doors - 1)
	var at := late.apron_position()
	var walked := late.apron_mm
	_world.run_to(doors + 2)
	print(
		(
			(
				"doors at %d: early %s; late %s, %d of %d mm walked, at %s (%.2f m up) the tick"
				+ " before"
			)
			% [
				doors,
				Passenger.Stage.keys()[early.stage],
				Passenger.Stage.keys()[late.stage],
				walked,
				total,
				at,
				at.y - SITE.ground_height
			]
		)
	)
	assert_int(early.stage).is_equal(Passenger.Stage.MADE)
	assert_int(late.stage).is_equal(Passenger.Stage.MISSED)
	assert_int(walked).is_greater(0)
	assert_int(walked).is_less(total)
	assert_float(at.y - SITE.ground_height).is_greater(RAISED_M)


## The drawn bridge docks from the flight model the walk is chosen from: its
## walk mounts are the sim's walk points, and a report of plane 03 parks it,
## with the 03 walk leaving by its drawn apron door.
func test_the_drawn_bridge_docks_from_the_flight_model_the_walk_uses() -> void:
	var exit := _exit_of(MODEL_05)
	var stand := _world.sim.layout.stand_of(_world.grid, exit)
	var airside: Airside = auto_free(Kit.airside_from_main())
	add_child(airside)
	assert_bool(airside.set_gate_stands({"A": stand})).is_true()
	var entry: Dictionary = airside.props.bridges["A"]
	var node: Node3D = entry["node"]
	airside.props.dock_plane(1, "A", MODEL_05)
	var walk := OutsideWalks.departure(_world.sim, exit, MODEL_05)
	var worst := 0.0
	for k in JetBridgePose.WALK.size():
		var mount := node.find_child(String(JetBridgePose.WALK[k]), true, false) as Node3D
		worst = maxf(worst, mount.global_position.distance_to(walk[k + 1]))
	var docked_05: bool = entry["docked"]
	airside.props.dock_plane(1, "A", MODEL_03)
	var drawn_door := (node.find_child("Mount_Door", true, false) as Node3D).global_position
	var drawn_apron := (node.find_child("Mount_ApronDoor", true, false) as Node3D).global_position
	var foot := OutsideWalks.departure(_world.sim, _exit_of(MODEL_03), MODEL_03)
	print(
		(
			(
				"05 report: docked %s, worst walk mount %.5f m off the sim's walk (root y %.3f, site"
				+ " ground %.3f); 03 report: docked %s, Mount_Door %.3f m from the 05 walk's end, apron"
				+ " door %s vs 03 walk %s"
			)
			% [
				docked_05,
				worst,
				(entry["root"] as Transform3D).origin.y,
				SITE.ground_height,
				entry["docked"],
				drawn_door.distance_to(walk.back()),
				drawn_apron,
				foot
			]
		)
	)
	assert_bool(docked_05).is_true()
	assert_float(worst).is_less(0.001)
	assert_bool(entry["docked"]).is_false()
	assert_dict(entry["pose"]).is_equal(JetBridgePose.parked())
	assert_float(drawn_door.distance_to(walk.back())).is_greater(0.5)
	assert_int(_exit_of(MODEL_03)).is_equal(exit)
	assert_float(drawn_apron.distance_to(foot[2])).is_less(0.001)
	airside.props.release_plane(1)


func _pose_of(model: String) -> Dictionary:
	var stand := _world.sim.layout.stand_of(_world.grid, _exit_of(model))
	return JetBridgePose.pose_for(stand, model, JetBridgePose.docks(model), SITE.ground_height)


## The contract `id` of `airline`'s medium plane, leaving `later_min` after
## the bootstrap minute; returns its flight id.
func _contract(id: String, airline: String, later_min: int) -> String:
	var terms := {
		"id": id,
		"airline": airline,
		"destination": "Oslo",
		"departure_minute": TestFlightContracts.bootstrap_minute() + later_min,
		"plane_size": PlaneClasses.MEDIUM,
		"booked_passengers": 24,
		"fee_per_passenger": 25,
	}
	assert_str(_world.flights.accept_problem(terms)).is_empty()
	assert_bool(_world.flights.accept_contract(terms)).is_true()
	for flight in _world.flights.flight_ids():
		if _world.flights.flight_contract_id(flight) == id:
			return flight
	return ""


## The exit of the gate the flight drawn with `model` stands at.
func _exit_of(model: String) -> int:
	var gate := _world.flights.flight_gate(_flights[model])
	return _world.sim.layout.open_exits_for(_world.grid, gate)[0]


## A passenger of the flight drawn with `model`, at its gate's exit, stepped
## out onto its walk to the plane (PassengerGates.step_out()).
func _stepped_out(model: String) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(_flights[model]))
	p.stage = Passenger.Stage.TO_EXIT
	p.exit_object = _exit_of(model)
	p.at = _world.sim.layout.door_cell(_world.grid, p.exit_object)
	PassengerGates.step_out(_world.sim, p)
	assert_int(p.stage).is_equal(Passenger.Stage.APRON)
	return p


## A passenger of the flight drawn with `model` put straight onto its walk out
## of its gate's exit, in no file, so the flight's own passengers on the way
## out cannot hold it at the door.
func _put_on_walk(model: String) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(_flights[model]))
	p.stage = Passenger.Stage.APRON
	p.exit_object = _exit_of(model)
	p.apron = OutsideWalks.departure(_world.sim, p.exit_object, model)
	p.apron_mm = 0
	return p


## (samples on the open apron, samples) along `walk` from its second point
## (the exit sill), every SAMPLE_M, against the bridge docked with `pose` (a
## pose_for() pose): a sample is in the bridge when it stands on the bridge's
## floor, in its root's frame: within the enclosure's width and on the
## vestibule floor, the stair's slope or the landing's height; or when it is
## RAISED_M or more up (the cab). Any other sample is on the apron.
func _on_apron(walk: Array[Vector3], stand: Dictionary, pose: Dictionary) -> Vector2i:
	var inv := JetBridgePose.root_for(stand, SITE.ground_height).affine_inverse()
	var foot: float = JetBridgePose.STAIR_Z0 - JetBridgePose.STEP_OFF + pose["slide"]
	var top: float = JetBridgePose.STAIR_Z1 + JetBridgePose.STEP_OFF + pose["slide"]
	var height: float = pose["height"]
	var count := Vector2i.ZERO
	for i in range(2, walk.size()):
		var steps := maxi(1, ceili(walk[i - 1].distance_to(walk[i]) / SAMPLE_M))
		for k in steps + 1:
			var local := inv * walk[i - 1].lerp(walk[i], k / float(steps))
			var floor_y := height * clampf((local.z - foot) / (top - foot), 0.0, 1.0)
			var on_floor := (
				absf(local.x) <= JetBridgePose.VEST_HALF and absf(local.y - floor_y) < 0.05
			)
			count.y += 1
			if not on_floor and local.y < RAISED_M:
				count.x += 1
	return count


func _nearest(walk: Array[Vector3], point: Vector3) -> float:
	var best := INF
	for i in range(1, walk.size()):
		var seg := Geometry3D.get_closest_point_to_segment(point, walk[i - 1], walk[i])
		best = minf(best, seg.distance_to(point))
	return best
