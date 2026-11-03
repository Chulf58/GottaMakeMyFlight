class_name StationUseCells
extends RefCounted
## The cells a station being placed will use, and the floor tiles and arrow
## the build ghost draws for them (decision station-build-ghost-shows-
## passenger-side-staff-spot-and-arrow): the passenger side in yellow, the
## staff spot in teal, a navy arrow for the way passengers walk, and a red
## tile under the colour for a cell that is blocked.
##
## The cells come from the code the sim reads them from, never from a copy:
## BuildObjectDef.interaction_cell() for the passenger cell of any piece with
## a use side, StaffSpots.cell_of() for a check-in desk's or scanner's staff
## spot, and SecurityLanes.geometry() for a lane (the arch shows its queue
## entry and unpack cell and both officer spots; a tray table, X-ray belt or
## pickup table shows the walk cell it serves, and the X-ray belt the primary
## officer spot). A lane part takes the mirror of an arch already standing
## where the part belongs; an arch takes the mirror with more parts already on
## their cells; either way RIGHT, the recogniser's first try, on a tie or with
## nothing placed.
##
## A gate desk has no cell the sim uses: passengers wait near its footprint
## (GateReach) and no staff work it. Its tiles are the row in front of it
## (BuildObjectDef's front, +y at facing 0), with no staff tile.
##
## Not shown: a shop counter's server spot (ShopCounters), which is chosen
## from the room it stands in once it is placed. A cell is blocked when it is
## off the floor or under an object (a walk-through scanner aside, for a
## passenger), or when the placement check refuses for that kind of cell
## (INTERACTION_BLOCKED or INTERACTION_RESERVED for the passenger cell,
## STAFF_SPOT for every staff tile).

## Colours from the HUD palette (decision hud-look-warm-cozy-cream-cards-with-
## a-dark-outline-toon-pale: sunny yellow attention, teal normal, coral red
## problems, dark navy outline). The passenger yellow is BuildMode's existing
## interaction-cell marker (BuildMode.MARKER_TINT), and the red its refusal tint.
const PASSENGER_TINT := Color(1.0, 0.85, 0.3, 0.7)
const STAFF_TINT := Color(0.18, 0.72, 0.68, 0.75)
const BLOCKED_TINT := Color(0.95, 0.3, 0.25, 0.8)
const ARROW_TINT := Color(0.12, 0.16, 0.3)
const PASSENGER := "UsePassenger"
const STAFF := "UseStaff"
const ARROW := "UseArrow"
## The share of a blocked tile its role colour keeps, in the middle.
const BLOCKED_INSET := 0.5

static var _materials := {}
static var _arrow_mesh: ArrayMesh


## The use cells of a `def_id` placed at `anchor` and `facing` on `grid`:
## {"passenger": cells, "staff": cells, "arrow": the passenger cells the arrow
## is centred over, "flow": the grid step passengers walk in}. Every list is
## empty for a piece with no use side.
static func of(grid: BuildGrid, def_id: StringName, anchor: Vector2i, facing: int) -> Dictionary:
	var passenger: Array[Vector2i] = []
	var staff_cells: Array[Vector2i] = []
	var arrow: Array[Vector2i] = []
	var out := {"passenger": passenger, "staff": staff_cells, "arrow": arrow, "flow": Vector2i.ZERO}
	var def := BuildCatalog.get_def(def_id)
	if def == null:
		return out
	if SecurityLanes.is_part(def_id):
		_lane_cells(grid, def_id, anchor, facing, out)
	elif def_id == GateDesks.DESK:
		var front := BuildObjectDef.rotate_offset(Vector2i(0, 1), facing)
		for cell in def.footprint(anchor, facing):
			if not def.footprint(anchor, facing).has(cell + front):
				out["passenger"].append(cell + front)
		out["arrow"].assign(out["passenger"])
		out["flow"] = -front
	elif def.has_interaction:
		var spot := def.interaction_cell(anchor, facing)
		out["passenger"].append(spot)
		out["arrow"].append(spot)
		for cell in def.footprint(anchor, facing):
			if absi(cell.x - spot.x) + absi(cell.y - spot.y) == 1:
				out["flow"] = cell - spot
				break
	var staff := StaffSpots.cell_of(def_id, anchor, facing)
	if staff != BuildObjectDef.NO_CELL:
		out["staff"].append(staff)
	return out


## Whether the `role` (PASSENGER or STAFF) tile on `cell` is blocked, given
## the placement check's `result` (null when there is none).
static func blocked(grid: BuildGrid, cell: Vector2i, role: String, result: BuildResult) -> bool:
	if not grid.in_bounds(cell) or grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
		return true
	var reason := BuildResult.Reason.NONE if result == null or result.ok else result.reason
	if role == STAFF:
		return grid.object_at(cell) != 0 or reason == BuildResult.Reason.STAFF_SPOT
	if not grid.is_walkable(cell):
		return true
	var interaction := [
		BuildResult.Reason.INTERACTION_BLOCKED, BuildResult.Reason.INTERACTION_RESERVED
	]
	return interaction.has(reason)


