class_name TestAirsidePropsBridgeTerminal
extends GdUnitTestSuite
## The jet bridge against a real terminal (board 0adca5c6, Sol review of
## 8c348ea): the starter shell built on a SiteGrid, drawn by the real
## BuildView (walls and the exit door piece) and RoofView (the 5.2 m roof, its
## 0.25 m overhang and the fascia down to 2.3 m), with the bridge laid out by
## the real Airside for the gate's stand.
##
## Checks: Mount_StairBottom lies on the drawn exit door's sill; the stair
## box's terminal face stands exactly BOX_GAP_M and its door collar
## COLLAR_GAP_M off the wall line; no bridge mesh cuts a terminal mesh in any
## pose the game uses. The corridor always runs east (conductor ruling for this
## round: no mirroring), so a gate at the east end of the north wall gets a
## corridor running past the wall's end: it must still cut no terminal mesh and
## meet no plane at its own stand or at the neighbouring stand one class
## spacing west (StandEnvelope.spacing_cells(), decision stand-envelopes-and-
## gate-max-class-as-built-per-class-swing). Two gates at the minimum exit
## spacing (StandPlacement.EXIT_SPACING_CELLS, 19 m) must not meet each
## other's stair box, corridor or bridge.
##
## Controls, each a positive count: the bridge moved 0.5 m into the wall cuts
## the terminal; the two gates 10 m apart meet; a plane moved onto the
## corridor meets it.

const Kit := preload("res://tests/airside/airside_props_kit.gd")
const SITE := preload("res://build/terminal_site.tres")
const MODELS: Array[String] = [
	"tp_plane_03a", "tp_plane_04a", "tp_plane_05a", "tp_plane_06a", "tp_plane_07a"
]
const EXIT_DEF := &"exit_door"

var _grid: SiteGrid
var _terminal: Node3D
var _airside: Airside
var _exit_cell := Vector2i.ZERO
var _east_cell := Vector2i.ZERO
var _stand: Dictionary = {}


func before() -> void:
	_grid = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset)).is_true()
	var exit_id := 0
	for id in _grid.object_ids():
		if StringName(_grid.get_object(id)["def"]) == EXIT_DEF:
			exit_id = id
	_stand = StandPlacement.for_exit(_grid, exit_id)
	assert_bool(_stand.is_empty()).is_false()
	_exit_cell = _grid.get_object(exit_id)["anchor"]
	# The east end of the exit's north wall.
	_east_cell = _exit_cell
	while _grid.has_wall(_east_cell + Vector2i(1, 0), BuildGrid.Side.NORTH):
		_east_cell += Vector2i(1, 0)
	_terminal = Node3D.new()
	_terminal.name = "Terminal"
	add_child(_terminal)
	var view := BuildView.new()
	_terminal.add_child(view)
	view.refresh(_grid)
	var roof := RoofView.new()
	_terminal.add_child(roof)
	roof.bind(_grid)
	_airside = Kit.airside_from_main()
	add_child(_airside)
	print(
		(
			(
				"fixture: exit cell %s stand %s, north wall east end %s (%d cells east),"
				+ " roofed cells %d, terminal triangles %d"
			)
			% [
				_exit_cell,
				_stand,
				_east_cell,
				_east_cell.x - _exit_cell.x,
				roof.roofed_cell_count(),
				Kit.world_tris(_terminal).size()
			]
		)
	)


func after() -> void:
	_airside.free()
	_terminal.free()


func test_the_stair_box_meets_the_exit_door_and_clears_the_terminal() -> void:
	assert_bool(_airside.set_gate_stands({"A": _stand})).is_true()
	var entry: Dictionary = _airside.props.bridges["A"]
	var bridge: Node3D = entry["node"]
	var door := _terminal.find_child(String(EXIT_DEF), true, false) as Node3D
	assert_object(door).is_not_null()
	var piece := door.get_child(0) as Node3D
	var sill := (bridge.find_child("Mount_StairBottom", true, false) as Node3D).global_position
	var flat := Vector2(sill.x, sill.z).distance_to(
		Vector2(piece.global_position.x, piece.global_position.z)
	)
	print(
		(
			"door piece at %s, stair sill %s: %.4f m apart on the ground"
			% [piece.global_position, sill, flat]
		)
	)
	assert_float(flat).is_less(0.01)
	# The terminal face: the collar nearest the wall, the box's wall face beside
	# it above the blue band (which stands 0.02 m proud at 2.5 to 2.8 m).
	var wall := float(_stand["wall_z"])
	var box := bridge.find_child("StairBox_Mesh", true, false) as MeshInstance3D
	var collar := -INF
	var face := -INF
	for v in box.mesh.get_faces():
		var w := box.global_transform * v
		collar = maxf(collar, w.z)
		if absf(w.x - sill.x) > 0.75 and w.y - sill.y > 3.0:
			face = maxf(face, w.z)
	print("collar %.4f m and box face %.4f m off the wall line" % [wall - collar, wall - face])
	assert_float(wall - collar).is_equal_approx(JetBridgePose.COLLAR_GAP_M, 0.002)
	assert_float(wall - face).is_equal_approx(JetBridgePose.BOX_GAP_M, 0.002)
	for model: String in [""] + MODELS:
		var plane := _park(model, _stand, "A")
		var cut := Kit.crossings(bridge, _terminal)
		print(
			(
				"%s: docked %s clear %s, bridge into terminal %d crossings (%s)"
				% [_name(model), entry["docked"], entry["clear"], cut["count"], cut["meshes"]]
			)
		)
		assert_int(cut["count"]).is_equal(0)
		_free(plane)
	# Control: the bridge 0.5 m into the wall.
	bridge.position.z += 0.5
	var into := Kit.crossings(bridge, _terminal)
	bridge.position.z -= 0.5
	print("control: 0.5 m into the wall, %d crossings (%s)" % [into["count"], into["meshes"]])
	assert_int(into["count"]).is_greater(0)


