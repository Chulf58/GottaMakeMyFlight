class_name TestKioskPieces
extends GdUnitTestSuite
## The kiosk pieces against their kit .glb files (Boredom 5/5, build_kiosk_kit.py):
## InteriorKit draws kiosk_counter, kiosk_display and the screen stand with
## their own pieces (the screen's picture to the front); at
## every facing the counter's interaction cell is its Mount_Till, and in a ready
## kiosk room each ShopLayout browse slot is the display's Mount_Browse_<index>,
## approach cell and facing alike. A blocked slot 1 leaves slot 0 on its mount.

const GRID := Vector2i(16, 16)
const ROOM := Rect2i(4, 4, 6, 6)
const COUNTER_ANCHOR := Vector2i(5, 5)
const DISPLAY_ANCHOR := Vector2i(7, 7)
## Mount positions are authored to the millimetre.
const EPS := 0.002

var _counter_mounts: Dictionary = {}
var _display_mounts: Dictionary = {}


func before() -> void:
	_counter_mounts = _mounts("res://assets/interior/kiosk_counter.glb")
	_display_mounts = _mounts("res://assets/interior/kiosk_display.glb")


## Mount name -> its transform relative to the piece root.
func _mounts(path: String) -> Dictionary:
	var root := (load(path) as PackedScene).instantiate() as Node3D
	var out := {}
	for node in root.find_children("Mount_*", "Node3D", true, false):
		var local := (node as Node3D).transform
		var parent := node.get_parent()
		while parent != root:
			local = (parent as Node3D).transform * local
			parent = parent.get_parent()
		out[node.name] = local
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


## A ready kiosk room: the counter at facing 0 in its north-west corner and
## the display at `facing`. Returns the display's object id.
func _kiosk(grid: BuildGrid, facing: int) -> int:
	assert_bool(grid.apply(BuildEdit.place_room(ROOM, &"kiosk")).ok).is_true()
	var counter := BuildEdit.place_object(&"kiosk_counter", COUNTER_ANCHOR, 0)
	assert_bool(grid.apply(counter).ok).is_true()
	var result := grid.apply(BuildEdit.place_object(&"kiosk_display", DISPLAY_ANCHOR, facing))
	assert_bool(result.ok).override_failure_message("display facing %d" % facing).is_true()
	return result.object_id


func _piece_transform(
	grid: BuildGrid, def_id: StringName, anchor: Vector2i, facing: int
) -> Transform3D:
	var def := BuildCatalog.get_def(def_id)
	return BuildView.object_transform(grid, def.footprint(anchor, facing), facing)


## The slot's approach cell centre and facing against the display's mount.
func _assert_slot_on_mount(grid: BuildGrid, slot: Dictionary, facing: int) -> void:
	var piece := _piece_transform(grid, &"kiosk_display", DISPLAY_ANCHOR, facing)
	var mount: Transform3D = piece * _display_mounts["Mount_Browse_%d" % slot["index"]]
	var centre := grid.cell_to_world(slot["approach"])
	var info := (
		"facing %d slot %d at %s, mount at %s" % [facing, slot["index"], centre, mount.origin]
	)
	assert_float(centre.distance_to(mount.origin)).override_failure_message(info).is_less(EPS)
	var looks: Vector2i = slot["facing"]
	var ahead := mount.basis.z.normalized()
	assert_float(ahead.distance_to(Vector3(looks.x, 0.0, looks.y))).is_less(EPS)


func test_the_kit_draws_the_kiosk_pieces_with_their_own_glbs() -> void:
	for def_id: StringName in [&"kiosk_counter", &"kiosk_display"]:
		var piece := InteriorKit.object_piece(def_id)
		assert_str(piece).is_equal(str(def_id))
		assert_bool(ResourceLoader.exists(InteriorKit.PIECE_PATH % piece)).is_true()
		var top := BuildView.pick_height(BuildCatalog.get_def(def_id))
		print("%s pick height %.3f" % [def_id, top])
		# The drawn mesh is taller than the catalog's stand-in box.
		assert_float(top).is_greater(BuildCatalog.get_def(def_id).height)
	assert_array(_counter_mounts.keys()).contains(["Mount_Till"])
	assert_array(_display_mounts.keys()).contains(["Mount_Browse_0", "Mount_Browse_1"])


