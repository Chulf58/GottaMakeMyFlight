class_name GateDesks
extends Node
## The gates of the player-built terminal (decision gates-technical-design-
## gate-desks-link-to-north-exits-one-st, points 1 and 6, building user ruling
## gates-are-placed-gate-desks-each-desk-links-automatically-to). A gate is a
## gate desk (DESK) linked to an exit door whose outside faces north; the
## gate's plane stand is straight out from that exit (StandPlacement.for_exit).
##
## Each desk links to the nearest exit within LINK_CELLS cells of its footprint
## that no other desk holds, ties to the lower exit id, older desks (lower ids)
## first. A link is sticky: it is saved and kept for as long as its desk and
## its exit both stand, even when another exit comes nearer. A gate gets the
## first letter from A that no other gate, running contract or live flight
## names, and keeps it.
##
## Refused before commit (edit_problem(), asked by ApronStand's site guard): a
## desk that would link to no exit, or whose stand's private ground (the
## stand's sweep south of the shared lane, StandPlacement.swept_rects()) would
## overlap another gate's; and a removal that would end a gate while a live
## flight is at it, or while one of its running contracts fits no other gate.
## A removal that ends a gate moves its contracts to the other gates first
## (FlightSim.move_plan()), when the removal is applied. A desk only ever links
## to an exit whose stand overlaps no linked gate's (links_on()), so no later
## edit (an exit placed by a desk with no gate, an exit or desk removed) can
## make overlapping gates once it is committed.
##
## FlightSim.gate_source is gate_ids(), so a gate has a stand exactly while it
## has a desk and an exit. `changed` fires after every refresh(), which runs on
## each graph change, so ApronStand works the stands out after the links.
##
## Not guaranteed: when a gate ends because its exit went, its desk links again
## as a new gate (perhaps with the same letter) only after the moves; and the
## moves are greedy, oldest contract first, so a set of contracts that would fit
## the other gates only in another order is refused.

signal changed

## Why a gate desk has no gate (unlinked_on()). NO_EXIT: no north exit within
## LINK_CELLS. EXIT_TAKEN: every exit in reach is another gate's. STAND_OVERLAP:
## a free exit is in reach, but its stand would overlap a gate's. NO_LETTER: it
## could link, but every gate letter is in use.
enum Unlinked { NO_EXIT, EXIT_TAKEN, STAND_OVERLAP, NO_LETTER }

const DESK := &"gate_desk"
## How far (in cells, either way, diagonals counting one) a desk's footprint may
## be from the exit it links to.
const LINK_CELLS := 4
const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const SAVE_VERSION := 1
const SAVE_KEYS := ["save_version", "gates"]
const GATE_KEYS := ["gate", "desk", "exit"]

@export var build_mode: BuildMode
@export var flights: FlightSim

var grid: BuildGrid
## {"gate": letter, "desk": desk object id, "exit": exit door id}, in desk id
## order.
var bindings: Array[Dictionary] = []


func _ready() -> void:
	if build_mode == null or flights == null or build_mode.grid == null:
		push_error("GateDesks: build_mode and flights must be set, so there are no gates")
		return
	bind(build_mode.grid, flights)


## Follows `on_grid` and supplies `on_flights`' gates.
func bind(on_grid: BuildGrid, on_flights: FlightSim) -> void:
	grid = on_grid
	flights = on_flights
	flights.gate_source = gate_ids
	grid.graph_changed.connect(_on_graph_changed)
	grid.edit_applied.connect(_on_edit_applied)
	refresh()


## The gate letters, in desk order.
func gate_ids() -> Array[String]:
	var out: Array[String] = []
	for binding in bindings:
		out.append(binding["gate"])
	return out


## The binding of gate `gate`, or {}.
func binding_of(gate: String) -> Dictionary:
	for binding in bindings:
		if binding["gate"] == gate:
			return binding
	return {}


## Keeps the links whose desk and exit stand, links the desks that have none,
## then says so (changed).
func refresh() -> void:
	var links := links_on(grid, bindings)
	for link in links:
		if link["gate"] == "":
			link["gate"] = _free_letter(links)
			if link["gate"] == "":
				push_error(
					"GateDesks: every gate letter is in use; desk %d is no gate" % link["desk"]
				)
	bindings.assign(links.filter(func(link: Dictionary) -> bool: return link["gate"] != ""))
	changed.emit()


