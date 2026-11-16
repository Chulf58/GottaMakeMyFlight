class_name TestSideLandStands
extends GdUnitTestSuite
## Stands on the side land once it is open (board airside-all-around-s7-side-
## routes-follow-the-build-each-side, S7c; decision side-land-columns-ship-
## locked-the-wide-site-grid-lands-first): a north stand whose join lies on the
## lane past a runway stub is refused even when a side spur has moved out
## beyond it, a west stand whose sill lies beyond its spur is refused, the
## whole grid is paved at the site's ground height, and a saved stand whose sill
## is on the grid's east edge loads.

const SITE := preload("res://build/terminal_site.tres")
## A small room on the grid's west edge, west of the west stub (x -124): its
## cells x 1 to 3 are x -127 to -124.
const ROOM := Rect2i(1, 50, 3, 3)

var _airside: Airside


func before() -> void:
	_airside = TestStandLaneClearance.scene_airside()
	add_child(_airside)


func after() -> void:
	_airside.free()


func after_test() -> void:
	_airside.set_gate_stands({})


## A west stand on a spur moved out to x -150, beside a north stand whose sill
## is at `north_x`.
static func _stands(north_x: float) -> Dictionary:
	var west := StandPlacement.make(1, -60.0, -150.0, StandPlacement.WEST, -150.0)
	return {"A": west, "B": StandPlacement.make(2, north_x, -150.0)}


## Once the west spur moves out the lane runs on west of TaxiWest to its head,
## but a north stand's join there would turn the plane back along the lane: it
## is refused, at the layout Airside checks and by Airside itself. A join just
## inside the stub still joins. Without the stub check the widened lane took it.
func test_a_north_join_past_the_stub_is_refused_beside_a_moved_spur() -> void:
	var layout := TaxiRoutes.north_only(FlightGround.points())
	layout["west_x"] = -150.0
	var past := Vector3(-130.0, 0.0, StandPlacement.TAXI_LANE_Z)
	var inside := Vector3(-123.5, 0.0, StandPlacement.TAXI_LANE_Z)
	print("layout %s: past %s, inside %s" % [layout, past, inside])
	assert_bool(TaxiRoutes.joins_lane(past, layout)).is_false()
	assert_bool(TaxiRoutes.joins_lane(inside, layout)).is_true()
	# The west spur's own joins still join the widened lane.
	var west_join := StandPlacement.lane_join(_stands(0.0)["A"])
	assert_bool(TaxiRoutes.joins_lane(west_join, layout)).is_true()
	# A north stand's join is its door side (DOOR_SIDE_M) west of its sill: sill
	# x -120 joins at -123.5, sill -126.5 at -130.
	assert_bool(_airside.set_gate_stands(_stands(-120.0))).is_true()
	assert_float(float(_airside.lane_layout()["west_x"])).is_equal(-150.0)
	assert_bool(_airside.set_gate_stands({})).is_true()
	assert_bool(_airside.set_gate_stands(_stands(-126.5))).is_false()
	assert_bool(_airside.routes_gate("B")).is_false()


## reaches_lane(): a north stand between the stubs reaches its lane and one
## past either stub does not; a west or east stand reaches its spur from short
## of it and not from on or beyond it.
func test_a_stand_reaches_its_lane_only_from_its_own_side_of_it() -> void:
	# The join is DOOR_SIDE_M (3.5 m) west of the sill: these join at x -123.5,
	# 123.5, -124 and 124.
	assert_bool(StandPlacement.reaches_lane(StandPlacement.make(1, -120.0, -150.0))).is_true()
	assert_bool(StandPlacement.reaches_lane(StandPlacement.make(1, 127.0, -150.0))).is_true()
	assert_bool(StandPlacement.reaches_lane(StandPlacement.make(1, -120.5, -150.0))).is_false()
	assert_bool(StandPlacement.reaches_lane(StandPlacement.make(1, 127.5, -150.0))).is_false()
	var west := StandPlacement.WEST
	var east := StandPlacement.EAST
	# On the floor spur: a sill well inside reaches it; one beyond it does not.
	assert_bool(StandPlacement.reaches_lane(StandPlacement.make(1, -60.0, -100.0, west))).is_true()
	(
		assert_bool(StandPlacement.reaches_lane(StandPlacement.make(1, -127.0, -100.0, west)))
		. is_false()
	)
	assert_bool(StandPlacement.reaches_lane(StandPlacement.make(1, 127.0, -100.0, east))).is_false()
	# The same sill once the spur has moved out past it reaches it again.
	var moved := StandPlacement.make(1, -127.0, -100.0, west, SideSpurs.stand_lane(west, -127.0))
	assert_bool(StandPlacement.reaches_lane(moved)).is_true()
	# A spur 1 cm inside where the pushback ends: no way on toward it; 1 cm out
	# of it: a way. `reach` is the sill-to-pushback-end depth along the stand.
	var twin := StandPlacement.north_twin(StandPlacement.make(1, -100.0, -100.0, west))
	var reach := float(twin["wall_z"]) - StandPlacement.pushback_end(twin).z
	var short := StandPlacement.make(1, -100.0, -100.0, west, -100.0 - reach + 0.01)
	var clear := StandPlacement.make(1, -100.0, -100.0, west, -100.0 - reach - 0.01)
	print(
		(
			"sill to pushback end %.3f m: spurs at %.3f and %.3f"
			% [reach, short["lane_x"], clear["lane_x"]]
		)
	)
	assert_bool(StandPlacement.reaches_lane(short)).is_false()
	assert_bool(StandPlacement.reaches_lane(clear)).is_true()


