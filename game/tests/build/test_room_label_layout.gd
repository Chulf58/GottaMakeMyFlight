class_name TestRoomLabelLayout
extends GdUnitTestSuite
## A room's world label (RoomView) keeps clear of the HUD, keeps a capped size on
## screen and fades out when the camera zooms in close (user rulings 2026-11-03,
## board item 9c2b0d32): it slides toward the screen's middle until no HUD
## control covers it and hides when no spot is clear; its text never draws bigger
## than RoomLabelLayout.MAX_SCALE screen pixels per font pixel; it fades out
## between FADE_FAR and FADE_NEAR of the camera rig's home distance, and comes
## back as the camera zooms out.
##
## Checked on the label's screen rectangle from a real camera and a real Control
## tree in a 1920x1080 viewport. How it looks next to the real HUD is a windowed
## plate's question, not this file's.

const VIEW := Rect2(0.0, 0.0, 1920.0, 1080.0)

var _port: SubViewport
var _view: RoomView
var _camera: Camera3D
var _layer: CanvasLayer
var _room := 0
var _anchor := Vector3.ZERO


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(16, 12))
	_room = grid.apply(BuildEdit.place_room(Rect2i(2, 2, 5, 4), &"cafe")).room_id
	_port = SubViewport.new()
	_port.size = Vector2i(1920, 1080)
	add_child(_port)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_port.add_child(_camera)
	_camera.current = true
	_layer = CanvasLayer.new()
	_port.add_child(_layer)
	_view = RoomView.new()
	_port.add_child(_view)
	_view.watch(grid)
	_anchor = _view.label_of(_room).position


func after_test() -> void:
	_port.free()


## Puts `camera` `distance` metres from the label, aimed `side` metres to the
## right of it, so the label stands left of the screen's middle.
func _aim(camera: Camera3D, distance: float, side := 8.0) -> void:
	var target := _anchor + Vector3(side, 0.0, 0.0)
	camera.global_position = target + Vector3(0.0, 0.766, 0.643) * distance
	camera.look_at(target)


## Screen pixels one font pixel of the label covers now.
func _scale(camera: Camera3D, label: Label3D) -> float:
	var at := label.global_position
	var up := camera.unproject_position(at + camera.global_basis.y)
	return absf(up.y - camera.unproject_position(at).y) * label.pixel_size


## The rectangle the label covers on screen now, with its slide.
func _rect(camera: Camera3D) -> Rect2:
	var label := _view.label_of(_room)
	var scale := _scale(camera, label)
	var rect := RoomLabelLayout.label_rect(
		camera.unproject_position(label.global_position),
		label.text,
		label.font_size,
		label.outline_size,
		scale
	)
	return Rect2(rect.position + Vector2(label.offset.x, -label.offset.y) * scale, rect.size)


func _add_button(rect: Rect2) -> Button:
	var button := Button.new()
	_layer.add_child(button)
	button.position = rect.position
	button.size = rect.size
	return button


func test_a_label_clear_of_the_hud_stays_where_it_is() -> void:
	_aim(_camera, 30.0)
	_view.layout_labels()
	var label := _view.label_of(_room)
	assert_bool(label.visible).is_true()
	assert_vector(label.offset).is_equal(Vector2.ZERO)
	assert_vector(label.position).is_equal(_anchor)
	assert_bool(VIEW.encloses(_rect(_camera))).is_true()


func test_a_label_under_a_hud_button_slides_toward_the_middle_until_clear() -> void:
	_aim(_camera, 30.0)
	_view.layout_labels()
	var home := _rect(_camera)
	var button_rect := home.grow(10.0)
	_add_button(button_rect)
	# Control: the button covers the label where it stands.
	assert_bool(home.intersects(button_rect)).is_true()
	_view.layout_labels()
	var label := _view.label_of(_room)
	var rect := _rect(_camera)
	print("label %s (home %s) button %s offset %s" % [rect, home, button_rect, label.offset])
	assert_bool(label.visible).is_true()
	assert_bool(rect.grow(RoomLabelLayout.GAP_PX - 0.01).intersects(button_rect)).is_false()
	assert_float(rect.get_center().distance_to(VIEW.get_center())).is_less(
		home.get_center().distance_to(VIEW.get_center())
	)
	assert_float(rect.get_center().distance_to(home.get_center())).is_less_equal(
		RoomLabelLayout.MAX_TRAVEL_PX
	)
	# The label's world anchor stays put: the cafe '+$' pop hangs under it.
	assert_vector(label.position).is_equal(_anchor)
	# The slide is undone once the button is gone.
	_layer.get_child(0).free()
	_view.layout_labels()
	assert_vector(label.offset).is_equal(Vector2.ZERO)