## The links `on_grid` would have, given `kept`: each of `kept` whose desk and
## exit still stand, then a link for every other desk that has an exit to link
## to, with gate "" (no letter yet). In desk id order. A desk never links to an
## exit whose stand would overlap a stand already linked, so no edit (an exit
## placed by an unlinked desk, an exit or desk removed) can make overlapping
## gates after it is committed.
static func links_on(on_grid: BuildGrid, kept: Array[Dictionary]) -> Array[Dictionary]:
	var links: Array[Dictionary] = []
	var taken := {}
	var linked := {}
	var stands: Array[Dictionary] = []
	for binding in kept:
		if is_desk(on_grid, binding["desk"]) and _is_gate_exit(on_grid, binding["exit"]):
			links.append(binding.duplicate())
			taken[binding["exit"]] = true
			linked[binding["desk"]] = true
			stands.append(StandPlacement.for_exit(on_grid, binding["exit"]))
	for desk in desk_ids(on_grid):
		if linked.has(desk):
			continue
		var exit := nearest_exit(on_grid, desk_footprint(on_grid, desk), taken, stands)
		if exit != 0:
			links.append({"gate": "", "desk": desk, "exit": exit})
			taken[exit] = true
			stands.append(StandPlacement.for_exit(on_grid, exit))
	links.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["desk"] < b["desk"])
	return links


## The gate desks the bindings give no gate, and why (decision gates-1b-as-
## built-gatedesks-link-desks-to-north-exits-as-sti: a desk that cannot link
## stays unlinked, and the Gates 2/4 view shows it). {} before bind().
func unlinked() -> Dictionary:
	if grid == null:
		return {}
	return unlinked_on(grid, bindings)


## Desk id -> {"why": Unlinked, "gate": the gate letter the reason names, or
## ""}, for every gate desk on `on_grid` that `links` gives no gate. EXIT_TAKEN
## names the gate holding the nearest exit in reach. STAND_OVERLAP only when
## every free exit in reach overlaps a gate's stand, naming the first gate the
## nearest free one overlaps; with any free exit that overlaps none, NO_LETTER.
## Exits are taken nearest first, ties to the lower id, as nearest_exit() takes
## them.
static func unlinked_on(on_grid: BuildGrid, links: Array[Dictionary]) -> Dictionary:
	var linked := {}
	var gate_of_exit := {}
	for link in links:
		linked[link["desk"]] = true
		gate_of_exit[link["exit"]] = link["gate"]
	var out := {}
	for desk in desk_ids(on_grid):
		if not linked.has(desk):
			out[desk] = _unlinked_reason(on_grid, desk, links, gate_of_exit)
	return out


static func _unlinked_reason(
	on_grid: BuildGrid, desk: int, links: Array[Dictionary], gate_of_exit: Dictionary
) -> Dictionary:
	var reach := exits_in_reach(on_grid, desk_footprint(on_grid, desk))
	if reach.is_empty():
		return {"why": Unlinked.NO_EXIT, "gate": ""}
	# Every free exit in nearest_exit()'s order: one whose stand overlaps no
	# gate's would link, so only a missing letter can stop it; the overlap is
	# the reason only when every free exit overlaps (named for the nearest).
	var overlap := {}
	for exit in reach:
		if gate_of_exit.has(exit):
			continue
		var gate := _overlapping_gate(on_grid, StandPlacement.for_exit(on_grid, exit), links)
		if gate == "":
			return {"why": Unlinked.NO_LETTER, "gate": ""}
		if overlap.is_empty():
			overlap = {"why": Unlinked.STAND_OVERLAP, "gate": gate}
	if not overlap.is_empty():
		return overlap
	return {"why": Unlinked.EXIT_TAKEN, "gate": gate_of_exit[reach[0]]}


## The first of `links`' gates whose stand overlaps `stand`, or "".
static func _overlapping_gate(
	on_grid: BuildGrid, stand: Dictionary, links: Array[Dictionary]
) -> String:
	for link in links:
		if stands_overlap(stand, StandPlacement.for_exit(on_grid, link["exit"])):
			return link["gate"]
	return ""