## A small room with one exit door at `exit` facing `turn` on the west edge of a
## fresh site grid with no land (every cell owned), walled in around it.
func _room(exit: Vector2i, turn: int, exit_side: int) -> SiteGrid:
	var grid := SiteGrid.new(SITE)
	var edits: Array[BuildEdit] = []
	for y in range(ROOM.position.y, ROOM.end.y):
		for x in range(ROOM.position.x, ROOM.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for x in range(ROOM.position.x, ROOM.end.x):
		edits.append(BuildEdit.place_wall(Vector2i(x, ROOM.position.y), BuildGrid.Side.NORTH))
		edits.append(BuildEdit.place_wall(Vector2i(x, ROOM.end.y - 1), BuildGrid.Side.SOUTH))
	for y in range(ROOM.position.y, ROOM.end.y):
		edits.append(BuildEdit.place_wall(Vector2i(ROOM.position.x, y), BuildGrid.Side.WEST))
		edits.append(BuildEdit.place_wall(Vector2i(ROOM.end.x - 1, y), BuildGrid.Side.EAST))
	edits.append(BuildEdit.remove_wall(exit, exit_side))
	edits.append(BuildEdit.place_object(&"exit_door", exit, turn))
	for result in grid.apply_batch(edits):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	return grid


## StandPlacement.place() and check() skip a stand that cannot reach its lane: a
## north exit west of the west stub (sill x -125.5), and a west exit whose sill
## (x -127) lies beyond the floor spur at x -124. Before reaches_lane() the north
## one was chosen, and FlightGround planned it a route that turns back along
## the lane.
func test_place_skips_an_exit_whose_stand_cannot_reach_its_lane() -> void:
	var north_grid := _room(Vector2i(2, ROOM.position.y), 0, BuildGrid.Side.NORTH)
	var west_grid := _room(Vector2i(ROOM.position.x, 51), 3, BuildGrid.Side.WEST)
	for grid: SiteGrid in [north_grid, west_grid]:
		var exit := 0
		for id in grid.object_ids():
			if StringName(grid.get_object(id)["def"]) == &"exit_door":
				exit = id
		var stand := StandPlacement.for_exit(grid, exit)
		var placed := StandPlacement.place(grid, SITE, {})
		var checked := StandPlacement.check(grid, SITE, exit, stand)
		print(
			(
				"exit %d stand %s: walk %d points, reaches %s, place %s, check %s"
				% [
					exit,
					stand,
					StandPlacement.walk_of(grid, SITE, exit, stand).size(),
					StandPlacement.reaches_lane(stand),
					placed["status"],
					checked["status"],
				]
			)
		)
		assert_int(exit).is_not_zero()
		assert_dict(stand).is_not_empty()
		assert_bool(StandPlacement.reaches_lane(stand)).is_false()
		assert_str(placed["status"]).is_equal(StandPlacement.UNAVAILABLE)
		assert_str(checked["status"]).is_equal(StandPlacement.UNAVAILABLE)
	# Control: the north exit's walk exists, so only the lane check refuses it.
	var north_stand := StandPlacement.for_exit(north_grid, north_grid.object_ids()[-1])
	assert_bool(StandPlacement.aircraft_clear(north_grid, SITE, north_stand)).is_true()


## A gate desk cannot link a north exit past the west stub: its envelope's way
## out is blocked (StandEnvelope.blocked_part() WAY, GateDesks ROUTE_BLOCKED),
## for every class, while the same stand one cell east is clear. Cell 7's sill
## is at x -120.5 and its join on the stub (x -124); cell 8's joins at -123.
func test_a_gate_cannot_link_a_north_exit_past_the_stub() -> void:
	var grid := SiteGrid.new(SITE)
	var past := StandPlacement.for_cell(grid, Vector2i(7, 60))
	var inside := StandPlacement.for_cell(grid, Vector2i(8, 60))
	print("past %s, inside %s" % [past, inside])
	for plane_class in PlaneClasses.ORDER:
		assert_int(StandEnvelope.blocked_part(grid, SITE, past, plane_class)).is_equal(
			StandEnvelope.Part.WAY
		)
		assert_int(StandEnvelope.blocked_part(grid, SITE, inside, plane_class)).is_equal(
			StandEnvelope.Part.CLEAR
		)
	assert_int(GateDesks.stand_unfit(grid, past, [])).is_equal(GateDesks.Unlinked.ROUTE_BLOCKED)
	assert_int(GateDesks.stand_unfit(grid, inside, [])).is_equal(-1)


## The plane rides at the site's ground height over the whole grid, side land
## included, ramping down to 0 over PAVING_RAMP_M outside it; the paving under
## it follows (TaxiPavingSite.lift_at()).
func test_side_land_is_paved_at_the_ground_height() -> void:
	var height := SITE.ground_height
	var west_side := Vector3(-100.0, 0.0, -150.0)
	var east_side := Vector3(100.0, 0.0, -150.0)
	var half_out := Vector3(-128.0 - PlaneView.PAVING_RAMP_M / 2.0, 0.0, -150.0)
	var off := Vector3(-128.0 - PlaneView.PAVING_RAMP_M, 0.0, -150.0)
	print(
		(
			"ground at %s %.3f, %s %.3f, %s %.3f, %s %.3f"
			% [
				west_side,
				PlaneView.ground_height_at(west_side),
				east_side,
				PlaneView.ground_height_at(east_side),
				half_out,
				PlaneView.ground_height_at(half_out),
				off,
				PlaneView.ground_height_at(off),
			]
		)
	)
	assert_float(PlaneView.ground_height_at(west_side)).is_equal(height)
	assert_float(PlaneView.ground_height_at(east_side)).is_equal(height)
	assert_float(PlaneView.ground_height_at(Vector3(0.0, 0.0, -150.0))).is_equal(height)
	assert_float(PlaneView.ground_height_at(half_out)).is_equal_approx(height / 2.0, 1e-6)
	assert_float(PlaneView.ground_height_at(off)).is_equal(0.0)
	assert_float(TaxiPavingSite.lift_at(west_side)).is_less(height)
	assert_float(TaxiPavingSite.lift_at(west_side)).is_greater(0.0)


## A saved east stand whose sill lies on the grid's east edge (x 128, an exit on
## the east column) loads; one a metre past it does not. Rect2.has_point left
## out the end edge.
func test_a_saved_stand_on_the_east_edge_loads() -> void:
	var edge := SITE.grid_origin.x + SITE.grid_size.x
	var on_edge := StandPlacement.make(3, edge, -150.0, StandPlacement.EAST, edge + 70.0)
	var past := StandPlacement.make(3, edge + 1.0, -150.0, StandPlacement.EAST, edge + 71.0)
	var south := StandPlacement.make(3, 0.5, SITE.grid_origin.z + SITE.grid_size.y)
	var loaded := ApronStand.checked({"stands": {"A": on_edge}}, SITE)
	print("east edge x %.1f: %s" % [edge, loaded])
	assert_dict(loaded).not_contains_keys(["error"])
	assert_dict(loaded["stands"]["A"]).is_equal(on_edge)
	assert_dict(ApronStand.checked({"live": south}, SITE)).not_contains_keys(["error"])
	assert_dict(ApronStand.checked({"stands": {"A": past}}, SITE)).contains_keys(["error"])
	assert_dict(ApronStand.checked({"live": on_edge}, SITE)).contains_key_value("live", on_edge)
