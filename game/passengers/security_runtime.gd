class_name SecurityRuntime
extends RefCounted
## Security service at both tiers (decision security-lane-technical-design-
## one-station-per-lane-with-int, points 1, 2 and 4): admissions, the phases
## inside Passenger.Stage.SECURITY, the main service position, the one repack
## berth, the returns and completion. PassengerSim keeps the external queue
## (lane and holding list); this owns everything after admission.
##
## THE BASIC SCANNER serves one passenger at a time. SCAN: the passenger walks
## the passage while BASIC_SCAN_TICKS plus BASIC_BAG_TICKS per carry-on bag
## run down. A passenger with liquids or an alarm then repacks in place
## (REPACK), and the scanner stays held, so a repack blocks it. The passenger
## is cleared at the passage end.
##
## A SECURITY LANE (SecurityLanes geometry) overlaps passengers. UNPACK at the
## unpack cell, ARCH through the passage to the pickup cell, PICKUP, LEAVE to
## the exit cell, where the passenger is cleared. The main service position
## (unpack and arch) is held from admission until the passenger has passed
## the arch (reached the pickup cell); then the next one starts. A passenger
## with liquids or an alarm reserves the berth before it is admitted; when the
## berth is taken it waits at the queue front and nobody skips it. After the
## arch it steps aside (TO_BERTH), repacks there (REPACK), and walks the return
## route (RETURN), releasing the berth once it has stepped off it. A returning
## passenger is never put back in the queue: once it stands at the end of the
## return route it takes the next free main position ahead of a fresh
## admission, never interrupting a started one, and walks through the arch
## again from there. Body alarms resolve at the arch (body_resolved); bag flags
## resolve at the berth (bag_resolved).
##
## Gate places (decision gate-full-design-passengers-reserve-a-gate-seat-or-
## standing, points 2 and 3): the queue front is admitted through
## ready_front() and admit_front(), which GateCapacity.admit_all() calls for
## every station at once, so it can reserve a gate place first. Nobody is
## cleared without a place (the host's `placed` check, before every
## clearance): a basic scanner's passenger waits at the passage end, a lane's
## at the pickup cell, or at the exit cell when its place went while it walked
## there. Positions
## inside a lane are claimed before they are walked into and given up once
## left: the arch walk stops on the arch cell until no one else is at the
## pickup cell (in PICKUP, or stepping off it for the berth or the exit), and
## a passenger sets off from the pickup cell to the exit only while no one
## else is walking there.
##
## Work phases (SCAN, UNPACK, REPACK, PICKUP) keep their remaining integer work
## on the passenger and lose rate() each tick, so a helper officer can raise
## the rate without a saved deadline going stale. Walking phases end
## when the passenger stops walking. Everything happens in admission order on
## PassengerSim's tick, and the same code replays a copy of the state for the
## forecast (SecurityForecast).
##
## The host is PassengerSim, or a SecurityForecast replaying a copy: it gives
## `layout`, `tick`, get_passenger(id) and, unless `helper_from` names the
## station (a replay), `staff` (a StaffSim or null, read by rate()); bind()
## takes what to call when a
## passenger is admitted, when it is cleared and to ask whether it holds a
## gate place.

enum Phase { NONE, SCAN, UNPACK, ARCH, TO_BERTH, REPACK, RETURN, PICKUP, LEAVE, BODY_CHECK }

