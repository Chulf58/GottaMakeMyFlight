class_name TestDirtyAlert
extends GdUnitTestSuite
## The dirty-terminal alert (decision cleaner-staff-and-messes-visits-
## leave-messes-bins-fill-pooled-cleaners-nearest-mess, point 6): it shows when
## the summed mess dirt reaches DirtyAlert.SHOW_AT, stays while the dirt is
## above the hysteresis band's floor, clears itself below CLEAR_BELOW, and says
## hire a cleaner when none is hired, otherwise place bins or hire more. How
## its card is drawn (covered, width, the click) is TestAlertStack's.

## Cells across an open row, far enough apart that no two spills merge.
const ROW_Y := 8
const CLEANER := StaffMember.Role.CLEANER

## One world for the file; each case starts with no messes and no cleaners'
## effect on the card beyond what it hires itself.
var _world: PassengerTestWorld
var _card: DirtyAlert


func before() -> void:
	PassengerTestWorld.tracker = self
	_world = MessTestKit.open_world()


func after() -> void:
	_world.free_all()
	_world = null
	PassengerTestWorld.tracker = null


func before_test() -> void:
	assert_bool(MessTestKit.clear(_world)).is_true()
	_card = DirtyAlert.new()
	_card.sim = _world.sim


## Adds `n` fresh spills on separate cells from column `first`; each costs MessSim.DIRT.
func _spills(n: int, first := 0) -> void:
	for i in range(first, first + n):
		var id := _world.sim.messes.add(MessSim.Kind.SPILL, Vector2i(2 + i * 2, ROW_Y))
		assert_int(id).is_greater(0)


func test_total_dirt_sums_each_mess_at_its_age() -> void:
	var messes := _world.sim.messes
	assert_int(messes.total_dirt()).is_equal(0)
	_spills(3)
	assert_int(messes.total_dirt()).is_equal(3 * MessSim.DIRT)
	_world.run_to(_world.sim.tick + MessSim.RAMP_TICKS)
	assert_int(messes.total_dirt()).is_equal(3 * MessSim.AGED_DIRT)


func test_the_card_is_hidden_one_below_the_show_threshold_and_shows_at_it() -> void:
	_spills(DirtyAlert.SHOW_AT - 1)
	_card.refresh()
	assert_bool(_card.is_shown()).is_false()
	_spills(1, DirtyAlert.SHOW_AT - 1)
	_card.refresh()
	assert_int(_world.sim.messes.total_dirt()).is_greater_equal(DirtyAlert.SHOW_AT)
	assert_bool(_card.is_shown()).is_true()


func test_the_card_stays_through_the_hysteresis_band_and_clears_below_it() -> void:
	_card.refresh_with(DirtyAlert.SHOW_AT, 0)
	assert_bool(_card.is_shown()).is_true()
	# Every dirt level from one under SHOW_AT down to CLEAR_BELOW keeps it up.
	for dirt in range(DirtyAlert.SHOW_AT - 1, DirtyAlert.CLEAR_BELOW - 1, -1):
		_card.refresh_with(dirt, 0)
		assert_bool(_card.is_shown()).override_failure_message("dirt %d" % dirt).is_true()
	_card.refresh_with(DirtyAlert.CLEAR_BELOW - 1, 0)
	assert_bool(_card.is_shown()).is_false()


func test_a_cleared_card_does_not_come_back_inside_the_band() -> void:
	_card.refresh_with(DirtyAlert.SHOW_AT, 0)
	_card.refresh_with(0, 0)
	assert_bool(_card.is_shown()).is_false()
	for dirt in range(DirtyAlert.CLEAR_BELOW, DirtyAlert.SHOW_AT):
		_card.refresh_with(dirt, 0)
		assert_bool(_card.is_shown()).override_failure_message("dirt %d" % dirt).is_false()
	_card.refresh_with(DirtyAlert.SHOW_AT, 0)
	assert_bool(_card.is_shown()).is_true()


func test_the_card_clears_itself_when_the_messes_are_cleaned() -> void:
	_spills(DirtyAlert.SHOW_AT)
	_card.refresh()
	assert_bool(_card.is_shown()).is_true()
	for id in _world.sim.messes.mess_ids():
		assert_bool(_world.sim.messes.clean(id)).is_true()
	_card.refresh()
	assert_bool(_card.is_shown()).is_false()


func test_the_text_says_hire_a_cleaner_when_none_is_hired() -> void:
	_spills(DirtyAlert.SHOW_AT)
	_card.refresh()
	assert_int(_world.sim.staff.count(CLEANER)).is_equal(0)
	assert_str(_card.card_text()).is_equal(DirtyAlert.HIRE_TEXT)
	assert_str(DirtyAlert.HIRE_TEXT).contains("Hire a cleaner")


func test_the_text_says_bins_or_more_cleaners_once_one_is_hired() -> void:
	_spills(DirtyAlert.SHOW_AT)
	var id := _world.sim.staff.hire(CLEANER)
	assert_int(id).is_greater(0)
	_card.refresh()
	assert_str(_card.card_text()).is_equal(DirtyAlert.BINS_TEXT)
	assert_str(DirtyAlert.BINS_TEXT).contains("bins")
	assert_str(DirtyAlert.BINS_TEXT).contains("more cleaners")


func test_the_text_follows_the_hired_count_while_the_card_stays_up() -> void:
	_card.refresh_with(DirtyAlert.SHOW_AT, 0)
	assert_str(_card.card_text()).is_equal(DirtyAlert.HIRE_TEXT)
	_card.refresh_with(DirtyAlert.SHOW_AT, 1)
	assert_str(_card.card_text()).is_equal(DirtyAlert.BINS_TEXT)


func test_a_different_sim_starts_the_card_again() -> void:
	_spills(DirtyAlert.SHOW_AT)
	_card.refresh()
	assert_bool(_card.is_shown()).is_true()
	var other := MessTestKit.open_world(2)
	_card.sim = other.sim
	assert_bool(_card.is_shown()).is_false()
	_card.refresh()
	assert_bool(_card.is_shown()).is_false()
	assert_int(other.sim.messes.total_dirt()).is_equal(0)
	other.free_all()


func test_reset_starts_hidden_and_the_band_applies_afresh() -> void:
	# 5 is inside the band: up before a reset, and not shown again by it.
	_card.refresh_with(DirtyAlert.SHOW_AT, 0)
	_card.refresh_with(5, 0)
	assert_bool(_card.is_shown()).is_true()
	_card.reset()
	assert_bool(_card.is_shown()).is_false()
	assert_str(_card.card_text()).is_equal("")
	_card.refresh_with(5, 0)
	assert_bool(_card.is_shown()).is_false()
	_card.refresh_with(DirtyAlert.SHOW_AT, 0)
	assert_bool(_card.is_shown()).is_true()
