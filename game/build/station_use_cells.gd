class_name StationUseCells
extends RefCounted
## The cells a station being placed will use, and the floor tiles and arrow
## the build ghost draws for them (decision station-build-ghost-shows-
## passenger-side-staff-spot-and-arrow): the passenger side in yellow, the
## staff spot in teal, a navy arrow for the way passengers walk, and a red
## tile under the colour for a cell that is blocked.
##
## Cells and their state come from the sim, never from a copy of its rules.
## The piece is written into the grid data for a moment
## (BuildGrid.with_trial_object, the write staff reach already uses) and the
## sim is asked about it there:
## - Any piece with a use side: its passenger cell is
##   BuildObjectDef.interaction_cell, blocked when BuildGrid.interaction_problem
##   (the placement check's own rule) refuses it on the grid as it stands.
## - A check-in desk or scanner: its staff spot is StaffSpots.spot_of, blocked
##   when StaffSpots.blocked says staff could never work it.
## - A lane piece: SecurityLanes.rebuild on the trial grid picks the lane it
##   joins (the arch's own candidate, or the first arch, in id order, whose
##   candidate takes the part), so the side, mirror and facing are the
##   recogniser's. The arch shows its queue entry and unpack cell and both
##   officer spots; a tray table, X-ray belt or pickup table the cell it serves,
##   the X-ray belt also the primary officer spot. Each cell's state is
##   SecurityLanes.use_cell_states. A part no arch would take shows nothing.
##
## A gate desk shows only a small arrow on the floor in front of it, pointing
## in (user-ruled 2026-11-04, decision gate-desk-build-ghost-shows-a-front-
## arrow-only): passengers wait near it and no staff work it. Not shown: a
## shop counter's server spot (ShopCounters), chosen from its room once placed,
## and the tiles of a piece standing where the ghost is (a Remove ghost).

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
static var _see_through := {}
static var _arrow_mesh: ArrayMesh


## The use cells of a `def_id` placed at `anchor` and `facing` on `grid`:
## {"passenger": cells, "staff": cells, "blocked": cell -> true, "arrow": the
## cells the arrow is centred over, "flow": the grid step passengers walk in}.
## Every list is empty for a piece with no use side.
static func of(grid: BuildGrid, def_id: StringName, anchor: Vector2i, facing: int) -> Dictionary:
	var passenger: Array[Vector2i] = []
	var staff: Array[Vector2i] = []
	var arrow: Array[Vector2i] = []
	var out := {
		"passenger": passenger, "staff": staff, "blocked": {}, "arrow": arrow, "flow": Vector2i.ZERO
	}
	var def := BuildCatalog.get_def(def_id)
	if def == null or _stands(grid, def_id, anchor, facing):
		return out
	var footprint := def.footprint(anchor, facing)
	if def_id == GateDesks.DESK:
		var front := BuildObjectDef.rotate_offset(Vector2i(0, 1), facing)
		for cell in footprint:
			if not footprint.has(cell + front):
				arrow.append(cell + front)
		out["flow"] = -front
		return out
	var spot := def.interaction_cell(anchor, facing)
	if spot != BuildObjectDef.NO_CELL and grid.interaction_problem(spot, footprint) != null:
		out["blocked"][spot] = true
	grid.with_trial_object(def_id, anchor, facing, _ask_sim.bind(grid, def, out))
	return out


## Fills `out` for the piece written into `grid` as `id`.
static func _ask_sim(id: int, grid: BuildGrid, def: BuildObjectDef, out: Dictionary) -> void:
	var record := grid.get_object(id)
	if SecurityLanes.is_part(def.id):
		_lane_cells(grid, def.id, id, out)
		return
	if def.has_interaction:
		var spot := def.interaction_cell(record["anchor"], record["facing"])
		out["passenger"].append(spot)
		out["arrow"].append(spot)
		for cell in def.footprint(record["anchor"], record["facing"]):
			if absi(cell.x - spot.x) + absi(cell.y - spot.y) == 1:
				out["flow"] = cell - spot
				break
	var staff := StaffSpots.spot_of(grid, id)
	if staff != BuildObjectDef.NO_CELL:
		out["staff"].append(staff)
		if StaffSpots.blocked(grid, id):
			out["blocked"][staff] = true


