class_name TestPlaneViewRotors
extends GdUnitTestSuite
## Regression test for PlaneView rotor and turbofan animation across tp_plane_03a
## through tp_plane_07a: spins all matched blades when powered and freezes them
## at the gate or during tug pushback.

const Kit := preload("res://tests/airside/airside_props_kit.gd")
const STAND := {"exit": 4, "x": 21.5, "wall_z": -98.0}

var _airside: Airside


func before() -> void:
	_airside = Kit.airside_from_main()
	add_child(_airside)
	assert_bool(_airside.set_gate_stands({FlightSim.DEFAULT_GATE: STAND})).is_true()


func after() -> void:
	_airside.free()


func test_plane_04a_rotors_and_jet_fans_spin_when_powered_and_stop_at_gate() -> void:
	var expectations := {
		"tp_plane_03a": [PlaneClasses.SMALL, "Gotta Air", 1],
		"tp_plane_04a": [PlaneClasses.MEDIUM, "Meridian Air", 2],
		"tp_plane_05a": [PlaneClasses.MEDIUM, "Nordic Wing", 2],
		"tp_plane_06a": [PlaneClasses.LARGE, "Meridian Air", 3],
		"tp_plane_07a": [PlaneClasses.LARGE, "Nordic Wing", 2],
	}
	for model: String in expectations:
		var spec: Array = expectations[model]
		assert_str(PlaneClasses.model_for(spec[1], spec[0])).is_equal(model)
		var sim := auto_free(FlightSim.new()) as FlightSim
		sim.open_airport()
		var contract_id := "C" + model.substr(9, 2)
		var terms := {
			"id": contract_id,
			"airline": spec[1],
			"destination": "Oslo",
			"departure_minute": TestFlightContracts.bootstrap_minute(),
			"plane_size": spec[0],
			"booked_passengers": PlaneClasses.passenger_range(spec[0])[0],
			"fee_per_passenger": 20,
		}
		assert_bool(sim.accept_contract(terms)).is_true()
		var fid := ""
		for flight in sim.flight_ids():
			if sim.flight_contract_id(flight) == contract_id:
				fid = flight
		assert_str(fid).is_not_empty()
		var view := PlaneView.new()
		view.sim = sim
		view.clock = auto_free(SimClock.new()) as SimClock
		view.airside = _airside
		view.gate = sim.flight_gate(fid)
		add_child(view)
		view.set_process(false)
		assert_str(view.model_of(fid)).is_equal(model)
		# At gate (BOARDING): stationary across tick + alpha advance.
		var t_board := sim.state_start(fid, FlightSim.State.BOARDING) + 2
		view.sim.tick = t_board + 1
		view.clock.alpha = 0.0
		view.update_pose()
		assert_str(view.model_name).is_equal(model)
		assert_int(view._rotors.size()).is_equal(spec[2])
		var bases_gate: Array[Basis] = []
		for r in view._rotors:
			bases_gate.append((r["node"] as Node3D).basis)
		view.sim.tick = t_board + 3
		view.clock.alpha = 0.5
		view.update_pose()
		for i in view._rotors.size():
			(
				assert_bool(
					(view._rotors[i]["node"] as Node3D).basis.is_equal_approx(bases_gate[i])
				)
				. is_true()
			)
		# Powered in TAXI_OUT: every rotor/fan spins around hub without shifting origin.
		var t_taxi := sim.state_start(fid, FlightSim.State.TAXI_OUT) + 1
		view.sim.tick = t_taxi + 1
		view.clock.alpha = 0.1
		view.update_pose()
		var bases_a: Array[Basis] = []
		var pos_a: Array[Vector3] = []
		for r in view._rotors:
			var nd := r["node"] as Node3D
			bases_a.append(nd.basis)
			pos_a.append(nd.position)
		view.sim.tick = t_taxi + 2
		view.clock.alpha = 0.6
		view.update_pose()
		for i in view._rotors.size():
			var nd := view._rotors[i]["node"] as Node3D
			var sil := view._rotors[i]["silhouette"] as Node3D
			assert_vector(nd.position).is_equal_approx(pos_a[i], Vector3.ONE * 1e-5)
			assert_float(bases_a[i].x.angle_to(nd.basis.x)).is_greater(0.5)
			assert_bool(sil.basis.is_equal_approx(nd.basis)).is_true()
		# Non-self-taxiing planes stop rotors during tug PUSHBACK.
		if not PlaneClasses.self_taxis(model):
			var t_push := sim.state_start(fid, FlightSim.State.PUSHBACK) + 1
			view.sim.tick = t_push + 1
			view.clock.alpha = 0.0
			view.update_pose()
			var b_push := (view._rotors[0]["node"] as Node3D).basis
			view.sim.tick = t_push + 3
			view.clock.alpha = 0.5
			view.update_pose()
			assert_bool((view._rotors[0]["node"] as Node3D).basis.is_equal_approx(b_push)).is_true()
		view.free()
