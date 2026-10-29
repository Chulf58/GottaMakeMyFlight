class_name TestMoneySlot
extends GdUnitTestSuite
## The money hover card (HUD 2/7, decision money-hover-design-categorised-
## wallet-transactions-feed-a-sa, point 5): hovering the money slot shows
## today's airline fees, shops, wages paid and operating result, then building,
## rescue grant and cash change today, and owed wages in the attention style
## only when some are owed. It follows the DayLedger and the wage debt.

const C := Wallet.Category

var _clock: SimClock
var _wallet: Wallet
var _ledger: DayLedger
var _settlement: Settlement
var _slot: MoneySlot


func before_test() -> void:
	_clock = auto_free(SimClock.new())
	_wallet = Wallet.new()
	_wallet.clock = _clock
	_ledger = auto_free(DayLedger.new())
	_ledger.bind(_wallet, _clock)
	_settlement = auto_free(Settlement.new())
	_slot = auto_free(MoneySlot.new())
	_slot.watch(_ledger, _settlement)


func _sample_day() -> void:
	assert_bool(_wallet.credit(20000, C.OPENING)).is_true()
	assert_bool(_wallet.credit(300, C.FEES)).is_true()
	assert_bool(_wallet.credit(40, C.SHOP)).is_true()
	assert_bool(_wallet.spend(90, C.WAGES)).is_true()
	assert_bool(_wallet.spend(400, C.BUILD)).is_true()
	assert_bool(_wallet.credit(150, C.BUILD)).is_true()
	assert_bool(_wallet.credit(500, C.GRANT)).is_true()


func test_the_card_shows_a_sample_day() -> void:
	_sample_day()
	var text := _slot.card_text()
	print(text)
	(
		assert_str(text)
		. is_equal(
			(
				"\n"
				. join(
					[
						"Today",
						"Airline fees  +300",
						"Shops  +40",
						"Wages paid  -90",
						"Upkeep paid  0",
						"Operating result  +250",
						"Building  -250",
						"Rescue grant  +500",
						"Cash change today  +500",
					]
				)
			)
		)
	)
	assert_str(_slot.tooltip_text).is_equal(text)


## Toilets 5/5: room upkeep paid is its own row among the operating rows, and
## the four rows above the operating result add up to it.
func test_upkeep_paid_is_an_operating_row_and_the_rows_add_up() -> void:
	_sample_day()
	assert_bool(_wallet.spend(30, C.UPKEEP)).is_true()
	var rows := MoneySlot.rows(_ledger, 0)
	print(rows)
	assert_array(rows[3]).is_equal(["Upkeep paid", "-30", &""])
	assert_array(rows[MoneySlot.OPERATING_ROWS - 1]).is_equal(["Operating result", "+220", &""])
	var parts := 0
	for i in MoneySlot.OPERATING_ROWS - 1:
		parts += int(rows[i][1])
	assert_int(parts).is_equal(_ledger.operating_result())
	assert_int(_ledger.operating_result()).is_equal(220)


func test_owed_upkeep_shows_in_the_attention_style_only_while_above_zero() -> void:
	for row in MoneySlot.rows(_ledger, 0, 0):
		assert_str(row[0]).is_not_equal("Owed upkeep")
	var rows := MoneySlot.rows(_ledger, 75, 40)
	assert_array(rows[rows.size() - 2]).is_equal(["Owed wages", "75", MoneySlot.ATTENTION])
	assert_array(rows[rows.size() - 1]).is_equal(["Owed upkeep", "40", MoneySlot.ATTENTION])
	rows = MoneySlot.rows(_ledger, 0, 40)
	assert_array(rows[rows.size() - 1]).is_equal(["Owed upkeep", "40", MoneySlot.ATTENTION])


func test_the_card_follows_owed_upkeep() -> void:
	assert_str(_slot.card_text()).not_contains("Owed upkeep")
	_settlement.from_snapshot(_settlement_with_upkeep_owed(25))
	print(_slot.card_text())
	assert_str(_slot.card_text()).contains("Owed upkeep  25")
	assert_str(_slot.tooltip_text).is_equal(_slot.card_text())


func _settlement_with_upkeep_owed(owed: int) -> Dictionary:
	var data := _settlement.to_snapshot()
	data[Settlement.UPKEEP_SNAPSHOT_KEY] = str(owed)
	return data


