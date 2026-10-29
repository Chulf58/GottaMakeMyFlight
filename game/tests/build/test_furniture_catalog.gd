class_name TestFurnitureCatalog
extends GdUnitTestSuite
## The furniture ids (Furniture 4/4, F4-1): every decor and activity model
## exported into game/ is a BuildCatalog id with a price and an InteriorKit
## piece, and its footprint, height and interaction offset agree with its .glb
## (decisions all-11-exported-decor-models-are-placeable-plants-trees-foun and
## oversized-toon-decor-trees-fountain-statue-tree-bench-is-bui: no rescale at
## placement). Reads the pieces only; nothing here builds a scene.

const DECOR_IDS: Array[StringName] = [
	&"bench_1a",
	&"bench_2a_indoor",
	&"bush",
	&"fountain_indoor",
	&"metal_pole",
	&"metal_pole_chain",
	&"plant_pot_1a",
	&"plant_pot_2a",
	&"statue_indoor",
	&"trash_can",
	&"tree_indoor",
]
const KIT_IDS: Array[StringName] = [
	&"bar_counter",
	&"grab_and_go_stall",
	&"restaurant_table",
	&"restaurant_booth",
	&"info_desk",
	&"info_screen",
	&"currency_exchange",
	&"atm",
	&"pharmacy_counter",
	&"pharmacy_shelf",
	&"shower_cubicle",
	&"nap_pod",
	&"play_blocks",
	&"play_slide",
	&"lounge_sofa",
	&"lounge_armchair",
	&"work_desk",
	&"prize_podium",
]
## The mounts that name where a passenger stands to use a piece, in the order
## a piece offers them (a piece has at most one of these).
const USE_MOUNTS: Array[String] = ["Mount_Order", "Mount_Use", "Mount_Browse"]
## Vendor decor is not inset like the kit: a piece may overhang its cells by
## this much.
const DECOR_OVERHANG := 0.05
const KIT_OVERHANG := 0.01
## Decor drawn below the floor: the bush's root ball (tc_bush_1a, as built).
const BELOW_FLOOR := {&"bush": 0.3}
## Height of the prize car on its podium (the car is drawn with the podium).
const PRIZE_CAR_ID := &"prize_podium"
## A def height is the model's top rounded up to a centimetre.
const HEIGHT_SLACK := 0.02

var _new_ids: Array[StringName] = []


func before() -> void:
	_new_ids.append_array(DECOR_IDS)
	_new_ids.append_array(KIT_IDS)


## The model's bounds in the object's frame: the kit pieces' meshes at their
## own transforms, lifted by the object's piece offset.
func _bounds(id: StringName) -> AABB:
	var piece := InteriorKit.object_piece(id)
	var box := AABB()
	var parts := InteriorKit.meshes(piece)
	for i in parts.size():
		var part_box: AABB = (parts[i][1] as Transform3D) * (parts[i][0] as Mesh).get_aabb()
		box = part_box if i == 0 else box.merge(part_box)
	box.position += InteriorKit.object_offset(id)
	return box


## Where a piece's mount sits in the piece's frame, or null when it has none.
func _mount(piece: String, mount_name: String) -> Variant:
	var root := InteriorKit.instantiate(piece)
	var node := root.find_child(mount_name, true, false) as Node3D
	var found: Variant = null
	if node != null:
		var xf := node.transform
		var parent := node.get_parent()
		while parent != root:
			xf = (parent as Node3D).transform * xf
			parent = parent.get_parent()
		found = xf
	root.free()
	return found


func test_every_catalog_id_has_a_loadable_piece() -> void:
	var ids := BuildCatalog.ids()
	assert_int(ids.size()).is_greater(0)
	for id in ids:
		var piece := InteriorKit.object_piece(id)
		assert_str(piece).override_failure_message("no piece for %s" % id).is_not_empty()
		var path := InteriorKit.piece_path(piece)
		assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
		assert_int(InteriorKit.meshes(piece).size()).override_failure_message(str(id)).is_greater(0)


