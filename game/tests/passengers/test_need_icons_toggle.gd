class_name TestNeedIconsToggle
extends GdUnitTestSuite
## The N key's on/off choice for the need icons (decision passenger-need-icons-
## toggle-key-n-on-by-default): on by default, N hides every icon and N again
## shows them, the choice persists in the HUD settings file, and the zoomed-out
## hide still applies while it is on.

var _world: PassengerTestWorld
var _views: PassengerViews
var _path: String


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_path = SaveTestKit.run_path("need_icons_toggle")
	var grid := BuildGrid.new()
	ToiletTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)


func after_test() -> void:
	DirAccess.remove_absolute(_path)
	if is_instance_valid(_views):
		_views.free()
	_world.free_all()


func _views_at(path: String) -> PassengerViews:
	var views := PassengerViews.new()
	views.clock = _world.clock
	views.sim = _world.sim
	views.need_icons_toggle.settings_path = path
	add_child(views)
	return views


## Three calm passengers, each hungry and needing the toilet, ticked and drawn.
func _needy_nodes() -> Array[Node3D]:
	_views = _views_at(_path)
	var nodes: Array[Node3D] = []
	var ids: Array[int] = []
	for i in 3:
		var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
		ids.append(id)
		var p := _world.passenger(id)
		ToiletTestLayout.calm(p)
		p.hunger = CafeSim.HUNGER_MAX
		p.toilet_need = ToiletSim.NEED_MAX
	_world.step()
	_views.draw()
	for id in ids:
		nodes.append(_views.node_for(id))
	return nodes


func _visible_icons(nodes: Array[Node3D]) -> int:
	var count := 0
	for node in nodes:
		for sprite_name in NeedIcons.SPRITES:
			if (node.get_node(sprite_name) as Sprite3D).visible:
				count += 1
	return count


func _n_key(pressed := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_N
	event.physical_keycode = KEY_N
	event.pressed = pressed
	return event


func test_the_icons_are_on_by_default() -> void:
	var nodes := _needy_nodes()
	var visible := _visible_icons(nodes)
	print("default: passengers %d, visible icons %d" % [nodes.size(), visible])
	assert_bool(_views.need_icons_toggle.is_shown()).is_true()
	assert_int(nodes.size()).is_equal(3)
	assert_int(visible).is_equal(6)


func test_n_hides_every_icon_and_n_again_shows_them() -> void:
	var nodes := _needy_nodes()
	var before := _visible_icons(nodes)
	_views.need_icons_toggle._shortcut_input(_n_key())
	_views.draw()
	var hidden := _visible_icons(nodes)
	_views.need_icons_toggle._shortcut_input(_n_key())
	_views.draw()
	var again := _visible_icons(nodes)
	print("icons visible: before %d, after N %d, after N again %d" % [before, hidden, again])
	assert_int(before).is_equal(6)
	assert_int(hidden).is_equal(0)
	assert_int(again).is_equal(6)


func test_a_held_key_a_release_and_a_modified_press_do_not_toggle() -> void:
	var nodes := _needy_nodes()
	var toggle := _views.need_icons_toggle
	var held := _n_key()
	held.echo = true
	var shifted := _n_key()
	shifted.shift_pressed = true
	for event in [held, _n_key(false), shifted]:
		toggle._shortcut_input(event)
	_views.draw()
	var visible := _visible_icons(nodes)
	print("after echo, release and shift+N: visible icons %d" % visible)
	assert_bool(toggle.is_shown()).is_true()
	assert_int(visible).is_equal(6)


func test_the_choice_is_saved_and_loaded() -> void:
	_needy_nodes()
	var key := NeedIconsToggle.SETTING_KEY
	assert_bool(FileAccess.file_exists(_path)).is_false()
	_views.need_icons_toggle.set_shown(false)
	var saved := HudFlagSetting.load_flag(_path, key, true, "test")
	print("saved after off: %s" % saved)
	assert_bool(saved).is_false()
	var reopened := _views_at(_path)
	var loaded := reopened.need_icons_toggle.is_shown()
	reopened.free()
	print("a new view reads: %s" % loaded)
	assert_bool(loaded).is_false()
	_views.need_icons_toggle.set_shown(true)
	assert_bool(HudFlagSetting.load_flag(_path, key, false, "test")).is_true()


func test_it_keeps_other_hud_settings_in_the_file() -> void:
	HudFlagSetting.save_flag(_path, "departures_board", false, "test")
	_needy_nodes()
	_views.need_icons_toggle.set_shown(false)
	assert_bool(HudFlagSetting.load_flag(_path, "departures_board", true, "test")).is_false()
	(
		assert_bool(HudFlagSetting.load_flag(_path, NeedIconsToggle.SETTING_KEY, true, "test"))
		. is_false()
	)


func test_the_zoomed_out_hide_still_applies_while_the_toggle_is_on() -> void:
	var rig := (
		(load("res://camera/tycoon_camera.tscn") as PackedScene).instantiate() as TycoonCamera
	)
	rig.home_distance = 40.0
	add_child(rig)
	rig.set_process(false)
	(rig.get_node("Camera3D") as Camera3D).make_current()
	var nodes := _needy_nodes()
	var seen := {}
	for distance in [12.0, 60.0]:
		rig.distance = distance
		_views.draw()
		seen[distance] = _visible_icons(nodes)
	_views.need_icons_toggle.set_shown(false)
	rig.distance = 12.0
	_views.draw()
	var off_close := _visible_icons(nodes)
	print("on: close %d, zoomed out %d; off, close: %d" % [seen[12.0], seen[60.0], off_close])
	rig.free()
	assert_int(seen[12.0]).is_equal(6)
	assert_int(seen[60.0]).is_equal(0)
	assert_int(off_close).is_equal(0)


func test_n_is_bound_to_the_toggle_action() -> void:
	assert_bool(InputMap.has_action(NeedIconsToggle.ACTION)).is_true()
	assert_bool(InputMap.event_is_action(_n_key(), NeedIconsToggle.ACTION)).is_true()
