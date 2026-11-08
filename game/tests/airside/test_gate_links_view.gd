class_name TestGateLinksView
extends GdUnitTestSuite
## The gate links view (Gates 2/4): each gate's line runs desk centre -> exit
## cell centre -> plane door, shown only in build mode with a disc at the door
## and a "Gate X" caption; an unlinked desk gets no line and, always, a sign
## with a caption naming why, in its own icon. The gate desk draws its own kit
## piece and its build card shows its own thumbnail.
##
## The site of test_gate_desks.gd: the starter shell with its exit at (20, 112)
## and a copy 44 cells east with its exit at (64, 112).

const SITE := preload("res://build/terminal_site.tres")
const EAST := Vector2i(44, 0)
const EXIT_WEST := Vector2i(20, 112)
const DESK_WEST := Vector2i(19, 115)
const DESK_EAST := DESK_WEST + EAST

var _grid: SiteGrid
var _flights: FlightSim
var _gates: GateDesks
var _view: GateLinksView


func before_test() -> void:
	_grid = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset)).is_true()
	for result in _grid.apply_batch(ReferenceTerminal.shell_edits(SITE.starter_offset + EAST)):
		assert_bool(result.ok).is_true()
	_flights = auto_free(FlightSim.new()) as FlightSim
	_flights.open_airport()
	_gates = auto_free(GateDesks.new()) as GateDesks
	_gates.bind(_grid, _flights)
	_grid.guard = _gates.edit_problem
	# In the tree, so the nodes a rebuild adds are not counted as orphans.
	_view = GateLinksView.new()
	add_child(_view)
	_view.bind(_grid, _gates)


func after_test() -> void:
	_view.free()


func _desk(at: Vector2i) -> BuildResult:
	return _grid.apply(BuildEdit.place_object(GateDesks.DESK, at, 0))


func test_a_link_runs_from_the_desk_to_its_exit_and_on_to_the_plane_door() -> void:
	var west := _desk(DESK_WEST)
	assert_bool(west.ok).is_true()
	var binding := _gates.bindings[0]
	var path := GateLinksView.link_points(_grid, binding)
	var desk_centre := (
		(_grid.cell_to_world(DESK_WEST) + _grid.cell_to_world(DESK_WEST + Vector2i.RIGHT)) / 2.0
	)
	var exit_centre := _grid.cell_to_world(EXIT_WEST)
	var door := StandPlacement.door_point(StandPlacement.for_exit(_grid, binding["exit"]))
	print("path %s; desk %s exit %s door %s" % [path, desk_centre, exit_centre, door])
	assert_int(path.size()).is_equal(3)
	var lift := _grid.origin.y + GateLinksView.LIFT_M
	# It starts on the desk's north edge (the footprint's z runs 115..116), on
	# the way from the footprint centre to the exit's centre: 0.5 of its 3 m
	# north, so 1/6 of its 0.5 m east.
	var edge := Vector3(desk_centre.x + 0.5 / 6.0, lift, _grid.origin.z + DESK_WEST.y)
	assert_vector(path[0]).is_equal_approx(edge, Vector3.ONE * 1e-4)
	assert_vector(path[1]).is_equal_approx(
		Vector3(exit_centre.x, lift, exit_centre.z), Vector3.ONE * 1e-4
	)
	assert_vector(path[2]).is_equal_approx(Vector3(door.x, lift, door.z), Vector3.ONE * 1e-4)
	# The door stands north of the exit (outside), straight out from it.
	assert_float(path[2].z).is_less(path[1].z)
	assert_float(path[2].x).is_equal_approx(path[1].x, 1e-4)
	assert_array(_view.paths()).is_equal([path])


func test_lines_ends_and_captions_show_only_in_build_mode() -> void:
	assert_bool(_desk(DESK_WEST).ok).is_true()
	assert_bool(_desk(DESK_EAST).ok).is_true()
	var texts := []
	for caption in _view.gate_captions():
		texts.append(caption.text)
	var mesh := _view.line_node().mesh as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	print(
		(
			"paths %d ends %d captions %s line vertices %d custom %d building %s"
			% [
				_view.paths().size(),
				_view.ends().size(),
				texts,
				verts.size(),
				custom.size(),
				_view.is_building()
			]
		)
	)
	assert_int(_view.paths().size()).is_equal(2)
	assert_int(_view.ends().size()).is_equal(2)
	# Each caption names its gate, then its biggest plane on a second line.
	assert_array(texts).is_equal(["Gate A\nup to large planes", "Gate B\nup to large planes"])
	# Two segments per gate, four corners per segment, each with its other end
	# and side in CUSTOM0.
	assert_int(verts.size()).is_equal(2 * 2 * 4)
	assert_int(custom.size()).is_equal(verts.size() * 4)
	# The faint pass through walls holds only each gate's exit -> door segment,
	# so it is never drawn across the desk.
	var through := (_view.through_node().mesh as ArrayMesh).surface_get_arrays(0)
	var through_verts: PackedVector3Array = through[Mesh.ARRAY_VERTEX]
	assert_int(through_verts.size()).is_equal(2 * 1 * 4)
	var path: PackedVector3Array = _view.paths()[0]
	assert_bool(through_verts.has(path[0])).is_false()
	assert_bool(through_verts.has(path[1])).is_false()
	assert_bool(through_verts.has(path[1].move_toward(path[2], 0.5))).is_true()
	assert_bool(through_verts.has(path[2])).is_true()
	assert_vector(_view.ends()[0].position).is_equal(_view.paths()[0][2])
	assert_bool(_view.is_building()).is_false()
	_view.set_building(true)
	assert_bool(_view.is_building()).is_true()
	_view.set_building(false)
	assert_bool(_view.is_building()).is_false()


