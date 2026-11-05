class_name TestQueueRipple
extends GdUnitTestSuite
## A desk or security lane moves up in a ripple (QueueRipple, board 34b0c378):
## a walker steps up only once the walker ahead pulling a roller has stood
## still long enough for the roller to be stood up beside it, a desk front
## steps onto the desk cell only once the roller leaver has walked clear, and
## the forecasts count both waits. Checked by behaviour only (set-off and
## arrival ticks, walk lengths), so a build without the ripple fails here.

const DESK_AT := Vector2i(3, 1)
const SCANNER_AT := Vector2i(8, 6)
## RollerPark.STILL_TICKS + QUEUE_STAND_TICKS (9.5) rounded up.
const STAND_TICKS := 10
const FRONT_CLEAR_MM := 1000
const RUN_LIMIT := 2500

var _worlds: Array = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for w in _worlds:
		if w is SecurityTestWorld:
			(w as SecurityTestWorld).world.free_all()
		else:
			(w as PassengerTestWorld).free_all()
	_worlds.clear()


## One desk with its lane, a scanner past it and the doors.
func _desk_world() -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(Vector2i(12, 16))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(5, 15), 2)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(8, 0), 0)
	PassengerTestWorld.place(grid, &"checkin_desk", DESK_AT, 0)
	PassengerTestWorld.place(grid, &"security_scanner", SCANNER_AT, 0)
	var w := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(3000, 6000))
	_worlds.append(w)
	return w


static func _roller(p: Passenger) -> bool:
	for i in p.carry_on:
		if SecurityLooks.bag_kind(p, i) == SecurityLooks.Kind.ROLLER:
			return true
	return false


## Spawns a calm passenger walking in to check in, with one bag, a roller when
## `roller` (else none): passengers whose first bag is not the kind asked for
## are settled at once and left out. It starts on `at`, or at the entrance.
## Returns its id.
func _send(w: PassengerTestWorld, roller: bool, at := Vector2i(-1, -1)) -> int:
	for attempt in 50:
		var id := w.sim.spawn_now(PassengerTestWorld.FLIGHT)
		var p := w.passenger(id)
		p.carry_on = 1
		if _roller(p) != roller:
			p.carry_on = 0
			p.stage = Passenger.Stage.MADE
			continue
		if not roller:
			p.carry_on = 0
		p.hunger = 0
		p.liquids = false
		p.alarm = false
		p.apron = []
		p.apron_mm = 0
		p.stage = Passenger.Stage.TO_CHECKIN
		if at.x >= 0:
			p.at = at
		p.clear_path()
		return id
	return 0


## Steps `w` until `done` holds or RUN_LIMIT ticks pass, calling `watch` each
## tick after the step.
func _run(w: PassengerTestWorld, watch: Callable, done: Callable) -> void:
	var stop := w.clock.tick + RUN_LIMIT
	while w.clock.tick < stop and not done.call():
		w.step()
		watch.call()


## Lane move-ups at `station` of `sim`, watched tick by tick: each set-off of
## a lane member (not moving to moving) with the member ahead of it and the
## tick that one last arrived; also each arrival.
class MoveUps:
	var sim: PassengerSim
	var station := 0
	var moving := {}
	var arrived := {}
	## [tick, id, ahead id or 0, ahead moving, ahead's last arrival tick].
	var setoffs: Array = []

	func watch() -> void:
		var lane := sim.queue_of(station)
		for i in lane.size():
			var p := sim.get_passenger(lane[i])
			var now := p.is_moving()
			if now and not moving.get(p.id, false) and i > 0:
				var ahead := sim.get_passenger(lane[i - 1])
				setoffs.append(
					[sim.tick, p.id, ahead.id, ahead.is_moving(), arrived.get(ahead.id, -1)]
				)
			if not now and moving.get(p.id, false):
				arrived[p.id] = sim.tick
			moving[p.id] = now


func test_a_lane_walker_steps_up_once_the_roller_ahead_is_stood() -> void:
	var w := _desk_world()
	var desk: int = w.sim.layout.desks[0]
	var ids: Array[int] = []
	for i in 4:
		ids.append(_send(w, true))
		w.run_to(w.clock.tick + 3)
	var ups := MoveUps.new()
	ups.sim = w.sim
	ups.station = desk
	_run(w, ups.watch, func() -> bool: return ups.setoffs.size() >= 4)
	print(
		(
			"lane %s setoffs [tick, id, ahead, ahead moving, ahead arrived] %s"
			% [w.sim.layout.lanes[desk], ups.setoffs]
		)
	)
	assert_int(ups.setoffs.size()).is_greater_equal(4)
	for entry: Array in ups.setoffs:
		# The walker ahead stands still on its place, its roller stood up.
		assert_bool(entry[3]).is_false()
		assert_int(entry[4]).is_greater_equal(0)
		assert_int(entry[0] - entry[4]).is_greater_equal(STAND_TICKS)


