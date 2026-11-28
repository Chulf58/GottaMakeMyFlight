class_name AirportGoals
extends Node
## Progressive 3-slot Airport Goals tracker (Slice 2 of Demo Engagement & Pacing,
## decision demo-engagement-technical-design-bottlenecks-events-and-airport-goals-tracker).
## Mixes cumulative and stateful milestones across Days 1-5 and full-game play,
## evaluating newly slotted stateful goals immediately so nothing soft-locks,
## paying cash grants via Wallet.Category.GRANT, and suppressing payouts/signals
## while SaveGame loads (`set_loading(true)`).

signal changed
signal goal_completed(goal: Dictionary)

const ACTIVE_SLOTS := 3
const SAVE_VERSION := 1
const MAX_COUNT := 1_000_000_000
const SNAPSHOT_KEYS := ["save_version", "active_ids", "completed_ids", "counters"]
const COUNTER_KEYS: Array[String] = [
	"departing_made",
	"on_time_flights",
	"cafe_served",
	"kiosk_served",
	"bags_loaded",
	"charters_departed",
	"incidents_resolved",
]

const CATALOG: Array[Dictionary] = [
	{
		"id": "board_10_pax",
		"title": "Board 10 passengers",
		"reward": 250,
		"target": 10,
		"kind": "counter",
		"counter": "departing_made",
		"min_tier": 1,
	},
	{
		"id": "on_time_2",
		"title": "Run 2 on-time flights",
		"reward": 300,
		"target": 2,
		"kind": "counter",
		"counter": "on_time_flights",
		"min_tier": 1,
	},
	{
		"id": "second_checkin",
		"title": "Add a 2nd Check-in Desk",
		"reward": 300,
		"target": 2,
		"kind": "checkin_desks",
		"min_tier": 1,
	},
	{
		"id": "hire_4_staff",
		"title": "Hire 4 staff members",
		"reward": 300,
		"target": 4,
		"kind": "staff_hired",
		"min_tier": 1,
	},
	{
		"id": "tier_2",
		"title": "Reach Tier 2 unlocks",
		"reward": 400,
		"target": 2,
		"kind": "tier",
		"min_tier": 1,
	},
	{
		"id": "serve_4_cafe",
		"title": "Serve 4 Cafe guests",
		"reward": 350,
		"target": 4,
		"kind": "counter",
		"counter": "cafe_served",
		"min_tier": 2,
	},
	{
		"id": "serve_4_kiosk",
		"title": "Serve 4 Kiosk shoppers",
		"reward": 350,
		"target": 4,
		"kind": "counter",
		"counter": "kiosk_served",
		"min_tier": 2,
	},
	{
		"id": "security_lane",
		"title": "Build a Security Lane",
		"reward": 500,
		"target": 1,
		"kind": "security_lanes",
		"min_tier": 2,
	},
	{
		"id": "bags_6",
		"title": "Handle 6 checked bags",
		"reward": 450,
		"target": 6,
		"kind": "counter",
		"counter": "bags_loaded",
		"min_tier": 2,
	},
	{
		"id": "charter_1",
		"title": "Complete a Charter flight",
		"reward": 500,
		"target": 1,
		"kind": "counter",
		"counter": "charters_departed",
		"min_tier": 2,
	},
	{
		"id": "extra_land_1",
		"title": "Buy 1 extra land plot",
		"reward": 450,
		"target": 1,
		"kind": "extra_land",
		"min_tier": 1,
	},
	{
		"id": "cert_2_star",
		"title": "Earn 2★ Airport Certification",
		"reward": 600,
		"target": 2,
		"kind": "certification",
		"min_tier": 2,
	},
	{
		"id": "board_40_pax",
		"title": "Board 40 passengers",
		"reward": 600,
		"target": 40,
		"kind": "counter",
		"counter": "departing_made",
		"min_tier": 2,
	},
	{
		"id": "resolve_incident_1",
		"title": "Resolve an airport incident",
		"reward": 400,
		"target": 1,
		"kind": "counter",
		"counter": "incidents_resolved",
		"min_tier": 1,
		"require_incidents": true,
	},
]

