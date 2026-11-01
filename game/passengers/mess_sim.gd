# gdlint:disable = max-public-methods
# MessSim is the mess API: the visit sims report uses to it, PassengerSim steps
# it, the save reads and checks it, and the cleaner and views of later slices
# read single messes, bins and counters, so it has more than 20 public methods.
class_name MessSim
extends RefCounted
## Messes left by real visits (decisions cleaner-staff-and-messes-visits-leave-
## messes-bins-fill-pooled-cleaners-nearest-mess and mess-sim-technical-design-
## messsim-under-passengersim-counters-refuse-at-cap). Owned by PassengerSim
## beside DecorEffect and stepped inside its tick; nothing here is random.
##
## Every source keeps a use counter, and every Nth real use leaves a mess at the
## spot where it was used: a cafe seat when the visit is settled (a walk-on
## stall's counter for the stall), a kiosk display slot when its browse is paid,
## a toilet room when a stall is actually used (a visit given up on the way
## counts nothing), and a shower room when a shower finishes (a shop completion
## in a room of the shower type). Cafes and kiosks leave LITTER, a bar a SPILL,
## a shower a SPILL and a toilet a TOILET mess.
##
## Litter is decided at the use spot: the nearest bin that is not full within
## BIN_RANGE of it, seen from it, takes it (its fill goes up by one), and only
## with no such bin does LITTER land there. Bins are the decor bin piece, keyed
## by object id. Only LITTER grows: left GROW_TICKS it becomes a grown mess with
## a larger radius and more dirt.
##
## A new mess on a cell that already has one of its kind merges into it. At
## MAX_MESSES a new mess merges into the nearest one of its kind within
## MERGE_RANGE, and otherwise it is refused and counted in `overflow`; an
## unrelated far mess is never grown.
##
## Messes never block walking: the grid is not touched. Each mess keeps a
## walkable approach cell for the cleaner (its own cell when that is walkable).
## After a grid edit, on the next tick (reconcile()), a mess whose floor went is
## dropped, one whose approach cell is no longer walkable gets a new one or is
## dropped when none is left, a removed bin's fill is dropped and the counter
## of a removed seat, counter, display or room is dropped.
##
## Mood: a passenger inside the terminal who stands within a mess's radius
## (Chebyshev, from the mess cell) and can see it (ScreenCoverage.sight_clear)
## loses mood on its beat, like DecorEffect's calm in reverse: the dirt of the
## messes in view, summed and capped at MAX_DIRT, is paid out as mood points per
## DecorEffect.PERIOD_BEATS beats, spread evenly. A mess's dirt ramps with age.
## The cells each mess is seen from are a cache rebuilt after an add, a removal,
## a growth, a load and any grid change, never saved.
##
## Cleaners (StaffSim, CleanerJobs) claim a mess (claim(), its claimed_by is the
## cleaner's member id) so no other cleaner takes it, then clean it (clean()),
## or claim a full bin (full_bins(); a bin's claim is its cleaner's job) and empty it
## (empty_bin()). A claimed mess that goes another way (an edit took its floor,
## remove()) emits claim_dropped, so its cleaner lets go of the job at once.
##
## Saved as one SaveGame part ("messes"): the messes, the next id, the bin fill,
## every use counter and the diagnostics, so a load plays on exactly like an
## unbroken run. A saved claimed_by is any whole number of 0 or more here; that
## it names a cleaner whose job is that mess is checked with the staff
## (StaffSnapshot), which load after the messes.

## A mess claimed by `cleaner` was removed by something other than its
## cleaner's work: an edit (reconcile()) or remove().
signal claim_dropped(id: int, cleaner: int)

enum Kind { LITTER, SPILL, TOILET }

