class_name LandTool
extends Node3D
## The Buy land tool of build mode (user ruling land-plots-are-bought-with-a-
## buy-land-tool-in-build-mode-buy: "While it is picked, plots the player can
## buy (touching owned land) show a dim fill, and the owned-land outline from
## decision 8ece9cc0 marks the edge. Hovering a buyable plot shows its price,
## and one click buys it, through the same money rules as building."). It owns
## the site's LandPlots: bind() makes them with a new game's land
## (LandPlots.own_start()) and gives them to the site's grid, which then
## refuses building on land the player does not own.
##
## While BuildMode's tool is BUY_LAND every buyable plot gets a dim teal fill
## (the outline's teal, BuildableOutline.COLOR), and the plot under the pointer
## is tinted like a build ghost, green when one click buys it and red when
## that would be refused, with its price floating over it. Prison Architect
## sells land by clicking a neighbouring parcel and Two Point Hospital shows
## each plot's price on the plot itself (decision land-plots-are-uniform-
## square-plots-of-about-25x25-m-bought, rationale); here the price shows on
## the hovered plot, and on BuildMenu's cost line (preview_price()).

## The fill over a plot the player may buy: the outline's teal, faint.
const FILL_COLOR := Color(0.2, 0.86, 0.86, 0.18)
## The fills lie this far over the grid's floor height, under the outline.
const LIFT_M := 0.03
## The hovered plot's tint lies just over the fills.
const HOVER_LIFT_M := 0.035
## The price floats this high over the hovered plot's middle.
const LABEL_HEIGHT_M := 2.0
const LABEL_FONT_SIZE := 64
const LABEL_PIXEL_SIZE := 0.0016
const NO_PLOT := Vector2i(-1, -1)

var land: LandPlots
var mode: BuildMode

var _fills := MeshInstance3D.new()
var _hover := MeshInstance3D.new()
var _price := Label3D.new()
var _fill_material := StandardMaterial3D.new()
var _valid_material := StandardMaterial3D.new()
var _invalid_material := StandardMaterial3D.new()
var _hovered := NO_PLOT
var _hover_text := ""


func _init() -> void:
	name = "LandTool"
	visible = false
	for pair in [
		[_fill_material, FILL_COLOR],
		[_valid_material, BuildMode.VALID_TINT],
		[_invalid_material, BuildMode.INVALID_TINT],
	]:
		var material: StandardMaterial3D = pair[0]
		material.albedo_color = pair[1]
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fills.name = "BuyableFills"
	_fills.material_override = _fill_material
	_hover.name = "HoverPlot"
	_price.name = "PlotPrice"
	_price.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_price.fixed_size = true
	_price.pixel_size = LABEL_PIXEL_SIZE
	_price.font_size = LABEL_FONT_SIZE
	_price.outline_size = 16
	_price.no_depth_test = true
	_price.visible = false
	for node: GeometryInstance3D in [_fills, _hover, _price]:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)


## A LandTool made a child of `build_mode`; with a site it binds the land
## (bind()), without one its land stays null and it draws nothing.
static func attach(build_mode: BuildMode) -> LandTool:
	var tool := LandTool.new()
	tool.mode = build_mode
	build_mode.add_child(tool)
	if build_mode.site != null:
		tool.bind(build_mode)
	return tool


## Makes `build_mode`'s land on its site, owning a new game's start, and hands
## it to the site's grid.
func bind(build_mode: BuildMode) -> void:
	mode = build_mode
	land = LandPlots.for_site(build_mode.site)
	land.own_start(build_mode.site)
	(build_mode.grid as SiteGrid).land = land
	land.changed.connect(_on_land_changed)
	build_mode.tool_changed.connect(_on_tool_changed)
	if build_mode.wallet() != null:
		build_mode.wallet().changed.connect(_on_balance_changed)
	_draw_fills()


## The plot under a ground point, or NO_PLOT off the site.
func plot_at(point: Variant) -> Vector2i:
	if point == null:
		return NO_PLOT
	var plot := land.plot_of(mode.grid.world_to_cell(point))
	return plot if land.in_site(plot) else NO_PLOT


## Shows what buying the plot under `point` would do and returns the status
## line's text: the price and the plot's size for a plot one click buys, the
## reason for one it would not, "" off the site.
func hover(point: Variant) -> String:
	var plot := plot_at(point)
	if plot == _hovered and _hover_text != "":
		return _hover_text
	_hovered = plot
	_hover.visible = false
	_price.visible = false
	_hover_text = ""
	if plot == NO_PLOT:
		return ""
	var problem := land.buy_problem(plot, mode.wallet())
	var cells := land.plot_cells(plot)
	if problem == null or problem.reason == BuildResult.Reason.CANT_AFFORD:
		_price.text = "Buy  %d" % land.next_price()
		_price.position = _ground(
			Vector2(cells.position) + Vector2(cells.size) / 2.0, LABEL_HEIGHT_M
		)
		_price.visible = true
	if problem == null:
		_hover_text = "Click to buy this %dx%d m plot" % [cells.size.x, cells.size.y]
	else:
		_hover_text = problem.reason_text()
	if not land.is_owned(plot):
		_hover.mesh = _quads([cells], HOVER_LIFT_M)
		_hover.material_override = _valid_material if problem == null else _invalid_material
		_hover.visible = true
	return _hover_text


## Buys the plot under `point` (LandPlots.buy(), from BuildMode's wallet) and
## returns the result; a refusal changes nothing.
func buy_at(point: Variant) -> BuildResult:
	var plot := plot_at(point)
	if plot == NO_PLOT:
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	var result := land.buy(plot, mode.wallet())
	_hover_text = ""
	return result


## (price, money the wallet must hold) of the plot under the pointer when it
## can be bought or only the money is short, zero otherwise (BuildMenu's cost
## line).
func preview_price() -> Vector2i:
	if _hovered == NO_PLOT or land.is_owned(_hovered) or not land.touches_owned(_hovered):
		return Vector2i.ZERO
	var price := land.next_price()
	return Vector2i(price, price)


## The buyable plots' fill mesh (for probes and tests).
func fill_mesh() -> Mesh:
	return _fills.mesh


## The label over the hovered plot.
func price_label() -> Label3D:
	return _price


func _on_tool_changed(tool: BuildMode.Tool) -> void:
	visible = tool == BuildMode.Tool.BUY_LAND
	_hovered = NO_PLOT
	_hover_text = ""


## The money decides whether the hovered plot can be bought: look again.
func _on_balance_changed(_balance: int) -> void:
	_hover_text = ""


func _on_land_changed() -> void:
	_hovered = NO_PLOT
	_hover_text = ""
	_draw_fills()


func _draw_fills() -> void:
	var areas: Array[Rect2i] = []
	for plot in land.buyable_plots():
		areas.append(land.plot_cells(plot))
	_fills.mesh = _quads(areas, LIFT_M) if not areas.is_empty() else null


## One flat quad per area of grid cells, `lift` over the floor.
func _quads(areas: Array[Rect2i], lift: float) -> Mesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for area in areas:
		var a := _ground(Vector2(area.position), lift)
		var b := _ground(Vector2(area.end.x, area.position.y), lift)
		var c := _ground(Vector2(area.end), lift)
		var d := _ground(Vector2(area.position.x, area.end.y), lift)
		for p in [a, b, c, a, c, d]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(p)
	return surface.commit()


## The world point over grid position `at` (in cells), `lift` over the floor.
func _ground(at: Vector2, lift: float) -> Vector3:
	var origin := mode.grid.origin
	return Vector3(origin.x + at.x, origin.y + lift, origin.z + at.y)
