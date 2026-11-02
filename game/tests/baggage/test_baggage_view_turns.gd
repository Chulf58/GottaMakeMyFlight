class_name TestBaggageViewTurns
extends GdUnitTestSuite
## How BaggageViews turns a drawn bag (headless, transforms only; how it looks
## is the windowed plate game/spike/baggage_turns_probe.gd): turn_toward turns
## by at most its limit, a corner turns under TURN_PER_TICK so its drawn
## heading is the path's, a bag that turns on a cell centre (the side desk's
## bag turning onto the line at its feed, (6, 7)) turns over the next half
## cell and is drawn slerped between ticks, and after a load (a tick later, none
## later while paused, or to the tick already showing) every bag starts over at
## its sim place.

const EPS := 0.0001

var _world: BagTestWorld
var _views: BaggageViews
var _side := 0
var _save: SaveGame


func before_test() -> void:
	_world = BagTestWorld.make(self, 600)
	_world.line()
	_side = _world.side_desk()
	_views = auto_free(BaggageViews.new())
	_views.clock = _world.clock
	_views.sim = _world.sim
	_save = auto_free(SaveGame.new())
	_views.save_game = _save
	add_child(_views)


## The heading of `basis` about the vertical, as BaggageViews builds it.
static func _yaw(basis: Basis) -> float:
	return atan2(basis.z.x, basis.z.z)


static func _angle(a: Basis, b: Basis) -> float:
	return a.get_rotation_quaternion().angle_to(b.get_rotation_quaternion())


func _drawn(id: int) -> Basis:
	_views.draw()
	return _views.node_for(id).transform.basis


func test_turn_toward_reaches_a_target_within_the_limit() -> void:
	var to := Basis(Vector3.UP, 0.1)
	var out := BaggageViews.turn_toward(Basis.IDENTITY, to, 0.2)
	assert_bool(out.is_equal_approx(to)).is_true()
	# A scaled target comes back as a pure rotation.
	var scaled := BaggageViews.turn_toward(Basis.IDENTITY, Basis.from_scale(Vector3.ONE * 2.0), 0.2)
	assert_bool(scaled.is_equal_approx(Basis.IDENTITY)).is_true()


func test_turn_toward_turns_by_the_limit_toward_a_far_target() -> void:
	var from := Basis(Vector3.UP, 0.3)
	var to := Basis(Vector3.UP, 0.3 + PI / 2.0)
	assert_float(_yaw(BaggageViews.turn_toward(from, to, 0.2))).is_equal_approx(0.5, EPS)
	assert_float(_yaw(BaggageViews.turn_toward(to, from, 0.2))).is_equal_approx(
		0.3 + PI / 2.0 - 0.2, EPS
	)
	assert_bool(BaggageViews.turn_toward(from, to, 0.0).is_equal_approx(from)).is_true()
	# Across the +-PI wrap it turns the short way: 170 to -170 degrees is 20.
	var a := Basis(Vector3.UP, deg_to_rad(170.0))
	var b := Basis(Vector3.UP, deg_to_rad(-170.0))
	var out := BaggageViews.turn_toward(a, b, deg_to_rad(5.0))
	assert_float(rad_to_deg(_angle(a, out))).is_equal_approx(5.0, 0.001)
	assert_float(rad_to_deg(_angle(out, b))).is_equal_approx(15.0, 0.001)


func test_a_corner_turns_under_the_limit_so_the_drawn_heading_is_the_paths() -> void:
	var step := float(BaggageSim.BELT_MM) / Bag.CELL_MM
	var most := 0.0
	for i in roundi(1.0 / step):
		var a := BaggageViews.turn_transform(Vector3.ZERO, Vector2i(0, 1), Vector2i(1, 0), i * step)
		var b := BaggageViews.turn_transform(
			Vector3.ZERO, Vector2i(0, 1), Vector2i(1, 0), (i + 1) * step
		)
		most = maxf(most, _angle(a.basis, b.basis))
	print(
		(
			"corner most_per_tick_deg=%.3f limit_deg=%.3f"
			% [rad_to_deg(most), rad_to_deg(BaggageViews.TURN_PER_TICK)]
		)
	)
	assert_float(rad_to_deg(most)).is_equal_approx(5.0, 0.001)
	assert_float(most).is_less(BaggageViews.TURN_PER_TICK)
	assert_float(rad_to_deg(BaggageViews.TURN_PER_TICK)).is_equal_approx(9.0, 0.0001)


func test_a_bag_turning_on_a_cell_centre_turns_over_the_next_half_cell() -> void:
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _side)
	_world.step()
	# alpha is 0 after whole steps, so draw() shows the tick before: compare
	# each drawn heading with the sim heading recorded a tick earlier.
	var raw_before := BaggageViews.belt_transform(_world.grid, bag).basis
	var drawn_before := _drawn(bag.id)
	var raw_most := 0.0
	var drawn_most := 0.0
	var off_ticks := 0
	# Up (0, -1) through (6, 8) to the feed's centre on tick 30, then east.
	for i in 60:
		_world.step()
		var drawn := _drawn(bag.id)
		var raw := BaggageViews.belt_transform(_world.grid, bag).basis
		raw_most = maxf(raw_most, _angle(raw_before, raw))
		drawn_most = maxf(drawn_most, _angle(drawn_before, drawn))
		if _angle(drawn, raw_before) > 0.001:
			off_ticks += 1
		raw_before = raw
		drawn_before = drawn
	# It went on east past the feed.
	assert_int(bag.cell.x).is_greater(BagTestWorld.SIDE_ENTRY.x + 1)
	print(
		(
			"feed raw_most_deg=%.2f drawn_most_deg=%.2f off_ticks=%d"
			% [rad_to_deg(raw_most), rad_to_deg(drawn_most), off_ticks]
		)
	)
	# Control: the sim's heading turned a quarter in one tick.
	assert_float(rad_to_deg(raw_most)).is_equal_approx(90.0, 0.01)
	assert_float(drawn_most).is_less_equal(BaggageViews.TURN_PER_TICK + EPS)
	assert_float(drawn_most).is_greater(BaggageViews.TURN_PER_TICK - EPS)
	# A quarter at 9 degrees a tick: 9 drawn ticks short of the sim's heading.
	assert_int(off_ticks).is_equal(9)
	assert_vector(_drawn(bag.id).z).is_equal_approx(Vector3(1.0, 0.0, 0.0), Vector3.ONE * EPS)