## Every Nth real use of one source leaves a mess. Tuning values.
const CAFE_EVERY := 3
const KIOSK_EVERY := 4
const TOILET_EVERY := 4
const SHOWER_EVERY := 3
## A bin takes litter dropped this many cells from it (Chebyshev), in sight.
const BIN_RANGE := 3
## Litter a bin holds before it is full and takes no more.
const BIN_CAPACITY := 12
const BIN_ID := &"trash_can"
## The most messes at once.
const MAX_MESSES := 40
## At the cap, a new mess merges into one of its kind this near.
const MERGE_RANGE := 2
## Litter left this long grows (one game hour is 1200 ticks).
const GROW_TICKS := 2400
## A mess this old costs AGED_DIRT instead of DIRT.
const RAMP_TICKS := 1200
## How far a mess is seen from, in cells; a grown one further.
const RADIUS := 3
const GROWN_RADIUS := 5
## Mood points per DecorEffect.PERIOD_BEATS beats a mess in view costs: fresh,
## aged and grown.
const DIRT := 1
const AGED_DIRT := 2
const GROWN_DIRT := 3
## The most one passenger loses per period, however many messes it sees: 0.4
## mood a second, beside a queue's 1 a second.
const MAX_DIRT := 4
## Food venues whose guests spill rather than litter.
const SPILL_VENUES: Array[StringName] = [&"bar"]
const KIOSK_TYPE := &"kiosk"
const SHOWER_TYPE := &"shower"
const NO_CELL := Vector2i(-1, -1)
const SAVE_VERSION := 1
## Source key kinds and how many ":" parts each has: "seat:<table>:<index>",
## "counter:<id>", "slot:<display>:<index>", "toilet:<room>", "shower:<room>".
const SOURCE_PARTS := {"seat": 3, "counter": 2, "slot": 3, "toilet": 2, "shower": 2}
const COUNTER_ID := &"cafe_counter"
## The approach cell is looked for on these steps from the mess cell, in order.
const AROUND: Array[Vector2i] = [
	Vector2i(0, 1),
	Vector2i(1, 0),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(1, 1),
	Vector2i(-1, 1),
	Vector2i(1, -1),
	Vector2i(-1, -1),
]

## New messes refused at the cap with nothing of their kind near.
var overflow := 0
## New messes merged into one already there.
var merged := 0
## Litter a bin took instead of the floor.
var caught := 0
## Set by a grid edit: the messes, bins and counters are brought in line on the
## next tick. SaveGame waits while it is set.
var stale := false

var _sim: PassengerSim
var _grid: BuildGrid
## Mess id -> {"id", "cell", "approach", "kind", "born_tick", "grown",
## "claimed_by"}.
var _messes: Dictionary = {}
var _next_id := 1
## Bin object id -> litter in it.
var _bins: Dictionary = {}
## Source key -> real uses counted.
var _counters: Dictionary = {}
## Derived: cell -> ids of the messes seen from it.
var _seen: Dictionary = {}
var _seen_dirty := true


static func radius_of(mess: Dictionary) -> int:
	return GROWN_RADIUS if mess["grown"] else RADIUS


## The dirt `mess` costs at `tick`: more once it is old, most once grown.
static func dirt_of(mess: Dictionary, tick: int) -> int:
	if mess["grown"]:
		return GROWN_DIRT
	return AGED_DIRT if tick - int(mess["born_tick"]) >= RAMP_TICKS else DIRT


static func seat_source(seat_key: String) -> String:
	return "seat:%s" % seat_key


static func counter_source(counter_id: int) -> String:
	return "counter:%d" % counter_id


static func slot_source(slot_key: String) -> String:
	return "slot:%s" % slot_key


static func toilet_source(room_id: int) -> String:
	return "toilet:%d" % room_id


static func shower_source(room_id: int) -> String:
	return "shower:%d" % room_id