## Basic scanner, zero bags: today's 40-tick service, the passage walk in it.
const BASIC_SCAN_TICKS := 40
## Each bag is unpacked, X-rayed and packed again at the one scanner.
const BASIC_BAG_TICKS := 15
## Crisp wand pat-down at the arch on a body alarm (at rate 1; halved with helper).
const BODY_CHECK_TICKS := 20
## Bag search / repacking after an X-ray bag flag, at either tier (at rate 1).
const REPACK_TICKS := 80
## Maximum daily confiscated items stored per confiscation bin (newest kept).
const MAX_BIN_HISTORY := 12
## Light positive mood boost when a priority flyer clears a Fast-Track lane.
const FAST_TRACK_MOOD_BONUS := 5
## Repack / check work done per tick at a lane when a helper officer assists:
## the work takes half as long (ruling security-lane-staffing-one-officer-
## opens-a-lane-and-a-second).
const HELPER_RATE := 2
## Lane: stepping up to the tray table, and each bag into a tray. Walking the
## arch is most of the main position's hold, so these are kept small enough
## that a lane clears a stream about 1.9 times as fast as the basic scanner
## (TestSecurityTierBalance).
const LANE_UNPACK_TICKS := 3
const LANE_UNPACK_BAG_TICKS := 4
## Lane: collecting the trays at the pickup table.
const LANE_PICKUP_TICKS := 2
const LANE_PICKUP_BAG_TICKS := 4
const WORK_PHASES: Array[Phase] = [
	Phase.SCAN, Phase.UNPACK, Phase.REPACK, Phase.PICKUP, Phase.BODY_CHECK
]
const BASIC_PHASES: Array[Phase] = [Phase.SCAN, Phase.REPACK]
const LANE_PHASES: Array[Phase] = [
	Phase.UNPACK,
	Phase.ARCH,
	Phase.BODY_CHECK,
	Phase.TO_BERTH,
	Phase.REPACK,
	Phase.PICKUP,
	Phase.LEAVE,
]
## Lane phases that hold the main position: until the arch is passed.
const MAIN_PHASES: Array[Phase] = [Phase.UNPACK, Phase.ARCH, Phase.BODY_CHECK]

## Station id -> {"admitted": Array (ids, admission order), "returns": Array
## (ids, return order), "main": id holding the main position or 0, "berth":
## id holding or reserving the berth or 0}. A station with nobody admitted
## has no record.
var records := {}
## Daily confiscation bin counts and gag item histories.
var bins := ConfiscationBins.new()
## Station id -> the first tick a helper is on duty there (-1: never), set by
## a replay (SecurityForecast) from StaffPosts.helper_from(), since a replay
## does not step the staff. A station listed here is judged by it instead of
## by the host's staff.
var helper_from := {}
var _host: Object
var _admitted: Callable
var _cleared: Callable
var _placed: Callable


## `admitted(p)` puts an admitted passenger in Stage.SECURITY; `cleared(p)`
## sends a cleared one on to the gate; `placed(p)` says whether it may be
## cleared (GateCapacity.placed(); always with none). A null host lets go of it.
func bind(
	host: Object, admitted := Callable(), cleared := Callable(), placed := Callable()
) -> void:
	_host = host
	_admitted = admitted
	_cleared = cleared
	_placed = placed


## How much work a phase loses per tick at `station`: HELPER_RATE for a
## repack or body check while a helper officer is on duty there, else 1.
func rate(station: int, phase: int) -> int:
	if phase != Phase.REPACK and phase != Phase.BODY_CHECK:
		return 1
	return HELPER_RATE if _helped(station) else 1


## Per-passenger work rate at `station`. One unhelped officer serializes
## conflicting arch wanding (BODY_CHECK) and bag search (REPACK) so the single
## officer never works both simultaneously: BODY_CHECK pauses REPACK until
## resolved. With a helper officer on duty, both run simultaneously.
func rate_for(station: int, p: Passenger) -> int:
	var phase := p.security_phase as Phase
	if phase == Phase.REPACK:
		if is_lane(station):
			if not _helped(station) and _has_body_check(station):
				return 0
			return HELPER_RATE if _helped(station) else 1
		return 1
	if phase == Phase.BODY_CHECK:
		if _helped(station) and not _has_repack(station):
			return HELPER_RATE
		return 1
	return 1


func _has_body_check(station: int) -> bool:
	var rec: Dictionary = records.get(station, {})
	var main_id: int = rec.get("main", 0)
	if main_id == 0:
		return false
	var main_p: Passenger = _host.get_passenger(main_id)
	return main_p != null and main_p.security_phase == Phase.BODY_CHECK and main_p.security_work > 0


func _has_repack(station: int) -> bool:
	var rec: Dictionary = records.get(station, {})
	var berth_id: int = rec.get("berth", 0)
	if berth_id == 0:
		return false
	var berth_p: Passenger = _host.get_passenger(berth_id)
	return berth_p != null and berth_p.security_phase == Phase.REPACK and berth_p.security_work > 0


func _helped(station: int) -> bool:
	if helper_from.has(station):
		var from: int = helper_from[station]
		return from >= 0 and _host.tick >= from
	var staff: StaffSim = _host.staff
	return staff != null and staff.is_staffed(station, StaffMember.Slot.HELPER)


static func body_pending(p: Passenger) -> bool:
	return p.alarm and not p.body_resolved


static func bag_pending(p: Passenger) -> bool:
	return p.liquids and p.carry_on > 0 and not p.bag_resolved


