extends GdUnitTestSuite
## A lane returner with two bags puts them into the tray one after the other,
## the bag on the tray's side first (board 521e46a5). Both bags went in on one
## schedule (SecurityLooks.put_in_share(), by the distance walked), so the bag
## from the far hand crossed in front of the body through the near one: on seed
## 1106001 --lane the case and the shoulder bag met over the tray. These tests
## check the schedule from stamped state alone; whether the drawn bags touch is
## the windowed lane probe's BAG_IN_BAG check (a headless draw has no posed
## skeleton: its hands, and so its carried bags, are not where a window draws
## them, anti_pattern 6d691dee).

## Two-bag alarm passengers sent one after another (each repacks and returns).
const SENT := 3

var _worlds: Array[SecurityTestWorld] = []
var _views: Array[PassengerViews] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for v in _views:
		v.free()
	_views.clear()
	for w in _worlds:
		w.world.free_all()
	_worlds.clear()


## The bag that goes first is the one on the tray table's side of a body
## facing the arch, on both mirrors of the lane: the tray's centre (the riding
## tray at the unpack cell, CarryTray) lies on that bag's side. Control: the
## two mirrors pick different bags.
func test_the_bag_on_the_tray_side_goes_in_first() -> void:
	var firsts := []
	for mirror in [SecurityLanes.RIGHT, SecurityLanes.LEFT]:
		var w := SecurityTestWorld.make(true, 7, mirror)
		_worlds.append(w)
		var p := w.world.passenger(w.send(2, false, true))
		# Admitted to the lane (lane_of() reads its station).
		for n in 3000:
			if p.stage == Passenger.Stage.SECURITY:
				break
			w.world.step()
		var lane := SecurityLooks.lane_of(w.world.sim, p)
		assert_bool(lane.is_empty()).is_false()
		var grid := w.world.grid
		var unpack := grid.cell_to_world(lane["unpack"])
		var tray := CarryTray.ride(grid, lane, unpack).origin - unpack
		var facing := grid.cell_to_world(lane["arch"]) - unpack
		# Bag 0 is in the right hand (-x of a body facing +z).
		var right := facing.cross(Vector3.UP).normalized()
		var first := SecurityLooks.put_in_first(w.world.sim, p)
		var side := tray.dot(right)
		print("mirror %d: tray %.3f m to the right, first bag %d" % [mirror, side, first])
		assert_float(absf(side)).is_greater(0.1)
		assert_int(first).is_equal(0 if side > 0.0 else 1)
		firsts.append(first)
	assert_int(firsts[0]).is_not_equal(firsts[1])


## Walking and running two-bag returners: on every tick of the arch walk the
## second bag stays in the hand until the first is down in the tray (its share
## past 1 - CarryLead.REACH_SHARE, where its carry ends), and the second's
## window ends where the one-bag put-in does (PUT_IN_PAST_MM), short of the
## arch's entry. Controls: both bags were seen moving and each reached 1.
func test_two_bags_go_in_one_after_the_other() -> void:
	for late in [false, true]:
		var seen := _watch(late)
		assert_int(seen["returners"]).is_equal(SENT)
		assert_int(seen["both_moved"]).is_equal(SENT)
		assert_int(seen["overlap"]).is_equal(0)


## A runner's second bag of two, its move clocked from the start of its window,
## does not come back out of the tray when the walk ends at the arch cell: once
## drawn settled in the tray its progress stays 1 to the end of ARCH. Control:
## draws past the walk's end were checked.
func test_a_settled_bag_stays_settled_past_the_walk() -> void:
	var seen := _watch(true)
	assert_int(seen["after_walk"]).is_greater(0)
	assert_int(seen["unsettled"]).is_equal(0)


## Sends SENT two-bag alarm passengers through the lane (kept late when
## `late`), drawn every tick, and watches each returner's second pass in ARCH:
## "returners" seen on the arch walk; "both_moved" with each bag's share seen
## between 0 and 1; "overlap" ticks on which the second bag had left the hand
## (share above 0) while the first was still carried (share below 1 -
## REACH_SHARE); "after_walk" draws in ARCH past the walk, and "unsettled" those
## with a bag in the tray drawn short of the end of its move.
func _watch(late: bool) -> Dictionary:
	var w := SecurityTestWorld.make(true)
	_worlds.append(w)
	var traits := []
	for n in SENT:
		traits.append([2, false, true])
	var ids := w.send_all(traits)
	var views := PassengerTestWorld.views()
	views.clock = w.world.clock
	views.sim = w.world.sim
	add_child(views)
	_views.append(views)
	var props := views.carry_on_props()
	var walked := {}
	var moved := {}
	var overlap := 0
	var after_walk := 0
	var unsettled := 0
	var carried_to := 1.0 - CarryLead.REACH_SHARE
	for n in 8000:
		if late:
			for id in ids:
				w.world.passenger(id).late = true
		w.world.step()
		views.draw()
		for id in ids:
			var p := w.world.passenger(id)
			if not p.incident_resolved or p.security_phase != SecurityRuntime.Phase.ARCH:
				continue
			var past := SecurityLooks.return_walk_mm(w.world.sim, p)
			if is_nan(past):
				if walked.has(id):
					after_walk += 1
					for i in 2:
						unsettled += int(props.transfer_progress(id, i) < 1.0)
				continue
			walked[id] = true
			var first := SecurityLooks.put_in_first(w.world.sim, p)
			var homes := SecurityLooks.bag_homes(w.world.sim, p)
			# Each bag's progress as drawn (CarryPlace.progress_of(), from the
			# stamped put-in), 0 while it is still in the hand.
			var shares := []
			for i in 2:
				var window := SecurityLooks.put_in_window(w.world.sim, p, i)
				assert_float(window.y).is_less_equal(SecurityLooks.PUT_IN_PAST_MM)
				var tray := homes[i] == SecurityLooks.Home.TRAY
				shares.append(props.transfer_progress(id, i) if tray else 0.0)
				if shares[i] > 0.0 and shares[i] < 1.0:
					moved.get_or_add(id, {})[i] = true
			var near: float = shares[first]
			var far: float = shares[1 - first]
			if far > 0.0 and near < carried_to:
				overlap += 1
				print(
					"late %s p%d at %.0f mm: first %.2f, second %.2f" % [late, id, past, near, far]
				)
		if ids.all(func(id: int) -> bool: return w.cleared.has(id)):
			break
	assert_bool(ids.all(func(id: int) -> bool: return w.cleared.has(id))).is_true()
	var both := moved.values().filter(func(m: Dictionary) -> bool: return m.size() == 2)
	print(
		(
			"late %s: returners %d, both bags moved %d, overlap ticks %d, after the walk %d (%d unsettled)"
			% [late, walked.size(), both.size(), overlap, after_walk, unsettled]
		)
	)
	return {
		"returners": walked.size(),
		"both_moved": both.size(),
		"overlap": overlap,
		"after_walk": after_walk,
		"unsettled": unsettled,
	}
