class_name TestAlertStack
extends GdUnitTestSuite
## The alert card stack (HUD 1/7, decision hud-steal-list-self-clearing-alert-
## cards-money-hover-departu): a card comes up when its cause is true and
## clears itself when it ends, a click glides the camera to the problem and
## the next click to the next place, every card goes in a history tray, and
## the on/off setting (decision optional-hud-pieces-keep-their-on-off-setting-
## in-user-hud-se) hides the cards but keeps the history. The dirty-terminal
## cause drives it here, since spills and cleaning are exact.

const ROW_Y := 8

var _world: PassengerTestWorld
var _path: String
var _stack: AlertStack
var _camera: TycoonCamera


func before() -> void:
	PassengerTestWorld.tracker = self
	_world = MessTestKit.open_world()


func after() -> void:
	_world.free_all()
	_world = null
	PassengerTestWorld.tracker = null


func before_test() -> void:
	assert_bool(MessTestKit.clear(_world)).is_true()
	_path = SaveTestKit.run_path("alert_stack_setting")
	_camera = TycoonCamera.new()
	var eye := Camera3D.new()
	eye.name = "Camera3D"
	_camera.add_child(eye)
	add_child(_camera)
	_stack = _stack_at(_path)


func after_test() -> void:
	_stack.free()
	_camera.free()
	DirAccess.remove_absolute(_path)


func _stack_at(path: String) -> AlertStack:
	var stack := AlertStack.new()
	stack.settings_path = path
	stack.sim = _world.sim
	stack.camera = _camera
	add_child(stack)
	return stack


## SHOW_AT fresh spills on separate cells, in id order; returns their cells.
func _spills() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for i in DirtyAlert.SHOW_AT:
		var cell := Vector2i(2 + i * 2, ROW_Y)
		assert_int(_world.sim.messes.add(MessSim.Kind.SPILL, cell)).is_greater(0)
		cells.append(cell)
	return cells


func _footprint_of(grid: BuildGrid, id: int) -> Array[Vector2i]:
	var record := grid.get_object(id)
	var def := BuildCatalog.get_def(StringName(record["def"]))
	return def.footprint(record["anchor"], record["facing"])


func _clean_all() -> void:
	for id in _world.sim.messes.mess_ids():
		assert_bool(_world.sim.messes.clean(id)).is_true()


func _cards(stack: AlertStack) -> Control:
	return stack.find_child("AlertCards", true, false) as Control


func _left_click() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	return click


func test_a_card_comes_up_with_its_cause_and_clears_itself_when_it_ends() -> void:
	_stack.refresh()
	assert_array(_stack.card_keys()).is_empty()
	_spills()
	_stack.refresh()
	assert_array(_stack.card_keys()).is_equal([DirtyAlert.KEY])
	var card := _stack.card_node(DirtyAlert.KEY)
	assert_object(card).is_not_null()
	assert_bool(card.is_visible_in_tree()).is_true()
	assert_str(_stack.card_text(DirtyAlert.KEY)).contains(DirtyAlert.TITLE)
	assert_str(_stack.card_text(DirtyAlert.KEY)).contains(DirtyAlert.HIRE_TEXT)
	_clean_all()
	_stack.refresh()
	assert_array(_stack.card_keys()).is_empty()
	assert_object(_stack.card_node(DirtyAlert.KEY)).is_null()


func test_a_click_glides_the_camera_to_the_problem_and_the_next_to_the_next() -> void:
	var cells := _spills()
	_stack.refresh()
	_camera.distance = 200.0
	var jumps: Array[Vector3] = []
	_stack.jumped.connect(func(target: Vector3) -> void: jumps.append(target))
	# A real click on the card, through its gui_input.
	_stack.card_node(DirtyAlert.KEY).gui_input.emit(_left_click())
	assert_int(jumps.size()).is_equal(1)
	var near := Vector3.ONE * 0.01
	assert_vector(jumps[0]).is_equal_approx(_world.sim.grid.cell_to_world(cells[0]), near)
	assert_bool(_camera.is_gliding()).is_true()
	assert_float(_camera.target_distance).is_equal(AlertStack.JUMP_DISTANCE)
	assert_bool(_stack.press_card(DirtyAlert.KEY)).is_true()
	assert_vector(jumps[1]).is_equal_approx(_world.sim.grid.cell_to_world(cells[1]), near)
	# A click on a card that is not up does nothing.
	assert_bool(_stack.press_card(&"nothing")).is_false()
	assert_int(jumps.size()).is_equal(2)


