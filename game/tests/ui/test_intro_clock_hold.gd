class_name TestIntroClockHold
extends GdUnitTestSuite
## The intro's hold on the clock (decision daily-incidents-technical-design-
## incidentdirector-shared-clo): it does not give way to the player, so a speed
## set while it is open waits for the close and then applies, and it takes the
## exclusive turn ahead of an unlock dialog opened under it.

var _world: PassengerTestWorld
var _hud: PassengerHud
var _shown_before: bool


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_shown_before = IntroDialogue.shown_this_session
	IntroDialogue.shown_this_session = false
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	add_child(_hud)


func after_test() -> void:
	_hud.free()
	_world.free_all()
	IntroDialogue.shown_this_session = _shown_before


func test_a_speed_set_while_open_waits_for_the_close_and_then_applies() -> void:
	_hud.open_intro()
	_world.clock.set_speed(2)
	_world.clock.set_paused(false)
	var tick := _world.clock.tick
	_world.clock.advance(0.11)
	assert_int(_world.clock.tick).is_equal(tick)
	_hud.dismiss_intro()
	assert_bool(_world.clock.paused).is_false()
	assert_int(_world.clock.speed).is_equal(2)
	_world.clock.advance(0.11)
	assert_int(_world.clock.tick - tick).is_equal(4)


func test_an_unlock_dialog_opened_under_the_intro_shows_after_it() -> void:
	_hud.open_intro()
	var guide := _hud.unlock_guide()
	guide.open_dialog([2])
	assert_bool(guide.is_open()).is_false()
	_hud.dismiss_intro()
	assert_bool(guide.is_open()).is_true()
	assert_bool(_world.clock.paused).is_true()
	guide.dismiss()
	assert_bool(_world.clock.paused).is_false()
