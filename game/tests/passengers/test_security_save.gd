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

var _lanes_were := false


func before() -> void:
	PassengerTestWorld.tracker = self
	_lanes_were = SecurityLanes.enabled
	SecurityLanes.enabled = true


func after() -> void:
	PassengerTestWorld.tracker = null
	SecurityLanes.enabled = _lanes_were


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
	assert_int(int(good["save_version"])).is_equal(8)
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
	var b := SecurityTestWorld.make(true)
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
	assert_bool(b.world.sim.from_snapshot(good)).is_true()
	a.world.free_all()
	b.world.free_all()
