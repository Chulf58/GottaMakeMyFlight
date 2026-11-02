class_name ApronStand
extends Node3D
## The plane stand the airside uses, as the terminal grows (decision plane-
## stand-design-airside-moves-110-m-north-stand-snaps-to, points 3, 4, 7 and
## 8). It holds two stands (StandPlacement): `wanted`, the best stand for the
## grid as it stands, worked out again on every graph change and on a load,
## and `live`, the one planes and passengers use. Live takes wanted only while
## no flight is between TAXI_IN and its TAKEOFF, so a stand never moves during
## a turnaround: a move waits for the outgoing plane's TAKEOFF. With no legal
## stand anywhere, wanted stays the live one and the status says so.
##
## While a flight uses the stand, edits that build on its parked footprint or
## on the route it still has to sweep (pushback, swing and the way north to
## the taxi lane) are refused (edit_problem(), the guard of the site's
## SiteGrid), and that area is drawn on the ground (GuardView) while build
## mode lasts: during normal play only the plane shows (user ruling plane-
## guard-area-shows-only-in-build-mode-the-site-paving-ex, point 1). Build
## mode is BuildMenu's BuildSession, so GuardView follows its changed signal,
## as BuildableOutline does. Removals are always allowed. A label over the
## stand shows a pending move with the time it will happen, "no usable
## stand", and a walk from an exit to the plane door over
## StandPlacement.WALK_WARNING_M, which refuses nothing.
##
## Only `live` is saved; wanted is worked out from the loaded grid.
##
## With gate desks (`gates`, GateDesks; decision gates-technical-design-gate-
## desks-link-to-north-exits-one-st, point 2) there is one stand per gate,
## straight out from its exit (gate_stands), in place of the one live stand.
## A gate's link is sticky and its exit never moves, so its stand is fixed
## while the gate lasts: the release rule above has nothing to wait for, and
## a stand only comes and goes with its gate (GateDesks refuses ending a gate
## while a flight is due there). Each gate's status (no usable stand, a long
## walk) shows over its own stand, and the guard is the union of what each
## gate's busy flight still needs. The save holds each gate's stand. Its
## GateLinksView child draws each gate's link from desk to exit to stand while
## build mode lasts, and a sign over every gate desk that has no gate.
##
## Not guaranteed: the live stand stays where it is while no legal stand
## exists, even when the player builds over its apron with no plane there.

## The live stand moved; Airside and PassengerSim have been told.
signal live_changed(stand: Dictionary)

const STATUS_HEIGHT_M := 18.0
const AREA_LIFT_M := 0.32
const AREA_TINT := Color(1.0, 0.5, 0.1, 0.3)
const REMOVALS: Array[BuildEdit.Kind] = [
	BuildEdit.Kind.REMOVE_FLOOR,
	BuildEdit.Kind.REMOVE_WALL,
	BuildEdit.Kind.REMOVE_OBJECT,
	BuildEdit.Kind.REMOVE_ROOM,
]

@export var build_mode: BuildMode
@export var flights: FlightSim
@export var airside: Airside
@export var passengers: PassengerSim
## The menu whose build session shows and hides the guarded area.
@export var menu: BuildMenu
## The gate desks; set, there is one stand per gate (gate_stands).
@export var gates: GateDesks

var live: Dictionary = {}
var wanted: Dictionary = {}
## The last StandPlacement.place() result.
var placement: Dictionary = {}
## The tick the live stand last took the wanted one, or -1.
var last_release_tick := -1
var grid: BuildGrid
var site: SiteDefinition
## With gates: gate letter -> {"live": its stand, "placement": its
## StandPlacement.check() result}.
var gate_stands: Dictionary = {}
## Gate letter -> the gate desk object id last sent to the passengers.
var _desks_sent: Dictionary = {}

