class_name TestAirportGoals
extends GdUnitTestSuite
## Unit and SaveGame v50 round-trip tests for AirportGoals (`game/economy/airport_goals.gd`).

const SEED := 50_202_611

var _save_path := SaveTestKit.run_path("test_airport_goals_save")
var _mains: Array[Node] = []
var _seq := 1000


func after_test() -> void:
	for m in _mains:
		if is_instance_valid(m):
			m.free()
	_mains.clear()
	DirAccess.remove_absolute(_save_path)
	DirAccess.remove_absolute(_save_path + ".tmp")


func _boot_world(seed_val := SEED) -> Node:
	var main := SaveTestKit.boot(self, seed_val)
	_mains.append(main)
	return main


func _emit_departing_made(sim: PassengerSim, count: int) -> void:
	var occ := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	for _i in count:
		_seq += 1
		var dep := Passenger.new()
		dep.id = _seq
		dep.flight_id = occ
		dep.direction = Passenger.Direction.DEPARTING
		dep.stage = Passenger.Stage.MADE
		sim._passengers.append(dep)
		sim._by_id[dep.id] = dep
		sim.outcome.emit(dep.id, true)


func _emit_charter_departed(flights: FlightSim, base_cid: String) -> void:
	_seq += 1
	var cid := "%s%d" % [base_cid, _seq]
	var day := 0
	var charter := (
		FlightContract
		. make(
			{
				"id": cid,
				"airline": OfferBoard.AIRLINES[0],
				"plane_size": PlaneClasses.SMALL,
				"one_off_day": day,
				"first_day": day,
				"traits": {},
			}
		)
	)
	flights._contracts.append(charter)
	var fid := FlightTimetable.occurrence_id(cid, day)
	var starts := {}
	for st: int in FlightSim.State.values():
		starts[st] = 0
	var stand: Dictionary = flights.gate_grounds().get(FlightSim.DEFAULT_GATE, {}).get("stand", {})
	var flight_row := {
		"id": fid,
		"starts": starts,
		"state": FlightSim.State.DEPARTED,
		"gate": FlightSim.DEFAULT_GATE,
		"stand_id": FlightSim.DEFAULT_GATE,
		"contract": cid,
		"day": day,
		"stand": stand,
		"arriving_passengers": 0,
	}
	flights._landed.append(flight_row)
	flights.state_changed.emit(fid, FlightSim.State.DEPARTED)


func _drive_counter_signal(goals: AirportGoals, key: String, need: int, extra: Dictionary) -> void:
	var sim: PassengerSim = extra["sim"]
	var flights: FlightSim = extra["flights"]
	var bag: BaggageSim = extra["bag"]
	var incidents: IncidentDirector = extra["incidents"]
	match key:
		"departing_made":
			_emit_departing_made(sim, need)
		"on_time_flights":
			for _i in need:
				_seq += 1
				var fid := "OT_%d" % _seq
				sim.flight_results[fid] = {"made": 3, "missed": 0, "close_calls": 0, "causes": {}}
				flights.state_changed.emit(fid, FlightSim.State.DEPARTED)
		"cafe_served":
			for _i in need:
				_seq += 1
				sim.cafes.paid.emit(_seq, 1, 10)
		"kiosk_served":
			for _i in need:
				_seq += 1
				sim.shops.paid.emit(_seq, 1, 10)
		"bags_loaded":
			for _i in need:
				_seq += 1
				bag.bag_settled.emit(_seq, 1, "F1", true)
		"charters_departed":
			for _i in need:
				_emit_charter_departed(flights, "GOALCHARTER")
		"incidents_resolved":
			for _i in need:
				_seq += 1
				incidents.ended.emit({"id": _seq, "kind": "spill", "outcome": ""})
		_:
			assert_bool(goals.counter_value(key) >= 0).is_true()


