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


## Walking and running two-bag passengers: on pass 1 UNPACK -> ARCH, both bags
## settle into the tray without reverting to hand, and under S1 no passenger
## ever returns through ARCH a second time.
func test_two_bags_go_in_one_after_the_other() -> void:
	for late in [false, true]:
		var seen := _watch(late)
		assert_int(seen["second_pass"]).is_equal(0)
		assert_int(seen["both_moved"]).is_equal(SENT)
		assert_int(seen["overlap"]).is_equal(0)


func test_a_settled_bag_stays_settled_past_the_walk() -> void:
	var seen := _watch(true)
	assert_int(seen["after_walk"]).is_greater(0)
	assert_int(seen["unsettled"]).is_equal(0)


## Sends SENT two-bag alarm passengers through the lane (kept late when
## `late`), drawn every tick, and verifies sequential pass-1 tray settlement
## (`0 < transfer_progress < 1` and zero hand-carry overlap) + zero second pass.
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
	var carried_to := 1.0 - CarryLead.REACH_SHARE
	var passed_arch := {}
	var second_pass := {}
	var moved := {}
	var overlap := 0
	var settled := {}
	var after_walk := 0
	var unsettled := 0
	for n in 8000:
		if late:
			for id in ids:
				w.world.passenger(id).late = true
		w.world.step()
		views.draw()
		for id in ids:
			var p := w.world.passenger(id)
			if p.stage != Passenger.Stage.SECURITY:
				continue
			if (
				p.security_phase
				in [
					SecurityRuntime.Phase.BODY_CHECK,
					SecurityRuntime.Phase.PICKUP,
				]
			):
				passed_arch[id] = true
			elif (
				passed_arch.has(id)
				and (
					p.security_phase
					in [
						SecurityRuntime.Phase.UNPACK,
						SecurityRuntime.Phase.ARCH,
					]
				)
			):
				second_pass[id] = true
			if p.security_phase in [SecurityRuntime.Phase.UNPACK, SecurityRuntime.Phase.ARCH]:
				var homes := SecurityLooks.bag_homes(w.world.sim, p)
				for i in 2:
					var k := props.transfer_progress(id, i)
					if homes[i] == SecurityLooks.Home.TRAY and k > 0.0 and k < 1.0:
						moved.get_or_add(id, {})[i] = true
				var first := SecurityLooks.put_in_first(w.world.sim, p)
				var near := props.transfer_progress(id, first)
				var far := props.transfer_progress(id, 1 - first)
				if (
					homes[0] == SecurityLooks.Home.TRAY
					and homes[1] == SecurityLooks.Home.TRAY
					and far > 0.0
					and near < carried_to
				):
					overlap += 1
			if p.security_phase in [SecurityRuntime.Phase.ARCH, SecurityRuntime.Phase.BODY_CHECK]:
				var homes := SecurityLooks.bag_homes(w.world.sim, p)
				for i in 2:
					if (
						homes[i] == SecurityLooks.Home.TRAY
						and props.transfer_progress(id, i) >= 1.0
					):
						settled.get_or_add(id, {})[i] = true
						after_walk += 1
					elif (settled.get(id, {}) as Dictionary).has(i):
						unsettled += 1
		if ids.all(func(id: int) -> bool: return w.cleared.has(id)):
			break
	assert_bool(ids.all(func(id: int) -> bool: return w.cleared.has(id))).is_true()
	var both := moved.values().filter(func(m: Dictionary) -> bool: return m.size() == 2)
	return {
		"second_pass": second_pass.size(),
		"both_moved": both.size(),
		"overlap": overlap,
		"after_walk": after_walk,
		"unsettled": unsettled,
	}