## Whether what a source key names is on `grid` as that kind of source: a seat
## index the piece has, a cafe counter, a browse slot index the display piece
## has, a room of the toilet or shower type. False for a key of no known shape.
static func source_exists(grid: BuildGrid, source: String) -> bool:
	var parts := source.split(":")
	if parts.size() != int(SOURCE_PARTS.get(parts[0], 0)):
		return false
	for part in parts.slice(1):
		if not part.is_valid_int():
			return false
	var id := parts[1].to_int()
	var index := parts[2].to_int() if parts.size() == 3 else 0
	var def := BuildCatalog.get_def(grid.get_object(id).get("def", &""))
	match parts[0]:
		"toilet", "shower":
			return grid.get_room(id).get("type", &"") == StringName(parts[0])
		"counter":
			return def != null and def.id == COUNTER_ID
		"seat":
			return def != null and index >= 0 and index < def.seats.size()
	return def != null and index >= 0 and index < slots_of(def)


## How many browse slots a display piece `def` gives in the shop room types
## that use it (ShopLayout); 0 for a piece no shop browses at.
static func slots_of(def: BuildObjectDef) -> int:
	var most := 0
	for type_id in RoomTypes.ids():
		var type := RoomTypes.get_type(type_id)
		if type.shop and type.seat_piece == def.id:
			most = maxi(most, mini(type.seats_per_piece, def.size.x * def.size.y))
	return most


## The walkable cell a cleaner stands on to clean a mess at `cell`: the cell
## itself, else the first walkable neighbour in AROUND order; NO_CELL for none.
static func approach_for(grid: BuildGrid, cell: Vector2i) -> Vector2i:
	if grid.is_walkable(cell):
		return cell
	for step in AROUND:
		if grid.is_walkable(cell + step):
			return cell + step
	return NO_CELL


func bind(sim: PassengerSim) -> void:
	_sim = sim
	_grid = sim.grid
	_seen_dirty = true
	if _grid != null:
		# Methods, not lambdas: a lambda reading a member would hold this sim,
		# which holds the grid, and neither would ever free.
		_grid.graph_changed.connect(_on_graph_changed)
		# A room edit dirties no cell, so graph_changed misses a removed room.
		_grid.edit_applied.connect(_on_edit_applied)


## A cafe visit was settled: one use of its seat (of its counter at a walk-on
## stall). A visit whose seat or counter is gone leaves nothing.
func cafe_used(visit: CafeVisit) -> void:
	var kind := Kind.SPILL if SPILL_VENUES.has(visit.venue) else Kind.LITTER
	if visit.walk_on():
		var spot := _grid.interaction_cell(visit.counter)
		if spot != BuildObjectDef.NO_CELL:
			_use(counter_source(visit.counter), CAFE_EVERY, kind, spot)
	elif not visit.seat.is_empty():
		_use(seat_source(visit.seat_key), CAFE_EVERY, kind, visit.seat["approach"])


## A shop visit's browse finished in a room of type `type_id`: a kiosk's slot
## or a shower room counts one use. Other shop types leave nothing.
func shop_used(visit: ShopVisit, type_id: StringName) -> void:
	if visit.slot.is_empty():
		return
	var spot: Vector2i = visit.slot["approach"]
	if type_id == KIOSK_TYPE:
		_use(slot_source(visit.slot_key()), KIOSK_EVERY, Kind.LITTER, spot)
	elif type_id == SHOWER_TYPE:
		_use(shower_source(visit.room), SHOWER_EVERY, Kind.SPILL, spot)


## A toilet stall was used (the need reset in it): one use of its room.
func toilet_used(visit: ToiletVisit) -> void:
	if not visit.stall.is_empty():
		_use(toilet_source(visit.room), TOILET_EVERY, Kind.TOILET, visit.stall["approach"])


