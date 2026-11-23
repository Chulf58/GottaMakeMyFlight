class_name TestLandsidePopsAndBadge
extends GdUnitTestSuite
## Floating '+$' popups (LandsidePops) and car park occupancy badges
## (LandsidePlaces, decision parking-and-landside-gameplay-popups-2-berth-
## curb-shortest-walk-routing).

const STARTER := preload("res://landside/starter_landside.tres")
const SURFACE := 0
const MULTI_STOREY := 1

var _sim: LandsideSim
var _views: LandsideViews
var _rng := RandomNumberGenerator.new()


func before_test() -> void:
	_rng.seed = 19
	_sim = auto_free(LandsideSim.new())
	assert_bool(_sim.use_definition(STARTER)).is_true()
	_sim.wallet = Wallet.new()
	_views = auto_free(LandsideViews.new())
	_views.landside = _sim
	add_child(_views)


func _park_cars(count: int) -> void:
	for i in count:
		var bookings: Array[int] = [i + 1]
		_sim.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, bookings)
	for t in range(1, 2000):
		_sim.step(t, true, _rng)


func test_floating_popup_spawns_rises_fades_and_frees_cleanly_for_both_lots() -> void:
	assert_bool(_sim.build_lot(SURFACE)).is_true()
	var pops := _views.pops()
	assert_int(pops.live_count()).is_equal(0)
	_sim.parked.emit(101, SURFACE)
	assert_int(pops.live_count()).is_equal(1)
	var label := pops.live_labels()[0]
	assert_str(label.text).is_equal("+$20")
	assert_object(label.font).is_same(CaptionFont.font())
	assert_bool(label.shaded).is_false()
	assert_int(label.billboard).is_equal(BaseMaterial3D.BILLBOARD_ENABLED)
	var start_y := label.position.y
	pops.advance(LandsidePops.POP_SECONDS * 0.5)
	assert_float(label.position.y).is_greater(start_y + LandsidePops.RISE_M * 0.4)
	assert_float(label.modulate.a).is_equal_approx(0.5, 0.05)
	pops.advance(LandsidePops.POP_SECONDS * 0.6)
	assert_int(pops.live_count()).is_equal(0)
	await get_tree().process_frame
	assert_bool(is_instance_valid(label)).is_false()

	assert_bool(_sim.build_lot(MULTI_STOREY)).is_true()
	_sim.parked.emit(102, MULTI_STOREY)
	assert_int(pops.live_count()).is_equal(1)
	var multi_label := pops.live_labels()[0]
	assert_str(multi_label.text).is_equal("+$35")
	assert_float(multi_label.position.y).is_greater(28.0)
	_views.snap()
	assert_int(pops.live_count()).is_equal(0)
	await get_tree().process_frame
	assert_bool(is_instance_valid(multi_label)).is_false()


func test_occupancy_badge_shows_above_roofed_multi_storey_and_updates_as_cars_park() -> void:
	assert_bool(_sim.build_lot(MULTI_STOREY)).is_true()
	_views.places().refresh()
	var badge := _views.places().occupancy_badge(MULTI_STOREY)
	assert_object(badge).is_not_null()
	assert_object(badge.font).is_same(CaptionFont.font())
	assert_bool(badge.shaded).is_false()
	assert_int(badge.billboard).is_equal(BaseMaterial3D.BILLBOARD_ENABLED)
	assert_str(badge.text).is_equal("0/31")
	assert_float(badge.position.y).is_greater(28.3)

	_park_cars(2)
	_views.places().refresh()
	assert_str(badge.text).is_equal("2/31")

	assert_bool(_sim.build_lot(SURFACE)).is_true()
	_views.places().refresh()
	var surface_badge := _views.places().occupancy_badge(SURFACE)
	assert_object(surface_badge).is_not_null()
	assert_str(surface_badge.text).is_equal("0/12")