var _guard_key: Array = []
var _guard_cells: Dictionary = {}
var _label: Label3D
## Holds the guarded-area meshes; shown only while build mode lasts.
var _guard_view := Node3D.new()
var _areas: Array[MeshInstance3D] = []
var _area_material: StandardMaterial3D
## With gates: gate letter -> its status Label3D.
var _gate_labels: Dictionary = {}
## With gates: the desk-to-exit-to-stand links and the unlinked desks' signs.
var _links_view := GateLinksView.new()


func _init() -> void:
	_guard_view.name = "GuardView"
	_guard_view.visible = false
	add_child(_guard_view)
	_links_view.name = "GateLinks"
	add_child(_links_view)


func _ready() -> void:
	_label = Label3D.new()
	_label.name = "Status"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 64
	_label.outline_size = 12
	_label.pixel_size = 0.02
	_label.visible = false
	add_child(_label)
	_area_material = StandardMaterial3D.new()
	_area_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_area_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_area_material.albedo_color = AREA_TINT
	for i in 2:
		_add_area()
	if menu != null:
		watch(menu.build_session)
	if build_mode == null or flights == null or build_mode.site == null:
		return
	bind(build_mode.grid, build_mode.site, flights, gates)
	if build_mode.grid is SiteGrid:
		(build_mode.grid as SiteGrid).guard = edit_problem
	_apply_live()


## One more guarded-area mesh: two for the one stand, two per busy gate.
func _add_area() -> void:
	var area := MeshInstance3D.new()
	area.name = "GuardedArea%d" % _areas.size()
	var mesh := PlaneMesh.new()
	mesh.material = _area_material
	area.mesh = mesh
	area.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	area.visible = false
	_guard_view.add_child(area)
	_areas.append(area)


func _process(_delta: float) -> void:
	if grid == null:
		return
	var frame := Rect2(Vector2(site.grid_origin.x, site.grid_origin.z), Vector2(site.grid_size))
	var rects := clip_rects(guard_rects(), frame)
	while _areas.size() < rects.size():
		_add_area()
	for i in _areas.size():
		_areas[i].visible = i < rects.size()
		if i < rects.size():
			var rect := rects[i]
			(_areas[i].mesh as PlaneMesh).size = rect.size
			_areas[i].position = Vector3(rect.get_center().x, AREA_LIFT_M, rect.get_center().y)
	if gates != null:
		_show_gate_labels()
		return
	var text := status_text()
	_label.text = text
	_label.visible = text != ""
	_label.position = StandPlacement.stand_point(live) + Vector3.UP * STATUS_HEIGHT_M


## Starts on the starter stand and follows the grid and the flights; with
## `on_gates`, one stand per gate, worked out after each change of the links.
func bind(
	on_grid: BuildGrid, on_site: SiteDefinition, on_flights: FlightSim, on_gates: GateDesks = null
) -> void:
	grid = on_grid
	site = on_site
	flights = on_flights
	gates = on_gates
	flights.state_changed.connect(_on_state_changed)
	if gates != null:
		live = {}
		gates.changed.connect(refresh)
		_links_view.bind(grid, gates)
	else:
		live = StandPlacement.starter_stand(grid, site)
		grid.graph_changed.connect(_on_graph_changed)
	refresh()


## Shows the guarded area while `session` lasts, and hides it outside it.
func watch(session: BuildSession) -> void:
	if not session.changed.is_connected(set_building):
		session.changed.connect(set_building)
	set_building(session.active)


func set_building(on: bool) -> void:
	_guard_view.visible = on
	_links_view.set_building(on)


## The gate links view (for probes and tests).
func links_view() -> GateLinksView:
	return _links_view


## Works the wanted stand out again and lets the live one take it if it may.
func refresh() -> void:
	if gates != null:
		_refresh_gates()
		return
	placement = StandPlacement.place(grid, site, live)
	wanted = placement["stand"]
	try_release()


## Each gate's stand from its exit, and its check; tells the airside and the
## passengers when the stands changed.
func _refresh_gates() -> void:
	var next := {}
	for binding in gates.bindings:
		var stand := StandPlacement.for_exit(grid, binding["exit"])
		next[binding["gate"]] = {
			"live": stand, "placement": StandPlacement.check(grid, site, binding["exit"], stand)
		}
	var desks := {}
	for binding in gates.bindings:
		desks[binding["gate"]] = binding["desk"]
	var moved := _stands_of(next) != _stands_of(gate_stands) or desks != _desks_sent
	gate_stands = next
	if moved:
		_apply_live()


