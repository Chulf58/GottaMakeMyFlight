class_name Achievements
extends Node
## Local 22-achievement profile tracker (Stage 3 Slice S3-P4b, decision c5664a34).
## Strictly Career-gated (decision 26d799a0): Career achievements never unlock
## when `SaveGame.is_career_mode()` is false. Persisted profile-wide in
## `user://achievements.json` (covered by Steam Auto-Cloud), and shielded under
## `-s` / `--script` runs like `HudFlagSetting` unless an explicit non-protected
## `profile_path` is provided for tests.

signal unlocked(id: String, title: String, description: String)
signal changed

const SAVE_VERSION := 1
const SteamBridgeScript := preload("res://core/steam_bridge.gd")
const DEFAULT_PROFILE_PATH := SteamBridgeScript.ACHIEVEMENTS_PATH

const CATALOG: Array[Dictionary] = [
	{
		"id": "OPEN_FOR_BUSINESS",
		"title": "Open for Business",
		"description": "Open the airport",
		"career_only": true,
	},
	{
		"id": "FIRST_FLIGHT",
		"title": "First Departure",
		"description": "Depart your first flight",
		"career_only": true,
	},
	{
		"id": "PAX_50",
		"title": "Fifty Flyers",
		"description": "Serve 50 passengers",
		"career_only": true,
	},
	{
		"id": "PAX_250",
		"title": "Busy Concourse",
		"description": "Serve 250 passengers",
		"career_only": true,
	},
	{
		"id": "PAX_1000",
		"title": "Thousand Flyers",
		"description": "Serve 1,000 passengers",
		"career_only": true,
	},
	{
		"id": "CERT_1_STAR",
		"title": "Local Strip",
		"description": "Earn 1★ Local Strip Certification",
		"career_only": true,
	},
	{
		"id": "CERT_2_STAR",
		"title": "Regional Terminal",
		"description": "Earn 2★ Regional Terminal Certification",
		"career_only": true,
	},
	{
		"id": "CERT_3_STAR",
		"title": "National Hub",
		"description": "Earn 3★ National Hub Certification",
		"career_only": true,
	},
	{
		"id": "CERT_4_STAR",
		"title": "International Gateway",
		"description": "Earn 4★ International Gateway Certification",
		"career_only": true,
	},
	{
		"id": "CERT_5_STAR",
		"title": "World-Class Airport",
		"description": "Earn 5★ World-Class Airport Certification",
		"career_only": true,
	},
	{
		"id": "TIER_2_UNLOCK",
		"title": "Build Tier 2",
		"description": "Reach Build Tier 2",
		"career_only": true,
	},
	{
		"id": "TIER_3_UNLOCK",
		"title": "Build Tier 3",
		"description": "Reach Build Tier 3",
		"career_only": true,
	},
	{
		"id": "TIER_4_UNLOCK",
		"title": "Build Tier 4",
		"description": "Reach Build Tier 4",
		"career_only": true,
	},
	{
		"id": "SECURITY_PRO",
		"title": "Security Pro",
		"description": "Build a full Security Lane",
		"career_only": true,
	},
	{
		"id": "BAGGAGE_MASTER",
		"title": "Baggage Master",
		"description": "Open a ready Bag Room",
		"career_only": true,
	},
	{
		"id": "MEDIUM_RUNWAY",
		"title": "Medium Wings",
		"description": "Depart a Medium plane",
		"career_only": true,
	},
	{
		"id": "LARGE_RUNWAY",
		"title": "Heavy Jet",
		"description": "Depart a Large plane",
		"career_only": true,
	},
	{
		"id": "AIRLINE_GOLD",
		"title": "Gold Loyalty",
		"description": "Reach Gold loyalty with an airline",
		"career_only": true,
	},
	{
		"id": "HUB_PARTNER",
		"title": "Hub Partner",
		"description": "Accept a Gold Hub Contract",
		"career_only": true,
	},
	{
		"id": "ROOM_PRESTIGE_5",
		"title": "Five-Star Room",
		"description": "Raise any room to Prestige Level 5",
		"career_only": true,
	},
	{
		"id": "ANNUAL_AWARD",
		"title": "Award Winner",
		"description": "Win an Annual Airport Award",
		"career_only": true,
	},
	{
		"id": "AIRPORT_OF_YEAR",
		"title": "Airport of the Year",
		"description": "Win Airport of the Year",
		"career_only": true,
	},
]

