class_name GateDesks
extends Node
## The gates of the player-built terminal (decision gates-technical-design-
## gate-desks-link-to-north-exits-one-st, points 1 and 6, building user ruling
## gates-are-placed-gate-desks-each-desk-links-automatically-to). A gate is a
## gate desk (DESK) linked to an exit door whose outside faces west, north or
## east, never the road (slice S5 of design airside-all-around-technical-
## design-one-route-source-per-con); the gate's plane stand is straight out
## from that exit on its side (StandPlacement.for_exit).
##
## Each desk links to the nearest exit within LINK_CELLS cells of its footprint
## that no other desk holds, ties to the lower exit id, older desks (lower ids)
## first. A link is sticky: it is saved and kept for as long as its desk and
## its exit both stand, even when another exit comes nearer. A gate gets the
## first letter from A that no other gate, running contract or live flight
## names, and keeps it.
##
## A gate has no size (decision runway-and-taxi-technical-design-movement-plan-
## analytic-bookings-planned-pauses, section 3): a desk links only to an exit
## whose small-plane envelope (StandEnvelope) is clear and whose small swing
## square, south of the shared lane, meets no other gate's, so exits can stand
## StandPlacement.EXIT_SPACING_CELLS (19) apart. Each gate's max_class
## (classes) is the largest class whose envelope is clear, worked out on every
## refresh(); building into a gate's unused larger space is allowed and lowers
## it (edit_warning() says so first).
##
## Refused before commit (edit_problem(), asked by ApronStand's site guard): a
## desk that would link to no exit, whose small swing square would overlap
## another gate's (GATE_STAND_OVERLAP), whose exit has no room for a small swing
## (GATE_NO_ROOM) or whose small way out to its lane is built over
## (GATE_ROUTE_BLOCKED); an edit that builds under the envelope of the largest
## class booked at a gate (GATE_ROUTE: its running contracts and the live
## flights at it); and a removal that would end a gate while a live
## flight is at it, or while one of its running contracts fits no other gate.
## A removal that ends a gate moves its contracts to the other gates first
## (FlightSim.move_plan()), when the removal is applied. A desk only ever links
## to an exit whose stand overlaps no linked gate's (links_on()), so no later
## edit (an exit placed by a desk with no gate, an exit or desk removed) can
## make overlapping gates once it is committed.
##
## FlightSim.gate_source is gate_ids(), so a gate has a stand exactly while it
## has a desk and an exit, and FlightSim.stand_source is gate_grounds(), each
## gate's stand and max_class as the last refresh() found them, so the taxi
## planner books the stands the planes use. The moves on a removal go through
## FlightSim's planner (move_plan()), so they never change an issued flight.
## `changed` fires after every refresh(), which runs on
## each graph change, so ApronStand works the stands out after the links.
##
## Side spurs (decision side-spur-move-design-s7-stands-carry-lane-x-the-wanted-
## spur, slice S7b): spur_x holds each side's spur x now, which every gate stand
## there is on, and refresh() works out spur_wanted from the build and the gate
## stands (SideSpurs.wanted()). A side whose two differ is pending: its gates'
## grounds carry "next", the stand and max_class on the wanted spur, and
## FlightSim calls release_spur() once the side is quiet (SpurMoves). A desk
## links at its exit's SideSpurs.link_stand(), so a gate past the spur can
## link and push it out; until the spur moves such a gate says WAITING_TEXT.
## The spurs are saved with the gates.
##
## Not guaranteed: when a gate ends because its exit went, its desk links again
## as a new gate (perhaps with the same letter) only after the moves; and the
## moves are greedy, oldest contract first, so a set of contracts that would fit
## the other gates only in another order is refused.

signal changed

## Why a gate desk has no gate (unlinked_on()). NO_EXIT: no exit facing west,
## north or east within LINK_CELLS. EXIT_TAKEN: every exit in reach is another
## gate's. STAND_OVERLAP: a free exit is in reach, but its stand would overlap a
## gate's. NO_LETTER: it could link, but every gate letter is in use. NO_ROOM:
## the free exit has no room for a small swing. ROUTE_BLOCKED: its small way
## out is built over.
enum Unlinked { NO_EXIT, EXIT_TAKEN, STAND_OVERLAP, NO_LETTER, NO_ROOM, ROUTE_BLOCKED }

## The refusal for a desk whose nearest free exit is unfit for that reason.
const REFUSAL_OF := {
	Unlinked.STAND_OVERLAP: BuildResult.Reason.GATE_STAND_OVERLAP,
	Unlinked.NO_ROOM: BuildResult.Reason.GATE_NO_ROOM,
	Unlinked.ROUTE_BLOCKED: BuildResult.Reason.GATE_ROUTE_BLOCKED,
}

const DESK := &"gate_desk"
const BUS_DESK := &"bus_gate_desk"
## How far (in cells, either way, diagonals counting one) a desk's footprint may
## be from the exit it links to.
const LINK_CELLS := 4
const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
## 3: "remote_stands" alongside "gates" and "spurs".
const SAVE_VERSION := 3
const SAVE_KEYS := ["save_version", "gates", "spurs", "remote_stands"]
## A gate whose stand can take no plane until its side's pending spur moves
## (waits_on_spur()) says so on its card and sign (user ruling airside-
## construction-works-are-a-visible-stage-props-mark-th, point 4).
## The English msgid of that line. Tests compare with it; waiting_text() is the
## player's text, tr() of the same literal because the POT extractor reads only
## literals.
const WAITING_TEXT := "Waiting for taxiway works"
## The rail notice when a side spur has moved.
const SPUR_KEY := &"spur_moved"
const SPUR_TITLE := "Taxiway moved"
const GATE_KEYS := ["gate", "desk", "exit"]
## Edits that never build: only a removal that ends a gate is ever refused.
const REMOVALS: Array[BuildEdit.Kind] = [
	BuildEdit.Kind.REMOVE_FLOOR,
	BuildEdit.Kind.REMOVE_WALL,
	BuildEdit.Kind.REMOVE_OBJECT,
	BuildEdit.Kind.REMOVE_ROOM,
]

## The key and title of the rail notice that says which flights a removal moved.
const MOVED_KEY := &"gate_moves"
const MOVED_TITLE := "Flights moved"

@export var build_mode: BuildMode
@export var flights: FlightSim

## The right rail the moved-flights notice goes to; found through its group the
## first time it is needed when not set.
var alerts: AlertStack