func test_a_label_with_no_clear_spot_hides() -> void:
	_aim(_camera, 30.0)
	_add_button(VIEW)
	_view.layout_labels()
	assert_bool(_view.label_of(_room).visible).is_false()
	_layer.get_child(0).free()
	_view.layout_labels()
	assert_bool(_view.label_of(_room).visible).is_true()


## A big partial panel (the offer sheet) blocks the way to the middle, but a
## pocket beside it is clear: the label goes there and is not hidden.
func test_a_label_with_a_blocked_way_to_the_middle_takes_a_clear_spot_elsewhere() -> void:
	var rect := Rect2(700.0, 70.0, 200.0, 100.0)
	var sheet: Array[Rect2] = [Rect2(630.0, 60.0, 700.0, 440.0)]
	# Control: the way toward the middle is blocked for the whole travel.
	var toward := (
		(VIEW.get_center() - rect.get_center()).normalized() * RoomLabelLayout.MAX_TRAVEL_PX
	)
	(
		assert_bool(
			sheet[0].grow(RoomLabelLayout.GAP_PX).intersects(
				Rect2(rect.position + toward, rect.size)
			)
		)
		. is_true()
	)
	var spot := RoomLabelLayout.slide_clear(rect, sheet, VIEW.size)
	print("blocked way: spot %s" % spot)
	assert_vector(spot.size).is_equal(rect.size)
	assert_bool(spot.grow(RoomLabelLayout.GAP_PX - 0.01).intersects(sheet[0])).is_false()
	assert_bool(VIEW.grow(-RoomLabelLayout.VIEW_MARGIN_PX).encloses(spot)).is_true()


## A drawn control over the whole view (a dim layer) hides the label at once: the
## search for a spot is not entered.
func test_a_hud_rect_over_the_whole_view_hides_the_label_without_a_search() -> void:
	var rect := Rect2(700.0, 70.0, 200.0, 100.0)
	var dim: Array[Rect2] = [VIEW]
	RoomLabelLayout.ring_candidates = 0
	assert_vector(RoomLabelLayout.slide_clear(rect, dim, VIEW.size).size).is_equal(Vector2.ZERO)
	assert_int(RoomLabelLayout.ring_candidates).is_equal(0)
	# Control: a panel that leaves a pocket still gets the ring search.
	var sheet: Array[Rect2] = [Rect2(630.0, 60.0, 700.0, 440.0)]
	RoomLabelLayout.slide_clear(rect, sheet, VIEW.size)
	assert_int(RoomLabelLayout.ring_candidates).is_greater(0)
	# In the layout: the label hides, counted, with no ring spot tried.
	_aim(_camera, 30.0)
	_add_button(VIEW)
	RoomLabelLayout.ring_candidates = 0
	_view.layout_labels()
	assert_bool(_view.label_of(_room).visible).is_false()
	assert_int(RoomLabelLayout.ring_candidates).is_equal(0)


func test_the_label_never_draws_bigger_than_the_cap_on_screen() -> void:
	var label := _view.label_of(_room)
	# Far out the world-size label is small and stays as it was.
	_aim(_camera, 60.0)
	assert_float(_scale(_camera, label)).is_less(RoomLabelLayout.MAX_SCALE)
	_view.layout_labels()
	assert_float(label.pixel_size).is_equal_approx(RoomView.LABEL_PIXEL_SIZE, 0.00001)
	# Control: close in, the uncapped label would be well over the cap.
	_aim(_camera, 14.0)
	_view.layout_labels()
	label.pixel_size = RoomView.LABEL_PIXEL_SIZE
	assert_float(_scale(_camera, label)).is_greater(RoomLabelLayout.MAX_SCALE * 1.3)
	_view.layout_labels()
	print("close scale %s, cap %s" % [_scale(_camera, label), RoomLabelLayout.MAX_SCALE])
	assert_float(_scale(_camera, label)).is_equal_approx(RoomLabelLayout.MAX_SCALE, 0.001)
	# Closer still it stays at the cap.
	_aim(_camera, 8.0)
	_view.layout_labels()
	assert_float(_scale(_camera, label)).is_equal_approx(RoomLabelLayout.MAX_SCALE, 0.001)