## The north exits at most LINK_CELLS from `footprint` (diagonals counting
## one), nearest first, ties to the lower id.
static func exits_in_reach(on_grid: BuildGrid, footprint: Array[Vector2i]) -> Array[int]:
	var found: Array[Vector2i] = []
	for id in on_grid.object_ids():
		if _is_gate_exit(on_grid, id):
			var cells := reach_cells(on_grid, footprint, id)
			if cells <= LINK_CELLS:
				found.append(Vector2i(cells, id))
	found.sort()
	var out: Array[int] = []
	for entry in found:
		out.append(entry.y)
	return out


## The cells gate desk `desk` stands on.
static func desk_footprint(on_grid: BuildGrid, desk: int) -> Array[Vector2i]:
	var record := on_grid.get_object(desk)
	return BuildCatalog.get_def(DESK).footprint(record["anchor"], record["facing"])


## How many cells (diagonals counting one) `footprint` is from exit `exit`'s
## cell.
static func reach_cells(on_grid: BuildGrid, footprint: Array[Vector2i], exit: int) -> int:
	var at: Vector2i = on_grid.get_object(exit)["anchor"]
	var cells := 1 << 30
	for cell in footprint:
		cells = mini(cells, maxi(absi(cell.x - at.x), absi(cell.y - at.y)))
	return cells


static func is_desk(on_grid: BuildGrid, id: int) -> bool:
	var record := on_grid.get_object(id)
	return not record.is_empty() and StringName(record["def"]) == DESK


## The gate desks on `on_grid`, in id order.
static func desk_ids(on_grid: BuildGrid) -> Array[int]:
	var out: Array[int] = []
	for id in on_grid.object_ids():
		if is_desk(on_grid, id):
			out.append(id)
	out.sort()
	return out


## The exit door nearest `footprint` (at most LINK_CELLS away, diagonals
## counting one) whose outside faces north, that is not in `taken` and whose
## stand overlaps none of `stands`; ties to the lower id. 0 for none.
static func nearest_exit(
	on_grid: BuildGrid,
	footprint: Array[Vector2i],
	taken: Dictionary,
	stands: Array[Dictionary] = []
) -> int:
	var best := 0
	var best_cells := LINK_CELLS + 1
	var ids := on_grid.object_ids()
	ids.sort()
	for id in ids:
		if taken.has(id) or not _is_gate_exit(on_grid, id):
			continue
		var cells := reach_cells(on_grid, footprint, id)
		if cells >= best_cells:
			continue
		var stand := StandPlacement.for_exit(on_grid, id)
		if stands.any(func(other: Dictionary) -> bool: return stands_overlap(stand, other)):
			continue
		if cells < best_cells:
			best = id
			best_cells = cells
	return best


## Whether stands `a` and `b` would sweep any of the same private ground: their
## StandPlacement.swept_rects() south of the shared lane zone.
static func stands_overlap(a: Dictionary, b: Dictionary) -> bool:
	for rect_a in private_rects(a):
		for rect_b in private_rects(b):
			if rect_a.intersects(rect_b):
				return true
	return false


## The stand's sweep south of the shared lane zone, which no other stand may
## share.
static func private_rects(stand: Dictionary) -> Array[Rect2]:
	var lane_south := StandPlacement.lane_zone().end.y
	var out: Array[Rect2] = []
	for rect in StandPlacement.swept_rects(stand):
		var north := maxf(rect.position.y, lane_south)
		if rect.end.y > north:
			out.append(Rect2(rect.position.x, north, rect.size.x, rect.end.y - north))
	return out


