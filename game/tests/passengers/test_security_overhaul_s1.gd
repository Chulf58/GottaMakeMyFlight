class_name TestSecurityOverhaulS1
extends GdUnitTestSuite
## Regression suite for Security Overhaul Slice S1 (9d99b363, user ruling
## a0247eca, Astra technical contract 802db2ea):
## (a) Zero-bag passengers never receive bag flags; 3 deterministic RNG draws hold
## (b) Body Alarm holds arch briefly (BODY_CHECK) and resolves ONLY body_resolved
##     without arch walk-back, strobing the Arch_Lamp beacon
## (c) X-Ray Bag Flag moves to Search Table / berth, mounts tray at Mount_Inspect
##     (y = 0.830), records confiscation ONCE on sim completion (never on forecast
##     replay), mounts gag prop in Mount_Prop_00..11, and exits without arch loop
## (d) Dual-flagged passenger resolves body at arch then bag at berth cleanly
## (e) Adding/removing search_table or confiscation_bin mid-service never triggers
##     SecurityLanes.broken() or ejects active passengers
## (f) Midnight rollover resets daily bin history/props, save/load round-trips
##     mid-phase & bin history, BuiltItemCard displays recent finds via tr(),
##     all 24 contraband names/quips exist in messages.pot, and fixed-seed
##     throughput meets or beats baseline.

var _worlds: Array[SecurityTestWorld] = []
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
		w.world.free_all()
	_worlds.clear()


func _make_lane(with_attachments: bool, seed := 11, mirror := SecurityLanes.RIGHT) -> Dictionary:
	var w := SecurityTestWorld.make(true, seed, mirror)
	_worlds.append(w)
	var geom := SecurityLanes.geometry(SecurityTestWorld.ARCH_AT, 0, mirror)
	var table_id := 0
	var bin_id := 0
	if with_attachments:
		table_id = PassengerTestWorld.place(
			w.world.grid, SecurityLanes.SEARCH_TABLE, geom["search_table_cell"], 0
		)
		bin_id = PassengerTestWorld.place(
			w.world.grid, SecurityLanes.CONFISCATION_BIN, geom["confiscation_bin_cell"], 0
		)
	var view := BuildView.new()
	add_child(view)
	view.refresh(w.world.grid)
	_nodes.append(view)
	return {"w": w, "view": view, "table_id": table_id, "bin_id": bin_id}


func test_zero_bag_passengers_never_get_bag_flag_and_three_draws_deterministic() -> void:
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 20261123
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 20261123
	var with_bag := 0
	var liquids_with_bag := 0
	var zero_bag_liquids := 0
	var alarms := 0
	for i in 2000:
		var a := Passenger.new()
		var b := Passenger.new()
		CarryOnTraits.draw(rng_a, a)
		CarryOnTraits.draw(rng_b, b)
		assert_int(a.carry_on).is_equal(b.carry_on)
		assert_bool(a.liquids).is_equal(b.liquids)
		assert_bool(a.alarm).is_equal(b.alarm)
		if a.carry_on == 0 and a.liquids:
			zero_bag_liquids += 1
		if a.carry_on > 0:
			with_bag += 1
			liquids_with_bag += int(a.liquids)
		alarms += int(a.alarm)
	assert_int(zero_bag_liquids).is_equal(0)
	assert_float(liquids_with_bag / float(with_bag)).is_equal_approx(0.12, 0.025)
	assert_float(alarms / 2000.0).is_equal_approx(0.08, 0.02)
	assert_float(rng_a.randf()).is_equal(rng_b.randf())


