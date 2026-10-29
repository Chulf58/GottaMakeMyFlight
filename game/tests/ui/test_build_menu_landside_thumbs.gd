class_name TestBuildMenuLandsideThumbs
extends GdUnitTestSuite
## The Landside tray's four cards (curb bay, surface lot, multi-storey and
## open / close) show their rendered thumbnails (decision build-menu-item-
## cards-use-thumbnails-rendered-from-the-inter; tools/blender/thumbnails/
## render_kit_thumbnails.py), no longer placeholder tiles.

const LANDSIDE_TOOLS := [
	BuildMode.Tool.CURB,
	BuildMode.Tool.SURFACE_LOT,
	BuildMode.Tool.MULTI_STOREY,
	BuildMode.Tool.LOT_GATE,
]

var _port: SubViewport
var _menu: BuildMenu


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	var mode := BuildMode.new()
	mode.grid_size = Vector2i(10, 10)
	_port.add_child(mode)
	mode.set_process(false)
	_menu = BuildMenu.new()
	_menu.build_mode = mode
	_port.add_child(_menu)


func after_test() -> void:
	_port.free()


func test_the_landside_cards_show_their_rendered_thumbnails() -> void:
	assert_array(BuildMenu.PLACEHOLDER_THUMBNAILS).is_empty()
	for tool in LANDSIDE_TOOLS:
		var name: String = BuildMenu.item(tool)[1]
		var picture := (
			_menu.card(tool).find_children("*", "TextureRect", true, false)[0] as TextureRect
		)
		print("card %s thumbnail %s" % [name, picture.texture])
		assert_object(picture.texture).override_failure_message(name).is_not_null()
		assert_str(picture.texture.resource_path).is_equal(BuildMenu.THUMBNAIL_DIR % name)
		assert_int(picture.texture.get_width()).is_equal(256)
		assert_int(picture.find_children("*", "ColorRect", true, false).size()).is_equal(0)
