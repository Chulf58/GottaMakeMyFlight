class_name RampDispatch
extends Node

signal emergency_pushback(flight_id: String, fee: int)

const EMERGENCY_RATING_HALF_STARS := -1
const EMERGENCY_ALERT_TICKS := 200
const EMERGENCY_PREFIX := "ramp_pushback:"

@export var clock: SimClock
@export var staff: StaffSim
@export var baggage: BaggageSim
@export var flights: FlightSim
@export var finances: Finances
@export var rating: AirportRating

var _entered_pushback := {}
var _emergencies: Array[Dictionary] = []
var _bound := false


func _ready() -> void:
	if clock != null and staff != null and flights != null:
		bind(clock, staff, baggage, flights, finances, rating)


func bind(
	with_clock: SimClock,
	with_staff: StaffSim,
	with_baggage: BaggageSim = null,
	with_flights: FlightSim = null,
	with_finances: Finances = null,
	with_rating: AirportRating = null,
) -> void:
	_unbind()
	clock = with_clock
	staff = with_staff
	baggage = with_baggage
	flights = with_flights
	finances = with_finances
	rating = with_rating
	if staff != null:
		staff.ramp_dispatch = self
	if clock != null:
		clock.ticked.connect(on_tick)
	if baggage != null:
		baggage.shuttle_can_dispatch = Callable(self, &"_can_dispatch_shuttle")
		baggage.shuttle_dispatched.connect(_on_shuttle_dispatched)
		baggage.shuttle_returned.connect(_on_shuttle_ended)
		baggage.shuttle_cancelled.connect(_on_shuttle_ended)
	if flights != null:
		flights.state_changed.connect(_on_flight_state)
		flights.snapshot_loaded.connect(_on_snapshot_loaded)
	_bound = true


func on_tick(new_tick: int) -> void:
	_prune_emergencies(new_tick)
	_reconcile_claims()
	if flights != null:
		_step_pushbacks(new_tick)
		_step_marshals()


func block_state() -> String:
	if baggage == null:
		return "none"
	return baggage.waiting_for_ramp_reason(staff)


func recent_emergencies() -> Array[Dictionary]:
	if rating == null:
		return _emergencies.duplicate(true)
	var out: Array[Dictionary] = []
	var has_clock := clock != null
	for adj: Dictionary in rating.active_adjustments():
		var parsed := parse_emergency_id(String(adj.get("id", "")))
		if parsed.is_empty():
			continue
		var fid: String = parsed["flight"]
		var tick := int(adj.get("outcome_tick", parsed["tick"]))
		if has_clock and (clock.tick < tick or clock.tick - tick >= EMERGENCY_ALERT_TICKS):
			continue
		var stand := flights.flight_stand(fid) if flights != null else {}
		out.append({"flight": fid, "stand": stand, "tick": tick})
	return out


static func parse_emergency_id(adj_id: String) -> Dictionary:
	if not adj_id.begins_with(EMERGENCY_PREFIX):
		return {}
	var rest := adj_id.substr(EMERGENCY_PREFIX.length())
	var sep := rest.rfind(":")
	if sep <= 0 or sep >= rest.length() - 1:
		return {}
	var fid := rest.substr(0, sep)
	var tick_text := rest.substr(sep + 1)
	if not tick_text.is_valid_int():
		return {}
	return {"flight": fid, "tick": tick_text.to_int()}


func _unbind() -> void:
	if not _bound:
		return
	if is_instance_valid(clock) and clock.ticked.is_connected(on_tick):
		clock.ticked.disconnect(on_tick)
	if is_instance_valid(baggage):
		if baggage.shuttle_dispatched.is_connected(_on_shuttle_dispatched):
			baggage.shuttle_dispatched.disconnect(_on_shuttle_dispatched)
		if baggage.shuttle_returned.is_connected(_on_shuttle_ended):
			baggage.shuttle_returned.disconnect(_on_shuttle_ended)
		if baggage.shuttle_cancelled.is_connected(_on_shuttle_ended):
			baggage.shuttle_cancelled.disconnect(_on_shuttle_ended)
		if baggage.shuttle_can_dispatch == Callable(self, &"_can_dispatch_shuttle"):
			baggage.shuttle_can_dispatch = Callable()
	if is_instance_valid(flights):
		if flights.state_changed.is_connected(_on_flight_state):
			flights.state_changed.disconnect(_on_flight_state)
		if flights.snapshot_loaded.is_connected(_on_snapshot_loaded):
			flights.snapshot_loaded.disconnect(_on_snapshot_loaded)
	_bound = false