## Adds a mess of `kind` at `cell` now and returns its id, or the id of the
## mess it merged into, or 0 when it was refused at the cap. A cell with no
## floor or no walkable approach is refused with an error.
func add(kind: Kind, cell: Vector2i) -> int:
	var approach := NO_CELL
	if _grid.floor_at(cell) != BuildGrid.FLOOR_NONE:
		approach = approach_for(_grid, cell)
	if approach == NO_CELL:
		push_error("MessSim.add: no floor or no way to %s" % cell)
		return 0
	var same := _same_kind_near(kind, cell, 0)
	if same == 0 and _messes.size() >= MAX_MESSES:
		same = _same_kind_near(kind, cell, MERGE_RANGE)
		if same == 0:
			overflow += 1
			return 0
	if same != 0:
		merged += 1
		return same
	var id := _next_id
	_next_id += 1
	_messes[id] = {
		"id": id,
		"cell": cell,
		"approach": approach,
		"kind": kind,
		"born_tick": _sim.tick,
		"grown": false,
		"claimed_by": 0,
	}
	_seen_dirty = true
	return id


## Removes a mess; false for an unknown id. A claimed one emits claim_dropped.
func remove(id: int) -> bool:
	var cleaner := int(_messes.get(id, {}).get("claimed_by", 0))
	if not _messes.erase(id):
		return false
	_seen_dirty = true
	if cleaner != 0:
		claim_dropped.emit(id, cleaner)
	return true


## Gives mess `id` to `cleaner` (a member id); false, changing nothing, for an
## unknown mess or one already claimed.
func claim(id: int, cleaner: int) -> bool:
	if not _messes.has(id) or int(_messes[id]["claimed_by"]) != 0 or cleaner < 1:
		return false
	_messes[id]["claimed_by"] = cleaner
	return true


## Lets go of `cleaner`'s claim on mess `id`, if it holds one.
func release(id: int, cleaner: int) -> void:
	if _messes.has(id) and int(_messes[id]["claimed_by"]) == cleaner:
		_messes[id]["claimed_by"] = 0


## A cleaner finished mess `id`: it is gone, and so is the mood it cost. False
## for an unknown id. Emits nothing: the cleaner is the one that cleaned it.
func clean(id: int) -> bool:
	if not _messes.erase(id):
		return false
	_seen_dirty = true
	return true


## The bins on the grid that are full, in id order: a cleaner empties them.
func full_bins() -> Array[int]:
	var full: Array[int] = []
	for bin: int in _bins.keys():
		if fill_of(bin) >= BIN_CAPACITY and _grid.get_object(bin).get("def", &"") == BIN_ID:
			full.append(bin)
	full.sort()
	return full


## A cleaner emptied `bin`: its fill goes back to 0, so it takes litter again.
## False for an object that is not a bin.
func empty_bin(bin: int) -> bool:
	if _grid.get_object(bin).get("def", &"") != BIN_ID:
		return false
	_bins.erase(bin)
	return true


## The mess records and bin fill as they stand, for the staff load check
## (StaffSnapshot): the same shape as checked() returns them. Read only.
func claim_state() -> Dictionary:
	return {"messes": _messes, "bins": _bins}


func mess_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_messes.keys())
	ids.sort()
	return ids


func mess_count() -> int:
	return _messes.size()


## A copy of the mess record, or an empty dictionary for an unknown id.
func get_mess(id: int) -> Dictionary:
	return _messes.get(id, {}).duplicate()


func next_id() -> int:
	return _next_id


## Litter in the bin with object id `bin`.
func fill_of(bin: int) -> int:
	return int(_bins.get(bin, 0))


## Real uses counted for a source key (seat_source() and the rest).
func uses_of(source: String) -> int:
	return int(_counters.get(source, 0))


## Every source key with a count, sorted.
func sources() -> Array[String]:
	var keys: Array[String] = []
	keys.assign(_counters.keys())
	keys.sort()
	return keys


## The bin that takes litter dropped at `cell`: the nearest one within
## BIN_RANGE that is not full and is seen from `cell`, ties to the lower id;
## 0 for none.
func bin_for(cell: Vector2i) -> int:
	var best := 0
	var best_distance := BIN_RANGE + 1
	for id in _sorted_objects():
		var record := _grid.get_object(id)
		if record["def"] != BIN_ID or fill_of(id) >= BIN_CAPACITY:
			continue
		var at: Vector2i = record["anchor"]
		var distance := maxi(absi(at.x - cell.x), absi(at.y - cell.y))
		if distance < best_distance and ScreenCoverage.sight_clear(_grid, at, cell):
			best = id
			best_distance = distance
	return best


