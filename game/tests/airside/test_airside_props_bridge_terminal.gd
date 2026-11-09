class_name TestAirsidePropsBridgeTerminal
extends GdUnitTestSuite
## The nose-loader bridge against a real terminal (board 0adca5c6): the
## starter shell built on a SiteGrid, drawn by the real BuildView (walls and
## the exit door piece) and RoofView (the 5.2 m roof, its 0.25 m overhang and
## the fascia down to 2.3 m), the bridge laid out by the real Airside.
##
## Checks: Mount_ExitSill lies on the drawn exit door piece; the collar and the
## vestibule face stand exactly COLLAR_GAP_M and BOX_GAP_M off the wall line;
## no bridge mesh cuts a terminal mesh docked at any docking model, with plane
## 03 at the gate or with none; a gate at the east end of the north wall cuts
## nothing; and two gates at the minimum exit spacing (StandPlacement.
## EXIT_SPACING_CELLS, 19 m; decision stand-envelopes-and-gate-max-class-as-
## built-per-class-swing), each with its own plane reporting under its own key,
## keep their bridges and planes apart, both ways.
##
## Controls, each a positive count: the bridge moved 0.5 m into the wall cuts
## the terminal; the two gates 2 m apart meet; a neighbour plane moved onto
## the bridge meets it.

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
			"fixture: exit cell %s stand %s, north wall east end %s, roofed cells %d"
			% [_exit_cell, _stand, _east_cell, roof.roofed_cell_count()]
		)
	)


func after() -> void:
	_airside.free()
	_terminal.free()


