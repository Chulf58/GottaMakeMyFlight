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
## A pose point this close to a route's first leg is on it.
const ON_LEG_M := 0.001
## The steps, in metres of route, the box of a plane still to turn or to clear the
## class's ground is sampled at, and the margin added to what they reach, for
## the swing between two samples.
const TURN_STEP_M := 0.5
const TURN_MARGIN_M := 0.3
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
var _drawn_key: Array = []
var _drawn_rects_cache: Array[Rect2] = []
var _label: Label3D
## Holds the guarded-area meshes; shown only while build mode lasts.
var _guard_view := Node3D.new()
var _areas: Array[MeshInstance3D] = []
var _area_material: StandardMaterial3D
## With gates: gate letter -> its status Label3D.
var _gate_labels: Dictionary = {}
## With gates: the desk-to-exit-to-stand links and the unlinked desks' signs.
var _links_view := GateLinksView.new()
## The construction works over a pending side spur and the runway upgrade.
var _works := TaxiwayWorksView.new()
var _last_route_ver := -1
var _last_enclosure_ver := -1


func _init() -> void:
	_guard_view.name = "GuardView"
	_guard_view.visible = false
	add_child(_guard_view)
	_links_view.name = "GateLinks"
	add_child(_links_view)
	_works.name = "TaxiwayWorks"
	add_child(_works)


func _ready() -> void:
	_label = CaptionFont.apply(Label3D.new())
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
	if airside != null:
		_works.bind(flights, airside)
	if build_mode.grid is SiteGrid:
		(build_mode.grid as SiteGrid).guard = edit_problem
		if gates != null:
			(build_mode.grid as SiteGrid).warner = gates.edit_warning
	_apply_live()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_retranslate()


func _retranslate() -> void:
	if grid == null:
		return
	refresh()
	if gates != null:
		_show_gate_labels()
	elif _label != null:
		var text := status_text()
		_label.text = text
		_label.visible = text != ""


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
	var rects := clip_rects(_drawn_rects(), frame)
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
	if grid != null:
		_last_route_ver = grid.route_version()
		_last_enclosure_ver = grid.enclosure_version()
	placement = StandPlacement.place(grid, site, live)
	wanted = placement["stand"]
	try_release()


## Each gate's stand from its exit, and its check; tells the airside and the
## passengers when the stands changed.
func _refresh_gates() -> void:
	var next := {}
	for binding in gates.bindings:
		if GateDesks.is_bus_binding(binding):
			continue
		var stand := SideSpurs.stand_for_exit(grid, binding["exit"], gates.spur_x)
		next[binding["gate"]] = {
			"live": stand,
			"placement": gate_check(binding["exit"], stand, gates.max_class(binding["gate"])),
		}
	var desks := {}
	for binding in gates.bindings:
		desks[binding["gate"]] = binding["desk"]
	var moved := _stands_of(next) != _stands_of(gate_stands) or desks != _desks_sent
	gate_stands = next
	if airside != null:
		var classes := {}
		for gate: String in next:
			classes[gate] = next[gate]["placement"]["max_class"]
		airside.set_gate_classes(classes)
		var rem_stands := {}
		var rem_classes := {}
		for sid: String in gates.remote_stands:
			var entry: Dictionary = gates.remote_stands[sid]
			rem_stands[sid] = entry["stand"]
			rem_classes[sid] = entry["max_class"]
		airside.set_remote_stands(rem_stands, rem_classes)
		airside.set_bus_bays(BusBays.bays_for(grid, gates.bindings))
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


## All live flights between TAXI_IN and TAKEOFF (exclusive), optionally filtered
## to `gate`.
func busy_flights(gate := "") -> Array[String]:
	var out: Array[String] = []
	for id in flights.flight_ids():
		if gate != "" and flights.flight_gate(id) != gate and flights.flight_stand_id(id) != gate:
			continue
		var state := flights.state_of(id)
		if state >= FlightSim.State.TAXI_IN and state < FlightSim.State.TAKEOFF:
			out.append(id)
	return out


## The first flight between TAXI_IN and TAKEOFF at the stand, or "". With gates,
## the first at gate `gate`'s stand.
func busy_flight(gate := "") -> String:
	var ids := busy_flights(gate)
	return ids[0] if not ids.is_empty() else ""