func test_a_turning_bag_is_drawn_slerped_between_its_ticks() -> void:
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _side)
	while bag.from_step != Vector2i(1, 0):
		_world.step()
	_world.run_to(_world.clock.tick + 3)
	var before := _yaw(_drawn(bag.id))
	_world.clock.advance(SimClock.STEP * 0.5)
	var mid := _yaw(_drawn(bag.id))
	_world.clock.advance(SimClock.STEP * 0.5)
	var after := _yaw(_drawn(bag.id))
	assert_float(absf(after - before)).is_greater(BaggageViews.TURN_PER_TICK * 0.5)
	assert_float(mid).is_equal_approx((before + after) / 2.0, 0.001)


func test_after_a_load_back_every_bag_starts_over_at_its_sim_place() -> void:
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _side)
	_world.run_to(5)
	var sim_save := _world.sim.to_snapshot()
	var clock_save := _world.clock.to_snapshot()
	_world.run_to(60)
	assert_vector(_drawn(bag.id).z).is_equal_approx(Vector3(1.0, 0.0, 0.0), Vector3.ONE * EPS)
	assert_bool(_world.clock.from_snapshot(clock_save)).is_true()
	assert_bool(_world.sim.from_snapshot(sim_save)).is_true()
	_world.step()
	var loaded := _world.sim.get_bag(bag.id)
	var place := BaggageViews.belt_transform(_world.grid, loaded)
	# Both recorded ticks are the loaded place: drawn there, heading north.
	_views.draw()
	var node := _views.node_for(bag.id)
	assert_vector(node.transform.origin).is_equal_approx(place.origin, Vector3.ONE * EPS)
	assert_vector(node.transform.basis.z).is_equal_approx(
		Vector3(0.0, 0.0, -1.0), Vector3.ONE * EPS
	)
	assert_int(_views.active_count()).is_equal(1)


func test_a_load_while_paused_snaps_every_bag_at_once() -> void:
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _side)
	_world.run_to(5)
	var sim_save := _world.sim.to_snapshot()
	var clock_save := _world.clock.to_snapshot()
	_world.run_to(60)
	assert_vector(_drawn(bag.id).z).is_equal_approx(Vector3(1.0, 0.0, 0.0), Vector3.ONE * EPS)
	assert_bool(_world.clock.from_snapshot(clock_save)).is_true()
	assert_bool(_world.sim.from_snapshot(sim_save)).is_true()
	# Paused: no tick follows the load, only SaveGame.loaded.
	_save.loaded.emit(true)
	var place := BaggageViews.belt_transform(_world.grid, _world.sim.get_bag(bag.id))
	_views.draw()
	var node := _views.node_for(bag.id)
	assert_vector(node.transform.origin).is_equal_approx(place.origin, Vector3.ONE * EPS)
	assert_vector(node.transform.basis.z).is_equal_approx(
		Vector3(0.0, 0.0, -1.0), Vector3.ONE * EPS
	)
	assert_int(_views.active_count()).is_equal(1)
	# The next tick follows the loaded clock, so it is a plain tick and not a gap.
	_world.step()
	assert_int(_views.active_count()).is_equal(1)


func test_a_load_to_the_tick_already_showing_snaps_to_the_loaded_bag() -> void:
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _side)
	_world.run_to(60)
	# A second world on the same tick with its bag checked in later, so its bag
	# lies somewhere else on the line.
	var other := BagTestWorld.make(self, 600)
	other.line()
	var other_side := other.side_desk()
	other.run_to(10)
	other.sim.check_in(1, BagTestWorld.FLIGHT, other_side)
	other.run_to(60)
	_drawn(bag.id)
	var shown_origin := _views.node_for(bag.id).transform.origin
	assert_int(other.clock.tick).is_equal(_world.clock.tick)
	assert_bool(_world.clock.from_snapshot(other.clock.to_snapshot())).is_true()
	assert_bool(_world.sim.from_snapshot(other.sim.to_snapshot())).is_true()
	_save.loaded.emit(true)
	var loaded := _world.sim.get_bag(bag.id)
	var place := BaggageViews.belt_transform(_world.grid, loaded)
	_views.draw()
	var node := _views.node_for(bag.id)
	# Control: the loaded bag is not where the view drew the old one.
	assert_float(place.origin.distance_to(shown_origin)).is_greater(0.3)
	assert_vector(node.transform.origin).is_equal_approx(place.origin, Vector3.ONE * EPS)
	assert_vector(node.transform.basis.z).is_equal_approx(place.basis.z, Vector3.ONE * EPS)
	assert_int(_views.active_count()).is_equal(1)


func test_a_failed_load_leaves_the_bags_as_they_were() -> void:
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _side)
	_world.run_to(60)
	var before := _drawn(bag.id)
	var origin := _views.node_for(bag.id).transform.origin
	_save.loaded.emit(false)
	assert_vector(_views.node_for(bag.id).transform.origin).is_equal_approx(
		origin, Vector3.ONE * EPS
	)
	assert_bool(_drawn(bag.id).is_equal_approx(before)).is_true()