func test_a_jump_never_zooms_out_a_camera_that_is_already_close() -> void:
	_spills()
	_stack.refresh()
	_camera.distance = 12.0
	assert_bool(_stack.press_card(DirtyAlert.KEY)).is_true()
	assert_float(_camera.target_distance).is_equal(12.0)


func test_a_jump_zooms_from_the_current_distance_not_one_still_easing_out() -> void:
	_spills()
	_stack.refresh()
	_camera.distance = 12.0
	_camera.target_distance = 200.0
	assert_bool(_stack.press_card(DirtyAlert.KEY)).is_true()
	assert_float(_camera.target_distance).is_equal(12.0)


func test_the_sim_is_scanned_once_per_tick_however_often_it_refreshes() -> void:
	_stack.refresh()
	assert_int(_stack.scans).is_equal(1)
	for i in 5:
		_stack.refresh()
	assert_int(_stack.scans).is_equal(1)
	_world.step()
	_stack.refresh()
	assert_int(_stack.scans).is_equal(2)
	_stack.refresh()
	assert_int(_stack.scans).is_equal(2)


## Two desks whose lanes hold 3 each, both full, with the card up.
func test_a_paused_build_edit_updates_the_queue_card_without_a_tick() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(10, 5))
	var first := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(2, 1), 0)
	var second := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(6, 1), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 4), 3)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	for i in 12:
		world.sim.spawn_now(PassengerTestWorld.FLIGHT)
		world.run_to(world.clock.tick + 12)
	world.run_to(world.clock.tick + 25)
	var stack := _stack_at(SaveTestKit.run_path("alert_stack_paused_edit"))
	stack.sim = world.sim
	stack.refresh()
	world.run_to(world.clock.tick + AlertSources.QUEUE_HOLD_TICKS)
	stack.refresh()
	assert_array(stack.card_keys()).is_equal([AlertSources.QUEUE_CHECKIN])
	assert_str(stack.card_text(AlertSources.QUEUE_CHECKIN)).contains("2 desks full")
	(
		assert_int((stack.board().alert(AlertSources.QUEUE_CHECKIN)["targets"] as Array).size())
		. is_equal(2)
	)
	# The player takes a desk down in a paused build session: no tick passes.
	var tick := world.sim.tick
	assert_bool(grid.apply(BuildEdit.remove_object(second)).ok).is_true()
	stack.refresh()
	assert_int(world.sim.tick).is_equal(tick)
	assert_str(stack.card_text(AlertSources.QUEUE_CHECKIN)).contains("1 desk full")
	var targets: Array = stack.board().alert(AlertSources.QUEUE_CHECKIN)["targets"]
	assert_int(targets.size()).is_equal(1)
	assert_array(_footprint_of(grid, first)).contains([grid.world_to_cell(targets[0])])
	stack.free()
	world.free_all()


func test_a_reset_or_a_new_sim_scans_again_on_the_same_tick() -> void:
	_stack.refresh()
	assert_int(_stack.scans).is_equal(1)
	_stack.reset()
	_stack.refresh()
	assert_int(_stack.scans).is_equal(2)
	var other := MessTestKit.open_world(2)
	other.run_to(_world.sim.tick)
	_stack.sim = other.sim
	_stack.refresh()
	assert_int(_stack.scans).is_equal(3)
	_stack.sim = _world.sim
	other.free_all()


