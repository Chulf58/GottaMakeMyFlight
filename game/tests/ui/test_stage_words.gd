class_name TestStageWords
extends GdUnitTestSuite
## StageWords holds the follow line's stage sentences (board T3). English output
## is covered by test_store_text.gd, test_food_venue_text.gd and
## test_activity_text.gd; this suite covers the lookups the profile reaches.


func after_test() -> void:
	PseudoLocale.disable()


func test_a_shop_name_is_looked_up_in_the_mid_sentence_context() -> void:
	PseudoLocale.enable(0.4)
	var words := StageWords.Words.new()
	var text := words.shop(Passenger.Stage.SHOP_WALK, "kiosk", true)
	print("shop text: %s" % text)
	assert_str(text).starts_with("[")
	assert_str(text).contains("Heading to the kiosk")
	var browse := words.shop(Passenger.Stage.SHOP_BROWSE, "kiosk", true)
	assert_str(browse).contains("Browsing at the kiosk")
	assert_str(words.shop(Passenger.Stage.SHOP_BROWSE, "ATM", false)).contains("Using the ATM")


func test_an_activity_room_has_its_own_verb() -> void:
	var words := StageWords.Words.new()
	assert_str(words.activity(&"play_area", "play area")).is_equal("Playing in the play area")
	assert_str(words.activity(&"lounge", "lounge")).is_equal("Relaxing in the lounge")
	assert_str(words.activity(&"shower", "shower")).is_equal("Using the shower")
	assert_str(words.activity(&"nap_pod", "nap pod")).is_equal("Resting in the nap pod")


func test_the_one_capitalised_shop_name_has_a_msgid() -> void:
	assert_array(StageWords.Words.new().shop_names()).contains(["ATM"])
	# Every other shop name is the lower-case msgid DisplayWords already keeps.
	var shop_types := ["kiosk", "pharmacy", "duty free", "fashion store", "exchange"]
	var ids := DisplayWords.Words.new().msgids()
	for shop in shop_types:
		assert_array(ids).contains([shop])