@export var finances: Finances
@export var passengers: PassengerSim
@export var flights: FlightSim
@export var build_mode: BuildMode
@export var staff: StaffSim
@export var baggage: BaggageSim
@export var incidents: IncidentDirector
@export var certification: AirportCertification
@export var unlocks: BuildUnlocks
@export var clock: SimClock
@export var save_game: SaveGame

var _active_ids: Array[String] = []
var _completed_ids: Array[String] = []
var _counters: Dictionary = _empty_counters()
var _counted_incident_ids: Dictionary = {}
var _loading := false
var _bound := false
var _bound_grid: BuildGrid
var _bound_land: LandPlots


func _ready() -> void:
	_resolve_certification()
	bind(
		finances,
		passengers,
		flights,
		build_mode,
		staff,
		baggage,
		incidents,
		certification,
		unlocks,
		clock
	)
	if _active_ids.is_empty() and _completed_ids.is_empty():
		_fill_slots()
		changed.emit()


func _exit_tree() -> void:
	_unbind()


## Catalog entry for `goal_id`, or {} if unknown.
static func definition(goal_id: String) -> Dictionary:
	for entry: Dictionary in CATALOG:
		if str(entry["id"]) == goal_id:
			return entry.duplicate(true)
	return {}


## Empty string when `data` is a valid saved goals state, else the refusal reason.
static func validation_problem(data: Variant) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "goals must be a dictionary"
	var dict := data as Dictionary
	for key in dict.keys():
		if not SNAPSHOT_KEYS.has(key):
			return "unknown key '%s'" % key
	for key in SNAPSHOT_KEYS:
		if not dict.has(key):
			return "missing key '%s'" % key
	if not WholeNumber.is_whole(dict["save_version"]) or int(dict["save_version"]) != SAVE_VERSION:
		return "save_version must be %d" % SAVE_VERSION
	var active_err := _id_list_problem(dict["active_ids"], "active_ids", ACTIVE_SLOTS)
	if active_err != "":
		return active_err
	var done_err := _id_list_problem(dict["completed_ids"], "completed_ids", CATALOG.size())
	if done_err != "":
		return done_err
	for active_id in dict["active_ids"]:
		if (dict["completed_ids"] as Array).has(active_id):
			return "goal '%s' cannot be both active and completed" % active_id
	return _counters_problem(dict["counters"])


static func _id_list_problem(raw: Variant, field: String, max_size: int) -> String:
	if typeof(raw) != TYPE_ARRAY:
		return "'%s' must be an array" % field
	var items := raw as Array
	if items.size() > max_size:
		return "'%s' has too many entries (%d > %d)" % [field, items.size(), max_size]
	var seen := {}
	for item in items:
		if typeof(item) != TYPE_STRING:
			return "'%s' entries must be strings" % field
		var goal_id := str(item)
		if definition(goal_id).is_empty():
			return "unknown goal id '%s' in %s" % [goal_id, field]
		if seen.has(goal_id):
			return "duplicate goal id '%s' in %s" % [goal_id, field]
		seen[goal_id] = true
	return ""


static func _counters_problem(raw: Variant) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return "'counters' must be a dictionary"
	var dict := raw as Dictionary
	for key in dict.keys():
		if not COUNTER_KEYS.has(key):
			return "unknown counter '%s'" % key
	for key in COUNTER_KEYS:
		if not dict.has(key):
			return "missing counter '%s'" % key
		if not WholeNumber.is_whole(dict[key]):
			return "counter '%s' must be a whole number" % key
		var value := int(dict[key])
		if value < 0 or value > MAX_COUNT:
			return "counter '%s' (%d) is outside 0..%d" % [key, value, MAX_COUNT]
	return ""


static func _empty_counters() -> Dictionary:
	var out := {}
	for key in COUNTER_KEYS:
		out[key] = 0
	return out


func set_loading(loading: bool) -> void:
	_loading = loading


func is_loading() -> bool:
	return _loading


func reset() -> void:
	_active_ids.clear()
	_completed_ids.clear()
	_counters = _empty_counters()
	_counted_incident_ids.clear()
	_fill_slots()
	changed.emit()


