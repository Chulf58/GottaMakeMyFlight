class_name RemoteStands
extends RefCounted
## Player-placed apron remote stands ("remote_stand"): 2x2 unfloored pads
## assigned persistent IDs R1, R2, ... on owned BuildGrid cells, connected
## north to TAXI_LANE_Z and dynamically sized by StandEnvelope. Pure helpers.

const STAND_ID := &"remote_stand"
const ID_PREFIX := "R"
const SAVE_KEYS := ["id", "object_id"]


## StandPlacement dictionary for a remote_stand object anchored at `anchor`
## (the 2x2 pad's northwest cell). Places stand_point at the pad centre.
static func stand_for_cell(grid: BuildGrid, anchor: Vector2i) -> Dictionary:
	var centre := grid.origin + Vector3(anchor.x + 1.0, 0.0, anchor.y + 1.0)
	return StandPlacement.make(
		0,
		centre.x + StandPlacement.DOOR_SIDE_M,
		centre.z + StandPlacement.NOSE_GAP_M + StandPlacement.NOSE_M
	)


## Sorted BuildGrid object IDs whose def is STAND_ID.
static func object_ids(grid: BuildGrid) -> Array[int]:
	var out: Array[int] = []
	for id in grid.object_ids():
		if StringName(grid.get_object(id).get("def", &"")) == STAND_ID:
			out.append(id)
	out.sort()
	return out


## Small-plane swing rectangle of `stand` (used for 19 m swing separation).
static func small_swing_rect(stand: Dictionary) -> Rect2:
	var parts := StandEnvelope.rects(stand, PlaneClasses.SMALL)
	return parts[0] if not parts.is_empty() else Rect2()


## All small-plane swing rectangles for placed remote stands on `grid`.
static func all_small_swings(grid: BuildGrid) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for obj_id in object_ids(grid):
		var rec := grid.get_object(obj_id)
		var stand := stand_for_cell(grid, rec["anchor"])
		var swing := small_swing_rect(stand)
		if swing.has_area():
			out.append(swing)
	return out


## Validates a saved "remote_stands" array against `on_grid`. Returns
## {"by_obj": object_id -> id} or {"error": msg}.
static func checked_snapshot(saved: Variant, on_grid: BuildGrid) -> Dictionary:
	if typeof(saved) != TYPE_ARRAY:
		return {"error": "'remote_stands' is not a list"}
	var on_grid_ids := {}
	for obj_id in object_ids(on_grid):
		on_grid_ids[obj_id] = true
	var by_obj := {}
	var used_ids := {}
	for entry: Variant in saved:
		var problem := _entry_problem(entry, on_grid_ids, by_obj, used_ids)
		if problem != "":
			return {"error": problem}
		var obj_id := int(entry["object_id"])
		var sid := str(entry["id"])
		by_obj[obj_id] = sid
		used_ids[sid] = true
	for obj_id: int in on_grid_ids:
		if not by_obj.has(obj_id):
			return {"error": "remote_stand %d has no saved id" % obj_id}
	return {"by_obj": by_obj}


static func _entry_problem(
	entry: Variant, on_grid_ids: Dictionary, by_obj: Dictionary, used_ids: Dictionary
) -> String:
	if typeof(entry) != TYPE_DICTIONARY or entry.size() != SAVE_KEYS.size():
		return "a remote stand entry holds id and object_id"
	if not (entry as Dictionary).has_all(SAVE_KEYS):
		return "a remote stand entry holds id and object_id"
	if not WholeNumber.is_whole(entry["object_id"]):
		return "remote_stand object_id must be a whole number"
	var obj_id := int(entry["object_id"])
	if not on_grid_ids.has(obj_id):
		return "remote_stand %d is not on the grid" % obj_id
	if by_obj.has(obj_id):
		return "remote_stand %d is listed twice" % obj_id
	var sid: Variant = entry["id"]
	if typeof(sid) != TYPE_STRING or not _is_valid_id(str(sid)):
		return "remote stand id '%s' must be R1, R2, ..." % [sid]
	if used_ids.has(str(sid)):
		return "remote stand id '%s' is used twice" % [sid]
	return ""


static func _is_valid_id(sid: String) -> bool:
	if not sid.begins_with(ID_PREFIX) or sid.length() < 2:
		return false
	var num := sid.substr(ID_PREFIX.length())
	return num.is_valid_int() and int(num) >= 1


## Largest PlaneClasses class whose envelope at `stand` is clear on `grid`
## (excluding own `object_id` pad cells), or "" if even SMALL does not fit.
## Land ownership is required only on the 2x2 pad itself (_footprint_problem).
static func max_class(
	grid: BuildGrid, site: SiteDefinition, stand: Dictionary, own_object_id := 0
) -> String:
	for plane_class in StandEnvelope.LARGEST_FIRST:
		if _class_fits(grid, site, stand, plane_class, own_object_id):
			return plane_class
	return ""


