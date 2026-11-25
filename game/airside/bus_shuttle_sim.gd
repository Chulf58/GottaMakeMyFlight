class_name BusShuttleSim
extends Node
## Deterministic apron shuttle bus sim: one bus per Bus Gate serving paired
## remote stands (decisions 6d69da79, b6486f8d, 710a78b4).

signal bus_departed(gate: String, flight_id: String, count: int)
signal bus_arrived(gate: String, flight_id: String)
signal bus_returned(gate: String)

enum State { IDLE_AT_BAY, LOADING, DRIVING_OUT, UNLOADING, DRIVING_BACK }

const BUS_CAPACITY := BusGatePairing.BUS_CAPACITY
const SPEED_M_PER_TICK := 0.75
const LOAD_INTERVAL_TICKS := 4
const LOAD_PER_WAVE := 4
const UNLOAD_INTERVAL_TICKS := 2
const UNLOAD_PER_WAVE := 2
const UNLOAD_GRACE_WAVE := 4
const UNLOAD_SETTLE_TICKS := 24
const BOARD_DWELL_TICKS := 60
const FINAL_CALL_LEAD_TICKS := 20
const YAW_EASE_TICKS := 10.0
const BUS_RIDE_MOOD_PENALTY := 6
const ALL_DOORS: Array[int] = [0, 1, 2, 3]
const INNER_DOORS: Array[int] = [1, 2]
const OUTER_DOORS: Array[int] = [0, 3]

@export var clock: SimClock
@export var flights: FlightSim
@export var passengers: PassengerSim
@export var build_mode: BuildMode

var grid: BuildGrid
var tick := 0

var _buses: Dictionary = {}
var _pax_to_gate: Dictionary = {}
var _route_cache: Dictionary = {}
var _bound := false


func _ready() -> void:
	if clock == null or flights == null or passengers == null:
		return
	var g := build_mode.grid if build_mode != null else passengers.grid
	bind(clock, flights, passengers, g)


func bind(
	with_clock: SimClock,
	with_flights: FlightSim,
	with_passengers: PassengerSim,
	with_grid: BuildGrid = null
) -> void:
	clock = with_clock
	flights = with_flights
	passengers = with_passengers
	grid = with_grid if with_grid != null else (passengers.grid if passengers != null else null)
	if clock != null:
		tick = clock.tick
		if not clock.ticked.is_connected(on_tick):
			clock.ticked.connect(on_tick)
	if grid != null and not grid.graph_changed.is_connected(_on_graph_changed):
		grid.graph_changed.connect(_on_graph_changed)
	_bound = true
	sync_gates()


func apply_grid(with_grid: BuildGrid) -> void:
	if grid != null and grid.graph_changed.is_connected(_on_graph_changed):
		grid.graph_changed.disconnect(_on_graph_changed)
	grid = with_grid
	if grid != null and not grid.graph_changed.is_connected(_on_graph_changed):
		grid.graph_changed.connect(_on_graph_changed)
	_route_cache.clear()
	sync_gates()


func on_tick(tick_now: int) -> void:
	tick = tick_now
	sync_gates()
	for gate in bus_gates():
		var bus: Dictionary = _buses[gate]
		match int(bus["state"]):
			State.IDLE_AT_BAY:
				_step_idle(bus)
			State.LOADING:
				_step_loading(bus)
			State.DRIVING_OUT:
				_step_driving_out(bus)
			State.UNLOADING:
				_step_unloading(bus)
			State.DRIVING_BACK:
				_step_driving_back(bus)


func sync_gates() -> void:
	if flights == null or grid == null:
		return
	var grounds := flights.bus_gate_grounds()
	var site := (grid as SiteGrid).site if grid is SiteGrid else null
	for gate: String in _buses.keys():
		if not grounds.has(gate):
			_clear_bus_pax(_buses[gate])
			_buses.erase(gate)
	for gate: String in grounds:
		var exit_id := int(grounds[gate]["exit"])
		var stand := StandPlacement.for_exit(grid, exit_id)
		var bay_pose := BusShuttleRoutes.bay_pose_for(stand, site)
		if not _buses.has(gate):
			_buses[gate] = _new_bus(gate, exit_id, stand, bay_pose)
		else:
			var bus: Dictionary = _buses[gate]
			bus["exit"] = exit_id
			bus["stand"] = stand
			bus["bay_pose"] = bay_pose


func bus_gates() -> Array[String]:
	var out: Array[String] = []
	for gate: String in _buses:
		out.append(gate)
	out.sort()
	return out


