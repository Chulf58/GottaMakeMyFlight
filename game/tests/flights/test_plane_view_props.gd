class_name TestPlaneViewProps
extends GdUnitTestSuite
## A real PlaneView drives the airside props through update_pose() (board
## 4c08b8e5): a large contract flight, stepped by the sim's tick through the
## stand, the pushback and past its climb-out, docks its gate's bridge at the
## drawn door while boarding, shows the tug on the nose wheel during pushback,
## and lets both go when it leaves the stand or hides. A view freed while
## docked parks the bridge.

const Kit := preload("res://tests/airside/airside_props_kit.gd")
const STAND := {"exit": 4, "x": 21.5, "wall_z": -98.0}
const TOLERANCE_M := 0.01

var _airside: Airside


func before() -> void:
	_airside = Kit.airside_from_main()
	add_child(_airside)
	# A contract accepted with no gate source flies from the default gate.
	assert_bool(_airside.set_gate_stands({FlightSim.DEFAULT_GATE: STAND})).is_true()


func after() -> void:
	_airside.free()


func test_update_pose_docks_the_bridge_pushes_with_the_tug_and_lets_go() -> void:
	var view := _view_with_large_flight()
	var id := _flight_of(view.sim)
	var entry: Dictionary = _airside.props.bridges[view.gate]
	var mount := entry["node"].find_child("Mount_Door", true, false) as Node3D
	var tug := (view.get_node("Props") as PlaneProps).tug
	# Boarding: the bridge docks on the drawn door; no tug.
	_step(view, view.sim.state_start(id, FlightSim.State.BOARDING) + 10)
	var model := view.get_node("Pivot").get_child(0) as Node3D
	var door: Vector3 = model.global_transform * PlaneModels.PLANES[view.model_name]["doors"][0]
	var off := mount.global_position.distance_to(door)
	print(
		(
			"%s boarding: docked %s, Mount_Door %.4f m off the door"
			% [view.model_name, entry["docked"], off]
		)
	)
	assert_int(view.phase).is_equal(FlightSim.State.BOARDING)
	assert_bool(entry["docked"]).is_true()
	assert_float(off).is_less(TOLERANCE_M)
	assert_bool(tug.is_visible_in_tree()).is_false()
	# Pushback: the bridge parks and the tug rides the nose wheel.
	var mid := (
		(
			view.sim.state_start(id, FlightSim.State.PUSHBACK)
			+ view.sim.state_start(id, FlightSim.State.TAXI_OUT)
		)
		/ 2
	)
	_step(view, mid)
	model = view.get_node("Pivot").get_child(0) as Node3D
	var gear := model.global_transform * PlaneProps.nose_gear_contact(model, view.model_name)
	var on_gear := tug.find_child("Mount_NoseGear", true, false) as Node3D
	var gear_off := on_gear.global_position.distance_to(gear)
	print("pushback: docked %s, tug %.4f m off the nose wheel" % [entry["docked"], gear_off])
	assert_int(view.phase).is_equal(FlightSim.State.PUSHBACK)
	assert_bool(entry["docked"]).is_false()
	assert_bool(tug.is_visible_in_tree()).is_true()
	assert_float(gear_off).is_less(TOLERANCE_M)
	# Back at the stand it docks again; then past the climb-out the view hides.
	_step(view, view.sim.state_start(id, FlightSim.State.BOARDING) + 10)
	assert_bool(entry["docked"]).is_true()
	_step(view, view.sim.state_start(id, FlightSim.State.DEPARTED) + 100000)
	print("hidden: visible %s, docked %s" % [view.visible, entry["docked"]])
	assert_bool(view.visible).is_false()
	assert_bool(entry["docked"]).is_false()
	assert_bool(tug.is_visible_in_tree()).is_false()
	view.free()


func test_a_view_freed_while_docked_parks_its_bridge() -> void:
	var view := _view_with_large_flight()
	var id := _flight_of(view.sim)
	var entry: Dictionary = _airside.props.bridges[view.gate]
	_step(view, view.sim.state_start(id, FlightSim.State.BOARDING) + 10)
	assert_bool(entry["docked"]).is_true()
	view.free()
	print("after free: docked %s" % entry["docked"])
	assert_bool(entry["docked"]).is_false()


## A PlaneView in the tree on the gate of a large Polar Jet contract (model 06
## or 07, both in the bridge's reach) in a sim of its own.
func _view_with_large_flight() -> PlaneView:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.open_airport()
	var terms := {
		"id": "C1",
		"airline": "Polar Jet",
		"destination": "Oslo",
		"departure_minute": TestFlightContracts.bootstrap_minute(),
		"plane_size": PlaneClasses.LARGE,
		"booked_passengers": 90,
		"fee_per_passenger": 25,
	}
	assert_bool(sim.accept_contract(terms)).is_true()
	var view := PlaneView.new()
	view.sim = sim
	view.clock = auto_free(SimClock.new()) as SimClock
	view.airside = _airside
	view.gate = sim.flight_gate(_flight_of(sim))
	add_child(view)
	view.set_process(false)
	assert_str(view.gate).is_equal(FlightSim.DEFAULT_GATE)
	assert_array(["tp_plane_06a", "tp_plane_07a"]).contains([view.model_of(_flight_of(sim))])
	return view


func _flight_of(sim: FlightSim) -> String:
	for id in sim.flight_ids():
		if sim.flight_contract_id(id) == "C1":
			return id
	return ""


## Draws `view` at sim time `time` through update_pose(), as each frame does.
func _step(view: PlaneView, time: int) -> void:
	view.sim.tick = time + 1
	view.update_pose()
