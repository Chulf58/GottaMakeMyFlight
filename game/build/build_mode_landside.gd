class_name BuildModeLandside
extends RefCounted
## The landside half of BuildMode: the plan a landside tool makes at a ground
## point, its ghost and status line, and applying it (LandsidePlacement).
## Static helpers over the BuildMode `mode` that owns the tool, the grid and the
## hover state; BuildMode keeps one-line delegates for what the HUD and tests call.


## The landside tools' rules (LandsidePlacement) for the sim, grid and wallet
## `mode` has now.
static func placement(mode: BuildMode) -> LandsidePlacement:
	mode._landside_placement.sim = mode.landside
	mode._landside_placement.grid = mode.grid
	mode._landside_placement.wallet = mode.wallet()
	return mode._landside_placement


## What the current tool would do on the landside at a ground point (picked on
## the y = 0 plane): a curb or car park tool snaps to the nearest free spot of
## its kind or says why not, the Close tool finds the car park under it, and
## Remove, off the grid, finds the built spot under it. Null for any other
## tool or point, and for a spot-less pointer.
static func plan_at(mode: BuildMode, point: Variant) -> LandsidePlacement.Plan:
	if point == null:
		return null
	var landside_rules := placement(mode)
	if BuildMode.LANDSIDE_BUILD_TOOLS.has(mode.tool):
		return landside_rules.plan_build(BuildMode.LANDSIDE_BUILD_TOOLS[mode.tool], point)
	if mode.tool == BuildMode.Tool.LOT_GATE:
		return landside_rules.plan_toggle(point)
	if (
		mode.tool == BuildMode.Tool.REMOVE
		and not mode.grid.in_bounds(mode.grid.world_to_cell(point))
	):
		return landside_rules.plan_remove(point)
	return null


## (cost, money the wallet must hold) of the landside build under the pointer,
## zero for anything else (BuildMenu's cost line).
static func preview_price(mode: BuildMode) -> Vector2i:
	if mode._landside_plan == null or mode._landside_plan.action != LandsidePlacement.Action.BUILD:
		return Vector2i.ZERO
	return Vector2i(mode._landside_plan.price, mode._landside_plan.price)


static func is_landside_tool(mode: BuildMode) -> bool:
	return BuildMode.LANDSIDE_BUILD_TOOLS.has(mode.tool) or mode.tool == BuildMode.Tool.LOT_GATE


## Ghosts and describes a landside plan: the free spots of the tool's kind in
## the marker tint, the spot under the pointer valid or invalid, and its
## capacity, walk and price on the status line.
static func hover(mode: BuildMode, plan: LandsidePlacement.Plan) -> void:
	var key := hover_key(mode, plan)
	if key == mode._hover_key:
		return
	mode._hover_key = key
	mode._status_note = ""
	BuildGhost.clear(mode)
	if plan == null:
		mode._ghost.visible = false
		mode._set_status("")
		return
	var spots: Array[LandsidePlacement.Plan] = []
	if BuildMode.LANDSIDE_BUILD_TOOLS.has(mode.tool):
		spots = placement(mode).free_spot_plans(BuildMode.LANDSIDE_BUILD_TOOLS[mode.tool])
	var valid := (
		mode._area_remove_material if mode.tool == BuildMode.Tool.REMOVE else mode._valid_material
	)
	LandsidePlacement.draw(
		mode._ghost, spots, plan, valid, mode._invalid_material, mode._marker_material
	)
	mode._set_status(plan.text, not plan.result.ok)


## Hover for a landside tool, or Buy land (LandTool draws its own plot ghost).
static func hover_off_grid_tool(mode: BuildMode, point: Variant) -> void:
	if mode.tool != BuildMode.Tool.BUY_LAND:
		mode._pointer_on_grid = point != null
		hover(mode, mode._landside_plan)
		return
	mode._ghost.visible = false
	var text := mode.land_tool.hover(point) if mode.land_tool.land != null else ""
	var refused := mode.land_tool.land != null and mode.land_tool.last_hover_refused()
	mode._set_status(text, refused)


static func hover_key(mode: BuildMode, plan: LandsidePlacement.Plan) -> String:
	return "landside:%d:%s" % [mode.tool, "none" if plan == null else plan.text]


## Applies a landside plan (null when the tool has no landside to build on).
## Landside actions keep their own undo records (LandsidePlacement.apply()).
static func apply(mode: BuildMode, plan: LandsidePlacement.Plan) -> BuildResult:
	var before_bal := mode.wallet().balance if mode.wallet() != null else 0
	var result := placement(mode).apply(plan, mode._history.peek())
	mode._hover_key = ""
	mode._status_note = ""
	if result != null and result.ok and plan != null:
		var after_bal := mode.wallet().balance if mode.wallet() != null else 0
		var net_cost := before_bal - after_bal if mode.wallet() != null else 0
		var kind := &"remove" if plan.action == LandsidePlacement.Action.REMOVE else &"landside"
		mode.emit_player_commit(
			kind, [] as Array[Vector2i], [] as Array[int], net_cost, plan.centre
		)
	if result != null and not result.ok:
		var msg := plan.text if plan != null and plan.text != "" else result.reason_text()
		mode.notify_refusal(msg)
	return result