func bus_state(gate: String) -> Dictionary:
	return (_buses[gate] as Dictionary).duplicate(true) if _buses.has(gate) else {}


func pose_at(gate: String, time: float) -> Dictionary:
	if not _buses.has(gate):
		return {"visible": false, "origin": Vector3.ZERO, "yaw": 0.0}
	var bus: Dictionary = _buses[gate]
	var state := int(bus["state"])
	if state == State.IDLE_AT_BAY or state == State.LOADING:
		return _static_pose(bus["bay_pose"])
	if state == State.UNLOADING:
		return _static_pose(bus["stop_pose"])
	var rev := state == State.DRIVING_BACK
	var start_pose: Dictionary = bus["stop_pose"] if rev else bus["bay_pose"]
	var end_pose: Dictionary = bus["bay_pose"] if rev else bus["stop_pose"]
	return _driving_pose(bus, time, rev, start_pose, end_pose)


func bus_position_for_passenger(pid: int) -> Vector3:
	if not _pax_to_gate.has(pid):
		return Vector3.ZERO
	var t := float(clock.tick) if clock != null else float(tick)
	var pose := pose_at(String(_pax_to_gate[pid]), t)
	return pose.get("origin", Vector3.ZERO)


func one_way_ticks_for(flight_id: String) -> int:
	if flights == null or grid == null:
		return 0
	var gate := flights.flight_gate(flight_id)
	var sid := flights.flight_stand_id(flight_id)
	var model := PlaneClasses.flight_model(flights, flight_id)
	var plan := _plan_for(gate, sid, model)
	if plan.is_empty():
		return 0
	return maxi(1, ceili(float(plan["route_len"]) / SPEED_M_PER_TICK))


func final_call_tick_for(flight_id: String) -> int:
	if flights == null:
		return 0
	return (
		flights.doors_close_tick(flight_id) - one_way_ticks_for(flight_id) - FINAL_CALL_LEAD_TICKS
	)


func remaining_ticks_for_passenger(p: Passenger, now: int) -> int:
	if not _pax_to_gate.has(p.id):
		return 0
	var gate := String(_pax_to_gate[p.id])
	var bus: Dictionary = _buses.get(gate, {})
	if bus.is_empty():
		return 0
	var wait_ticks := 0
	var st := int(bus["state"])
	var close := flights.doors_close_tick(p.flight_id) if flights != null else -1
	if st == State.LOADING and close >= 0:
		var drive := _drive_ticks_of(bus)
		wait_ticks = maxi(0, close - FINAL_CALL_LEAD_TICKS - now)
		wait_ticks = mini(wait_ticks, BOARD_DWELL_TICKS + drive)
	elif st == State.DRIVING_OUT:
		wait_ticks = maxi(0, int(bus["arrive_tick"]) - now)
	var closed := (
		flights != null and (flights.is_doors_closed(p.flight_id) or (close >= 0 and now >= close))
	)
	var climb_mm := PassengerSim.BRISK_APRON_MM if closed else PassengerSim.WALK_MM
	var stair_mm := _stair_walk_mm(bus.get("stop_pose", {}))
	@warning_ignore("integer_division")
	var unload_and_climb := UNLOAD_INTERVAL_TICKS * 10 + (stair_mm + climb_mm - 1) / climb_mm
	return wait_ticks + unload_and_climb


func has_active_bus_for_passenger(pid: int) -> bool:
	return _pax_to_gate.has(pid)


func passenger_ids_on_buses() -> Dictionary:
	return _pax_to_gate.duplicate()


func to_snapshot() -> Dictionary:
	return BusShuttleSnapshot.pack(tick, _buses)


func from_snapshot(data: Variant) -> bool:
	var by_id := {}
	if passengers != null:
		for p in passengers._passengers:
			by_id[p.id] = p
	var checked := BusShuttleSnapshot.checked(data, flights, by_id)
	if checked.has("error"):
		push_error("BusShuttleSim.from_snapshot: %s" % checked["error"])
		return false
	_buses.clear()
	_pax_to_gate.clear()
	_route_cache.clear()
	tick = int(checked["tick"])
	sync_gates()
	for e: Dictionary in checked["buses"]:
		var gate := String(e["gate"])
		if not _buses.has(gate):
			continue
		var bus: Dictionary = _buses[gate]
		for key in [
			"state",
			"flight_id",
			"stand_id",
			"model",
			"start_tick",
			"arrive_tick",
			"load_tick",
			"last_board_tick",
			"unload_tick",
		]:
			bus[key] = e[key]
		bus["aboard"] = (e["aboard"] as Array).duplicate()
		for pid: int in bus["aboard"]:
			_pax_to_gate[pid] = gate
		if int(bus["state"]) != State.IDLE_AT_BAY:
			var plan := _plan_for(gate, String(bus["stand_id"]), String(bus["model"]))
			bus["stop_pose"] = plan.get("stop_pose", {})
			bus["route"] = plan.get("route", PackedVector3Array())
			bus["route_len"] = float(plan.get("route_len", 0.0))
	return true


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	_route_cache.clear()


