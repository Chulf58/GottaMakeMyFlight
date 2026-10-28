class_name TestSecurityLaneGeometry
extends GdUnitTestSuite
## The one lane-geometry source (SecurityLanes.geometry()): every named cell
## at each facing and mirror, and the new lane part definitions (decision
## security-lane-technical-design-one-station-per-lane-with-int, point 6).

const ANCHOR := Vector2i(6, 6)
const POINT_KEYS := [
	"arch",
	"tray_table",
	"xray_belt",
	"pickup_table",
	"queue_entry",
	"unpack",
	"pickup",
	"exit",
	"berth",
	"primary_spot",
	"helper_spot",
]


func _expect(lane: Dictionary, expected: Dictionary) -> void:
	for key in expected:
		assert_that(lane[key]).override_failure_message("%s" % key).is_equal(expected[key])


func test_facing_0_right_mirror_names_every_cell() -> void:
	var lane := SecurityLanes.geometry(ANCHOR, 0, SecurityLanes.RIGHT)
	print("facing 0 right: %s" % lane)
	_expect(
		lane,
		{
			"arch": Vector2i(6, 6),
			"tray_table": Vector2i(7, 7),
			"xray_belt": Vector2i(7, 6),
			"pickup_table": Vector2i(7, 5),
			"queue_entry": Vector2i(6, 8),
			"unpack": Vector2i(6, 7),
			"pickup": Vector2i(6, 5),
			"exit": Vector2i(6, 4),
			"berth": Vector2i(5, 5),
			"primary_spot": Vector2i(8, 6),
			"helper_spot": Vector2i(5, 4),
			"front": Vector2i(0, 1),
			"side": Vector2i(1, 0),
			"facing": 0,
			"mirror": SecurityLanes.RIGHT,
		}
	)
	assert_array(lane["return_route"]).is_equal([Vector2i(5, 6), Vector2i(5, 7)])
	assert_array(lane["passage"]).is_equal([Vector2i(6, 7), Vector2i(6, 6), Vector2i(6, 5)])


func test_the_left_mirror_flips_the_lane_across_its_walk() -> void:
	var lane := SecurityLanes.geometry(ANCHOR, 0, SecurityLanes.LEFT)
	_expect(
		lane,
		{
			"tray_table": Vector2i(5, 7),
			"xray_belt": Vector2i(5, 6),
			"pickup_table": Vector2i(5, 5),
			"queue_entry": Vector2i(6, 8),
			"berth": Vector2i(7, 5),
			"primary_spot": Vector2i(4, 6),
			"helper_spot": Vector2i(7, 4),
			"side": Vector2i(-1, 0),
		}
	)
	assert_array(lane["return_route"]).is_equal([Vector2i(7, 6), Vector2i(7, 7)])


func test_facing_1_turns_the_frame_a_quarter() -> void:
	var lane := SecurityLanes.geometry(ANCHOR, 1, SecurityLanes.RIGHT)
	_expect(
		lane,
		{
			"tray_table": Vector2i(5, 7),
			"xray_belt": Vector2i(6, 7),
			"pickup_table": Vector2i(7, 7),
			"queue_entry": Vector2i(4, 6),
			"unpack": Vector2i(5, 6),
			"pickup": Vector2i(7, 6),
			"exit": Vector2i(8, 6),
			"berth": Vector2i(7, 5),
			"primary_spot": Vector2i(6, 8),
			"helper_spot": Vector2i(8, 5),
		}
	)
	assert_array(lane["return_route"]).is_equal([Vector2i(6, 5), Vector2i(5, 5)])


func test_every_facing_and_mirror_gives_distinct_cells_and_a_joined_walk() -> void:
	var arch := BuildCatalog.get_def(SecurityLanes.ARCH)
	for facing in 4:
		for mirror in SecurityLanes.MIRRORS:
			var lane := SecurityLanes.geometry(ANCHOR, facing, mirror)
			var cells := SecurityLanes.lane_cells(lane)
			var distinct := {}
			for cell in cells:
				distinct[cell] = true
			print("facing %d mirror %d: %d cells" % [facing, mirror, cells.size()])
			assert_int(cells.size()).is_equal(POINT_KEYS.size() + 2)
			assert_int(distinct.size()).is_equal(cells.size())
			assert_that(lane["unpack"]).is_equal(arch.interaction_cell(ANCHOR, facing))
			# The walk: queue entry, unpack, arch, pickup, exit in a straight line.
			var walk: Array = [lane["queue_entry"]] + lane["passage"] + [lane["exit"]]
			for i in walk.size() - 1:
				assert_that(walk[i + 1] - walk[i]).is_equal(-lane["front"])
			# The return: pickup, berth, the route, back to the unpack cell.
			var back: Array = [lane["pickup"], lane["berth"]] + lane["return_route"]
			back.append(lane["unpack"])
			for i in back.size() - 1:
				var step: Vector2i = back[i + 1] - back[i]
				assert_int(absi(step.x) + absi(step.y)).is_equal(1)
			assert_int(_distance(lane["primary_spot"], lane["xray_belt"])).is_equal(1)
			assert_int(_distance(lane["helper_spot"], lane["berth"])).is_equal(1)
			assert_int(_distance(lane["tray_table"], lane["unpack"])).is_equal(1)
			assert_int(_distance(lane["pickup_table"], lane["pickup"])).is_equal(1)


func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func test_the_parts_are_one_cell_and_only_the_arch_is_walked_through() -> void:
	for part in SecurityLanes.PART_IDS:
		var def := BuildCatalog.get_def(part)
		assert_object(def).override_failure_message("%s" % part).is_not_null()
		assert_that(def.size).is_equal(Vector2i.ONE)
	var arch := BuildCatalog.get_def(SecurityLanes.ARCH)
	assert_bool(arch.walk_through).is_true()
	assert_bool(arch.has_interaction).is_true()
	assert_bool(BuildCatalog.is_security(SecurityLanes.ARCH)).is_true()
	assert_bool(BuildCatalog.is_security(&"security_scanner")).is_true()
	for part in [SecurityLanes.TRAY_TABLE, SecurityLanes.XRAY_BELT, SecurityLanes.PICKUP_TABLE]:
		var def := BuildCatalog.get_def(part)
		assert_bool(def.walk_through).is_false()
		assert_bool(def.has_interaction).is_false()
		assert_bool(BuildCatalog.is_security(part)).is_false()


func test_routing_never_enters_the_arch_but_its_passage_is_open() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(14, 14))
	var ids := SecurityLaneBuilder.build(grid, ANCHOR, 0, SecurityLanes.RIGHT)
	var lane := SecurityLanes.geometry(ANCHOR, 0, SecurityLanes.RIGHT)
	assert_bool(grid.can_step(lane["unpack"], ANCHOR)).is_true()
	assert_bool(grid.can_route(lane["unpack"], ANCHOR)).is_false()
	assert_bool(grid.can_route(ANCHOR, lane["pickup"])).is_false()
	assert_array(grid.passage_cells(ids[SecurityLanes.ARCH])).is_equal(lane["passage"])
	var path := grid.find_path(lane["queue_entry"], lane["exit"])
	print("route queue entry -> exit: %s" % [path])
	assert_bool(path.is_empty()).is_false()
	assert_bool(path.has(ANCHOR)).is_false()
	for part in SecurityLaneBuilder.PARTS:
		assert_bool(grid.is_walkable(lane[part])).is_false()
