class_name TestBuildMenuTranslation
extends GdUnitTestSuite
## The build menu's names live in English tables (they key icons and tests) and
## reach the screen through BuildMenuCatalog.shown(). Each Words.msgids() lists
## those names inside tr(), so POT generation finds them; this suite checks the
## lists are complete, that English output is unchanged, and that pseudolocalization
## reaches the names.


func after_test() -> void:
	PseudoLocale.disable()
	TranslationServer.pseudolocalization_enabled = false
	TranslationServer.reload_pseudolocalization()


func test_the_catalog_msgids_hold_every_name_of_its_tables() -> void:
	var ids := BuildMenuCatalog.Words.new().msgids()
	var wanted: Array[String] = ["Staff"]
	for category: Dictionary in BuildMenuCatalog.CATEGORIES:
		wanted.append(category["name"])
		wanted.append(category.get("group", category["name"]))
	for table: Dictionary in [BuildMenuCatalog.ITEMS, BuildMenuCatalog.LANE_ITEMS]:
		for tool: BuildMode.Tool in table:
			wanted.append(table[tool][0])
			if table[tool][2] != "":
				wanted.append(table[tool][2])
	wanted.append_array(BuildMenuCatalog.CARD_NEEDS.values())
	var missing: Array[String] = []
	for name in wanted:
		if not ids.has(name):
			missing.append(name)
	print("catalog names checked: %d, msgids: %d" % [wanted.size(), ids.size()])
	assert_array(missing).is_empty()
	assert_int(wanted.size()).is_greater(75)


func test_the_furniture_msgids_hold_every_card_name() -> void:
	var ids := FurnitureTools.Words.new().msgids()
	var missing: Array[String] = []
	for tool: BuildMode.Tool in FurnitureTools.ITEMS:
		if not ids.has(FurnitureTools.ITEMS[tool][0]):
			missing.append(FurnitureTools.ITEMS[tool][0])
	print("furniture names checked: %d" % FurnitureTools.ITEMS.size())
	assert_array(missing).is_empty()
	assert_int(FurnitureTools.ITEMS.size()).is_greater(25)


func test_the_unlock_msgids_hold_every_tier_facilities_text() -> void:
	var ids := BuildUnlocks.Words.new().facilities()
	var checked := 0
	for tier: Dictionary in BuildUnlocks.TIERS:
		if tier["facilities"] == "":
			continue
		assert_array(ids).contains([tier["facilities"]])
		checked += 1
	assert_int(checked).is_equal(3)


func test_english_output_is_unchanged() -> void:
	assert_str(BuildMenuCatalog.upkeep_text(20)).is_equal("Upkeep 20/day")
	assert_str(BuildMenuCatalog.no_key_hint(BuildMode.Tool.CAFE_ROOM)).is_equal("Drag")
	assert_str(BuildMenuCatalog.no_key_hint(BuildMode.Tool.DESK)).is_equal("Click")
	assert_str(BuildMenuCatalog.shown("Check-in desk")).is_equal("Check-in desk")
	assert_str(BuildMenuCatalog.shown("")).is_empty()
	assert_str(RotateHint.text()).is_equal(RotateHint.TEXT)
	assert_str(BuildUnlocks.requirement_text(3)).is_equal("Unlocks at 3 stars and 200 passengers")
	assert_str(BuildUnlocks.requirement_text(1)).is_equal("Not available yet")
	assert_str(ItemCardButton.card_text("Floor", ["a", "b", "c"], "Locked")).is_equal(
		"Floor\nLocked\na\nHow it works: b\nNeeds and upkeep: c"
	)


func test_pseudolocalization_reaches_a_table_name_and_a_hover_sentence() -> void:
	PseudoLocale.enable(0.4)
	var name := BuildMenuCatalog.shown("Check-in desk")
	var sentence: String = ItemInfo.of(BuildMode.Tool.FLOOR)[0]
	print("shown: %s | %s" % [name, sentence])
	assert_str(name).starts_with("[")
	assert_str(name).ends_with("]")
	assert_int(name.length()).is_greater("Check-in desk".length())
	assert_str(sentence).starts_with("[")
	assert_str(BuildMenuCatalog.shown("")).is_empty()