func test_the_history_tray_lists_each_card_with_when_it_cleared() -> void:
	assert_bool(_stack.is_tray_open()).is_false()
	_spills()
	_stack.refresh()
	var lines := _stack.history_lines()
	assert_int(lines.size()).is_equal(1)
	assert_str(lines[0]).contains(DirtyAlert.TITLE)
	assert_str(lines[0]).contains("still up")
	_clean_all()
	_stack.refresh()
	lines = _stack.history_lines()
	assert_int(lines.size()).is_equal(1)
	assert_str(lines[0]).contains("cleared")
	_stack.set_tray_open(true)
	var tray := _stack.find_child("AlertHistory", true, false) as Control
	assert_bool(tray.is_visible_in_tree()).is_true()
	var shown := tray.find_children("*", "Label", true, false)
	assert_bool(shown.any(func(l: Label) -> bool: return l.text == lines[0])).is_true()


func test_the_off_setting_hides_the_cards_but_keeps_the_history() -> void:
	assert_bool(_stack.cards_on()).is_true()
	_stack.set_cards_on(false)
	_spills()
	_stack.refresh()
	assert_bool(_cards(_stack).is_visible_in_tree()).is_false()
	assert_int(_stack.history_lines().size()).is_equal(1)
	assert_str(_stack.history_lines()[0]).contains(DirtyAlert.TITLE)
	# The choice is saved: a stack made later starts off.
	var later := _stack_at(_path)
	assert_bool(later.cards_on()).is_false()
	later.free()
	# On again: the card that is up shows at once.
	_stack.set_cards_on(true)
	_stack.refresh()
	assert_bool(_cards(_stack).is_visible_in_tree()).is_true()
	assert_array(_stack.card_keys()).is_equal([DirtyAlert.KEY])


func test_the_history_toggle_turns_the_cards_off_and_on() -> void:
	_stack.set_tray_open(true)
	var toggle := _stack.find_child("AlertCardsToggle", true, false) as BaseButton
	assert_bool(toggle.button_pressed).is_true()
	toggle.button_pressed = false
	assert_bool(_stack.cards_on()).is_false()
	toggle.button_pressed = true
	assert_bool(_stack.cards_on()).is_true()


func test_one_card_per_cause_however_often_it_refreshes() -> void:
	_spills()
	for i in 10:
		_stack.refresh()
	assert_int(_cards(_stack).get_child_count()).is_equal(1)
	assert_int(_stack.history_lines().size()).is_equal(1)


func test_the_stack_is_not_drawn_while_covered_and_returns_after() -> void:
	var covering := [false]
	_stack.covered = func() -> bool: return covering[0]
	_spills()
	_stack.refresh()
	assert_bool(_stack.visible).is_true()
	covering[0] = true
	_stack.refresh()
	assert_bool(_stack.visible).is_false()
	assert_array(_stack.card_keys()).is_equal([DirtyAlert.KEY])
	covering[0] = false
	_stack.refresh()
	assert_bool(_stack.visible).is_true()


func test_cards_take_the_mouse_and_the_rest_of_the_stack_lets_it_through() -> void:
	_spills()
	_stack.refresh()
	var card := _stack.card_node(DirtyAlert.KEY)
	assert_int(card.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	for label in card.find_children("*", "Label", true, false):
		assert_int((label as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(_stack.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(_cards(_stack).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_a_new_sim_drops_the_cards_and_the_history() -> void:
	_spills()
	_stack.refresh()
	assert_int(_stack.history_lines().size()).is_equal(1)
	var other := MessTestKit.open_world(2)
	_stack.sim = other.sim
	assert_array(_stack.card_keys()).is_empty()
	assert_int(_stack.history_lines().size()).is_equal(0)
	assert_object(_stack.dirty_source().sim).is_same(other.sim)
	_stack.sim = _world.sim
	other.free_all()


func test_the_width_shrinks_with_the_viewport_down_to_a_floor() -> void:
	assert_float(AlertStack.width_for(1536.0)).is_equal(AlertStack.WIDTH)
	assert_float(AlertStack.width_for(1280.0)).is_equal(AlertStack.WIDTH)
	assert_float(AlertStack.width_for(800.0)).is_equal(
		800.0 - AlertStack.RIGHT_GAP - AlertStack.LEFT_MARGIN
	)
	assert_float(AlertStack.width_for(400.0)).is_equal(AlertStack.MIN_WIDTH)
