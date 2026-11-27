class_name StaffBreaks
extends RefCounted
## Lull-only break cycling and energy stepping for StaffSim (Slice S3-P2b;
## decision b764f946). Staff only seek a Break Room during genuine lulls and
## return immediately if unserved demand arrives while no other staff covers it.


static func _is_airport_closed(staff: StaffSim) -> bool:
	return staff.sim != null and staff.sim.flights != null and staff.sim.flights.opened_tick < 0


static func step_energy(staff: StaffSim) -> void:
	if _is_airport_closed(staff):
		return
	for id in staff.member_ids():
		var m := staff.get_member(id)
		var prev := m.energy
		match m.state:
			StaffMember.State.ON_DUTY:
				m.energy_ticks += 1
				if m.energy_ticks >= StaffMember.DRAIN_INTERVAL_TICKS:
					m.energy_ticks = 0
					m.energy = maxi(m.energy - 1, StaffMember.ENERGY_MIN)
			StaffMember.State.ON_BREAK:
				var bonus := StaffBreakRooms.recovery_bonus_percent(staff.sim.grid, m.break_room)
				m.energy_ticks += StaffMember.RECOVERY_BASE_RATE + bonus
				while m.energy_ticks >= StaffMember.RECOVERY_THRESHOLD:
					m.energy_ticks -= StaffMember.RECOVERY_THRESHOLD
					m.energy = mini(m.energy + 1, StaffMember.ENERGY_MAX)
				if m.energy >= StaffMember.ENERGY_MAX:
					m.energy_ticks = 0
			StaffMember.State.OFF_SHIFT:
				m.energy = StaffMember.ENERGY_MAX
				m.energy_ticks = 0
			StaffMember.State.IDLE:
				if m.role == StaffMember.Role.RAMP and m.energy < StaffMember.ENERGY_MAX:
					m.energy_ticks += StaffMember.RECOVERY_BASE_RATE
					if m.energy_ticks >= StaffMember.RECOVERY_THRESHOLD:
						m.energy_ticks -= StaffMember.RECOVERY_THRESHOLD
						m.energy = mini(m.energy + 1, StaffMember.ENERGY_MAX)
					if m.energy >= StaffMember.ENERGY_MAX:
						m.energy_ticks = 0
		if m.energy != prev:
			staff.member_energy_changed.emit(m.id, m.energy)


static func update_breaks(staff: StaffSim, begin_break: Callable, end_break: Callable) -> void:
	if staff.sim == null or staff.sim.grid == null or _is_airport_closed(staff):
		return
	for id in staff.member_ids():
		var m := staff.get_member(id)
		if m == null or not m.is_on_break():
			continue
		if m.energy >= StaffMember.BREAK_DONE_THRESHOLD or _must_interrupt(staff, m):
			end_break.call(m)
	if staff.is_off_shift() or staff.sim.layout == null:
		return
	if StaffBreakRooms.ready_rooms(staff.sim.grid).is_empty():
		return
	for id in staff.member_ids():
		var m := staff.get_member(id)
		if m == null or m.role == StaffMember.Role.RAMP or m.leaving:
			continue
		if m.energy > StaffMember.BREAK_SEEK_THRESHOLD:
			continue
		if m.state != StaffMember.State.IDLE and m.state != StaffMember.State.ON_DUTY:
			continue
		if (
			m.state == StaffMember.State.IDLE
			and m.search_failed
			and not StaffPosts.on_beat(m, staff.sim.tick)
		):
			continue
		if not _is_lull_for(staff, m):
			continue
		var pick := StaffBreakRooms.nearest_break(staff, m)
		if pick.is_empty():
			if m.state == StaffMember.State.IDLE:
				m.search_failed = true
			continue
		begin_break.call(m, pick["room"], pick["spot"], pick["path"])


static func _is_lull_for(staff: StaffSim, m: StaffMember) -> bool:
	var sim := staff.sim
	if m.role == StaffMember.Role.CLEANER:
		return (
			m.state == StaffMember.State.IDLE
			and m.job == 0
			and m.bag_carry == StaffMember.BagCarry.NONE
			and CleanerJobs.nearest(staff, m).is_empty()
		)
	if m.state == StaffMember.State.IDLE:
		return not _role_has_demand(staff, m.role, 0)
	if m.station == 0:
		return false
	if not m.is_helper() and staff._in_service(m.station):
		return false
	if _station_busy(sim, m.station, m.role):
		return false
	var ignoring := 0 if m.is_helper() else m.station
	return not _role_has_demand(staff, m.role, ignoring)


static func _must_interrupt(staff: StaffSim, m: StaffMember) -> bool:
	if m.role == StaffMember.Role.CLEANER:
		return (
			not CleanerJobs.nearest(staff, m).is_empty()
			and not _has_idle_worker(staff, m.role, m.id)
		)
	return _role_has_demand(staff, m.role, 0)


static func _has_idle_worker(staff: StaffSim, role: StaffMember.Role, exclude_id: int) -> bool:
	for id in staff.member_ids():
		if id == exclude_id:
			continue
		var other := staff.get_member(id)
		if other.role == role and other.state == StaffMember.State.IDLE and not other.leaving:
			return true
	return false