## Binds live scene dependencies and connects state signals idempotently.
func bind(
	with_finances: Finances,
	with_passengers: PassengerSim,
	with_flights: FlightSim,
	with_build_mode: BuildMode,
	with_staff: StaffSim,
	with_baggage: BaggageSim,
	with_incidents: IncidentDirector,
	with_certification: AirportCertification,
	with_unlocks: BuildUnlocks,
	with_clock: SimClock = null
) -> void:
	if (
		_bound
		and finances == with_finances
		and passengers == with_passengers
		and flights == with_flights
		and build_mode == with_build_mode
		and staff == with_staff
		and baggage == with_baggage
		and incidents == with_incidents
		and certification == with_certification
		and unlocks == with_unlocks
		and clock == with_clock
	):
		_sync_grid_and_land_signals()
		return
	_unbind()
	finances = with_finances
	passengers = with_passengers
	flights = with_flights
	build_mode = with_build_mode
	staff = with_staff
	baggage = with_baggage
	incidents = with_incidents
	certification = with_certification
	unlocks = with_unlocks
	clock = with_clock
	_connect_signals()
	_bound = true


## Returns up to ACTIVE_SLOTS active goal dictionaries with live progress/target/reward.
func active_goals() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for goal_id in _active_ids:
		var def := definition(goal_id)
		if def.is_empty():
			continue
		var target := int(def["target"])
		var progress := mini(target, _progress_for(def))
		(
			out
			. append(
				{
					"id": goal_id,
					"title": str(def["title"]),
					"reward": int(def["reward"]),
					"progress": progress,
					"target": target,
				}
			)
		)
	return out


func active_ids() -> Array[String]:
	return _active_ids.duplicate()


func completed_ids() -> Array[String]:
	return _completed_ids.duplicate()


func is_completed(goal_id: String) -> bool:
	return _completed_ids.has(goal_id)


func counter_value(key: String) -> int:
	return int(_counters.get(key, 0))


## Evaluates active goals, pays cash grants, refills open slots, and loops so
## already-satisfied stateful goals entering a slot complete immediately.
func evaluate() -> Array[Dictionary]:
	if _loading:
		return []
	var completed: Array[Dictionary] = []
	var filled_before := _fill_slots()
	var safety := 0
	var progressed := true
	while progressed and safety <= CATALOG.size():
		progressed = false
		safety += 1
		var still_active: Array[String] = []
		var newly_done: Array[Dictionary] = []
		for goal_id in _active_ids:
			var def := definition(goal_id)
			if def.is_empty():
				continue
			var target := int(def["target"])
			if _progress_for(def) >= target:
				newly_done.append(def)
			else:
				still_active.append(goal_id)
		if newly_done.is_empty():
			break
		_active_ids = still_active
		for def in newly_done:
			var gid := str(def["id"])
			_completed_ids.append(gid)
			var reward := int(def["reward"])
			_pay_reward(reward)
			var payload := {
				"id": gid,
				"title": str(def["title"]),
				"reward": reward,
				"progress": int(def["target"]),
				"target": int(def["target"]),
			}
			completed.append(payload)
			goal_completed.emit(payload)
		_fill_slots()
		progressed = true
	if filled_before or not completed.is_empty():
		changed.emit()
	return completed


func to_snapshot() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"active_ids": _active_ids.duplicate(),
		"completed_ids": _completed_ids.duplicate(),
		"counters": _counters.duplicate(true),
	}


func from_snapshot(data: Variant) -> bool:
	var problem := validation_problem(data)
	if problem != "":
		push_error("AirportGoals.from_snapshot: %s" % problem)
		return false
	var dict := data as Dictionary
	_active_ids.clear()
	for raw_id in dict["active_ids"]:
		_active_ids.append(str(raw_id))
	_completed_ids.clear()
	for raw_id in dict["completed_ids"]:
		_completed_ids.append(str(raw_id))
	_counters = _empty_counters()
	_counted_incident_ids.clear()
	for key in COUNTER_KEYS:
		_counters[key] = int(dict["counters"][key])
	changed.emit()
	return true


