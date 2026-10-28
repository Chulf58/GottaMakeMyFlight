class_name TestSecurityHelperRate
extends GdUnitTestSuite
## A helper officer on duty at a security lane speeds up its repacks (ruling
## security-lane-staffing-one-officer-opens-a-lane-and-a-second):
## SecurityRuntime.rate() is HELPER_RATE for REPACK work while the helper is
## on duty, applied to the remaining work each tick, so a helper who leaves
## mid-repack only slows what is left. The forecast replays the same rate, and
## a save taken mid-repack plays on identically.

const PRIMARY := StaffMember.Slot.PRIMARY
const HELPER := StaffMember.Slot.HELPER
const REPACK := SecurityRuntime.Phase.REPACK

var _worlds: Array[SecurityTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for w in _worlds:
		w.world.free_all()
	_worlds.clear()


## A lane with its primary seated, and a helper when `helped`; no automatic
## staffing.
func _lane(helped: bool) -> SecurityTestWorld:
	var w := SecurityTestWorld.make(true)
	w.world.auto_staff = false
	_worlds.append(w)
	StaffTestKit.seat(w.world.staff, w.station, PRIMARY)
	if helped:
		StaffTestKit.seat(w.world.staff, w.station, HELPER)
	return w


## Steps until passenger `id` is in `phase`; returns whether it got there.
func _until_phase(w: SecurityTestWorld, id: int, phase: int, limit := 2000) -> bool:
	var stop := w.world.clock.tick + limit
	while w.world.clock.tick < stop:
		if w.world.passenger(id).security_phase == phase:
			return true
		w.world.step()
	return false


## Ticks passenger `id` spends in REPACK, from the tick it starts.
func _repack_ticks(w: SecurityTestWorld, id: int) -> int:
	assert_bool(_until_phase(w, id, REPACK)).is_true()
	var ticks := 0
	while w.world.passenger(id).security_phase == REPACK and ticks < 1000:
		ticks += 1
		w.world.step()
	return ticks


func test_a_helper_halves_a_repack_at_a_lane() -> void:
	var alone := _lane(false)
	var helped := _lane(true)
	assert_bool(helped.world.staff.is_staffed(helped.station, HELPER)).is_true()
	var slow := _repack_ticks(alone, alone.send(1, true))
	var fast := _repack_ticks(helped, helped.send(1, false, true))
	print("repack ticks: alone %d, helped %d" % [slow, fast])
	assert_int(slow).is_equal(SecurityRuntime.REPACK_TICKS)
	@warning_ignore("integer_division")
	assert_int(fast).is_equal(SecurityRuntime.REPACK_TICKS / SecurityRuntime.HELPER_RATE)
	# Only repack work is helped: the unpack of a passenger with no incident
	# takes as long with a helper as without.
	(
		assert_int(helped.world.sim.security.rate(helped.station, SecurityRuntime.Phase.UNPACK))
		. is_equal(1)
	)


func test_a_helper_leaving_mid_repack_slows_only_the_work_left() -> void:
	var w := _lane(true)
	var id := w.send(0, true)
	assert_bool(_until_phase(w, id, REPACK)).is_true()
	var p := w.world.passenger(id)
	for i in 10:
		w.world.step()
	var before := p.security_work
	assert_int(before).is_equal(SecurityRuntime.REPACK_TICKS - 10 * SecurityRuntime.HELPER_RATE)
	# Firing lets the helper go first; it walks out and stops helping at once.
	assert_bool(w.world.staff.fire(StaffMember.Role.SECURITY)).is_true()
	assert_bool(w.world.staff.is_staffed(w.station, HELPER)).is_false()
	assert_bool(w.world.staff.is_open(w.station)).is_true()
	w.world.step()
	print("work before the helper left %d, a tick later %d" % [before, p.security_work])
	assert_int(p.security_work).is_equal(before - 1)
	var rest := 1
	while p.security_phase == REPACK and rest < 1000:
		w.world.step()
		rest += 1
	assert_int(rest).is_equal(before)


func test_the_forecast_replays_the_helper_rate() -> void:
	var w := _lane(true)
	var id := w.send(2, true)
	assert_bool(_until_phase(w, id, REPACK)).is_true()
	var now := w.world.clock.tick
	var eta := SecurityForecast.eta(w.world.sim, w.world.passenger(id))
	assert_bool(w.run_until_cleared([id])).is_true()
	print("forecast %d, measured %d" % [eta, int(w.cleared[id]) - now])
	assert_int(int(w.cleared[id]) - now).is_equal(eta)


## A helper still walking to its post when the forecast is taken arrives
## mid-repack; the replay switches to HELPER_RATE on the tick the runtime
## does.
func test_the_forecast_counts_a_helper_arriving_mid_repack() -> void:
	var w := _lane(false)
	var id := w.send(0, true)
	assert_bool(_until_phase(w, id, REPACK)).is_true()
	var helper := StaffTestKit.send_helper(w.world.staff, w.station, Vector2i(1, 4))
	var now := w.world.clock.tick
	var eta := SecurityForecast.eta(w.world.sim, w.world.passenger(id))
	var arrived := -1
	while not w.cleared.has(id) and w.world.clock.tick < now + 2000:
		w.world.step()
		var m := w.world.staff.get_member(helper)
		if arrived < 0 and m.state == StaffMember.State.ON_DUTY:
			arrived = w.world.clock.tick
			# On the tick it arrives the repack is still running.
			assert_int(w.world.passenger(id).security_phase).is_equal(REPACK)
	print(
		(
			"helper on duty at %d (forecast at %d), forecast %d, measured %d"
			% [arrived, now, eta, int(w.cleared.get(id, -1)) - now]
		)
	)
	# The helper arrived while the repack was still running, so it counted.
	assert_int(arrived).is_greater(now)
	assert_int(arrived - now).is_less(SecurityRuntime.REPACK_TICKS)
	assert_bool(w.cleared.has(id)).is_true()
	assert_int(int(w.cleared[id]) - now).is_equal(eta)


func test_a_save_mid_repack_with_a_helper_plays_on_identically() -> void:
	var a := _lane(true)
	var id := a.send(1, false, true)
	assert_bool(_until_phase(a, id, REPACK)).is_true()
	for i in 7:
		a.world.step()
	var text := (
		JSON
		. stringify(
			{
				"clock": a.world.clock.to_snapshot(),
				"flights": a.world.flights.to_snapshot(),
				"passengers": a.world.sim.to_snapshot(),
				"staff": a.world.staff.to_snapshot(),
			}
		)
	)
	var data: Dictionary = JSON.parse_string(text)
	var b := SecurityTestWorld.make(true)
	b.world.auto_staff = false
	_worlds.append(b)
	assert_bool(b.world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(b.world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(b.world.sim.from_snapshot(data["passengers"])).is_true()
	assert_bool(b.world.staff.from_snapshot(data["staff"])).is_true()
	assert_bool(b.world.staff.is_staffed(b.station, HELPER)).is_true()
	assert_int(b.world.passenger(id).security_work).is_equal(a.world.passenger(id).security_work)
	var ticks := 0
	while not a.cleared.has(id) and ticks < 2000:
		a.world.step()
		b.world.step()
		ticks += 1
		assert_str(b.signature()).is_equal(a.signature())
		assert_str(StaffTestKit.signature(b.world.staff)).is_equal(
			StaffTestKit.signature(a.world.staff)
		)
	print("cleared at %s and %s" % [a.cleared.get(id), b.cleared.get(id)])
	assert_bool(a.cleared.has(id)).is_true()
	assert_int(int(b.cleared[id])).is_equal(int(a.cleared[id]))
