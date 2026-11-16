class_name TestTaxiwayWorksLayout
extends GdUnitTestSuite
## Where the construction works stand (TaxiwayWorks; board ecd67e67, S8b phase
## 2; user ruling airside-construction-works-are-a-visible-stage-props-mark-th):
## on the scene's airside paved for a west and an east stand, no prop's footprint
## and no piece of works ground overlaps a live taxiway rect (every strip and pad
## drawn, and the runway) for a west and an east spur pending outward, inward and
## a little way out, and for both runway upgrades; each layout places barriers,
## cones and a yard with a brick pile (the positive control); cones close both
## ends of every piece; and two layouts from the same geometry are identical.
## The footprints the layout uses are checked against the written glbs.

const WEST_SILL := Vector2(0.0, -149.5)
const EAST_SILL := Vector2(0.0, -129.5)
const SIZE_TOLERANCE_M := 0.02

var _airside: Airside


func before() -> void:
	_airside = TestStandLaneClearance.scene_airside()
	add_child(_airside)


func after() -> void:
	_airside.free()


## Paves the airside for a west stand on spur `west_x` and an east one on
## `east_x`, and returns the live rects of a `runway_size` runway with them.
func _live(west_x: float, east_x: float, runway_size := Runway.SMALL) -> Array[Rect2]:
	var west := StandPlacement.make(0, WEST_SILL.x, WEST_SILL.y, StandPlacement.WEST)
	var east := StandPlacement.make(0, EAST_SILL.x, EAST_SILL.y, StandPlacement.EAST)
	var stands := {
		"A": StandPlacement.with_lane_x(west, west_x),
		"B": StandPlacement.with_lane_x(east, east_x),
	}
	_airside.set_gate_classes({"A": PlaneClasses.LARGE, "B": PlaneClasses.LARGE})
	assert_bool(_airside.set_gate_stands(stands)).is_true()
	return TaxiwayWorks.live_rects(_airside.paving.shown, _airside.paving.pads, runway_size)


func _side(side: String, now_x: float, wanted_x: float, live: Array[Rect2]) -> Dictionary:
	var span := TaxiwayWorks.spur_span(_airside.paving.shown, now_x)
	assert_float(span.y - span.x).is_greater(TaxiPaving.WIDTH_M)
	return TaxiwayWorks.side_layout(side, wanted_x, span, live)


## Checks `layout` against `live` and prints what it compared.
func _check(label: String, layout: Dictionary, live: Array[Rect2]) -> void:
	var counts := {}
	var nearest := INF
	for item: Dictionary in layout["props"]:
		counts[item["kind"]] = counts.get(item["kind"], 0) + 1
		var rect: Rect2 = item["rect"]
		for live_rect in live:
			(
				assert_bool(rect.intersects(live_rect))
				. override_failure_message(
					"%s: %s at %s overlaps live %s" % [label, item["kind"], rect, live_rect]
				)
				. is_false()
			)
			nearest = minf(nearest, _gap(rect, live_rect))
	for piece: Rect2 in layout["ground"]:
		for live_rect in live:
			(
				assert_bool(piece.intersects(live_rect))
				. override_failure_message("%s: ground %s overlaps %s" % [label, piece, live_rect])
				. is_false()
			)
		_check_cones(label, piece, layout["props"])
	print(
		(
			"%s: pieces=%d props=%d %s yard=%s nearest live gap=%.2f m"
			% [
				label,
				layout["ground"].size(),
				layout["props"].size(),
				counts,
				layout["yard"],
				nearest
			]
		)
	)
	assert_int(layout["ground"].size()).is_greater(0)
	assert_int(counts.get("barrier", 0)).is_greater(0)
	assert_int(counts.get("cone", 0)).is_greater(0)
	assert_int(counts.get("bricks", 0)).is_equal(1)
	assert_int(counts.get("loader", 0)).is_equal(1)
	assert_int(counts.get("trailer", 0)).is_equal(1)
	assert_int(counts.get("fence", 0)).is_equal(10)
	assert_bool((layout["yard"] as Rect2).has_area()).is_true()


## Both ends of `piece` (across its long side) have a row of cones in it.
func _check_cones(label: String, piece: Rect2, props: Array) -> void:
	var axis := 0 if piece.size.x > piece.size.y else 1
	var ends := [0, 0]
	for item: Dictionary in props:
		var at: Vector2 = item["centre"]
		if item["kind"] != "cone" or not piece.has_point(at):
			continue
		if absf(at[axis] - (piece.position[axis] + TaxiwayWorks.EDGE_INSET_M)) < 0.01:
			ends[0] += 1
		if absf(at[axis] - (piece.end[axis] - TaxiwayWorks.EDGE_INSET_M)) < 0.01:
			ends[1] += 1
	(
		assert_bool(ends[0] > 1 and ends[1] > 1)
		. override_failure_message("%s: piece %s cones at its ends %s" % [label, piece, ends])
		. is_true()
	)


## The distance between two rects that do not overlap.
static func _gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(0.0, maxf(b.position.x - a.end.x, a.position.x - b.end.x))
	var dz := maxf(0.0, maxf(b.position.y - a.end.y, a.position.y - b.end.y))
	return Vector2(dx, dz).length()