static func incident_open(p: Passenger) -> bool:
	return body_pending(p) or bag_pending(p)


## The work a phase starts with for `p`, at rate 1.
static func work_for(phase: Phase, p: Passenger) -> int:
	match phase:
		Phase.SCAN:
			return BASIC_SCAN_TICKS + BASIC_BAG_TICKS * p.carry_on
		Phase.UNPACK:
			return LANE_UNPACK_TICKS + LANE_UNPACK_BAG_TICKS * p.carry_on
		Phase.PICKUP:
			return LANE_PICKUP_TICKS + LANE_PICKUP_BAG_TICKS * p.carry_on
		Phase.BODY_CHECK:
			return BODY_CHECK_TICKS
		Phase.REPACK:
			return REPACK_TICKS
	return 0


## What breaks the scheduler's rules in a station's record (see `records`)
## whose admitted passengers are `units`, between ticks, or "". `lane` says
## which tier. A basic scanner serves exactly one passenger, in SCAN or
## REPACK, who holds the main position, and has no berth or returns. At a
## lane the one passenger in UNPACK or ARCH holds the main position, or
## nobody does when there is none; a passenger stepping aside or repacking
## has an open incident and holds the berth, and so does one in UNPACK or ARCH
## with an open incident (reserved); otherwise only a returning passenger may
## still hold it (it is released on the tick after it steps off); a returning
## passenger's incident is resolved.
static func record_problem(record: Dictionary, units: Array, lane: bool) -> String:
	var in_main: Array[int] = []
	var needs_berth: Array[int] = []
	var by_id := {}
	for p: Passenger in units:
		by_id[p.id] = p
		var phase := p.security_phase as Phase
		if not (LANE_PHASES if lane else BASIC_PHASES).has(phase):
			return "passenger %d is in a phase this tier does not have" % p.id
		# Work only runs down from what its phase started with, and a walking
		# phase has none. Zero is allowed: a basic scanner's passenger can
		# still be walking the passage when its scan work has run out. A
		# version 7 save migrates to SCAN work of its old service end minus
		# the tick, at most the old 40-tick scan, which is within the cap.
		if p.security_work < 0 or p.security_work > work_for(phase, p):
			return "passenger %d has more work left than its phase starts with" % p.id
		if phase == Phase.BODY_CHECK and not body_pending(p):
			return "passenger %d is in body check with no open body alarm" % p.id
		var aside := phase == Phase.TO_BERTH or phase == Phase.REPACK
		if aside and not (bag_pending(p) if lane else incident_open(p)):
			return "passenger %d repacks with no open incident" % p.id
		if not lane or MAIN_PHASES.has(phase):
			in_main.append(p.id)
		if lane and (aside or (MAIN_PHASES.has(phase) and bag_pending(p))):
			needs_berth.append(p.id)
	if not lane and (units.size() != 1 or record["berth"] != 0 or not record["returns"].is_empty()):
		return "a basic scanner serves one passenger, with no berth or returns"
	if in_main.size() > 1 or record["main"] != (in_main[0] if in_main.size() == 1 else 0):
		return "the main position is not held by its one passenger in service"
	if needs_berth.size() > 1:
		return "two passengers need the one berth"
	var berth: int = record["berth"]
	if not needs_berth.is_empty() and berth != needs_berth[0]:
		return "passenger %d needs the berth it does not hold" % needs_berth[0]
	if needs_berth.is_empty() and berth != 0 and by_id[berth].security_phase != Phase.LEAVE:
		return "the berth is held by passenger %d, who does not need it" % berth
	return ""


## Whether `station` is a whole security lane (otherwise a basic scanner).
func is_lane(station: int) -> bool:
	return (
		_host != null
		and _host.layout != null
		and (_host.layout as TerminalLayout).security_lanes.is_complete(station)
	)


## The cell where a passenger of `station` is cleared: a lane's exit cell, a
## basic scanner's passage end. NO_CELL when it has neither.
func exit_cell(station: int) -> Vector2i:
	var layout: TerminalLayout = _host.layout
	if is_lane(station):
		return layout.security_lanes.lane(station)["exit"]
	var passage: Array = layout.passages.get(station, [])
	return passage[passage.size() - 1] if not passage.is_empty() else BuildObjectDef.NO_CELL


## Whether a passenger is admitted at any station.
func holds(id: int) -> bool:
	for record in records.values():
		if (record["admitted"] as Array).has(id):
			return true
	return false


