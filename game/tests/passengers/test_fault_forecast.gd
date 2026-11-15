class_name TestFaultForecast
extends GdUnitTestSuite
## SecurityForecast across a scanner fault (decision scanner-fault-incident-
## design-stationfaults-beside-stationcl): the replay sends the faulted
## station's queue and walkers to choose again on the next tick, as the sim
## does, and reopens it on its repair tick before anything else of that tick.
## On the two-scanner burst of TestHoldLineForecast (a late flight, so nobody
## turns late), every forecast made right after the fault (F), on the next
## tick (F+1), the tick before the repair (R-1), on the repair tick (R) and
## every EVERY ticks between and after equals the measured clearance; the same
## holds when only walkers, nobody queued, are committed to the faulted
## scanner; and the skipped replay ticks change no forecast against
## SecurityForecast.every_tick.

## Just checked in, between the desks and the scanner lanes (CafeTestLayout).
const CROWD_CELL := Vector2i(16, 12)
## More than both scanners' lines hold together.
const BURST := 32
## The fault lasts this long, set directly (StationFaults.add()).
const FAULT_TICKS := 300
## How often the stream is forecast besides F, F+1, R-1 and R.
const EVERY := 100
## The most waiting passengers forecast on one tick (each is its own replay).
const SEEKERS := 3

var _world: PassengerTestWorld
var _sim: PassengerSim
var _ids: Array[int] = []
## Passenger id -> the tick it was cleared, and the station it was admitted at.
var _cleared := {}
var _admitted_at := {}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	SecurityForecast.every_tick = false
	if _world != null:
		_world.free_all()
	_world = null
	_ids.clear()
	_cleared.clear()
	_admitted_at.clear()


func _make_world() -> void:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(3000))
	_sim = _world.sim