func _new_bus(gate: String, exit_id: int, stand: Dictionary, bay_pose: Dictionary) -> Dictionary:
	return {
		"gate": gate,
		"exit": exit_id,
		"stand": stand,
		"bay_pose": bay_pose,
		"state": State.IDLE_AT_BAY,
		"flight_id": "",
		"stand_id": "",
		"model": "",
		"stop_pose": {},
		"route": PackedVector3Array(),
		"route_len": 0.0,
		"start_tick": 0,
		"arrive_tick": 0,
		"load_tick": 0,
		"last_board_tick": -1,
		"unload_tick": 0,
		"aboard": [] as Array[int],
	}


func _step_idle(bus: Dictionary) -> void:
	if flights == null or passengers == null:
		return
	var gate := String(bus["gate"])
	for fid in flights.flights_at_gate(gate):
		if flights.state_of(fid) == FlightSim.State.BOARDING:
			var sid := flights.flight_stand_id(fid)
			var model := PlaneClasses.flight_model(flights, fid)
			var plan := _plan_for(gate, sid, model)
			if plan.is_empty():
				return
			var drive_ticks := maxi(1, ceili(float(plan["route_len"]) / SPEED_M_PER_TICK))
			var final_call := flights.doors_close_tick(fid) - drive_ticks - FINAL_CALL_LEAD_TICKS
			if tick >= final_call:
				continue
			bus["state"] = State.LOADING
			bus["flight_id"] = fid
			bus["stand_id"] = sid
			bus["model"] = model
			bus["stop_pose"] = plan["stop_pose"]
			bus["route"] = plan["route"]
			bus["route_len"] = plan["route_len"]
			bus["load_tick"] = tick
			bus["last_board_tick"] = -1
			bus["aboard"] = [] as Array[int]
			_step_loading(bus)
			return


func _step_loading(bus: Dictionary) -> void:
	var fid := String(bus["flight_id"])
	if flights == null or flights.state_of(fid) < 0:
		_reset_to_bay(bus)
		return
	var exit_id := int(bus["exit"])
	var aboard: Array = bus["aboard"]
	var drive_ticks := _drive_ticks_of(bus)
	var final_call := flights.doors_close_tick(fid) - drive_ticks - FINAL_CALL_LEAD_TICKS
	if flights.is_doors_closed(fid) or tick >= final_call:
		if aboard.is_empty():
			_reset_to_bay(bus)
		else:
			_depart(bus)
		return
	if aboard.size() < BUS_CAPACITY and (tick - int(bus["load_tick"])) % LOAD_INTERVAL_TICKS == 0:
		_board_wave(bus, fid, exit_id, aboard)
	if aboard.is_empty():
		return
	var full := aboard.size() >= BUS_CAPACITY
	var dwell_done := (
		not _has_approaching(fid, exit_id)
		and (tick - int(bus["last_board_tick"])) >= BOARD_DWELL_TICKS
	)
	if full or dwell_done:
		_depart(bus)


func _board_wave(bus: Dictionary, fid: String, exit_id: int, aboard: Array) -> void:
	var waiting := PassengerGates.passengers_at_bus_door(passengers, exit_id, fid)
	var gate := String(bus["gate"])
	var taken := 0
	for p in waiting:
		if aboard.size() >= BUS_CAPACITY or taken >= LOAD_PER_WAVE:
			break
		aboard.append(p.id)
		_pax_to_gate[p.id] = gate
		bus["last_board_tick"] = tick
		PassengerGates.board_bus(passengers, p, BUS_RIDE_MOOD_PENALTY)
		taken += 1


func _depart(bus: Dictionary) -> void:
	var drive_ticks := _drive_ticks_of(bus)
	bus["state"] = State.DRIVING_OUT
	bus["start_tick"] = tick
	bus["arrive_tick"] = tick + drive_ticks
	bus_departed.emit(
		String(bus["gate"]), String(bus["flight_id"]), (bus["aboard"] as Array).size()
	)