func _fill_slots() -> bool:
	var added := false
	while _active_ids.size() < ACTIVE_SLOTS:
		var next_id := _next_eligible_id()
		if next_id == "":
			break
		_active_ids.append(next_id)
		added = true
	return added


func _next_eligible_id() -> String:
	for def: Dictionary in CATALOG:
		var goal_id := str(def["id"])
		if _active_ids.has(goal_id) or _completed_ids.has(goal_id):
			continue
		if _is_eligible(def):
			return goal_id
	return ""


func _is_eligible(def: Dictionary) -> bool:
	var min_tier := int(def.get("min_tier", 1))
	if min_tier > 1 and _current_tier() < min_tier:
		return false
	if bool(def.get("require_incidents", false)):
		if incidents == null or not incidents.is_enabled():
			return false
	return true


func _progress_for(def: Dictionary) -> int:
	var kind := str(def.get("kind", ""))
	var value := 0
	match kind:
		"counter":
			value = counter_value(str(def.get("counter", "")))
		"checkin_desks":
			var grid := _active_grid()
			value = grid.count_objects(&"checkin_desk") if grid != null else 0
		"staff_hired":
			value = _total_hired_staff()
		"tier":
			value = _current_tier()
		"security_lanes":
			if (
				passengers != null
				and passengers.layout != null
				and passengers.layout.security_lanes != null
			):
				value = passengers.layout.security_lanes.complete_arches().size()
		"extra_land":
			var land := _active_land()
			value = land.bought if land != null else 0
		"certification":
			var cert := _resolve_certification()
			value = cert.earned_star() if cert != null else 0
	return value


func _total_hired_staff() -> int:
	if staff == null:
		return 0
	var total := 0
	for role: StaffMember.Role in StaffPanel.ROLES:
		total += staff.count(role)
	return total


func _current_tier() -> int:
	if unlocks != null:
		return unlocks.tier()
	if build_mode != null and build_mode.unlocks != null:
		return build_mode.unlocks.tier()
	if build_mode != null and not build_mode.require_unlocks:
		return BuildUnlocks.CAFE_TIER
	return BuildUnlocks.START_TIER


func _active_grid() -> BuildGrid:
	if build_mode != null and build_mode.grid != null:
		return build_mode.grid
	if passengers != null and passengers.grid != null:
		return passengers.grid
	return null


func _active_land() -> LandPlots:
	if build_mode != null and build_mode.land_tool != null:
		return build_mode.land_tool.land
	var grid := _active_grid()
	return grid.land if grid != null else null


func _resolve_certification() -> AirportCertification:
	if certification != null:
		return certification
	if save_game != null:
		certification = save_game.certification
		if certification != null:
			return certification
	if get_parent() != null:
		certification = (
			get_parent().get_node_or_null("AirportCertification") as AirportCertification
		)
	return certification


func _pay_reward(amount: int) -> void:
	if amount <= 0 or finances == null or finances.wallet == null:
		return
	finances.wallet.credit(amount, Wallet.Category.GRANT)


func _increment_counter(key: String) -> void:
	if _loading or not _counters.has(key):
		return
	_counters[key] = mini(int(_counters[key]) + 1, MAX_COUNT)
	if evaluate().is_empty():
		changed.emit()


func _connect_signals() -> void:
	if passengers != null:
		if not passengers.outcome.is_connected(_on_passenger_outcome):
			passengers.outcome.connect(_on_passenger_outcome)
		if not passengers.cafes.paid.is_connected(_on_cafe_paid):
			passengers.cafes.paid.connect(_on_cafe_paid)
		if not passengers.shops.paid.is_connected(_on_shop_paid):
			passengers.shops.paid.connect(_on_shop_paid)
	if flights != null and not flights.state_changed.is_connected(_on_flight_state_changed):
		flights.state_changed.connect(_on_flight_state_changed)
	if baggage != null and not baggage.bag_settled.is_connected(_on_bag_settled):
		baggage.bag_settled.connect(_on_bag_settled)
	if staff != null and not staff.staff_changed.is_connected(_on_staff_changed):
		staff.staff_changed.connect(_on_staff_changed)
	if unlocks != null and not unlocks.tier_changed.is_connected(_on_tier_changed):
		unlocks.tier_changed.connect(_on_tier_changed)
	if incidents != null:
		if not incidents.ended.is_connected(_on_incident_ended):
			incidents.ended.connect(_on_incident_ended)
		if not incidents.vip_resolved.is_connected(_on_incident_resolved):
			incidents.vip_resolved.connect(_on_incident_resolved)
		if not incidents.inspector_resolved.is_connected(_on_incident_resolved):
			incidents.inspector_resolved.connect(_on_incident_resolved)
	if certification != null and not certification.changed.is_connected(_on_certification_changed):
		certification.changed.connect(_on_certification_changed)
	if clock != null and not clock.ticked.is_connected(_on_clock_ticked):
		clock.ticked.connect(_on_clock_ticked)
	_sync_grid_and_land_signals()


