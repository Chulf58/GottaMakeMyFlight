class_name TestBaggagePieces
extends GdUnitTestSuite
## The baggage pieces in BuildCatalog: footprints, prices and the belt ports
## (decision baggage-rides-a-player-built-belt-from-check-in-to-a-bag-roo). At
## every facing the catalog's ports agree with the Mount_Belt_* empties in the
## .glb pieces, a check-in desk's belt outlet meets a feed placed behind it,
## and belt pieces chain edge to edge.

const GRID := Vector2i(16, 16)
const ANCHOR := Vector2i(7, 7)
## Mount positions are authored to the millimetre.
const EPS := 0.002
const BELT_TOP := 0.355
const PORT_NAMES := ["F", "B", "L", "R"]

var _mounts_by_piece: Dictionary = {}


func before() -> void:
	for id in BuildCatalog.BELT_IDS:
		_mounts_by_piece[id] = _belt_mounts("res://assets/interior/%s.glb" % id)


## Port name ("F") -> its transform relative to the piece root.
func _belt_mounts(path: String) -> Dictionary:
	var root := (load(path) as PackedScene).instantiate() as Node3D
	var out := {}
	for node in root.find_children("Mount_Belt_*", "Node3D", true, false):
		var local := (node as Node3D).transform
		var parent := node.get_parent()
		while parent != root:
			local = (parent as Node3D).transform * local
			parent = parent.get_parent()
		out[String(node.name).trim_prefix("Mount_Belt_")] = local
	root.free()
	return out


func _floored() -> BuildGrid:
	var grid := BuildGrid.new(GRID)
	var edits: Array[BuildEdit] = []
	for y in GRID.y:
		for x in GRID.x:
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(edits)
	return grid


func _place(grid: BuildGrid, def_id: StringName, anchor: Vector2i, facing: int) -> int:
	var result := grid.apply(BuildEdit.place_object(def_id, anchor, facing))
	assert_bool(result.ok).override_failure_message("%s at %s" % [def_id, anchor]).is_true()
	return result.object_id


func _ports(grid: BuildGrid, object_id: int) -> Array[Dictionary]:
	var record := grid.get_object(object_id)
	return BuildCatalog.belt_ports(record["def"], record["anchor"], record["facing"])


func _port(ports: Array[Dictionary], port_name: String) -> Dictionary:
	for port in ports:
		if port["name"] == port_name:
			return port
	fail("no port %s" % port_name)
	return {}


func test_the_baggage_pieces_have_the_footprints_of_their_glb_pieces() -> void:
	for id in [&"baggage_belt", &"baggage_belt_corner", &"baggage_belt_feed", &"baggage_belt_end"]:
		assert_vector(BuildCatalog.get_def(id).size).is_equal(Vector2i.ONE)
	assert_vector(BuildCatalog.get_def(&"baggage_cart").size).is_equal(Vector2i(1, 2))
	for id in [&"baggage_belt", &"baggage_belt_end", &"baggage_cart"]:
		assert_bool(BuildCatalog.get_def(id).has_interaction).is_false()
		assert_bool(BuildCatalog.get_def(id).walk_through).is_false()


func test_every_baggage_piece_is_priced_and_a_run_of_belt_costs_less_than_a_desk() -> void:
	for id in [
		&"baggage_belt",
		&"baggage_belt_corner",
		&"baggage_belt_feed",
		&"baggage_belt_end",
		&"baggage_cart"
	]:
		assert_int(PriceTable.price_of_object(id)).is_greater(0)
	var desk := PriceTable.price_of_object(&"checkin_desk")
	var straight := PriceTable.price_of_object(&"baggage_belt")
	assert_int(straight * 6).is_less(desk)
	assert_int(PriceTable.price_of_object(&"baggage_belt_end")).is_greater(
		PriceTable.price_of_object(&"baggage_belt_feed")
	)


func test_only_the_belt_pieces_are_belts_and_each_has_ports() -> void:
	assert_array(BuildCatalog.BELT_IDS).has_size(4)
	for id in BuildCatalog.ids():
		assert_bool(BuildCatalog.is_belt(id)).is_equal(BuildCatalog.BELT_IDS.has(id))
	assert_int(BuildCatalog.belt_ports(&"baggage_belt", ANCHOR, 0).size()).is_equal(2)
	assert_int(BuildCatalog.belt_ports(&"baggage_belt_corner", ANCHOR, 0).size()).is_equal(2)
	assert_int(BuildCatalog.belt_ports(&"baggage_belt_feed", ANCHOR, 0).size()).is_equal(3)
	assert_int(BuildCatalog.belt_ports(&"baggage_belt_end", ANCHOR, 0).size()).is_equal(1)
	assert_array(BuildCatalog.belt_ports(&"seat_row", ANCHOR, 0)).is_empty()
	assert_array(BuildCatalog.belt_ports(&"baggage_cart", ANCHOR, 0)).is_empty()


