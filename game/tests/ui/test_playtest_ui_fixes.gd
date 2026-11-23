class_name TestPlaytestUiFixes
extends GdUnitTestSuite
## Regression tests for the three Day 1-5 demo exploratory playtest UI bugs:
## 1. Detached get_tree() / teardown callbacks in PassengerHud and AlertStack.
## 2. BuildMenu passive wages-paid grant_hold preempted only by real refusals.
## 3. SaveGame 'Saved to <path>' card clear of MoodToggle, HUD controls, and open sheets.

const LAYOUTS := {
	1.0: Vector2i(1920, 1080),
	1.25: Vector2i(1536, 864),
	1.4: Vector2i(1371, 771),
	1.5: Vector2i(1280, 720),
}
const RESTING_CONTROLS := [
	"MoneySlot",
	"RatingCard",
	"RunwayButton",
	"OffersButton",
	"FlightPanel",
	"MoodToggle",
	"DeparturesToggle",
	"PlannerToggle",
	"DebugToggle",
]

var _port: SubViewport
var _main: Node
var _save_path: String


func before() -> void:
	_port = SubViewport.new()
	_port.size = LAYOUTS[1.0]
	add_child(_port)
	_main = SaveTestKit.boot(_port, 4_070_093)
	_save_path = SaveTestKit.run_path("playtest_ui_fixes_save")
	await await_idle_frame()
	await await_idle_frame()


func after() -> void:
	if _save_path != "" and FileAccess.file_exists(_save_path):
		DirAccess.remove_absolute(_save_path)
	if _save_path != "" and FileAccess.file_exists(_save_path + ".tmp"):
		DirAccess.remove_absolute(_save_path + ".tmp")
	if _port != null:
		_port.free()
		_port = null
	_main = null


func test_detached_passenger_hud_and_alert_stack_teardown_callbacks_guard_tree() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	PassengerTestWorld.tracker = self
	var port := SubViewport.new()
	port.size = Vector2i(1280, 720)
	add_child(port)

	var hud := PassengerHud.new()
	hud.clock = world.clock
	hud.flights = world.flights
	hud.sim = world.sim
	hud.alert_settings_path = SaveTestKit.run_path("detached_hud_alerts")
	hud.departures_settings_path = SaveTestKit.run_path("detached_hud_departures")
	port.add_child(hud)

	var stack := hud.find_child("AlertStack", false, false) as AlertStack
	assert_object(stack).is_not_null()
	hud.refresh()
	assert_bool(hud.is_inside_tree()).is_true()
	assert_bool(stack.is_inside_tree()).is_true()

	# Detach HUD (and its AlertStack child) as happens during scene teardown.
	port.remove_child(hud)
	assert_bool(hud.is_inside_tree()).is_false()
	assert_bool(stack.is_inside_tree()).is_false()

	# Trigger every teardown / signal callback while detached: zero errors, clean handling.
	assert_bool(stack.covered.call()).is_false()
	hud._process(0.016)
	hud.refresh()
	hud._fit_follow()
	hud._place_debug_docks()
	assert_bool(hud._in_current_scene()).is_false()
	assert_object(hud._banner_rect()).is_equal(Rect2())
	stack._process(0.016)
	stack.refresh()
	assert_float(stack._stop_y()).is_equal(0.0)
	stack._layout_cards()
	stack._retranslate()

	# Realistic DemoEndCard -> Back to Title teardown ordering:
	# re-attach HUD under a scene root, then tear down the root via remove_child + queue_free
	# inside back_to_title while firing covered/refresh callbacks mid-teardown.
	var scene_root := Node.new()
	port.add_child(scene_root)
	scene_root.add_child(hud)
	var back_calls := [0]
	hud.demo_end_card.back_to_title = func() -> void:
		back_calls[0] += 1
		port.remove_child(scene_root)
		assert_bool(stack.covered.call()).is_false()
		hud.refresh()
		stack.refresh()
		scene_root.queue_free()
	hud.demo_end_card._shown = true
	hud.demo_end_card._build_layer()
	hud.demo_end_card.press_back_to_title()
	await await_idle_frame()
	assert_int(back_calls[0]).is_equal(1)
	assert_bool(is_instance_valid(hud)).is_false()

	# Also detach a standalone AlertStack with a freed `above` control.
	var standalone := AlertStack.new()
	standalone.settings_path = SaveTestKit.run_path("detached_standalone_alerts")
	standalone.sim = world.sim
	var above := Control.new()
	port.add_child(above)
	standalone.above = above
	port.add_child(standalone)
	standalone.refresh()
	port.remove_child(standalone)
	above.free()
	standalone._place()
	standalone.refresh()
	assert_float(standalone._stop_y()).is_equal(0.0)

	DirAccess.remove_absolute(SaveTestKit.run_path("detached_hud_alerts"))
	DirAccess.remove_absolute(SaveTestKit.run_path("detached_hud_departures"))
	DirAccess.remove_absolute(standalone.settings_path)
	standalone.free()
	port.free()
	world.free_all()
	PassengerTestWorld.tracker = null


