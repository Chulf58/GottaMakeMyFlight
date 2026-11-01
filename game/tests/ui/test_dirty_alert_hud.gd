class_name TestDirtyAlertHud
extends GdUnitTestSuite
## The dirty-terminal alert card as the HUD holds it: a replaced sim and a
## successful load both start it hidden, and then SHOW_AT applies afresh, so a
## load with dirt inside the band (CLEAR_BELOW to SHOW_AT - 1) gives the same
## card whether or not the world before the load showed it.

const ROW_Y := 8

var _world: PassengerTestWorld
var _save: SaveGame
var _hud: PassengerHud


func before() -> void:
	PassengerTestWorld.tracker = self
	_world = MessTestKit.open_world()


func after() -> void:
	_world.free_all()
	_world = null
	PassengerTestWorld.tracker = null


func before_test() -> void:
	assert_bool(MessTestKit.clear(_world)).is_true()
	_save = auto_free(SaveGame.new())
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	_hud.save_game = _save
	add_child(_hud)


func after_test() -> void:
	_hud.free()


## Adds `n` fresh spills on separate cells; each costs MessSim.DIRT.
func _spills(n: int) -> void:
	for i in n:
		var id := _world.sim.messes.add(MessSim.Kind.SPILL, Vector2i(2 + i * 2, ROW_Y))
		assert_int(id).is_greater(0)


## Cleans messes until `dirt` is left (all fresh, one each).
func _leave_dirt(dirt: int) -> void:
	var ids := _world.sim.messes.mess_ids()
	for id in ids.slice(0, ids.size() - dirt):
		assert_bool(_world.sim.messes.clean(id)).is_true()
	assert_int(_world.sim.messes.total_dirt()).is_equal(dirt)


func test_the_hud_card_shows_and_clears_with_the_terminal() -> void:
	_spills(DirtyAlert.SHOW_AT)
	_hud.refresh()
	assert_bool(_hud.dirty_alert().is_shown()).is_true()
	_leave_dirt(0)
	_hud.refresh()
	assert_bool(_hud.dirty_alert().is_shown()).is_false()


func test_a_load_with_dirt_in_the_band_gives_the_same_card_whether_it_was_up_or_not() -> void:
	var band := DirtyAlert.SHOW_AT - 1
	# World before the load had the card up.
	_spills(DirtyAlert.SHOW_AT)
	_hud.refresh()
	assert_bool(_hud.dirty_alert().is_shown()).is_true()
	_leave_dirt(band)
	_hud.refresh()
	assert_bool(_hud.dirty_alert().is_shown()).is_true()
	_save.loaded.emit(true)
	_hud.refresh()
	var after_shown := _hud.dirty_alert().is_shown()
	# World before the load had the card down, same dirt after it.
	_leave_dirt(0)
	_hud.refresh()
	assert_bool(_hud.dirty_alert().is_shown()).is_false()
	_spills(band)
	_save.loaded.emit(true)
	_hud.refresh()
	assert_int(_world.sim.messes.total_dirt()).is_equal(band)
	assert_bool(_hud.dirty_alert().is_shown()).is_equal(after_shown)
	assert_bool(after_shown).is_false()


func test_a_load_does_not_hide_a_card_whose_dirt_is_at_the_show_threshold() -> void:
	_spills(DirtyAlert.SHOW_AT)
	_hud.refresh()
	_save.loaded.emit(true)
	assert_bool(_hud.dirty_alert().is_shown()).is_false()
	_hud.refresh()
	assert_bool(_hud.dirty_alert().is_shown()).is_true()


func test_a_refused_load_leaves_the_card_up() -> void:
	_spills(DirtyAlert.SHOW_AT)
	_hud.refresh()
	_save.loaded.emit(false)
	assert_bool(_hud.dirty_alert().is_shown()).is_true()


func test_replacing_the_hud_sim_starts_the_card_again() -> void:
	_spills(DirtyAlert.SHOW_AT)
	_hud.refresh()
	assert_bool(_hud.dirty_alert().is_shown()).is_true()
	var other := MessTestKit.open_world(3)
	_hud.sim = other.sim
	assert_bool(_hud.dirty_alert().is_shown()).is_false()
	assert_object(_hud.dirty_alert().sim).is_same(other.sim)
	_hud.sim = _world.sim
	other.free_all()