func _sync_grid_and_land_signals() -> void:
	var grid := _active_grid()
	if grid != _bound_grid:
		if is_instance_valid(_bound_grid):
			if _bound_grid.edit_applied.is_connected(_on_grid_edit_applied):
				_bound_grid.edit_applied.disconnect(_on_grid_edit_applied)
			if _bound_grid.graph_changed.is_connected(_on_grid_graph_changed):
				_bound_grid.graph_changed.disconnect(_on_grid_graph_changed)
		_bound_grid = grid
		if _bound_grid != null:
			if not _bound_grid.edit_applied.is_connected(_on_grid_edit_applied):
				_bound_grid.edit_applied.connect(_on_grid_edit_applied)
			if not _bound_grid.graph_changed.is_connected(_on_grid_graph_changed):
				_bound_grid.graph_changed.connect(_on_grid_graph_changed)
	var land := _active_land()
	if land != _bound_land:
		if is_instance_valid(_bound_land):
			if _bound_land.changed.is_connected(_on_land_changed):
				_bound_land.changed.disconnect(_on_land_changed)
		_bound_land = land
		if _bound_land != null and not _bound_land.changed.is_connected(_on_land_changed):
			_bound_land.changed.connect(_on_land_changed)


func _unbind() -> void:
	if not _bound:
		return
	if is_instance_valid(passengers):
		if passengers.outcome.is_connected(_on_passenger_outcome):
			passengers.outcome.disconnect(_on_passenger_outcome)
		if passengers.cafes.paid.is_connected(_on_cafe_paid):
			passengers.cafes.paid.disconnect(_on_cafe_paid)
		if passengers.shops.paid.is_connected(_on_shop_paid):
			passengers.shops.paid.disconnect(_on_shop_paid)
	if is_instance_valid(flights) and flights.state_changed.is_connected(_on_flight_state_changed):
		flights.state_changed.disconnect(_on_flight_state_changed)
	if is_instance_valid(baggage) and baggage.bag_settled.is_connected(_on_bag_settled):
		baggage.bag_settled.disconnect(_on_bag_settled)
	if is_instance_valid(staff) and staff.staff_changed.is_connected(_on_staff_changed):
		staff.staff_changed.disconnect(_on_staff_changed)
	if is_instance_valid(unlocks) and unlocks.tier_changed.is_connected(_on_tier_changed):
		unlocks.tier_changed.disconnect(_on_tier_changed)
	if is_instance_valid(incidents):
		if incidents.ended.is_connected(_on_incident_ended):
			incidents.ended.disconnect(_on_incident_ended)
		if incidents.vip_resolved.is_connected(_on_incident_resolved):
			incidents.vip_resolved.disconnect(_on_incident_resolved)
		if incidents.inspector_resolved.is_connected(_on_incident_resolved):
			incidents.inspector_resolved.disconnect(_on_incident_resolved)
	if (
		is_instance_valid(certification)
		and certification.changed.is_connected(_on_certification_changed)
	):
		certification.changed.disconnect(_on_certification_changed)
	if is_instance_valid(clock) and clock.ticked.is_connected(_on_clock_ticked):
		clock.ticked.disconnect(_on_clock_ticked)
	if is_instance_valid(_bound_grid):
		if _bound_grid.edit_applied.is_connected(_on_grid_edit_applied):
			_bound_grid.edit_applied.disconnect(_on_grid_edit_applied)
		if _bound_grid.graph_changed.is_connected(_on_grid_graph_changed):
			_bound_grid.graph_changed.disconnect(_on_grid_graph_changed)
	if is_instance_valid(_bound_land) and _bound_land.changed.is_connected(_on_land_changed):
		_bound_land.changed.disconnect(_on_land_changed)
	_bound_grid = null
	_bound_land = null
	_bound = false


