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


func test_small_flight_folds_bridge_hides_tug_and_self_taxis_forward() -> void:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.open_airport()
	var terms := {
		"id": "C2",
		"airline": "Gotta Air",
		"destination": "Bergen",
		"departure_minute": TestFlightContracts.bootstrap_minute() + 3,
		"plane_size": PlaneClasses.SMALL,
		"booked_passengers": 6,
		"fee_per_passenger": 50,
	}
	assert_bool(sim.accept_contract(terms)).is_true()
	var id := ""
	for flight in sim.flight_ids():
		if sim.flight_contract_id(flight) == "C2":
			id = flight
	assert_str(id).is_not_empty()
	var view := PlaneView.new()
	view.sim = sim
	view.clock = auto_free(SimClock.new()) as SimClock
	view.airside = _airside
	view.gate = sim.flight_gate(id)
	add_child(view)
	view.set_process(false)
	var entry: Dictionary = _airside.props.bridges[view.gate]
	var tug := (view.get_node("Props") as PlaneProps).tug
	var push_start := sim.state_start(id, FlightSim.State.PUSHBACK)
	var push_end := sim.state_start(id, FlightSim.State.TAXI_OUT)
	_step(view, sim.state_start(id, FlightSim.State.BOARDING) + 10)
	assert_str(view.model_name).is_equal("tp_plane_03a")
	assert_bool(entry["folded"]).is_true()
	assert_bool(entry["docked"]).is_false()
	assert_bool(tug.is_visible_in_tree()).is_false()
	# Mid-turn in PUSHBACK: stays on stand_point, turns west away from bridge, zero tug.
	var turn_mid := push_start + int((push_end - push_start) * FlightPose.SELF_TAXI_TURN_END * 0.5)
	_step(view, turn_mid)
	var stand_pos := StandPlacement.stand_point(STAND)
	assert_int(view.phase).is_equal(FlightSim.State.PUSHBACK)
	assert_bool(tug.is_visible_in_tree()).is_false()
	var flat_dist := Vector2(view.position.x - stand_pos.x, view.position.z - stand_pos.z).length()
	assert_float(flat_dist).is_less(0.01)
	assert_float(view.transform.basis.z.dot(Vector3.LEFT)).is_greater(0.99)
	# Roll-out in PUSHBACK: faces north (forward) and moves north toward pushback_end.
	var roll_mid := push_start + int((push_end - push_start) * 0.75)
	_step(view, roll_mid)
	assert_bool(tug.is_visible_in_tree()).is_false()
	assert_float(view.transform.basis.z.dot(Vector3.FORWARD)).is_greater(0.999)
	assert_float(view.position.z).is_less(stand_pos.z - 5.0)
	view.free()


func test_small_flight_propeller_spins_on_hub_when_powered_and_stops_at_gate() -> void:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.open_airport()
	var terms := {
		"id": "C2",
		"airline": "Gotta Air",
		"destination": "Bergen",
		"departure_minute": TestFlightContracts.bootstrap_minute() + 3,
		"plane_size": PlaneClasses.SMALL,
		"booked_passengers": 6,
		"fee_per_passenger": 50,
	}
	assert_bool(sim.accept_contract(terms)).is_true()
	var id := ""
	for flight in sim.flight_ids():
		if sim.flight_contract_id(flight) == "C2":
			id = flight
	assert_str(id).is_not_empty()
	var view := PlaneView.new()
	view.sim = sim
	view.clock = auto_free(SimClock.new()) as SimClock
	view.airside = _airside
	view.gate = sim.flight_gate(id)
	add_child(view)
	view.set_process(false)
	var stand_pos := StandPlacement.stand_point(STAND)
	# Stopped at the stand (AT_STAND, BOARDING, DOORS_CLOSED): 0 delta across ticks + fraction.
	for gate_state in [
		FlightSim.State.AT_STAND, FlightSim.State.BOARDING, FlightSim.State.DOORS_CLOSED
	]:
		var gate_tick := sim.state_start(id, gate_state) + 2
		view.clock.alpha = 0.0
		_step(view, gate_tick)
		var model := view.get_node("Pivot").get_child(0) as Node3D
		var prop := model.find_child(PlaneView.PROPELLER_NODE, true, false) as Node3D
		assert_object(prop).is_not_null()
		var basis_a := prop.basis
		view.clock.alpha = 0.65
		_step(view, gate_tick + 3)
		assert_int(view.phase).is_equal(gate_state)
		assert_bool(prop.basis.is_equal_approx(basis_a)).is_true()
	# Powered in PUSHBACK t in [0.0, 0.4] while staying on stand_point: pure hub spin, no wobble.
	var push_start := sim.state_start(id, FlightSim.State.PUSHBACK)
	var push_end := sim.state_start(id, FlightSim.State.TAXI_OUT)
	var turn_a := push_start + int((push_end - push_start) * 0.15)
	view.clock.alpha = 0.10
	_step(view, turn_a)
	var model := view.get_node("Pivot").get_child(0) as Node3D
	var prop := model.find_child(PlaneView.PROPELLER_NODE, true, false) as Node3D
	var sil := view.get_node("FarShadow").get_child(0) as Node3D
	var sil_prop := sil.find_child(PlaneView.PROPELLER_NODE, true, false) as Node3D
	var hub_local := prop.position
	var hub_rel_a := (model.global_transform.affine_inverse() * prop.global_transform).origin
	var basis_turn_a := prop.basis
	var flat_a := Vector2(view.position.x - stand_pos.x, view.position.z - stand_pos.z).length()
	assert_float(flat_a).is_less(0.01)
	var turn_b := turn_a + 1
	view.clock.alpha = 0.60
	_step(view, turn_b)
	var hub_rel_b := (model.global_transform.affine_inverse() * prop.global_transform).origin
	var flat_b := Vector2(view.position.x - stand_pos.x, view.position.z - stand_pos.z).length()
	var spin_angle := basis_turn_a.x.angle_to(prop.basis.x)
	assert_int(view.phase).is_equal(FlightSim.State.PUSHBACK)
	assert_float(flat_b).is_less(0.01)
	assert_vector(prop.position).is_equal_approx(hub_local, Vector3.ONE * 1e-6)
	assert_vector(hub_rel_b).is_equal_approx(hub_rel_a, Vector3.ONE * 2e-4)
	assert_float(prop.basis.y.dot(Vector3.BACK)).is_greater(0.9999)
	assert_float(spin_angle).is_greater(0.5)
	assert_bool(sil_prop.basis.is_equal_approx(prop.basis)).is_true()
	# Other engine-powered phases spin across a tick + fraction advance.
	for powered_state in [
		FlightSim.State.APPROACH,
		FlightSim.State.LANDING,
		FlightSim.State.TAXI_IN,
		FlightSim.State.TAXI_OUT,
		FlightSim.State.TAKEOFF,
	]:
		var t0 := sim.state_start(id, powered_state) + 1
		view.clock.alpha = 0.10
		_step(view, t0)
		var b0 := prop.basis
		view.clock.alpha = 0.60
		_step(view, t0 + 1)
		assert_int(view.phase).is_equal(powered_state)
		assert_float(b0.x.angle_to(prop.basis.x)).is_greater(0.5)
	view.free()


## A PlaneView in the tree on the gate of a large Polar Jet contract (model 06
## or 07, both in the bridge's reach) in a sim of its own.
func _view_with_large_flight() -> PlaneView:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.open_airport()
	var terms := {
		"id": "C1",
		"airline": "Polar Jet",
		"destination": "Oslo",
		"departure_minute": TestFlightContracts.bootstrap_minute() + 3,
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