func test_the_zoom_alpha_follows_the_rigs_distance_from_home() -> void:
	var rig := _rig(40.0)
	var camera := rig.get_node("Camera3D") as Camera3D
	var seen := {}
	for distance in [60.0, 24.0, 19.0, 14.0, 6.0]:
		rig.distance = distance
		seen[distance] = RoomLabelLayout.zoom_alpha(camera)
	print("home 40: distance -> alpha %s" % seen)
	assert_float(seen[60.0]).is_equal(1.0)
	assert_float(seen[24.0]).is_equal(1.0)
	assert_float(seen[19.0]).is_between(0.2, 0.8)
	assert_float(seen[14.0]).is_equal(0.0)
	assert_float(seen[6.0]).is_equal(0.0)
	# A camera outside a rig, or none, never fades the label.
	assert_float(RoomLabelLayout.zoom_alpha(_camera)).is_equal(1.0)
	assert_float(RoomLabelLayout.zoom_alpha(null)).is_equal(1.0)


func test_the_label_fades_out_zoomed_in_and_returns_zoomed_out() -> void:
	var rig := _rig(40.0)
	var camera := rig.get_node("Camera3D") as Camera3D
	var label := _view.label_of(_room)
	rig.distance = 40.0
	_aim(camera, 30.0)
	_view.layout_labels()
	assert_bool(label.visible).is_true()
	assert_float(label.modulate.a).is_equal(1.0)
	assert_float(label.outline_modulate.a).is_equal(1.0)
	rig.distance = 19.0
	_aim(camera, 30.0)
	_view.layout_labels()
	assert_bool(label.visible).is_true()
	assert_float(label.modulate.a).is_between(0.2, 0.8)
	assert_float(label.outline_modulate.a).is_between(0.2, 0.8)
	rig.distance = 8.0
	_aim(camera, 30.0)
	_view.layout_labels()
	assert_bool(label.visible).is_false()
	rig.distance = 40.0
	_aim(camera, 30.0)
	_view.layout_labels()
	assert_bool(label.visible).is_true()
	assert_float(label.modulate.a).is_equal(1.0)
	# The text colour the room's status chose is not touched by the fade.
	assert_that(Color(label.modulate, 1.0)).is_equal(RoomView.NEEDS_TEXT)


## The game's camera rig with `home` as its home distance, current in the port.
func _rig(home: float) -> TycoonCamera:
	var rig := (
		(load("res://camera/tycoon_camera.tscn") as PackedScene).instantiate() as TycoonCamera
	)
	rig.home_distance = home
	_port.add_child(rig)
	rig.set_process(false)
	(rig.get_node("Camera3D") as Camera3D).make_current()
	return rig


## Whether a texel matches a colour within 8-bit rounding.
func _near(texel: Color, colour: Color) -> bool:
	return (
		Vector4(texel.r, texel.g, texel.b, texel.a).distance_to(
			Vector4(colour.r, colour.g, colour.b, colour.a)
		)
		< 0.01
	)


## WCAG contrast ratio of two colours.
func _contrast(a: Color, b: Color) -> float:
	var la := a.srgb_to_linear().get_luminance() + 0.05
	var lb := b.srgb_to_linear().get_luminance() + 0.05
	return maxf(la, lb) / minf(la, lb)