## The live stand takes the wanted one when they differ and no flight is
## turning round. True when it moved. With gates a stand never moves.
func try_release() -> bool:
	if gates != null or same_stand(wanted, live) or busy_flight() != "":
		return false
	live = wanted
	last_release_tick = flights.tick
	_apply_live()
	return true


## Whether `a` and `b` are one stand: the same exit, sill and side, and for a
## west or east stand the same spur (lane_x).
static func same_stand(a: Dictionary, b: Dictionary) -> bool:
	if not (StandPlacement.is_stand(a) and StandPlacement.is_stand(b)):
		return a.is_empty() and b.is_empty()
	var side := StandPlacement.side_of(a)
	return (
		int(a["exit"]) == int(b["exit"])
		and is_equal_approx(float(a["x"]), float(b["x"]))
		and is_equal_approx(float(a["wall_z"]), float(b["wall_z"]))
		and side == StandPlacement.side_of(b)
		and (
			side == StandPlacement.NORTH
			or is_equal_approx(StandPlacement.lane_x_of(a), StandPlacement.lane_x_of(b))
		)
	)


## The ground the flight at the stand still needs, as world xz rectangles:
## everything its class needs and the box it is parked on (still_rects())
## until it pushes back, then only
## what lies ahead of its rearmost point on the way to the taxi lane, and the
## box it covers (route_rects()). With no taxi route to follow
## (Airside.routes_gate() false) it keeps everything. Empty while no flight is
## at the stand. With gates, the side spurs issued flights still need too
## (spur_rects()).
func guard_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if gates == null:
		for id in busy_flights():
			out.append_array(_rects_of(id, live, ""))
		return out
	for gate: String in gate_stands:
		var stand: Dictionary = gate_stands[gate]["live"]
		for id in busy_flights(gate):
			out.append_array(_rects_of(id, stand, gate))
	for sid: String in gates.remote_stands:
		var stand: Dictionary = gates.remote_stands[sid]["stand"]
		for id in busy_flights(sid):
			out.append_array(_rects_of(id, stand, sid))
	out.append_array(spur_rects())
	return out


## The side spurs planes still need (decision side-spur-move-design-s7-stands-
## carry-lane-x-the-wanted-spur): for each gate on a west or east stand with a
## flight issued and not yet at TAKEOFF, its spur from the taxi lane to the
## stand's join, as wide as the band a plane on it sweeps (SideSpurs.
## build_clearance()). Empty without gates.
func spur_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var half := SideSpurs.build_clearance()
	for gate: String in gate_stands:
		var stand: Dictionary = gate_stands[gate]["live"]
		if StandPlacement.side_of(stand) == StandPlacement.NORTH or not _flies_before_takeoff(gate):
			continue
		var top := StandPlacement.TAXI_LANE_Z
		var south := StandPlacement.lane_join(stand).z + half
		out.append(Rect2(StandPlacement.lane_x_of(stand) - half, top, 2.0 * half, south - top))
	return out


## Whether a live flight at gate `gate` has not reached TAKEOFF.
func _flies_before_takeoff(gate: String) -> bool:
	for id in flights.flight_ids():
		if flights.flight_gate(id) == gate and flights.state_of(id) < FlightSim.State.TAKEOFF:
			return true
	return false


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
## route.
##
## The cut follows the plane along the route's first leg, from the pushback's
## end to the join, which runs north in the stand's own frame
## (StandPlacement.to_frame()): the ground north of the pose point plus the
## plane's rear on that heading (at least StandPlacement.TAIL_M). Near the join
## it also holds what the plane's box will still reach: from
## MovementPlan.CORNER_BLEND before the join, where the plane starts to turn,
## on along the leg after it for as long as the box overlaps the class's ground.
## Past that the plane is on the lane or a spur with the ground behind it, and
## only its box is held. A later leg is never read in the stand's frame: a spur
## or the lane runs along its z, or back across its x, and read there it would
## take released ground back. So the cut only moves north, what is released
## stays released, and a cell the plane covers now or on its way out is guarded.
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
	var corners := footprint(pose, model)
	var box := Rect2(Vector2(corners[0].x, corners[0].z), Vector2.ZERO)
	for corner in corners:
		box = box.expand(Vector2(corner.x, corner.z))
	var cut := _cut_z(stand, path, entry, model, plane_class, pose.origin)
	var out := class_rects(stand, plane_class, cut)
	out.append(box)
	return out


