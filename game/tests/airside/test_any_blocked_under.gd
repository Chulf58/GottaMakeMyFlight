class_name TestAnyBlockedUnder
extends GdUnitTestSuite
## StandPlacement.any_blocked_under() stops at the first blocked cell instead of
## building cells_under()'s whole set first (S7c fix round: SpareStand.find() on
## a fully owned grid). It must give the answer the set gave: on two layouts
## (the starter shell; scattered floor with a wall run), for north, west and
## east stands across the grid and every class's envelope, any_blocked_under(),
## aircraft_clear() and StandEnvelope.blocked_part() agree with the set-based
## checks they replaced, and both answers occur.

const SITE := preload("res://build/terminal_site.tres")
## Every how many cells a candidate stand is tried, across and down.
const STEP := Vector2i(37, 23)

var _layouts := {}


func before() -> void:
	var starter := SiteGrid.new(SITE)
	StarterShell.place(starter, SITE.starter_offset)
	_layouts["starter"] = starter
	var scattered := SiteGrid.new(SITE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var edits: Array[BuildEdit] = []
	for i in 400:
		var cell := Vector2i(rng.randi_range(0, SITE.grid_size.x - 1), rng.randi_range(0, 149))
		edits.append(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1))
	for x in range(40, 200):
		edits.append(BuildEdit.place_wall(Vector2i(x, 70), BuildGrid.Side.NORTH))
	scattered.apply_batch(edits)
	_layouts["scattered"] = scattered


## The set-based check any_blocked_under() replaced.
static func _blocked_by_set(grid: BuildGrid, rects: Array[Rect2]) -> bool:
	for cell: Vector2i in StandPlacement.cells_under(grid, rects):
		if not StandPlacement.apron_clear(grid, SITE, cell):
			return true
	return false


## StandEnvelope.blocked_part() as it was, on the set.
static func _part_by_set(grid: BuildGrid, stand: Dictionary, plane_class: String) -> int:
	var parts := StandEnvelope.rects(stand, plane_class)
	for i in parts.size():
		var one: Array[Rect2] = [parts[i]]
		if StandPlacement.reaches_road(grid, one) or _blocked_by_set(grid, one):
			return StandEnvelope.Part.SWING if i == 0 else StandEnvelope.Part.WAY
	if not StandEnvelope.clears_lane(stand, plane_class):
		return StandEnvelope.Part.LANE
	if not StandPlacement.reaches_lane(stand):
		return StandEnvelope.Part.WAY
	return StandEnvelope.Part.CLEAR


func test_the_early_stop_gives_the_set_answer_on_every_layout() -> void:
	var compared := 0
	var answers := {}
	for name: String in _layouts:
		var grid: SiteGrid = _layouts[name]
		for y in range(0, grid.size.y, STEP.y):
			for x in range(0, grid.size.x, STEP.x):
				for side: String in StandPlacement.SIDES:
					var stand := StandPlacement.for_cell(grid, Vector2i(x, y), 0, side)
					var swept := StandPlacement.swept_rects(stand)
					var blocked := _blocked_by_set(grid, swept)
					(
						assert_bool(StandPlacement.any_blocked_under(grid, SITE, swept))
						. override_failure_message("%s %s" % [name, stand])
						. is_equal(blocked)
					)
					assert_bool(StandPlacement.aircraft_clear(grid, SITE, stand)).is_equal(
						not blocked and not StandPlacement.reaches_road(grid, swept)
					)
					answers[blocked] = true
					for plane_class in PlaneClasses.ORDER:
						var part := StandEnvelope.blocked_part(grid, SITE, stand, plane_class)
						(
							assert_int(part)
							. override_failure_message("%s %s %s" % [name, stand, plane_class])
							. is_equal(_part_by_set(grid, stand, plane_class))
						)
						answers["part %d" % part] = true
					compared += 1
	print("compared %d stands on %s; answers seen %s" % [compared, _layouts.keys(), answers.keys()])
	assert_int(compared).is_greater(250)
	assert_bool(answers.has(true) and answers.has(false)).is_true()
	for part in ["part 0", "part 1", "part 2"]:
		assert_bool(answers.has(part)).override_failure_message(part).is_true()


## SpareStand.find() as it was before it skipped candidates by their parked
## cell (_parked_steps()): every candidate built and checked.
static func _find_every_candidate(
	grid: BuildGrid, stands: Array[Dictionary], plane_class: String
) -> Dictionary:
	var site := GateDesks.site_of(grid)
	var land: LandPlots = (grid as SiteGrid).land if grid is SiteGrid else null
	for y in range(grid.size.y - 1, -1, -1):
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if land != null and not land.owns_cell(cell):
				continue
			if site != null and site.is_obstacle(cell):
				continue
			for side: String in StandPlacement.SIDES:
				var stand := StandPlacement.for_cell(grid, cell, 0, side)
				if SpareStand._fits(grid, site, stand, stands, plane_class):
					return stand
	return {}


## SpareStand.find() skips a candidate whose parked cell is built on without
## changing which stand it finds: on the starter with a new game's land, and
## on a grid floored everywhere but a patch reaching in from its north edge,
## where the first fit lies far up the scan.
func test_spare_stand_finds_what_trying_every_candidate_finds() -> void:
	var land := LandPlots.for_site(SITE)
	land.own_start(SITE)
	var starter: SiteGrid = (_layouts["starter"] as SiteGrid).clone()
	starter.land = land
	var patched := SiteGrid.new(SITE)
	var edits: Array[BuildEdit] = []
	var patch := Rect2i(100, 0, 60, 90)
	for y in patched.size.y:
		for x in patched.size.x:
			if not patch.has_point(Vector2i(x, y)):
				edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	patched.apply_batch(edits)
	var cases := [
		["starter", starter, PlaneClasses.SMALL],
		["starter", starter, PlaneClasses.LARGE],
		["patched", patched, PlaneClasses.SMALL],
	]
	for case: Array in cases:
		var grid: SiteGrid = case[1]
		var stands: Array[Dictionary] = [StandPlacement.starter_stand(grid, SITE)]
		var found := SpareStand.find(grid, stands, case[2])
		var want := _find_every_candidate(grid, stands, case[2])
		print("%s %s: found %s, every candidate %s" % [case[0], case[2], found, want])
		assert_dict(want).is_not_empty()
		assert_dict(found).override_failure_message("%s" % [case]).is_equal(want)