func test_body_alarm_holds_arch_resolves_only_body_without_walkback_and_strobes_lamp() -> void:
	var ctx := _make_lane(true)
	var w: SecurityTestWorld = ctx["w"]
	var view: BuildView = ctx["view"]
	var id := w.send(1, false, true)
	var p := w.world.passenger(id)
	var holders: Array[int] = []
	var saw_body_check := false
	var saw_repack := false
	var saw_red := false
	var saw_amber := false
	for _i in 600:
		w.world.step()
		view.sync_security(w.world.sim, 0.0)
		var main: int = w.runtime_record().get("main", 0)
		if main != 0 and (holders.is_empty() or holders[-1] != main):
			holders.append(main)
		if p.security_phase == SecurityRuntime.Phase.BODY_CHECK:
			saw_body_check = true
			var lamp := (
				view.object_node(w.station).find_child("Arch_Lamp", true, false) as MeshInstance3D
			)
			var mat := lamp.material_override as StandardMaterial3D
			assert_bool(mat != null and mat.emission_enabled).is_true()
			if mat.emission.r > 0.9 and mat.emission.g < 0.3:
				saw_red = true
			elif mat.emission.r > 0.9 and mat.emission.g > 0.5:
				saw_amber = true
		elif p.security_phase in [SecurityRuntime.Phase.TO_BERTH, SecurityRuntime.Phase.REPACK]:
			saw_repack = true
		if w.cleared.has(id):
			break
	assert_bool(w.cleared.has(id)).is_true()
	assert_bool(saw_body_check).is_true()
	assert_bool(saw_repack).is_false()
	assert_bool(p.body_resolved).is_true()
	assert_bool(p.bag_resolved).is_false()
	assert_int(holders.count(id)).is_equal(1)
	assert_bool(saw_red).is_true()
	assert_bool(saw_amber).is_true()
	view.sync_security(w.world.sim, 0.0)
	var clear_lamp := (
		view.object_node(w.station).find_child("Arch_Lamp", true, false) as MeshInstance3D
	)
	var clear_mat := clear_lamp.material_override as StandardMaterial3D
	assert_float(clear_mat.emission.g).is_greater(0.7)


func test_bag_flag_uses_search_table_records_confiscation_once_and_mounts_bin_prop() -> void:
	var ctx := _make_lane(true)
	var w: SecurityTestWorld = ctx["w"]
	var view: BuildView = ctx["view"]
	var bin_id: int = ctx["bin_id"]
	var id := w.send(1, true, false)
	var p := w.world.passenger(id)
	var holders: Array[int] = []
	var saw_inspect := false
	for _i in 800:
		w.world.step()
		view.sync_security(w.world.sim, 0.0)
		var main: int = w.runtime_record().get("main", 0)
		if main != 0 and (holders.is_empty() or holders[-1] != main):
			holders.append(main)
		if p.security_phase == SecurityRuntime.Phase.REPACK:
			saw_inspect = true
			assert_int(SecurityLooks.tray(w.world.sim, p)).is_equal(SecurityLooks.Tray.INSPECT)
			assert_array(SecurityLooks.bag_homes(w.world.sim, p)).is_equal(
				[SecurityLooks.Home.TRAY]
			)
			var lane := SecurityLooks.lane_of(w.world.sim, p)
			var tray_xf := (
				CarryTray
				. placed(
					w.world.grid,
					lane,
					SecurityLooks.Tray.INSPECT,
					w.world.sim.world_position(p),
				)
			)
			assert_float(tray_xf.origin.y).is_equal_approx(0.830, 0.01)
			# Querying SecurityForecast mid-REPACK must never duplicate bin confiscations.
			var eta := SecurityForecast.eta(w.world.sim, p)
			assert_int(eta).is_greater(0)
			assert_int(w.world.sim.security.bins.count(bin_id)).is_equal(0)
		if w.cleared.has(id):
			break
	assert_bool(w.cleared.has(id)).is_true()
	assert_bool(saw_inspect).is_true()
	assert_bool(p.bag_resolved).is_true()
	assert_bool(p.body_resolved).is_false()
	assert_int(holders.count(id)).is_equal(1)
	assert_int(w.world.sim.security.bins.count(bin_id)).is_equal(1)
	var want_item := SecuritySearchReasons.contraband_index(id)
	assert_array(w.world.sim.security.bins.items(bin_id)).is_equal([want_item])
	var bin_node := view.object_node(bin_id)
	var mount0 := bin_node.find_child("Mount_Prop_00", true, false) as Node3D
	var mount1 := bin_node.find_child("Mount_Prop_01", true, false) as Node3D
	assert_int(mount0.get_child_count()).is_equal(1)
	assert_int(mount1.get_child_count()).is_equal(0)


