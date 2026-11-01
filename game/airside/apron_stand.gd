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

var live: Dictionary = {}
var wanted: Dictionary = {}
## The last StandPlacement.place() result.
var placement: Dictionary = {}
## The tick the live stand last took the wanted one, or -1.
var last_release_tick := -1
var grid: BuildGrid
var site: SiteDefinition

var _guard_key: Array = []
var _guard_cells: Dictionary = {}
var _label: Label3D
## Holds the guarded-area meshes; shown only while build mode lasts.
var _guard_view := Node3D.new()
var _areas: Array[MeshInstance3D] = []


func _init() -> void:
	_guard_view.name = "GuardView"
	_guard_view.visible = false
	add_child(_guard_view)


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
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = AREA_TINT
	for i in 2:
		var area := MeshInstance3D.new()
		area.name = "GuardedArea%d" % i
		var mesh := PlaneMesh.new()
		mesh.material = material
		area.mesh = mesh
		area.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		area.visible = false
		_guard_view.add_child(area)
		_areas.append(area)
	if menu != null:
		watch(menu.build_session)
	if build_mode == null or flights == null or build_mode.site == null:
		return
	bind(build_mode.grid, build_mode.site, flights)
	if build_mode.grid is SiteGrid:
		(build_mode.grid as SiteGrid).guard = edit_problem
	_apply_live()


func _process(_delta: float) -> void:
	if grid == null:
		return
	var rects := guard_rects()
	for i in _areas.size():
		_areas[i].visible = i < rects.size()
		if i < rects.size():
			var rect := rects[i]
			(_areas[i].mesh as PlaneMesh).size = rect.size
			_areas[i].position = Vector3(rect.get_center().x, AREA_LIFT_M, rect.get_center().y)
	var text := status_text()
	_label.text = text
	_label.visible = text != ""
	_label.position = StandPlacement.stand_point(live) + Vector3.UP * STATUS_HEIGHT_M


## Starts on the starter stand and follows the grid and the flights.
func bind(on_grid: BuildGrid, on_site: SiteDefinition, on_flights: FlightSim) -> void:
	grid = on_grid
	site = on_site
	flights = on_flights
	live = StandPlacement.starter_stand(grid, site)
	grid.graph_changed.connect(_on_graph_changed)
	flights.state_changed.connect(_on_state_changed)
	refresh()


## Shows the guarded area while `session` lasts, and hides it outside it.
func watch(session: BuildSession) -> void:
	if not session.changed.is_connected(set_building):
		session.changed.connect(set_building)
	set_building(session.active)


func set_building(on: bool) -> void:
	_guard_view.visible = on


## Works the wanted stand out again and lets the live one take it if it may.
func refresh() -> void:
	placement = StandPlacement.place(grid, site, live)
	wanted = placement["stand"]
	try_release()


## The flight between TAXI_IN and TAKEOFF at the stand, or "".
func busy_flight() -> String:
	for id in flights.flight_ids():
		var state := flights.state_of(id)
		if state >= FlightSim.State.TAXI_IN and state < FlightSim.State.TAKEOFF:
			return id
	return ""


## The live stand takes the wanted one when they differ and no flight is
## turning round. True when it moved.
func try_release() -> bool:
	if same_stand(wanted, live) or busy_flight() != "":
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
	var id := busy_flight()
	if id == "":
		return [] as Array[Rect2]
	if flights.state_of(id) < FlightSim.State.TAXI_OUT:
		return StandPlacement.swept_rects(live)
	var path := (
		airside.phase_path(FlightSim.State.TAXI_OUT)
		if airside != null
		else PackedVector3Array([StandPlacement.pushback_end(live), StandPlacement.lane_join(live)])
	)
	var t := smoothstep(0.0, 1.0, flights.phase_progress(id, flights.tick))
	var at := FlightPose.point_at(path, FlightPose.path_length(path) * t)
	return StandPlacement.swept_rects(live, at.z + StandPlacement.TAIL_M)


## The grid cells guard_rects() covers, as a set, worked out once per tick.
func guarded_cells() -> Dictionary:
	var key := [flights.tick, busy_flight(), live["x"], live["wall_z"]]
	if key != _guard_key:
		_guard_key = key
		_guard_cells = StandPlacement.cells_under(grid, guard_rects())
	return _guard_cells


## The guard of the site's grid (SiteGrid): a PLANE_AREA refusal for an
## edit that builds on a guarded cell, else null. Removals pass.
func edit_problem(_on_grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	if REMOVALS.has(edit.kind):
		return null
	var cells := guarded_cells()
	if cells.is_empty():
		return null
	for cell in _cells_of(edit):
		if cells.has(cell):
			return BuildResult.refused(BuildResult.Reason.PLANE_AREA)
	return null


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


func to_snapshot() -> Dictionary:
	return {"live": live.duplicate()}


## The live stand a to_snapshot() dictionary holds, as {"live": stand}, or
## {"error": why} when it is malformed or its door and wall line lie outside
## `on_site`'s grid.
static func checked(data: Dictionary, on_site: SiteDefinition) -> Dictionary:
	var saved: Variant = data.get("live")
	if not StandPlacement.is_stand(saved) or not WholeNumber.is_whole(saved["exit"]):
		return {"error": "'live' is not a stand"}
	var stand := StandPlacement.make(int(saved["exit"]), float(saved["x"]), float(saved["wall_z"]))
	var low := Vector2(on_site.grid_origin.x, on_site.grid_origin.z)
	var frame := Rect2(low, Vector2(on_site.grid_size))
	if int(stand["exit"]) < 0 or not frame.has_point(Vector2(stand["x"], stand["wall_z"])):
		return {"error": "the live stand lies outside the site"}
	return {"live": stand}


## Loads the live stand (checked()) and works out the wanted one from the
## grid. False (with an error) for a refused save.
func from_snapshot(data: Dictionary) -> bool:
	if site == null:
		push_error("ApronStand.from_snapshot: no site is bound")
		return false
	var loaded := checked(data, site)
	if loaded.has("error"):
		push_error("ApronStand.from_snapshot: %s" % loaded["error"])
		return false
	live = loaded["live"]
	_apply_live()
	refresh()
	return true


func _apply_live() -> void:
	if airside != null:
		airside.set_stand(live)
	if passengers != null and passengers.grid != null:
		passengers.set_stand(live)
	live_changed.emit(live)


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