## The record of `station` (see `records`), or an empty dictionary.
func record_of(station: int) -> Dictionary:
	return records.get(station, {})


## Phase changes and completions of the admitted passengers, in admission
## order. Runs before admit() on each tick.
func advance(station: int) -> void:
	if not records.has(station):
		return
	var record: Dictionary = records[station]
	for id: int in (record["admitted"] as Array).duplicate():
		_advance_one(station, record, _host.get_passenger(id))


## Gives a free main position to the first returning passenger who stands at
## the end of the return route. True when the main position is taken (now or
## already), so no queue front can be admitted on this tick.
func admit_return(station: int) -> bool:
	var record: Dictionary = records.get(station, {})
	if record.is_empty():
		return false
	return record["main"] != 0


## The queue front that admit_front() would admit (when `open`, once it
## stands on the first lane cell, unless it needs the berth and the berth is
## taken), or null. `queue` is PassengerSim's {"lane", "holding"} and `cells`
## the lane. Call it after admit_return() came back false.
func ready_front(station: int, queue: Dictionary, cells: Array, open: bool) -> Passenger:
	var lane: Array = queue["lane"]
	if not open or lane.is_empty():
		return null
	var front: Passenger = _host.get_passenger(lane[0])
	if front == null or front.stage != Passenger.Stage.SECURITY_QUEUE:
		return null
	if front.at != cells[0] or front.is_moving():
		return null
	var record: Dictionary = records.get(station, {})
	if is_lane(station) and bag_pending(front) and not record.is_empty() and record["berth"] != 0:
		return null
	return front


## Admits the queue front ready_front() gave; refuses and drops a stale
## non-SECURITY_QUEUE front or empty lane.
func admit_front(station: int, queue: Dictionary) -> bool:
	var lane: Array = queue.get("lane", [])
	if lane.is_empty():
		push_error("SecurityRuntime.admit_front: empty lane at station %d" % station)
		return false
	var front_id: int = lane.pop_front()
	var front: Passenger = _host.get_passenger(front_id)
	if front == null or front.stage != Passenger.Stage.SECURITY_QUEUE:
		var stage_name := "null"
		if front != null:
			var key: Variant = Passenger.Stage.find_key(front.stage)
			stage_name = str(front.stage) if key == null else str(key)
		push_error(
			(
				(
					"SecurityRuntime.admit_front: refused passenger %d at station %d "
					+ "(stage %s, expected SECURITY_QUEUE)"
				)
				% [front_id, station, stage_name]
			)
		)
		return false
	var record: Dictionary = records.get(station, {})
	var on_lane := is_lane(station)
	if record.is_empty():
		record = {"admitted": [], "returns": [], "main": 0, "berth": 0}
		records[station] = record
	(record["admitted"] as Array).append(front.id)
	record["main"] = front.id
	front.station = station
	_admitted.call(front)
	if on_lane:
		if bag_pending(front):
			record["berth"] = front.id
		_enter(front, Phase.UNPACK)
	else:
		var passage: Array[Vector2i] = []
		passage.assign(_host.layout.passages[station])
		_enter(front, Phase.SCAN, passage)
	return true


## Takes a passenger out of its station's service (it missed its flight or
## was sent away): its main position, berth and return place are freed.
func release(p: Passenger) -> void:
	for station: int in records.keys():
		var record: Dictionary = records[station]
		if not (record["admitted"] as Array).has(p.id):
			continue
		_forget(station, record, p.id)
		_reset(p)
		return


## Ends a station's service (it is gone or its lane changed): every admitted
## passenger loses its phase, without clearance. Returns their ids in
## admission order, for the caller to send back to security selection.
func drop(station: int) -> Array[int]:
	var out: Array[int] = []
	if not records.has(station):
		return out
	out.assign(records[station]["admitted"])
	records.erase(station)
	for id in out:
		_reset(_host.get_passenger(id))
	return out


## The records as JSON-safe entries, in station order.
func to_list() -> Array:
	var out := []
	var stations: Array = records.keys()
	stations.sort()
	for station: int in stations:
		var record: Dictionary = records[station]
		(
			out
			. append(
				{
					"station": station,
					"admitted": (record["admitted"] as Array).duplicate(),
					"returns": (record["returns"] as Array).duplicate(),
					"main": record["main"],
					"berth": record["berth"],
				}
			)
		)
	return out