static func _role_has_demand(
	staff: StaffSim, role: StaffMember.Role, ignoring_station: int
) -> bool:
	var sim := staff.sim
	var stations := staff.stations_of(role)
	var has_vacant := false
	for station in stations:
		if _is_vacant_post(staff, station, ignoring_station):
			has_vacant = true
			if _station_busy(sim, station, role):
				return true
	if not has_vacant:
		return false
	match role:
		StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY:
			return _pooled_queue_demand(staff, role, stations, ignoring_station)
		StaffMember.Role.GATE:
			for station in stations:
				if (
					_is_vacant_post(staff, station, ignoring_station)
					and _gate_desk_active(sim, station)
				):
					return true
		StaffMember.Role.SHOP:
			for station in stations:
				if not _is_vacant_post(staff, station, ignoring_station):
					continue
				var bucket := _shop_bucket(sim.grid, station)
				if bucket == &"":
					continue
				if _has_open_idle_shop(staff, stations, ignoring_station, bucket):
					continue
				if _shop_counter_has_demand(sim, bucket):
					return true
	return false


static func _pooled_queue_demand(
	staff: StaffSim,
	role: StaffMember.Role,
	stations: Array[int],
	ignoring_station: int,
) -> bool:
	if _has_open_idle(staff, stations, ignoring_station, role):
		return false
	var sim := staff.sim
	for pid in sim.passenger_ids():
		var p := sim.get_passenger(pid)
		if p.is_done():
			continue
		if role == StaffMember.Role.CHECKIN:
			if p.stage == Passenger.Stage.SPAWNED or p.stage == Passenger.Stage.TO_CHECKIN:
				return true
		elif p.stage == Passenger.Stage.TO_SECURITY:
			return true
	return false


static func _is_vacant_post(staff: StaffSim, station: int, ignoring_station: int) -> bool:
	return (
		station == ignoring_station
		or StaffPosts.is_vacant(staff, station, StaffMember.Slot.PRIMARY)
	)


static func _has_open_idle(
	staff: StaffSim, stations: Array[int], ignoring_station: int, role: StaffMember.Role
) -> bool:
	for station in stations:
		if (
			station != ignoring_station
			and staff.is_open(station)
			and not _station_busy(staff.sim, station, role)
		):
			return true
	return false


static func _has_open_idle_shop(
	staff: StaffSim, stations: Array[int], ignoring_station: int, bucket: StringName
) -> bool:
	for station in stations:
		if (
			station != ignoring_station
			and staff.is_open(station)
			and _shop_bucket(staff.sim.grid, station) == bucket
			and not _station_busy(staff.sim, station, StaffMember.Role.SHOP)
		):
			return true
	return false


static func _shop_bucket(grid: BuildGrid, station: int) -> StringName:
	var obj: Dictionary = grid.get_object(station)
	if obj.is_empty():
		return &""
	match obj.get("def", &""):
		&"info_desk":
			return &"info"
		&"grab_and_go_stall":
			return &"food"
		&"currency_exchange":
			return &"shop"
	var room_id := ShopCounters.room_of(grid, station)
	var room: Dictionary = grid.get_room(room_id) if room_id > 0 else {}
	var rtype := RoomTypes.get_type(room["type"]) if not room.is_empty() else null
	if rtype == null:
		return &""
	if rtype.food:
		return &"food"
	return &"shop" if rtype.shop else &""


static func _station_busy(sim: PassengerSim, station: int, role: StaffMember.Role) -> bool:
	if sim._incoming.get(station, 0) > 0:
		return true
	if not sim.queue_of(station).is_empty() or not sim.holding_of(station).is_empty():
		return true
	if sim._queues.has(station) and int(sim._queues[station].get("serving", 0)) != 0:
		return true
	if not sim.security.record_of(station).is_empty():
		return true
	if sim.cafes.serving_at(station) != 0 or not sim.cafes.queue_of(station).is_empty():
		return true
	if sim.info_desks.helping_at(station):
		return true
	for pid in sim.passenger_ids():
		var p := sim.get_passenger(pid)
		if p.station == station and not p.is_done():
			return true
		if sim.info_desks.desk_of(p) == station:
			return true
	if role == StaffMember.Role.SHOP:
		var room_id := ShopCounters.room_of(sim.grid, station)
		for vid in sim.shops.visit_ids():
			var visit := sim.shops.visit_of(vid)
			if visit == null:
				continue
			if (room_id > 0 and visit.room == room_id) or visit.display == station:
				return true
	elif role == StaffMember.Role.GATE:
		return _gate_desk_active(sim, station)
	return false


static func _gate_desk_active(sim: PassengerSim, station: int) -> bool:
	if sim.flights == null:
		return false
	var gate_letter := ""
	for letter: String in sim.layout.gate_desk_ids:
		if int(sim.layout.gate_desk_ids[letter]) == station:
			gate_letter = letter
			break
	if gate_letter == "":
		return false
	for fid: String in sim.flights.flight_ids():
		if sim.flights.flight_gate(fid) != gate_letter:
			continue
		var st: int = sim.flights.state_of(fid)
		if st == FlightSim.State.BOARDING or st == FlightSim.State.DEBOARDING:
			return true
		if st == FlightSim.State.AT_STAND:
			for pid in sim.passenger_ids():
				var p := sim.get_passenger(pid)
				if p.flight_id == fid and p.is_departing() and not p.is_done():
					return true
	return false


static func _shop_counter_has_demand(sim: PassengerSim, bucket: StringName) -> bool:
	match bucket:
		&"info":
			for pid in sim.passenger_ids():
				if sim.info_desks.wants_help(sim.get_passenger(pid)):
					return true
		&"food":
			for pid in sim.passenger_ids():
				if sim.cafes.wants_food(sim.get_passenger(pid)):
					return true
		&"shop":
			for pid in sim.passenger_ids():
				if sim.boredom.is_bored(sim.get_passenger(pid)):
					return true
	return false
