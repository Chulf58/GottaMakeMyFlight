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
## while a flight is due there). Each gate's status (no usable stand, when not
## even a small plane fits by GateDesks.max_class or there is no walk; a long
## walk) shows over its own stand, and the guard is the union of what each
## gate's busy flight still needs, asked before GateDesks' refusals (desks,
## removals, and building under a gate's booked envelope, GATE_ROUTE). The
## save holds each gate's stand. Its GateLinksView child draws each gate's link
## from desk to exit to stand and its max_class envelope while build mode
## lasts, and a sign over every gate desk that has no gate. Every refresh sends
## each gate's max_class to the airside (Airside.set_gate_classes()), which
## sizes the gate's stand pad for it.
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
		if gates != null:
			(build_mode.grid as SiteGrid).warner = gates.edit_warning
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
		if passengers != null:
			_links_view.bind_walk(passengers)
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
			"live": stand,
			"placement": gate_check(binding["exit"], stand, gates.max_class(binding["gate"])),
		}
	var desks := {}
	for binding in gates.bindings:
		desks[binding["gate"]] = binding["desk"]
	var moved := _stands_of(next) != _stands_of(gate_stands) or desks != _desks_sent
	gate_stands = next
	# Each gate's pad follows its max_class, which building can change without
	# moving any stand.
	if airside != null:
		var classes := {}
		for gate: String in next:
			classes[gate] = next[gate]["placement"]["max_class"]
		airside.set_gate_classes(classes)
	if moved:
		_apply_live()


## A gate's stand checked as StandPlacement.check() checks one, with the
## gate's `plane_class` (its GateDesks max_class) in place of the medium
## sweep: {"status": OK when some class fits and exit `exit_id` has a walk to
## the door, else UNAVAILABLE; "walk_m" (-1 when UNAVAILABLE); "warning";
## "max_class"}.
func gate_check(exit_id: int, stand: Dictionary, plane_class: String) -> Dictionary:
	var walk: Array[Vector3] = []
	if plane_class != "":
		walk = StandPlacement.walk_of(grid, site, exit_id, stand)
	var metres := StandPlacement.walk_length(walk) if not walk.is_empty() else -1.0
	return {
		"status": StandPlacement.UNAVAILABLE if walk.is_empty() else StandPlacement.OK,
		"walk_m": metres,
		"warning": metres > StandPlacement.WALK_WARNING_M,
		"max_class": plane_class,
	}


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
		and StandPlacement.side_of(a) == StandPlacement.side_of(b)
	)


## The ground the flight at the stand still needs, as world xz rectangles:
## everything its class needs and the box it is parked on (still_rects())
## until it pushes back, then only
## what lies ahead of its rearmost point on the way to the taxi lane, and the
## box it covers (route_rects()). With no taxi route to follow
## (Airside.routes_gate() false) it keeps everything. Empty while no flight is
## at the stand.
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
	var contract := flights.contract_of(flights.flight_contract_id(id))
	var plane_class: String = contract.get("plane_size", FlightSim.STARTER_TERMS["plane_size"])
	var model := PlaneClasses.flight_model(flights, id)
	if flights.state_of(id) < FlightSim.State.TAXI_OUT:
		return still_rects(stand, plane_class, model)
	if airside != null and not airside.routes_gate(gate):
		return still_rects(stand, plane_class, model)
	var path := (
		airside.phase_path(FlightSim.State.TAXI_OUT, gate)
		if airside != null
		else PackedVector3Array(
			[StandPlacement.pushback_end(stand), StandPlacement.lane_join(stand)]
		)
	)
	if path.is_empty():
		return still_rects(stand, plane_class, model)
	var start := flights.state_start(id, FlightSim.State.TAXI_OUT)
	return route_rects(
		stand,
		path,
		flights.phase_progress(id, flights.tick),
		model,
		plane_class,
		flights.taxi_plan(id).get(FlightSim.State.TAXI_OUT, {}),
		float(flights.state_start(id, FlightSim.State.TAKEOFF) - start)
	)


## The ground a `plane_class` plane needs at `stand`, from `north_of` on (a z
## at the stand's north twin, StandPlacement.swept_rects()): the sweep
## StandPlacement has always guarded for small and medium planes, the large
## envelope (StandEnvelope) for a large one, whose wings reach past it.
static func class_rects(stand: Dictionary, plane_class: String, north_of := INF) -> Array[Rect2]:
	if plane_class == PlaneClasses.LARGE:
		return StandEnvelope.rects(stand, PlaneClasses.LARGE, north_of)
	return StandPlacement.swept_rects(stand, north_of)