func test_an_unlinked_desk_gets_a_sign_with_why_and_no_line() -> void:
	var west := _desk(DESK_WEST)
	assert_bool(_desk(DESK_EAST).ok).is_true()
	assert_int(_view.signs().size()).is_equal(0)
	assert_bool(_grid.apply(BuildEdit.remove_object(_grid.object_at(EXIT_WEST))).ok).is_true()
	var signs := _view.signs()
	var captions := []
	for marker in signs:
		captions.append(_view.caption_of(marker).text)
	print("signs %d captions %s paths %d" % [signs.size(), captions, _view.paths().size()])
	assert_int(signs.size()).is_equal(1)
	assert_int(signs[0].get_meta("desk")).is_equal(west.object_id)
	assert_array(captions).is_equal(["Unlinked: no north exit within 4 cells"])
	assert_int(_view.paths().size()).is_equal(1)
	# The sign shows outside build mode too (it is not under the links node),
	# over the desk's top.
	assert_bool(_view.is_building()).is_false()
	assert_bool(signs[0].visible and signs[0].get_parent() == _view).is_true()
	assert_float(signs[0].position.y).is_greater(BuildCatalog.get_def(GateDesks.DESK).height)
	# The exit comes back: the desk links again and its sign goes.
	assert_bool(_grid.apply(BuildEdit.place_object(&"exit_door", EXIT_WEST, 0)).ok).is_true()
	assert_int(_view.signs().size()).is_equal(0)
	assert_int(_view.paths().size()).is_equal(2)


func test_each_reason_has_its_own_caption() -> void:
	var texts := [
		GateLinksView.caption_for({"why": GateDesks.Unlinked.NO_EXIT, "gate": ""}),
		GateLinksView.caption_for({"why": GateDesks.Unlinked.EXIT_TAKEN, "gate": "B"}),
		GateLinksView.caption_for({"why": GateDesks.Unlinked.STAND_OVERLAP, "gate": "C"}),
		GateLinksView.caption_for({"why": GateDesks.Unlinked.NO_LETTER, "gate": ""}),
	]
	print("captions %s" % [texts])
	(
		assert_array(texts)
		. is_equal(
			[
				"Unlinked: no north exit within 4 cells",
				"Unlinked: Gate B uses the exit",
				"Unlinked: stand would overlap Gate C",
				"Unlinked: every gate letter is in use",
			]
		)
	)


func test_the_unlinked_icon_is_its_own_slate_sign() -> void:
	var icon := GateLinksView.unlinked_icon().get_image()
	var queue := MarkerIcons.queue_full_image()
	var half := MarkerIcons.SIZE / 2
	var differ := 0
	var white := 0
	for y in MarkerIcons.SIZE:
		for x in MarkerIcons.SIZE:
			var c := icon.get_pixel(x, y)
			if not c.is_equal_approx(queue.get_pixel(x, y)):
				differ += 1
			if c.a > 0.9 and c.r > 0.95 and c.g > 0.95 and c.b > 0.95:
				white += 1
	# A pixel inside the rounded square, away from the glyph: the slate fill.
	var fill := icon.get_pixel(half - 44, half + 40)
	print("differ %d white %d fill %s" % [differ, white, fill])
	assert_int(differ).is_greater(1000)
	assert_int(white).is_greater(300)
	assert_float(fill.r).is_equal_approx(MissMarkers.CLOSED_FILL.r, 0.02)
	assert_float(fill.b).is_equal_approx(MissMarkers.CLOSED_FILL.b, 0.02)


func test_the_gate_desk_draws_its_own_piece_and_card_thumbnail() -> void:
	assert_str(InteriorKit.object_piece(GateDesks.DESK)).is_equal("gate_desk")
	var parts := InteriorKit.meshes("gate_desk")
	var box := AABB()
	for i in parts.size():
		var part_box: AABB = (parts[i][1] as Transform3D) * (parts[i][0] as Mesh).get_aabb()
		box = part_box if i == 0 else box.merge(part_box)
	print("gate desk parts %d bounds %s" % [parts.size(), box])
	assert_int(parts.size()).is_equal(2)
	# Inside its 2x1 footprint less the 0.08 m furniture inset, up to the catalog
	# height.
	assert_float(box.position.x).is_greater_equal(-0.921)
	assert_float(box.end.x).is_less_equal(0.921)
	assert_float(box.position.z).is_greater_equal(-0.421)
	assert_float(box.end.z).is_less_equal(0.421)
	assert_float(box.end.y).is_equal_approx(BuildCatalog.get_def(GateDesks.DESK).height, 0.01)
	var item: Array = BuildMenu.ITEMS[BuildMode.Tool.GATE_DESK]
	assert_str(item[1]).is_equal("gate_desk")
	assert_bool(ResourceLoader.exists(BuildMenu.THUMBNAIL_DIR % item[1])).is_true()
	assert_bool(BuildMenu.PLACEHOLDER_THUMBNAILS.has(item[1])).is_false()


func test_the_apron_stand_shows_the_links_with_build_mode() -> void:
	var stand := auto_free(ApronStand.new()) as ApronStand
	var view := stand.links_view()
	assert_object(view).is_not_null()
	assert_bool(view.get_parent() == stand).is_true()
	stand.set_building(true)
	assert_bool(view.is_building()).is_true()
	stand.set_building(false)
	assert_bool(view.is_building()).is_false()