## Replaces the records with checked ones (PassengerSnapshot) or a copy.
func restore(with_records: Dictionary) -> void:
	records = with_records.duplicate(true)


func _advance_one(station: int, record: Dictionary, p: Passenger) -> void:
	var phase := p.security_phase as Phase
	if WORK_PHASES.has(phase):
		p.security_work = maxi(p.security_work - rate_for(station, p), 0)
	var on_lane := is_lane(station)
	var lane := _lane(station) if on_lane else {}
	if record["berth"] == p.id and phase == Phase.LEAVE and p.at != lane["berth"]:
		record["berth"] = 0
	if p.is_moving() or (WORK_PHASES.has(phase) and p.security_work > 0):
		return
	match phase:
		Phase.SCAN:
			if incident_open(p):
				_enter(p, Phase.REPACK)
			elif _may_clear(p):
				_clear(station, record, p)
		Phase.UNPACK:
			_enter(p, Phase.ARCH, _arch_walk(station))
		Phase.ARCH:
			# Stopped on the arch cell: wand pat-down first if body alarm is open,
			# otherwise into the pickup cell once no one is there.
			if p.at != lane["pickup"]:
				if body_pending(p):
					_enter(p, Phase.BODY_CHECK)
				elif _pickup_free(record, lane["pickup"], p.id):
					var step: Array[Vector2i] = [p.at, lane["pickup"]]
					p.set_path(step)
				return
			record["main"] = 0
			if bag_pending(p):
				var aside: Array[Vector2i] = [p.at, lane["berth"]]
				_enter(p, Phase.TO_BERTH, aside)
			else:
				_enter(p, Phase.PICKUP)
		Phase.BODY_CHECK:
			if p.at != lane["pickup"]:
				if _pickup_free(record, lane["pickup"], p.id):
					var step: Array[Vector2i] = [p.at, lane["pickup"]]
					p.set_path(step)
				return
			p.body_resolved = true
			record["main"] = 0
			if bag_pending(p):
				var aside: Array[Vector2i] = [p.at, lane["berth"]]
				_enter(p, Phase.TO_BERTH, aside)
			else:
				_enter(p, Phase.PICKUP)
		Phase.TO_BERTH:
			_enter(p, Phase.REPACK)
		Phase.REPACK:
			if not on_lane:
				if _may_clear(p):
					if p.alarm:
						p.body_resolved = true
					if p.liquids and p.carry_on > 0:
						p.bag_resolved = true
					_clear(station, record, p)
				return
			if (
				_may_clear(p)
				and _pickup_free(record, lane["pickup"], p.id)
				and _exit_free(record, p.id)
			):
				p.bag_resolved = true
				if _host is PassengerSim:
					var bin_id: int = lane.get("confiscation_bin_id", 0)
					if bin_id != 0:
						bins.record(bin_id, SecuritySearchReasons.contraband_index(p.id))
				var out: Array[Vector2i] = [p.at, lane["pickup"], lane["exit"]]
				_enter(p, Phase.LEAVE, out)
		Phase.PICKUP:
			if _may_clear(p) and _exit_free(record, p.id):
				var out: Array[Vector2i] = [p.at, lane["exit"]]
				_enter(p, Phase.LEAVE, out)
		Phase.LEAVE:
			# At the exit cell: cleared only with its place, else it waits there.
			if _may_clear(p):
				_clear(station, record, p)


## The arch walk of a lane: its passage up to the arch cell, short of the
## pickup cell, which is claimed before it is walked into.
func _arch_walk(station: int) -> Array[Vector2i]:
	var walk: Array[Vector2i] = []
	walk.assign(_lane(station)["passage"])
	walk.pop_back()
	return walk


## Whether no one but `me` among `record`'s admitted passengers is at or about
## to cross the pickup cell `pickup`: in PICKUP, leaving from the berth via
## pickup, or stepping off pickup not yet halfway to the next cell.
func _pickup_free(record: Dictionary, pickup: Vector2i, me: int) -> bool:
	for id: int in record["admitted"]:
		if id == me:
			continue
		var other: Passenger = _host.get_passenger(id)
		if other.security_phase == Phase.PICKUP:
			return false
		if (
			other.security_phase == Phase.LEAVE
			and other.path.size() >= 3
			and other.path[1] == pickup
			and other.path_index == 0
		):
			return false
		var stepping := other.security_phase in [Phase.LEAVE, Phase.TO_BERTH]
		if stepping and other.at == pickup:
			if not other.is_moving():
				return false
			var next := other.path[other.path_index + 1]
			if other.seg_mm * 2 < Passenger.segment_mm(pickup, next):
				return false
	return true