## The z, at `stand`'s north twin, north of which route_rects() keeps the class's
## ground for a `model` plane of `plane_class` at `origin` on `path` (its first
## leg runs from the pushback's end to the join): the plane's rear, and the
## furthest rear of the box at every pose still ahead of it from the start of
## its turn at the join, up to the last one whose box overlaps the class's
## ground (a pose past the corner is its box turned to the leg's heading). -INF
## once no such pose is left, or when the plane is not on the first two legs.
static func _cut_z(
	stand: Dictionary,
	path: PackedVector3Array,
	entry: Vector3,
	model: String,
	plane_class: String,
	origin: Vector3
) -> float:
	if path.size() < 2:
		return _rear_z(stand, origin, entry, model)
	var join := path[1]
	var run := path[0].distance_to(join)
	var travelled := 0.0
	var rear := 0.0
	if _on_leg(origin, path[0], join):
		travelled = path[0].distance_to(origin)
		rear = _rear_z(stand, origin, entry, model)
	elif path.size() > 2 and _on_leg(origin, join, path[2]):
		travelled = run + origin.distance_to(join)
		rear = _rear_z(stand, join, entry, model)
	else:
		return -INF
	var ground := class_rects(stand, plane_class)
	var total := MovementPlan.path_length(path)
	var turn_end := run + MovementPlan.CORNER_BLEND
	var at := maxf(travelled, run - MovementPlan.CORNER_BLEND)
	var cut := -INF
	var swept := false
	while true:
		var turned := Transform3D(
			Basis(Vector3.UP, MovementPlan.yaw_of(MovementPlan.heading_at(path, at, entry))),
			MovementPlan.point_at(path, at)
		)
		var corners := footprint(turned, model)
		if at > turn_end and not _overlaps(corners, ground):
			break
		swept = true
		for corner in corners:
			cut = maxf(cut, StandPlacement.to_frame(stand, corner).z + TURN_MARGIN_M)
		if at >= total:
			break
		at = minf(at + TURN_STEP_M, total)
	return maxf(cut, rear) if swept else -INF


## Whether the box with `corners` (footprint()), grown by TURN_MARGIN_M, overlaps
## any of `rects`.
static func _overlaps(corners: PackedVector3Array, rects: Array[Rect2]) -> bool:
	var box := Rect2(Vector2(corners[0].x, corners[0].z), Vector2.ZERO)
	for corner in corners:
		box = box.expand(Vector2(corner.x, corner.z))
	box = box.grow(TURN_MARGIN_M)
	return rects.any(func(rect: Rect2) -> bool: return rect.intersects(box))


## The z, at `stand`'s north twin, of the rearmost point of a `model` plane at
## `origin` heading `entry`: StandPlacement.TAIL_M behind it, or further when
## the model's box reaches further.
static func _rear_z(stand: Dictionary, origin: Vector3, entry: Vector3, model: String) -> float:
	var rear := StandPlacement.to_frame(stand, origin).z + StandPlacement.TAIL_M
	var straight := Transform3D(Basis(Vector3.UP, MovementPlan.yaw_of(entry)), origin)
	for corner in footprint(straight, model):
		rear = maxf(rear, StandPlacement.to_frame(stand, corner).z)
	return rear


## Whether `point` lies on the segment from `from` to `to`.
static func _on_leg(point: Vector3, from: Vector3, to: Vector3) -> bool:
	return Geometry3D.get_closest_point_to_segment(point, from, to).distance_to(point) < ON_LEG_M


## The grid cells guard_rects() covers, as a set, worked out once per tick.
func guarded_cells() -> Dictionary:
	var key := _tick_key()
	if key != _guard_key:
		_guard_key = key
		_guard_cells = StandPlacement.cells_under(grid, guard_rects())
	return _guard_cells


## guard_rects() for the drawn area, worked out once per tick like
## guarded_cells(): _process() asks every rendered frame, and a taxiing plane's
## rects are worked out from many poses.
func _drawn_rects() -> Array[Rect2]:
	var key := _tick_key()
	if key != _drawn_key:
		_drawn_key = key
		_drawn_rects_cache = guard_rects()
	return _drawn_rects_cache