var grid: BuildGrid
## {"gate": letter, "desk": desk object id, "exit": exit door id}, in desk id
## order.
var bindings: Array[Dictionary] = []
## Gate letter -> its max_class (StandEnvelope.max_class), "" when not even a
## small plane fits; worked out on every refresh().
var classes: Dictionary = {}
## Gate letter -> its stand (SideSpurs.stand_for_exit) on its side's spur now,
## worked out on every refresh() with classes.
var stands: Dictionary = {}
## Remote stand ID ("R1", ...) -> {"id", "object_id", "stand", "max_class"}.
var remote_stands: Dictionary = {}
## Side -> the x its spur runs at now, saved; it takes spur_wanted's only when
## FlightSim releases the side (release_spur()).
var spur_x: Dictionary = SideSpurs.floor_lanes()
## Side -> the x the build wants its spur at (SideSpurs.wanted()), worked out
## on every refresh().
var spur_wanted: Dictionary = SideSpurs.floor_lanes()
## gate_grounds() as the last refresh() found them, with "next" on a pending side.
var _grounds: Dictionary = {}
var _remote_by_obj: Dictionary = {}
## "x|wall_z|side|lane_x|class|grid size" -> the envelope's cells, which only
## the stand decides.
var _envelope_cells: Dictionary = {}
## Plane class -> spare_stand()'s answer, kept until the next refresh() or a
## change of owned land: the offer fit asks for it dozens of times a night.
var _spare_stands: Dictionary = {}
var _spare_prefix: Dictionary = {}
var _spare_land := ""
var _last_route_ver := -1
var _last_enclosure_ver := -1
var _last_desk_ids: Array[int] = []
var _last_remote_ids: Array[int] = []


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
	flights.stand_source = gate_grounds
	flights.bus_gate_source = bus_gate_ids
	flights.remote_stand_source = remote_stand_ids
	flights.remote_ground_source = remote_stand_grounds
	flights.spare_stand_source = spare_stand
	flights.spur_source = spurs
	flights.spur_release = release_spur
	grid.graph_changed.connect(_on_graph_changed)
	grid.edit_applied.connect(_on_edit_applied)
	refresh()


## The gate letters, in desk order.
## The second line of a gate waiting on the spur, as the player reads it.
static func waiting_text() -> String:
	return TranslationServer.translate("Waiting for taxiway works")


static func is_bus_binding(binding: Dictionary) -> bool:
	return bool(binding.get("is_bus_gate", false))


func gate_ids() -> Array[String]:
	var out: Array[String] = []
	for binding in bindings:
		if not is_bus_binding(binding):
			out.append(binding["gate"])
	return out


func bus_gate_ids() -> Array[String]:
	var out: Array[String] = []
	for binding in bindings:
		if is_bus_binding(binding):
			out.append(binding["gate"])
	return out


func remote_stand_ids() -> Array[String]:
	var out: Array[String] = []
	for sid: String in remote_stands:
		out.append(sid)
	out.sort()
	return out


func remote_stand_grounds() -> Dictionary:
	return remote_stands.duplicate(true)


## The binding of gate `gate`, or {}.
func binding_of(gate: String) -> Dictionary:
	for binding in bindings:
		if binding["gate"] == gate:
			return binding
	return {}


## Keeps the links whose desk and exit stand, links the desks that have none,
## then says so (changed).
func refresh() -> void:
	if grid != null:
		_last_route_ver = grid.route_version()
		_last_enclosure_ver = grid.enclosure_version()
		_last_desk_ids = desk_ids(grid)
		_last_remote_ids = RemoteStands.object_ids(grid)
	var links := links_on(grid, bindings)
	for link in links:
		if link["gate"] == "":
			link["gate"] = _free_letter(links)
			if link["gate"] == "":
				push_error(
					"GateDesks: every gate letter is in use; desk %d is no gate" % link["desk"]
				)
	bindings.assign(links.filter(func(link: Dictionary) -> bool: return link["gate"] != ""))
	spur_wanted = SideSpurs.wanted(grid, _regular_exits(bindings))
	_grounds = grounds_on(grid, bindings, spur_x, spur_wanted)
	classes = {}
	stands = {}
	_spare_stands.clear()
	_spare_prefix.clear()
	for gate: String in _grounds:
		stands[gate] = _grounds[gate]["stand"]
		classes[gate] = _grounds[gate]["max_class"]
	_refresh_remote_stands()
	changed.emit()


func _refresh_remote_stands() -> void:
	remote_stands = {}
	if grid == null:
		_remote_by_obj = {}
		return
	var site := site_of(grid)
	var land: LandPlots = (grid as SiteGrid).land if grid is SiteGrid else null
	var assigned := RemoteStands.assign_ids(grid, _remote_by_obj, _used_remote_flight_ids())
	var next_by_obj := {}
	for obj_id: int in assigned:
		var sid: String = assigned[obj_id]
		var anchor: Vector2i = grid.get_object(obj_id)["anchor"]
		var stand := RemoteStands.stand_for_cell(grid, anchor)
		var cls := RemoteStands.max_class(grid, site, stand, obj_id)
		next_by_obj[obj_id] = {"id": sid, "object_id": obj_id}
		remote_stands[sid] = {"id": sid, "object_id": obj_id, "stand": stand, "max_class": cls}
	_remote_by_obj = next_by_obj


func _used_remote_flight_ids() -> Array[String]:
	var out: Array[String] = []
	if flights == null:
		return out
	for cid in flights.active_contract_ids():
		var sid := String(flights.contract_of(cid).get("stand", ""))
		if sid.begins_with(RemoteStands.ID_PREFIX) and not out.has(sid):
			out.append(sid)
	for fid in flights.flight_ids():
		var sid := flights.flight_stand_id(fid)
		if sid.begins_with(RemoteStands.ID_PREFIX) and not out.has(sid):
			out.append(sid)
	return out


## Gate letter -> {"stand", "max_class"} for every gate (FlightSim.stand_source),
## and on a side whose spur waits to move, "next": the same on the wanted spur.
func gate_grounds() -> Dictionary:
	return _grounds.duplicate()


## The side spurs FlightSim plans with (FlightSim.spur_source): side -> {"x",
## "wanted"}.
func spurs() -> Dictionary:
	return SideSpurs.spurs_at(spur_x, spur_wanted)


## Moves `side`'s spur to its wanted x and works the stands out again; FlightSim
## calls it at the side's release tick (FlightSim.spur_release). Then one notice
## on the right rail says the taxiway has moved.
func release_spur(side: String) -> void:
	spur_x[side] = spur_wanted[side]
	refresh()
	var words := tr("The west taxiway has moved")
	if side != StandPlacement.WEST:
		words = tr("The east taxiway has moved")
	_post_notice(SPUR_KEY, tr("Taxiway moved"), words)