## Whether no one but `me` is walking to the lane's exit cell.
func _exit_free(record: Dictionary, me: int) -> bool:
	for id: int in record["admitted"]:
		if id != me and _host.get_passenger(id).security_phase == Phase.LEAVE:
			return false
	return true


## Whether `p` may be cleared: it holds a gate place (the host's `placed`).
func _may_clear(p: Passenger) -> bool:
	return _placed.is_null() or _placed.call(p)


func _lane(station: int) -> Dictionary:
	return (_host.layout as TerminalLayout).security_lanes.lane(station)


## Starts a phase with its work, and walks `path` when one is given.
func _enter(p: Passenger, phase: Phase, path: Array[Vector2i] = []) -> void:
	p.security_phase = phase
	p.security_work = work_for(phase, p)
	if (phase == Phase.BODY_CHECK or phase == Phase.REPACK) and _host is PassengerSim:
		var is_alarm := phase == Phase.BODY_CHECK or body_pending(p)
		PassengerThoughts.security_search(p, _host.tick, is_alarm)
	if not path.is_empty():
		p.set_path(path)


func _clear(station: int, record: Dictionary, p: Passenger) -> void:
	if _host is PassengerSim and is_lane(station):
		var lane_dict := _lane(station)
		if bool(lane_dict.get("fast_track", false)) and SecurityLanes.is_priority(p):
			p.mood = mini(PassengerSim.MOOD_MAX, p.mood + FAST_TRACK_MOOD_BONUS)
			if p.at != Passenger.NO_CELL:
				PassengerThoughts.record(
					p, PassengerThoughts.Kind.FAST_TRACK, _host.tick, p.at, station
				)
	_forget(station, record, p.id)
	_reset(p)
	_cleared.call(p)


func _forget(station: int, record: Dictionary, id: int) -> void:
	(record["admitted"] as Array).erase(id)
	(record["returns"] as Array).erase(id)
	if record["main"] == id:
		record["main"] = 0
	if record["berth"] == id:
		record["berth"] = 0
	if (record["admitted"] as Array).is_empty():
		records.erase(station)


static func _reset(p: Passenger) -> void:
	p.security_phase = Phase.NONE
	p.security_work = 0


## Per-bin daily confiscated gag item totals and bounded history (newest kept).
class ConfiscationBins:
	extends RefCounted

	var entries := {}
	var day := 0

	func record(bin_id: int, item_index: int) -> void:
		if item_index < 0 or item_index >= SecuritySearchReasons.CONTRABAND_COUNT:
			return
		var entry: Dictionary = entries.get(bin_id, {"count": 0, "items": [] as Array[int]})
		entry["count"] = int(entry["count"]) + 1
		var items: Array = entry["items"]
		items.append(item_index)
		if items.size() > MAX_BIN_HISTORY:
			items = items.slice(items.size() - MAX_BIN_HISTORY)
		entry["items"] = items
		entries[bin_id] = entry

	func reset(new_day: int) -> void:
		entries.clear()
		day = new_day

	func prune(grid: BuildGrid) -> void:
		for bin_id: int in entries.keys():
			var obj := grid.get_object(bin_id)
			if obj.is_empty() or StringName(obj["def"]) != SecurityLanes.CONFISCATION_BIN:
				entries.erase(bin_id)

	func count(bin_id: int) -> int:
		return int(entries.get(bin_id, {}).get("count", 0))

	func items(bin_id: int) -> Array[int]:
		var out: Array[int] = []
		out.assign(entries.get(bin_id, {}).get("items", []))
		return out

	func to_dict() -> Dictionary:
		var out_bins := []
		var ids: Array = entries.keys()
		ids.sort()
		for bin_id: int in ids:
			var entry: Dictionary = entries[bin_id]
			(
				out_bins
				. append(
					{
						"bin": bin_id,
						"count": int(entry["count"]),
						"items": (entry["items"] as Array).duplicate(),
					}
				)
			)
		return {"day": day, "bins": out_bins}

	func restore(data: Dictionary) -> void:
		day = int(data["day"])
		entries.clear()
		for entry: Dictionary in data["bins"]:
			var typed: Array[int] = []
			for v in entry["items"]:
				typed.append(int(v))
			entries[int(entry["bin"])] = {"count": int(entry["count"]), "items": typed}