func test_active_refusal_preempts_passive_wages_grant_hold_immediately() -> void:
	var port := SubViewport.new()
	port.size = Vector2i(1280, 720)
	add_child(port)
	var finances := Finances.new()
	port.add_child(finances)
	var rating := AirportRating.new()
	port.add_child(rating)
	var pax := PassengerSim.new()
	port.add_child(pax)
	var unlocks := BuildUnlocks.new()
	unlocks.rating = rating
	unlocks.passengers = pax
	unlocks.manual = true
	port.add_child(unlocks)
	var mode := BuildMode.new()
	mode.grid_size = Vector2i(20, 20)
	mode.finances = finances
	mode.unlocks = unlocks
	mode.require_unlocks = true
	port.add_child(mode)
	var menu := BuildMenu.new()
	menu.build_mode = mode
	port.add_child(menu)

	# Control 1: ordinary non-refusal status hints, tool guidance, drag dimensions,
	# empty status resets, and off-grid hover noise must NOT cancel a passive hold.
	menu._on_wages_paid(60, 0)
	assert_str(menu.status_label().text).is_equal("Wages paid: 60")
	mode.set_tool(BuildMode.Tool.DESK)
	assert_str(menu.status_label().text).is_equal("Wages paid: 60")
	mode._set_status("4 x 3")
	assert_str(menu.status_label().text).is_equal("Wages paid: 60")
	mode.set_tool(BuildMode.Tool.FLOOR)
	assert_str(menu.status_label().text).is_equal("Wages paid: 60")
	mode._update_ghost(mode.grid.cell_to_world(Vector2i(-3, -3)))
	assert_str(menu.status_label().text).is_equal("Wages paid: 60")

	# Same protection holds for an unlock passive hold.
	menu._on_unlocked(2, "Unlocked: Cafes")
	mode._set_status("Facing auto")
	assert_str(menu.status_label().text).is_equal("Unlocked: Cafes")
	var locked_refusal_tool := BuildMode.Tool.TREE
	mode.set_tool(locked_refusal_tool)
	assert_str(menu.status_label().text).contains("Unlocks at")

	# Real demo-cap refusal preempts the passive wage hold immediately.
	menu._on_wages_paid(60, 0)
	var hold_gen: int = menu._hold_generation
	menu.refresh_preview()
	assert_str(menu.status_label().text).is_equal("Wages paid: 60")
	assert_bool(menu.status_label().visible).is_true()

	var demo_refusal := "Demo limit: 1 extra plot (more in the full game)"
	mode.notify_refusal(demo_refusal)
	assert_str(menu.status_label().text).is_equal(demo_refusal)
	assert_bool(menu.status_label().visible).is_true()

	# Old wage hold timer firing later must not overwrite or clear the active refusal.
	menu._on_hold_timeout(hold_gen)
	assert_str(menu.status_label().text).is_equal(demo_refusal)

	# Verify grid.edit_refused preempts when the same refusal text repeats on click.
	mode.set_tool(BuildMode.Tool.DESK)
	var out_cell := Vector2i(-2, -2)
	mode._update_ghost(mode.grid.cell_to_world(out_cell))
	menu._on_wages_paid(90, 0)
	assert_str(menu.status_label().text).is_equal("Wages paid: 90")
	var click_result := mode.apply_at(mode.grid.cell_to_world(out_cell))
	assert_object(click_result).is_not_null()
	assert_bool(click_result.ok).is_false()
	assert_str(menu.status_label().text).is_equal(click_result.reason_text())

	# Control 2: RescueGrant hold stays protected over passive updates and refusals.
	menu._on_granted(100, "Rescue grant")
	mode.notify_refusal("Needs a floor")
	assert_str(menu.status_label().text).is_equal("Rescue grant")

	port.free()