## The lane cells of the lane piece `id` on the trial grid.
static func _lane_cells(grid: BuildGrid, def_id: StringName, id: int, out: Dictionary) -> void:
	var lanes := SecurityLanes.new()
	lanes.rebuild(grid)
	var arch := id if def_id == SecurityLanes.ARCH else 0
	for each in lanes.arches:
		if arch == 0 and (lanes.candidate(each)["parts"] as Dictionary).values().has(id):
			arch = each
	if arch == 0:
		return
	var lane := lanes.candidate(arch)
	out["flow"] = -(lane["front"] as Vector2i)
	if def_id == SecurityLanes.ARCH:
		out["passenger"].append_array([lane["queue_entry"], lane["unpack"]])
		out["arrow"].append(lane["unpack"])
		out["staff"].append_array([lane["primary_spot"], lane["helper_spot"]])
	else:
		for entry in SecurityLanes.SIDE_PARTS:
			if entry[0] == def_id:
				out["passenger"].append(lane[entry[2]])
				out["arrow"].append(lane[entry[2]])
		if def_id == SecurityLanes.XRAY_BELT:
			out["staff"].append(lane["primary_spot"])
	var states := lanes.use_cell_states(grid, arch)
	for cell in out["passenger"] + out["staff"]:
		if not states.get(cell, true):
			out["blocked"][cell] = true


## Adds the tiles and arrow for a `def_id` ghosted at `anchor` and `facing` to
## `parent`. Each tile is named PASSENGER or STAFF and carries the metas
## "role" (the same), "cell" and "blocked"; the arrow is named ARROW and
## carries "role" and "flow". Names can gain a suffix beside a freed ghost. A
## tile on a cell an object stands on (the X-ray belt's arch cell) is drawn
## through that object.
static func draw(
	parent: Node3D, grid: BuildGrid, def_id: StringName, anchor: Vector2i, facing: int
) -> void:
	var cells := of(grid, def_id, anchor, facing)
	for role in [PASSENGER, STAFF]:
		var key := "passenger" if role == PASSENGER else "staff"
		for cell: Vector2i in cells[key]:
			var stopped: bool = cells["blocked"].has(cell)
			var tile := _tile(role, stopped, grid.object_at(cell) != 0)
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
	arrow.material_override = _material(ARROW_TINT, grid.object_at(over[0]) != 0)
	arrow.position = centre / over.size() + Vector3(0.0, 0.115, 0.0)
	arrow.rotation.y = atan2(-float(flow.x), -float(flow.y))
	arrow.set_meta("role", ARROW)
	arrow.set_meta("flow", flow)
	parent.add_child(arrow)


## Whether an object of `def_id` with `facing` stands anchored on `cell`.
static func _stands(grid: BuildGrid, def_id: StringName, cell: Vector2i, facing: int) -> bool:
	var record := grid.get_object(grid.object_at(cell))
	return (
		not record.is_empty()
		and StringName(record["def"]) == def_id
		and record["anchor"] == cell
		and record["facing"] == facing
	)


static func _tile(role: String, stopped: bool, through: bool) -> MeshInstance3D:
	var tint := PASSENGER_TINT if role == PASSENGER else STAFF_TINT
	var tile := _box(0.96, BLOCKED_TINT if stopped else tint, through)
	if stopped:
		var inset := _box(0.96 * BLOCKED_INSET, tint, through)
		inset.position.y = 0.01
		tile.add_child(inset)
	return tile


static func _box(width: float, tint: Color, through: bool) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.08, width)
	var box := MeshInstance3D.new()
	box.mesh = mesh
	box.material_override = _material(tint, through)
	return box


## The tint's material; `through` draws it over what stands in front of it.
static func _material(tint: Color, through := false) -> StandardMaterial3D:
	var cache := _see_through if through else _materials
	if not cache.has(tint):
		var material := StandardMaterial3D.new()
		material.no_depth_test = through
		material.albedo_color = tint
		if tint.a < 1.0:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		cache[tint] = material
	return cache[tint]


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