func _complete_goal(goals: AirportGoals, goal_id: String, finances: Finances, extra := {}) -> void:
	var def := AirportGoals.definition(goal_id)
	assert_bool(def.is_empty()).is_false()
	var target := int(def["target"])
	var kind := str(def["kind"])
	match kind:
		"counter":
			var key := str(def["counter"])
			var need := maxi(0, target - goals.counter_value(key))
			_drive_counter_signal(goals, key, need, extra)
		"checkin_desks":
			var grid: BuildGrid = extra["grid"]
			for x in [6, 10]:
				if grid.count_objects(&"checkin_desk") >= target:
					break
				grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(x, 4), 0))
		"staff_hired":
			var staff: StaffSim = extra["staff"]
			while goals._total_hired_staff() < target:
				staff.hire(StaffMember.Role.CLEANER)
		"tier":
			var unlocks: BuildUnlocks = extra["unlocks"]
			(
				unlocks
				. from_snapshot(
					{
						"tier": target,
						"made": int(BuildUnlocks.TIERS[target - 1]["passengers"]),
						"shown": [],
						"seen": [],
						"firsts": [],
					}
				)
			)
		"security_lanes":
			var grid: BuildGrid = extra["grid"]
			for edit in SecurityLaneStamp.edits_for(Vector2i(14, 10), 0):
				grid.apply(edit)
		"extra_land":
			var land: LandPlots = extra["land"]
			var plot := land.buyable_plots()[0]
			assert_bool(land.buy(plot, finances.wallet).ok).is_true()
		"certification":
			var cert: AirportCertification = extra["cert"]
			(
				cert
				. from_save_dict(
					{
						"save_version": AirportCertification.SAVE_VERSION,
						"earned_star": target,
						"medium_departed": 0,
						"large_departed": 0,
					}
				)
			)


func test_catalog_integrity_and_initial_three_slots() -> void:
	var seen := {}
	for entry: Dictionary in AirportGoals.CATALOG:
		var gid := str(entry.get("id", ""))
		var title := str(entry.get("title", ""))
		assert_str(gid).is_not_empty()
		assert_str(title).is_not_empty()
		assert_bool(seen.has(gid)).is_false()
		seen[gid] = true
		assert_int(int(entry.get("target", 0))).is_greater(0)
		assert_int(int(entry.get("reward", 0))).is_greater(0)
		var words := title.split(" ", false)
		assert_int(words.size()).is_between(3, 6)

	var goals: AirportGoals = auto_free(AirportGoals.new())
	add_child(goals)
	var active := goals.active_goals()
	assert_int(active.size()).is_equal(AirportGoals.ACTIVE_SLOTS)
	assert_array(goals.active_ids()).is_equal(["board_10_pax", "on_time_2", "second_checkin"])


func test_departing_made_ignores_arriving_passengers_and_pays_grant() -> void:
	var main := _boot_world()
	var goals := main.get_node("AirportGoals") as AirportGoals
	var sim := main.get_node("PassengerSim") as PassengerSim
	var wallet := (main.get_node("Finances") as Finances).wallet

	var completed: Array[Dictionary] = []
	goals.goal_completed.connect(func(g: Dictionary) -> void: completed.append(g))

	var occ := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	var start_balance := wallet.balance

	# An arriving passenger outcome must NOT increment departing_made.
	var arr := Passenger.new()
	arr.id = 9001
	arr.flight_id = occ
	arr.direction = Passenger.Direction.ARRIVING
	arr.stage = Passenger.Stage.MADE
	sim._passengers.append(arr)
	sim._by_id[arr.id] = arr
	sim.outcome.emit(arr.id, true)
	assert_int(goals.counter_value("departing_made")).is_equal(0)

	# 10 departing MADE passengers complete "board_10_pax" and credit +$250 via GRANT.
	for i in 10:
		var dep := Passenger.new()
		dep.id = 9100 + i
		dep.flight_id = occ
		dep.direction = Passenger.Direction.DEPARTING
		dep.stage = Passenger.Stage.MADE
		sim._passengers.append(dep)
		sim._by_id[dep.id] = dep
		sim.outcome.emit(dep.id, true)

	assert_int(goals.counter_value("departing_made")).is_equal(10)
	assert_bool(goals.is_completed("board_10_pax")).is_true()
	assert_int(wallet.balance).is_equal(start_balance + 250)
	assert_int(completed.size()).is_equal(1)
	assert_str(str(completed[0]["id"])).is_equal("board_10_pax")
	# Slot refilled immediately with "hire_4_staff".
	assert_array(goals.active_ids()).contains(["hire_4_staff"])


