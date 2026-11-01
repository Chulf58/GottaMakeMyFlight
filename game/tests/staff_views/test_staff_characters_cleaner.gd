class_name TestStaffCharactersCleaner
extends GdUnitTestSuite
## A cleaner is drawn with an existing staff body (the officer's, until its
## own model comes): walking with the walk clip to its job, then idle at work,
## facing a bin it empties from the cell beside it, never asking for a
## station's post yaw.

const CLEANER := StaffMember.Role.CLEANER
const BIN_AT := Vector2i(12, 10)

var _w: PassengerTestWorld
var _views: StaffCharacters


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_w = MessTestKit.open_world()
	_views = StaffCharacters.new()
	_views.clock = _w.clock
	_views.staff = _w.staff
	add_child(_views)


func after_test() -> void:
	_views.free()
	_w.free_all()


func _clip(node: Node3D) -> String:
	return (node.get_node("AnimationPlayer") as AnimationPlayer).current_animation


func test_a_cleaner_walks_to_a_full_bin_and_empties_it_facing_it() -> void:
	var bin := PassengerTestWorld.place(_w.grid, MessSim.BIN_ID, BIN_AT, 0)
	var data := _w.sim.messes.to_snapshot()
	data["bins"][str(bin)] = MessSim.BIN_CAPACITY
	assert_bool(_w.sim.messes.from_snapshot(data)).is_true()
	var m := CleanerTestKit.cleaner_at(_w, Vector2i(6, 16))
	_w.step()
	_w.step()
	var node := _views.node_for(m.id)
	assert_object(node).is_not_null()
	var walking := _clip(node)
	var at_work := func() -> bool: return m.state == StaffMember.State.ON_DUTY
	assert_bool(CleanerTestKit.step_until(_w, at_work)).is_true()
	_w.step()
	var ahead := BIN_AT - m.at
	var facing := atan2(ahead.x, ahead.y)
	print(
		(
			"body %s, walking clip %s; emptying from %s clip %s yaw %.3f (to the bin %.3f)"
			% [node.scene_file_path, walking, m.at, _clip(node), node.rotation.y, facing]
		)
	)
	assert_str(node.scene_file_path).is_equal(StaffCharacters.CHARACTERS[CLEANER].resource_path)
	assert_str(walking).is_equal("walk")
	assert_str(_clip(node)).is_equal("idle")
	assert_that(ahead).is_not_equal(Vector2i.ZERO)
	assert_float(node.rotation.y).is_equal_approx(facing, 0.001)