func test_catalog_ports_are_exactly_the_glb_belt_mounts_at_every_facing() -> void:
	var grid := _floored()
	for id in BuildCatalog.BELT_IDS:
		var mounts: Dictionary = _mounts_by_piece[id]
		var names: Array = []
		for port in BuildCatalog.belt_ports(id, ANCHOR, 0):
			names.append(port["name"])
		names.sort()
		var glb_names: Array = mounts.keys()
		glb_names.sort()
		assert_array(names).override_failure_message("%s ports" % id).is_equal(glb_names)
		for facing in 4:
			var def := BuildCatalog.get_def(id)
			var piece := BuildView.object_transform(grid, def.footprint(ANCHOR, facing), facing)
			for port in BuildCatalog.belt_ports(id, ANCHOR, facing):
				var mount: Transform3D = piece * mounts[port["name"]]
				var side: Vector2i = port["side"]
				var edge := grid.cell_to_world(port["cell"]) + Vector3(side.x, 0.0, side.y) * 0.5
				var info := (
					"%s facing %d port %s mount %s edge %s"
					% [id, facing, port["name"], mount.origin, edge]
				)
				(
					assert_float(
						Vector2(mount.origin.x, mount.origin.z).distance_to(Vector2(edge.x, edge.z))
					)
					. override_failure_message(info)
					. is_less(EPS)
				)
				(
					assert_float(mount.origin.y - edge.y)
					. override_failure_message(info)
					. is_equal_approx(BELT_TOP, EPS)
				)
				# The port's +Z points out of the piece, along the side.
				var out := mount.basis.z.normalized()
				assert_float(out.distance_to(Vector3(side.x, 0.0, side.y))).is_less(EPS)


func test_belt_paths_only_use_the_pieces_own_ports() -> void:
	for id in BuildCatalog.BELT_PATHS:
		var names: Array = []
		for port in BuildCatalog.belt_ports(id, ANCHOR, 0):
			names.append(port["name"])
		for path in BuildCatalog.BELT_PATHS[id]:
			assert_array(names).contains([path[0]])
			assert_bool(names.has(path[1]) or path[1] == "BagRest").is_true()
	# A merge has more than one way out of its inlet; the bag sim picks one.
	assert_int(BuildCatalog.BELT_PATHS[&"baggage_belt_feed"].size()).is_equal(3)


func test_the_desk_outlet_is_its_belt_cell_on_the_back_edge() -> void:
	for facing in 4:
		var def := BuildCatalog.get_def(&"checkin_desk")
		var ports := BuildCatalog.belt_ports(&"checkin_desk", ANCHOR, facing)
		assert_int(ports.size()).is_equal(1)
		var outlet: Dictionary = ports[0]
		var footprint := def.footprint(ANCHOR, facing)
		assert_bool(footprint.has(outlet["cell"])).is_true()
		# The counter cell is the anchor (its front is the interaction cell).
		assert_vector(outlet["cell"]).is_not_equal(ANCHOR)
		# The outlet leaves the desk on the side opposite the interaction cell.
		assert_bool(footprint.has(outlet["cell"] + outlet["side"])).is_false()
		var front := def.interaction_cell(ANCHOR, facing) - ANCHOR
		assert_vector(outlet["side"]).is_equal(-front)


func test_a_feed_behind_the_desk_joins_its_outlet_at_every_facing() -> void:
	for facing in 4:
		var grid := _floored()
		var desk := _place(grid, &"checkin_desk", ANCHOR, facing)
		var outlet := _ports(grid, desk)[0]
		var feed := _place(grid, &"baggage_belt_feed", outlet["cell"] + outlet["side"], facing)
		var inlet := _port(_ports(grid, feed), "F")
		assert_bool(BuildCatalog.belt_ports_join(outlet, inlet)).is_true()
		assert_bool(BuildCatalog.belt_ports_join(inlet, outlet)).is_true()


func _joined(grid: BuildGrid, first: int, second: int) -> bool:
	for mine in _ports(grid, first):
		for theirs in _ports(grid, second):
			if BuildCatalog.belt_ports_join(mine, theirs):
				return true
	return false


func test_a_line_of_pieces_chains_from_the_desk_to_the_end() -> void:
	# Desk (belt cell (8, 7), outlet north), feed behind it, two straight belts
	# running east (facing 1 turns F to -x), a corner (facing 2: R meets the
	# belt from the west, F leaves north) and the end below it facing south.
	var grid := _floored()
	var desk := _place(grid, &"checkin_desk", ANCHOR, 0)
	var feed := _place(grid, &"baggage_belt_feed", Vector2i(8, 6), 0)
	var belt_a := _place(grid, &"baggage_belt", Vector2i(9, 6), 1)
	var belt_b := _place(grid, &"baggage_belt", Vector2i(10, 6), 1)
	var corner := _place(grid, &"baggage_belt_corner", Vector2i(11, 6), 2)
	var end := _place(grid, &"baggage_belt_end", Vector2i(11, 5), 0)
	var line := [desk, feed, belt_a, belt_b, corner, end]
	for i in line.size():
		for j in line.size():
			var adjacent := absi(i - j) == 1
			var info := "pieces %d and %d" % [i, j]
			assert_bool(_joined(grid, line[i], line[j])).override_failure_message(info).is_equal(
				adjacent
			)


func test_ports_that_do_not_face_each_other_do_not_join() -> void:
	var grid := _floored()
	var a := _place(grid, &"baggage_belt", ANCHOR, 0)
	# Two cells away, side by side, and the same cell facing the same way.
	var far := _place(grid, &"baggage_belt", ANCHOR + Vector2i(0, 2), 0)
	var beside := _place(grid, &"baggage_belt", ANCHOR + Vector2i(1, 0), 0)
	for other in [far, beside]:
		for mine in _ports(grid, a):
			for theirs in _ports(grid, other):
				assert_bool(BuildCatalog.belt_ports_join(mine, theirs)).is_false()
	# Facing away: a belt behind another, turned the opposite way, still joins end
	# to end (a straight belt is symmetric), but a corner's R does not meet a
	# straight belt's F when they are not on the same edge.
	var corner := _place(grid, &"baggage_belt_corner", ANCHOR + Vector2i(0, -1), 0)
	var corner_f := _port(_ports(grid, corner), "F")
	var belt_b := _port(_ports(grid, a), "B")
	assert_bool(BuildCatalog.belt_ports_join(corner_f, belt_b)).is_true()
	assert_bool(BuildCatalog.belt_ports_join(_port(_ports(grid, corner), "R"), belt_b)).is_false()