func test_hybrid_stateful_evaluation_completes_already_satisfied_goal_on_entry() -> void:
	var main := _boot_world()
	var goals := main.get_node("AirportGoals") as AirportGoals
	var staff := main.get_node("Staff") as StaffSim
	var mode := main.get_node("BuildMode") as BuildMode
	var grid := mode.grid
	var wallet := (main.get_node("Finances") as Finances).wallet
	var start_balance := wallet.balance

	# Pre-hire 4 staff members BEFORE "hire_4_staff" enters an active slot.
	for _i in 4:
		staff.hire(StaffMember.Role.CLEANER)
	assert_bool(goals.active_ids().has("hire_4_staff")).is_false()
	assert_bool(goals.is_completed("hire_4_staff")).is_false()

	# Pre-place 2 check-in desks to complete slot 3 ("second_checkin").
	LandKit.own_all(grid.land)
	for y in range(2, 12):
		for x in range(2, 14):
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(4, 4), 0))
	grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(8, 4), 0))

	# Completing "second_checkin" (+$300) slots "hire_4_staff", which is already satisfied ->
	# completes immediately (+$300) and slots "tier_2"!
	assert_bool(goals.is_completed("second_checkin")).is_true()
	assert_bool(goals.is_completed("hire_4_staff")).is_true()
	assert_array(goals.active_ids()).contains(["tier_2"])
	assert_int(wallet.balance).is_greater_equal(start_balance + 300 + 300)


func test_tier2_gating_on_time_flights_bags_charter_land_cert_and_incidents() -> void:
	var main := _boot_world()
	var goals := main.get_node("AirportGoals") as AirportGoals
	var finances := main.get_node("Finances") as Finances
	var sim := main.get_node("PassengerSim") as PassengerSim
	var flights := main.get_node("FlightSim") as FlightSim
	var bag := main.get_node("BaggageSim") as BaggageSim
	var mode := main.get_node("BuildMode") as BuildMode
	var grid := mode.grid
	var staff := main.get_node("Staff") as StaffSim
	var unlocks := main.get_node("BuildUnlocks") as BuildUnlocks
	var incidents := main.get_node("IncidentDirector") as IncidentDirector
	var cert := (main.get_node("SaveGame") as SaveGame).ensure_certification()
	var land: LandPlots = mode.land_tool.land
	var buy_plot := land.buyable_plots()[0]
	LandKit.own_all(grid.land)
	for y in range(2, 18):
		for x in range(2, 22):
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	var extra := {
		"sim": sim,
		"flights": flights,
		"bag": bag,
		"incidents": incidents,
		"grid": grid,
		"staff": staff,
		"unlocks": unlocks,
		"land": land,
		"cert": cert,
	}
	# Complete Tier 1 goals in order.
	for gid in ["board_10_pax", "on_time_2", "second_checkin", "hire_4_staff", "tier_2"]:
		_complete_goal(goals, gid, finances, extra)
		assert_bool(goals.is_completed(gid)).is_true()

	assert_int(unlocks.tier()).is_greater_equal(2)
	assert_array(goals.active_ids()).contains(["extra_land_1", "serve_4_cafe", "serve_4_kiosk"])

	# Un-own the buyable plot inside open_columns so land.buy() purchases it cleanly.
	land.bought = 0
	land._owned[buy_plot.x + buy_plot.y * land.plots.x] = 0
	for gid in [
		"extra_land_1",
		"serve_4_cafe",
		"serve_4_kiosk",
		"security_lane",
		"bags_6",
		"charter_1",
		"cert_2_star",
		"board_40_pax",
	]:
		_complete_goal(goals, gid, finances, extra)
		assert_bool(goals.is_completed(gid)).is_true()

	# Incidents disabled -> resolve_incident_1 does NOT enter active slots.
	assert_bool(incidents.is_enabled()).is_false()
	assert_array(goals.active_ids()).is_empty()

	# Enable incidents -> resolve_incident_1 enters and NO_PLACE does not count.
	incidents.set_enabled(true)
	goals.evaluate()
	assert_array(goals.active_ids()).is_equal(["resolve_incident_1"])
	incidents.ended.emit({"id": 1, "kind": "spill", "outcome": IncidentSnapshot.NO_PLACE})
	assert_bool(goals.is_completed("resolve_incident_1")).is_false()
	incidents.ended.emit({"id": 2, "kind": "spill", "outcome": ""})
	assert_bool(goals.is_completed("resolve_incident_1")).is_true()
	assert_array(goals.active_ids()).is_empty()


