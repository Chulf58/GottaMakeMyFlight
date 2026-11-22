class_name TestGameMenuCameraAngle
extends GdUnitTestSuite
## Esc -> Settings Camera Angle selector: selects presets, persists through
## TycoonCamera, displays custom right-dragged pitch without clobbering it on
## open, and retranslates cleanly.

var _kit: IncidentPanelKit
var _camera: TycoonCamera
var _menu: GameMenu
var _path: String


func before_test() -> void:
	_path = SaveTestKit.run_path("game_menu_camera_angle").replace(".json", ".cfg")
	_remove_settings()
	_kit = IncidentPanelKit.new()
	_kit.build(self)
	_camera = _new_camera()
	_menu = GameMenu.new()
	_menu.director = _kit.director
	_menu.clock = _kit.clock
	_menu.save_game = _kit.save
	_menu.camera = _camera
	_kit.port.add_child(_menu)


func after_test() -> void:
	PseudoLocale.disable()
	if _kit != null and is_instance_valid(_kit.port):
		_kit.port.free()
	_remove_settings()


func _remove_settings() -> void:
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


func _new_camera() -> TycoonCamera:
	var scene: PackedScene = load("res://camera/tycoon_camera.tscn")
	var rig := scene.instantiate() as TycoonCamera
	rig.settings_path = _path
	_kit.port.add_child(rig)
	return rig


func test_settings_camera_angle_updates_camera_and_persists() -> void:
	_menu.open()
	_menu.press_settings()
	assert_bool(_menu.camera_angle_picker.visible).is_true()
	var opt := _menu.camera_angle_option
	assert_int(opt.item_count).is_equal(3)
	assert_int(opt.selected).is_equal(TycoonCamera.AngleStep.TOP_DOWN)

	opt.select(TycoonCamera.AngleStep.LOW)
	opt.item_selected.emit(TycoonCamera.AngleStep.LOW)
	assert_int(_camera.angle_step).is_equal(TycoonCamera.AngleStep.LOW)
	assert_float(_camera.pitch_degrees()).is_equal_approx(38.0, 0.001)

	var reloaded := _new_camera()
	assert_int(reloaded.angle_step).is_equal(TycoonCamera.AngleStep.LOW)
	assert_float(reloaded.pitch_degrees()).is_equal_approx(38.0, 0.001)


func test_opening_settings_preserves_custom_dragged_pitch_and_allows_preset_reset() -> void:
	_camera.set_pitch_degrees(46.2)
	_menu.open()
	_menu.press_settings()
	assert_float(_camera.pitch_degrees()).is_equal_approx(46.2, 0.001)
	var opt := _menu.camera_angle_option
	assert_int(opt.item_count).is_equal(4)
	assert_int(opt.selected).is_equal(3)
	assert_str(opt.get_item_text(3)).is_equal("Custom (46°)")

	opt.select(TycoonCamera.AngleStep.MEDIUM)
	opt.item_selected.emit(TycoonCamera.AngleStep.MEDIUM)
	assert_int(opt.item_count).is_equal(3)
	assert_int(opt.selected).is_equal(TycoonCamera.AngleStep.MEDIUM)
	assert_float(_camera.pitch_degrees()).is_equal_approx(54.0, 0.001)

	var reloaded := _new_camera()
	assert_float(reloaded.pitch_degrees()).is_equal_approx(54.0, 0.001)


func test_camera_angle_selector_is_routed_through_tr() -> void:
	PseudoLocale.enable(0.4)
	_menu.open()
	_menu.press_settings()
	var label := _menu.camera_angle_picker.get_node("Label") as Label
	var opt := _menu.camera_angle_option
	assert_str(label.text).starts_with("[")
	assert_str(label.text).contains("Camera angle")
	assert_str(opt.get_item_text(0)).starts_with("[")
	assert_str(opt.get_item_text(0)).contains("Low (38°)")
	assert_str(opt.get_item_text(1)).contains("Medium (54°)")
	assert_str(opt.get_item_text(2)).contains("Top-Down (70°)")
	PseudoLocale.disable()


func test_settings_selector_updates_when_camera_cycles_or_tilts() -> void:
	_menu.open()
	_menu.press_settings()
	assert_int(_menu.camera_angle_option.selected).is_equal(TycoonCamera.AngleStep.TOP_DOWN)
	_camera.cycle_angle_step()
	assert_int(_menu.camera_angle_option.selected).is_equal(TycoonCamera.AngleStep.LOW)
	_camera.set_pitch_degrees(61.0)
	assert_int(_menu.camera_angle_option.item_count).is_equal(4)
	assert_str(_menu.camera_angle_option.get_item_text(3)).is_equal("Custom (61°)")