const CERT_IDS := [
	"CERT_1_STAR",
	"CERT_2_STAR",
	"CERT_3_STAR",
	"CERT_4_STAR",
	"CERT_5_STAR",
]
const TIER_IDS := {
	2: "TIER_2_UNLOCK",
	3: "TIER_3_UNLOCK",
	4: "TIER_4_UNLOCK",
}
const PAX_MILESTONES := [
	[50, "PAX_50"],
	[250, "PAX_250"],
	[1000, "PAX_1000"],
]

## The file a script run leaves alone. DEFAULT_PROFILE_PATH in normal play;
## tests may temporarily repoint it to verify the shield without touching user data.
static var protected_path := DEFAULT_PROFILE_PATH

var profile_path := DEFAULT_PROFILE_PATH

var _unlocked := {}
var _loading := false
var _bound := false
var _flights: FlightSim
var _passengers: PassengerSim
var _unlocks: BuildUnlocks
var _certification: AirportCertification
var _awards: AirportAwards
var _offer_desk: OfferDesk
var _build_mode: BuildMode
var _baggage: BaggageSim
var _clock: SimClock
var _career_checker := Callable()


func _exit_tree() -> void:
	_unbind()


## True when `path` is the protected profile file and this process is a script run.
static func is_shielded(path: String) -> bool:
	return path == protected_path and Hints.launched_by_script(OS.get_cmdline_args())


## Catalog entry for `id`, or {} if unknown.
static func definition(id: String) -> Dictionary:
	for entry in CATALOG:
		if entry["id"] == id:
			return entry.duplicate()
	return {}


static func has_id(id: String) -> bool:
	for entry in CATALOG:
		if entry["id"] == id:
			return true
	return false


func total_count() -> int:
	return CATALOG.size()


func unlocked_count() -> int:
	return _unlocked.size()


func is_unlocked(id: String) -> bool:
	return _unlocked.has(id)


func unlocked_ids() -> Array[String]:
	var out: Array[String] = []
	for entry in CATALOG:
		var cid := str(entry["id"])
		if _unlocked.has(cid):
			out.append(cid)
	return out


func set_loading(loading: bool) -> void:
	_loading = loading


func is_loading() -> bool:
	return _loading


## Attempts to unlock `id`. Refuses unknown IDs, refuses Career-only achievements
## when `career_mode` is false, ignores repeats idempotently, persists when not
## shielded, forwards to SteamBridge, and emits `unlocked`.
func unlock(id: String, career_mode: bool = true) -> bool:
	if _loading:
		return false
	var def := definition(id)
	if def.is_empty():
		push_error("Achievements.unlock: unknown achievement id '%s'" % id)
		return false
	if bool(def.get("career_only", true)) and not career_mode:
		return false
	if _unlocked.has(id):
		return false
	_unlocked[id] = int(Time.get_unix_time_from_system())
	save_profile()
	var bridge := _steam_bridge()
	if is_instance_valid(bridge) and bridge.has_method("unlock_achievement"):
		bridge.call("unlock_achievement", id)
	changed.emit()
	unlocked.emit(id, str(def["title"]), str(def["description"]))
	return true


func _steam_bridge() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("SteamBridge")


## Loads unlocked achievements from `profile_path` (no-op when shielded).
func load_profile() -> bool:
	_unlocked.clear()
	if is_shielded(profile_path) or not FileAccess.file_exists(profile_path):
		changed.emit()
		return true
	var text := FileAccess.get_file_as_string(profile_path)
	var open_err := FileAccess.get_open_error()
	if open_err != OK:
		return _fail_load(
			"Achievements: cannot read %s (%s)" % [profile_path, error_string(open_err)]
		)
	var saved_map := _parse_saved_unlocked(text)
	if saved_map.is_empty() and not _valid_saved_profile(text):
		return false
	for raw_id: Variant in saved_map.keys():
		var cid := str(raw_id)
		if has_id(cid):
			_unlocked[cid] = int(saved_map[raw_id])
	changed.emit()
	return true


func _fail_load(message: String) -> bool:
	push_error(message)
	changed.emit()
	return false


