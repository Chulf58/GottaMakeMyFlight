class_name TestSecuritySave
extends GdUnitTestSuite
## A save taken at any security phase boundary, at either tier, plays on
## exactly like continuous play (decision security-lane-technical-design-
## one-station-per-lane-with-int, point 4): phase, remaining work, resolved
## incidents, the berth and main position, admission and return order are
## saved, and every tick after the load matches, through JSON.

## [bags, liquids, alarm]: both incidents, back to back, among clean passengers.
const TRAITS := [
	[2, true, false],
	[1, false, true],
	[0, false, false],
	[2, false, false],
	[1, true, true],
]

## Each scheduler-rule case and the words its refusal must give.
const RULE_ERRORS := {
	"a repacking passenger without the berth": "needs the berth it does not hold",
	"main given to a passenger past the arch": "main position",
	"a basic scanner phase at a lane": "phase this tier does not have",
	"repacking with the incident resolved": "repacks with no open incident",
	"mid-scan with the main position free": "main position",
	"a berth at a basic scanner": "one passenger, with no berth",
	"a lane phase at a basic scanner": "phase this tier does not have",
	"two passengers in service": "one passenger, with no berth",
	"admitted and in the lane": "in a queue as well",
	"admitted and in the holding list": "in a queue as well",
	"admitted and the queue's service": "in a queue as well",
	"huge SCAN work": "more work left than its phase starts with",
	"SCAN work one over its start": "more work left than its phase starts with",
	"work in a walking phase": "more work left than its phase starts with",
	"huge REPACK work": "more work left than its phase starts with",
	"REPACK work one over its start": "more work left than its phase starts with",
}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func _json(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))


## The phases on this tick, to spot a boundary.
func _phases(w: SecurityTestWorld) -> String:
	var parts := PackedStringArray()
	for id in w.world.sim.passenger_ids():
		var p := w.world.passenger(id)
		parts.append("%d:%d:%d" % [id, p.stage, p.security_phase])
	return ",".join(parts)


func _check_tier(use_lane: bool) -> void:
	var a := SecurityTestWorld.make(use_lane)
	var ids := a.send_all(TRAITS)
	# Continuous play: the signature on every tick, and a save on every tick
	# a phase or stage changed.
	var trace := {}
	var saves := []
	var seen := {}
	var last := _phases(a)
	var stop := a.world.clock.tick + 3000
	while (
		a.world.clock.tick < stop and not ids.all(func(id: int) -> bool: return a.cleared.has(id))
	):
		a.world.step()
		trace[a.world.sim.tick] = a.signature()
		var now := _phases(a)
		if now != last:
			for id in ids:
				seen[a.world.passenger(id).security_phase] = true
			(
				saves
				. append(
					[
						a.world.sim.tick,
						_json(a.world.clock.to_snapshot()),
						_json(a.world.flights.to_snapshot()),
						_json(a.world.sim.to_snapshot()),
					]
				)
			)
		last = now
	var end := a.world.sim.tick
	assert_bool(ids.all(func(id: int) -> bool: return a.cleared.has(id))).is_true()
	var bad := []
	for save: Array in saves:
		var b := SecurityTestWorld.make(use_lane)
		assert_bool(b.world.clock.from_snapshot(save[1])).is_true()
		assert_bool(b.world.flights.from_snapshot(save[2])).is_true()
		assert_bool(b.world.sim.from_snapshot(save[3])).is_true()
		assert_str(b.signature()).is_equal(trace[save[0]])
		while b.world.clock.tick < end:
			b.world.step()
			if b.signature() != trace[b.world.sim.tick]:
				bad.append([save[0], b.world.sim.tick])
				break
		b.world.free_all()
	print(
		"lane %s: %d saves over phases %s, ticks to %d" % [use_lane, saves.size(), seen.keys(), end]
	)
	(
		assert_array(bad)
		. override_failure_message("[saved at, first differing tick] %s" % [bad])
		. is_empty()
	)
	assert_int(saves.size()).is_greater(10)
	a.world.free_all()


func test_a_save_at_every_basic_scanner_phase_boundary_plays_on_identically() -> void:
	_check_tier(false)


func test_a_save_at_every_lane_phase_boundary_plays_on_identically() -> void:
	_check_tier(true)