func test_the_bridge_meets_the_exit_door_and_clears_the_terminal() -> void:
	assert_bool(_airside.set_gate_stands({"A": _stand})).is_true()
	var entry: Dictionary = _airside.props.bridges["A"]
	var bridge: Node3D = entry["node"]
	var door := _terminal.find_child(String(EXIT_DEF), true, false) as Node3D
	assert_object(door).is_not_null()
	var piece := door.get_child(0) as Node3D
	var sill := (bridge.find_child("Mount_ExitSill", true, false) as Node3D).global_position
	var flat := Vector2(sill.x, sill.z).distance_to(
		Vector2(piece.global_position.x, piece.global_position.z)
	)
	print(
		(
			"door piece at %s, exit sill %s: %.4f m apart on the ground"
			% [piece.global_position, sill, flat]
		)
	)
	assert_float(flat).is_less(0.001)
	# The faces toward the terminal: the collar nearest the wall, the
	# vestibule's face beside it above the collar.
	var wall := float(_stand["wall_z"])
	var body := bridge.find_child("JetBridge_Body", true, false) as MeshInstance3D
	var collar := -INF
	var face := -INF
	for v in body.mesh.get_faces():
		var w := body.global_transform * v
		collar = maxf(collar, w.z)
		if w.y - sill.y > JetBridgePose.CAB_TOP + 0.5:
			face = maxf(face, w.z)
	print(
		"collar %.4f m and vestibule face %.4f m off the wall line" % [wall - collar, wall - face]
	)
	assert_float(wall - collar).is_equal_approx(JetBridgePose.COLLAR_GAP_M, 0.001)
	assert_float(wall - face).is_equal_approx(JetBridgePose.BOX_GAP_M, 0.001)
	for model: String in [""] + MODELS:
		var plane := _park(model, _stand, "A", 1)
		var cut := Kit.crossings(bridge, _terminal)
		print(
			(
				"%s: docked %s, bridge into terminal %d crossings (%s)"
				% [_name(model), entry["docked"], cut["count"], cut["meshes"]]
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


## A gate on the east end of the north wall: the bridge cuts no terminal mesh,
## docked or parked.
func test_a_gate_at_the_east_end_of_the_wall_cuts_nothing() -> void:
	var stand := StandPlacement.for_cell(_grid, _east_cell, 99)
	assert_bool(_airside.set_gate_stands({"E": stand})).is_true()
	var entry: Dictionary = _airside.props.bridges["E"]
	var bridge: Node3D = entry["node"]
	print(
		(
			"east-end gate at %s (wall ends at x %.2f)"
			% [stand, _grid.cell_to_world(_east_cell).x + 0.5]
		)
	)
	for model: String in [""] + MODELS:
		var plane := _park(model, stand, "E", 1)
		var cut := Kit.crossings(bridge, _terminal)
		print(
			(
				"%s: docked %s; into terminal %d (%s)"
				% [_name(model), entry["docked"], cut["count"], cut["meshes"]]
			)
		)
		assert_int(cut["count"]).is_equal(0)
		_free(plane)


## Two gates at the minimum exit spacing, each plane reporting under its own
## key: neither bridge meets the other, and neither bridge meets the
## neighbour's plane, docked or parked.
func test_two_gates_at_the_minimum_spacing_keep_apart() -> void:
	var gap := StandPlacement.EXIT_SPACING_CELLS
	var east := StandPlacement.for_cell(_grid, _exit_cell + Vector2i(gap, 0), 97)
	assert_bool(_airside.set_gate_stands({"A": _stand, "B": east})).is_true()
	var a: Dictionary = _airside.props.bridges["A"]
	var b: Dictionary = _airside.props.bridges["B"]
	for model: String in [""] + MODELS:
		var plane_a := _park(model, _stand, "A", 1)
		var plane_b := _park(model, east, "B", 2)
		var bridges := Kit.crossings(a["node"], b["node"])
		var a_on_b: int = 0 if plane_b == null else Kit.crossings(a["node"], plane_b)["count"]
		var b_on_a: int = 0 if plane_a == null else Kit.crossings(b["node"], plane_a)["count"]
		print(
			(
				(
					"%s at both stands %d m apart: A docked %s, B docked %s; bridges %d, bridge A on"
					+ " plane B %d, bridge B on plane A %d"
				)
				% [_name(model), gap, a["docked"], b["docked"], bridges["count"], a_on_b, b_on_a]
			)
		)
		if JetBridgePose.docks(model):
			assert_bool(a["docked"] and b["docked"]).is_true()
		assert_int(bridges["count"]).is_equal(0)
		assert_int(a_on_b).is_equal(0)
		assert_int(b_on_a).is_equal(0)
		if model == "tp_plane_05a":
			# Control: plane B moved onto bridge A meets it.
			var holder := plane_b.get_parent() as Node3D
			var shift: Vector3 = a["node"].global_position - b["node"].global_position
			holder.position += shift
			var met := Kit.crossings(a["node"], plane_b)
			holder.position -= shift
			print(
				(
					"control: plane B moved %s onto gate A, bridge A meets it %d"
					% [shift, met["count"]]
				)
			)
			assert_int(met["count"]).is_greater(0)
		_free(plane_a)
		_free(plane_b)
	# Control: 2 m apart the two bridges meet.
	var node_b: Node3D = b["node"]
	node_b.position.x -= gap - 2.0
	var close := Kit.crossings(a["node"], node_b)
	node_b.position.x += gap - 2.0
	print("control: 2 m apart, %d crossings" % close["count"])
	assert_int(close["count"]).is_greater(0)


## Plane `model` parked at `stand`, reporting gate `gate` under `key` as in
## BOARDING; null for "".
func _park(model: String, stand: Dictionary, gate: String, key: int) -> Node3D:
	if model == "":
		return null
	var at := StandPlacement.stand_point(stand)
	var pose := Transform3D(Basis.IDENTITY, at + Vector3.UP * PlaneView.ground_height_at(at))
	var plane := Kit.posed_model(self, model, pose, at, Vector3.BACK)
	var props := PlaneProps.new()
	plane.get_parent().add_child(props)
	props.follow(true, plane, model, FlightSim.State.BOARDING, gate, _airside, key)
	return plane


func _free(plane: Node3D) -> void:
	if plane != null:
		plane.get_parent().free()


func _name(model: String) -> String:
	return model if model != "" else "parked"
