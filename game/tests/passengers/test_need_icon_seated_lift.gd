class_name TestNeedIconSeatedLift
extends GdUnitTestSuite
## A seated passenger's need icon row sits higher than a standing one's and over
## the head (board bd08ed8e, user ruling 2026-11-13 "Lift icons for seated"). A
## seated body is drawn about 0.54 m behind its root, so from the game camera's
## start pitch (70 degrees) its head lands above the screen point of a row
## anchored 2.0 m over the root. The row (and the VIP crown and count clusters,
## which take their place from it) anchors NeedIcons.SEATED_LIFT_M high and
## SEATED_BACK_M behind the root; a standing passenger's anchor does not move.

## The seated head the near-camera probe measured on a gate chair (bone_head_m
## 1.28 to 1.34 high, 0.54 m behind the root) with the head's top 0.12 m over it.
const SEATED_HEAD_TOP_M := 1.46
const SEATED_HEAD_BACK_M := 0.54

var _camera: Camera3D


func before_test() -> void:
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.make_current()


func after_test() -> void:
	_camera.free()


func test_a_seated_row_anchors_higher_than_a_standing_row() -> void:
	var seated := _node(true)
	var standing := _node(false)
	var seated_at := NeedIcons.row_anchor(seated, _bubble(seated), _camera, 0.001)
	var standing_at := NeedIcons.row_anchor(standing, _bubble(standing), _camera, 0.001)
	var anchor: Vector3 = seated_at[0]
	assert_float(anchor.y).is_equal_approx(NeedIcons.SEATED_LIFT_M, 0.0001)
	assert_float(anchor.z).is_equal_approx(-NeedIcons.SEATED_BACK_M, 0.0001)
	assert_float(anchor.y).is_greater((standing_at[0] as Vector3).y + 0.1)
	seated.free()
	standing.free()


func test_a_standing_row_stays_at_the_old_anchor() -> void:
	var standing := _node(false)
	var at := NeedIcons.row_anchor(standing, _bubble(standing), _camera, 0.001)
	assert_vector(at[0]).is_equal(Vector3(0.0, NeedIcons.LIFT_M, 0.0))
	assert_float(NeedIcons.LIFT_M).is_equal(2.0)
	standing.free()


func test_a_shown_bubble_still_takes_the_row_for_a_seated_passenger() -> void:
	var seated := _node(true)
	var bubble := _bubble(seated)
	bubble.text = "I'm late!"
	var at := NeedIcons.row_anchor(seated, bubble, _camera, 0.001)
	assert_vector(at[0]).is_equal(bubble.position)
	seated.free()


func test_layout_puts_a_seated_icon_at_the_seated_anchor() -> void:
	var seated := _node(true)
	NeedIcons.show_needs(seated, [NeedIcons.Need.HUNGER] as Array[NeedIcons.Need])
	_camera.global_position = Vector3(0.0, 4.0, 10.0)
	seated.global_position = Vector3(0.0, 0.0, -2.0)
	NeedIcons.layout(seated, _bubble(seated), _camera, 0.001)
	var icon := seated.get_node(NeedIcons.SPRITES[0]) as Sprite3D
	assert_bool(icon.visible).is_true()
	assert_vector(icon.position).is_equal_approx(
		NeedIcons.head_anchor(seated), Vector3.ONE * 0.0001
	)
	assert_float(icon.position.y).is_equal_approx(NeedIcons.SEATED_LIFT_M, 0.0001)
	seated.free()


func test_the_crown_follows_a_seated_row_up() -> void:
	var seated := _node(true)
	var standing := _node(false)
	VipMarker.mark(seated, true)
	VipMarker.mark(standing, true)
	_camera.global_position = Vector3(0.0, 4.0, 10.0)
	seated.global_position = Vector3(0.0, 0.0, -2.0)
	standing.global_position = Vector3(0.0, 0.0, -2.0)
	VipMarker.layout(seated, _bubble(seated), _camera, 0.001)
	VipMarker.layout(standing, _bubble(standing), _camera, 0.001)
	var crown := seated.get_node(VipMarker.SPRITE) as Sprite3D
	var plain := standing.get_node(VipMarker.SPRITE) as Sprite3D
	assert_vector(crown.position).is_equal_approx(
		Vector3(0.0, NeedIcons.SEATED_LIFT_M, -NeedIcons.SEATED_BACK_M), Vector3.ONE * 0.0001
	)
	assert_vector(plain.position).is_equal(Vector3(0.0, NeedIcons.LIFT_M, 0.0))
	seated.free()
	standing.free()


## The cause. At the game's start pitch the seated head lands higher on screen
## than the 2.0 m anchor over the root (control: the old anchor's gap to the
## head top is negative, the row over the face); the seated anchor stands over
## the head with more than half an icon of clear space, at every angle step.
func test_the_seated_anchor_clears_the_head_at_every_angle_step() -> void:
	var head_top := Vector3(0.0, SEATED_HEAD_TOP_M, -SEATED_HEAD_BACK_M)
	for step in TycoonCamera.STEP_PITCH_DEGREES.size():
		var pitch := deg_to_rad(TycoonCamera.STEP_PITCH_DEGREES[step])
		_camera.global_position = Vector3(0.0, 8.0 * sin(pitch), 8.0 * cos(pitch))
		_camera.rotation = Vector3(-pitch, 0.0, 0.0)
		var head_y := _camera.unproject_position(head_top).y
		var old_y := _camera.unproject_position(Vector3(0.0, NeedIcons.LIFT_M, 0.0)).y
		var seated_y := _camera.unproject_position(_seated_anchor()).y
		# Screen y grows downward: the gap is how far the anchor stands over the
		# head top on screen.
		var seated_gap := head_y - seated_y
		assert_float(seated_gap).is_greater(NeedIcons.ICON_PX / 2.0)
		if step == TycoonCamera.AngleStep.TOP_DOWN:
			assert_float(head_y - old_y).is_less(0.0)


func _seated_anchor() -> Vector3:
	var seated := _node(true)
	var anchor := NeedIcons.head_anchor(seated)
	seated.free()
	return anchor


func _node(seated: bool) -> Node3D:
	var node := Node3D.new()
	var bubble := Label3D.new()
	bubble.name = "Bubble"
	bubble.font_size = 56
	bubble.outline_size = 14
	bubble.pixel_size = 0.006
	bubble.position = Vector3(0.0, PassengerViews.BUBBLE_HEIGHT, 0.0)
	node.add_child(bubble)
	for sprite_name in NeedIcons.SPRITES:
		node.add_child(NeedIcons.make_sprite(sprite_name))
	node.add_child(WishIconView.make_sprite())
	node.add_child(VipMarker.make_sprite())
	add_child(node)
	node.set_meta(&"seated", seated)
	return node


func _bubble(node: Node3D) -> Label3D:
	return node.get_node("Bubble") as Label3D