## Case (a): a gate at the east end of the north wall.
func test_a_gate_at_the_east_end_of_the_wall_cuts_nothing() -> void:
	var stand := StandPlacement.for_cell(_grid, _east_cell, 99)
	assert_bool(_airside.set_gate_stands({"E": stand})).is_true()
	var entry: Dictionary = _airside.props.bridges["E"]
	var bridge: Node3D = entry["node"]
	var box := bridge.find_child("StairBox_Mesh", true, false) as MeshInstance3D
	var reach := _aabb_of(bridge)
	print(
		(
			"east-end gate at %s: wall ends at x %.2f, bridge x %.2f..%.2f (%.2f m past the wall end)"
			% [
				stand,
				_grid.cell_to_world(_east_cell).x + 0.5,
				reach.position.x,
				reach.end.x,
				reach.end.x - (_grid.cell_to_world(_east_cell).x + 0.5)
			]
		)
	)
	for model: String in [""] + MODELS:
		var plane := _park(model, stand, "E")
		var cut := Kit.crossings(bridge, _terminal)
		var own := Kit.crossings(box, plane) if plane != null else {"count": 0, "meshes": []}
		print(
			(
				"%s: docked %s clear %s; into terminal %d (%s); stair box into own plane %d"
				% [
					_name(model),
					entry["docked"],
					entry["clear"],
					cut["count"],
					cut["meshes"],
					own["count"]
				]
			)
		)
		assert_int(cut["count"]).is_equal(0)
		assert_int(own["count"]).is_equal(0)
		_free(plane)
	# The neighbour one class spacing west, with that class's planes; the
	# east-end bridge parked.
	for model: String in MODELS:
		var spacing := StandEnvelope.spacing_cells(_class_of(model))
		var west := StandPlacement.for_cell(_grid, _east_cell - Vector2i(spacing, 0), 98)
		var neighbour := _place_plane(model, west)
		var met := Kit.crossings(bridge, neighbour)
		print(
			(
				"%s at the neighbour stand %d m west: east-end bridge meets it %d (%s)"
				% [model, spacing, met["count"], met["meshes"]]
			)
		)
		assert_int(met["count"]).is_equal(0)
		var holder := neighbour.get_parent() as Node3D
		if model == MODELS[0]:
			# Control, once: the same plane moved onto the corridor.
			var door: Vector3 = neighbour.global_transform * PlaneModels.PLANES[model]["doors"][0]
			var link := (bridge.find_child("Mount_Link", true, false) as Node3D).global_position
			holder.position += link - door
			var moved := Kit.crossings(bridge, neighbour)
			print("control: %s with its door on the corridor meets it %d" % [model, moved["count"]])
			assert_int(moved["count"]).is_greater(0)
		holder.free()


## Case (b): two gates at the minimum exit spacing.
func test_two_gates_at_the_minimum_spacing_keep_apart() -> void:
	var gap := StandPlacement.EXIT_SPACING_CELLS
	var east := StandPlacement.for_cell(_grid, _exit_cell + Vector2i(gap, 0), 97)
	assert_bool(_airside.set_gate_stands({"A": _stand, "B": east})).is_true()
	var a: Node3D = _airside.props.bridges["A"]["node"]
	var b: Node3D = _airside.props.bridges["B"]["node"]
	for model: String in [""] + MODELS:
		var plane_a := _park(model, _stand, "A")
		var plane_b := _park(model, east, "B")
		var met := Kit.crossings(a, b)
		var near := _aabb_of(a).end.x
		var far := _aabb_of(b).position.x
		print(
			(
				"%s at both stands %d m apart: bridge A x ..%.2f, bridge B x %.2f.. (%.2f m gap), %d crossings"
				% [_name(model), gap, near, far, far - near, met["count"]]
			)
		)
		assert_int(met["count"]).is_equal(0)
		_free(plane_a)
		_free(plane_b)
	# Control: 10 m apart the two corridors overlap.
	b.position.x -= gap - 10.0
	var close := Kit.crossings(a, b)
	b.position.x += gap - 10.0
	print("control: 10 m apart, %d crossings" % close["count"])
	assert_int(close["count"]).is_greater(0)


## Plane `model` parked at `stand`, reporting gate `gate` to the bridge as in
## BOARDING; null for "" (the bridge stays parked).
func _park(model: String, stand: Dictionary, gate: String) -> Node3D:
	if model == "":
		return null
	var plane := _place_plane(model, stand)
	var props := PlaneProps.new()
	plane.get_parent().add_child(props)
	props.follow(true, plane, model, FlightSim.State.BOARDING, gate, _airside, 1)
	return plane


func _place_plane(model: String, stand: Dictionary) -> Node3D:
	var at := StandPlacement.stand_point(stand)
	var pose := Transform3D(Basis.IDENTITY, at + Vector3.UP * PlaneView.ground_height_at(at))
	return Kit.posed_model(self, model, pose, at, Vector3.BACK)


func _free(plane: Node3D) -> void:
	if plane != null:
		plane.get_parent().free()


func _name(model: String) -> String:
	return model if model != "" else "parked"


func _class_of(model: String) -> String:
	for cls: String in PlaneClasses.CLASSES:
		if PlaneClasses.CLASSES[cls]["models"].has(model):
			return cls
	return PlaneClasses.LARGE


func _aabb_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for tri: Dictionary in Kit.world_tris(node):
		box = tri["box"] if first else box.merge(tri["box"])
		first = false
	return box