func test_side_works_stay_off_the_live_taxiway_west_and_east() -> void:
	var now := StandPlacement.SIDE_LANE_X
	var live := _live(-now, now)
	_check("west out", _side(StandPlacement.WEST, -now, -now - 40.0, live), live)
	_check("east out", _side(StandPlacement.EAST, now, now + 46.0, live), live)
	# A little way out: the new strip overlaps the spur in use.
	_check("west near", _side(StandPlacement.WEST, -now, -now - 12.0, live), live)
	_check("east near", _side(StandPlacement.EAST, now, now + 12.0, live), live)


func test_side_works_stay_off_the_live_taxiway_when_the_spur_moves_in() -> void:
	var now := StandPlacement.SIDE_LANE_X + 56.0
	var live := _live(-now, now)
	var west := _side(StandPlacement.WEST, -now, -StandPlacement.SIDE_LANE_X, live)
	var east := _side(StandPlacement.EAST, now, StandPlacement.SIDE_LANE_X, live)
	_check("west in", west, live)
	_check("east in", east, live)
	# The lane, the connectors and the pads cross the strip: it is cut back.
	for layout: Dictionary in [west, east]:
		var area := 0.0
		for piece: Rect2 in layout["ground"]:
			area += piece.get_area()
		var span := TaxiwayWorks.spur_span(_airside.paving.shown, now)
		var whole := TaxiPaving.WIDTH_M * (span.y - span.x)
		print("in: works ground %.0f of the strip's %.0f m2" % [area, whole])
		assert_float(area).is_greater(0.0)
		assert_float(area).is_less(whole * 0.9)


func test_runway_works_stay_off_the_live_taxiway() -> void:
	var live := _live(-StandPlacement.SIDE_LANE_X, StandPlacement.SIDE_LANE_X)
	_check("runway medium", TaxiwayWorks.runway_layout(Runway.SMALL, Runway.MEDIUM, live), live)
	live = _live(-StandPlacement.SIDE_LANE_X, StandPlacement.SIDE_LANE_X, Runway.MEDIUM)
	var large := TaxiwayWorks.runway_layout(Runway.MEDIUM, Runway.LARGE, live)
	_check("runway large", large, live)
	# The yard stands north of the runway, the side no taxiway uses.
	var yard: Rect2 = large["yard"]
	assert_float(yard.end.y).is_less(TaxiwayWorks.runway_rect(Runway.LARGE).position.y)


func test_two_layouts_from_the_same_geometry_are_identical() -> void:
	var now := StandPlacement.SIDE_LANE_X
	var live := _live(-now, now)
	var first := _side(StandPlacement.WEST, -now, -now - 40.0, live)
	var again := _side(StandPlacement.WEST, -now, -now - 40.0, live.duplicate())
	assert_int(first["props"].size()).is_greater(0)
	assert_str(var_to_str(again)).is_equal(var_to_str(first))
	var runway := TaxiwayWorks.runway_layout(Runway.SMALL, Runway.MEDIUM, live)
	assert_int(runway["props"].size()).is_greater(0)
	assert_str(var_to_str(TaxiwayWorks.runway_layout(Runway.SMALL, Runway.MEDIUM, live))).is_equal(
		var_to_str(runway)
	)


func test_the_footprints_match_the_written_glbs() -> void:
	for kind: String in TaxiwayWorks.KINDS:
		var entry: Array = TaxiwayWorks.KINDS[kind]
		var node: Node = (load(TaxiwayWorks.DIR + entry[0] + ".glb") as PackedScene).instantiate()
		var box := _bounds(node)
		node.free()
		var size := Vector2(box.size.x, box.size.z)
		var centre := Vector2(box.get_center().x, box.get_center().z)
		print(
			(
				"works %s footprint %s centre %s, layout %s %s"
				% [kind, size, centre, entry[1], entry[2]]
			)
		)
		assert_vector(size).is_equal_approx(entry[1], Vector2.ONE * SIZE_TOLERANCE_M)
		assert_vector(centre).is_equal_approx(entry[2], Vector2.ONE * SIZE_TOLERANCE_M)


## A prop turned a quarter puts its footprint where the layout says.
func test_a_turned_prop_lands_on_its_footprint() -> void:
	var item := TaxiwayWorks.prop("trailer", Vector2(10.0, 20.0), false)
	assert_float(item["yaw"]).is_equal_approx(PI / 2.0, 0.0001)
	var node: Node3D = (
		(load(TaxiwayWorks.DIR + "tfp_dump_trailer_01a.glb") as PackedScene).instantiate()
	)
	var origin: Vector2 = item["origin"]
	node.position = Vector3(origin.x, 0.0, origin.y)
	node.rotation.y = item["yaw"]
	var box: AABB = node.transform * _bounds(node)
	node.free()
	var got := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
	var want: Rect2 = item["rect"]
	print("turned trailer %s, layout %s" % [got, want])
	assert_vector(got.position).is_equal_approx(want.position, Vector2.ONE * SIZE_TOLERANCE_M)
	assert_vector(got.size).is_equal_approx(want.size, Vector2.ONE * SIZE_TOLERANCE_M)


## Bounds of `root`'s meshes in its own frame (not in the tree).
static func _bounds(root: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != root and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