## The summed dirt of the messes seen from `cell`, before the cap.
func dirt_at(cell: Vector2i) -> int:
	var total := 0
	for id: int in seen().get(cell, []):
		total += dirt_of(_messes[id], _sim.tick)
	return total


## Every cell a mess is seen from, as cell -> mess ids. Worked out again only
## after a change.
func seen() -> Dictionary:
	if _seen_dirty:
		_seen.clear()
		for id in mess_ids():
			var mess: Dictionary = _messes[id]
			var at: Vector2i = mess["cell"]
			var radius := radius_of(mess)
			for y in range(at.y - radius, at.y + radius + 1):
				for x in range(at.x - radius, at.x + radius + 1):
					var cell := Vector2i(x, y)
					if _grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
						continue
					if ScreenCoverage.sight_clear(_grid, at, cell):
						if not _seen.has(cell):
							_seen[cell] = []
						(_seen[cell] as Array).append(id)
		_seen_dirty = false
	return _seen


## Once a tick, before the passengers step: an edit's reconcile, then growth.
func step() -> void:
	if stale:
		reconcile()
	for id in mess_ids():
		var mess: Dictionary = _messes[id]
		if mess["kind"] != Kind.LITTER or mess["grown"]:
			continue
		if _sim.tick - int(mess["born_tick"]) >= GROW_TICKS:
			mess["grown"] = true
			_seen_dirty = true


## Brings the messes, bins and counters in line with the grid (see the class
## notes).
func reconcile() -> void:
	stale = false
	_seen_dirty = true
	for id in mess_ids():
		var mess: Dictionary = _messes[id]
		var approach := NO_CELL
		if _grid.floor_at(mess["cell"]) != BuildGrid.FLOOR_NONE:
			approach = mess["approach"]
			if not _grid.is_walkable(approach):
				approach = approach_for(_grid, mess["cell"])
		if approach == NO_CELL:
			_messes.erase(id)
			if int(mess["claimed_by"]) != 0:
				claim_dropped.emit(id, int(mess["claimed_by"]))
		else:
			mess["approach"] = approach
	for bin: int in _bins.keys():
		if _grid.get_object(bin).get("def", &"") != BIN_ID:
			_bins.erase(bin)
	for source: String in _counters.keys():
		if not source_exists(_grid, source):
			_counters.erase(source)


## Once a simulated second per passenger: the messes it can see cost mood.
func beat(p: Passenger) -> void:
	if DecorEffect.AWAY_STAGES.has(p.stage):
		return
	var dirt := mini(dirt_at(BoredomSim.watch_cell(p)), MAX_DIRT)
	if dirt <= 0:
		return
	@warning_ignore("integer_division")
	var beat_number := _sim.tick / PassengerSim.BEAT_TICKS
	p.mood = maxi(p.mood - DecorEffect.due(dirt, beat_number), 0)


## JSON-safe state for a save. Reads only.
func to_snapshot() -> Dictionary:
	var list: Array = []
	for id in mess_ids():
		var mess: Dictionary = _messes[id]
		var cell: Vector2i = mess["cell"]
		var approach: Vector2i = mess["approach"]
		(
			list
			. append(
				{
					"id": id,
					"cell": [cell.x, cell.y],
					"approach": [approach.x, approach.y],
					"kind": int(mess["kind"]),
					"born_tick": mess["born_tick"],
					"grown": mess["grown"],
					"claimed_by": mess["claimed_by"],
				}
			)
		)
	var bins := {}
	var bin_ids: Array = _bins.keys()
	bin_ids.sort()
	for bin: int in bin_ids:
		bins[str(bin)] = _bins[bin]
	return {
		"save_version": SAVE_VERSION,
		"tick": _sim.tick,
		"next_id": _next_id,
		"messes": list,
		"bins": bins,
		"counters": _counters.duplicate(),
		"overflow": overflow,
		"merged": merged,
		"caught": caught,
	}


