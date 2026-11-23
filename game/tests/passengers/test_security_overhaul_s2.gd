class_name TestSecurityOverhaulS2
extends GdUnitTestSuite
## Regression suite for Security Overhaul Slice S2 (1cff7458, user ruling
## a0247eca, Astra technical contract 802db2ea):
## (a) fast_track bool persisted on security_arch in BuildGridSave + SaveGame
##     v34 with strict boolean validation, independent of closed state
## (b) BuiltItemCard Fast-Track toggle on ANY piece of a complete lane (arch,
##     tray, xray, pickup, attached search_table/confiscation_bin) + BuildView
##     in-world arch badge shown/freed cleanly
## (c) Preferential routing with safe overflow in BOTH PassengerStations and
##     SecurityForecast + cozy mood/thought payoff on Fast-Track clearance
## (d) 1-click Complete Security Lane stamp derived from SecurityLanes.geometry()
##     at all 4 facings, atomic validation & combined charge, BuildUnlocks gating,
##     ghost preview, and 1-step Ctrl+Z undo.

const GRID_SIZE := Vector2i(24, 16)
const ARCH_A := Vector2i(6, 7)
const ARCH_B := Vector2i(14, 7)

var _worlds: Array[PassengerTestWorld] = []
var _nodes: Array[Node] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	PseudoLocale.disable()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	for w in _worlds:
		w.free_all()
	_worlds.clear()


func _two_lane_world() -> Dictionary:
	var grid := PassengerTestWorld.floored(GRID_SIZE)
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(2, 12), 0)
	var entrance := PassengerTestWorld.place(grid, &"entrance_door", Vector2i(2, 15), 2)
	var exit_door := PassengerTestWorld.place(grid, &"exit_door", Vector2i(10, 0), 0)
	var arch_a := _place_lane_parts(grid, ARCH_A, 0)
	var arch_b := _place_lane_parts(grid, ARCH_B, 0)
	EnclosureKit.close_floor(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 101)
	_worlds.append(world)
	world.auto_staff = true
	for station in [desk, arch_a, arch_b]:
		StaffTestKit.seat(world.staff, station, StaffMember.Slot.PRIMARY)
	return {
		"world": world,
		"desk": desk,
		"entrance": entrance,
		"exit": exit_door,
		"arch_a": arch_a,
		"arch_b": arch_b,
	}


func _place_lane_parts(grid: BuildGrid, anchor: Vector2i, facing: int) -> int:
	var edits := SecurityLaneStamp.edits_for(anchor, facing)
	var arch_id := 0
	for edit in edits:
		var res := grid.apply(edit)
		assert_bool(res.ok).is_true()
		if edit.def_id == SecurityLanes.ARCH:
			arch_id = res.object_id
	return arch_id


func _make_card(world: PassengerTestWorld) -> Dictionary:
	var sel := BuiltSelection.new()
	var bm := BuildMode.new()
	bm.set_process(false)
	add_child(bm)
	_nodes.append(bm)
	var card := BuiltItemCard.new()
	card.sim = world.sim
	card.selection = sel
	card.build_mode = bm
	add_child(card)
	_nodes.append(card)
	return {"sel": sel, "card": card}


func _make_stamp_mode(starting_cash := 50000) -> Dictionary:
	var finances := Finances.new()
	finances.wallet.balance = starting_cash
	add_child(finances)
	_nodes.append(finances)
	var port := SubViewport.new()
	port.size = Vector2i(1280, 720)
	add_child(port)
	_nodes.append(port)
	var cam := Camera3D.new()
	port.add_child(cam)
	cam.look_at_from_position(Vector3(0, 12, 10), Vector3.ZERO, Vector3.UP)
	var mode := BuildMode.new()
	mode.grid_size = Vector2i(20, 20)
	mode.finances = finances
	port.add_child(mode)
	mode.set_process(false)
	for y in range(2, 18):
		for x in range(2, 18):
			mode.grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	return {"mode": mode, "finances": finances, "port": port}