## Board a48bca8d, decision room-labels-sit-on-a-cream-card-and-slide-clear-of-
## need-icons: the label draws dark text on a cream card with a dark outline,
## under the need icons, and the card follows the label's size cap and fade.
func test_a_room_label_draws_dark_text_on_a_cream_card() -> void:
	_aim(_camera, 30.0)
	_view.layout_labels()
	var label := _view.label_of(_room)
	var card := label.get_node(RoomLabelLayout.CARD) as Sprite3D
	var font := ThemeDB.fallback_font
	var text := font.get_multiline_string_size(
		label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, label.font_size
	)
	var pad := 2.0 * (label.outline_size + RoomLabelLayout.CARD_PAD_PX)
	var image := card.texture.get_image()
	print(
		(
			"card %s for text %s, pixel %s/%s, offset %s, alpha %s"
			% [
				image.get_size(),
				text,
				card.pixel_size,
				label.pixel_size,
				card.offset,
				card.modulate.a
			]
		)
	)
	assert_vector(Vector2(image.get_size())).is_equal((text + Vector2.ONE * pad).ceil())
	assert_float(card.pixel_size).is_equal(label.pixel_size)
	assert_vector(card.offset).is_equal(label.offset + Vector2(0.0, text.y / 2.0))
	var middle := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	var top := image.get_pixel(image.get_width() / 2, 1)
	assert_bool(_near(middle, RoomLabelLayout.CARD_FILL)).is_true()
	assert_bool(_near(top, RoomLabelLayout.CARD_BORDER)).is_true()
	# A corner texel is see-through: the card is rounded.
	assert_float(image.get_pixel(0, 0).a).is_less(0.1)
	# Dark text that reads on the card: both colours at a 4.5:1 contrast or more.
	assert_float(_contrast(RoomView.READY_TEXT, RoomLabelLayout.CARD_FILL)).is_greater(4.5)
	assert_float(_contrast(RoomView.NEEDS_TEXT, RoomLabelLayout.CARD_FILL)).is_greater(4.5)
	# The card under the text's outline under the text, all under the need icons.
	assert_int(card.render_priority).is_less(label.outline_render_priority)
	assert_int(label.outline_render_priority).is_less(label.render_priority)
	var need_icon := NeedIcons.make_sprite("probe")
	assert_int(label.render_priority).is_less(need_icon.render_priority)
	need_icon.free()
	# The card fades with the label.
	label.modulate.a = 0.4
	RoomLabelLayout.sync_card(label)
	assert_float(card.modulate.a).is_equal_approx(0.4, 0.001)
	# The culling margins are written only when they differ, each on its own: a
	# repeat sync keeps them, and a margin knocked off by itself is restored.
	var margin := card.extra_cull_margin
	assert_float(margin).is_greater(0.0)
	assert_float(label.extra_cull_margin).is_equal_approx(margin, 0.0001)
	RoomLabelLayout.sync_card(label)
	assert_float(card.extra_cull_margin).is_equal_approx(margin, 0.0001)
	assert_float(label.extra_cull_margin).is_equal_approx(margin, 0.0001)
	card.extra_cull_margin = margin + 5.0
	RoomLabelLayout.sync_card(label)
	assert_float(card.extra_cull_margin).is_equal_approx(margin, 0.0001)
	label.extra_cull_margin = margin + 5.0
	RoomLabelLayout.sync_card(label)
	assert_float(label.extra_cull_margin).is_equal_approx(margin, 0.0001)
	label.text = "A much longer\nlabel than before"
	RoomLabelLayout.sync_card(label)
	assert_float(card.extra_cull_margin).is_equal_approx(label.extra_cull_margin, 0.0001)
	assert_float(label.extra_cull_margin).is_not_equal(margin)


## A stand-in for PassengerViews: one passenger node with one shown need icon
## NeedIcons.ICON_PX on screen, standing where the icon draws at `point`.
func _icon_at(point: Vector2) -> Sprite3D:
	var views := Node3D.new()
	_port.add_child(views)
	var node := Node3D.new()
	node.set_meta(&"body", 0)
	views.add_child(node)
	var icon := Sprite3D.new()
	icon.name = "NeedIcon0"
	icon.fixed_size = true
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.texture = ImageTexture.create_from_image(
		Image.create(NeedIcons.SIZE, NeedIcons.SIZE, false, Image.FORMAT_RGBA8)
	)
	var unit := 2.0 * tan(deg_to_rad(_camera.fov) / 2.0) / VIEW.size.y
	icon.pixel_size = NeedIcons.ICON_PX * unit / NeedIcons.SIZE
	node.add_child(icon)
	_view.passenger_views = views
	_put_icon(icon, point)
	return icon


func _put_icon(icon: Sprite3D, point: Vector2) -> void:
	var plane := Plane(Vector3.UP, _anchor.y)
	var hit: Variant = plane.intersects_ray(
		_camera.project_ray_origin(point), _camera.project_ray_normal(point)
	)
	icon.get_parent().global_position = hit


## The card's box on screen now, from the card sprite's own size and offset.
func _card(camera: Camera3D) -> Rect2:
	var card := _view.label_of(_room).get_node(RoomLabelLayout.CARD) as Sprite3D
	var unit := 2.0 * tan(deg_to_rad(camera.fov) / 2.0) / VIEW.size.y
	return RoomLabelLayout.sprite_rect(card, camera, unit)


