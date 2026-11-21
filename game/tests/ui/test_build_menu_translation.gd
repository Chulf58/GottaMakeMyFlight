class_name TestBuildMenuTranslation
extends GdUnitTestSuite
## The build menu's names live in English tables (they key icons and tests) and
## reach the screen through BuildMenuCatalog.shown(). Each Words.msgids() lists
## those names inside tr(), so POT generation finds them; this suite checks the
## lists are complete, that English output is unchanged, and that pseudolocalization
## reaches the names.

## Build menu and Templates scripts whose tr() calls must exist in messages.pot.
const ROUTED := [
	"res://ui/build_menu_catalog.gd",
	"res://ui/build_menu.gd",
	"res://ui/build_menu_layout.gd",
	"res://ui/templates_page.gd",
]


func after_test() -> void:
	PseudoLocale.disable()
	TranslationServer.pseudolocalization_enabled = false
	TranslationServer.reload_pseudolocalization()


func test_the_catalog_msgids_hold_every_name_of_its_tables() -> void:
	var ids := BuildMenuCatalog.Words.new().msgids()
	var wanted: Array[String] = ["Staff", "Templates", "All", "Room"]
	for category: Dictionary in BuildMenuCatalog.CATEGORIES:
		wanted.append(category["name"])
		wanted.append(category.get("group", category["name"]))
	for cat_id: String in BuildMenuCatalog.SUBFILTERS:
		for entry: Dictionary in BuildMenuCatalog.SUBFILTERS[cat_id]:
			wanted.append(entry["name"])
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


func _wanted_entries(source: String) -> Array[Dictionary]:
	var string_arg := '"((?:[^"\\\\]|\\\\.)*)"'
	var tr_pattern := RegEx.create_from_string(
		"\\btr\\(\\s*" + string_arg + "\\s*(?:,\\s*" + string_arg + ")?"
	)
	var tr_n_pattern := RegEx.create_from_string(
		"\\btr_n\\(\\s*" + string_arg + "\\s*,\\s*" + string_arg + "\\s*,[^,]*,\\s*" + string_arg
	)
	var wanted: Array[Dictionary] = []
	for found in tr_pattern.search_all(source):
		wanted.append({"ctx": found.get_string(2), "id": found.get_string(1), "plural": ""})
	for found in tr_n_pattern.search_all(source):
		wanted.append(
			{"ctx": found.get_string(3), "id": found.get_string(1), "plural": found.get_string(2)}
		)
	return wanted


func test_every_build_menu_and_templates_msgid_is_in_the_pot() -> void:
	var template := FileAccess.get_file_as_string("res://locale/messages.pot").replace("\r\n", "\n")
	var entries := PotEntries.parse(template)
	assert_array(PotEntries.malformed(entries)).is_empty()
	assert_array(PotEntries.duplicates(entries)).is_empty()
	var checked := 0
	var missing: Array[String] = []
	for path: String in ROUTED:
		var source := FileAccess.get_file_as_string(path)
		for want: Dictionary in _wanted_entries(source):
			checked += 1
			if (
				PotEntries.count(entries, want["ctx"], want["id"], want["plural"]) != 1
				or PotEntries.complete(entries, want["ctx"], want["id"], want["plural"]) != 1
			):
				missing.append("%s: %s" % [path, str(want)])
	for word: String in BuildMenuCatalog.Words.new().msgids():
		checked += 1
		if (
			PotEntries.count(entries, BuildMenuCatalog.NAME_CONTEXT, word) != 1
			or PotEntries.complete(entries, BuildMenuCatalog.NAME_CONTEXT, word) != 1
		):
			missing.append("Words.msgids: %s" % word)
	print("build/templates POT entries checked: %d, missing: %s" % [checked, missing])
	assert_int(checked).is_greater(90)
	assert_array(missing).is_empty()