## The site guard's part for gates: a refusal for a gate desk that would link
## to no exit or whose stand would overlap another gate's, or for a removal
## that would end a gate whose flights cannot move; else null. `on_grid` is the
## grid the edit is checked on (the live grid or a trial copy of it).
func edit_problem(on_grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	if edit.kind == BuildEdit.Kind.PLACE_OBJECT and edit.def_id == DESK:
		return _placement_problem(on_grid, edit)
	if edit.kind == BuildEdit.Kind.REMOVE_OBJECT:
		return _removal_problem(on_grid, edit.object_id)
	return null


func _placement_problem(on_grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var footprint := BuildCatalog.get_def(DESK).footprint(edit.cell, edit.facing)
	var links := links_on(on_grid, bindings)
	var taken := {}
	var stands: Array[Dictionary] = []
	for link in links:
		taken[link["exit"]] = true
		stands.append(StandPlacement.for_exit(on_grid, link["exit"]))
	var reach := nearest_exit(on_grid, footprint, taken)
	if reach == 0:
		return BuildResult.refused(BuildResult.Reason.GATE_NO_EXIT)
	if nearest_exit(on_grid, footprint, taken, stands) != 0:
		return null
	# Every exit in reach would overlap a gate's stand: name the nearest's.
	var stand := StandPlacement.for_exit(on_grid, reach)
	for link in links:
		if stands_overlap(stand, StandPlacement.for_exit(on_grid, link["exit"])):
			var refusal := BuildResult.refused(BuildResult.Reason.GATE_STAND_OVERLAP, link["desk"])
			if link["gate"] != "":
				refusal.detail = "gate %s" % link["gate"]
			return refusal
	return BuildResult.refused(BuildResult.Reason.GATE_STAND_OVERLAP)


## A refusal for removing object `id` from `on_grid`, or null. Only a removal
## that ends a gate (its desk, or its exit) can be refused. Gates that already
## lost their desk or exit on `on_grid` (earlier edits of the same batch) are
## counted as ended too, since their contracts have not moved yet.
func _removal_problem(on_grid: BuildGrid, id: int) -> BuildResult:
	var ending: Array[String] = []
	var staying: Array[String] = []
	for binding in bindings:
		var stands: bool = is_desk(on_grid, binding["desk"])
		stands = stands and _is_gate_exit(on_grid, binding["exit"])
		if stands and binding["desk"] != id and binding["exit"] != id:
			staying.append(binding["gate"])
		else:
			ending.append(binding["gate"])
	if ending.is_empty() or flights == null:
		return null
	var busy := _live_flights_at(ending)
	if not busy.is_empty():
		var refusal := BuildResult.refused(BuildResult.Reason.GATE_IN_USE)
		refusal.detail = ", ".join(busy)
		return refusal
	var plan := flights.move_plan(ending, staying)
	if not (plan["stuck"] as Array).is_empty():
		var refusal := BuildResult.refused(BuildResult.Reason.GATE_FLIGHTS_STUCK)
		refusal.detail = ", ".join(plan["stuck"])
		return refusal
	return null


## The live flights at any of `gates` that have not departed.
func _live_flights_at(gates: Array[String]) -> PackedStringArray:
	var out: PackedStringArray = []
	for flight_id in flights.flight_ids():
		var at_gate := gates.has(flights.flight_gate(flight_id))
		if at_gate and flights.state_of(flight_id) < FlightSim.State.DEPARTED:
			out.append(flight_id)
	return out


## The first letter no link in `links`, running contract or live flight
## names; "" when all are named.
func _free_letter(links: Array[Dictionary]) -> String:
	var named := {}
	for link in links:
		named[link["gate"]] = true
	if flights != null:
		for contract_id in flights.active_contract_ids():
			named[flights.contract_of(contract_id)["gate"]] = true
		for flight_id in flights.flight_ids():
			named[flights.flight_gate(flight_id)] = true
	for letter in LETTERS:
		if not named.has(letter):
			return letter
	return ""


static func _is_gate_exit(on_grid: BuildGrid, id: int) -> bool:
	return not StandPlacement.for_exit(on_grid, id).is_empty()


func to_snapshot() -> Dictionary:
	var gates: Array = []
	for binding in bindings:
		gates.append(binding.duplicate())
	return {"save_version": SAVE_VERSION, "gates": gates}


## The bindings a to_snapshot() dictionary holds, checked against `on_grid`:
## {"gates": Array[Dictionary]} or {"error": why}. Each gate needs a letter
## from LETTERS, a gate desk and a north exit on the grid; letters, desks and
## exits are each used once; and the set must be one the links make on the grid
## (_set_problem()), so a load installs exactly the saved gates.
static func checked(data: Dictionary, on_grid: BuildGrid) -> Dictionary:
	if data.size() != SAVE_KEYS.size() or not data.has_all(SAVE_KEYS):
		return {"error": "a gates part holds save_version and gates"}
	var version: Variant = data["save_version"]
	if not WholeNumber.is_whole(version) or int(version) != SAVE_VERSION:
		return {"error": "save_version must be %d" % SAVE_VERSION}
	if typeof(data["gates"]) != TYPE_ARRAY:
		return {"error": "'gates' is not a list"}
	var out: Array[Dictionary] = []
	var used := {}
	for entry: Variant in data["gates"]:
		var problem := _entry_problem(entry, on_grid, used)
		if problem != "":
			return {"error": problem}
		var binding := {
			"gate": str(entry["gate"]), "desk": int(entry["desk"]), "exit": int(entry["exit"])
		}
		for key in GATE_KEYS:
			used["%s:%s" % [key, binding[key]]] = true
		out.append(binding)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["desk"] < b["desk"])
	var problem := _set_problem(out, on_grid)
	if problem != "":
		return {"error": problem}
	return {"gates": out}


## Why `bindings` (each checked alone) are not a set the game could have made on
## `on_grid`, or "": a desk out of its exit's reach, two gates whose stands
## overlap, or a desk with no saved gate that refresh() would link (the load
## would then not be the saved world).
static func _set_problem(bindings: Array[Dictionary], on_grid: BuildGrid) -> String:
	for i in bindings.size():
		var binding := bindings[i]
		var footprint := desk_footprint(on_grid, binding["desk"])
		if reach_cells(on_grid, footprint, binding["exit"]) > LINK_CELLS:
			return "gate %s: its desk is out of its exit's reach" % binding["gate"]
		var stand := StandPlacement.for_exit(on_grid, binding["exit"])
		for other in bindings.slice(i + 1):
			if stands_overlap(stand, StandPlacement.for_exit(on_grid, other["exit"])):
				return "gates %s and %s have overlapping stands" % [binding["gate"], other["gate"]]
	for link in links_on(on_grid, bindings):
		if link["gate"] == "":
			return (
				"desk %d has no saved gate but would link to exit %d" % [link["desk"], link["exit"]]
			)
	return ""


static func _entry_problem(entry: Variant, on_grid: BuildGrid, used: Dictionary) -> String:
	if typeof(entry) != TYPE_DICTIONARY or entry.size() != GATE_KEYS.size():
		return "a gate holds gate, desk and exit"
	if not (entry as Dictionary).has_all(GATE_KEYS):
		return "a gate holds gate, desk and exit"
	var letter: Variant = entry["gate"]
	if typeof(letter) != TYPE_STRING or letter.length() != 1 or not LETTERS.contains(letter):
		return "gate '%s' is not a letter A to Z" % [letter]
	if not WholeNumber.is_whole(entry["desk"]) or not is_desk(on_grid, int(entry["desk"])):
		return "gate %s: %s is not a gate desk" % [letter, entry["desk"]]
	if not WholeNumber.is_whole(entry["exit"]) or not _is_gate_exit(on_grid, int(entry["exit"])):
		return "gate %s: %s is not an exit facing north" % [letter, entry["exit"]]
	for key in GATE_KEYS:
		var value: Variant = letter if key == "gate" else int(entry[key])
		if used.has("%s:%s" % [key, value]):
			return "gate %s: its %s is used twice" % [letter, key]
	return ""


## Installs a checked() save. False (with an error) for a refused one; the
## links then stay as they were.
func from_snapshot(data: Dictionary) -> bool:
	var loaded := checked(data, grid)
	if loaded.has("error"):
		push_error("GateDesks.from_snapshot: %s" % loaded["error"])
		return false
	bindings.assign(loaded["gates"])
	refresh()
	return true


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	refresh()


## A removal that ended gates moves their contracts first (_removal_problem()
## checked that they fit), before the graph change drops the gates.
func _on_edit_applied(edit: BuildEdit, _result: BuildResult) -> void:
	if edit.kind != BuildEdit.Kind.REMOVE_OBJECT or flights == null:
		return
	var ending: Array[String] = []
	var staying: Array[String] = []
	for binding in bindings:
		var stands := is_desk(grid, binding["desk"]) and _is_gate_exit(grid, binding["exit"])
		(staying if stands else ending).append(binding["gate"])
	if ending.is_empty():
		return
	# _removal_problem() refused any removal whose plan has stuck contracts, so a
	# failure here is a defect: said loudly, never passed over.
	var plan := flights.move_plan(ending, staying)
	if not flights.move_contracts(plan):
		push_error("GateDesks: the contracts of gates %s could not move: %s" % [ending, plan])
		assert(false, "GateDesks: a removal that was checked left contracts unmoved")