## Adds the tiles and arrow for a `def_id` ghosted at `anchor` and `facing` to
## `parent`. Each tile is named PASSENGER or STAFF and carries the metas
## "role" (the same), "cell" and "blocked"; the arrow is named ARROW and
## carries "role" and "flow". Names can gain a suffix beside a freed ghost.
static func draw(
	parent: Node3D,
	grid: BuildGrid,
	def_id: StringName,
	anchor: Vector2i,
	facing: int,
	result: BuildResult
) -> void:
	var cells := of(grid, def_id, anchor, facing)
	for role in [PASSENGER, STAFF]:
		var key := "passenger" if role == PASSENGER else "staff"
		for cell: Vector2i in cells[key]:
			if cell == BuildObjectDef.NO_CELL:
				continue
			var stopped := blocked(grid, cell, role, result)
			var tile := _tile(role, stopped)
			tile.position = grid.cell_to_world(cell) + Vector3(0.0, 0.06, 0.0)
			tile.name = role
			tile.set_meta("role", role)
			tile.set_meta("cell", cell)
			tile.set_meta("blocked", stopped)
			parent.add_child(tile)
	var over: Array[Vector2i] = cells["arrow"]
	if over.is_empty() or cells["flow"] == Vector2i.ZERO:
		return
	var centre := Vector3.ZERO
	for cell in over:
		centre += grid.cell_to_world(cell)
	var flow: Vector2i = cells["flow"]
	var arrow := MeshInstance3D.new()
	arrow.name = ARROW
	arrow.mesh = _arrow()
	arrow.material_override = _material(ARROW_TINT)
	arrow.position = centre / over.size() + Vector3(0.0, 0.115, 0.0)
	arrow.rotation.y = atan2(-float(flow.x), -float(flow.y))
	arrow.set_meta("role", ARROW)
	arrow.set_meta("flow", flow)
	parent.add_child(arrow)


## The lane cells for a lane part ghosted at `anchor` and `facing`.
static func _lane_cells(
	grid: BuildGrid, def_id: StringName, anchor: Vector2i, facing: int, out: Dictionary
) -> void:
	var lane := _lane_for(grid, def_id, anchor, facing)
	out["flow"] = -(lane["front"] as Vector2i)
	if def_id == SecurityLanes.ARCH:
		out["passenger"].append_array([lane["queue_entry"], lane["unpack"]])
		out["arrow"].append(lane["unpack"])
		out["staff"].append_array([lane["primary_spot"], lane["helper_spot"]])
		return
	for entry in SecurityLanes.SIDE_PARTS:
		if entry[0] == def_id:
			out["passenger"].append(lane[entry[2]])
			out["arrow"].append(lane[entry[2]])
	if def_id == SecurityLanes.XRAY_BELT:
		out["staff"].append(lane["primary_spot"])


## The SecurityLanes.geometry() a piece at `anchor` would join: for a side
## part, the lane of a standing arch with its facing at the arch cell either
## mirror puts it; for the arch, the mirror with more parts already standing
## on their cells with its facing. RIGHT first on a tie.
static func _lane_for(
	grid: BuildGrid, def_id: StringName, anchor: Vector2i, facing: int
) -> Dictionary:
	if def_id != SecurityLanes.ARCH:
		for mirror in SecurityLanes.MIRRORS:
			var offset: Vector2i = SecurityLanes.FRAME[def_id]
			var arch := (
				anchor - BuildObjectDef.rotate_offset(Vector2i(offset.x * mirror, offset.y), facing)
			)
			if _stands(grid, SecurityLanes.ARCH, arch, facing):
				return SecurityLanes.geometry(arch, facing, mirror)
		var right: Vector2i = SecurityLanes.FRAME[def_id]
		var root := anchor - BuildObjectDef.rotate_offset(right, facing)
		return SecurityLanes.geometry(root, facing, SecurityLanes.RIGHT)
	var best := {}
	var best_count := -1
	for mirror in SecurityLanes.MIRRORS:
		var lane := SecurityLanes.geometry(anchor, facing, mirror)
		var count := 0
		for part in SecurityLanes.PART_IDS:
			if part != SecurityLanes.ARCH and _stands(grid, part, lane[part], facing):
				count += 1
		if count > best_count:
			best = lane
			best_count = count
	return best


## Whether an object of `def_id` with `facing` stands anchored on `cell`.
static func _stands(grid: BuildGrid, def_id: StringName, cell: Vector2i, facing: int) -> bool:
	var record := grid.get_object(grid.object_at(cell))
	return (
		not record.is_empty()
		and StringName(record["def"]) == def_id
		and record["anchor"] == cell
		and record["facing"] == facing
	)


static func _tile(role: String, stopped: bool) -> MeshInstance3D:
	var tint := PASSENGER_TINT if role == PASSENGER else STAFF_TINT
	var tile := _box(0.96, BLOCKED_TINT if stopped else tint)
	if stopped:
		var inset := _box(0.96 * BLOCKED_INSET, tint)
		inset.position.y = 0.01
		tile.add_child(inset)
	return tile


static func _box(width: float, tint: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.08, width)
	var box := MeshInstance3D.new()
	box.mesh = mesh
	box.material_override = _material(tint)
	return box


static func _material(tint: Color) -> StandardMaterial3D:
	if not _materials.has(tint):
		var material := StandardMaterial3D.new()
		material.albedo_color = tint
		if tint.a < 1.0:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[tint] = material
	return _materials[tint]


## A flat arrow 0.7 m long pointing along -z, its middle on the origin.
static func _arrow() -> ArrayMesh:
	if _arrow_mesh != null:
		return _arrow_mesh
	var shaft := 0.09
	var head := 0.26
	var outline: Array[Vector2] = [
		Vector2(0.0, -0.35),
		Vector2(head, -0.05),
		Vector2(shaft, -0.05),
		Vector2(shaft, 0.35),
		Vector2(-shaft, 0.35),
		Vector2(-shaft, -0.05),
		Vector2(-head, -0.05),
	]
	var triangles := [[0, 1, 6], [2, 3, 4], [2, 4, 5]]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for triangle in triangles:
		for i: int in triangle:
			tool.add_vertex(Vector3(outline[i].x, 0.0, outline[i].y))
	_arrow_mesh = tool.commit()
	return _arrow_mesh
