class_name TestDeskForecastPace
extends GdUnitTestSuite
## The desk forecasts count a late passenger at a run (board b13ac401, the
## pace the sim gives it, Passenger.pace_mm()): a late passenger choosing a
## desk is forecast its run there (PassengerSim.station_eta()),
## and the front behind a late roller leaver waits the leaver's run of
## QueueRipple.FRONT_CLEAR_MM in its forecast (wait_ticks()). Before, both
## counted a walk.

const DESK_AT := Vector2i(3, 1)
const SCANNER_AT := Vector2i(8, 6)
## Doors close soon after the passengers are sent, so they are late and run.
const BOARDING := 20
const DOORS := 300
const RUN_LIMIT := 280

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for w in _worlds:
		w.free_all()
	_worlds.clear()


## One desk with its lane, a scanner past it and the doors; the flight closes
## its doors at DOORS.
func _world(doors := DOORS) -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(Vector2i(12, 16))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(5, 15), 2)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(8, 0), 0)
	PassengerTestWorld.place(grid, &"checkin_desk", DESK_AT, 0)
	PassengerTestWorld.place(grid, &"security_scanner", SCANNER_AT, 0)
	var w := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(BOARDING, doors))
	_worlds.append(w)
	return w


## A calm passenger walking in to check in from `at`, late when `late`, with a
## roller when `roller` (else no bag). Returns it.
func _send(w: PassengerTestWorld, roller: bool, at: Vector2i, late := true) -> Passenger:
	for attempt in 50:
		var p := w.passenger(w.sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.carry_on = 1
		if QueueRipple.pulls_roller(p) != roller:
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
		p.late = late
		p.stage = Passenger.Stage.TO_CHECKIN
		p.at = at
		p.clear_path()
		return p
	return null


## Steps `w` until `p` has checked in; returns that tick, or -1. Counts in
## `off` the ticks on which `p` was not as late as `late`.
func _checked_in(w: PassengerTestWorld, p: Passenger, late: bool, off: Array) -> int:
	var stop := w.clock.tick + RUN_LIMIT
	while w.clock.tick < stop:
		if p.stage >= Passenger.Stage.TO_SECURITY:
			return w.clock.tick
		if p.late != late:
			off[0] += 1
		w.step()
	return -1


## The desk model counts the walk to the lane and the service but not the tick
## of joining and being called, so a forecast made as a passenger chooses its
## desk misses by the same ticks for a walker and for a late runner: the run is
## in it. Before, a runner was forecast its walk at a walk (47 ticks late here).
func test_a_late_passenger_choosing_a_desk_is_forecast_its_run() -> void:
	var misses := []
	for late in [false, true]:
		var w := _world(DOORS if late else 6000)
		w.run_to(5)
		var p := _send(w, false, Vector2i(5, 12), late)
		var desk: int = w.sim.layout.desks[0]
		var cells: Array = w.sim.layout.lanes[desk]
		var walk := Passenger.path_mm(w.sim.grid.find_path(p.at, cells[0]))
		var forecast := w.sim.tick + w.sim.station_eta(desk, walk, p)
		var off := [0]
		var actual := _checked_in(w, p, late, off)
		print(
			(
				"late %s: walk %d mm, forecast done %d, checked in %d, ticks off pace %d"
				% [late, walk, forecast, actual, off[0]]
			)
		)
		assert_int(off[0]).is_equal(0)
		assert_int(actual).is_greater(0)
		misses.append(actual - forecast)
	assert_int(misses[1]).is_equal(misses[0])


## The desk model leaves out the front's own walk up to the desk, so its
## forecast misses by that walk with or without a roller ahead (as in
## test_queue_ripple); behind a late roller leaver it misses by the same ticks
## as behind a late leaver with no roller: the leaver's clearing run is in it.
func test_a_late_front_waits_the_late_roller_leavers_run_in_its_forecast() -> void:
	var misses := []
	for roller in [false, true]:
		var w := _world()
		w.run_to(5)
		var leaver := _send(w, roller, Vector2i(3, 4))
		w.step()
		var front := _send(w, false, Vector2i(3, 6))
		var forecast := -1
		var not_late := 0
		var stop := w.clock.tick + RUN_LIMIT
		while w.clock.tick < stop and front.stage < Passenger.Stage.TO_SECURITY:
			if forecast < 0 and leaver.stage == Passenger.Stage.CHECKIN:
				forecast = w.sim.tick + w.sim.wait_ticks(front)
			if not (leaver.late and front.late):
				not_late += 1
			w.step()
		var actual := w.clock.tick if front.stage >= Passenger.Stage.TO_SECURITY else -1
		print(
			(
				"roller %s: forecast front done %d, checked in %d, ticks not late %d"
				% [roller, forecast, actual, not_late]
			)
		)
		assert_int(not_late).is_equal(0)
		assert_int(forecast).is_greater(0)
		assert_int(actual).is_greater(0)
		misses.append(actual - forecast)
	assert_int(misses[1]).is_equal(misses[0])
