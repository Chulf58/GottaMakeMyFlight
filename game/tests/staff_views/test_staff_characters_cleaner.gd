class_name TestStaffCharactersCleaner
extends GdUnitTestSuite
## A cleaner is drawn with its own body (CLEANER_BODY): walking with the walk
## clip to its job, then the clean clip at work,
## side-on to a bin it empties from the cell beside it, never asking for a
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


func test_the_cleaner_body_is_no_passenger_and_no_other_staff_body() -> void:
	var body := StaffCharacters.CHARACTERS[CLEANER].resource_path
	var stem := body.get_file().get_basename()
	var player := StaffCharacters.CHARACTERS[CLEANER].instantiate().get_node("AnimationPlayer")
	var clean := (player as AnimationPlayer).get_animation(StaffCharacters.CLEAN_CLIP)
	var mode := clean.loop_mode if clean != null else -1
	print("cleaner body %s, clean clip %.2f s, loop mode %d" % [stem, clean.length, mode])
	player.get_parent().free()
	for role in [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY, StaffMember.Role.SHOP]:
		assert_str(StaffCharacters.CHARACTERS[role].resource_path).is_not_equal(body)
	assert_bool(PassengerLooks.BODIES.has(stem)).is_false()
	assert_float(clean.length).is_greater(1.0)
	# StaffCharacters._ready (this suite's views) plays it forward and back.
	assert_int(mode).is_equal(Animation.LOOP_PINGPONG)


func test_a_cleaner_walks_to_a_full_bin_and_empties_it_facing_it_in_cleaner_mode() -> void:
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
	_views.draw()
	var ahead := BIN_AT - m.at
	var facing := atan2(ahead.x, ahead.y)
	var mod := node.find_children("*", "StaffStationPose", true, false)[0] as StaffStationPose
	print(
		(
			"body %s, walking clip %s; emptying from %s clip %s yaw %.3f (to the bin %.3f) sub %d"
			% [
				node.scene_file_path,
				walking,
				m.at,
				_clip(node),
				node.rotation.y,
				facing,
				mod.sub_mode,
			]
		)
	)
	assert_str(node.scene_file_path).is_equal(StaffCharacters.CHARACTERS[CLEANER].resource_path)
	assert_str(walking).is_equal("walk")
	assert_str(_clip(node)).is_equal("idle")
	assert_that(ahead).is_not_equal(Vector2i.ZERO)
	# Mode.CLEANER (SubMode.CLEANER_BIN) faces the bin upright on idle clip.
	assert_float(absf(angle_difference(node.rotation.y, facing))).is_equal_approx(0.0, 0.001)
	assert_int(mod.mode).is_equal(StaffStationPose.Mode.CLEANER)
	assert_int(mod.sub_mode).is_equal(StaffStationPose.SubMode.CLEANER_BIN)
