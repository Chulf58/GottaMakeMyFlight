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

var _worlds: Array[SecurityTestWorld] = []
var _lanes_were := false


func before() -> void:
	PassengerTestWorld.tracker = self
	_lanes_were = SecurityLanes.enabled
	SecurityLanes.enabled = true


func after() -> void:
	PassengerTestWorld.tracker = null
	SecurityLanes.enabled = _lanes_were


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
			var incidents := order.filter(func(id: int) -> bool: return id != ids[4])
			for i in range(1, incidents.size()):
				var before_free: int = berth_free_at[incidents[i - 1]]
				assert_int(w.admitted[incidents[i]]).is_greater_equal(before_free)
		for id in ids:
			var p := w.world.passenger(id)
			assert_bool(p.cleared).is_true()
			assert_int(p.security_phase).is_equal(SecurityRuntime.Phase.NONE)
			assert_bool(p.incident_resolved).is_equal(p.liquids or p.alarm)


func test_a_returning_passenger_goes_ahead_of_the_queue_front() -> void:
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
	var ready_tick := -1
	var held_then := -1
	var next_holder := 0
	var front_waiting := false
	var cells: Array = w.world.sim.layout.lanes[w.station]
	for i in 2000:
		var p := w.world.passenger(first)
		if (
			ready_tick < 0
			and p.security_phase == SecurityRuntime.Phase.RETURN
			and not p.is_moving()
		):
			ready_tick = w.world.sim.tick
			held_then = w.runtime_record().get("main", 0)
			var lane := w.world.sim.queue_of(w.station)
			front_waiting = not lane.is_empty() and w.world.passenger(lane[0]).at == cells[0]
		w.world.step()
		var main: int = w.runtime_record().get("main", 0)
		if main != 0 and (holders.is_empty() or holders[holders.size() - 1] != main):
			holders.append(main)
			if ready_tick >= 0 and next_holder == 0 and main != held_then:
				next_holder = main
		if ids.all(func(id: int) -> bool: return w.cleared.has(id)):
			break
	print(
		(
			"main holders %s; the returner was ready at %d while %d held main, front waiting: %s"
			% [holders, ready_tick, held_then, front_waiting]
		)
	)
	# A fresh passenger stood ready at the front, yet the returner went next.
	assert_bool(front_waiting).is_true()
	assert_int(next_holder).is_equal(first)
	assert_int(holders.count(first)).is_equal(2)
	assert_bool(ids.all(func(id: int) -> bool: return w.cleared.has(id))).is_true()
	assert_int(w.cleared[first]).is_greater(w.cleared[ids[1]])


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