func test_on_time_flights_bags_and_charter_signals() -> void:
	var main := _boot_world()
	var goals := main.get_node("AirportGoals") as AirportGoals
	var sim := main.get_node("PassengerSim") as PassengerSim
	var flights := main.get_node("FlightSim") as FlightSim
	var bag := main.get_node("BaggageSim") as BaggageSim

	# Flight with 1 miss does NOT count as on-time.
	sim.flight_results["F_MISS"] = {"made": 3, "missed": 1, "close_calls": 0, "causes": {}}
	flights.state_changed.emit("F_MISS", FlightSim.State.DEPARTED)
	assert_int(goals.counter_value("on_time_flights")).is_equal(0)

	# Flight with 0 misses and made > 0 counts; non-charter does NOT count as charter.
	sim.flight_results["F_OK"] = {"made": 4, "missed": 0, "close_calls": 0, "causes": {}}
	flights.state_changed.emit("F_OK", FlightSim.State.DEPARTED)
	assert_int(goals.counter_value("on_time_flights")).is_equal(1)
	assert_int(goals.counter_value("charters_departed")).is_equal(0)

	# Real charter flight departure increments charters_departed.
	_emit_charter_departed(flights, "CHARTERSIG")
	assert_int(goals.counter_value("charters_departed")).is_equal(1)

	# Real CafeSim and ShopSim paid signals increment counters.
	sim.cafes.paid.emit(1, 1, 15)
	assert_int(goals.counter_value("cafe_served")).is_equal(1)
	sim.shops.paid.emit(2, 1, 20)
	assert_int(goals.counter_value("kiosk_served")).is_equal(1)

	# Missed bag does NOT count; loaded bag counts.
	bag.bag_settled.emit(1, 1, "F_OK", false)
	assert_int(goals.counter_value("bags_loaded")).is_equal(0)
	bag.bag_settled.emit(2, 1, "F_OK", true)
	assert_int(goals.counter_value("bags_loaded")).is_equal(1)


func test_incidents_vip_and_inspector_resolutions_and_grant_without_rating_change() -> void:
	var main := _boot_world()
	var goals := main.get_node("AirportGoals") as AirportGoals
	var incidents := main.get_node("IncidentDirector") as IncidentDirector
	var wallet := (main.get_node("Finances") as Finances).wallet
	var rating := main.get_node("AirportRating") as AirportRating

	incidents.set_enabled(true)
	var seeded := {
		"save_version": AirportGoals.SAVE_VERSION,
		"active_ids": ["resolve_incident_1"],
		"completed_ids": [],
		"counters": AirportGoals._empty_counters(),
	}
	assert_bool(goals.from_snapshot(seeded)).is_true()
	assert_array(rating.active_adjustments()).is_empty()

	var grant_txs: Array[int] = []
	wallet.transaction.connect(
		func(amount: int, category: int, _claimed: Dictionary, _tick: int) -> void:
			if category == Wallet.Category.GRANT:
				grant_txs.append(amount)
	)

	var insp_plan := {
		"window_from": 0,
		"window_to": 100,
		"pass_money": 200,
		"max_messes": 2,
		"max_full_queue": 0,
		"fail_half_stars": 1,
		"seen_messes": 3,
		"seen_full_queue": 0,
	}
	var vip_plan := {"departs": 100, "bonus": 200, "good_mood": 80, "miss_half_stars": 1}

	# Failed inspection and penalized VIP must NOT increment or complete resolve_incident_1.
	(
		incidents
		. inspector_resolved
		. emit(
			{
				"id": 10,
				"kind": IncidentCatalogue.INSPECTOR,
				"outcome": IncidentMajors.FAILED,
				"fire_tick": 0,
				"plan": insp_plan,
			}
		)
	)
	(
		incidents
		. vip_resolved
		. emit(
			{
				"id": 11,
				"kind": IncidentCatalogue.VIP,
				"outcome": IncidentMajors.PENALTY,
				"fire_tick": 0,
				"plan": vip_plan,
			}
		)
	)
	# Major incident emitted through ended() must also be ignored (never double-count).
	(
		incidents
		. ended
		. emit(
			{
				"id": 12,
				"kind": IncidentCatalogue.INSPECTOR,
				"outcome": IncidentMajors.PASSED,
				"fire_tick": 0,
				"plan": insp_plan,
			}
		)
	)
	assert_int(goals.counter_value("incidents_resolved")).is_equal(0)
	assert_bool(goals.is_completed("resolve_incident_1")).is_false()
	assert_array(grant_txs).is_empty()

	# Passed inspection completes resolve_incident_1 and credits +$400 via GRANT only.
	(
		incidents
		. inspector_resolved
		. emit(
			{
				"id": 12,
				"kind": IncidentCatalogue.INSPECTOR,
				"outcome": IncidentMajors.PASSED,
				"fire_tick": 0,
				"plan": insp_plan,
			}
		)
	)
	assert_int(goals.counter_value("incidents_resolved")).is_equal(1)
	assert_bool(goals.is_completed("resolve_incident_1")).is_true()
	assert_array(grant_txs).is_equal([400])
	assert_array(rating.active_adjustments()).is_empty()

	# Re-emitting the same incident id never double-counts.
	(
		incidents
		. inspector_resolved
		. emit(
			{
				"id": 12,
				"kind": IncidentCatalogue.INSPECTOR,
				"outcome": IncidentMajors.PASSED,
				"fire_tick": 0,
				"plan": insp_plan,
			}
		)
	)
	assert_int(goals.counter_value("incidents_resolved")).is_equal(1)

	# Positive VIP resolutions (bonus and neutral) both count.
	(
		incidents
		. vip_resolved
		. emit(
			{
				"id": 13,
				"kind": IncidentCatalogue.VIP,
				"outcome": IncidentMajors.BONUS,
				"fire_tick": 0,
				"plan": vip_plan,
			}
		)
	)
	(
		incidents
		. vip_resolved
		. emit(
			{
				"id": 14,
				"kind": IncidentCatalogue.VIP,
				"outcome": IncidentMajors.NEUTRAL,
				"fire_tick": 0,
				"plan": vip_plan,
			}
		)
	)
	assert_int(goals.counter_value("incidents_resolved")).is_equal(3)
	assert_array(rating.active_adjustments()).is_empty()