func test_a_lane_walker_behind_a_walker_without_a_roller_steps_up_at_once() -> void:
	var w := _desk_world()
	var desk: int = w.sim.layout.desks[0]
	for i in 4:
		_send(w, false)
		w.run_to(w.clock.tick + 3)
	var ups := MoveUps.new()
	ups.sim = w.sim
	ups.station = desk
	_run(w, ups.watch, func() -> bool: return ups.setoffs.size() >= 3)
	print("setoffs without rollers %s" % [ups.setoffs])
	assert_int(ups.setoffs.size()).is_greater_equal(3)
	# Not held: some walker sets off while the one ahead is still walking.
	assert_bool(ups.setoffs.any(func(e: Array) -> bool: return e[3])).is_true()


func test_the_desk_front_waits_for_the_roller_leaver_to_walk_clear() -> void:
	var w := _desk_world()
	var desk: int = w.sim.layout.desks[0]
	var cells: Array = w.sim.layout.lanes[desk]
	var leaver := _send(w, true, Vector2i(3, 4))
	w.step()
	var front := _send(w, false, Vector2i(3, 6))
	var left := {}
	var seen := {}
	var watch := func() -> void:
		var l := w.passenger(leaver)
		if not left.has("tick") and l.stage == Passenger.Stage.TO_SECURITY:
			left["tick"] = w.clock.tick
		var f := w.passenger(front)
		if left.has("tick") and not seen.has("tick") and f.is_moving():
			seen["tick"] = w.clock.tick
			seen["from"] = l.path[0]
			seen["walked"] = Passenger.path_mm(l.path) - l.remaining_mm()
	_run(w, watch, func() -> bool: return seen.has("tick"))
	print("lane %s leaver %d left %s, front %d set off %s" % [cells, leaver, left, front, seen])
	assert_bool(seen.has("tick")).is_true()
	assert_that(seen["from"]).is_equal(cells[0])
	# Walked clear, by one tick of walking more when it stepped after the front.
	assert_int(int(seen["walked"])).is_greater_equal(FRONT_CLEAR_MM)
	assert_int(int(seen["walked"])).is_less(FRONT_CLEAR_MM + 2 * PassengerSim.WALK_MM)


## The forecast of the passenger behind the one served misses its real
## service end by the same ticks whether the one served pulls a roller or not:
## the front's wait on a roller leaver is in it.
func test_the_desk_forecast_counts_the_wait_on_a_roller_leaver() -> void:
	var misses := []
	for roller in [false, true]:
		var w := _desk_world()
		var first := _send(w, roller, Vector2i(3, 4))
		w.step()
		var second := _send(w, false, Vector2i(3, 6))
		var forecast := {}
		var watch := func() -> void:
			var a := w.passenger(first)
			if not forecast.has("end") and a.stage == Passenger.Stage.CHECKIN:
				forecast["end"] = w.clock.tick + w.sim.wait_ticks(w.passenger(second))
		_run(
			w,
			watch,
			func() -> bool: return w.passenger(second).stage == Passenger.Stage.TO_SECURITY
		)
		var served := w.clock.tick
		print("roller %s forecast end %s served %d" % [roller, forecast, served])
		assert_bool(forecast.has("end")).is_true()
		misses.append(served - int(forecast["end"]))
	assert_int(misses[1]).is_equal(misses[0])


## SecurityForecast replays the ripple: read between ticks it equals the tick
## each passenger is cleared, and a ripple wait did happen in the run.
func test_the_security_forecast_is_exact_behind_a_ripple() -> void:
	var s := SecurityTestWorld.make(false)
	_worlds.append(s)
	var ids: Array[int] = []
	while ids.size() < 6:
		var id := s.send(1)
		var p := s.world.passenger(id)
		if not _roller(p):
			p.carry_on = 0
			p.stage = Passenger.Stage.MADE
			continue
		ids.append(id)
		s.world.run_to(s.world.clock.tick + 6)
	var ups := MoveUps.new()
	ups.sim = s.world.sim
	ups.station = s.station
	var wrong := []
	var checked := 0
	var etas := {}
	while not ids.all(func(id: int) -> bool: return s.cleared.has(id)):
		for id in ids:
			var p := s.world.passenger(id)
			if p.station != s.station or s.cleared.has(id):
				continue
			var eta := SecurityForecast.eta(s.world.sim, p)
			checked += 1
			if eta < JourneyForecast.NEVER:
				(etas.get_or_add(id, []) as Array).append(s.world.sim.tick + eta)
		s.world.step()
		ups.watch()
		assert_int(s.world.clock.tick).is_less(20000)
	for id: int in etas:
		for at: int in etas[id]:
			if at != s.cleared[id]:
				wrong.append([id, at, s.cleared[id]])
	var held := ups.setoffs.filter(
		func(e: Array) -> bool:
			return _roller(s.world.passenger(e[2])) and e[0] - e[4] >= STAND_TICKS
	)
	print(
		(
			"forecasts %d, wrong %s; setoffs %s; held by a roller %d"
			% [checked, wrong.slice(0, 5), ups.setoffs, held.size()]
		)
	)
	assert_int(checked).is_greater(100)
	assert_array(wrong).is_empty()
	assert_int(held.size()).is_greater(0)
