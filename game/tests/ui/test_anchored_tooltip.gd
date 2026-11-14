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
