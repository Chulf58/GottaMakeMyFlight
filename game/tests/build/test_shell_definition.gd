class_name TestShellDefinition
extends GdUnitTestSuite
## The authored Toon terminal shell definition against the shell .glb it
## describes: its grid frame fits inside the shell's walls, each door
## connection sits on its Doorway_n (same x, the doorway just beyond the
## grid edge, the same outward direction) and each outside route starts or
## ends at that doorway. main.tscn hands the definition to BuildMode and puts
## the camera's Home on the building's centre.

const SHELL := "res://build/toon_terminal_shell.tres"
const SHELL_GLB := "res://assets/buildings/tp_airport_shell.glb"
const MAIN := "res://main/main.tscn"
const PLANE_DOOR := Vector2(-14.5, -106.5)
## The road's near kerb (Road node, z -60.33 to -40).
const ROAD_KERB_Z := -60.3
## Landside letters west to east, airside letters east to west (finding
## does-the-toon-terminal-building-game-assets-buildings-tp-air).
const LANDSIDE_LETTERS := {-26: "A", -17: "B", 16: "C", 25: "D"}
const AIRSIDE_LETTERS := {25: "A", 16: "B", -17: "C", -26: "D"}

var _shell: ShellDefinition
var _shell_scene: Node3D
var _main_shell: Resource
var _home: Vector3


func before() -> void:
	_shell = load(SHELL)
	# Read main.tscn without instantiating it (its nodes make children in _ready).
	var state := (load(MAIN) as PackedScene).get_state()
	var at: Transform3D = (
		_scene_value(state, "Airside", "transform", Transform3D.IDENTITY)
		* _scene_value(state, "Airside/Terminal", "transform", Transform3D.IDENTITY)
	)
	_main_shell = _scene_value(state, "BuildMode", "shell", null)
	_home = _scene_value(state, "TycoonCamera", "home_position", Vector3.ZERO)
	_shell_scene = load(SHELL_GLB).instantiate()
	_shell_scene.transform = at
	add_child(_shell_scene)


func after() -> void:
	_shell_scene.free()


## A property main.tscn sets on the node at `path` (relative to Main), or
## `fallback` when the scene leaves it at its default.
func _scene_value(state: SceneState, path: String, property: String, fallback: Variant) -> Variant:
	for i in state.get_node_count():
		if str(state.get_node_path(i)) != "./" + path:
			continue
		for j in state.get_node_property_count(i):
			if state.get_node_property_name(i, j) == property:
				return state.get_node_property_value(i, j)
	return fallback


func _doorway(n: int) -> Node3D:
	return _shell_scene.find_child("Doorway_%d" % n, true, false) as Node3D


func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func test_the_grid_frame_is_66_by_30_inside_the_shell_walls() -> void:
	assert_object(_shell).is_not_null()
	assert_vector(_shell.grid_origin).is_equal_approx(
		Vector3(-33.5, 0.32, -94.8), Vector3.ONE * 1e-4
	)
	assert_vector(_shell.grid_size).is_equal(Vector2i(66, 30))
	# Inner wall faces measured on the shell: x -33.69..32.69, z -95.0..-64.6.
	var far := _shell.grid_origin + Vector3(_shell.grid_size.x, 0.0, _shell.grid_size.y)
	print("FRAME origin=%s far=%s" % [_shell.grid_origin, far])
	assert_float(_shell.grid_origin.x).is_greater(-33.69)
	assert_float(_shell.grid_origin.z).is_greater(-95.0)
	assert_float(far.x).is_less(32.69)
	assert_float(far.z).is_less(-64.6)
	assert_vector(_shell.centre()).is_equal_approx(Vector3(-0.5, 0.32, -79.8), Vector3.ONE * 1e-4)


func test_there_are_four_landside_and_four_airside_doors_lettered_a_to_d() -> void:
	var seen := {}
	var letters := {ShellDoorConnection.Kind.LANDSIDE: [], ShellDoorConnection.Kind.AIRSIDE: []}
	for c in _shell.connections:
		seen[c.doorway] = true
		(letters[c.kind] as Array).append(c.label)
	assert_int(seen.size()).is_equal(8)
	for kind in letters:
		var got: Array = letters[kind]
		got.sort()
		assert_array(got).is_equal(["A", "B", "C", "D"])


func test_each_connection_sits_on_its_toon_doorway() -> void:
	var grid := BuildGrid.new(_shell.grid_size, _shell.grid_origin)
	var checked := 0
	for c in _shell.connections:
		var marker := _doorway(c.doorway)
		assert_object(marker).is_not_null()
		var extras: Dictionary = marker.get_meta("extras")
		var out := DoorPlacement.back_step(c.facing)
		var outward: Array = extras["outward"]
		assert_vector(Vector2(outward[0], outward[2])).is_equal(Vector2(out))
		assert_bool(grid.in_bounds(c.cell)).is_true()
		assert_bool(grid.in_bounds(c.cell + out)).is_false()
		var centre := _xz(grid.cell_to_world(c.cell))
		var door := _xz(marker.global_position)
		var along := (door - centre).dot(Vector2(out))
		var lateral := absf((door - centre).dot(Vector2(out.y, -out.x)))
		print(
			(
				"DOOR %d %s cell=%s centre=%s doorway=%s along=%.3f lateral=%.3f"
				% [c.doorway, c.label, c.cell, centre, door, along, lateral]
			)
		)
		assert_float(lateral).is_less(0.05)
		# The doorway is 0.45 m past the grid edge, so 0.95 m past the centre.
		assert_float(along).is_between(0.9, 1.0)
		var landside: bool = out.y > 0
		var kind := (
			ShellDoorConnection.Kind.LANDSIDE if landside else ShellDoorConnection.Kind.AIRSIDE
		)
		assert_int(c.kind).is_equal(kind)
		var letters: Dictionary = LANDSIDE_LETTERS if landside else AIRSIDE_LETTERS
		assert_str(c.label).is_equal(letters[roundi(door.x)])
		checked += 1
	assert_int(checked).is_equal(8)


func test_each_route_meets_its_doorway_and_the_road_or_the_plane() -> void:
	for c in _shell.connections:
		var door := _xz(_doorway(c.doorway).global_position)
		assert_int(c.route.size()).is_greater_equal(2)
		var first := _xz(c.route[0])
		var last := _xz(c.route[c.route.size() - 1])
		if c.kind == ShellDoorConnection.Kind.LANDSIDE:
			assert_float(last.distance_to(door)).is_less(0.05)
			assert_float(first.y).is_greater(ROAD_KERB_Z)
		else:
			assert_float(first.distance_to(door)).is_less(0.05)
			assert_float(last.distance_to(PLANE_DOOR)).is_less(0.01)
		for point in c.route:
			assert_float(point.y).is_between(0.0, 0.6)


func test_main_scene_gives_build_mode_the_shell_and_homes_on_its_centre() -> void:
	assert_object(_main_shell).is_not_null()
	assert_str(_main_shell.resource_path).is_equal(SHELL)
	# TycoonCamera keeps its focus on y 0, so only x and z are the building's.
	assert_vector(_xz(_home)).is_equal_approx(_xz(_shell.centre()), Vector2.ONE * 1e-4)