## Gate letter -> its stand.
static func _stands_of(entries: Dictionary) -> Dictionary:
	var out := {}
	for gate: String in entries:
		out[gate] = entries[gate]["live"]
	return out


## The flight between TAXI_IN and TAKEOFF at the stand, or "". With gates,
## the one at gate `gate`'s stand.
func busy_flight(gate := "") -> String:
	for id in flights.flight_ids():
		if gate != "" and flights.flight_gate(id) != gate:
			continue
		var state := flights.state_of(id)
		if state >= FlightSim.State.TAXI_IN and state < FlightSim.State.TAKEOFF:
			return id
	return ""


## The live stand takes the wanted one when they differ and no flight is
## turning round. True when it moved. With gates a stand never moves.
func try_release() -> bool:
	if gates != null or same_stand(wanted, live) or busy_flight() != "":
		return false
	live = wanted
	last_release_tick = flights.tick
	_apply_live()
	return true


static func same_stand(a: Dictionary, b: Dictionary) -> bool:
	if not (StandPlacement.is_stand(a) and StandPlacement.is_stand(b)):
		return a.is_empty() and b.is_empty()
	return (
		int(a["exit"]) == int(b["exit"])
		and is_equal_approx(float(a["x"]), float(b["x"]))
		and is_equal_approx(float(a["wall_z"]), float(b["wall_z"]))
	)


## The ground the flight at the stand still needs, as world xz rectangles:
## everything StandPlacement.swept_rects() covers until it pushes back, then
## only what lies north of its tail on the way to the taxi lane. Empty while
## no flight is at the stand.
func guard_rects() -> Array[Rect2]:
	if gates == null:
		return _rects_of(busy_flight(), live, "")
	var out: Array[Rect2] = []
	for gate: String in gate_stands:
		out.append_array(_rects_of(busy_flight(gate), gate_stands[gate]["live"], gate))
	return out


