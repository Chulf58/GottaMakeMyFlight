class_name TestRoomTemplatesSave
extends GdUnitTestSuite
## Room templates in the whole-world save (decision room-templates-store-
## rooms-with-their-pieces-kept-in-each-sa, point 2): the real main scene's
## BuildMode keeps them, a new game starts with none, a save holds them as the
## "templates" part and a load puts them back; a save without the part is
## refused (save version 4, no migration before a release). One boot of
## main.tscn for the file.

const SEED := 31_102_026

var _main: Node
var _save: SaveGame
var _library: RoomTemplates


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	_library = (_main.get_node("BuildMode") as BuildMode).templates.library
	SaveTestKit.step(_main)


func after() -> void:
	_main.free()


func _cafe() -> RoomTemplate:
	var pieces := [
		{"def": "cafe_counter", "anchor": [1, 0], "facing": 0},
		{"def": "cafe_table", "anchor": [1, 2], "facing": 0},
	]
	var floor_cells := []
	for i in 20:
		floor_cells.append([BuildGrid.FLOOR_TILE, 1])
	var data := {
		"name": "Cafe 5x4", "type": "cafe", "size": [5, 4], "pieces": pieces, "floor": floor_cells
	}
	var read := RoomTemplate.from_dict(data)
	assert_bool(read.has("template")).is_true()
	return read["template"]


## A save taken now, through JSON as a file holds it.
func _taken() -> Dictionary:
	var data := _save.snapshot()
	assert_bool(data.is_empty()).is_false()
	return JSON.parse_string(JSON.stringify(data, "", true, true))


func test_a_new_game_starts_with_no_templates() -> void:
	assert_int(_library.size()).is_equal(0)


func test_a_save_holds_the_templates_and_a_load_puts_them_back() -> void:
	_library.add(_cafe())
	var data := _taken()
	assert_int(int(data["save_version"])).is_equal(4)
	assert_int((data["templates"]["templates"] as Array).size()).is_equal(1)
	var empty := {"save_version": RoomTemplates.SAVE_VERSION, "templates": []}
	assert_bool(_library.from_snapshot(empty)).is_true()
	assert_int(_library.size()).is_equal(0)
	assert_bool(_save.load_world(data)).is_true()
	assert_int(_library.size()).is_equal(1)
	assert_dict(_library.get_template(0).to_dict()).is_equal(_cafe().to_dict())


func test_a_save_without_templates_is_refused_and_keeps_them() -> void:
	_library.from_snapshot({"save_version": RoomTemplates.SAVE_VERSION, "templates": []})
	_library.add(_cafe())
	var old := _taken()
	old.erase("templates")
	assert_bool(_save.load_world(old)).is_false()
	assert_str(_save.message_text()).contains("templates")
	assert_int(_library.size()).is_equal(1)
