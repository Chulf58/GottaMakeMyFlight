extends GdUnitTestSuite
## A lane returner's bags go into the tray on the walk up to the unpack cell,
## so the hand is back from the tray before the body reaches the arch's entry
## (board 40d26b16). A returner (second pass, after a repack) does not stop at
## the unpack cell: it walks from the return route's end across the unpack
## cell into the arch. Its bags went in the tray (HAND to TRAY,
## SecurityLooks.bag_homes()) only once it stood on the unpack cell, and the
## hand-led move to the tray beside it (CarryOnProps.TRANSFER_TICKS) ran on
## while the body walked into the arch: runner p15 on seed 1106001 --lane
## reached 0.673 m across the 0.38 m half opening at z +0.555.

## How far (m, along the lane) from the arch cell's centre the body must still
## be when a move into the tray ends: the probe's arch entry window ends 0.60 m
## out (basic_scanner_crossing_probe ENTRY_Z), and 0.05 m more is the margin.
const ENTRY_CLEAR_M := 0.65

var _worlds: Array[SecurityTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for w in _worlds:
		w.world.free_all()
	_worlds.clear()


## A walking alarm passenger with two bags: on its second pass every bag's
## move into the tray ends with the body ENTRY_CLEAR_M or more from the arch's
## centre; both bags are seen going in (the control that the pass ran).
func test_walker_puts_its_bags_in_the_tray_before_the_arch() -> void:
	var ends := _second_pass_put_ins(2, false)
	assert_int(ends.size()).is_equal(2)
	for end: float in ends:
		assert_float(end).is_greater_equal(ENTRY_CLEAR_M)


## The same for a running alarm passenger with one bag (kept late every tick,
## as the lane probe keeps its runners): it covers a move's six ticks in about
## a metre, so a move started on the unpack cell ended mid-arch.
func test_runner_puts_its_bag_in_the_tray_before_the_arch() -> void:
	var ends := _second_pass_put_ins(1, true)
	assert_int(ends.size()).is_equal(1)
	for end: float in ends:
		assert_float(end).is_greater_equal(ENTRY_CLEAR_M)


## A running returner turns from across the lane to the arch's axis around
## the unpack cell's corner (SecurityLooks.setoff_yaw()), so on every tick of
## its arch walk within ENTRY_CLEAR_M of the arch's centre it faces the axis.
## Turned only once past the corner, runner p15 was 46 degrees off the axis at
## z +0.415 and its free arm reached 0.66 m. Controls: the turn was seen part
## way (a share between 0 and 1) and ticks near the arch were sampled.
func test_runner_faces_the_arch_before_its_entry() -> void:
	var w := SecurityTestWorld.make(true)
	_worlds.append(w)
	var ids := w.send_all([[1, false, true]])
	var p := w.world.passenger(ids[0])
	var arch := w.world.grid.cell_to_world(SecurityTestWorld.ARCH_AT)
	var axis := atan2(0.0, -1.0)
	var turning := 0
	var near := 0
	var worst := 0.0
	for n in 3000:
		p.late = true
		w.world.step()
		if w.cleared.has(p.id):
			break
		if not p.incident_resolved or p.security_phase != SecurityRuntime.Phase.ARCH:
			continue
		var yaw := SecurityLooks.setoff_yaw(w.world.sim, p)
		if is_nan(yaw) or p.path_index > 1:
			continue
		var off := absf(rad_to_deg(angle_difference(yaw, axis)))
		turning += int(off > 1.0 and off < 89.0)
		var z := absf(w.world.sim.world_position(p).z - arch.z)
		if z <= ENTRY_CLEAR_M:
			near += 1
			worst = maxf(worst, off)
		print("tick %d z %.3f yaw off the axis %.1f deg" % [w.world.clock.tick, z, off])
	print("turning ticks %d, ticks near the arch %d, worst %.2f deg" % [turning, near, worst])
	assert_int(turning).is_greater(0)
	assert_int(near).is_greater(0)
	assert_float(worst).is_less(1.0)


## Sends one alarm passenger with `bags` bags through the lane (kept late when
## `late`) and returns, for each bag that goes from the hand into the tray on
## its second pass, how far from the arch's centre along the lane the body is
## on the tick that move ends (TRANSFER_TICKS after it starts). Prints each.
func _second_pass_put_ins(bags: int, late: bool) -> Array[float]:
	var w := SecurityTestWorld.make(true)
	_worlds.append(w)
	var ids := w.send_all([[bags, false, true]])
	var p := w.world.passenger(ids[0])
	var arch := w.world.grid.cell_to_world(SecurityTestWorld.ARCH_AT)
	var was: Array = SecurityLooks.bag_homes(w.world.sim, p)
	var ending := {}
	var ends: Array[float] = []
	var lines: Array[String] = []
	for n in 3000:
		if late:
			p.late = true
		w.world.step()
		if w.cleared.has(p.id):
			break
		var tick := w.world.clock.tick
		var off := absf(w.world.sim.world_position(p).z - arch.z)
		for i: int in ending.keys():
			if tick >= ending[i]:
				ends.append(off)
				ending.erase(i)
				lines.append("bag %d move ends at tick %d, %.3f m from the arch" % [i, tick, off])
		var now: Array = SecurityLooks.bag_homes(w.world.sim, p)
		var second := p.incident_resolved and p.security_phase == SecurityRuntime.Phase.ARCH
		for i in mini(now.size(), was.size()):
			if second and was[i] == SecurityLooks.Home.HAND and now[i] == SecurityLooks.Home.TRAY:
				ending[i] = tick + roundi(CarryOnProps.TRANSFER_TICKS)
				lines.append(
					"bag %d into the tray at tick %d, %.3f m from the arch" % [i, tick, off]
				)
		was = now
	print("\n".join(lines))
	print(
		(
			"late %s: %d moves into the tray ended, at %s m from the arch (>= %.2f), cleared %s"
			% [late, ends.size(), ends, ENTRY_CLEAR_M, w.cleared.has(p.id)]
		)
	)
	assert_bool(w.cleared.has(p.id)).is_true()
	return ends