## Restores a to_snapshot() dictionary, including one that went through JSON,
## checked against the bound grid. Pushes an error and returns false, leaving
## everything as it was, when it is refused (checked()).
func from_snapshot(data: Dictionary) -> bool:
	var loaded := checked(data, _grid)
	if loaded.has("error"):
		push_error("MessSim.from_snapshot: %s" % loaded["error"])
		return false
	_messes = loaded["messes"]
	_next_id = loaded["next_id"]
	_bins = loaded["bins"]
	_counters = loaded["counters"]
	overflow = loaded["overflow"]
	merged = loaded["merged"]
	caught = loaded["caught"]
	stale = false
	_seen_dirty = true
	return true


## Checks a saved dictionary against `grid` without touching any sim: returns
## {"error": reason}, or the loaded state {"tick", "messes", "next_id", "bins",
## "counters", "overflow", "merged", "caught"}.
static func checked(data: Dictionary, grid: BuildGrid) -> Dictionary:
	var keys := ["save_version", "tick", "next_id", "messes", "bins", "counters"]
	keys.append_array(["overflow", "merged", "caught"])
	for key in keys:
		if not data.has(key):
			return {"error": "missing key '%s'" % key}
	if not WholeNumber.is_whole(data["save_version"]) or int(data["save_version"]) != SAVE_VERSION:
		return {"error": "save_version must be %d" % SAVE_VERSION}
	for key in ["tick", "next_id", "overflow", "merged", "caught"]:
		if not WholeNumber.is_whole(data[key]) or int(data[key]) < 0:
			return {"error": "'%s' must be a whole number of 0 or more" % key}
	if typeof(data["messes"]) != TYPE_ARRAY or (data["messes"] as Array).size() > MAX_MESSES:
		return {"error": "'messes' must be a list of at most %d" % MAX_MESSES}
	var tick := int(data["tick"])
	var next := int(data["next_id"])
	# Ids start at 1: add() returns 0 for a refused mess.
	if next < 1:
		return {"error": "'next_id' must be 1 or more"}
	var messes := {}
	for entry: Variant in data["messes"]:
		var mess := _checked_mess(entry, grid, tick, next)
		if mess.has("error"):
			return mess
		if messes.has(mess["id"]):
			return {"error": "mess %d is saved twice" % mess["id"]}
		messes[mess["id"]] = mess
	var bins := _checked_bins(data["bins"], grid)
	if bins.has("error"):
		return bins
	var counters := _checked_counters(data["counters"], grid)
	if counters.has("error"):
		return counters
	return {
		"tick": tick,
		"messes": messes,
		"next_id": next,
		"bins": bins["bins"],
		"counters": counters["counters"],
		"overflow": int(data["overflow"]),
		"merged": int(data["merged"]),
		"caught": int(data["caught"]),
	}