## What the guard is worked out from: the tick, the flights at the stands and
## the stands (a side stand's spur too).
func _tick_key() -> Array:
	var key := [
		flights.tick,
		busy_flights(),
		live.get("x"),
		live.get("wall_z"),
		live.get("side"),
		live.get("lane_x"),
	]
	if gates != null:
		var rem_ids := gates.remote_stand_ids()
		key = [flights.tick, _stands_of(gate_stands), rem_ids]
		for gate: String in gate_stands:
			# A flight issued while the clock is paused adds a spur band
			# (spur_rects()) at the same tick.
			key.append_array([busy_flights(gate), _flies_before_takeoff(gate)])
		for sid in rem_ids:
			key.append_array([gates.remote_stands[sid]["stand"], busy_flights(sid)])
	return key


## The guard of the site's grid (SiteGrid): a PLANE_AREA refusal for an
## edit that builds on a guarded cell, then the gates' refusals
## (GateDesks.edit_problem: desks, removals and the booked envelopes), else
## null. A plane standing there is named before the bookings behind it, and
## land the player does not own before the plane (LandPlots.edit_problem()):
## a side spur's band reaches over the side plots.
func edit_problem(on_grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	if not REMOVALS.has(edit.kind):
		var cells := guarded_cells()
		for cell in StandEnvelope.edit_cells(edit):
			if cells.has(cell):
				var land: LandPlots = (on_grid as SiteGrid).land if on_grid is SiteGrid else null
				var unowned := land.edit_problem(edit) if land != null else null
				return (
					unowned
					if unowned != null
					else BuildResult.refused(BuildResult.Reason.PLANE_AREA)
				)
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
		return (
			tr(
				"Gate {gate}: no usable stand. Keep its apron and the walk to it clear",
				"apron caption"
			)
			. format({"gate": gate})
		)
	if checked_stand["warning"]:
		return tr("Gate {gate}: long walk to the plane: {meters} m", "apron caption").format(
			{"gate": gate, "meters": roundi(checked_stand["walk_m"])}
		)
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
		lines.append(
			tr("No usable stand: no exit facing the planes has a clear apron", "apron caption")
		)
	elif not same_stand(wanted, live):
		var id := busy_flight()
		var at := flights.state_start(id, FlightSim.State.TAKEOFF) if id != "" else flights.tick
		lines.append(
			tr("Stand moves to the new exit after takeoff at {time}", "apron caption").format(
				{"time": GameCalendar.clock_text(at, flights.epoch)}
			)
		)
	if placement.get("warning", false):
		lines.append(
			tr("Long walk to the plane: {meters} m", "apron caption").format(
				{"meters": roundi(placement["longest_walk_m"])}
			)
		)
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
	# A sill lies on a cell edge, so one on the grid's east or south edge is on
	# the site: the frame is closed, which Rect2.has_point (end excluded) is not.
	var frame := on_site.grid_rect()
	var sill := Vector2(stand["x"], stand["wall_z"])
	var inside := sill.clamp(frame.position, frame.end) == sill
	if int(stand["exit"]) < 0 or not inside:
		return {"error": "the live stand lies outside the site"}
	return {"stand": stand}


## Why saved gate stands `stands` do not belong to the gates in `bindings`
## (GateDesks) on `on_grid` with side spurs `lanes` (side -> x, GateDesks.
## spur_x), or "": every gate needs its own stand, straight out from its exit
## on its side's spur, and there is no other.
static func stands_problem(
	stands: Dictionary, bindings: Array[Dictionary], on_grid: BuildGrid, lanes := {}
) -> String:
	var regular: Array[Dictionary] = []
	for binding in bindings:
		if not GateDesks.is_bus_binding(binding):
			regular.append(binding)
	if stands.size() != regular.size():
		return "there are %d gates but %d stands" % [regular.size(), stands.size()]
	for binding in regular:
		var saved: Dictionary = stands.get(binding["gate"], {})
		if not same_stand(saved, SideSpurs.stand_for_exit(on_grid, binding["exit"], lanes)):
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
		var problem := stands_problem(loaded["stands"], gates.bindings, grid, gates.spur_x)
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
	if (
		grid != null
		and grid.route_version() == _last_route_ver
		and grid.enclosure_version() == _last_enclosure_ver
	):
		return
	refresh()


func _on_state_changed(_id: String, state: int) -> void:
	if state == FlightSim.State.TAKEOFF:
		try_release()
