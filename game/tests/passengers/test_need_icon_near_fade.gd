class_name TestNeedIconNearFade
extends GdUnitTestSuite
## A passenger's need icons fade out when the camera is very close to that
## passenger (decision passenger-need-icons-fade-out-when-the-camera-is-very-
## close, board 73e15dd7 part 6): the near-end match of the hide past the home
## zoom. Icons draw with no depth test, so close to the lens a row landed on
## another passenger's face.

var _world: PassengerTestWorld
var _views: PassengerViews
var _camera: Camera3D


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new()
	ToiletTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.fov = 55.0
	_camera.make_current()


func after_test() -> void:
	_camera.free()
	_views.free()
	_world.free_all()


## A passenger node with two icons shown.
func _hungry_node() -> Node3D:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.hunger = CafeSim.HUNGER_MAX
	p.toilet_need = ToiletSim.NEED_MAX
	_world.step()
	var node := _views.node_for(p.id)
	(node.get_node("Bubble") as Label3D).text = ""
	return node


## The camera `metres` from `node`, looking at it, and the node laid out.
func _lay_out_at(node: Node3D, metres: float) -> void:
	_camera.look_at_from_position(
		node.global_position + Vector3(0.0, 0.6, 1.0).normalized() * metres, node.global_position
	)
	var unit := NeedIcons.unit_of(get_viewport(), _camera)
	NeedIcons.layout(node, node.get_node("Bubble") as Label3D, _camera, unit)


func _sprite(node: Node3D, i: int) -> Sprite3D:
	return node.get_node(NeedIcons.SPRITES[i]) as Sprite3D


func test_the_near_alpha_is_zero_up_close_one_further_out_and_linear_between() -> void:
	assert_float(NeedIcons.near_alpha(0.0)).is_equal(0.0)
	assert_float(NeedIcons.near_alpha(NeedIcons.NEAR_HIDDEN_M)).is_equal(0.0)
	assert_float(NeedIcons.near_alpha(NeedIcons.NEAR_FULL_M)).is_equal(1.0)
	assert_float(NeedIcons.near_alpha(NeedIcons.NEAR_FULL_M * 3.0)).is_equal(1.0)
	var middle := (NeedIcons.NEAR_HIDDEN_M + NeedIcons.NEAR_FULL_M) / 2.0
	assert_float(NeedIcons.near_alpha(middle)).is_equal_approx(0.5, 0.0001)
	# A short fade, not a pop: a band of a few metres, and not an instant step.
	var band := NeedIcons.NEAR_FULL_M - NeedIcons.NEAR_HIDDEN_M
	assert_float(band).is_greater(0.5)
	assert_float(band).is_less_equal(3.0)


func test_icons_are_hidden_below_the_near_distance_and_whole_beyond_the_fade() -> void:
	var node := _hungry_node()
	_lay_out_at(node, NeedIcons.NEAR_FULL_M + 1.0)
	print(
		(
			"far: visible %s %s alpha %.2f"
			% [_sprite(node, 0).visible, _sprite(node, 1).visible, _sprite(node, 0).modulate.a]
		)
	)
	assert_bool(_sprite(node, 0).visible).is_true()
	assert_bool(_sprite(node, 1).visible).is_true()
	assert_float(_sprite(node, 0).modulate.a).is_equal(1.0)
	_lay_out_at(node, NeedIcons.NEAR_HIDDEN_M - 0.5)
	assert_bool(_sprite(node, 0).visible).is_false()
	assert_bool(_sprite(node, 1).visible).is_false()
	# Back out again: the icons return, so the hide is per frame, not latched.
	_lay_out_at(node, NeedIcons.NEAR_FULL_M + 1.0)
	assert_bool(_sprite(node, 0).visible).is_true()


func test_inside_the_fade_band_the_icons_show_part_transparent() -> void:
	var node := _hungry_node()
	var middle := (NeedIcons.NEAR_HIDDEN_M + NeedIcons.NEAR_FULL_M) / 2.0
	_lay_out_at(node, middle)
	assert_bool(_sprite(node, 0).visible).is_true()
	assert_float(_sprite(node, 0).modulate.a).is_equal_approx(0.5, 0.01)
	assert_float(_sprite(node, 1).modulate.a).is_equal_approx(0.5, 0.01)


func test_the_fade_follows_each_passenger_not_the_rig() -> void:
	var near := _hungry_node()
	var far := _hungry_node()
	far.position = near.position + Vector3(0.0, 0.0, -20.0)
	var unit := NeedIcons.unit_of(get_viewport(), _camera)
	_camera.look_at_from_position(
		near.global_position + Vector3(0.0, 2.0, 2.0), near.global_position
	)
	var gap := _camera.global_position.distance_to(near.global_position)
	assert_float(gap).is_less(NeedIcons.NEAR_HIDDEN_M)
	NeedIcons.layout(near, near.get_node("Bubble") as Label3D, _camera, unit)
	NeedIcons.layout(far, far.get_node("Bubble") as Label3D, _camera, unit)
	print(
		(
			"near %.1f m visible %s, far %.1f m visible %s"
			% [
				gap,
				_sprite(near, 0).visible,
				_camera.global_position.distance_to(far.global_position),
				_sprite(far, 0).visible
			]
		)
	)
	assert_bool(_sprite(near, 0).visible).is_false()
	assert_bool(_sprite(far, 0).visible).is_true()
	assert_float(_sprite(far, 0).modulate.a).is_equal(1.0)


func test_the_home_zoom_hide_still_wins_over_the_near_fade() -> void:
	var node := _hungry_node()
	var unit := NeedIcons.unit_of(get_viewport(), _camera)
	_lay_out_at(node, NeedIcons.NEAR_FULL_M + 1.0)
	assert_bool(_sprite(node, 0).visible).is_true()
	NeedIcons.layout(node, node.get_node("Bubble") as Label3D, _camera, unit, false)
	assert_bool(_sprite(node, 0).visible).is_false()