func test_a_save_with_inconsistent_security_state_is_refused() -> void:
	var a := SecurityTestWorld.make(true)
	var ids := a.send_all(TRAITS)
	while a.world.passenger(ids[0]).security_phase != SecurityRuntime.Phase.REPACK:
		a.world.step()
	var good := _json(a.world.sim.to_snapshot())
	assert_int(int(good["save_version"])).is_equal(15)
	assert_int(good["security"].size()).is_equal(1)
	var cases := {}
	var no_record: Dictionary = good.duplicate(true)
	no_record["security"] = []
	cases["admitted nowhere"] = no_record
	var stranger: Dictionary = good.duplicate(true)
	stranger["security"][0]["berth"] = 999
	cases["berth to an unknown passenger"] = stranger
	var twice: Dictionary = good.duplicate(true)
	twice["security"].append(twice["security"][0].duplicate(true))
	cases["a repeated station"] = twice
	var phased: Dictionary = good.duplicate(true)
	for record: Dictionary in phased["passengers"]:
		if int(record["stage"]) == Passenger.Stage.SECURITY_QUEUE:
			record["security_phase"] = SecurityRuntime.Phase.UNPACK
			break
	cases["a queued passenger with a phase"] = phased
	var negative: Dictionary = good.duplicate(true)
	negative["passengers"][0]["security_work"] = -1
	cases["negative work"] = negative
	var missing: Dictionary = good.duplicate(true)
	(missing["passengers"][0] as Dictionary).erase("incident_resolved")
	cases["a missing field"] = missing
	var no_key: Dictionary = good.duplicate(true)
	no_key.erase("security")
	cases["no security key"] = no_key
	# The scheduler's rules at a lane: the repacking passenger holds the berth
	# with its incident open, is past the arch and is in no queue.
	var repacker := ids[0]
	var no_berth := _changed(good, func(d: Dictionary) -> void: d["security"][0]["berth"] = 0)
	cases["a repacking passenger without the berth"] = no_berth
	cases["main given to a passenger past the arch"] = _changed(
		good, func(d: Dictionary) -> void: d["security"][0]["main"] = repacker
	)
	cases["a basic scanner phase at a lane"] = _changed(
		good,
		func(d: Dictionary) -> void:
			_record(d, repacker)["security_phase"] = SecurityRuntime.Phase.SCAN
	)
	cases["repacking with the incident resolved"] = _changed(
		good, func(d: Dictionary) -> void: _record(d, repacker)["incident_resolved"] = true
	)
	_add_queue_cases(cases, good, repacker)
	_check_refused(true, a, [good], cases)
	a.world.free_all()


func test_a_basic_scanner_save_that_breaks_its_one_service_is_refused() -> void:
	var a := SecurityTestWorld.make(false)
	var ids := a.send_all(TRAITS)
	# Scanning the first passenger, with another waiting in the lane.
	while not a.admitted.has(ids[0]) or a.world.sim.queue_of(a.station).is_empty():
		a.world.step()
	var good := _json(a.world.sim.to_snapshot())
	var scanning := ids[0]
	assert_int(int(good["security"][0]["main"])).is_equal(scanning)
	var waiting := int(_queue_entry(good)["lane"][0])
	var cases := {}
	# With main free, the next tick would admit the queue front beside it.
	cases["mid-scan with the main position free"] = _changed(
		good, func(d: Dictionary) -> void: d["security"][0]["main"] = 0
	)
	cases["a berth at a basic scanner"] = _changed(
		good, func(d: Dictionary) -> void: d["security"][0]["berth"] = scanning
	)
	cases["a lane phase at a basic scanner"] = _changed(
		good,
		func(d: Dictionary) -> void:
			_record(d, scanning)["security_phase"] = SecurityRuntime.Phase.UNPACK
	)
	cases["two passengers in service"] = _changed(
		good,
		func(d: Dictionary) -> void:
			(_queue_entry(d)["lane"] as Array).erase(float(waiting))
			var record := _record(d, waiting)
			record["stage"] = Passenger.Stage.SECURITY
			record["security_phase"] = SecurityRuntime.Phase.SCAN
			record["security_work"] = SecurityRuntime.BASIC_SCAN_TICKS
			d["security"][0]["admitted"].append(waiting)
	)
	# Scan work never exceeds what the scan started with at these traits.
	var cap := SecurityRuntime.BASIC_SCAN_TICKS + SecurityRuntime.BASIC_BAG_TICKS * TRAITS[0][0]
	cases["huge SCAN work"] = _work(good, scanning, 1000000000)
	cases["SCAN work one over its start"] = _work(good, scanning, cap + 1)
	_add_queue_cases(cases, good, scanning)
	_check_refused(false, a, [good, _work(good, scanning, cap), _work(good, scanning, 0)], cases)
	a.world.free_all()