static func _checked_mess(entry: Variant, grid: BuildGrid, tick: int, next: int) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		return {"error": "a mess is not a dictionary"}
	var data: Dictionary = entry
	for key in ["id", "cell", "approach", "kind", "born_tick", "grown", "claimed_by"]:
		if not data.has(key):
			return {"error": "a mess is missing '%s'" % key}
	for key in ["id", "kind", "born_tick", "claimed_by"]:
		if not WholeNumber.is_whole(data[key]) or int(data[key]) < 0:
			return {"error": "a mess's '%s' must be a whole number of 0 or more" % key}
	var id := int(data["id"])
	var kind := int(data["kind"])
	if id < 1 or id >= next:
		return {"error": "mess id %d is outside 1 to %d" % [id, next - 1]}
	if kind >= Kind.size():
		return {"error": "mess %d has an unknown kind %d" % [id, kind]}
	if int(data["born_tick"]) > tick:
		return {"error": "mess %d was made after the save's tick" % id}
	# Growth runs at the start of each tick, so a save between ticks holds
	# exactly the litter old enough as grown.
	var grows := kind == Kind.LITTER and tick - int(data["born_tick"]) >= GROW_TICKS
	if typeof(data["grown"]) != TYPE_BOOL or data["grown"] != grows:
		return {"error": "mess %d: 'grown' must be %s at its age" % [id, grows]}
	# claimed_by is 0 or more (checked above); that it names a live cleaner
	# whose job is this mess is checked with the staff (StaffSnapshot).
	var cell := _cell_of(data["cell"])
	var approach := _cell_of(data["approach"])
	if cell == NO_CELL or grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
		return {"error": "mess %d is not on a floor cell" % id}
	if approach == NO_CELL or not grid.is_walkable(approach):
		return {"error": "mess %d has no walkable approach cell" % id}
	return {
		"id": id,
		"cell": cell,
		"approach": approach,
		"kind": kind,
		"born_tick": int(data["born_tick"]),
		"grown": data["grown"],
		"claimed_by": int(data["claimed_by"]),
	}


static func _checked_bins(value: Variant, grid: BuildGrid) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"error": "'bins' must be a dictionary"}
	var bins := {}
	for key: Variant in value:
		var text := str(key)
		var fill: Variant = value[key]
		if not text.is_valid_int() or grid.get_object(text.to_int()).get("def", &"") != BIN_ID:
			return {"error": "bin '%s' is not a bin on the grid" % text}
		if not WholeNumber.is_whole(fill) or int(fill) < 0 or int(fill) > BIN_CAPACITY:
			return {"error": "bin %s's fill must be 0 to %d" % [text, BIN_CAPACITY]}
		bins[text.to_int()] = int(fill)
	return {"bins": bins}


static func _checked_counters(value: Variant, grid: BuildGrid) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"error": "'counters' must be a dictionary"}
	var counters := {}
	for key: Variant in value:
		var source := str(key)
		var count: Variant = value[key]
		if not source_exists(grid, source):
			return {"error": "use counter '%s' names nothing on the grid" % source}
		if not WholeNumber.is_whole(count) or int(count) < 0:
			return {"error": "use counter '%s' must be a whole number of 0 or more" % source}
		counters[source] = int(count)
	return {"counters": counters}


static func _cell_of(value: Variant) -> Vector2i:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		return NO_CELL
	if not WholeNumber.is_whole(value[0]) or not WholeNumber.is_whole(value[1]):
		return NO_CELL
	return Vector2i(int(value[0]), int(value[1]))


## One real use of `source`: every `every`th leaves a mess of `kind` at `cell`,
## litter caught by a bin in range when there is one.
func _use(source: String, every: int, kind: Kind, cell: Vector2i) -> void:
	var count := uses_of(source) + 1
	_counters[source] = count
	if count % every != 0:
		return
	if kind == Kind.LITTER:
		var bin := bin_for(cell)
		if bin != 0:
			_bins[bin] = fill_of(bin) + 1
			caught += 1
			return
	add(kind, cell)


## The mess of `kind` nearest `cell` within `reach` cells, ties to the lower
## id; 0 for none.
func _same_kind_near(kind: Kind, cell: Vector2i, reach: int) -> int:
	var best := 0
	var best_distance := reach + 1
	for id in mess_ids():
		var mess: Dictionary = _messes[id]
		if mess["kind"] != kind:
			continue
		var at: Vector2i = mess["cell"]
		var distance := maxi(absi(at.x - cell.x), absi(at.y - cell.y))
		if distance < best_distance:
			best = id
			best_distance = distance
	return best


func _sorted_objects() -> Array[int]:
	var ids := _grid.object_ids()
	ids.sort()
	return ids


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	stale = true
	_seen_dirty = true


func _on_edit_applied(_edit: BuildEdit, _result: BuildResult) -> void:
	stale = true