func _on_passenger_outcome(id: int, made: bool) -> void:
	if _loading or not made:
		return
	if passengers != null:
		var p := passengers.get_passenger(id)
		if p != null and not p.is_departing():
			return
	_increment_counter("departing_made")


func _on_cafe_paid(_passenger_id: int, _room_id: int, _amount: int) -> void:
	_increment_counter("cafe_served")


func _on_shop_paid(_passenger_id: int, _room_id: int, _amount: int) -> void:
	_increment_counter("kiosk_served")


func _on_bag_settled(_bag_id: int, _passenger_id: int, _flight_id: String, loaded: bool) -> void:
	if not loaded:
		return
	_increment_counter("bags_loaded")


func _on_flight_state_changed(flight_id: String, new_state: int) -> void:
	if _loading or new_state != FlightSim.State.DEPARTED or flights == null:
		return
	var touched := false
	if passengers != null:
		var summary := FlightResult.summarize(passengers, flight_id)
		if int(summary.get("made", 0)) > 0 and int(summary.get("missed", 0)) == 0:
			_counters["on_time_flights"] = mini(int(_counters["on_time_flights"]) + 1, MAX_COUNT)
			touched = true
	var contract := flights.contract_of(flights.flight_contract_id(flight_id))
	if FlightContract.is_charter(contract):
		_counters["charters_departed"] = mini(int(_counters["charters_departed"]) + 1, MAX_COUNT)
		touched = true
	if touched and evaluate().is_empty():
		changed.emit()


func _on_incident_ended(incident: Dictionary) -> void:
	if _loading:
		return
	if IncidentCatalogue.is_major(str(incident.get("kind", ""))):
		return
	var outcome := str(incident.get("outcome", ""))
	if (
		outcome
		in [
			IncidentSnapshot.NO_PLACE,
			IncidentMajors.NOT_HELD,
			IncidentMajors.FAILED,
			IncidentMajors.PENALTY,
		]
	):
		return
	_record_resolved_incident(incident)


func _on_incident_resolved(incident: Dictionary) -> void:
	if _loading:
		return
	var outcome := str(incident.get("outcome", ""))
	if outcome not in [IncidentMajors.PASSED, IncidentMajors.BONUS, IncidentMajors.NEUTRAL]:
		return
	_record_resolved_incident(incident)


func _record_resolved_incident(incident: Dictionary) -> void:
	var incident_id := int(incident.get("id", 0))
	if incident_id > 0:
		if _counted_incident_ids.has(incident_id):
			return
		_counted_incident_ids[incident_id] = true
	_increment_counter("incidents_resolved")


func _on_staff_changed() -> void:
	if _loading:
		return
	if evaluate().is_empty():
		changed.emit()


func _on_tier_changed(_tier: int) -> void:
	if _loading:
		return
	if evaluate().is_empty():
		changed.emit()


func _on_certification_changed() -> void:
	if _loading:
		return
	if evaluate().is_empty():
		changed.emit()


func _on_grid_edit_applied(_edit: BuildEdit, result: BuildResult) -> void:
	if _loading or not result.ok:
		return
	if evaluate().is_empty():
		changed.emit()


func _on_grid_graph_changed(_cells: Array[Vector2i]) -> void:
	if _loading:
		return
	if evaluate().is_empty():
		changed.emit()


func _on_land_changed() -> void:
	if _loading:
		return
	if evaluate().is_empty():
		changed.emit()


func _on_clock_ticked(_tick: int) -> void:
	if _loading:
		return
	if _active_ids.size() < ACTIVE_SLOTS:
		evaluate()