func test_snapshot_validation_and_save_game_v50_load_suppresses_payouts() -> void:
	# Validation errors on malformed snapshots.
	assert_str(AirportGoals.validation_problem([])).is_not_empty()
	assert_str(AirportGoals.validation_problem({})).is_not_empty()
	var valid := {
		"save_version": AirportGoals.SAVE_VERSION,
		"active_ids": ["on_time_2", "second_checkin"],
		"completed_ids": ["board_10_pax"],
		"counters":
		{
			"departing_made": 10,
			"on_time_flights": 1,
			"cafe_served": 0,
			"kiosk_served": 0,
			"bags_loaded": 0,
			"charters_departed": 0,
			"incidents_resolved": 0,
		},
	}
	assert_str(AirportGoals.validation_problem(valid)).is_empty()

	var bad_ver := valid.duplicate(true)
	bad_ver["save_version"] = 99
	assert_str(AirportGoals.validation_problem(bad_ver)).is_not_empty()

	var bad_overlap := valid.duplicate(true)
	bad_overlap["active_ids"] = ["board_10_pax"]
	assert_str(AirportGoals.validation_problem(bad_overlap)).is_not_empty()

	var bad_unknown := valid.duplicate(true)
	bad_unknown["active_ids"] = ["not_a_goal"]
	assert_str(AirportGoals.validation_problem(bad_unknown)).is_not_empty()

	var bad_counter := valid.duplicate(true)
	bad_counter["counters"]["departing_made"] = -1
	assert_str(AirportGoals.validation_problem(bad_counter)).is_not_empty()

	# SaveGame v50 round-trip + loading suppression check.
	assert_int(SaveGame.SAVE_VERSION).is_equal(50)
	var src := _boot_world(SEED)
	var src_goals := src.get_node("AirportGoals") as AirportGoals
	var src_save := src.get_node("SaveGame") as SaveGame
	for _i in 10:
		src_goals._increment_counter("departing_made")
	assert_bool(src_goals.is_completed("board_10_pax")).is_true()
	var saved_balance := (src.get_node("Finances") as Finances).wallet.balance
	assert_bool(src_save.save_to_file(_save_path)).is_true()

	var dst := _boot_world(SEED + 1)
	var dst_goals := dst.get_node("AirportGoals") as AirportGoals
	var dst_save := dst.get_node("SaveGame") as SaveGame
	var load_emissions: Array[Dictionary] = []
	dst_goals.goal_completed.connect(func(g: Dictionary) -> void: load_emissions.append(g))

	assert_bool(dst_save.load_from_file(_save_path)).is_true()
	assert_int(load_emissions.size()).is_equal(0)
	assert_int((dst.get_node("Finances") as Finances).wallet.balance).is_equal(saved_balance)
	assert_bool(dst_goals.is_completed("board_10_pax")).is_true()
	assert_int(dst_goals.counter_value("departing_made")).is_equal(10)
	assert_array(dst_goals.active_ids()).is_equal(src_goals.active_ids())

	# v49 save is refused.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_save_path))
	assert_int(int(raw["save_version"])).is_equal(50)
	raw["save_version"] = 49
	assert_bool(dst_save.load_world(raw)).is_false()