func test_save_status_does_not_overlap_mood_toggle_or_hud_at_all_scales() -> void:
	var save := _main.get_node("SaveGame") as SaveGame
	var mood := _main.find_child("MoodToggle", true, false) as Control
	var menu := _main.get_node("BuildMenu") as BuildMenu
	var flights := _main.get_node("FlightSim") as FlightSim
	var runway_card := _main.get_node("RunwayCard")
	var offer_panel := _main.get_node("OfferPanel")
	var msg := save.get_node("SaveMessage/Message") as Label
	assert_object(save).is_not_null()
	assert_object(mood).is_not_null()
	assert_object(msg).is_not_null()
	if flights.opened_tick < 0:
		flights.open_airport()
		await await_idle_frame()

	for ui_scale: float in LAYOUTS:
		var layout_size: Vector2i = LAYOUTS[ui_scale]
		_port.size = layout_size
		await await_idle_frame()
		await await_idle_frame()

		# 1. Resting HUD (no sheet open)
		assert_bool(save.save_to_file(_save_path)).is_true()
		await await_idle_frame()
		_assert_save_msg_clear(msg, mood, menu, layout_size, ui_scale, null)

		# 2. Open RunwaySheet
		runway_card.open()
		await await_idle_frame()
		var runway_sheet := _main.find_child("RunwaySheet", true, false) as Control
		assert_bool(runway_sheet.is_visible_in_tree()).is_true()
		assert_bool(save.save_to_file(_save_path)).is_true()
		await await_idle_frame()
		_assert_save_msg_clear(msg, mood, menu, layout_size, ui_scale, runway_sheet)
		runway_card.close()
		await await_idle_frame()

		# 3. Open OfferSheet
		offer_panel.open()
		await await_idle_frame()
		var offer_sheet := _main.find_child("OfferSheet", true, false) as Control
		assert_bool(offer_sheet.is_visible_in_tree()).is_true()
		assert_bool(save.save_to_file(_save_path)).is_true()
		await await_idle_frame()
		_assert_save_msg_clear(msg, mood, menu, layout_size, ui_scale, offer_sheet)
		offer_panel.close()
		await await_idle_frame()

	# Verify viewport.size_changed disconnects cleanly when SaveGame exits tree.
	var temp_port := SubViewport.new()
	temp_port.size = Vector2i(1280, 720)
	add_child(temp_port)
	var temp_save := SaveGame.new()
	temp_port.add_child(temp_save)
	assert_bool(temp_port.size_changed.is_connected(temp_save._place_label)).is_true()
	temp_port.remove_child(temp_save)
	assert_bool(temp_port.size_changed.is_connected(temp_save._place_label)).is_false()
	temp_save.free()
	temp_port.free()


func _assert_save_msg_clear(
	msg: Label,
	mood: Control,
	menu: BuildMenu,
	layout_size: Vector2i,
	ui_scale: float,
	open_sheet: Control
) -> void:
	assert_bool(msg.is_visible_in_tree()).is_true()
	assert_str(msg.text).starts_with("Saved to ")
	var msg_rect := msg.get_global_rect()
	var mood_rect := mood.get_global_rect()
	assert_float(msg_rect.size.x).is_greater(0.0)
	assert_float(msg_rect.size.y).is_greater(0.0)
	(
		assert_bool(Rect2(Vector2.ZERO, Vector2(layout_size)).encloses(msg_rect))
		. override_failure_message(
			"SaveMessage %s leaves viewport %s at scale %.2f" % [msg_rect, layout_size, ui_scale]
		)
		. is_true()
	)
	(
		assert_bool(msg_rect.intersects(mood_rect))
		. override_failure_message(
			"SaveMessage %s overlaps MoodToggle %s at scale %.2f" % [msg_rect, mood_rect, ui_scale]
		)
		. is_false()
	)
	if open_sheet != null:
		var sheet_rect := open_sheet.get_global_rect()
		(
			assert_bool(msg_rect.intersects(sheet_rect))
			. override_failure_message(
				(
					"SaveMessage %s overlaps open sheet %s (%s) at scale %.2f"
					% [msg_rect, open_sheet.name, sheet_rect, ui_scale]
				)
			)
			. is_false()
		)
	for node_name: String in RESTING_CONTROLS:
		var control := _main.find_child(node_name, true, false) as Control
		if control == null or not control.is_visible_in_tree():
			continue
		var other := control.get_global_rect()
		(
			assert_bool(msg_rect.intersects(other))
			. override_failure_message(
				(
					"SaveMessage %s overlaps %s %s at scale %.2f"
					% [msg_rect, node_name, other, ui_scale]
				)
			)
			. is_false()
		)
	assert_bool(msg_rect.intersects(menu.bar().get_global_rect())).is_false()
