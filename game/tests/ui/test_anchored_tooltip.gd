class_name TestAnchoredTooltip
extends GdUnitTestSuite
## AnchoredTooltip.place(): the card sits beside its anchor (right first, then
## left, below, above), inside the screen by HudLayout.MARGIN, and off the rects
## it is told to avoid (the HUD rails and cards); with no free side it is kept
## inside the screen.

const SCREEN := Rect2(0.0, 0.0, 1536.0, 864.0)
const CARD := Vector2(200.0, 40.0)
const ANCHOR := Rect2(600.0, 400.0, 40.0, 40.0)


func _inside(card: Rect2) -> bool:
	return SCREEN.grow(-HudLayout.MARGIN).encloses(card)


func test_the_card_sits_right_of_the_anchor_centred_on_it() -> void:
	var at := AnchoredTooltip.place(ANCHOR, CARD, SCREEN, [])
	print("card at %s" % at)
	assert_float(at.x).is_equal(ANCHOR.end.x + HudLayout.GAP)
	assert_float(at.y + CARD.y / 2.0).is_equal(ANCHOR.get_center().y)


func test_near_the_right_edge_the_card_flips_left() -> void:
	var anchor := Rect2(1450.0, 400.0, 40.0, 40.0)
	var at := AnchoredTooltip.place(anchor, CARD, SCREEN, [])
	var card := Rect2(at, CARD)
	print("card %s anchor %s" % [card, anchor])
	assert_float(card.end.x).is_equal(anchor.position.x - HudLayout.GAP)
	assert_bool(_inside(card)).is_true()


func test_an_avoided_rect_on_the_right_sends_the_card_left() -> void:
	var rail := Rect2(ANCHOR.end.x, 0.0, 440.0, 864.0)
	var at := AnchoredTooltip.place(ANCHOR, CARD, SCREEN, [rail])
	var card := Rect2(at, CARD)
	print("card %s rail %s" % [card, rail])
	assert_bool(card.intersects(rail)).is_false()
	assert_float(card.end.x).is_less_equal(ANCHOR.position.x)


func test_near_the_bottom_corner_the_card_stays_on_screen() -> void:
	var anchor := Rect2(1500.0, 850.0, 30.0, 14.0)
	var at := AnchoredTooltip.place(anchor, CARD, SCREEN, [])
	var card := Rect2(at, CARD)
	print("card %s" % card)
	assert_bool(_inside(card)).is_true()


func test_with_every_side_blocked_the_card_still_stays_on_screen() -> void:
	var anchor := Rect2(-80.0, -60.0, 40.0, 40.0)
	var all := SCREEN
	var at := AnchoredTooltip.place(anchor, CARD, SCREEN, [all])
	var card := Rect2(at, CARD)
	print("card %s" % card)
	assert_bool(_inside(card)).is_true()


func test_a_card_wider_than_the_screen_starts_at_the_margin() -> void:
	var wide := Vector2(2000.0, 40.0)
	var at := AnchoredTooltip.place(ANCHOR, wide, SCREEN, [])
	assert_float(at.x).is_equal(float(HudLayout.MARGIN))


func test_place_bottom_right_docks_in_lower_right_and_clamps() -> void:
	var at := AnchoredTooltip.place_bottom_right(CARD, SCREEN)
	var card := Rect2(at, CARD)
	assert_float(card.end.x).is_equal(SCREEN.end.x - float(HudLayout.MARGIN))
	assert_float(card.end.y).is_equal(SCREEN.end.y - float(HudLayout.MARGIN))
	assert_bool(_inside(card)).is_true()

	var lifted := AnchoredTooltip.place_bottom_right(CARD, SCREEN, 120.0)
	assert_float(lifted.y + CARD.y).is_equal(SCREEN.end.y - 120.0)

	var wide := Vector2(2000.0, 2000.0)
	var clamped := AnchoredTooltip.place_bottom_right(wide, SCREEN)
	assert_vector(clamped).is_equal(Vector2.ZERO)


func test_show_bottom_right_stacks_above_right_floor_inspect_card() -> void:
	var port: SubViewport = auto_free(SubViewport.new())
	port.size = Vector2i(1536, 864)
	add_child(port)
	var inspect := PanelContainer.new()
	inspect.add_to_group(BottomDocks.RIGHT_FLOOR_GROUP)
	inspect.position = Vector2(float(1536 - HudLayout.MARGIN) - HudLayout.RAIL_W, 600.0)
	inspect.size = Vector2(HudLayout.RAIL_W, 248.0)
	port.add_child(inspect)
	var tip := AnchoredTooltip.new()
	port.add_child(tip)
	await get_tree().process_frame

	tip.show_bottom_right("Check-in Desk: serves departing passengers.")
	var tip_rect := tip.get_global_rect()
	assert_bool(tip.visible).is_true()
	assert_float(tip_rect.end.x).is_equal_approx(float(1536 - HudLayout.MARGIN), 1.0)
	assert_float(tip_rect.end.y).is_less_equal(
		inspect.get_global_rect().position.y - float(HudLayout.GAP) + 1.0
	)
	assert_bool(tip_rect.intersects(inspect.get_global_rect())).is_false()