## Whether gate `gate` waits on its side's pending spur: its stand takes no plane
## now but takes one on the wanted spur.
func waits_on_spur(gate: String) -> bool:
	var ground: Dictionary = _grounds.get(gate, {})
	return (
		ground.get("max_class", "") == ""
		and ground.has("next")
		and ground["next"]["max_class"] != ""
	)


## Gate letter -> its ground on `on_grid` for gate `on_bindings`, its stand on the
## spurs `lanes` (side -> x) with its max_class, and on a side whose `wanted` x
## differs, "next": its stand and max_class there. SaveGame stages a load with it.
static func grounds_on(
	on_grid: BuildGrid, on_bindings: Array[Dictionary], lanes: Dictionary, wanted: Dictionary
) -> Dictionary:
	var site := site_of(on_grid)
	var out := {}
	for binding in on_bindings:
		if is_bus_binding(binding):
			continue
		var stand := SideSpurs.stand_for_exit(on_grid, binding["exit"], lanes)
		var ground := {"stand": stand, "max_class": StandEnvelope.max_class(on_grid, site, stand)}
		var side := StandPlacement.side_of(stand)
		if side != StandPlacement.NORTH:
			var to := SideSpurs.lane_x(side, wanted)
			if not is_equal_approx(to, SideSpurs.lane_x(side, lanes)):
				var next := StandPlacement.with_lane_x(stand, to)
				ground["next"] = {
					"stand": next, "max_class": StandEnvelope.max_class(on_grid, site, next)
				}
		out[binding["gate"]] = ground
	return out


## The exit doors of `on_bindings`.
static func _exits_of(on_bindings: Array[Dictionary]) -> Array:
	return on_bindings.map(func(binding: Dictionary) -> int: return binding["exit"])


static func _regular_exits(on_bindings: Array[Dictionary]) -> Array:
	var out: Array = []
	for binding in on_bindings:
		if not is_bus_binding(binding):
			out.append(binding["exit"])
	return out


## The stand of `plane_class` one more gate could have on the grid as it is, or
## {} (FlightSim.spare_stand_source; SpareStand has the rules).
func spare_stand(plane_class: String) -> Dictionary:
	if bindings.size() >= LETTERS.length():
		return {}
	var land: LandPlots = (grid as SiteGrid).land if grid is SiteGrid else null
	var owned := str(land.owned_plots()) if land != null else ""
	if owned != _spare_land:
		_spare_stands.clear()
		_spare_prefix.clear()
		_spare_land = owned
	if not _spare_stands.has(plane_class):
		if _spare_prefix.is_empty():
			_spare_prefix = SpareStand.build_prefix(grid, site_of(grid))
		var taken: Array[Dictionary] = []
		taken.assign(stands.values())
		_spare_stands[plane_class] = SpareStand.find(
			grid,
			taken,
			plane_class,
			_spare_prefix,
			RemoteStands.all_small_swings(grid),
			BusBays.bay_rects_for(grid, bindings),
			bindings.size()
		)
	return _spare_stands[plane_class]


## The largest plane class gate `gate`'s stand holds now, or "" (also for no
## such gate).
func max_class(gate: String) -> String:
	return classes.get(gate, "")


## The largest plane class booked at gate `gate`: its running contracts' and the
## live flights' at it that have not yet taken off (a one-off flight is the
## starter's class). "" with none.
func booked_class(gate: String) -> String:
	var out := ""
	if flights == null:
		return out
	for contract_id in flights.active_contract_ids():
		var contract := flights.contract_of(contract_id)
		if contract["gate"] == gate or String(contract.get("stand", "")) == gate:
			out = StandEnvelope.larger(out, contract["plane_size"])
	for flight_id in flights.flight_ids():
		if flights.flight_gate(flight_id) != gate and flights.flight_stand_id(flight_id) != gate:
			continue
		if flights.state_of(flight_id) >= FlightSim.State.TAKEOFF:
			continue
		var contract := flights.contract_of(flights.flight_contract_id(flight_id))
		var plane_class: String = contract.get("plane_size", FlightSim.STARTER_TERMS["plane_size"])
		out = StandEnvelope.larger(out, plane_class)
	return out


## The site of `on_grid` (a SiteGrid's), or null.
static func site_of(on_grid: BuildGrid) -> SiteDefinition:
	return (on_grid as SiteGrid).site if on_grid is SiteGrid else null


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
	var bays: Array[Rect2] = []
	for binding in kept:
		if is_desk(on_grid, binding["desk"]) and _is_gate_exit(on_grid, binding["exit"]):
			var copy := binding.duplicate()
			if is_bus_desk(on_grid, binding["desk"]):
				copy["is_bus_gate"] = true
			links.append(copy)
			taken[binding["exit"]] = true
			linked[binding["desk"]] = true
			if is_bus_binding(copy):
				var bay := BusBays.bay_rect(StandPlacement.for_exit(on_grid, binding["exit"]))
				if bay.has_area():
					bays.append(bay)
			else:
				stands.append(SideSpurs.link_stand(on_grid, binding["exit"]))
	for desk in desk_ids(on_grid):
		if linked.has(desk):
			continue
		if is_bus_desk(on_grid, desk):
			var blocked := _blocked_envelopes(on_grid, stands)
			var bexit := BusBays.nearest_bus_exit(
				on_grid, desk_footprint(on_grid, desk), taken, bays, blocked
			)
			if bexit != 0:
				links.append({"gate": "", "desk": desk, "exit": bexit, "is_bus_gate": true})
				taken[bexit] = true
				var bay := BusBays.bay_rect(StandPlacement.for_exit(on_grid, bexit))
				if bay.has_area():
					bays.append(bay)
			continue
		var exit := nearest_exit(on_grid, desk_footprint(on_grid, desk), taken, stands, true, bays)
		if exit != 0:
			links.append({"gate": "", "desk": desk, "exit": exit})
			taken[exit] = true
			stands.append(SideSpurs.link_stand(on_grid, exit))
	links.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["desk"] < b["desk"])
	return links


