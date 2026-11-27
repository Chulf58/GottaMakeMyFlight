class_name BinDetour
extends RefCounted
## Short, forecast-safe trash-bin detour for passengers leaving a litter-producing
## cafe or kiosk visit (`MessSim.BIN_DETOUR_RANGE`, `MessSim.BIN_TOSS_TICKS`).
## Never triggers if the detour and extra slack could risk missing the flight.


static func plan_from(
	sim: PassengerSim,
	p: Passenger,
	spot: Vector2i,
	resume: Passenger.Stage,
	extra_delay: int = 0,
) -> Dictionary:
	if sim == null or sim.messes == null or sim.grid == null or sim.flights == null:
		return {}
	if p == null or p.late or p.is_done() or p.bin_detour_bin > 0:
		return {}
	if spot == Passenger.NO_CELL or not sim.grid.is_walkable(spot):
		return {}
	var doors_close := sim.flights.doors_close_tick(p.flight_id)
	if doors_close < 0:
		return {}
	for candidate in sim.messes.detour_bins_near(spot):
		var bin_spot: Vector2i = candidate["spot"]
		var way := sim.grid.find_path(spot, bin_spot)
		if way.is_empty():
			continue
		var walk_ticks := JourneyForecast.walk_ticks(Passenger.path_mm(way))
		var duration := extra_delay + walk_ticks + MessSim.BIN_TOSS_TICKS
		var arrival := VisitForecast.arrival(sim, p, duration, bin_spot, 0, resume)
		if arrival + VisitForecast.MARGIN_TICKS + MessSim.BIN_DETOUR_SLACK_TICKS <= doors_close:
			return {"bin": int(candidate["id"]), "spot": bin_spot, "path": way}
	return {}


static func try_start(sim: PassengerSim, p: Passenger) -> bool:
	if p == null or p.bin_detour_bin > 0:
		return false
	if p.stage != Passenger.Stage.TO_SECURITY and p.stage != Passenger.Stage.TO_GATE:
		return false
	var plan := plan_from(sim, p, p.at, p.stage, 0)
	if plan.is_empty():
		return false
	p.bin_detour_bin = int(plan["bin"])
	var way: Array[Vector2i] = []
	way.assign(plan["path"])
	if way.size() <= 1 and p.at == plan["spot"]:
		p.clear_path()
		p.bin_detour_end = sim.tick + MessSim.BIN_TOSS_TICKS
	else:
		p.set_path(way)
		p.seg_mm = 0
		p.bin_detour_end = -1
	return true


static func step(sim: PassengerSim, p: Passenger) -> void:
	if p.bin_detour_bin <= 0:
		return
	var bin_id := p.bin_detour_bin
	var rec := sim.grid.get_object(bin_id)
	var spot := (
		sim.messes.bin_approach(bin_id)
		if rec.get("def", &"") == MessSim.BIN_ID
		else MessSim.NO_CELL
	)
	if spot == MessSim.NO_CELL or sim.messes.fill_of(bin_id) >= MessSim.BIN_CAPACITY or p.late:
		cancel(p)
		sim._advance(p)
		return
	var doors_close := sim.flights.doors_close_tick(p.flight_id) if sim.flights != null else -1
	if p.bin_detour_end < 0:
		var walk_mm := 0
		var from_cell := p.at
		if p.is_moving() and p.path_end() == spot:
			walk_mm = p.remaining_mm()
			from_cell = spot
		elif p.at != spot:
			var way := sim.grid.find_path(p.at, spot)
			if way.is_empty():
				cancel(p)
				sim._advance(p)
				return
			p.set_path(way)
			p.seg_mm = 0
			walk_mm = Passenger.path_mm(way)
			from_cell = spot
		var duration := (
			(JourneyForecast.walk_ticks(walk_mm) if walk_mm > 0 else 0) + MessSim.BIN_TOSS_TICKS
		)
		if _forecast_unsafe(sim, p, duration, from_cell, doors_close):
			cancel(p)
			sim._advance(p)
			return
		if p.at == spot and not p.is_moving():
			p.clear_path()
			p.bin_detour_end = sim.tick + MessSim.BIN_TOSS_TICKS
		return
	var toss_left := maxi(p.bin_detour_end - sim.tick, 0)
	if _forecast_unsafe(sim, p, toss_left, p.at, doors_close):
		cancel(p)
		sim._advance(p)
		return
	if sim.tick < p.bin_detour_end:
		return
	if not sim.messes.add_to_bin(bin_id):
		cancel(p)
		sim._advance(p)
		return
	cancel(p)
	sim._advance(p)


static func _forecast_unsafe(
	sim: PassengerSim, p: Passenger, duration: int, from_cell: Vector2i, doors_close: int
) -> bool:
	if doors_close < 0:
		return false
	var arrival := VisitForecast.arrival(sim, p, duration, from_cell, 0, p.stage)
	return arrival + VisitForecast.MARGIN_TICKS > doors_close


static func cancel(p: Passenger) -> void:
	p.bin_detour_bin = 0
	p.bin_detour_end = 0
	p.clear_path()


static func reconcile(sim: PassengerSim) -> void:
	for p in sim._passengers:
		if p.bin_detour_bin <= 0:
			continue
		var rec := sim.grid.get_object(p.bin_detour_bin)
		var bin_ok: bool = rec.get("def", &"") == MessSim.BIN_ID
		var spot := sim.messes.bin_approach(p.bin_detour_bin) if bin_ok else MessSim.NO_CELL
		var fill_ok := sim.messes.fill_of(p.bin_detour_bin) < MessSim.BIN_CAPACITY
		var arrived_at_spot := not p.is_moving() and p.at == spot and p.path_end() == spot
		var walk_or_toss_ok := (
			(p.bin_detour_end >= 0 and not p.is_moving() and p.at == spot)
			or (
				p.bin_detour_end < 0
				and ((p.is_moving() and p.path_end() == spot) or arrived_at_spot)
			)
		)
		if not bin_ok or spot == MessSim.NO_CELL or not fill_ok or not walk_or_toss_ok:
			cancel(p)
