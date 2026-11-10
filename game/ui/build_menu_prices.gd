class_name BuildMenuPrices
extends RefCounted
## What the build menu's cards and cost line say things cost (split out of
## BuildMenu, which keeps preview_text() and _card_price() as one-line delegates
## of these). Static only: each function takes the menu and reads the wallet and
## BuildMode through it.


## What a card's price slot shows: tool_price(), or for Buy land the price of
## the next plot (LandPlots.next_price()), which rises with each plot bought.
static func card_price(menu: BuildMenu, tool: BuildMode.Tool) -> int:
	var land: LandPlots = null
	if menu.build_mode != null and menu.build_mode.land_tool != null:
		land = menu.build_mode.land_tool.land
	if tool == BuildMode.Tool.BUY_LAND and land != null:
		return land.next_price()
	return BuildMenuCatalog.tool_price(tool)


## What the current tool would cost now, as "Cost 400" and, when the wallet is
## short, "Cost 400   Short by 300"; "" when nothing costs money, there is no
## wallet or the pointer is not over a cell of the grid (no hover yet, over the
## HUD, or over ground outside the grid). The cost is the net of the plan
## BuildMode would apply under the pointer (a door over a paid wall also
## refunds the wall, so it is cheaper than its card), or for a dragged Floor
## rectangle the unfloored tiles the rules accept, as AreaDrag.fill_floor()
## charges.
static func preview_text(menu: BuildMenu) -> String:
	if menu._wallet == null or menu.build_mode == null:
		return ""
	var price := preview_price(menu)
	if price.x <= 0:
		return ""
	var text := "Cost %d" % price.x
	if price.y > menu._wallet.balance:
		text += "   Short by %d" % (price.y - menu._wallet.balance)
	return text


## (what the placement costs net of refunds, what the wallet must hold for it).
## A door over a paid wall costs its price less the wall's refund, but the
## wallet must still hold the full door price (BuildTransaction.needed).
static func preview_price(menu: BuildMenu) -> Vector2i:
	var mode := menu.build_mode
	if mode.room_mover.active or mode.templates.armed >= 0:
		return held_price(menu)
	var area := mode.dragged_area()
	if mode.tool == BuildMode.Tool.FLOOR and area.has_area():
		var rect_cost := floor_rect_cost(menu, area)
		return Vector2i(rect_cost, rect_cost)
	if mode.tool == BuildMode.Tool.BELT:
		# Only the cells with no belt yet are bought; reshaping is free.
		var line_cost := mode.belt_cells_to_buy() * BuildMenuCatalog.tool_price(BuildMode.Tool.BELT)
		return Vector2i(line_cost, line_cost)
	if mode.tool in BuildMode.LANDSIDE_BUILD_TOOLS or mode.tool == BuildMode.Tool.BUY_LAND:
		return off_grid_price(menu)
	var edit := mode.hover_edit()
	if edit == null or not menu._pointer_on_grid():
		return Vector2i.ZERO
	var plan := DoorPlacement.edits_for(mode.grid, edit)
	var net := 0
	for step in plan:
		net += BuildTransaction.quote(mode.grid, step).net()
	if net > 0 and edit.kind == BuildEdit.Kind.REMOVE_OBJECT and _removal_refused(mode, edit):
		return Vector2i.ZERO
	return Vector2i(maxi(0, net), maxi(0, BuildTransaction.needed(mode.grid, plan)))


## Whether the removal `edit` is refused for a reason of its own (a gate with a
## flight due), so nothing would be paid and the status line says why. A wallet
## too short for the wall a door removal leaves behind is not one: that keeps its
## cost and shortfall.
static func _removal_refused(mode: BuildMode, edit: BuildEdit) -> bool:
	var result := mode.check(edit)
	return not result.ok and result.reason != BuildResult.Reason.CANT_AFFORD


## The price of the room in hand (RoomMoveTool) or of the armed template paste.
static func held_price(menu: BuildMenu) -> Vector2i:
	if menu.build_mode.room_mover.active:
		return menu.build_mode.room_mover.preview_price()
	return menu.build_mode.templates.preview_price()


## The landside build's or the land plot's price under the pointer, for the
## tools that do not edit the grid.
static func off_grid_price(menu: BuildMenu) -> Vector2i:
	var mode := menu.build_mode
	if mode.tool != BuildMode.Tool.BUY_LAND:
		return mode.landside_preview_price()
	if mode.land_tool == null or mode.land_tool.land == null:
		return Vector2i.ZERO
	return mode.land_tool.preview_price()


## A rectangle is priced once per rectangle and balance, not every frame.
static func floor_rect_cost(menu: BuildMenu, area: Rect2i) -> int:
	var key := "%s:%d" % [area, menu._wallet.balance]
	if key != menu._rect_cost_key:
		menu._rect_cost_key = key
		menu._rect_cost = menu._price_floor_rect(area)
	return menu._rect_cost