## Refusal for placing a new remote_stand at `anchor`, or null when valid.
static func placement_problem(
	grid: BuildGrid,
	site: SiteDefinition,
	land: LandPlots,
	anchor: Vector2i,
	existing_swings: Array[Rect2],
	bus_bays: Array[Rect2]
) -> BuildResult:
	var fp := _footprint_problem(grid, land, anchor)
	if fp != null:
		return fp
	var stand := stand_for_cell(grid, anchor)
	if not StandPlacement.reaches_lane(stand):
		return BuildResult.refused(BuildResult.Reason.REMOTE_STAND_NO_ROOM)
	var small := StandEnvelope.rects(stand, PlaneClasses.SMALL)
	var clears := StandEnvelope.clears_lane(stand, PlaneClasses.SMALL)
	if StandPlacement.reaches_road(grid, small) or not clears:
		return BuildResult.refused(BuildResult.Reason.REMOTE_STAND_NO_ROOM)
	var swing := small_swing_rect(stand)
	if _overlaps_any(swing, existing_swings) or _overlaps_any(swing, bus_bays):
		return BuildResult.refused(BuildResult.Reason.REMOTE_STAND_OVERLAP)
	var fitted := max_class(grid, site, stand, 0)
	if fitted == "":
		return BuildResult.refused(BuildResult.Reason.REMOTE_STAND_NO_ROOM)
	return null


static func _footprint_problem(grid: BuildGrid, land: LandPlots, anchor: Vector2i) -> BuildResult:
	for dy in 2:
		for dx in 2:
			var cell := anchor + Vector2i(dx, dy)
			if not grid.in_bounds(cell):
				return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
			if grid.floor_at(cell) != BuildGrid.FLOOR_NONE:
				return BuildResult.refused(BuildResult.Reason.REMOTE_STAND_NEEDS_APRON)
			if land != null and not land.owns_cell(cell):
				return BuildResult.refused(BuildResult.Reason.LAND_NOT_OWNED)
	return null


## Assigns persistent IDs R1, R2, ... for every remote_stand object in `grid`,
## preserving existing IDs from `existing` first before checking external IDs.
static func assign_ids(
	grid: BuildGrid, existing: Dictionary, used_external_ids: Array[String] = []
) -> Dictionary:
	var out := {}
	var taken := {}
	var ids := object_ids(grid)
	for obj_id in ids:
		if existing.has(obj_id):
			var sid := String(existing[obj_id].get("id", ""))
			if sid != "" and not taken.has(sid):
				out[obj_id] = sid
				taken[sid] = true
	for ext in used_external_ids:
		taken[ext] = true
	for obj_id in ids:
		if not out.has(obj_id):
			var sid := _next_id(taken)
			out[obj_id] = sid
			taken[sid] = true
	return out


## Next free ID "R1", "R2", ... not in `taken`.
static func _next_id(taken: Dictionary) -> String:
	var n := 1
	while taken.has(ID_PREFIX + str(n)):
		n += 1
	return ID_PREFIX + str(n)


static func _class_fits(
	grid: BuildGrid,
	site: SiteDefinition,
	stand: Dictionary,
	plane_class: String,
	own_object_id: int
) -> bool:
	var parts := StandEnvelope.rects(stand, plane_class)
	if StandPlacement.reaches_road(grid, parts):
		return false
	if not StandEnvelope.clears_lane(stand, plane_class):
		return false
	if not StandPlacement.reaches_lane(stand):
		return false
	for rect in parts:
		if not _rect_clear_for_stand(grid, site, rect, own_object_id):
			return false
	return true


static func _rect_clear_for_stand(
	grid: BuildGrid, site: SiteDefinition, rect: Rect2, own_object_id: int
) -> bool:
	var span := StandPlacement._span_under(grid, rect)
	for y in range(span.position.y, span.end.y):
		for x in range(span.position.x, span.end.x):
			if not _cell_clear_for_stand(grid, site, Vector2i(x, y), own_object_id):
				return false
	return true


static func _cell_clear_for_stand(
	grid: BuildGrid, site: SiteDefinition, cell: Vector2i, own_object_id: int
) -> bool:
	if grid.floor_at(cell) != BuildGrid.FLOOR_NONE:
		return false
	var obj := grid.object_at(cell)
	if obj != 0 and obj != own_object_id:
		return false
	if site != null and site.is_obstacle(cell):
		return false
	for wall_side in 4:
		if grid.has_wall(cell, wall_side):
			return false
	return true


static func _overlaps_any(rect: Rect2, others: Array[Rect2]) -> bool:
	var shrunk := rect.grow(-0.01)
	for other in others:
		if shrunk.intersects(other):
			return true
	return false