static func _blocked_envelopes(on_grid: BuildGrid, stands: Array[Dictionary]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for stand in at_common_lanes(on_grid, stands):
		out.append_array(StandEnvelope.rects(stand, PlaneClasses.SMALL))
	for swing in RemoteStands.all_small_swings(on_grid):
		out.append(swing)
	return out


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
	if is_bus_desk(on_grid, desk):
		return _unlinked_bus_reason(on_grid, reach, gate_of_exit, links)
	# Every free exit in nearest_exit()'s order: one fit for a gate would link,
	# so only a missing letter can stop it; otherwise the nearest free exit's
	# unfitness is the reason (an overlap named for the gate it meets).
	var stands: Array[Dictionary] = []
	for link in links:
		if not is_bus_binding(link):
			stands.append(SideSpurs.link_stand(on_grid, link["exit"]))
	var first := {}
	for exit in reach:
		if gate_of_exit.has(exit):
			continue
		var why := exit_unfit(on_grid, exit, stands)
		if why < 0:
			return {"why": Unlinked.NO_LETTER, "gate": ""}
		if first.is_empty():
			var gate := ""
			if why == Unlinked.STAND_OVERLAP:
				gate = _overlapping_gate(on_grid, SideSpurs.link_stand(on_grid, exit), links)
			first = {"why": why, "gate": gate}
	if not first.is_empty():
		return first
	return {"why": Unlinked.EXIT_TAKEN, "gate": gate_of_exit[reach[0]]}


static func _unlinked_bus_reason(
	on_grid: BuildGrid, reach: Array[int], gate_of_exit: Dictionary, links: Array[Dictionary]
) -> Dictionary:
	var site := site_of(on_grid)
	var bays := BusBays.bay_rects_for(on_grid, links)
	var stands: Array[Dictionary] = []
	for link in links:
		if not is_bus_binding(link):
			stands.append(SideSpurs.link_stand(on_grid, link["exit"]))
	var blocked := _blocked_envelopes(on_grid, stands)
	var saw_free := false
	for exit in reach:
		if gate_of_exit.has(exit):
			continue
		saw_free = true
		var stand := StandPlacement.for_exit(on_grid, exit)
		if BusBays.bay_clear(on_grid, site, stand, bays, blocked):
			return {"why": Unlinked.NO_LETTER, "gate": ""}
	if saw_free:
		return {"why": Unlinked.NO_ROOM, "gate": ""}
	return {"why": Unlinked.EXIT_TAKEN, "gate": gate_of_exit[reach[0]]}


## Why exit `exit` on `on_grid` cannot be a new gate's beside `stands`, as an
## Unlinked reason (STAND_OVERLAP before NO_ROOM before ROUTE_BLOCKED), or -1
## when it can (stand_unfit() of its SideSpurs.link_stand()).
static func exit_unfit(on_grid: BuildGrid, exit: int, stands: Array[Dictionary]) -> int:
	return stand_unfit(on_grid, SideSpurs.link_stand(on_grid, exit), stands)


## exit_unfit() for the stand `stand` of an exit (placed or about to be): its
## small swing square must meet none of `stands`' on the spurs they would all
## share (overlaps_common()), and its small envelope must be clear.
static func stand_unfit(on_grid: BuildGrid, stand: Dictionary, stands: Array[Dictionary]) -> int:
	if overlaps_common(on_grid, stand, stands):
		return Unlinked.STAND_OVERLAP
	match StandEnvelope.blocked_part(on_grid, site_of(on_grid), stand, PlaneClasses.SMALL):
		StandEnvelope.Part.CLEAR:
			return -1
		StandEnvelope.Part.WAY:
			return Unlinked.ROUTE_BLOCKED
	return Unlinked.NO_ROOM


## `stands` each on its side's common spur on `on_grid`: the wanted x the build
## and every side stand among them push it to (SideSpurs.wanted()).
static func at_common_lanes(on_grid: BuildGrid, stands: Array[Dictionary]) -> Array[Dictionary]:
	var lanes := SideSpurs.wanted(on_grid, [], {}, stands)
	var out: Array[Dictionary] = []
	for stand in stands:
		var side := StandPlacement.side_of(stand)
		out.append(
			(
				stand
				if side == StandPlacement.NORTH
				else StandPlacement.with_lane_x(stand, lanes[side])
			)
		)
	return out


## Whether `stand` would share private ground with any of `stands` once all of
## them are on the spurs they would share (at_common_lanes()), or two of
## `stands` would once `stand` pushed their side's spur farther out: a later
## gate never moves an earlier one's spur onto ground it is not checked on.
static func overlaps_common(
	on_grid: BuildGrid, stand: Dictionary, stands: Array[Dictionary]
) -> bool:
	var all: Array[Dictionary] = stands.duplicate()
	all.append(stand)
	var moved := at_common_lanes(on_grid, all)
	var placed: Array[Dictionary] = moved.slice(0, stands.size())
	if placed.any(func(other: Dictionary) -> bool: return stands_overlap(moved[-1], other)):
		return true
	if placed == at_common_lanes(on_grid, stands):
		return false
	for i in placed.size():
		for j in range(i + 1, placed.size()):
			if stands_overlap(placed[i], placed[j]):
				return true
	return false


## The first of `links`' gates whose stand overlaps `stand`, both on the spurs
## they would share with every link (at_common_lanes()), or "".
static func _overlapping_gate(
	on_grid: BuildGrid, stand: Dictionary, links: Array[Dictionary]
) -> String:
	var all: Array[Dictionary] = []
	for link in links:
		all.append(SideSpurs.link_stand(on_grid, link["exit"]))
	all.append(stand)
	var moved := at_common_lanes(on_grid, all)
	for i in links.size():
		if stands_overlap(moved[-1], moved[i]):
			return links[i]["gate"]
	return ""


## The exits facing west, north or east at most LINK_CELLS from `footprint`
## (diagonals counting one), nearest first, ties to the lower id.
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
	return BuildCatalog.get_def(record["def"]).footprint(record["anchor"], record["facing"])


## How many cells (diagonals counting one) `footprint` is from exit `exit`'s
## cell.
static func reach_cells(on_grid: BuildGrid, footprint: Array[Vector2i], exit: int) -> int:
	var at: Vector2i = on_grid.get_object(exit)["anchor"]
	var cells := 1 << 30
	for cell in footprint:
		cells = mini(cells, maxi(absi(cell.x - at.x), absi(cell.y - at.y)))
	return cells


static func is_bus_desk(on_grid: BuildGrid, id: int) -> bool:
	var record := on_grid.get_object(id)
	return not record.is_empty() and StringName(record["def"]) == BUS_DESK


static func is_desk(on_grid: BuildGrid, id: int) -> bool:
	var record := on_grid.get_object(id)
	if record.is_empty():
		return false
	var def_id := StringName(record["def"])
	return def_id == DESK or def_id == BUS_DESK


## The gate desks on `on_grid`, in id order.
static func desk_ids(on_grid: BuildGrid) -> Array[int]:
	var out: Array[int] = []
	for id in on_grid.object_ids():
		if is_desk(on_grid, id):
			out.append(id)
	out.sort()
	return out


## The exit door nearest `footprint` (at most LINK_CELLS away, diagonals
## counting one) whose outside faces west, north or east and that is not in
## `taken`; with `fit`, also one fit for a gate beside `stands` (exit_unfit()).
## Ties to the lower id. 0 for none.
static func nearest_exit(
	on_grid: BuildGrid,
	footprint: Array[Vector2i],
	taken: Dictionary,
	stands: Array[Dictionary] = [],
	fit := true,
	bays: Array[Rect2] = []
) -> int:
	var best := 0
	var best_cells := LINK_CELLS + 1
	var ids := on_grid.object_ids()
	ids.sort()
	var remote_swings := RemoteStands.all_small_swings(on_grid)
	for id in ids:
		if taken.has(id) or not _is_gate_exit(on_grid, id):
			continue
		var cells := reach_cells(on_grid, footprint, id)
		if cells >= best_cells:
			continue
		if (
			fit
			and (
				exit_unfit(on_grid, id, stands) >= 0
				or _exit_hits_rects(on_grid, id, bays, remote_swings)
			)
		):
			continue
		if cells < best_cells:
			best = id
			best_cells = cells
	return best


static func _exit_hits_rects(
	on_grid: BuildGrid, exit: int, bays: Array[Rect2], remote_swings: Array[Rect2]
) -> bool:
	if bays.is_empty() and remote_swings.is_empty():
		return false
	var env := StandEnvelope.rects(SideSpurs.link_stand(on_grid, exit), PlaneClasses.SMALL)
	for r in env:
		var shrunk := r.grow(-0.01)
		for bay in bays:
			if shrunk.intersects(bay):
				return true
	var priv := private_rects(SideSpurs.link_stand(on_grid, exit))
	for p in priv:
		var shrunk := p.grow(-0.01)
		for swing in remote_swings:
			if shrunk.intersects(swing):
				return true
	return false


## Whether stands `a` and `b` would share any private ground: their small-plane
## envelopes (StandEnvelope) south of the shared lane zone.
static func stands_overlap(a: Dictionary, b: Dictionary) -> bool:
	for rect_a in private_rects(a):
		for rect_b in private_rects(b):
			if rect_a.intersects(rect_b):
				return true
	return false


## The stand's small-plane envelope south of the shared lane zone, which no
## other gate's may share. The larger envelopes are shared between neighbours.
## A side stand's are its north twin's turned onto it, so they stop at its own
## side lane's band.
static func private_rects(stand: Dictionary) -> Array[Rect2]:
	if StandPlacement.side_of(stand) != StandPlacement.NORTH:
		return StandPlacement.rects_to_world(stand, private_rects(StandPlacement.north_twin(stand)))
	var lane_south := StandPlacement.lane_zone().end.y
	var out: Array[Rect2] = []
	for rect in StandEnvelope.rects(stand, PlaneClasses.SMALL):
		var north := maxf(rect.position.y, lane_south)
		if rect.end.y > north:
			out.append(Rect2(rect.position.x, north, rect.size.x, rect.end.y - north))
	return out


## The site guard's part for gates: a refusal for a gate desk that would link
## to no exit or to none fit for a gate, for an edit that builds under the
## envelope of a gate's booked class, for a removal that would end a gate whose
## flights cannot move, or for an edit whose side spur move would strand a
## flight (SpurTrial, SPUR_STRANDS); else null. `on_grid` is the grid the edit
## is checked on (the live grid or a trial copy of it).
func edit_problem(on_grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var problem: BuildResult = null
	var moves := {}
	if edit.kind == BuildEdit.Kind.REMOVE_OBJECT:
		problem = _removal_problem(on_grid, edit.object_id)
		if problem == null:
			problem = _remote_removal_problem(edit.object_id)
		if problem == null and flights != null:
			moves = _removal_plan(on_grid, edit.object_id)["moves"]
	elif not REMOVALS.has(edit.kind):
		problem = _route_problem(on_grid, edit)
		if problem == null and edit.kind == BuildEdit.Kind.PLACE_OBJECT:
			if edit.def_id == DESK:
				problem = _placement_problem(on_grid, edit)
			elif edit.def_id == BUS_DESK:
				problem = _bus_placement_problem(on_grid, edit)
			elif edit.def_id == RemoteStands.STAND_ID:
				problem = _remote_placement_problem(on_grid, edit)
	# Then the side spurs the edit would move, with a removal's moves carried out
	# in the same trial (SpurTrial): SPUR_STRANDS.
	return problem if problem != null else SpurTrial.problem(self, on_grid, edit, moves)


func _placement_problem(on_grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var footprint := BuildCatalog.get_def(DESK).footprint(edit.cell, edit.facing)
	var links := links_on(on_grid, bindings)
	var taken := {}
	var stands: Array[Dictionary] = []
	var bays: Array[Rect2] = []
	for link in links:
		taken[link["exit"]] = true
		if is_bus_binding(link):
			var bay := BusBays.bay_rect(StandPlacement.for_exit(on_grid, link["exit"]))
			if bay.has_area():
				bays.append(bay)
		else:
			stands.append(SideSpurs.link_stand(on_grid, link["exit"]))
	var reach := nearest_exit(on_grid, footprint, taken, stands, false)
	if reach == 0:
		return BuildResult.refused(BuildResult.Reason.GATE_NO_EXIT)
	if nearest_exit(on_grid, footprint, taken, stands, true, bays) != 0:
		return null
	var remote_swings := RemoteStands.all_small_swings(on_grid)
	if _exit_hits_rects(on_grid, reach, bays, remote_swings):
		return BuildResult.refused(BuildResult.Reason.GATE_STAND_OVERLAP)
	var why := exit_unfit(on_grid, reach, stands)
	if why != Unlinked.STAND_OVERLAP:
		return BuildResult.refused(REFUSAL_OF[why])
	var gate := _overlapping_gate(on_grid, SideSpurs.link_stand(on_grid, reach), links)
	for link in links:
		if gate != "" and link["gate"] == gate:
			var refusal := BuildResult.refused(BuildResult.Reason.GATE_STAND_OVERLAP, link["desk"])
			refusal.detail = "gate %s is too close" % gate
			refusal.detail_args = {"gate": gate}
			return refusal
	return BuildResult.refused(BuildResult.Reason.GATE_STAND_OVERLAP)


func _bus_placement_problem(on_grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var footprint := BuildCatalog.get_def(BUS_DESK).footprint(edit.cell, edit.facing)
	var links := links_on(on_grid, bindings)
	var taken := {}
	var stands: Array[Dictionary] = []
	var bays: Array[Rect2] = []
	for link in links:
		taken[link["exit"]] = true
		if is_bus_binding(link):
			var bay := BusBays.bay_rect(StandPlacement.for_exit(on_grid, link["exit"]))
			if bay.has_area():
				bays.append(bay)
		else:
			stands.append(SideSpurs.link_stand(on_grid, link["exit"]))
	var reach := nearest_exit(on_grid, footprint, taken, stands, false)
	if reach == 0:
		return BuildResult.refused(BuildResult.Reason.GATE_NO_EXIT)
	var blocked := _blocked_envelopes(on_grid, stands)
	if BusBays.nearest_bus_exit(on_grid, footprint, taken, bays, blocked) != 0:
		return null
	return BuildResult.refused(BuildResult.Reason.BUS_BAY_BLOCKED)


func _remote_placement_problem(on_grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var links := links_on(on_grid, bindings)
	var swings := RemoteStands.all_small_swings(on_grid)
	var bays: Array[Rect2] = []
	var reg_stands: Array[Dictionary] = []
	for link in links:
		if is_bus_binding(link):
			var bay := BusBays.bay_rect(StandPlacement.for_exit(on_grid, link["exit"]))
			if bay.has_area():
				bays.append(bay)
		else:
			reg_stands.append(SideSpurs.stand_for_exit(on_grid, link["exit"], spur_x))
	for stand in reg_stands:
		var swing := RemoteStands.small_swing_rect(stand)
		if swing.has_area():
			swings.append(swing)
	for stand in at_common_lanes(on_grid, reg_stands):
		var swing := RemoteStands.small_swing_rect(stand)
		if swing.has_area():
			swings.append(swing)
	var land: LandPlots = (on_grid as SiteGrid).land if on_grid is SiteGrid else null
	return RemoteStands.placement_problem(on_grid, site_of(on_grid), land, edit.cell, swings, bays)


## A GATE_ROUTE / REMOTE_STAND_OVERLAP / BUS_BAY_BLOCKED refusal when `edit`
## builds on an active stand envelope or bus bay, else null.
func _route_problem(on_grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var built := StandEnvelope.edit_cells(edit)
	for binding in bindings:
		if is_bus_binding(binding):
			var exit_stand := StandPlacement.for_exit(on_grid, binding["exit"])
			if BusBays.is_bay_sill_wall(on_grid, exit_stand, edit):
				continue
			var bay := BusBays.bay_rect(exit_stand)
			var bay_cells := BusBays.bay_cells(on_grid, bay)
			if built.any(func(cell: Vector2i) -> bool: return bay_cells.has(cell)):
				return BuildResult.refused(BuildResult.Reason.BUS_BAY_BLOCKED)
			continue
		var booked := booked_class(binding["gate"])
		if booked == "":
			continue
		var under := envelope_cells(on_grid, binding["exit"], booked)
		if built.any(func(cell: Vector2i) -> bool: return under.has(cell)):
			var refusal := BuildResult.refused(BuildResult.Reason.GATE_ROUTE)
			refusal.detail = "gate %s, a %s plane" % [binding["gate"], booked]
			refusal.detail_args = {"gate": binding["gate"], "plane": booked}
			return refusal
	return _remote_route_problem(on_grid, built)


func _remote_route_problem(on_grid: BuildGrid, built: Array[Vector2i]) -> BuildResult:
	for sid: String in remote_stands:
		var entry: Dictionary = remote_stands[sid]
		var stand: Dictionary = entry["stand"]
		var booked := booked_class(sid)
		if booked != "":
			var b_cells := StandEnvelope.cells(on_grid, stand, booked)
			if built.any(func(cell: Vector2i) -> bool: return b_cells.has(cell)):
				var refusal := BuildResult.refused(BuildResult.Reason.GATE_ROUTE)
				refusal.detail = "stand %s, a %s plane" % [sid, booked]
				refusal.detail_args = {"gate": sid, "plane": booked}
				return refusal
		var s_cells := StandEnvelope.cells(on_grid, stand, PlaneClasses.SMALL)
		if built.any(func(cell: Vector2i) -> bool: return s_cells.has(cell)):
			return BuildResult.refused(BuildResult.Reason.REMOTE_STAND_OVERLAP, entry["object_id"])
	return null


## The cells of the `plane_class` envelope at exit `exit`'s stand on `on_grid`,
## kept per stand (its spur too) and class.
func envelope_cells(on_grid: BuildGrid, exit: int, plane_class: String) -> Dictionary:
	var stand := SideSpurs.stand_for_exit(on_grid, exit, spur_x)
	if stand.is_empty():
		return {}
	var key := (
		"%s|%s|%s|%s|%s|%s"
		% [
			stand["x"],
			stand["wall_z"],
			StandPlacement.side_of(stand),
			stand.get("lane_x", ""),
			plane_class,
			on_grid.size,
		]
	)
	if not _envelope_cells.has(key):
		_envelope_cells[key] = StandEnvelope.cells(on_grid, stand, plane_class)
	return _envelope_cells[key]


## What `edit` would do to the gates though it is allowed, for the build ghost
## (SiteGrid.edit_warning): "Gate A will then take planes up to medium" for each
## gate whose max_class envelope it builds in; for removing a desk or exit,
## where the flights of the gate it ends move ("Blue Fjord to Oslo moves to
## Gate A", moves_text()). "" when it changes nothing.
func edit_warning(on_grid: BuildGrid, edit: BuildEdit) -> String:
	if edit.kind == BuildEdit.Kind.REMOVE_OBJECT:
		return moves_text(flights, _removal_plan(on_grid, edit.object_id)["moves"], false)
	if REMOVALS.has(edit.kind):
		return ""
	var built := StandEnvelope.edit_cells(edit)
	var lines := PackedStringArray()
	for binding in bindings:
		if is_bus_binding(binding):
			continue
		var now: String = classes.get(binding["gate"], "")
		if now == "":
			continue
		# The envelopes nest, so the largest class up to now that the edit leaves
		# clear is the class after it.
		var after := ""
		for plane_class in StandEnvelope.LARGEST_FIRST:
			if PlaneClasses.ORDER.find(plane_class) > PlaneClasses.ORDER.find(now):
				continue
			var under := envelope_cells(on_grid, binding["exit"], plane_class)
			if not built.any(func(cell: Vector2i) -> bool: return under.has(cell)):
				after = plane_class
				break
		if after == now:
			continue
		if after == "":
			lines.append("Gate %s will then have no room for a plane" % binding["gate"])
		else:
			lines.append("Gate %s will then take planes up to %s" % [binding["gate"], after])
	return ". ".join(lines)


## A refusal for removing object `id` from `on_grid`, or null. Only a removal
## that ends a gate (its desk, or its exit) can be refused. Gates that already
## lost their desk or exit on `on_grid` (earlier edits of the same batch) are
## counted as ended too, since their contracts have not moved yet.
func _removal_problem(on_grid: BuildGrid, id: int) -> BuildResult:
	var plan := _removal_plan(on_grid, id)
	var ending: Array[String] = plan["ending"]
	if ending.is_empty() or flights == null:
		return null
	var busy := _live_flights_at(ending)
	if not busy.is_empty():
		var refusal := BuildResult.refused(BuildResult.Reason.GATE_IN_USE)
		refusal.detail = FlightLabel.english_list(busy)
		refusal.detail_args = {"flights": busy}
		return refusal
	if not (plan["stuck"] as Array).is_empty():
		var refusal := BuildResult.refused(BuildResult.Reason.GATE_FLIGHTS_STUCK)
		var stuck: Array[Dictionary] = []
		for contract_id: String in plan["stuck"]:
			stuck.append(FlightLabel.label_args(flights, false, contract_id))
		refusal.detail = FlightLabel.english_list(stuck)
		refusal.detail_args = {"flights": stuck}
		return refusal
	return null


func _remote_removal_problem(id: int) -> BuildResult:
	if not _remote_by_obj.has(id) or flights == null:
		return null
	var sid := String(_remote_by_obj[id]["id"])
	for cid in flights.active_contract_ids():
		if String(flights.contract_of(cid).get("stand", "")) == sid:
			return BuildResult.refused(BuildResult.Reason.REMOTE_STAND_IN_USE)
	for fid in flights.flight_ids():
		if flights.flight_stand_id(fid) == sid and flights.state_of(fid) < FlightSim.State.DEPARTED:
			return BuildResult.refused(BuildResult.Reason.REMOTE_STAND_IN_USE)
	return null


## What removing object `id` from `on_grid` does to the gates: {"ending": the
## gates it ends, "moves", "stuck"} as FlightSim.move_plan() has them for those
## gates' running contracts. No moves and nothing stuck when no gate ends.
func _removal_plan(on_grid: BuildGrid, id: int) -> Dictionary:
	var ending: Array[String] = []
	var staying: Array[String] = []
	for binding in bindings:
		var stands: bool = is_desk(on_grid, binding["desk"])
		stands = stands and _is_gate_exit(on_grid, binding["exit"])
		if stands and binding["desk"] != id and binding["exit"] != id:
			staying.append(binding["gate"])
		else:
			ending.append(binding["gate"])
	var plan := {"ending": ending, "moves": {}, "stuck": []}
	if not ending.is_empty() and flights != null:
		var moving := flights.move_plan(ending, staying)
		plan["moves"] = moving["moves"]
		plan["stuck"] = moving["stuck"]
	return plan


## The moves of a FlightSim.move_plan() in words, one line: "Blue Fjord to Oslo
## moves to Gate A" for one flight to a gate, "3 flights move to Gate A" for
## several, gates in letter order, joined by ". ". `past` reads "moved" for the
## notice after the removal; the preview before it reads "moves". "" with no moves.
static func moves_text(sim: FlightSim, moves: Dictionary, past: bool) -> String:
	var by_gate := {}
	for contract_id: String in moves:
		var ids: Array = by_gate.get(moves[contract_id], [])
		ids.append(contract_id)
		by_gate[moves[contract_id]] = ids
	var gates := by_gate.keys()
	gates.sort()
	var lines := PackedStringArray()
	for gate: String in gates:
		var ids: Array = by_gate[gate]
		if ids.size() == 1:
			var contract := sim.contract_of(ids[0])
			var named := {
				"flight":
				TranslationServer.translate("{airline} to {destination}").format(
					{"airline": contract["airline"], "destination": contract["destination"]}
				),
				"gate": gate
			}
			if past:
				lines.append(
					TranslationServer.translate("{flight} moved to Gate {gate}").format(named)
				)
			else:
				lines.append(
					TranslationServer.translate("{flight} moves to Gate {gate}").format(named)
				)
		else:
			var several := {"count": ids.size(), "gate": gate}
			if past:
				lines.append(
					(
						TranslationServer
						. translate_plural(
							"{count} flight moved to Gate {gate}",
							"{count} flights moved to Gate {gate}",
							ids.size()
						)
						. format(several)
					)
				)
			else:
				lines.append(
					(
						TranslationServer
						. translate_plural(
							"{count} flight moves to Gate {gate}",
							"{count} flights move to Gate {gate}",
							ids.size()
						)
						. format(several)
					)
				)
	return ". ".join(lines)


## Tells the player, with one notice on the right rail, which flights a removal
## moved. Without a rail the words are a warning, never passed over silently.
func _post_moved(text: String) -> void:
	_post_notice(MOVED_KEY, tr("Flights moved"), text)


## One notice card on the right rail, or a warning with its words without one.
func _post_notice(key: StringName, title: String, text: String) -> void:
	if not is_instance_valid(alerts) and is_inside_tree():
		alerts = get_tree().get_first_node_in_group(AlertStack.GROUP) as AlertStack
	if not is_instance_valid(alerts):
		push_warning("GateDesks: no alert rail to tell the player: %s" % text)
		return
	var card := OfferPanel.coral_card(key, title, text)
	alerts.post_notice(key, card, 0.0, title, text)


## The live flights at any of `gates` that have not departed, each named by
## its time, airline and destination (FlightLabel.label_args()).
func _live_flights_at(gates: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for flight_id in flights.flight_ids():
		var at_gate := gates.has(flights.flight_gate(flight_id))
		if at_gate and flights.state_of(flight_id) < FlightSim.State.DEPARTED:
			out.append(FlightLabel.label_args(flights, true, flight_id))
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
	var remotes: Array = []
	for sid in remote_stand_ids():
		remotes.append({"id": sid, "object_id": remote_stands[sid]["object_id"]})
	return {
		"save_version": SAVE_VERSION,
		"gates": gates,
		"spurs": spur_x.duplicate(),
		"remote_stands": remotes,
	}


## The bindings a to_snapshot() dictionary holds, checked against `on_grid`:
## {"gates": Array[Dictionary], "spurs": side -> x, "remote_stands": obj -> id}
## or {"error": why}.
static func checked(data: Dictionary, on_grid: BuildGrid) -> Dictionary:
	if data.size() != SAVE_KEYS.size() or not data.has_all(SAVE_KEYS):
		return {"error": "a gates part holds save_version, gates, spurs and remote_stands"}
	var version: Variant = data["save_version"]
	if not WholeNumber.is_whole(version) or int(version) != SAVE_VERSION:
		return {"error": "save_version must be %d" % SAVE_VERSION}
	var lanes := _checked_spurs(data["spurs"])
	if lanes.has("error"):
		return lanes
	var gates := _checked_gates(data["gates"], on_grid)
	if gates.has("error"):
		return gates
	var remotes := RemoteStands.checked_snapshot(data["remote_stands"], on_grid)
	if remotes.has("error"):
		return remotes
	return {
		"gates": gates["gates"],
		"spurs": lanes["spurs"],
		"remote_stands": remotes["by_obj"],
	}


static func _checked_spurs(spurs_saved: Variant) -> Dictionary:
	if typeof(spurs_saved) != TYPE_DICTIONARY or spurs_saved.size() != SideSpurs.SIDES.size():
		return {"error": "'spurs' holds the west and the east spur x"}
	var lanes := {}
	for side in SideSpurs.SIDES:
		var why := StandPlacement.lane_x_problem(side, spurs_saved.get(side))
		if why != "":
			return {"error": "spur %s: %s" % [side, why]}
		lanes[side] = float(spurs_saved[side])
	return {"spurs": lanes}


static func _checked_gates(saved: Variant, on_grid: BuildGrid) -> Dictionary:
	if typeof(saved) != TYPE_ARRAY:
		return {"error": "'gates' is not a list"}
	var out: Array[Dictionary] = []
	var used := {}
	for entry: Variant in saved:
		var problem := _entry_problem(entry, on_grid, used)
		if problem != "":
			return {"error": problem}
		var binding := {
			"gate": str(entry["gate"]), "desk": int(entry["desk"]), "exit": int(entry["exit"])
		}
		if bool(entry.get("is_bus_gate", false)):
			binding["is_bus_gate"] = true
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
## overlap, or a desk with no saved gate that refresh() would link.
static func _set_problem(bindings: Array[Dictionary], on_grid: BuildGrid) -> String:
	var reg_bindings: Array[Dictionary] = []
	var reg_stands: Array[Dictionary] = []
	var bus_bindings: Array[Dictionary] = []
	var bays: Array[Rect2] = []
	for binding in bindings:
		var footprint := desk_footprint(on_grid, binding["desk"])
		if reach_cells(on_grid, footprint, binding["exit"]) > LINK_CELLS:
			return "gate %s: its desk is out of its exit's reach" % binding["gate"]
		if is_bus_binding(binding):
			bus_bindings.append(binding)
			bays.append(BusBays.bay_rect(StandPlacement.for_exit(on_grid, binding["exit"])))
		else:
			reg_bindings.append(binding)
			reg_stands.append(SideSpurs.link_stand(on_grid, binding["exit"]))
	reg_stands = at_common_lanes(on_grid, reg_stands)
	var rem_swings := RemoteStands.all_small_swings(on_grid)
	for i in reg_bindings.size():
		if _exit_hits_rects(on_grid, reg_bindings[i]["exit"], bays, rem_swings):
			return "gate %s overlaps a bus bay or remote stand" % reg_bindings[i]["gate"]
		for j in range(i + 1, reg_bindings.size()):
			if stands_overlap(reg_stands[i], reg_stands[j]):
				return (
					"gates %s and %s have overlapping stands"
					% [reg_bindings[i]["gate"], reg_bindings[j]["gate"]]
				)
	var bus_err := _bus_set_problem(on_grid, bus_bindings, bays, reg_stands)
	if bus_err != "":
		return bus_err
	for link in links_on(on_grid, bindings):
		if link["gate"] == "":
			return (
				"desk %d has no saved gate but would link to exit %d" % [link["desk"], link["exit"]]
			)
	return ""


static func _bus_set_problem(
	on_grid: BuildGrid,
	bus_bindings: Array[Dictionary],
	bays: Array[Rect2],
	reg_stands: Array[Dictionary]
) -> String:
	var site := site_of(on_grid)
	var blocked := _blocked_envelopes(on_grid, reg_stands)
	for i in bus_bindings.size():
		var other_bays: Array[Rect2] = []
		for j in bays.size():
			if j != i:
				other_bays.append(bays[j])
		var stand := StandPlacement.for_exit(on_grid, bus_bindings[i]["exit"])
		if not BusBays.bay_clear(on_grid, site, stand, other_bays, blocked):
			return "bus gate %s has a blocked bay" % bus_bindings[i]["gate"]
	return ""


static func _entry_problem(entry: Variant, on_grid: BuildGrid, used: Dictionary) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return "a gate holds gate, desk and exit"
	var dict: Dictionary = entry
	var expect_bus := dict.has("is_bus_gate")
	var valid_size := dict.size() == GATE_KEYS.size() + (1 if expect_bus else 0)
	if not valid_size or not dict.has_all(GATE_KEYS):
		return "a gate holds gate, desk and exit"
	if expect_bus and typeof(dict["is_bus_gate"]) != TYPE_BOOL:
		return "is_bus_gate must be a bool"
	var letter: Variant = entry["gate"]
	if typeof(letter) != TYPE_STRING or letter.length() != 1 or not LETTERS.contains(letter):
		return "gate '%s' is not a letter A to Z" % [letter]
	var desk := int(entry["desk"]) if WholeNumber.is_whole(entry["desk"]) else 0
	if desk == 0 or not is_desk(on_grid, desk):
		return "gate %s: %s is not a gate desk" % [letter, entry["desk"]]
	if bool(dict.get("is_bus_gate", false)) != is_bus_desk(on_grid, desk):
		return "gate %s: bus gate flag disagrees with desk type" % letter
	if not WholeNumber.is_whole(entry["exit"]) or not _is_gate_exit(on_grid, int(entry["exit"])):
		return "gate %s: %s is not an exit facing west, north or east" % [letter, entry["exit"]]
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
	spur_x = loaded["spurs"]
	_remote_by_obj = {}
	for obj_id: int in loaded["remote_stands"]:
		_remote_by_obj[obj_id] = {"id": loaded["remote_stands"][obj_id], "object_id": obj_id}
	refresh()
	return true


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	if (
		grid != null
		and grid.route_version() == _last_route_ver
		and grid.enclosure_version() == _last_enclosure_ver
		and desk_ids(grid) == _last_desk_ids
		and RemoteStands.object_ids(grid) == _last_remote_ids
	):
		return
	refresh()


## A removal that ended gates moves their contracts first (_removal_problem()
## checked that they fit), before the graph change drops the gates.
func _on_edit_applied(edit: BuildEdit, _result: BuildResult) -> void:
	_spare_stands.clear()
	_spare_prefix.clear()
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
		return
	if not (plan["moves"] as Dictionary).is_empty():
		_post_moved(moves_text(flights, plan["moves"], true))