func _valid_saved_profile(text: String) -> bool:
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return _fail_load("Achievements: invalid JSON in %s" % profile_path)
	var data := json.data as Dictionary
	if int(data.get("save_version", 0)) != SAVE_VERSION:
		return _fail_load("Achievements: unsupported save_version in %s" % profile_path)
	if typeof(data.get("unlocked", {})) != TYPE_DICTIONARY:
		return _fail_load("Achievements: 'unlocked' must be a dictionary in %s" % profile_path)
	return true


func _parse_saved_unlocked(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	var data := json.data as Dictionary
	if int(data.get("save_version", 0)) != SAVE_VERSION:
		return {}
	var raw: Variant = data.get("unlocked", {})
	return raw as Dictionary if typeof(raw) == TYPE_DICTIONARY else {}


## Persists unlocked achievements atomically to `profile_path` (no-op when shielded).
func save_profile() -> bool:
	if is_shielded(profile_path):
		return false
	var dir := profile_path.get_base_dir()
	var made := DirAccess.make_dir_recursive_absolute(dir)
	if made != OK:
		push_error("Achievements: cannot make folder %s (%s)" % [dir, error_string(made)])
		return false
	var payload := {
		"save_version": SAVE_VERSION,
		"unlocked": _unlocked.duplicate(),
	}
	var temp := profile_path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_error(
			"Achievements: cannot write %s (%s)" % [temp, error_string(FileAccess.get_open_error())]
		)
		return false
	file.store_string(JSON.stringify(payload, "\t", true, true))
	var write_err := file.get_error()
	file.close()
	if write_err != OK:
		DirAccess.remove_absolute(temp)
		push_error("Achievements: cannot write %s (%s)" % [temp, error_string(write_err)])
		return false
	var rename_err := DirAccess.rename_absolute(temp, profile_path)
	if rename_err != OK:
		push_error(
			"Achievements: cannot replace %s (%s)" % [profile_path, error_string(rename_err)]
		)
		return false
	return true


## Evaluates live world state and unlocks any newly satisfied achievements.
## Returns the IDs unlocked by this call.
func evaluate_world(
	flights: FlightSim = null,
	passengers: PassengerSim = null,
	unlocks: BuildUnlocks = null,
	certification: AirportCertification = null,
	awards: AirportAwards = null,
	offer_desk: OfferDesk = null,
	build_mode: BuildMode = null,
	baggage: BaggageSim = null,
	career_mode: bool = true
) -> Array[String]:
	var newly_unlocked: Array[String] = []
	if _loading or not career_mode:
		return newly_unlocked
	_check_operations(flights, passengers, unlocks, offer_desk, newly_unlocked, career_mode)
	_check_progression(unlocks, certification, awards, newly_unlocked, career_mode)
	_check_facilities(passengers, build_mode, baggage, newly_unlocked, career_mode)
	return newly_unlocked


## Connects live scene signals so Career achievements unlock automatically.
func bind(
	with_flights: FlightSim,
	with_passengers: PassengerSim,
	with_unlocks: BuildUnlocks,
	with_certification: AirportCertification,
	with_awards: AirportAwards,
	with_offer_desk: OfferDesk,
	with_build_mode: BuildMode,
	with_baggage: BaggageSim,
	with_clock: SimClock,
	career_checker: Callable = Callable()
) -> void:
	_unbind()
	_flights = with_flights
	_passengers = with_passengers
	_unlocks = with_unlocks
	_certification = with_certification
	_awards = with_awards
	_offer_desk = with_offer_desk
	_build_mode = with_build_mode
	_baggage = with_baggage
	_clock = with_clock
	_career_checker = career_checker

	if _certification != null and not _certification.certified.is_connected(_on_certified):
		_certification.certified.connect(_on_certified)
	if _awards != null and not _awards.ceremony_due.is_connected(_on_ceremony_due):
		_awards.ceremony_due.connect(_on_ceremony_due)
	if _unlocks != null and not _unlocks.tier_changed.is_connected(_on_tier_changed):
		_unlocks.tier_changed.connect(_on_tier_changed)
	if _flights != null:
		if not _flights.state_changed.is_connected(_on_flight_state):
			_flights.state_changed.connect(_on_flight_state)
		if _flights.gate != null and not _flights.gate.opened.is_connected(_on_airport_opened):
			_flights.gate.opened.connect(_on_airport_opened)
	if _passengers != null and not _passengers.outcome.is_connected(_on_passenger_outcome):
		_passengers.outcome.connect(_on_passenger_outcome)
	if _offer_desk != null and _offer_desk.board != null:
		if not _offer_desk.board.changed.is_connected(_on_offer_board_changed):
			_offer_desk.board.changed.connect(_on_offer_board_changed)
	if _build_mode != null:
		if not _build_mode.grid_changed.is_connected(_on_grid_changed):
			_build_mode.grid_changed.connect(_on_grid_changed)
		if (
			_build_mode.grid != null
			and not _build_mode.grid.edit_applied.is_connected(_on_grid_edit)
		):
			_build_mode.grid.edit_applied.connect(_on_grid_edit)
	if _clock != null and not _clock.ticked.is_connected(_on_clock_ticked):
		_clock.ticked.connect(_on_clock_ticked)
	_bound = true


func _unbind() -> void:
	if not _bound:
		return
	if is_instance_valid(_certification) and _certification.certified.is_connected(_on_certified):
		_certification.certified.disconnect(_on_certified)
	if is_instance_valid(_awards) and _awards.ceremony_due.is_connected(_on_ceremony_due):
		_awards.ceremony_due.disconnect(_on_ceremony_due)
	if is_instance_valid(_unlocks) and _unlocks.tier_changed.is_connected(_on_tier_changed):
		_unlocks.tier_changed.disconnect(_on_tier_changed)
	if is_instance_valid(_flights):
		if _flights.state_changed.is_connected(_on_flight_state):
			_flights.state_changed.disconnect(_on_flight_state)
		if (
			is_instance_valid(_flights.gate)
			and _flights.gate.opened.is_connected(_on_airport_opened)
		):
			_flights.gate.opened.disconnect(_on_airport_opened)
	if is_instance_valid(_passengers) and _passengers.outcome.is_connected(_on_passenger_outcome):
		_passengers.outcome.disconnect(_on_passenger_outcome)
	if is_instance_valid(_offer_desk) and _offer_desk.board != null:
		if _offer_desk.board.changed.is_connected(_on_offer_board_changed):
			_offer_desk.board.changed.disconnect(_on_offer_board_changed)
	if is_instance_valid(_build_mode):
		if _build_mode.grid_changed.is_connected(_on_grid_changed):
			_build_mode.grid_changed.disconnect(_on_grid_changed)
		if _build_mode.grid != null and _build_mode.grid.edit_applied.is_connected(_on_grid_edit):
			_build_mode.grid.edit_applied.disconnect(_on_grid_edit)
	if is_instance_valid(_clock) and _clock.ticked.is_connected(_on_clock_ticked):
		_clock.ticked.disconnect(_on_clock_ticked)
	_bound = false


func _is_career() -> bool:
	if _career_checker.is_valid():
		return bool(_career_checker.call())
	return true


func _try_unlock(id: String, career_mode: bool, out: Array[String]) -> void:
	if unlock(id, career_mode):
		out.append(id)


func _check_operations(
	flights: FlightSim,
	passengers: PassengerSim,
	unlocks: BuildUnlocks,
	offer_desk: OfferDesk,
	out: Array[String],
	career_mode: bool
) -> void:
	if flights != null and flights.opened_tick >= 0:
		_try_unlock("OPEN_FOR_BUSINESS", career_mode, out)
	if _any_flight_departed(flights, passengers, unlocks):
		_try_unlock("FIRST_FLIGHT", career_mode, out)
	var made := _made_passengers(passengers, unlocks)
	for pair: Array in PAX_MILESTONES:
		if made >= int(pair[0]):
			_try_unlock(str(pair[1]), career_mode, out)
	if _has_gold_loyalty(offer_desk):
		_try_unlock("AIRLINE_GOLD", career_mode, out)
	if _has_hub_contract(flights):
		_try_unlock("HUB_PARTNER", career_mode, out)


func _check_progression(
	unlocks: BuildUnlocks,
	certification: AirportCertification,
	awards: AirportAwards,
	out: Array[String],
	career_mode: bool
) -> void:
	if certification != null:
		for star in range(1, mini(certification.earned_star(), CERT_IDS.size()) + 1):
			_try_unlock(CERT_IDS[star - 1], career_mode, out)
		if certification.medium_departed() > 0:
			_try_unlock("MEDIUM_RUNWAY", career_mode, out)
		if certification.large_departed() > 0:
			_try_unlock("LARGE_RUNWAY", career_mode, out)
	if unlocks != null and not unlocks.is_unlock_all():
		for tier_val: int in TIER_IDS.keys():
			if unlocks.tier() >= tier_val:
				_try_unlock(str(TIER_IDS[tier_val]), career_mode, out)
	if awards != null and awards.trophies_earned() > 0:
		_try_unlock("ANNUAL_AWARD", career_mode, out)
	if _report_won_airport_of_year(_awards_report(awards)):
		_try_unlock("AIRPORT_OF_YEAR", career_mode, out)


func _check_facilities(
	passengers: PassengerSim,
	build_mode: BuildMode,
	baggage: BaggageSim,
	out: Array[String],
	career_mode: bool
) -> void:
	if not is_unlocked("SECURITY_PRO") and _has_security_lane(passengers, build_mode):
		_try_unlock("SECURITY_PRO", career_mode, out)
	if not is_unlocked("BAGGAGE_MASTER") and _has_ready_bag_room(baggage, build_mode):
		_try_unlock("BAGGAGE_MASTER", career_mode, out)
	if not is_unlocked("ROOM_PRESTIGE_5") and _has_room_prestige_5(build_mode):
		_try_unlock("ROOM_PRESTIGE_5", career_mode, out)


static func _made_passengers(passengers: PassengerSim, unlocks: BuildUnlocks) -> int:
	var from_unlocks := unlocks.made_total() if unlocks != null else 0
	var from_pax := passengers.made_count() if passengers != null else 0
	return maxi(from_unlocks, from_pax)


static func _any_flight_departed(
	flights: FlightSim, passengers: PassengerSim, unlocks: BuildUnlocks
) -> bool:
	if flights != null:
		for fid in flights.flight_ids():
			if flights.state_of(fid) == FlightSim.State.DEPARTED:
				return true
	return _made_passengers(passengers, unlocks) > 0


static func _has_gold_loyalty(offer_desk: OfferDesk) -> bool:
	if offer_desk == null or offer_desk.board == null:
		return false
	for group: Array in OfferBoard.TIER_AIRLINES:
		for airline: String in group:
			if offer_desk.board.loyalty_tier(airline) == OfferBoard.LOYALTY_TIER_GOLD:
				return true
	return false


static func _has_hub_contract(flights: FlightSim) -> bool:
	if flights == null:
		return false
	for cid in flights.contract_ids():
		if FlightContract.is_hub(flights.contract_of(cid)):
			return true
	return false


static func _has_security_lane(passengers: PassengerSim, build_mode: BuildMode) -> bool:
	if build_mode != null and build_mode.grid != null:
		var lanes := SecurityLanes.new()
		lanes.rebuild(build_mode.grid)
		if not lanes.complete_arches().is_empty():
			return true
	if (
		passengers != null
		and passengers.layout != null
		and passengers.layout.security_lanes != null
	):
		return not passengers.layout.security_lanes.complete_arches().is_empty()
	return false


static func _has_ready_bag_room(baggage: BaggageSim, build_mode: BuildMode) -> bool:
	if baggage != null and baggage.grid != null:
		return baggage.has_ready_bag_room()
	if build_mode != null and build_mode.grid != null:
		for room_id in build_mode.grid.room_ids():
			if build_mode.grid.get_room(room_id)["type"] == BeltShaper.BAG_ROOM:
				if RoomRules.status(build_mode.grid, room_id).ok:
					return true
	return false


static func _has_room_prestige_5(build_mode: BuildMode) -> bool:
	if build_mode == null or build_mode.grid == null:
		return false
	for room_id in build_mode.grid.room_ids():
		var info := RoomPrestige.evaluate_room(build_mode.grid, room_id)
		if int(info.get("level", RoomPrestige.MIN_LEVEL)) >= RoomPrestige.MAX_LEVEL:
			return true
	return false


func _on_certified(award: Dictionary) -> void:
	if _loading or not _is_career():
		return
	var star := int(award.get("star", 0))
	for s in range(1, mini(star, CERT_IDS.size()) + 1):
		unlock(CERT_IDS[s - 1], true)


func _on_ceremony_due(report: Dictionary) -> void:
	if _loading or not _is_career():
		return
	if int(report.get("won_count", 0)) > 0:
		unlock("ANNUAL_AWARD", true)
	if _report_won_airport_of_year(report):
		unlock("AIRPORT_OF_YEAR", true)


static func _awards_report(awards: AirportAwards) -> Dictionary:
	if awards == null:
		return {}
	if awards.has_method("last_report"):
		var rep: Variant = awards.call("last_report")
		return rep as Dictionary if rep is Dictionary else {}
	var raw: Variant = awards.get("_last_report")
	return raw as Dictionary if raw is Dictionary else {}


static func _report_won_airport_of_year(report: Dictionary) -> bool:
	if report.is_empty():
		return false
	var won_ids: Variant = report.get("won_ids", [])
	if (
		won_ids is Array
		and (
			(won_ids as Array).has(&"airport_of_the_year")
			or (won_ids as Array).has("airport_of_the_year")
		)
	):
		return true
	for cat: Variant in report.get("categories", []):
		if (
			cat is Dictionary
			and StringName((cat as Dictionary).get("id", &"")) == &"airport_of_the_year"
			and bool((cat as Dictionary).get("won", false))
		):
			return true
	return false


func _on_tier_changed(tier: int) -> void:
	if _loading or not _is_career():
		return
	if _unlocks != null and _unlocks.is_unlock_all():
		return
	for tier_val: int in TIER_IDS.keys():
		if tier >= tier_val:
			unlock(str(TIER_IDS[tier_val]), true)


func _on_airport_opened(_tick: int) -> void:
	if _loading or not _is_career():
		return
	unlock("OPEN_FOR_BUSINESS", true)


func _on_flight_state(flight_id: String, state: int) -> void:
	if _loading or not _is_career() or state != FlightSim.State.DEPARTED or _flights == null:
		return
	unlock("FIRST_FLIGHT", true)
	var contract := _flights.contract_of(_flights.flight_contract_id(flight_id))
	var plane_size := str(contract.get("plane_size", FlightSim.STARTER_TERMS["plane_size"]))
	if plane_size == PlaneClasses.MEDIUM:
		unlock("MEDIUM_RUNWAY", true)
	elif plane_size == PlaneClasses.LARGE:
		unlock("MEDIUM_RUNWAY", true)
		unlock("LARGE_RUNWAY", true)
	if _has_gold_loyalty(_offer_desk):
		unlock("AIRLINE_GOLD", true)


func _on_passenger_outcome(_id: int, made: bool) -> void:
	if _loading or not _is_career() or not made:
		return
	var total := _made_passengers(_passengers, _unlocks)
	for pair: Array in PAX_MILESTONES:
		if total >= int(pair[0]):
			unlock(str(pair[1]), true)


func _on_offer_board_changed() -> void:
	if _loading or not _is_career():
		return
	if _has_gold_loyalty(_offer_desk):
		unlock("AIRLINE_GOLD", true)
	if _has_hub_contract(_flights):
		unlock("HUB_PARTNER", true)


func _on_grid_edit(_edit: BuildEdit, result: BuildResult) -> void:
	if result != null and result.ok:
		_on_grid_changed()


func _on_grid_changed() -> void:
	if _loading or not _is_career():
		return
	var unused: Array[String] = []
	_check_facilities(_passengers, _build_mode, _baggage, unused, true)


func _on_clock_ticked(_tick: int) -> void:
	if _loading or not _is_career():
		return
	if not is_unlocked("OPEN_FOR_BUSINESS") and _flights != null and _flights.opened_tick >= 0:
		unlock("OPEN_FOR_BUSINESS", true)
	if not is_unlocked("AIRLINE_GOLD") and _has_gold_loyalty(_offer_desk):
		unlock("AIRLINE_GOLD", true)
	if not is_unlocked("HUB_PARTNER") and _has_hub_contract(_flights):
		unlock("HUB_PARTNER", true)