func test_dual_flag_completes_body_then_bag_without_arch_walkback() -> void:
	var ctx := _make_lane(true)
	var w: SecurityTestWorld = ctx["w"]
	var bin_id: int = ctx["bin_id"]
	var id := w.send(2, true, true)
	var p := w.world.passenger(id)
	var phases: Array[int] = []
	for _i in 800:
		w.world.step()
		if p.stage == Passenger.Stage.SECURITY:
			if phases.is_empty() or phases[-1] != p.security_phase:
				phases.append(p.security_phase)
		if w.cleared.has(id):
			break
	assert_bool(w.cleared.has(id)).is_true()
	assert_bool(p.body_resolved).is_true()
	assert_bool(p.bag_resolved).is_true()
	assert_int(phases.find(SecurityRuntime.Phase.BODY_CHECK)).is_greater(-1)
	assert_int(phases.find(SecurityRuntime.Phase.REPACK)).is_greater(
		phases.find(SecurityRuntime.Phase.BODY_CHECK)
	)
	assert_int(phases.count(SecurityRuntime.Phase.UNPACK)).is_equal(1)
	assert_int(phases.count(SecurityRuntime.Phase.ARCH)).is_equal(1)
	assert_int(w.world.sim.security.bins.count(bin_id)).is_equal(1)


func test_one_officer_serializes_body_check_over_repack_and_helper_overlaps() -> void:
	var ctx := _make_lane(true)
	var w: SecurityTestWorld = ctx["w"]
	w.world.auto_staff = false
	StaffTestKit.seat(w.world.staff, w.station, StaffMember.Slot.PRIMARY)
	var bag_id := w.send(1, true, false)
	w.world.run_to(w.world.clock.tick + 25)
	var body_id := w.send(0, false, true)
	var bag_p := w.world.passenger(bag_id)
	var body_p := w.world.passenger(body_id)
	while (
		bag_p.security_phase != SecurityRuntime.Phase.REPACK
		or body_p.security_phase != SecurityRuntime.Phase.BODY_CHECK
	):
		w.world.step()
	assert_int(bag_p.security_work).is_greater(0)
	assert_int(body_p.security_work).is_greater(0)
	assert_int(w.world.sim.security.rate_for(w.station, body_p)).is_equal(1)
	assert_int(w.world.sim.security.rate_for(w.station, bag_p)).is_equal(0)
	var bag_work_paused := bag_p.security_work
	w.world.step()
	assert_int(bag_p.security_work).is_equal(bag_work_paused)
	StaffTestKit.seat(w.world.staff, w.station, StaffMember.Slot.HELPER)
	assert_int(w.world.sim.security.rate_for(w.station, bag_p)).is_equal(
		SecurityRuntime.HELPER_RATE
	)
	assert_int(w.world.sim.security.rate_for(w.station, body_p)).is_equal(1)


func test_attachment_edits_mid_service_never_break_lane_or_eject_passengers() -> void:
	var ctx := _make_lane(false)
	var w: SecurityTestWorld = ctx["w"]
	var geom := SecurityLanes.geometry(SecurityTestWorld.ARCH_AT, 0, SecurityLanes.RIGHT)
	var id := w.send(1, true, false)
	var p := w.world.passenger(id)
	while p.security_phase != SecurityRuntime.Phase.REPACK:
		w.world.step()
	var before := SecurityLanes.new()
	before.rebuild(w.world.grid)
	var table_id := PassengerTestWorld.place(
		w.world.grid, SecurityLanes.SEARCH_TABLE, geom["search_table_cell"], 0
	)
	var bin_id := PassengerTestWorld.place(
		w.world.grid, SecurityLanes.CONFISCATION_BIN, geom["confiscation_bin_cell"], 0
	)
	var after_add := SecurityLanes.new()
	after_add.rebuild(w.world.grid)
	assert_array(SecurityLanes.broken(before, after_add)).is_empty()
	w.world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SECURITY)
	assert_int(p.security_phase).is_equal(SecurityRuntime.Phase.REPACK)
	assert_bool(w.world.grid.apply(BuildEdit.remove_object(table_id)).ok).is_true()
	assert_bool(w.world.grid.apply(BuildEdit.remove_object(bin_id)).ok).is_true()
	var after_rem := SecurityLanes.new()
	after_rem.rebuild(w.world.grid)
	assert_array(SecurityLanes.broken(after_add, after_rem)).is_empty()
	w.world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SECURITY)
	assert_bool(w.run_until_cleared([id])).is_true()