func test_the_kit_draws_the_screen_stand_with_its_own_glb() -> void:
	var piece := InteriorKit.object_piece(ScreenCoverage.SCREEN_ID)
	assert_str(piece).is_equal("screen_stand")
	assert_bool(ResourceLoader.exists(InteriorKit.PIECE_PATH % piece)).is_true()
	# Its picture is the separate Screen_Face node, facing the front (+Z), the way
	# its coverage fan points.
	var root := InteriorKit.instantiate(piece)
	var face := root.find_child("Screen_Face", true, false) as Node3D
	assert_object(face).is_not_null()
	var bounds := AABB()
	for mi in face.find_children("*", "MeshInstance3D", true, false):
		bounds = (mi as MeshInstance3D).get_aabb()
	print("screen face aabb %s" % bounds)
	assert_float(bounds.position.z).is_greater(0.0)
	assert_float(bounds.size.x).is_greater(0.7)
	root.free()


## The importer bound every surface to a shared toon material (the glTF carries
## no images).
func test_every_kiosk_and_screen_surface_has_a_toon_material() -> void:
	for piece in ["kiosk_counter", "kiosk_display", "screen_stand"]:
		var surfaces := 0
		for part in InteriorKit.meshes(piece):
			var mesh := part[0] as Mesh
			for i in mesh.get_surface_count():
				var material := mesh.surface_get_material(i)
				assert_object(material).override_failure_message(piece).is_not_null()
				assert_str(material.resource_path).starts_with("res://assets/materials/")
				surfaces += 1
		print("%s surfaces %d" % [piece, surfaces])
		assert_int(surfaces).is_greater(0)


func test_the_till_spot_matches_its_mount_at_every_facing() -> void:
	var grid := _floored()
	var def := BuildCatalog.get_def(&"kiosk_counter")
	for facing in 4:
		var piece := _piece_transform(grid, &"kiosk_counter", COUNTER_ANCHOR, facing)
		var mount: Transform3D = piece * _counter_mounts["Mount_Till"]
		var spot := def.interaction_cell(COUNTER_ANCHOR, facing)
		var centre := grid.cell_to_world(spot)
		var info := "facing %d spot %s mount %s" % [facing, centre, mount.origin]
		assert_float(centre.distance_to(mount.origin)).override_failure_message(info).is_less(EPS)
		# Standing on the spot, the passenger faces the counter, straight back
		# against the counter's front.
		var ahead := mount.basis.z.normalized()
		var front := TerminalLayout.front_of(facing)
		assert_float(ahead.distance_to(-Vector3(front.x, 0.0, front.y))).is_less(EPS)
		var counter_cell := spot + Vector2i(roundi(ahead.x), roundi(ahead.z))
		assert_bool(def.footprint(COUNTER_ANCHOR, facing).has(counter_cell)).is_true()


func test_each_browse_slot_matches_its_mount_at_every_facing() -> void:
	for facing in 4:
		var grid := _floored()
		var display := _kiosk(grid, facing)
		var layout := ShopLayout.new()
		layout.rebuild(grid)
		assert_int(layout.shops.size()).override_failure_message("facing %d" % facing).is_equal(1)
		var slots: Array = layout.shops[0]["slots"]
		assert_int(slots.size()).is_equal(2)
		for i in slots.size():
			assert_int(slots[i]["display"]).is_equal(display)
			assert_int(slots[i]["index"]).is_equal(i)
			_assert_slot_on_mount(grid, slots[i], facing)
		# Slot 0 is the display's interaction cell.
		assert_vector(slots[0]["approach"]).is_equal(grid.interaction_cell(display))


func test_a_blocked_slot_one_leaves_slot_zero_on_its_mount() -> void:
	for facing in 4:
		var grid := _floored()
		var display := _kiosk(grid, facing)
		var layout := ShopLayout.new()
		layout.rebuild(grid)
		var blocked: Vector2i = layout.slot(display, 1)["approach"]
		assert_bool(grid.apply(BuildEdit.place_object(&"tray_table", blocked, 0)).ok).is_true()
		layout.rebuild(grid)
		var slots: Array = layout.shops[0]["slots"]
		assert_int(slots.size()).override_failure_message("facing %d" % facing).is_equal(1)
		assert_int(slots[0]["index"]).is_equal(0)
		assert_bool(layout.slot(display, 1).is_empty()).is_true()
		_assert_slot_on_mount(grid, slots[0], facing)