## `rects` cut to `frame`; a rectangle wholly outside it is dropped.
static func clip_rects(rects: Array[Rect2], frame: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for rect in rects:
		if rect.intersects(frame):
			out.append(rect.intersection(frame))
	return out


## What flight `id` (none: "") still needs of `stand`, the stand of gate
## `gate` ("" for the one stand).
func _rects_of(id: String, stand: Dictionary, gate: String) -> Array[Rect2]:
	if id == "":
		return [] as Array[Rect2]
	if flights.state_of(id) < FlightSim.State.TAXI_OUT:
		return StandPlacement.swept_rects(stand)
	var path := (
		airside.phase_path(FlightSim.State.TAXI_OUT, gate)
		if airside != null
		else PackedVector3Array(
			[StandPlacement.pushback_end(stand), StandPlacement.lane_join(stand)]
		)
	)
	var t := smoothstep(0.0, 1.0, flights.phase_progress(id, flights.tick))
	var at := FlightPose.point_at(path, FlightPose.path_length(path) * t)
	return StandPlacement.swept_rects(stand, at.z + StandPlacement.TAIL_M)


## The grid cells guard_rects() covers, as a set, worked out once per tick.
func guarded_cells() -> Dictionary:
	var key := [flights.tick, busy_flight(), live.get("x"), live.get("wall_z")]
	if gates != null:
		key = [flights.tick, _stands_of(gate_stands)]
		for gate: String in gate_stands:
			key.append(busy_flight(gate))
	if key != _guard_key:
		_guard_key = key
		_guard_cells = StandPlacement.cells_under(grid, guard_rects())
	return _guard_cells


## The guard of the site's grid (SiteGrid): a PLANE_AREA refusal for an
## edit that builds on a guarded cell, else null. Removals pass.
func edit_problem(on_grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	if gates != null:
		var gate_problem := gates.edit_problem(on_grid, edit)
		if gate_problem != null:
			return gate_problem
	if REMOVALS.has(edit.kind):
		return null
	var cells := guarded_cells()
	if cells.is_empty():
		return null
	for cell in _cells_of(edit):
		if cells.has(cell):
			return BuildResult.refused(BuildResult.Reason.PLANE_AREA)
	return null


## What gate `gate`'s status label says, or "" for nothing.
func gate_status_text(gate: String) -> String:
	var entry: Dictionary = gate_stands.get(gate, {})
	if entry.is_empty():
		return ""
	var checked_stand: Dictionary = entry["placement"]
	if checked_stand["status"] == StandPlacement.UNAVAILABLE:
		return "Gate %s: no usable stand. Keep its apron and the walk to it clear" % gate
	if checked_stand["warning"]:
		return "Gate %s: long walk to the plane: %d m" % [gate, roundi(checked_stand["walk_m"])]
	return ""


func _show_gate_labels() -> void:
	for gate: String in _gate_labels.keys():
		if not gate_stands.has(gate):
			(_gate_labels[gate] as Label3D).queue_free()
			_gate_labels.erase(gate)
	for gate: String in gate_stands:
		if not _gate_labels.has(gate):
			var made := _label.duplicate() as Label3D
			made.name = "Status%s" % gate
			add_child(made)
			_gate_labels[gate] = made
		var label: Label3D = _gate_labels[gate]
		label.text = gate_status_text(gate)
		label.visible = label.text != ""
		label.position = (
			StandPlacement.stand_point(gate_stands[gate]["live"]) + Vector3.UP * STATUS_HEIGHT_M
		)


## What the status label says, or "" for nothing.
func status_text() -> String:
	var lines: PackedStringArray = []
	if placement.get("status", StandPlacement.OK) == StandPlacement.UNAVAILABLE:
		lines.append("No usable stand: no exit faces north with a clear apron")
	elif not same_stand(wanted, live):
		var id := busy_flight()
		var at := flights.state_start(id, FlightSim.State.TAKEOFF) if id != "" else flights.tick
		lines.append(
			"Stand moves to the new exit after takeoff at %s" % GameCalendar.clock_text(at)
		)
	if placement.get("warning", false):
		lines.append("Long walk to the plane: %d m" % roundi(placement["longest_walk_m"]))
	return "\n".join(lines)


## {"live": the live stand}, or with gates {"stands": gate letter -> its
## stand}.
func to_snapshot() -> Dictionary:
	if gates != null:
		return {"stands": _stands_of(gate_stands).duplicate(true)}
	return {"live": live.duplicate()}


## The stands a to_snapshot() dictionary holds, as {"live": stand} or
## {"stands": gate letter -> stand}, or {"error": why} when it is malformed or
## a stand's door and wall line lie outside `on_site`'s grid.
static func checked(data: Dictionary, on_site: SiteDefinition) -> Dictionary:
	if data.size() != 1 or not (data.has("live") or data.has("stands")):
		return {"error": "an apron part holds 'live' or 'stands'"}
	if data.has("live"):
		var one := _checked_stand(data["live"], on_site)
		return one if one.has("error") else {"live": one["stand"]}
	if typeof(data["stands"]) != TYPE_DICTIONARY:
		return {"error": "'stands' is not a dictionary"}
	var stands := {}
	for gate: Variant in data["stands"]:
		if typeof(gate) != TYPE_STRING:
			return {"error": "a stand's gate is not a letter"}
		var one := _checked_stand(data["stands"][gate], on_site)
		if one.has("error"):
			return {"error": "gate %s: %s" % [gate, one["error"]]}
		stands[gate] = one["stand"]
	return {"stands": stands}


static func _checked_stand(saved: Variant, on_site: SiteDefinition) -> Dictionary:
	if not StandPlacement.is_stand(saved) or not WholeNumber.is_whole(saved["exit"]):
		return {"error": "'live' is not a stand"}
	var stand := StandPlacement.make(int(saved["exit"]), float(saved["x"]), float(saved["wall_z"]))
	var low := Vector2(on_site.grid_origin.x, on_site.grid_origin.z)
	var frame := Rect2(low, Vector2(on_site.grid_size))
	if int(stand["exit"]) < 0 or not frame.has_point(Vector2(stand["x"], stand["wall_z"])):
		return {"error": "the live stand lies outside the site"}
	return {"stand": stand}


## Why saved gate stands `stands` do not belong to the gates in `bindings`
## (GateDesks) on `on_grid`, or "": every gate needs its own stand, straight
## out from its exit, and there is no other.
static func stands_problem(
	stands: Dictionary, bindings: Array[Dictionary], on_grid: BuildGrid
) -> String:
	if stands.size() != bindings.size():
		return "there are %d gates but %d stands" % [bindings.size(), stands.size()]
	for binding in bindings:
		var saved: Dictionary = stands.get(binding["gate"], {})
		if not same_stand(saved, StandPlacement.for_exit(on_grid, binding["exit"])):
			return "gate %s's stand is not the one out from its exit" % binding["gate"]
	return ""


## Loads the stands (checked()) and works the rest out from the grid. False
## (with an error) for a refused save, or for one of the other kind (one live
## stand with gates, or gate stands without).
func from_snapshot(data: Dictionary) -> bool:
	if site == null:
		push_error("ApronStand.from_snapshot: no site is bound")
		return false
	var loaded := checked(data, site)
	if not loaded.has("error") and loaded.has("stands") != (gates != null):
		loaded = {"error": "the save's stands are not of this airport's kind"}
	if not loaded.has("error") and gates != null:
		var problem := stands_problem(loaded["stands"], gates.bindings, grid)
		if problem != "":
			loaded = {"error": problem}
	if loaded.has("error"):
		push_error("ApronStand.from_snapshot: %s" % loaded["error"])
		return false
	if gates != null:
		gate_stands = {}
		refresh()
		return true
	live = loaded["live"]
	_apply_live()
	refresh()
	return true


func _apply_live() -> void:
	if gates != null:
		_apply_gate_stands()
		return
	if airside != null:
		airside.set_stand(live)
	if passengers != null and passengers.grid != null:
		passengers.set_stand(live)
	live_changed.emit(live)


## The gate stands to the airside (one set of stand waypoints per gate) and to
## the passengers (each gate's exit walks to its own stand).
func _apply_gate_stands() -> void:
	_desks_sent = {}
	for binding in gates.bindings:
		_desks_sent[binding["gate"]] = binding["desk"]
	var by_gate := _stands_of(gate_stands)
	if airside != null:
		airside.set_gate_stands(by_gate)
	if passengers == null or passengers.grid == null:
		return
	var exit_stands := {}
	var exit_gates := {}
	for gate: String in by_gate:
		var exit_id: int = by_gate[gate]["exit"]
		exit_stands[exit_id] = by_gate[gate]
		exit_gates[exit_id] = gate
	passengers.set_gate_stands(exit_stands, exit_gates, _desks_sent.duplicate())


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	refresh()


func _on_state_changed(_id: String, state: int) -> void:
	if state == FlightSim.State.TAKEOFF:
		try_release()


static func _cells_of(edit: BuildEdit) -> Array[Vector2i]:
	var out: Array[Vector2i] = [edit.cell]
	match edit.kind:
		BuildEdit.Kind.PLACE_WALL:
			out.append(edit.cell + BuildGrid.SIDE_STEP[edit.side])
		BuildEdit.Kind.PLACE_OBJECT:
			var def := BuildCatalog.get_def(edit.def_id)
			if def != null:
				out = def.footprint(edit.cell, edit.facing)
		BuildEdit.Kind.PLACE_ROOM, BuildEdit.Kind.RESIZE_ROOM:
			for y in edit.room_size.y:
				for x in edit.room_size.x:
					out.append(edit.cell + Vector2i(x, y))
	return out
