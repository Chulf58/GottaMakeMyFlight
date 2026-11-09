extends GdUnitTestSuite
## A lane passenger's bags come out of the tray (TRAY to HAND,
## SecurityLooks.bag_homes()) only once its body has cleared the lane's arch
## (user ruling "Pick up after the arch", board 0dd2c787 item b). A returner's
## second pass reached for its bags from inside the arch: the arch phase's last
## step onto the pickup cell starts a new path, and SecurityLooks._on_passage()
## read its first cell as the return route's end, so the bags went to the hand
## while the body stood between the posts and the arm reached 0.79-0.89 m
## across the 0.38 m half opening (seed 1106001 --lane, passenger 6).

## How far (m, along the lane) from the arch cell's centre the body must be
## when a bag leaves the tray: the posts reach 0.30 m either side, and a body
## stands about 0.2 m deep about its centre.
const CLEAR_M := 0.5

var _worlds: Array[SecurityTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for w in _worlds:
		w.world.free_all()
	_worlds.clear()


## An alarm passenger with two bags through the lane, its second pass
## included: every bag leaves the tray with the body CLEAR_M or more from the
## arch, outside its passage; at least the first pass's and the second pass's
## pick-ups are seen (the control that the moves were engaged).
func test_bags_leave_the_tray_only_past_the_arch() -> void:
	var w := SecurityTestWorld.make(true)
	_worlds.append(w)
	var ids := w.send_all([[2, false, true]])
	var p := w.world.passenger(ids[0])
	var arch := w.world.grid.cell_to_world(SecurityTestWorld.ARCH_AT)
	var was: Array = SecurityLooks.bag_homes(w.world.sim, p)
	var seen := 0
	var inside := 0
	var least := INF
	var lines: Array[String] = []
	for n in 3000:
		w.world.step()
		if w.cleared.has(p.id):
			break
		var now: Array = SecurityLooks.bag_homes(w.world.sim, p)
		for i in mini(now.size(), was.size()):
			if was[i] != SecurityLooks.Home.TRAY or now[i] != SecurityLooks.Home.HAND:
				continue
			var off := absf(w.world.sim.world_position(p).z - arch.z)
			var passage := SecurityLooks.in_arch_passage(w.world.sim, p)
			seen += 1
			least = minf(least, off)
			inside += int(off < CLEAR_M or passage)
			var line := (
				(
					"bag %d out of the tray at tick %d: phase %s, resolved %s,"
					+ " %.3f m from the arch, in passage %s"
				)
				% [
					i,
					w.world.clock.tick,
					SecurityRuntime.Phase.keys()[p.security_phase],
					p.incident_resolved,
					off,
					passage
				]
			)
			lines.append(line)
		was = now
	print("\n".join(lines))
	print(
		(
			"tray to hand %d, inside the arch %d (0), least distance %.3f m (>= %.2f), cleared %s"
			% [seen, inside, least, CLEAR_M, w.cleared.has(p.id)]
		)
	)
	assert_bool(w.cleared.has(p.id)).is_true()
	assert_int(seen).is_greater_equal(4)
	assert_int(inside).is_equal(0)