func _checked_in() -> Passenger:
	var p := _world.passenger(_sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	p.stage = Passenger.Stage.TO_SECURITY
	p.service_end = _world.clock.tick
	p.at = CROWD_CELL
	p.clear_path()
	_ids.append(p.id)
	return p


## One tick, noting who was admitted where and who was cleared.
func _step() -> void:
	_world.step()
	for id in _ids:
		var p := _sim.get_passenger(id)
		if p == null:
			continue
		if p.stage == Passenger.Stage.SECURITY and not _admitted_at.has(id):
			_admitted_at[id] = [p.station, _sim.tick]
		if p.stage == Passenger.Stage.TO_GATE and not _cleared.has(id):
			_cleared[id] = _sim.tick


## Every forecast of the passengers at security now: key -> forecast
## clearance tick. The committed ones come from one replay per station
## (SecurityForecast.clearances()), up to SEEKERS waiting ones from their own.
func _forecasts() -> Dictionary:
	var out := {}
	for station: int in _sim.layout.scanners:
		var ids := []
		for p in _sim._passengers:
			var at_security := (
				p.stage
				in [
					Passenger.Stage.TO_SECURITY,
					Passenger.Stage.SECURITY_QUEUE,
					Passenger.Stage.SECURITY,
				]
			)
			if at_security and p.station == station:
				ids.append(p.id)
		var some := SecurityForecast.clearances(_sim, station, ids)
		for id: int in some:
			out[id] = _sim.tick + int(some[id])
	var seekers := 0
	for p in _sim._passengers:
		if seekers >= SEEKERS or not PassengerStations.is_seeking(_sim, p, false):
			continue
		seekers += 1
		SecurityForecast._waiting_memo = []
		var first: int = _sim.layout.scanners[0]
		out[p.id] = _sim.tick + SecurityForecast.clearance(_sim, first, p, _sim.tick + 1)
	return out


## Plays until every passenger is cleared, forecasting on `at_ticks` and every
## EVERY ticks: [[tick, id, forecast clearance tick], ...].
func _play(at_ticks: Array) -> Array:
	var out := []
	for i in 6000:
		if _cleared.size() == _ids.size():
			break
		if at_ticks.has(_sim.tick) or _sim.tick % EVERY == 0:
			var made := _forecasts()
			for id: int in made:
				out.append([_sim.tick, id, made[id]])
		_step()
	return out


## The forecasts that missed: each entry plus the measured clearance.
func _wrong(forecasts: Array) -> Array:
	var wrong := []
	for entry: Array in forecasts:
		if entry[2] != _cleared.get(entry[1], -1):
			wrong.append(entry + [_cleared.get(entry[1], -1)])
	return wrong


## The ids committed to `station` now: queued, holding or walking to it.
func _committed(station: int) -> Array[int]:
	var out: Array[int] = []
	for id in _ids:
		var p := _sim.get_passenger(id)
		var stages := [Passenger.Stage.TO_SECURITY, Passenger.Stage.SECURITY_QUEUE]
		if p != null and p.station == station and stages.has(p.stage):
			out.append(id)
	return out


func _check(forecasts: Array, faulted: int, fault: int, repair: int, sent: Array[int]) -> void:
	var wrong := _wrong(forecasts)
	var at_key := 0
	var early_to_faulted := 0
	var admitted_during := 0
	var admitted_after := 0
	for entry: Array in forecasts:
		at_key += int([fault, fault + 1, repair - 1, repair].has(entry[0]))
		var admitted: Array = _admitted_at.get(entry[1], [0, -1])
		if entry[0] < repair and admitted[0] == faulted and admitted[1] >= repair:
			early_to_faulted += 1
	for id: int in _admitted_at:
		var admitted: Array = _admitted_at[id]
		if admitted[0] == faulted and admitted[1] > fault and admitted[1] < repair:
			admitted_during += 1
		if admitted[0] == faulted and admitted[1] >= repair:
			admitted_after += 1
	var sent_elsewhere := sent.filter(
		func(id: int) -> bool: return _admitted_at.get(id, [0, -1])[0] != faulted
	)
	print(
		(
			(
				"fault %d to %d: %d forecasts (%d on F, F+1, R-1, R), %d before R for one later"
				% [fault, repair, forecasts.size(), at_key, early_to_faulted]
			)
			+ (
				" admitted at the faulted scanner; admitted there during %d, after %d;"
				% [admitted_during, admitted_after]
			)
			+ (
				" sent away %s, admitted elsewhere %s; %d wrong"
				% [sent, sent_elsewhere, wrong.size()]
			)
		)
	)
	assert_int(_cleared.size()).is_equal(_ids.size())
	assert_int(sent.size()).is_greater(0)
	assert_int(sent_elsewhere.size()).is_greater(0)
	assert_int(at_key).is_greater(0)
	# The fault held, and the repair was engaged and forecast before it came.
	assert_int(admitted_during).is_zero()
	assert_int(admitted_after).is_greater(0)
	assert_int(early_to_faulted).is_greater(0)
	(
		assert_array(wrong)
		. override_failure_message("[tick, id, forecast, measured] %s" % [wrong])
		. is_empty()
	)


func test_the_forecast_equals_the_sim_across_a_fault_and_its_repair() -> void:
	_make_world()
	for i in BURST:
		_checked_in()
	var faulted := 0
	for i in 400:
		_step()
		var queued := _sim.queue_of(_sim.layout.scanners[0]).size()
		if queued >= 2 and _sim.layout.scanners.all(_sim._is_open):
			faulted = _sim.layout.scanners[0]
			break
	assert_int(faulted).is_not_zero()
	var fault := _sim.tick
	var repair := fault + FAULT_TICKS
	var sent := _committed(faulted)
	assert_bool(_world.staff.faults.add(faulted, repair)).is_true()
	var forecasts := _play([fault, fault + 1, repair - 1, repair])
	_check(forecasts, faulted, fault, repair, sent)


func test_the_forecast_equals_the_sim_when_only_walkers_were_committed() -> void:
	_make_world()
	# Staffed first, so the walkers choose between two open scanners.
	_step()
	for i in 6:
		_checked_in()
	_step()
	var faulted := 0
	for station: int in _sim.layout.scanners:
		var lined := _sim.queue_of(station).size() + _sim.holding_of(station).size()
		if lined == 0 and not _committed(station).is_empty():
			faulted = station
			break
	assert_int(faulted).is_not_zero()
	var sent := _committed(faulted)
	for id in sent:
		assert_int(_sim.get_passenger(id).stage).is_equal(Passenger.Stage.TO_SECURITY)
	# More arrive behind them, so some wait for the repair.
	for i in BURST - 6:
		_checked_in()
	var fault := _sim.tick
	var repair := fault + FAULT_TICKS
	assert_bool(_world.staff.faults.add(faulted, repair)).is_true()
	var forecasts := _play([fault, fault + 1, repair - 1, repair])
	_check(forecasts, faulted, fault, repair, sent)


func test_skipped_ticks_change_no_forecast_across_a_fault() -> void:
	_make_world()
	for i in BURST:
		_checked_in()
	for i in 120:
		_step()
	var faulted: int = _sim.layout.scanners[0]
	var fault := _sim.tick
	var repair := fault + FAULT_TICKS
	assert_bool(_world.staff.faults.add(faulted, repair)).is_true()
	var wrong := []
	var compared := 0
	var waits := 0
	for i in FAULT_TICKS + 2 * EVERY:
		if [fault, fault + 1, repair - 1, repair].has(_sim.tick) or _sim.tick % EVERY == 0:
			var before := SecurityForecast.steps_played
			var skipping := _forecasts()
			var mid := SecurityForecast.steps_played
			SecurityForecast.every_tick = true
			var every := _forecasts()
			SecurityForecast.every_tick = false
			waits += int(mid - before < SecurityForecast.steps_played - mid)
			for id: int in every:
				compared += 1
				if skipping.get(id, -1) != every[id]:
					wrong.append([_sim.tick, id, skipping.get(id, -1), every[id]])
		_step()
	print("%d forecasts compared, skipping played fewer ticks on %d rounds" % [compared, waits])
	assert_int(compared).is_greater(0)
	assert_int(waits).is_greater(0)
	(
		assert_array(wrong)
		. override_failure_message("[tick, id, skipping, every tick] %s" % [wrong])
		. is_empty()
	)


## A loaded fault whose repair tick is at the clock (StationFaults.checked()
## accepts it; the next StaffSim.step() clears it): a forecast taken before
## that step treats the station as open from the next tick (nobody sent away, no
## wake behind the replay's own tick), and equals the measured clearance of
## everyone committed to it.
func test_the_forecast_equals_the_sim_when_a_loaded_fault_is_already_due() -> void:
	_make_world()
	for i in BURST:
		_checked_in()
	var faulted := 0
	for i in 400:
		_step()
		var queued := _sim.queue_of(_sim.layout.scanners[0]).size()
		if queued >= 2 and _sim.layout.scanners.all(_sim._is_open):
			faulted = _sim.layout.scanners[0]
			break
	assert_int(faulted).is_not_zero()
	var due := _sim.tick
	var committed := _committed(faulted)
	# What a load leaves: the fault is in, its repair tick is the clock's.
	_world.staff.faults.assign([[faulted, due]])
	assert_bool(_world.staff.is_open(faulted)).is_false()
	var forecasts := _forecasts()
	_step()
	# The control: the next step repaired it, so it admitted again from tick + 1.
	assert_bool(_world.staff.faults.is_faulted(faulted)).is_false()
	assert_bool(_world.staff.is_open(faulted)).is_true()
	assert_int(_sim.tick).is_equal(due + 1)
	for i in 6000:
		if _cleared.size() == _ids.size():
			break
		_step()
	var wrong := []
	for id: int in forecasts:
		if forecasts[id] != _cleared.get(id, -1):
			wrong.append([id, forecasts[id], _cleared.get(id, -1)])
	print(
		(
			"due fault at %d: %d forecasts, %d committed to it, %d wrong %s"
			% [due, forecasts.size(), committed.size(), wrong.size(), wrong]
		)
	)
	assert_int(_cleared.size()).is_equal(_ids.size())
	assert_int(committed.size()).is_greater(0)
	assert_int(forecasts.size()).is_greater(0)
	assert_array(wrong).override_failure_message("[id, forecast, measured] %s" % [wrong]).is_empty()