func _can_dispatch_shuttle(_cart_id: int, _flight_id: String) -> bool:
	return _find_mandatory_worker() != null


func _on_shuttle_dispatched(shuttle_id: int, _flight_id: String, _cart_id: int) -> void:
	var worker := _find_mandatory_worker()
	if worker == null:
		push_error("RampDispatch: shuttle %d dispatched with no available ramp agent" % shuttle_id)
		return
	staff._set_ramp_job(worker, StaffMember.RampJob.SHUTTLE, shuttle_id)
	baggage.assign_shuttle_driver(shuttle_id, worker.id)


func _on_shuttle_ended(shuttle_id: int, _cart_id: int) -> void:
	if staff == null:
		return
	for id in staff.member_ids():
		var m := staff.get_member(id)
		if (
			m.role == StaffMember.Role.RAMP
			and m.ramp_job == StaffMember.RampJob.SHUTTLE
			and m.ramp_shuttle_id == shuttle_id
		):
			staff._set_ramp_job(m, StaffMember.RampJob.NONE)
			return


func _on_flight_state(flight_id: String, new_state: int) -> void:
	if new_state == FlightSim.State.AT_STAND or new_state == FlightSim.State.BOARDING:
		_release_flight_job(flight_id, StaffMember.RampJob.MARSHAL)
	elif new_state == FlightSim.State.PUSHBACK:
		_entered_pushback[flight_id] = true
	elif new_state >= FlightSim.State.TAXI_OUT:
		_release_flight_job(flight_id, StaffMember.RampJob.PUSHBACK)
		_release_flight_job(flight_id, StaffMember.RampJob.MARSHAL)


func _on_snapshot_loaded() -> void:
	_entered_pushback.clear()
	_emergencies.clear()


func _release_flight_job(flight_id: String, job: StaffMember.RampJob) -> void:
	if staff == null:
		return
	for id in staff.member_ids():
		var m := staff.get_member(id)
		if m.role == StaffMember.Role.RAMP and m.ramp_job == job and m.ramp_flight_id == flight_id:
			staff._set_ramp_job(m, StaffMember.RampJob.NONE)
			return


func _reconcile_claims() -> void:
	if staff == null:
		return
	for id in staff.member_ids():
		var m := staff.get_member(id)
		if m.role != StaffMember.Role.RAMP or m.ramp_job == StaffMember.RampJob.NONE:
			continue
		if m.ramp_job == StaffMember.RampJob.SHUTTLE:
			if baggage == null or baggage.get_shuttle(m.ramp_shuttle_id) == null:
				staff._set_ramp_job(m, StaffMember.RampJob.NONE)
		elif flights == null or not flights.flight_ids().has(m.ramp_flight_id):
			staff._set_ramp_job(m, StaffMember.RampJob.NONE)
		else:
			var state: int = flights.state_of(m.ramp_flight_id)
			if m.ramp_job == StaffMember.RampJob.PUSHBACK:
				if state != FlightSim.State.DOORS_CLOSED and state != FlightSim.State.PUSHBACK:
					staff._set_ramp_job(m, StaffMember.RampJob.NONE)
			elif m.ramp_job == StaffMember.RampJob.MARSHAL and state != FlightSim.State.TAXI_IN:
				staff._set_ramp_job(m, StaffMember.RampJob.NONE)


