class_name TestClockAndPersistentUndo
extends GdUnitTestSuite
## Regression suite for decision
## build-mode-auto-pause-restored-while-offers-planner-stay-unpaused (9e86b858,
## partial override citing ea4411e6):
## - Build trays auto-pause SimClock via a yielding ClockHolds hold and resume
##   on close; Space can still unpause manually while building.
## - OfferPanel and FlightPlanner never pause or unpause SimClock.
## - Ctrl+Z undo persists across tray closes and sim ticks (bounded to 20),
##   refuses cleanly on live wallet/grid conflicts, clears on load / RescueGrant,
##   and stays blocked while modal dialogs (GameMenu, IntroDialogue) own input.
## - Inspect-card Delete removes and refunds directly without build mode or
##   pausing, and Ctrl+Z undoes it cleanly.
## - Modal dialogs (GameMenu, IntroDialogue, IncidentPanel) still hold SimClock.

const STRUCTURE := 0
const STATUE := &"statue_indoor"
const FREE_CELL := Vector2i(3, 3)

var _port: SubViewport
var _clock: SimClock
var _finances: Finances
var _mode: BuildMode
var _save: SaveGame
var _menu: BuildMenu
var _offers: OfferPanel
var _planner: FlightPlanner
var _game_menu: GameMenu
var _incidents: MajorTestDirector
var _incident_panel: IncidentPanel
var _card: BuiltItemCard
var _actions: BuiltItemActions
var _sim: PassengerSim


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_clock = SimClock.new()
	_port.add_child(_clock)
	_finances = Finances.new()
	_port.add_child(_finances)
	_mode = BuildMode.new()
	_mode.initial_tool = BuildMode.Tool.NONE
	_mode.grid_size = Vector2i(12, 12)
	_mode.finances = _finances
	_port.add_child(_mode)
	var edits: Array[BuildEdit] = []
	for y in 12:
		for x in 12:
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	_mode.clear_undo()
	_save = SaveGame.new()
	_port.add_child(_save)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_menu.clock = _clock
	_menu.save_game = _save
	_port.add_child(_menu)
	var flights := FlightSim.new()
	flights.open_airport()
	_port.add_child(flights)
	var desk := auto_free(OfferDesk.new()) as OfferDesk
	desk.runway = Runway.new(PlaneClasses.LARGE)
	desk.clock = _clock
	(
		assert_bool(
			desk.board.from_snapshot(
				TestOfferBoard.save_of(TestOfferBoard.day_records(0, [600, 660, 1200]))
			)
		)
		. is_true()
	)
	_offers = OfferPanel.new()
	_offers.desk = desk
	_offers.flights = flights
	_offers.clock = _clock
	_offers.build_mode = _mode
	_offers.save_game = _save
	_port.add_child(_offers)
	_planner = FlightPlanner.new()
	_planner.flights = flights
	_planner.clock = _clock
	_planner.build_mode = _mode
	_port.add_child(_planner)
	_incidents = MajorTestDirector.new()
	_port.add_child(_incidents)
	_incident_panel = IncidentPanel.new()
	_incident_panel.director = _incidents
	_incident_panel.clock = _clock
	_incident_panel.save_game = _save
	_incident_panel.copy_for = MajorTestDirector.copy
	_port.add_child(_incident_panel)
	_game_menu = GameMenu.new()
	_game_menu.clock = _clock
	_game_menu.build_menu = _menu
	_game_menu.build_mode = _mode
	_game_menu.save_game = _save
	_port.add_child(_game_menu)
	_sim = PassengerSim.new()
	_sim.grid = _mode.grid
	_port.add_child(_sim)
	var selection := BuiltSelection.new()
	_card = BuiltItemCard.new()
	_card.sim = _sim
	_card.selection = selection
	_card.build_mode = _mode
	_card.visible = true
	_port.add_child(_card)
	_actions = BuiltItemActions.new()
	_actions.card = _card
	_actions.session = _menu.build_session
	_port.add_child(_actions)


func after_test() -> void:
	_port.free()


func _key(code: Key, ctrl := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.ctrl_pressed = ctrl
	event.pressed = true
	return event


func _ctrl_z() -> void:
	_port.push_input(_key(KEY_Z, true))


func test_build_tray_auto_pauses_space_unpauses_and_offers_planner_stay_unpaused() -> void:
	_clock.set_speed(3)
	_clock.set_paused(false)
	_menu.press_category(STRUCTURE)
	assert_bool(_menu.is_tray_open()).is_true()
	assert_bool(_menu.build_session.active).is_true()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.holds.count()).is_equal(1)

	# Space unpauses manually while staying in build mode.
	_clock.set_paused(false)
	_menu.build_session.sync()
	assert_bool(_menu.is_tray_open()).is_true()
	assert_bool(_menu.build_session.active).is_true()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.holds.count()).is_equal(0)
	_menu.press_category(STRUCTURE)
	assert_bool(_menu.build_session.active).is_false()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)

	# Re-entering build mode pauses again and closing resumes when no other hold exists.
	_menu.press_category(STRUCTURE)
	assert_bool(_clock.paused).is_true()
	_menu.press_category(STRUCTURE)
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)

	_offers.open()
	assert_bool(_offers.is_open()).is_true()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.holds.count()).is_equal(0)
	assert_int(_clock.speed).is_equal(3)
	_offers.close()
	assert_bool(_clock.paused).is_false()

	_planner.open()
	assert_bool(_planner.is_open()).is_true()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.holds.count()).is_equal(0)
	assert_int(_clock.speed).is_equal(3)
	_planner.close()
	assert_bool(_clock.paused).is_false()

	_clock.set_speed(2)
	_clock.set_paused(true)
	_menu.press_category(STRUCTURE)
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.holds.count()).is_equal(1)
	_offers.open()
	assert_bool(_clock.paused).is_true()
	_planner.open()
	assert_bool(_clock.paused).is_true()
	_planner.close()
	_menu.press_category(STRUCTURE)
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.speed).is_equal(2)
	assert_int(_clock.holds.count()).is_equal(0)