func test_every_new_id_is_in_the_catalog_with_a_size() -> void:
	assert_int(_new_ids.size()).is_equal(29)
	for id in _new_ids:
		var def := BuildCatalog.get_def(id)
		assert_object(def).override_failure_message("missing %s" % id).is_not_null()
		assert_int(def.size.x).is_greater(0)
		assert_int(def.size.y).is_greater(0)
		assert_str(def.display_name).is_not_empty()


func test_each_model_stays_inside_its_footprint_and_def_height_is_its_top() -> void:
	for id in _new_ids:
		var def := BuildCatalog.get_def(id)
		var box := _bounds(id)
		var slack := DECOR_OVERHANG if id in DECOR_IDS else KIT_OVERHANG
		var half := Vector2(def.size) / 2.0
		assert_float(box.position.x).override_failure_message(str(id)).is_greater_equal(
			-half.x - slack
		)
		assert_float(box.end.x).override_failure_message(str(id)).is_less_equal(half.x + slack)
		assert_float(box.position.z).override_failure_message(str(id)).is_greater_equal(
			-half.y - slack
		)
		assert_float(box.end.z).override_failure_message(str(id)).is_less_equal(half.y + slack)
		assert_float(box.position.y).override_failure_message(str(id)).is_greater_equal(
			-BELOW_FLOOR.get(id, 0.0) - 0.01
		)
		var top := box.end.y
		if id == PRIZE_CAR_ID:
			# The podium is drawn with its car, so its top is the drawn node's.
			var node := BuildView.make_object_node(def, null)
			top = _node_box(node).end.y
			node.free()
		print(
			"%s: bounds %s, footprint %s, height %s, top %s" % [id, box, def.size, def.height, top]
		)
		assert_float(def.height).override_failure_message(str(id)).is_between(
			top - 0.001, top + HEIGHT_SLACK
		)


func test_the_chain_is_three_cells_with_a_post_in_each_outer_cell() -> void:
	# The piece starts on a post (the glb origin) and reaches the next one 2 m
	# on; the 1 m back offset puts the posts on the centres of the outer cells.
	var def := BuildCatalog.get_def(&"metal_pole_chain")
	assert_vector(Vector2(def.size)).is_equal(Vector2(1, 3))
	assert_vector(InteriorKit.object_offset(&"metal_pole_chain")).is_equal(Vector3(0, 0, -1.0))
	var box := _bounds(&"metal_pole_chain")
	assert_float(box.position.z).is_greater_equal(-1.0)
	assert_float(box.end.z).is_less_equal(1.0)
	assert_float(box.size.z).is_greater(1.5)


## The chain reserves its whole span: nothing else goes in a cell it covers,
## and a wall cannot cut across it. BuildGrid refuses a wall only on an edge
## inside one footprint (it does not refuse a wall along the footprint's outer
## edge, for any object), so the chain's two inner edges are the walls tested.
func test_the_grid_reserves_every_cell_of_the_chain() -> void:
	var grid := BuildGrid.new(Vector2i(10, 10))
	var floors: Array[BuildEdit] = []
	for y in 10:
		for x in 10:
			floors.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(floors)
	var origin := Vector2i(4, 4)
	var chain := grid.apply(BuildEdit.place_object(&"metal_pole_chain", origin, 0))
	assert_bool(chain.ok).is_true()
	for y in 3:
		var cell := origin + Vector2i(0, y)
		var other := grid.apply(BuildEdit.place_object(&"metal_pole", cell, 0))
		assert_bool(other.ok).override_failure_message("pole on %s" % cell).is_false()
		assert_int(other.reason).is_equal(BuildResult.Reason.OVERLAP)
	# A pole beside the chain is fine.
	var beside := grid.apply(BuildEdit.place_object(&"metal_pole", origin + Vector2i(1, 1), 0))
	assert_bool(beside.ok).is_true()
	for y in [0, 1]:
		var wall := grid.apply(
			BuildEdit.place_wall(
				origin + Vector2i(0, y), BuildGrid.Side.SOUTH, BuildGrid.WallKind.PLAIN
			)
		)
		assert_bool(wall.ok).override_failure_message("wall in the chain, row %d" % y).is_false()
		assert_int(wall.reason).is_equal(BuildResult.Reason.WALL_IN_FOOTPRINT)