func _step_pushbacks(at_tick: int) -> void:
	var ids := flights.flight_ids()
	ids.sort()
	for fid: String in ids:
		if _is_self_taxi(fid):
			continue
		var state: int = flights.state_of(fid)
		if state == FlightSim.State.DOORS_CLOSED:
			if _worker_for_flight(fid, StaffMember.RampJob.PUSHBACK) == null:
				var worker := _find_mandatory_worker()
				if worker != null:
					staff._set_ramp_job(worker, StaffMember.RampJob.PUSHBACK, 0, fid)
		elif state == FlightSim.State.PUSHBACK and _entered_pushback.has(fid):
			_entered_pushback.erase(fid)
			if _worker_for_flight(fid, StaffMember.RampJob.PUSHBACK) == null:
				if _has_emergency_adjustment(fid):
					continue
				var worker := _find_mandatory_worker()
				if worker != null:
					staff._set_ramp_job(worker, StaffMember.RampJob.PUSHBACK, 0, fid)
				else:
					_trigger_emergency_pushback(fid, at_tick)
	_entered_pushback.clear()


func _step_marshals() -> void:
	var ids := flights.flight_ids()
	ids.sort()
	for fid: String in ids:
		if _is_self_taxi(fid):
			continue
		if flights.state_of(fid) != FlightSim.State.TAXI_IN:
			continue
		if _worker_for_flight(fid, StaffMember.RampJob.MARSHAL) != null:
			continue
		var worker := _lowest_idle_worker()
		if worker != null:
			staff._set_ramp_job(worker, StaffMember.RampJob.MARSHAL, 0, fid)


func _has_emergency_adjustment(fid: String) -> bool:
	if rating != null:
		for adj: Dictionary in rating.active_adjustments():
			var parsed := parse_emergency_id(String(adj.get("id", "")))
			if parsed.get("flight", "") == fid:
				return true
		return false
	for entry in _emergencies:
		if entry.get("flight", "") == fid:
			return true
	return false


func _trigger_emergency_pushback(fid: String, at_tick: int) -> void:
	if _has_emergency_adjustment(fid):
		return
	var fee := PriceTable.EMERGENCY_PUSHBACK_FEE
	if finances != null and finances.wallet != null:
		finances.wallet.charge(fee, Wallet.Category.FINES)
	if rating != null:
		var adj_id := "%s%s:%d" % [EMERGENCY_PREFIX, fid, at_tick]
		var epoch := SimClock.epoch_of(clock)
		rating.add_adjustment(
			adj_id,
			at_tick,
			RatingAdjustments.expiry_for(at_tick, epoch),
			EMERGENCY_RATING_HALF_STARS
		)
	var stand := flights.flight_stand(fid)
	_emergencies.append({"flight": fid, "stand": stand, "tick": at_tick})
	emergency_pushback.emit(fid, fee)


func _prune_emergencies(at_tick: int) -> void:
	var kept: Array[Dictionary] = []
	for entry in _emergencies:
		if at_tick - int(entry["tick"]) < EMERGENCY_ALERT_TICKS:
			kept.append(entry)
	_emergencies = kept


func _is_self_taxi(flight_id: String) -> bool:
	var model := PlaneClasses.flight_model(flights, flight_id)
	return model == "" or PlaneClasses.self_taxis(model)


func _worker_for_flight(flight_id: String, job: StaffMember.RampJob) -> StaffMember:
	if staff == null:
		return null
	for id in staff.member_ids():
		var m := staff.get_member(id)
		if m.role == StaffMember.Role.RAMP and m.ramp_job == job and m.ramp_flight_id == flight_id:
			return m
	return null


func _lowest_idle_worker() -> StaffMember:
	if staff == null:
		return null
	for id in staff.member_ids():
		var m := staff.get_member(id)
		if (
			m.role == StaffMember.Role.RAMP
			and not m.leaving
			and m.ramp_job == StaffMember.RampJob.NONE
		):
			return m
	return null


func _find_mandatory_worker() -> StaffMember:
	var idle := _lowest_idle_worker()
	if idle != null:
		return idle
	if staff == null:
		return null
	for id in staff.member_ids():
		var m := staff.get_member(id)
		if (
			m.role == StaffMember.Role.RAMP
			and not m.leaving
			and m.ramp_job == StaffMember.RampJob.MARSHAL
		):
			return m
	return null