func _step_driving_out(bus: Dictionary) -> void:
	if tick < int(bus["arrive_tick"]):
		return
	bus["state"] = State.UNLOADING
	bus["unload_tick"] = tick
	bus_arrived.emit(String(bus["gate"]), String(bus["flight_id"]))
	_step_unloading(bus)


func _step_unloading(bus: Dictionary) -> void:
	var aboard: Array = bus["aboard"]
	var fid := String(bus["flight_id"])
	if flights != null and flights.state_of(fid) >= 0:
		var fst := flights.state_of(fid)
		if fst >= FlightSim.State.PUSHBACK:
			_clear_bus_pax(bus)
			_start_return(bus)
			return
	var closed := flights != null and flights.is_doors_closed(fid)
	var interval := 1 if closed else UNLOAD_INTERVAL_TICKS
	if not aboard.is_empty() and (tick - int(bus["unload_tick"])) % interval == 0:
		var stop_pose: Dictionary = bus["stop_pose"]
		var wave_limit := UNLOAD_GRACE_WAVE if closed else UNLOAD_PER_WAVE
		var doors: Array[int] = ALL_DOORS
		if not closed:
			@warning_ignore("integer_division")
			var wave_idx := (tick - int(bus["unload_tick"])) / interval
			doors = INNER_DOORS if wave_idx % 2 == 0 else OUTER_DOORS
		var door_count := mini(wave_limit, aboard.size())
		for i in door_count:
			var pid := int(aboard.pop_front())
			_pax_to_gate.erase(pid)
			var p := passengers.get_passenger(pid)
			if p == null or p.is_done():
				continue
			var door_idx := doors[i % doors.size()]
			var walk := BusShuttleRoutes.bus_unload_walk(stop_pose, door_idx)
			PassengerGates.unload_from_bus(passengers, p, walk)
		if aboard.is_empty():
			bus["unload_tick"] = tick
	if aboard.is_empty():
		var skip_settle := closed or _tight_for_next_wave(bus, fid)
		if skip_settle or tick - int(bus["unload_tick"]) >= UNLOAD_SETTLE_TICKS:
			_start_return(bus)


func _tight_for_next_wave(bus: Dictionary, fid: String) -> bool:
	if flights == null or flights.state_of(fid) != FlightSim.State.BOARDING:
		return false
	var drive := _drive_ticks_of(bus)
	var final_call := flights.doors_close_tick(fid) - drive - FINAL_CALL_LEAD_TICKS
	return tick + drive + UNLOAD_SETTLE_TICKS + LOAD_INTERVAL_TICKS * 10 >= final_call


func _start_return(bus: Dictionary) -> void:
	var drive_ticks := _drive_ticks_of(bus)
	bus["state"] = State.DRIVING_BACK
	bus["start_tick"] = tick
	bus["arrive_tick"] = tick + drive_ticks


func _step_driving_back(bus: Dictionary) -> void:
	if tick < int(bus["arrive_tick"]):
		return
	var gate := String(bus["gate"])
	_reset_to_bay(bus)
	bus_returned.emit(gate)


func _reset_to_bay(bus: Dictionary) -> void:
	_clear_bus_pax(bus)
	bus["state"] = State.IDLE_AT_BAY
	bus["flight_id"] = ""
	bus["stand_id"] = ""
	bus["model"] = ""
	bus["stop_pose"] = {}
	bus["route"] = PackedVector3Array()
	bus["route_len"] = 0.0
	bus["last_board_tick"] = -1


func _clear_bus_pax(bus: Dictionary) -> void:
	var aboard: Array = bus.get("aboard", [])
	for pid: Variant in aboard:
		_pax_to_gate.erase(int(pid))
	aboard.clear()


func _has_approaching(fid: String, exit_id: int) -> bool:
	var door_cell := passengers.layout.door_cell(grid, exit_id)
	for p in passengers._passengers:
		if p.flight_id != fid or p.is_done():
			continue
		if p.stage == Passenger.Stage.TO_EXIT and p.exit_object == exit_id:
			if p.is_moving() or p.at != door_cell:
				return true
	return false


func _drive_ticks_of(bus: Dictionary) -> int:
	return maxi(1, ceili(float(bus.get("route_len", 0.0)) / SPEED_M_PER_TICK))