func test_fast_track_persists_through_save_rejects_invalid_and_keeps_closed_independent() -> void:
	var ctx := _two_lane_world()
	var w: PassengerTestWorld = ctx["world"]
	var arch_a: int = ctx["arch_a"]
	var arch_b: int = ctx["arch_b"]

	assert_int(BuildGridSave.SAVE_VERSION).is_greater_equal(2)
	assert_int(SaveGame.SAVE_VERSION).is_greater_equal(34)
	assert_int(PassengerSim.SAVE_VERSION).is_greater_equal(39)

	assert_bool(w.grid.is_object_fast_track(arch_a)).is_false()
	assert_bool(w.grid.set_object_fast_track(arch_b, true)).is_true()
	assert_bool(w.grid.is_object_fast_track(arch_b)).is_true()
	assert_bool(w.sim.layout.security_lanes.is_fast_track(arch_b)).is_true()

	# Non-arch object refuses set_object_fast_track.
	assert_bool(w.grid.set_object_fast_track(ctx["desk"], true)).is_false()

	# Closing a Fast-Track lane keeps its fast_track flag when reopened.
	w.staff.closures.set_closed(arch_b, true)
	assert_bool(w.staff.is_open(arch_b)).is_false()
	assert_bool(w.grid.is_object_fast_track(arch_b)).is_true()
	w.staff.closures.set_closed(arch_b, false)
	assert_bool(w.staff.is_open(arch_b)).is_true()
	assert_bool(w.grid.is_object_fast_track(arch_b)).is_true()

	# Grid snapshot round-trip through JSON preserves fast_track + VIP field on Passenger.
	var p := w.sim.get_passenger(w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.vip = true
	var grid_snap: Dictionary = JSON.parse_string(JSON.stringify(w.grid.to_snapshot()))
	var sim_snap: Dictionary = JSON.parse_string(JSON.stringify(w.sim.to_snapshot()))
	var loaded_grid := BuildGrid.new()
	assert_bool(loaded_grid.from_snapshot(grid_snap)).is_true()
	assert_bool(loaded_grid.is_object_fast_track(arch_a)).is_false()
	assert_bool(loaded_grid.is_object_fast_track(arch_b)).is_true()
	assert_bool(loaded_grid.recognised_lanes().is_fast_track(arch_b)).is_true()

	var loaded_sim := PassengerSim.new()
	add_child(loaded_sim)
	_nodes.append(loaded_sim)
	loaded_sim.bind(w.clock, w.flights, loaded_grid)
	assert_bool(loaded_sim.from_snapshot(sim_snap)).is_true()
	assert_bool(loaded_sim.get_passenger(p.id).vip).is_true()

	# Strict boolean validation on BuildGridSnapshot rejects non-bool or non-arch fast_track.
	var bad_type: Dictionary = grid_snap.duplicate(true)
	for entry: Dictionary in bad_type["objects"]:
		if int(entry["id"]) == arch_b:
			entry["fast_track"] = "yes"
	assert_str(BuildGridSnapshot.problem(bad_type)).contains("fast_track")
	assert_bool(BuildGrid.new().from_snapshot(bad_type)).is_false()

	var bad_non_arch: Dictionary = grid_snap.duplicate(true)
	for entry: Dictionary in bad_non_arch["objects"]:
		if int(entry["id"]) == ctx["desk"]:
			entry["fast_track"] = true
	assert_str(BuildGridSnapshot.problem(bad_non_arch)).contains("security_arch")
	assert_bool(BuildGrid.new().from_snapshot(bad_non_arch)).is_false()


func test_built_item_card_toggles_from_any_lane_piece_and_syncs_arch_badge() -> void:
	var ctx := _two_lane_world()
	var w: PassengerTestWorld = ctx["world"]
	var arch_a: int = ctx["arch_a"]
	var geom := SecurityLanes.geometry(ARCH_A, 0, SecurityLanes.RIGHT)
	var st_id := PassengerTestWorld.place(
		w.grid, SecurityLanes.SEARCH_TABLE, geom["search_table_cell"], 0
	)
	var bin_id := PassengerTestWorld.place(
		w.grid, SecurityLanes.CONFISCATION_BIN, geom["confiscation_bin_cell"], 0
	)
	var loose_st := PassengerTestWorld.place(w.grid, SecurityLanes.SEARCH_TABLE, Vector2i(2, 2), 0)

	var view := BuildView.new()
	add_child(view)
	_nodes.append(view)
	view.refresh(w.grid)
	view.sync_security(w.sim, 0.0)
	var arch_node := view.object_node(arch_a)
	assert_object(arch_node.get_node_or_null("FastTrackBadge")).is_null()

	var ui := _make_card(w)
	var sel: BuiltSelection = ui["sel"]
	var card: BuiltItemCard = ui["card"]

	# Loose unattached piece hides Fast-Track toggle.
	sel.select_object(loose_st)
	card.refresh()
	assert_bool(card.fast_track_button().visible).is_false()

	# Every piece of the complete lane resolves to the owning arch and toggles fast_track.
	var lane_dict := w.sim.layout.security_lanes.lane(arch_a)
	var pieces: Array[int] = [
		arch_a,
		lane_dict["parts"][SecurityLanes.TRAY_TABLE],
		lane_dict["parts"][SecurityLanes.XRAY_BELT],
		lane_dict["parts"][SecurityLanes.PICKUP_TABLE],
		st_id,
		bin_id,
	]
	var expected := false
	for obj_id in pieces:
		sel.select_object(obj_id)
		card.refresh()
		assert_bool(card.fast_track_button().visible).is_true()
		expected = not expected
		assert_bool(card.press_fast_track()).is_true()
		assert_bool(w.grid.is_object_fast_track(arch_a)).is_equal(expected)
		view.refresh(w.grid)
		view.sync_security(w.sim, 0.0)
		var badge := view.object_node(arch_a).get_node_or_null("FastTrackBadge")
		if expected:
			assert_object(badge).is_not_null()
		else:
			assert_object(badge).is_null()


func test_preferential_routing_safe_overflow_forecast_parity_and_cozy_thought() -> void:
	var ctx := _two_lane_world()
	var w: PassengerTestWorld = ctx["world"]
	var arch_a: int = ctx["arch_a"]
	var arch_b: int = ctx["arch_b"]
	w.grid.set_object_fast_track(arch_b, true)

	# Stack 2 standard passengers into lane B's queue? Wait: put 2 passengers in lane A?
	# Even simpler: lane A is Standard at x=6 (closer to check-in at x=2), lane B is Fast-Track
	# at x=14 (farther). Let's test BOTH directions!
	# 1) Priority passengers (late or VIP) choose Fast-Track lane B over closer Standard lane A.
	var late_p := w.sim.get_passenger(w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	late_p.at = Vector2i(4, 10)
	late_p.stage = Passenger.Stage.TO_SECURITY
	late_p.late = true
	PassengerStations.choose(w.sim, late_p)
	assert_int(late_p.station).is_equal(arch_b)

	var vip_p := w.sim.get_passenger(w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	vip_p.at = Vector2i(4, 10)
	vip_p.stage = Passenger.Stage.TO_SECURITY
	vip_p.vip = true
	PassengerStations.choose(w.sim, vip_p)
	assert_int(vip_p.station).is_equal(arch_b)

	# 2) Standard passenger chooses Standard lane A even if Fast-Track lane B is closer and empty.
	var norm_p := w.sim.get_passenger(w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	norm_p.at = Vector2i(14, 10)
	norm_p.stage = Passenger.Stage.TO_SECURITY
	PassengerStations.choose(w.sim, norm_p)
	assert_int(norm_p.station).is_equal(arch_a)

	# 3) Forecast parity: waiting candidate in SecurityForecast picks matching tier.
	var wait_vip := w.sim.get_passenger(w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	wait_vip.at = Vector2i(4, 10)
	wait_vip.stage = Passenger.Stage.TO_SECURITY
	wait_vip.station = 0
	wait_vip.vip = true
	wait_vip.stuck = Passenger.Stuck.NONE
	var eta_ft := SecurityForecast.clearance(w.sim, arch_b, wait_vip, w.clock.tick + 1)
	var eta_std := SecurityForecast.clearance(w.sim, arch_a, wait_vip, w.clock.tick + 1)
	assert_int(eta_ft).is_less(JourneyForecast.NEVER)
	assert_int(eta_std).is_less(JourneyForecast.NEVER)
	# JourneyForecast._soonest_scanner picks Fast-Track arch_b for VIP despite farther walk.
	var chosen_by_forecast := JourneyForecast._soonest_scanner(
		w.sim, Vector2i(4, 10), wait_vip, true
	)
	assert_int(chosen_by_forecast.y).is_equal(arch_b)
	# And for a standard flyer right by Fast-Track arch_b, forecast still picks Standard arch_a.
	var wait_std := w.sim.get_passenger(w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	wait_std.at = Vector2i(14, 10)
	wait_std.stage = Passenger.Stage.TO_SECURITY
	wait_std.station = 0
	var std_forecast := JourneyForecast._soonest_scanner(w.sim, Vector2i(14, 10), wait_std, true)
	assert_int(std_forecast.y).is_equal(arch_a)

	# 4) Safe overflow: if ALL open lanes are Fast-Track, standard flyer safely overflows.
	w.grid.set_object_fast_track(arch_a, true)
	var overflow_std := w.sim.get_passenger(w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	overflow_std.at = Vector2i(6, 10)
	overflow_std.stage = Passenger.Stage.TO_SECURITY
	PassengerStations.choose(w.sim, overflow_std)
	assert_bool(overflow_std.station == arch_a or overflow_std.station == arch_b).is_true()

	# 5) Safe overflow: if ALL open lanes are Standard, priority flyer uses Standard.
	w.grid.set_object_fast_track(arch_a, false)
	w.grid.set_object_fast_track(arch_b, false)
	var overflow_vip := w.sim.get_passenger(w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	overflow_vip.at = Vector2i(6, 10)
	overflow_vip.stage = Passenger.Stage.TO_SECURITY
	overflow_vip.vip = true
	PassengerStations.choose(w.sim, overflow_vip)
	assert_bool(overflow_vip.station == arch_a or overflow_vip.station == arch_b).is_true()

	# 6) Cozy payoff: priority flyer clearing Fast-Track receives mood boost and FAST_TRACK thought.
	w.grid.set_object_fast_track(arch_b, true)
	var cozy_vip := w.sim.get_passenger(w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	cozy_vip.vip = true
	cozy_vip.carry_on = 0
	cozy_vip.liquids = false
	cozy_vip.alarm = false
	cozy_vip.at = Vector2i(14, 10)
	cozy_vip.stage = Passenger.Stage.TO_SECURITY
	var mood_before := cozy_vip.mood
	for _i in 600:
		w.step()
		if cozy_vip.cleared:
			break
	assert_bool(cozy_vip.cleared).is_true()
	assert_int(cozy_vip.mood).is_greater_equal(mood_before)
	var has_ft_thought := false
	for entry in PassengerThoughts.entries(cozy_vip):
		if entry["kind"] == PassengerThoughts.Kind.FAST_TRACK:
			has_ft_thought = true
			assert_bool(entry["positive"]).is_true()
			assert_str(entry["text"]).contains("Fast-Track")
	assert_bool(has_ft_thought).is_true()


func test_one_click_security_lane_stamp_places_all_facings_atomically_and_undoes() -> void:
	var ctx := _make_stamp_mode(50000)
	var mode: BuildMode = ctx["mode"]
	var finances: Finances = ctx["finances"]

	# Expected combined price equals sum of all 4 PART_IDS.
	var expected_price := 0
	for def_id: StringName in SecurityLanes.PART_IDS:
		expected_price += PriceTable.price_of_object(def_id)
	assert_int(SecurityLaneStamp.price()).is_equal(expected_price)
	assert_int(BuildMenuCatalog.tool_price(BuildMode.Tool.SECURITY_LANE)).is_equal(expected_price)

	# All 4 facings place a COMPLETE SecurityLanes lane and revert in ONE Undo step.
	mode.set_tool(BuildMode.Tool.SECURITY_LANE)
	for facing in 4:
		mode.facing = facing
		var anchor := Vector2i(9, 9)
		var cash_before := finances.wallet.balance
		var res := mode.apply_at(mode.grid.cell_to_world(anchor))
		assert_bool(res.ok).override_failure_message("facing %d" % facing).is_true()
		assert_int(finances.wallet.balance).is_equal(cash_before - expected_price)
		var lanes := SecurityLanes.new()
		lanes.rebuild(mode.grid)
		var arch_id := mode.grid.object_at(anchor)
		assert_bool(lanes.is_complete(arch_id)).is_true()
		assert_int(mode.grid.object_ids().size()).is_equal(4)
		var undo_res := mode.undo()
		assert_bool(undo_res != null and undo_res.ok).is_true()
		assert_int(mode.grid.object_ids().size()).is_equal(0)
		assert_int(finances.wallet.balance).is_equal(cash_before)

	# Atomic failure when blocked (wall across lane): zero partial pieces & cash untouched.
	mode.facing = 0
	mode.grid.apply(BuildEdit.place_wall(Vector2i(9, 9), BuildGrid.Side.EAST))
	var cash_blocked := finances.wallet.balance
	var count_before := mode.grid.object_ids().size()
	var blocked_res := mode.apply_at(mode.grid.cell_to_world(Vector2i(9, 9)))
	assert_bool(blocked_res.ok).is_false()
	assert_int(mode.grid.object_ids().size()).is_equal(count_before)
	assert_int(finances.wallet.balance).is_equal(cash_blocked)

	# Atomic failure when unaffordable: zero partial pieces & cash untouched.
	finances.wallet.balance = expected_price - 1
	var poor_res := mode.apply_at(mode.grid.cell_to_world(Vector2i(12, 9)))
	assert_bool(poor_res.ok).is_false()
	assert_int(poor_res.reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_int(mode.grid.object_ids().size()).is_equal(count_before)
	assert_int(finances.wallet.balance).is_equal(expected_price - 1)

	# BuildUnlocks gates SECURITY_LANE at the same tier as ARCH (tier 2).
	assert_int(BuildUnlocks.tier_of(BuildMode.Tool.SECURITY_LANE)).is_equal(
		BuildUnlocks.tier_of(BuildMode.Tool.ARCH)
	)

	# Hover ghost shows all 4 parts when valid.
	finances.wallet.balance = expected_price * 2
	mode._pointer_on_grid = true
	SecurityLaneStamp.hover(mode, mode.grid.cell_to_world(Vector2i(12, 9)))
	assert_bool(mode._ghost.visible).is_true()
	assert_int(mode._ghost.get_child_count()).is_greater_equal(4)