func test_interaction_offsets_match_the_models_use_mounts() -> void:
	for id in _new_ids:
		var def := BuildCatalog.get_def(id)
		var piece := InteriorKit.object_piece(id)
		var xf: Variant = null
		for mount_name in USE_MOUNTS:
			var found: Variant = _mount(piece, mount_name)
			if found != null:
				assert_object(xf).override_failure_message("%s has two use mounts" % id).is_null()
				xf = found
		assert_bool(def.has_interaction).override_failure_message(str(id)).is_equal(xf != null)
		if xf == null:
			continue
		var at: Vector3 = (xf as Transform3D).origin
		var cell := Vector2i(
			floori(at.x + def.size.x / 2.0 + 0.0), floori(at.z + def.size.y / 2.0 + 0.0)
		)
		print("%s: use mount %s -> cell %s, offset %s" % [id, at, cell, def.interaction_offset])
		assert_vector(Vector2(def.interaction_offset)).override_failure_message(str(id)).is_equal(
			Vector2(cell)
		)
		# The interaction cell lies outside the footprint.
		var inside := cell.x >= 0 and cell.y >= 0 and cell.x < def.size.x and cell.y < def.size.y
		assert_bool(inside).override_failure_message(str(id)).is_false()


## The node the build view draws for a podium: BuildView.make_object_node()
## holds the car, standing at the podium's Mount_Car and turned the way the
## mount points (the car's nose is its +Z).
func test_the_podium_node_holds_the_car_at_the_car_mount() -> void:
	var def := BuildCatalog.get_def(PRIZE_CAR_ID)
	var node := BuildView.make_object_node(def, null)
	var car := _car_child(node)
	assert_object(car).is_not_null()
	var mount: Transform3D = _mount(InteriorKit.object_piece(PRIZE_CAR_ID), "Mount_Car")
	assert_bool(car.transform.is_equal_approx(mount.orthonormalized())).is_true()
	assert_vector(car.transform.basis.z).is_equal_approx(mount.basis.z, Vector3.ONE * 0.001)
	var placed := _node_box(car)
	var box := car.transform * placed
	var half := Vector2(def.size) / 2.0
	print("car on podium: %s in footprint %s" % [box, def.size])
	assert_float(box.position.x).is_greater_equal(-half.x)
	assert_float(box.end.x).is_less_equal(half.x)
	assert_float(box.position.z).is_greater_equal(-half.y)
	assert_float(box.end.z).is_less_equal(half.y)
	assert_float(box.position.y).is_greater_equal(mount.origin.y - 0.01)
	node.free()


## A ghost wears its one material on the car too.
func test_the_ghost_podium_tints_the_car() -> void:
	var ghost := StandardMaterial3D.new()
	var node := BuildView.make_object_node(BuildCatalog.get_def(PRIZE_CAR_ID), ghost)
	var car := _car_child(node)
	assert_object(car).is_not_null()
	var meshes := car.find_children("*", "MeshInstance3D", true, false)
	assert_int(meshes.size()).is_greater(0)
	for mi in meshes:
		assert_object((mi as MeshInstance3D).material_override).is_same(ghost)
	node.free()


## The car's root node under a drawn podium, found by the .glb it came from.
func _car_child(node: Node3D) -> Node3D:
	var path := InteriorKit.piece_path(InteriorKit.PRIZE_CAR_PIECE)
	for child in node.get_children():
		if child.scene_file_path == path:
			return child as Node3D
	return null


## The bounds of every mesh under `root`, in root's own frame.
func _node_box(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var xf := (mi as MeshInstance3D).transform
		var parent := mi.get_parent()
		while parent != root:
			xf = (parent as Node3D).transform * xf
			parent = parent.get_parent()
		var part_box: AABB = xf * (mi as MeshInstance3D).get_aabb()
		box = part_box if first else box.merge(part_box)
		first = false
	return box
