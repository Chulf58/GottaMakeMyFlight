class_name TestGhostCardNudge
extends GdUnitTestSuite
## The refusal card keeps clear of HUD panels and banners (decision ghost-
## refusal-card-nudges-clear-of-hud-panels-and-banners): GhostCardNudge.clear_y()
## moves it up or down the least that clears them and keeps it inside the window,
## and hud_rects() finds what the HUD draws, leaving out the card's own layer.

const AREA := Rect2(8.0, 8.0, 1000.0, 600.0)
const CARD_SIZE := Vector2(120.0, 30.0)


func _card(y: float) -> Rect2:
	return Rect2(Vector2(300.0, y), CARD_SIZE)


func _banner(y: float, height: float) -> Array[Rect2]:
	return [Rect2(Vector2(250.0, y), Vector2(400.0, height))]


func test_a_card_clear_of_the_hud_does_not_move() -> void:
	var y := GhostCardNudge.clear_y(_card(200.0), _banner(400.0, 50.0), AREA)
	assert_float(y).is_equal(200.0)


func test_a_card_beside_a_banner_does_not_move() -> void:
	var beside: Array[Rect2] = [Rect2(Vector2(600.0, 190.0), Vector2(200.0, 80.0))]
	assert_float(GhostCardNudge.clear_y(_card(200.0), beside, AREA)).is_equal(200.0)


func test_a_card_over_the_top_of_a_banner_moves_up_to_clear_it() -> void:
	# Banner 190..240; the card at 180..210 overlaps its top, so up is shorter.
	var y := GhostCardNudge.clear_y(_card(180.0), _banner(190.0, 50.0), AREA)
	assert_float(y).is_equal(190.0 - GhostCardNudge.GAP - CARD_SIZE.y)
	assert_bool(_card(y).intersects(_banner(190.0, 50.0)[0])).is_false()


func test_a_card_over_the_bottom_of_a_banner_moves_down_to_clear_it() -> void:
	# Banner 190..240; the card at 220..250 overlaps its bottom, so down is shorter.
	var y := GhostCardNudge.clear_y(_card(220.0), _banner(190.0, 50.0), AREA)
	assert_float(y).is_equal(240.0 + GhostCardNudge.GAP)


func test_the_card_takes_the_smaller_move_not_the_first_side() -> void:
	# A 200 px banner 200..400 with the card near its bottom: down is 24 px, up 214.
	var y := GhostCardNudge.clear_y(_card(380.0), _banner(200.0, 200.0), AREA)
	assert_float(y).is_equal(400.0 + GhostCardNudge.GAP)


func test_the_card_steps_past_a_second_banner_in_the_way() -> void:
	# Banners 190..240 and 250..300 leave a 10 px gap the card cannot fit. Down to 244
	# is the nearest place but it touches the second banner, so the card goes to 304
	# (69 px) rather than up to 156 (79 px).
	var both: Array[Rect2] = [
		Rect2(Vector2(250.0, 190.0), Vector2(400.0, 50.0)),
		Rect2(Vector2(250.0, 250.0), Vector2(400.0, 50.0)),
	]
	var y := GhostCardNudge.clear_y(_card(235.0), both, AREA)
	assert_float(y).is_equal(300.0 + GhostCardNudge.GAP)


func test_a_card_that_cannot_clear_either_way_stays_inside_the_window() -> void:
	# The banner fills the window's height, so no place is clear.
	var wall: Array[Rect2] = [Rect2(Vector2(250.0, 0.0), Vector2(400.0, 700.0))]
	var y := GhostCardNudge.clear_y(_card(300.0), wall, AREA)
	assert_float(y).is_equal(300.0)
	var low := GhostCardNudge.clear_y(_card(900.0), wall, AREA)
	assert_float(low).is_equal(AREA.end.y - CARD_SIZE.y)
	var high := GhostCardNudge.clear_y(_card(-50.0), wall, AREA)
	assert_float(high).is_equal(AREA.position.y)