func test_attachment_sockets_never_overlap_walk_or_staff_cells_at_any_facing_or_mirror() -> void:
	for facing in 4:
		for mirror in [SecurityLanes.RIGHT, SecurityLanes.LEFT]:
			var g := SecurityLanes.geometry(Vector2i(8, 8), facing, mirror)
			var reserved := [
				g["arch"],
				g["tray_table"],
				g["xray_belt"],
				g["pickup_table"],
				g["queue_entry"],
				g["unpack"],
				g["pickup"],
				g["exit"],
				g["berth"],
				g["primary_spot"],
				g["helper_spot"],
			]
			reserved.append_array(g["return_route"])
			assert_bool(reserved.has(g["search_table_cell"])).is_false()
			assert_bool(reserved.has(g["confiscation_bin_cell"])).is_false()
			assert_that(g["search_table_cell"]).is_not_equal(g["confiscation_bin_cell"])


func test_midnight_rollover_save_load_built_item_card_and_pot_coverage() -> void:
	var ctx := _make_lane(true)
	var w: SecurityTestWorld = ctx["w"]
	var view: BuildView = ctx["view"]
	var bin_id: int = ctx["bin_id"]
	var id := w.send(1, true, false)
	assert_bool(w.run_until_cleared([id])).is_true()
	assert_int(w.world.sim.security.bins.count(bin_id)).is_equal(1)

	# BuiltItemCard shows confiscated today count and recent gag item with localized tr().
	var sel := BuiltSelection.new()
	sel.select_object(bin_id)
	var bm := BuildMode.new()
	bm.set_process(false)
	add_child(bm)
	_nodes.append(bm)
	var card := BuiltItemCard.new()
	card.sim = w.world.sim
	card.selection = sel
	card.build_mode = bm
	add_child(card)
	_nodes.append(card)
	card.refresh()
	var item_idx := SecuritySearchReasons.contraband_index(id)
	var item_name := SecuritySearchReasons.contraband_name(item_idx)
	assert_str(card.field_text("confiscated")).contains("1")
	assert_str(card.field_text("recent")).contains(item_name)

	# Save/load round-trips confiscation bin history cleanly.
	assert_int(PassengerSim.SAVE_VERSION).is_equal(37)
	assert_int(SaveGame.SAVE_VERSION).is_equal(32)
	var snap: Dictionary = JSON.parse_string(JSON.stringify(w.world.sim.to_snapshot()))
	var ctx_loaded := _make_lane(true)
	var loaded: SecurityTestWorld = ctx_loaded["w"]
	loaded.world.clock.from_snapshot(JSON.parse_string(JSON.stringify(w.world.clock.to_snapshot())))
	loaded.world.flights.from_snapshot(
		JSON.parse_string(JSON.stringify(w.world.flights.to_snapshot()))
	)
	assert_bool(loaded.world.sim.from_snapshot(snap)).is_true()
	assert_int(loaded.world.sim.security.bins.count(bin_id)).is_equal(1)
	assert_array(loaded.world.sim.security.bins.items(bin_id)).is_equal([item_idx])

	# Midnight day rollover clears daily counts, items, and rendered bin props.
	var ticks_to_midnight := (
		GameCalendar.TICKS_PER_DAY
		- GameCalendar.tick_of_day(w.world.clock.tick, w.world.clock.epoch)
	)
	w.world.run_to(w.world.clock.tick + ticks_to_midnight)
	view.sync_security(w.world.sim, 0.0)
	assert_int(w.world.sim.security.bins.count(bin_id)).is_equal(0)
	assert_array(w.world.sim.security.bins.items(bin_id)).is_empty()
	var mount0 := view.object_node(bin_id).find_child("Mount_Prop_00", true, false) as Node3D
	assert_int(mount0.get_child_count()).is_equal(0)

	# All 24 contraband props exist and all 48 names/quips are in messages.pot.
	assert_int(SecuritySearchReasons.CONTRABAND_ITEMS.size()).is_equal(24)
	var pot := PotEntries.parse(FileAccess.get_file_as_string("res://locale/messages.pot"))
	for entry: Dictionary in SecuritySearchReasons.CONTRABAND_ITEMS:
		var glb := "res://assets/interior/contraband/%s.glb" % entry["prop"]
		assert_bool(ResourceLoader.exists(glb)).is_true()
		assert_int(PotEntries.count(pot, "", entry["name"])).is_equal(1)
		assert_int(PotEntries.count(pot, "", entry["quip"])).is_equal(1)


