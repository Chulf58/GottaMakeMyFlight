class_name TestRescueGrantMessage
extends GdUnitTestSuite
## The grant comes "with a message" (ruling going-broke-a-one-off-rescue-grant-
## when-the-airport-is-stuck): BuildMenu shows it on its status line, which
## wears the shared HUD theme (decision hud-theme-file-game-ui-hud-theme-tres-
## nunito-font-set-on-eac).

var _world: PassengerTestWorld
var _grant: RescueGrant
var _menu: BuildMenu


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(100000))
	_grant = auto_free(RescueGrant.new())
	_grant.bind(_world.clock, _world.sim, _world.sim.wallet)
	_menu = BuildMenu.new()
	_menu.rescue_grant = _grant
	add_child(_menu)


func after_test() -> void:
	_menu.free()
	_world.free_all()
	_world = null


func test_a_paid_grant_shows_its_message_on_the_status_line() -> void:
	var said: Array[String] = []
	_grant.granted.connect(func(_amount: int, text: String) -> void: said.append(text))
	for id in ReferenceTerminal.object_ids(_world.grid)["scanners"]:
		_world.grid.apply(BuildEdit.remove_object(id))
	_world.step()
	print("said %s label '%s'" % [said, _menu.status_label().text])
	assert_array(said).has_size(1)
	assert_str(_menu.status_label().text).is_equal(said[0])
	assert_str(said[0]).contains("rescue grant")
	assert_object(_menu.status_label().theme).is_same(BuildMenu.HUD_THEME)


func test_no_grant_leaves_the_status_line_alone() -> void:
	_world.step()
	assert_str(_menu.status_label().text).is_empty()


func test_status_text_waits_while_the_grant_message_is_held() -> void:
	for id in ReferenceTerminal.object_ids(_world.grid)["scanners"]:
		_world.grid.apply(BuildEdit.remove_object(id))
	_world.step()
	var message := _menu.status_label().text
	assert_str(message).contains("rescue grant")
	_menu._on_status_changed("Not enough money")
	assert_str(_menu.status_label().text).is_equal(message)
	_menu.end_grant_hold()
	assert_str(_menu.status_label().text).is_equal("Not enough money")
	_menu._on_status_changed("Placed 1 for 25")
	assert_str(_menu.status_label().text).is_equal("Placed 1 for 25")


## A second grant inside the first one's hold gets a full hold of its own.
func test_a_second_grant_inside_the_hold_keeps_its_full_hold() -> void:
	_menu.grant_hold_s = 0.3
	_grant.granted.emit(10, "first grant")
	await get_tree().create_timer(0.2).timeout
	_grant.granted.emit(20, "second grant")
	_menu._on_status_changed("hover text")
	await get_tree().create_timer(0.2).timeout
	print("after the first hold ran out: '%s'" % _menu.status_label().text)
	assert_str(_menu.status_label().text).is_equal("second grant")
	await get_tree().create_timer(0.25).timeout
	assert_str(_menu.status_label().text).is_equal("hover text")