func test_place_close_tray_advance_ticks_and_ctrl_z_undoes_and_refunds() -> void:
	_clock.set_paused(false)
	var before := _finances.wallet.balance
	_menu.press_category(STRUCTURE)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	var statue := _mode.apply_edit(BuildEdit.place_object(STATUE, FREE_CELL, 0))
	assert_bool(statue.ok).is_true()
	assert_int(_finances.wallet.balance).is_less(before)
	_port.push_input(_key(KEY_ESCAPE))
	assert_bool(_menu.is_tray_open()).is_false()
	assert_bool(_menu.build_session.active).is_false()
	for i in 10:
		_clock.advance(SimClock.STEP)
	assert_int(_mode.undo_history().size()).is_equal(1)
	_ctrl_z()
	assert_int(_mode.grid.object_at(FREE_CELL)).is_equal(0)
	assert_int(_finances.wallet.balance).is_equal(before)
	assert_str(_mode.status_text()).contains(UndoStack.UNDONE)


func test_direct_delete_removes_without_build_mode_or_pause_and_ctrl_z_undoes() -> void:
	_clock.set_speed(2)
	_clock.set_paused(false)
	var placed := _mode.apply_edit(BuildEdit.place_object(STATUE, FREE_CELL, 0))
	assert_bool(placed.ok).is_true()
	_mode.clear_undo()
	var before_delete := _finances.wallet.balance
	var saved_price := int(_mode.grid.get_object(placed.object_id)["paid"])
	_card.selection.kind = BuiltSelection.Kind.OBJECT
	_card.selection.id = placed.object_id
	_actions.refresh()
	var result := _actions.press_delete()
	assert_bool(result.ok).is_true()
	assert_bool(_menu.build_session.active).is_false()
	assert_bool(_menu.is_tray_open()).is_false()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.holds.count()).is_equal(0)
	assert_int(_finances.wallet.balance).is_equal(before_delete + PriceTable.refund_of(saved_price))
	for i in 6:
		_clock.advance(SimClock.STEP)
	_ctrl_z()
	assert_int(_mode.grid.object_at(FREE_CELL)).is_not_equal(0)
	assert_int(_finances.wallet.balance).is_equal(before_delete)


func test_ctrl_z_refuses_cleanly_when_wallet_cannot_repay_delete_refund() -> void:
	var placed := _mode.apply_edit(BuildEdit.place_object(STATUE, FREE_CELL, 0))
	assert_bool(placed.ok).is_true()
	_mode.clear_undo()
	_card.selection.kind = BuiltSelection.Kind.OBJECT
	_card.selection.id = placed.object_id
	_actions.refresh()
	assert_bool(_actions.press_delete().ok).is_true()
	# Spend wages during live ticks so wallet drops below the refund owed.
	var balance := _finances.wallet.balance
	assert_bool(_finances.wallet.spend(balance, Wallet.Category.WAGES)).is_true()
	var snapshot := _mode.grid.to_snapshot()
	_ctrl_z()
	assert_str(_mode.status_text()).starts_with(UndoStack.CANT_UNDO)
	assert_int(_mode.grid.object_at(FREE_CELL)).is_equal(0)
	assert_dict(_mode.grid.to_snapshot()).is_equal(snapshot)
	assert_int(_finances.wallet.balance).is_equal(0)
	assert_int(_mode.undo_history().size()).is_equal(1)


func test_ctrl_z_is_blocked_while_game_menu_or_intro_dialogue_is_open() -> void:
	var placed := _mode.apply_edit(BuildEdit.place_object(STATUE, FREE_CELL, 0))
	assert_bool(placed.ok).is_true()
	assert_int(_mode.undo_history().size()).is_equal(1)

	assert_bool(_game_menu.open()).is_true()
	assert_bool(_game_menu.is_open()).is_true()
	_ctrl_z()
	assert_int(_mode.grid.object_at(FREE_CELL)).is_equal(placed.object_id)
	assert_int(_mode.undo_history().size()).is_equal(1)
	_game_menu.close()

	var intro := IntroDialogue.new("Title", "Body")
	_port.add_child(intro)
	_ctrl_z()
	assert_int(_mode.grid.object_at(FREE_CELL)).is_equal(placed.object_id)
	assert_int(_mode.undo_history().size()).is_equal(1)
	intro.free()

	_ctrl_z()
	assert_int(_mode.grid.object_at(FREE_CELL)).is_equal(0)
	assert_int(_mode.undo_history().size()).is_equal(0)


func test_modal_dialogs_still_pause_clock_via_clock_holds() -> void:
	_clock.set_paused(false)
	assert_bool(_game_menu.open()).is_true()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.holds.count()).is_equal(1)
	_game_menu.close()
	assert_bool(_clock.paused).is_false()

	var id := _incidents.add_scheduled()
	_incidents.present(id, false)
	assert_bool(_incident_panel.is_open()).is_true()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.holds.count()).is_equal(1)
	_incident_panel.dialog().continue_button().pressed.emit()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.holds.count()).is_equal(0)