func test_fixed_seed_throughput_meets_or_beats_baseline() -> void:
	var ctx := _make_lane(true, 42)
	var w: SecurityTestWorld = ctx["w"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var ids: Array[int] = []
	for i in 12:
		var p := Passenger.new()
		CarryOnTraits.draw(rng, p)
		ids.append(w.send(p.carry_on, p.liquids, p.alarm))
		w.world.run_to(w.world.clock.tick + 12)
	assert_bool(w.run_until_cleared(ids, 2000)).is_true()
	var last := 0
	for id in ids:
		last = maxi(last, w.cleared[id])
	# No second arch pass means even a 12-passenger mixed queue clears briskly.
	assert_int(last).is_less(850)


func test_mid_phase_dual_save_round_trip_bin_eviction_and_prune() -> void:
	var ctx := _make_lane(true, 17)
	var w: SecurityTestWorld = ctx["w"]
	var bin_id: int = ctx["bin_id"]
	var id := w.send(2, true, true)
	var p := w.world.passenger(id)

	# 1. Mid-BODY_CHECK save/load preserves body_resolved = false & phase = BODY_CHECK.
	while p.security_phase != SecurityRuntime.Phase.BODY_CHECK:
		w.world.step()
	w.world.step()
	var body_snap: Dictionary = JSON.parse_string(JSON.stringify(w.world.sim.to_snapshot()))
	var ctx_b := _make_lane(true, 17)
	var wb: SecurityTestWorld = ctx_b["w"]
	wb.world.clock.from_snapshot(JSON.parse_string(JSON.stringify(w.world.clock.to_snapshot())))
	wb.world.flights.from_snapshot(JSON.parse_string(JSON.stringify(w.world.flights.to_snapshot())))
	assert_bool(wb.world.sim.from_snapshot(body_snap)).is_true()
	var pb := wb.world.passenger(id)
	assert_int(pb.security_phase).is_equal(SecurityRuntime.Phase.BODY_CHECK)
	assert_int(pb.security_work).is_equal(p.security_work)
	assert_bool(pb.body_resolved).is_false()
	assert_bool(pb.bag_resolved).is_false()

	# 2. Mid-REPACK after BODY_CHECK preserves body_resolved = true, bag_resolved = false.
	while p.security_phase != SecurityRuntime.Phase.REPACK:
		w.world.step()
	var repack_snap: Dictionary = JSON.parse_string(JSON.stringify(w.world.sim.to_snapshot()))
	var ctx_r := _make_lane(true, 17)
	var wr: SecurityTestWorld = ctx_r["w"]
	wr.world.clock.from_snapshot(JSON.parse_string(JSON.stringify(w.world.clock.to_snapshot())))
	wr.world.flights.from_snapshot(JSON.parse_string(JSON.stringify(w.world.flights.to_snapshot())))
	assert_bool(wr.world.sim.from_snapshot(repack_snap)).is_true()
	var pr := wr.world.passenger(id)
	assert_int(pr.security_phase).is_equal(SecurityRuntime.Phase.REPACK)
	assert_bool(pr.body_resolved).is_true()
	assert_bool(pr.bag_resolved).is_false()
	assert_bool(wr.run_until_cleared([id])).is_true()
	assert_bool(pr.bag_resolved).is_true()
	assert_int(wr.world.sim.security.bins.count(bin_id)).is_equal(1)

	# 3. ConfiscationBins evicts oldest past MAX_BIN_HISTORY = 12 while keeping total count.
	for i in 14:
		w.world.sim.security.bins.record(bin_id, i)
	assert_int(w.world.sim.security.bins.count(bin_id)).is_equal(14)
	var kept := w.world.sim.security.bins.items(bin_id)
	assert_int(kept.size()).is_equal(SecurityRuntime.MAX_BIN_HISTORY)
	assert_int(kept[0]).is_equal(2)
	assert_int(kept[-1]).is_equal(13)

	# 4. Removing the bin and pruning removes its stored confiscation history.
	assert_bool(w.world.grid.apply(BuildEdit.remove_object(bin_id)).ok).is_true()
	w.world.sim.security.bins.prune(w.world.grid)
	assert_int(w.world.sim.security.bins.count(bin_id)).is_equal(0)
	assert_array(w.world.sim.security.bins.items(bin_id)).is_empty()