## A need icon drawn on the label's card nudges the label a short way to a
## clear spot; the label keeps that spot while the icon moves about elsewhere
## and goes home once no icon is near. The icon itself never moves.
func test_a_label_under_a_need_icon_nudges_clear_and_keeps_its_spot() -> void:
	_aim(_camera, 30.0)
	_view.layout_labels()
	var home := _card(_camera)
	var icon := _icon_at(home.get_center())
	var unit := 2.0 * tan(deg_to_rad(_camera.fov) / 2.0) / VIEW.size.y
	var icon_box := RoomLabelLayout.sprite_rect(icon, _camera, unit)
	# Control: the icon is drawn on the card where it stands.
	assert_bool(home.intersects(icon_box)).is_true()
	var icon_at := icon.global_position
	_view.layout_labels()
	var label := _view.label_of(_room)
	var moved := _card(_camera)
	print("card %s (home %s) icon %s offset %s" % [moved, home, icon_box, label.offset])
	assert_bool(label.visible).is_true()
	assert_vector(label.offset).is_not_equal(Vector2.ZERO)
	assert_bool(moved.intersects(icon_box)).is_false()
	var reach := minf(RoomLabelLayout.NUDGE_PX, home.size.y) + 2.0 * NeedIcons.ICON_PX
	assert_float(moved.get_center().distance_to(home.get_center())).is_less_equal(reach + 1.0)
	assert_vector(icon.global_position).is_equal(icon_at)
	assert_vector(label.position).is_equal(_anchor)
	# A kept nudge is used while it stays clear, not searched again: plant one
	# straight up by the card's height, which the search (toward the middle, to
	# the right here) would not pick, and the label takes it.
	var searched := label.offset
	label.set_meta(&"nudge", Vector2(0.0, -home.size.y))
	_view.layout_labels()
	var kept := _card(_camera)
	print("kept card %s, searched offset %s, now %s" % [kept, searched, label.offset])
	assert_vector(label.offset).is_not_equal(searched)
	(
		assert_float(kept.get_center().distance_to(home.get_center() - Vector2(0.0, home.size.y)))
		. is_less(1.0)
	)
	assert_bool(kept.intersects(icon_box)).is_false()
	# The icon leaves: the label goes home.
	_put_icon(icon, Vector2(-500.0, -500.0))
	_view.layout_labels()
	assert_vector(label.offset).is_equal(Vector2.ZERO)


## Sol review of 0537708: at the farthest zoom a label slid clear of the HUD
## is drawn far from its anchor, in the camera's axes. Its culling box (and its
## card's), grown by the cull margin, must still hold the drawn card, or the
## label is culled while the card shows empty.
func test_a_label_slid_at_the_farthest_zoom_stays_inside_its_culling_box() -> void:
	var rig := TycoonCamera.new()
	var far := rig.max_distance
	rig.free()
	_aim(_camera, far)
	_view.layout_labels()
	_add_button(_rect(_camera).grow(10.0))
	_view.layout_labels()
	await get_tree().process_frame
	var label := _view.label_of(_room)
	var card := label.get_node(RoomLabelLayout.CARD) as Sprite3D
	assert_bool(label.visible).is_true()
	assert_vector(label.offset).is_not_equal(Vector2.ZERO)
	var right := _camera.global_basis.x
	var up := _camera.global_basis.y
	var drawn := (
		card.global_position + (right * card.offset.x + up * card.offset.y) * card.pixel_size
	)
	for node: GeometryInstance3D in [label, card]:
		var box: AABB = node.global_transform * node.get_aabb()
		print("%s box %s margin %.2f drawn %s" % [node.name, box, node.extra_cull_margin, drawn])
		# The control: the slide is real, the card is drawn metres from its anchor.
		assert_float(drawn.distance_to(node.global_position)).is_greater(3.0)
		assert_bool(box.grow(node.extra_cull_margin).has_point(drawn)).is_true()
		# The margin alone holds it, whatever box Godot gives a billboard.
		var bare := AABB(node.global_position, Vector3.ZERO)
		assert_bool(bare.grow(node.extra_cull_margin).has_point(drawn)).is_true()


func test_the_nudge_reach_is_the_card_height_capped_plus_two_icon_widths() -> void:
	var icons := 2.0 * NeedIcons.ICON_PX
	assert_float(RoomLabelLayout.nudge_reach(40.0)).is_equal(40.0 + icons)
	assert_float(RoomLabelLayout.nudge_reach(RoomLabelLayout.NUDGE_PX * 3.0)).is_equal(
		RoomLabelLayout.NUDGE_PX + icons
	)