func test_a_nudge_never_leaves_the_window() -> void:
	# A banner at the top edge pushes the card down, never above the window.
	var top: Array[Rect2] = [Rect2(Vector2(250.0, 0.0), Vector2(400.0, 60.0))]
	var y := GhostCardNudge.clear_y(_card(20.0), top, AREA)
	assert_float(y).is_equal(60.0 + GhostCardNudge.GAP)
	assert_float(y).is_greater_equal(AREA.position.y)
	# A banner at the bottom edge pushes it up, never below the window.
	var bottom: Array[Rect2] = [Rect2(Vector2(250.0, 560.0), Vector2(400.0, 100.0))]
	var up := GhostCardNudge.clear_y(_card(580.0), bottom, AREA)
	assert_float(up).is_equal(560.0 - GhostCardNudge.GAP - CARD_SIZE.y)
	assert_float(up + CARD_SIZE.y).is_less_equal(AREA.end.y)


func test_hud_rects_find_visible_panels_and_leave_out_the_cards_own_layer() -> void:
	var port := SubViewport.new()
	port.size = Vector2i(1000, 600)
	add_child(port)
	var hud := CanvasLayer.new()
	port.add_child(hud)
	var banner := PanelContainer.new()
	banner.position = Vector2(100.0, 50.0)
	banner.custom_minimum_size = Vector2(200.0, 40.0)
	hud.add_child(banner)
	var hidden := PanelContainer.new()
	hidden.position = Vector2(500.0, 50.0)
	hidden.custom_minimum_size = Vector2(200.0, 40.0)
	hidden.visible = false
	hud.add_child(hidden)
	var backdrop := ColorRect.new()
	backdrop.size = Vector2(1000.0, 600.0)
	hud.add_child(backdrop)
	var own := CanvasLayer.new()
	port.add_child(own)
	var card := GhostReason.new()
	own.add_child(card)
	await get_tree().process_frame
	var rects := GhostCardNudge.hud_rects(card)
	assert_int(rects.size()).is_equal(1)
	assert_vector(rects[0].position).is_equal(Vector2(100.0, 50.0))
	assert_vector(rects[0].size).is_equal(Vector2(200.0, 40.0))
	port.free()


func test_the_live_card_leaves_a_banner_over_its_spot_by_the_smallest_move() -> void:
	var port := SubViewport.new()
	port.size = Vector2i(1536, 864)
	add_child(port)
	var mode := BuildMode.new()
	mode.grid_size = Vector2i(10, 10)
	port.add_child(mode)
	mode.set_process(false)
	var camera := Camera3D.new()
	port.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 14.0, 10.0), Vector3.ZERO)
	camera.make_current()
	var menu := BuildMenu.new()
	menu.build_mode = mode
	port.add_child(menu)
	var reason := menu.ghost_reason()
	reason.set_process(false)
	mode.set_tool(BuildMode.Tool.DESK)
	mode._update_ghost(mode.grid.cell_to_world(Vector2i(4, 4)))
	reason.refresh()
	assert_bool(reason.visible).is_true()
	var home := Rect2(reason.position, reason.size)
	# A banner laid over the card's own spot, past the bar and tray.
	var layer := CanvasLayer.new()
	port.add_child(layer)
	var banner := PanelContainer.new()
	banner.position = home.position + Vector2(-20.0, 4.0)
	banner.custom_minimum_size = Vector2(home.size.x + 40.0, 40.0)
	layer.add_child(banner)
	await get_tree().process_frame
	reason.refresh()
	var moved := Rect2(reason.position, reason.size)
	var shut := Rect2(banner.position, banner.size)
	assert_bool(moved.intersects(shut)).is_false()
	assert_float(moved.position.x).is_equal(home.position.x)
	assert_float(absf(moved.position.y - home.position.y)).is_less(home.size.y + shut.size.y)
	assert_bool(Rect2(Vector2.ZERO, Vector2(port.size)).encloses(moved)).is_true()
	port.free()
