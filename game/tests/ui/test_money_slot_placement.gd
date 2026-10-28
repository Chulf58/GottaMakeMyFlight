class_name TestMoneySlotPlacement
extends GdUnitTestSuite
## Where the money hover card opens (smoke playtest 5 note e): below the Money
## slot, so it covers neither the "Money N" figure nor the rating stars beside
## it. The slot, the stars and the card's origin are all taken from a real
## BuildMenu and RatingBadge in one 1280x720 viewport.

const CARD_SIZE := Vector2(260.0, 190.0)

var _port: SubViewport
var _rating: AirportRating
var _badge: RatingBadge
var _menu: BuildMenu
var _slot: MoneySlot


func before() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	var clock := SimClock.new()
	_port.add_child(clock)
	var wallet := Wallet.new()
	wallet.clock = clock
	var ledger: DayLedger = auto_free(DayLedger.new())
	ledger.bind(wallet, clock)
	_rating = AirportRating.new()
	_port.add_child(_rating)
	_badge = RatingBadge.new()
	_badge.rating = _rating
	_port.add_child(_badge)
	_menu = BuildMenu.new()
	_menu.day_ledger = ledger
	_port.add_child(_menu)
	_slot = _menu.money_label().get_parent() as MoneySlot


func after() -> void:
	_port.free()


func _card_rect() -> Rect2:
	return Rect2(_slot.card_origin(), CARD_SIZE)


func test_the_slot_is_the_money_slot_with_its_card() -> void:
	assert_object(_slot).is_not_null()
	assert_str(_slot.tooltip_text).starts_with("Today")


func test_the_card_does_not_cover_the_money_figure() -> void:
	assert_bool(_card_rect().intersects(_menu.money_label().get_global_rect())).is_false()
	assert_bool(_card_rect().intersects(_slot.get_global_rect())).is_false()


func test_the_card_does_not_cover_the_rating_stars() -> void:
	var stars := _badge.card().get_global_rect()
	assert_float(stars.size.x).is_greater(0.0)
	assert_bool(_card_rect().intersects(stars)).is_false()


func test_the_card_opens_under_the_slot_and_starts_at_its_left_edge() -> void:
	var slot := _slot.get_global_rect()
	assert_float(_slot.card_origin().y).is_greater_equal(slot.end.y)
	assert_float(_slot.card_origin().x).is_equal(slot.position.x)
