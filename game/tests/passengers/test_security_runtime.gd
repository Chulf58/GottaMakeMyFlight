class_name TestSecurityRuntime
extends GdUnitTestSuite
## SecurityRuntime at both tiers (decisions security-lane-technical-design-
## one-station-per-lane-with-int, carry-on-slows-both-security-tiers-the-basic-
## scanner-serves and security-repack-at-a-security-lane-a-liquids-or-alarm-
## passen): the lane clears a queue sooner than the basic scanner on the same
## seed and traits, a repack holds the basic scanner but not the lane, the
## berth is reserved before service, a returning passenger goes ahead of the
## queue front, and back-to-back incidents do not deadlock.

## [bags, liquids, alarm] for a mixed queue: every bag count and both incidents.
const MIXED := [
	[1, false, false],
	[2, false, false],
	[0, false, false],
	[1, true, false],
	[2, false, false],
	[1, false, true],
	[0, false, false],
	[2, false, false],
]

const STARTER_SITE := preload("res://build/terminal_site.tres")

var _worlds: Array[SecurityTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for w in _worlds:
		w.world.free_all()
	_worlds.clear()


func _make(use_lane: bool) -> SecurityTestWorld:
	var w := SecurityTestWorld.make(use_lane)
	_worlds.append(w)
	return w


func test_both_tiers_are_one_open_station_on_the_same_cells() -> void:
	var lane := _make(true)
	var basic := _make(false)
	lane.world.step()
	basic.world.step()
	assert_bool(lane.world.staff.is_open(lane.station)).is_true()
	assert_bool(basic.world.staff.is_open(basic.station)).is_true()
	assert_bool(lane.world.sim.security.is_lane(lane.station)).is_true()
	assert_bool(basic.world.sim.security.is_lane(basic.station)).is_false()
	assert_that(lane.world.sim.security.exit_cell(lane.station)).is_equal(Vector2i(5, 4))
	assert_that(basic.world.sim.security.exit_cell(basic.station)).is_equal(Vector2i(5, 4))
	assert_array(lane.world.sim.layout.lanes[lane.station]).is_equal(
		basic.world.sim.layout.lanes[basic.station]
	)


func test_one_passenger_with_no_bags_takes_the_old_basic_time() -> void:
	var basic := _make(false)
	var id := basic.send(0)
	assert_bool(basic.run_until_cleared([id])).is_true()
	var took: int = basic.cleared[id] - basic.admitted[id]
	print("basic, no bags: admitted %d, cleared %d" % [basic.admitted[id], basic.cleared[id]])
	assert_int(took).is_equal(SecurityRuntime.BASIC_SCAN_TICKS)


func test_bags_add_time_at_both_tiers() -> void:
	for use_lane in [false, true]:
		var took := []
		for bags in [0, 1, 2]:
			var w := _make(use_lane)
			var id := w.send(bags)
			assert_bool(w.run_until_cleared([id])).is_true()
			took.append(w.cleared[id] - w.admitted[id])
		print("lane %s: clearance for 0, 1, 2 bags %s" % [use_lane, took])
		assert_int(took[1]).is_greater(took[0])
		assert_int(took[2]).is_greater(took[1])


func test_the_lane_clears_a_queue_sooner_than_the_basic_scanner() -> void:
	var finish := {}
	for use_lane in [false, true]:
		var w := _make(use_lane)
		var ids := w.send_all(MIXED)
		assert_bool(w.run_until_cleared(ids)).is_true()
		var last := 0
		var total := 0
		for id in ids:
			last = maxi(last, w.cleared[id])
			total += w.cleared[id]
		finish[use_lane] = [last, total]
	print(
		"last cleared and sum of clearance ticks: basic %s, lane %s" % [finish[false], finish[true]]
	)
	assert_int(finish[true][0]).is_less(finish[false][0])
	assert_int(finish[true][1]).is_less(finish[false][1])


## The clearance of the passenger behind a first passenger with or without
## liquids, at one tier.
func _second_clearance(use_lane: bool, incident: bool) -> int:
	var w := _make(use_lane)
	var ids := w.send_all([[1, incident, false], [1, false, false]])
	assert_bool(w.run_until_cleared(ids)).is_true()
	return w.cleared[ids[1]]


func test_a_repack_blocks_the_basic_scanner_but_not_the_lane() -> void:
	var basic_delay := _second_clearance(false, true) - _second_clearance(false, false)
	var lane_delay := _second_clearance(true, true) - _second_clearance(true, false)
	print(
		(
			"the next passenger is held %d ticks at the scanner, %d at the lane"
			% [basic_delay, lane_delay]
		)
	)
	assert_int(basic_delay).is_greater_equal(SecurityRuntime.REPACK_TICKS)
	assert_int(lane_delay).is_equal(0)


func test_back_to_back_incidents_do_not_deadlock_and_nobody_skips() -> void:
	for use_lane in [false, true]:
		var w := _make(use_lane)
		var traits := [
			[1, true, false], [2, false, true], [0, true, true], [1, true, false], [1, false, false]
		]
		var ids := w.send_all(traits)
		# The berth holder on each tick: an incident passenger is admitted
		# only once the previous one has stepped off the berth.
		var berth_free_at := {}
		var stop := w.world.clock.tick + 4000
		var holder := 0
		while (
			w.world.clock.tick < stop
			and not ids.all(func(id: int) -> bool: return w.cleared.has(id))
		):
			w.world.step()
			var now: int = w.runtime_record().get("berth", 0)
			if holder != 0 and now != holder:
				berth_free_at[holder] = w.world.sim.tick
			holder = now
		var order := w.joined
		print(
			(
				"lane %s: joined %s, admitted %s, berth freed %s, cleared %s"
				% [use_lane, order, w.admitted, berth_free_at, w.cleared]
			)
		)
		assert_bool(ids.all(func(id: int) -> bool: return w.cleared.has(id))).is_true()
		assert_bool(w.world.sim.security.records.is_empty()).is_true()
		# Admitted in the order they joined the queue: nobody skips a front
		# passenger waiting for the berth.
		assert_int(order.size()).is_equal(ids.size())
		for i in range(1, order.size()):
			assert_int(w.admitted[order[i]]).is_greater(w.admitted[order[i - 1]])
		if use_lane:
			var incidents := order.filter(
				func(id: int) -> bool:
					var pax := w.world.passenger(id)
					return pax.liquids and pax.carry_on > 0
			)
			for i in range(1, incidents.size()):
				var before_free: int = berth_free_at[incidents[i - 1]]
				assert_int(w.admitted[incidents[i]]).is_greater_equal(before_free)
		for id in ids:
			var p := w.world.passenger(id)
			assert_bool(p.cleared).is_true()
			assert_int(p.security_phase).is_equal(SecurityRuntime.Phase.NONE)
			assert_bool(p.body_resolved).is_equal(p.alarm)
			assert_bool(p.bag_resolved).is_equal(p.liquids and p.carry_on > 0)


func test_bag_search_exits_from_berth_without_returning_through_arch() -> void:
	var w := _make(true)
	var ids := w.send_all(
		[
			[1, true, false],
			[2, false, false],
			[2, false, false],
			[2, false, false],
			[2, false, false],
			[2, false, false],
			[2, false, false]
		]
	)
	var first := ids[0]
	var holders: Array[int] = []
	var saw_repack := false
	for i in 2000:
		var p := w.world.passenger(first)
		if p.security_phase == SecurityRuntime.Phase.REPACK:
			saw_repack = true
		w.world.step()
		var main: int = w.runtime_record().get("main", 0)
		if main != 0 and (holders.is_empty() or holders[holders.size() - 1] != main):
			holders.append(main)
		if ids.all(func(id: int) -> bool: return w.cleared.has(id)):
			break
	assert_bool(saw_repack).is_true()
	# Bag-flagged passenger resolves at berth and leaves without looping back through main/arch.
	assert_int(holders.count(first)).is_equal(1)
	assert_bool(ids.all(func(id: int) -> bool: return w.cleared.has(id))).is_true()
	assert_bool(w.world.passenger(first).bag_resolved).is_true()


func test_a_removed_lane_part_sends_admitted_passengers_back_without_clearance() -> void:
	var w := _make(true)
	var ids := w.send_all([[2, true, false], [2, false, false]])
	while w.world.passenger(ids[0]).security_phase != SecurityRuntime.Phase.REPACK:
		w.world.step()
	var tray := w.world.grid.object_at(
		SecurityLanes.geometry(SecurityTestWorld.ARCH_AT, 0, 1)["tray_table"]
	)
	assert_bool(w.world.grid.apply(BuildEdit.remove_object(tray)).ok).is_true()
	w.world.step()
	for id in ids:
		var p := w.world.passenger(id)
		assert_bool(p.cleared).is_false()
		assert_int(p.security_phase).is_equal(SecurityRuntime.Phase.NONE)
		assert_int(p.stage).is_equal(Passenger.Stage.TO_SECURITY)
	assert_bool(w.world.sim.security.records.is_empty()).is_true()


func test_admit_front_refuses_and_drops_stale_non_queued_members() -> void:
	var w := _make(true)
	w.world.step()
	var sim := w.world.sim
	var cells: Array = sim.layout.lanes[w.station]
	var stale_made := w.world.passenger(w.send(0))
	stale_made.stage = Passenger.Stage.MADE
	stale_made.station = 0
	stale_made.at = cells[0]
	var stale_gate := w.world.passenger(w.send(0))
	stale_gate.stage = Passenger.Stage.TO_GATE
	stale_gate.station = 99
	stale_gate.at = cells[0]
	var valid := w.world.passenger(w.send(0))
	valid.stage = Passenger.Stage.SECURITY_QUEUE
	valid.station = w.station
	valid.at = cells[0]
	var q := sim._queue(w.station)
	q["lane"] = [999999, valid.id]
	assert_object(sim.security.ready_front(w.station, q, cells, true)).is_null()
	assert_array(q["lane"]).is_equal([999999, valid.id])
	q["lane"] = [stale_made.id, stale_gate.id, 999999, valid.id]
	assert_object(sim.security.ready_front(w.station, q, cells, true)).is_null()
	assert_array(q["lane"]).is_equal([stale_made.id, stale_gate.id, 999999, valid.id])
	var results: Array[bool] = []
	await (
		assert_error(func() -> void: results.append(sim.security.admit_front(w.station, q)))
		. is_push_error(
			(
				(
					"SecurityRuntime.admit_front: refused passenger %d at station %d "
					+ "(stage MADE, expected SECURITY_QUEUE)"
				)
				% [stale_made.id, w.station]
			)
		)
	)
	await (
		assert_error(func() -> void: results.append(sim.security.admit_front(w.station, q)))
		. is_push_error(
			(
				(
					"SecurityRuntime.admit_front: refused passenger %d at station %d "
					+ "(stage TO_GATE, expected SECURITY_QUEUE)"
				)
				% [stale_gate.id, w.station]
			)
		)
	)
	await (
		assert_error(func() -> void: results.append(sim.security.admit_front(w.station, q)))
		. is_push_error(
			(
				(
					"SecurityRuntime.admit_front: refused passenger 999999 at station %d "
					+ "(stage null, expected SECURITY_QUEUE)"
				)
				% w.station
			)
		)
	)
	assert_array(results).is_equal([false, false, false])
	assert_array(q["lane"]).is_equal([valid.id])
	assert_bool(sim.security.records.is_empty()).is_true()
	assert_int(stale_made.stage).is_equal(Passenger.Stage.MADE)
	assert_int(stale_made.station).is_equal(0)
	assert_int(stale_made.security_phase).is_equal(SecurityRuntime.Phase.NONE)
	assert_int(stale_gate.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_int(stale_gate.station).is_equal(99)
	assert_int(stale_gate.security_phase).is_equal(SecurityRuntime.Phase.NONE)
	assert_bool(w.admitted.has(stale_made.id)).is_false()
	assert_bool(w.admitted.has(stale_gate.id)).is_false()
	assert_object(sim.security.ready_front(w.station, q, cells, true)).is_same(valid)
	var admitted_valid := sim.security.admit_front(w.station, q)
	assert_bool(admitted_valid).is_true()
	assert_array(q["lane"]).is_empty()
	assert_int(valid.stage).is_equal(Passenger.Stage.SECURITY)
	assert_bool(w.admitted.has(valid.id)).is_true()
	var empty_res: Array[bool] = []
	await (
		assert_error(func() -> void: empty_res.append(sim.security.admit_front(w.station, q)))
		. is_push_error("SecurityRuntime.admit_front: empty lane at station %d" % w.station)
	)
	assert_array(empty_res).is_equal([false])


func test_basic_scanner_runs_body_check_then_repack_on_dual_incident() -> void:
	var w := _make(false)
	var id := w.send(1, true, true)
	var p := w.world.passenger(id)
	var phases: Array[int] = []
	var stop := w.world.clock.tick + 600
	while w.world.clock.tick < stop and not w.cleared.has(id):
		w.world.step()
		if p.security_phase != SecurityRuntime.Phase.NONE:
			if phases.is_empty() or phases[-1] != p.security_phase:
				phases.append(p.security_phase)
	assert_bool(w.cleared.has(id)).is_true()
	(
		assert_array(phases)
		. is_equal(
			[
				SecurityRuntime.Phase.SCAN,
				SecurityRuntime.Phase.BODY_CHECK,
				SecurityRuntime.Phase.REPACK,
			]
		)
	)
	assert_bool(p.body_resolved).is_true()
	assert_bool(p.bag_resolved).is_true()


func test_day1_starter_flight_boards_cleanly_with_slower_basic_scanners() -> void:
	var grid := BuildGrid.new(STARTER_SITE.grid_size, STARTER_SITE.grid_origin)
	assert_bool(ReferenceTerminal.build(grid, STARTER_SITE.starter_offset)).is_true()
	var starts := FlightSim.schedule_starts(0)
	var starter := PassengerTestWorld.make(grid, starts, 19)
	starter.sim.site = STARTER_SITE
	var count := 14
	for i in count:
		var pid := starter.sim.spawn_now(PassengerTestWorld.FLIGHT)
		var p := starter.passenger(pid)
		p.carry_on = 1 if i % 3 != 0 else 0
		p.liquids = i % 6 == 2
		p.alarm = i % 5 == 3
		starter.run_to(starter.clock.tick + 15)
	starter.run_to(starts[FlightSim.State.DOORS_CLOSED])
	var made := starter.sim.made_count()
	starter.free_all()
	assert_int(made).is_equal(count)
