class_name TestWideSiteRefused
extends GdUnitTestSuite
## A site whose plot columns do not cut its grid fails closed (Sol re-check,
## board a91c3969): main.tscn boots on a scratch 255-wide site whose 256 cells
## of plot columns are refused. The land is refused once and still bound, so
## the grid takes no build, no starter is placed, a save is refused rather
## than taken without its land part, and the land checks a load runs return
## the column error instead of reading a land that is not there.

const SITE := preload("res://build/terminal_site.tres")
const SEED := 4_401_255

var _bad: SiteDefinition
var _main: Node
var _mode: BuildMode
var _save: SaveGame


func before() -> void:
	_bad = SITE.duplicate()
	_bad.grid_size = Vector2i(255, SITE.grid_size.y)
	_main = load(SaveTestKit.MAIN).instantiate()
	_mode = _main.get_node("BuildMode")
	_mode.site = _bad
	var clock: SimClock = _main.get_node("SimClock")
	clock.seed_rng(SEED)
	clock.set_paused(true)
	add_child(_main)
	_save = SaveTestKit.save_game(_main)


func after() -> void:
	_main.free()


func test_the_land_is_refused_and_still_bound() -> void:
	var land := _mode.land_tool.land
	print("land error '%s', plots %s" % [land.error, land.plots])
	assert_object((_mode.grid as SiteGrid).land).is_same(land)
	assert_str(land.error).contains("add up to 256 cells, not the grid's 255")
	assert_that(land.plots).is_equal(Vector2i.ZERO)
	assert_array(land.buyable_plots()).is_empty()


func test_no_building_is_allowed_and_no_starter_was_placed() -> void:
	var grid := _mode.grid
	var floors := 0
	for y in grid.size.y:
		for x in grid.size.x:
			floors += 1 if grid.floor_at(Vector2i(x, y)) != BuildGrid.FLOOR_NONE else 0
	print("floor cells after boot %d" % floors)
	assert_int(floors).is_equal(0)
	var at := SITE.starter_offset + Vector2i(5, 5)
	var floor_edit := BuildEdit.paint_floor(at, BuildGrid.FLOOR_TILE, 1)
	assert_int(grid.validate(floor_edit).reason).is_equal(BuildResult.Reason.LAND_NOT_OWNED)
	assert_bool(grid.apply(floor_edit).ok).is_false()
	# A desk is refused too (the gate guard speaks first), and the land alone
	# refuses it as well.
	var desk := BuildEdit.place_object(GateDesks.DESK, at, 0)
	assert_bool(grid.validate(desk).ok).is_false()
	var land := _mode.land_tool.land
	assert_int(land.edit_problem(desk).reason).is_equal(BuildResult.Reason.LAND_NOT_OWNED)
	# The control: the same edit on the real site's land is not refused for land.
	var good := LandPlots.for_site(SITE)
	good.own_start(SITE)
	assert_object(good.edit_problem(floor_edit)).is_null()


func test_a_save_is_refused_not_taken_without_its_land() -> void:
	var why := _save.save_problem()
	print("save problem: '%s'" % why)
	assert_str(why).contains("the site's land plots were refused")
	assert_dict(_save.snapshot()).is_empty()


func test_the_load_checks_return_the_column_error() -> void:
	var data := {"plot_counts": [12, 6], "owned": [], "bought": 0}
	var why := LandPlots.problem(data, _bad)
	assert_str(why).contains("add up to 256 cells, not the grid's 255")
	assert_str(LandPlots.grid_problem(data, _bad, _mode.grid)).is_equal(why)