## What a `model` plane of `plane_class` that has not left its stand needs of
## it: class_rects() and the box it is parked on (parked_rects()), the box left
## out when one of the class's rectangles already holds it (a small plane's).
static func still_rects(stand: Dictionary, plane_class: String, model: String) -> Array[Rect2]:
	var out := class_rects(stand, plane_class)
	for box in parked_rects(stand, model):
		if not out.any(func(rect: Rect2) -> bool: return rect.encloses(box)):
			out.append(box)
	return out


## The ground `model` covers parked at `stand`, as the one world xz rectangle
## PlaneView draws it on: the model's box at the stand point moved by
## PlaneClasses.stand_offset, nose to the wall, turned onto a side stand like
## the rest of its frame (StandPlacement.rects_to_world()). Empty for no model.
## A parked model 04, 06 or 07 reaches past the south edge of its class's swing
## square, short of the wall, so class_rects() leaves that strip out.
static func parked_rects(stand: Dictionary, model: String) -> Array[Rect2]:
	if not PlaneModels.PLANES.has(model):
		return [] as Array[Rect2]
	var twin := StandPlacement.north_twin(stand)
	var box: AABB = PlaneModels.PLANES[model]["aabb"]
	var origin := StandPlacement.stand_point(twin) + PlaneClasses.stand_offset(model)
	var rects: Array[Rect2] = [
		Rect2(origin.x + box.position.x, origin.z + box.position.z, box.size.x, box.size.z)
	]
	return StandPlacement.rects_to_world(stand, rects)


## The corners of `model`'s box drawn at ground `pose` off the stand, centred
## on the pose point (PlaneModels "model_offset", FlightPose.model_position()),
## as world points at y 0.
static func footprint(pose: Transform3D, model: String) -> PackedVector3Array:
	var box: AABB = PlaneModels.PLANES[model]["aabb"]
	var centred: Vector3 = PlaneModels.PLANES[model]["model_offset"]
	var turn := Basis(Vector3.UP, MovementPlan.yaw_of(pose.basis.z))
	var out := PackedVector3Array()
	for x in [box.position.x, box.end.x]:
		for z in [box.position.z + centred.z, box.end.z + centred.z]:
			var at := pose.origin + turn * Vector3(x, 0.0, z)
			out.append(Vector3(at.x, 0.0, at.z))
	return out


## What a `model` plane of `plane_class` `progress` (0 to 1) through TAXI_OUT
## along its route `path` from `stand` still needs of it: the class's ground
## (class_rects()) ahead of the plane's rearmost point, and the box the plane
## covers there. The plane stands where it is drawn (FlightPose.pose(), with
## its planned `pause` inside `budget` ticks), turned to its heading on the
## route, so the cut follows the route on every side and through each corner.
## The cut is taken in the stand's own frame (StandPlacement.to_frame()) and
## never lies north of the old one, the pose point plus StandPlacement.TAIL_M.
static func route_rects(
	stand: Dictionary,
	path: PackedVector3Array,
	progress: float,
	model: String,
	plane_class: String,
	pause := {},
	budget := 0.0
) -> Array[Rect2]:
	var entry := MovementPlan.flat_dir(
		StandPlacement.stand_point(stand), StandPlacement.pushback_end(stand)
	)
	var pose := FlightPose.pose(FlightSim.State.TAXI_OUT, progress, path, entry, pause, budget)
	var tail_z := StandPlacement.to_frame(stand, pose.origin).z + StandPlacement.TAIL_M
	var corners := footprint(pose, model)
	var box := Rect2(Vector2(corners[0].x, corners[0].z), Vector2.ZERO)
	for corner in corners:
		tail_z = maxf(tail_z, StandPlacement.to_frame(stand, corner).z)
		box = box.expand(Vector2(corner.x, corner.z))
	var out := class_rects(stand, plane_class, tail_z)
	out.append(box)
	return out


## The grid cells guard_rects() covers, as a set, worked out once per tick.
func guarded_cells() -> Dictionary:
	var key := [flights.tick, busy_flight(), live.get("x"), live.get("wall_z"), live.get("side")]
	if gates != null:
		key = [flights.tick, _stands_of(gate_stands)]
		for gate: String in gate_stands:
			key.append(busy_flight(gate))
	if key != _guard_key:
		_guard_key = key
		_guard_cells = StandPlacement.cells_under(grid, guard_rects())
	return _guard_cells


## The guard of the site's grid (SiteGrid): a PLANE_AREA refusal for an
## edit that builds on a guarded cell, then the gates' refusals
## (GateDesks.edit_problem: desks, removals and the booked envelopes), else
## null. A plane standing there is named before the bookings behind it.
func edit_problem(on_grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	if not REMOVALS.has(edit.kind):
		var cells := guarded_cells()
		for cell in StandEnvelope.edit_cells(edit):
			if cells.has(cell):
				return BuildResult.refused(BuildResult.Reason.PLANE_AREA)
	if gates != null:
		return gates.edit_problem(on_grid, edit)
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
	var stand := StandPlacement.from_saved(saved)
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