func _plan_for(gate: String, sid: String, model: String) -> Dictionary:
	if flights == null or grid == null or gate == "" or sid == "":
		return {}
	var key := "%s|%s|%s" % [gate, sid, model]
	if _route_cache.has(key):
		return _route_cache[key]
	var bus_grounds := flights.bus_gate_grounds()
	var rem_grounds := flights.remote_stand_grounds()
	if not bus_grounds.has(gate) or not rem_grounds.has(sid):
		return {}
	var site := (grid as SiteGrid).site if grid is SiteGrid else null
	var gate_stand := StandPlacement.for_exit(grid, int(bus_grounds[gate]["exit"]))
	var bay_pose := BusShuttleRoutes.bay_pose_for(gate_stand, site)
	var rem_stand: Dictionary = rem_grounds[sid].get("stand", {})
	if bay_pose.is_empty() or rem_stand.is_empty():
		return {}
	var gy := AirstairsPose.ground_y(rem_stand) if site != null else float(bay_pose["origin"].y)
	var stop_pose := BusShuttleRoutes.stop_pose_for(rem_stand, model, gy)
	var reg_stands: Array[Dictionary] = []
	for g: Dictionary in flights.gate_grounds().values():
		reg_stands.append(g["stand"])
	var rem_stands := {}
	for r_id: String in rem_grounds:
		rem_stands[r_id] = rem_grounds[r_id]["stand"]
	var route := BusShuttleRoutes.plan_route(
		grid, bay_pose["origin"], stop_pose["origin"], reg_stands, rem_stands, sid, model
	)
	var plan := {
		"bay_pose": bay_pose,
		"stop_pose": stop_pose,
		"route": route,
		"route_len": BusShuttleRoutes.route_length(route),
	}
	_route_cache[key] = plan
	return plan


static func _static_pose(pose: Dictionary) -> Dictionary:
	if pose.is_empty():
		return {"visible": false, "origin": Vector3.ZERO, "yaw": 0.0}
	return {
		"visible": true,
		"origin": pose["origin"],
		"yaw": float(pose["yaw"]),
	}


static func _driving_pose(
	bus: Dictionary, time: float, reversed: bool, start_pose: Dictionary, end_pose: Dictionary
) -> Dictionary:
	var route: PackedVector3Array = bus.get("route", PackedVector3Array())
	var total := float(bus.get("route_len", 0.0))
	if route.size() < 2 or total <= 0.0:
		return _static_pose(end_pose)
	var t0 := float(bus["start_tick"])
	var t1 := float(bus["arrive_tick"])
	var span := maxf(t1 - t0, 1.0)
	var frac := clampf((time - t0) / span, 0.0, 1.0)
	var target_dist := (1.0 - frac) * total if reversed else frac * total
	var pos := route[route.size() - 1] if not reversed else route[0]
	var yaw := float(end_pose.get("yaw", 0.0))
	var acc := 0.0
	for i in range(1, route.size()):
		var a := route[i - 1]
		var b := route[i]
		var seg := Vector2(b.x - a.x, b.z - a.z).length()
		if acc + seg >= target_dist or i == route.size() - 1:
			var local_t := clampf((target_dist - acc) / maxf(seg, 1e-4), 0.0, 1.0)
			pos = a.lerp(b, local_t)
			var dir := a - b if reversed else b - a
			if Vector2(dir.x, dir.z).length() > 1e-3:
				yaw = atan2(dir.x, dir.z)
			break
		acc += seg
	pos.y = PlaneView.ground_height_at(pos)
	var ease_ticks := minf(YAW_EASE_TICKS, maxf(span * 0.25, 1.0))
	var start_yaw := float(start_pose.get("yaw", yaw))
	var end_yaw := float(end_pose.get("yaw", yaw))
	var elapsed := time - t0
	var left := t1 - time
	if elapsed < ease_ticks:
		var k := smoothstep(0.0, 1.0, clampf(elapsed / ease_ticks, 0.0, 1.0))
		yaw = lerp_angle(start_yaw, yaw, k)
	elif left < ease_ticks:
		var k := smoothstep(0.0, 1.0, clampf(left / ease_ticks, 0.0, 1.0))
		yaw = lerp_angle(end_yaw, yaw, k)
	return {"visible": true, "origin": pos, "yaw": yaw}


static func _stair_walk_mm(stop_pose: Dictionary) -> int:
	var pts := BusShuttleRoutes.bus_unload_walk(stop_pose, 1)
	if pts.is_empty():
		return 0
	var mm := 0
	for i in range(1, pts.size()):
		mm += roundi(pts[i - 1].distance_to(pts[i]) * 1000.0)
	return mm