## Lane work: a walking phase has none, and repack work never exceeds its
## start.
func test_a_lane_save_with_impossible_work_is_refused() -> void:
	var a := SecurityTestWorld.make(true)
	var ids := a.send_all(TRAITS)
	var walking := 0
	while walking == 0:
		a.world.step()
		for id in ids:
			if a.world.passenger(id).security_phase == SecurityRuntime.Phase.ARCH:
				walking = id
	var through := _json(a.world.sim.to_snapshot())
	while a.world.passenger(ids[0]).security_phase != SecurityRuntime.Phase.REPACK:
		a.world.step()
	var repacking := _json(a.world.sim.to_snapshot())
	var cases := {}
	cases["work in a walking phase"] = _work(through, walking, 1)
	cases["huge REPACK work"] = _work(repacking, ids[0], 1000000000)
	cases["REPACK work one over its start"] = _work(
		repacking, ids[0], SecurityRuntime.REPACK_TICKS + 1
	)
	var at_cap := _work(repacking, ids[0], SecurityRuntime.REPACK_TICKS)
	_check_refused(true, a, [repacking, at_cap], cases)
	a.world.free_all()


## A copy of `data` with passenger `id`'s remaining security work set.
func _work(data: Dictionary, id: int, work: int) -> Dictionary:
	return _changed(data, func(d: Dictionary) -> void: _record(d, id)["security_work"] = work)


## An admitted passenger also put in the queue, the holding list or the
## queue's service.
func _add_queue_cases(cases: Dictionary, good: Dictionary, admitted: int) -> void:
	cases["admitted and in the lane"] = _changed(
		good, func(d: Dictionary) -> void: _queue_entry(d)["lane"].append(admitted)
	)
	cases["admitted and in the holding list"] = _changed(
		good, func(d: Dictionary) -> void: _queue_entry(d)["holding"].append(admitted)
	)
	cases["admitted and the queue's service"] = _changed(
		good, func(d: Dictionary) -> void: _queue_entry(d)["serving"] = admitted
	)


func _check_refused(
	use_lane: bool, a: SecurityTestWorld, accepted: Array, cases: Dictionary
) -> void:
	var b := SecurityTestWorld.make(use_lane)
	b.world.clock.from_snapshot(_json(a.world.clock.to_snapshot()))
	b.world.flights.from_snapshot(_json(a.world.flights.to_snapshot()))
	var before := b.signature()
	for name: String in cases:
		(
			assert_bool(b.world.sim.from_snapshot(cases[name]))
			. override_failure_message(name)
			. is_false()
		)
		assert_str(b.signature()).is_equal(before)
		# A scheduler-rule case is refused for that rule, not something else.
		if RULE_ERRORS.has(name):
			var problem: String = PassengerSnapshot.load(cases[name], b.world.grid).get("error", "")
			assert_str(problem).override_failure_message("%s: %s" % [name, problem]).contains(
				RULE_ERRORS[name]
			)
	for good: Dictionary in accepted:
		assert_bool(b.world.sim.from_snapshot(good)).is_true()
	b.world.free_all()


## A deep copy of `data` with `change` applied.
func _changed(data: Dictionary, change: Callable) -> Dictionary:
	var out := data.duplicate(true)
	change.call(out)
	return out


func _record(data: Dictionary, id: int) -> Dictionary:
	for record: Dictionary in data["passengers"]:
		if int(record["id"]) == id:
			return record
	return {}


## The queue entry of the save's one security station.
func _queue_entry(data: Dictionary) -> Dictionary:
	var station := int(data["security"][0]["station"])
	for entry: Dictionary in data["queues"]:
		if int(entry["station"]) == station:
			return entry
	return {}