func test_an_empty_day_shows_zeros_and_no_owed_wages() -> void:
	var text := _slot.card_text()
	assert_str(text).contains("Airline fees  0")
	assert_str(text).contains("Operating result  0")
	assert_str(text).contains("Cash change today  0")
	assert_str(text).not_contains("Owed wages")


func test_owed_wages_show_only_while_above_zero() -> void:
	var rows := MoneySlot.rows(_ledger, 0)
	for row in rows:
		assert_str(row[0]).is_not_equal("Owed wages")
	rows = MoneySlot.rows(_ledger, 75)
	var last: Array = rows[rows.size() - 1]
	assert_array(last).is_equal(["Owed wages", "75", MoneySlot.ATTENTION])


func test_owed_wages_use_the_attention_style_in_the_hover_card() -> void:
	var card: Control = _slot.make_card(MoneySlot.heading(_ledger), MoneySlot.rows(_ledger, 75))
	auto_free(card)
	assert_object(card.theme).is_same(BuildMenu.HUD_THEME)
	var owed: Label = null
	var styles := {}
	for label in card.find_children("*", "Label", true, false):
		styles[(label as Label).text] = (label as Label).theme_type_variation
		if (label as Label).text == "Owed wages":
			owed = label
	assert_object(owed).is_not_null()
	assert_str(String(owed.theme_type_variation)).is_equal(String(MoneySlot.ATTENTION))
	assert_str(String(styles["Airline fees"])).is_not_equal(String(MoneySlot.ATTENTION))


func test_a_ledger_marked_since_load_says_so() -> void:
	_ledger.start_since_load()
	var text := _slot.card_text()
	assert_str(text.get_slice("\n", 0)).is_equal("Since load")
	assert_str(text).contains("Cash change since load  0")
	assert_str(text).not_contains("today")


func test_the_card_follows_the_ledger() -> void:
	assert_bool(_wallet.credit(300, C.FEES)).is_true()
	assert_str(_slot.tooltip_text).contains("Airline fees  +300")


## The card Godot's tooltip popup shows, while it is in the tree.
func _open_card() -> Control:
	var card: Control = _slot._make_custom_tooltip("")
	add_child(card)
	auto_free(card)
	return card


func _shown(card: Control) -> PackedStringArray:
	var texts := PackedStringArray()
	for label in card.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return texts


func test_an_open_card_follows_the_ledger_in_place() -> void:
	var card := _open_card()
	assert_bool(_shown(card).has("Owed wages")).is_false()
	assert_bool(_wallet.credit(100, C.SHOP)).is_true()
	var shown := _shown(card)
	assert_bool(shown.has("+100")).is_true()
	assert_int(shown.count("Shops")).is_equal(1)


func test_an_open_card_updates_its_heading_and_rows() -> void:
	var card := _open_card()
	assert_str(_shown(card)[0]).is_equal("Today")
	_ledger.start_since_load()
	assert_str(_shown(card)[0]).is_equal("Since load")
	assert_bool(_shown(card).has("Cash change since load")).is_true()


func test_a_card_no_longer_shown_is_not_refilled() -> void:
	var card: Control = auto_free(_slot._make_custom_tooltip(""))
	var before := _shown(card)
	assert_bool(_wallet.credit(100, C.SHOP)).is_true()
	assert_array(Array(_shown(card))).is_equal(Array(before))


func test_the_grid_takes_its_spacing_from_the_theme() -> void:
	var card: Control = auto_free(_slot.make_card("Today", MoneySlot.rows(_ledger, 0)))
	var grids := card.find_children("*", "GridContainer", true, false)
	assert_int(grids.size()).is_equal(2)
	for grid in grids:
		assert_str(String((grid as GridContainer).theme_type_variation)).is_equal("HudMoneyGrid")
	assert_int(BuildMenu.HUD_THEME.get_constant(&"h_separation", &"HudMoneyGrid")).is_equal(32)


func test_a_slot_with_no_ledger_has_no_card() -> void:
	var bare: MoneySlot = auto_free(MoneySlot.new())
	assert_str(bare.card_text()).is_empty()
	assert_str(bare.tooltip_text).is_empty()
