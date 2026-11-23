extends GdUnitTestSuite
## A late passenger at a security lane is drawn walking while it puts its
## bags into the tray in Phase.UNPACK, and running before and after (board
## b1754061, user-ruled 2026-11-17 "Slow to a walk"; updated for S1 where
## Phase.RETURN was removed and pass-1 UNPACK -> ARCH is the sole put-in). A
## drawing change only: the sim walks the same cells at the same pace either way.

## The walk clip's speed may differ from the speed walked by at most this.
const SPEED_EPS := 0.001

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


## A runner with one bag: the walk clip on every moving tick during UNPACK
## put-in, at the speed it is drawn moving; the run clip before (entering
## security) and after (ARCH through LEAVE); and each change between the two
## blends from the pose drawn (no pop). Controls: ticks in all three stretches.
func test_runner_walks_over_its_put_in_and_runs_outside_it() -> void:
	var seen := _watch_gait([1, false, true])
	_assert_walks_over_the_put_in(seen)


## A runner with two bags also puts both in during UNPACK at a walk and runs
## before and after.
func test_two_bag_runner_walks_over_its_put_in_and_runs_outside_it() -> void:
	var seen := _watch_gait([2, false, true])
	_assert_walks_over_the_put_in(seen)


## A runner with no bags has nothing to put in: it runs on every moving tick
## at security (UNPACK step included), and return_walk_mm() stays NAN under S1.
func test_no_bag_runner_keeps_running() -> void:
	var seen := _watch_gait([0, false, true])
	assert_int(seen["before"]["run"]).is_greater(0)
	assert_int(seen["inside"]["run"]).is_greater(0)
	assert_int(seen["after"]["run"]).is_greater(1)
	assert_int(_walks(seen)).is_equal(0)
	assert_int(seen["return_walk_ticks"]).is_equal(0)


## A late passenger with a bag and no alarm still walks during UNPACK put-in
## and runs before and after, with return_walk_mm() NAN (no Phase.RETURN).
func test_late_passenger_without_alarm_walks_unpack_and_runs_arch() -> void:
	var seen := _watch_gait([1, false, false])
	_assert_walks_over_the_put_in(seen)
	assert_int(seen["return_walk_ticks"]).is_equal(0)


func _assert_walks_over_the_put_in(seen: Dictionary) -> void:
	assert_int(seen["inside"]["walk"]).is_greater(0)
	assert_int(seen["inside"]["run"]).is_equal(0)
	assert_int(seen["before"]["run"]).is_greater(0)
	assert_int(seen["before"]["walk"]).is_equal(0)
	assert_int(seen["after"]["run"]).is_greater(0)
	assert_int(seen["after"]["walk"]).is_equal(0)
	assert_float(seen["worst_speed"]).is_less(SPEED_EPS)
	assert_array(seen["changes"]).contains_exactly(
		["run>walk blending=true", "walk>run blending=true"]
	)


func _walks(seen: Dictionary) -> int:
	var total := 0
	for key in ["before", "inside", "after"]:
		total += int(seen[key]["walk"])
	return total


## Sends one passenger with `traits` ([bags, liquids, alarm]) through the lane,
## kept late every tick and drawn every tick, and tallies its clip on every
## moving tick while approaching and inside security: before UNPACK, inside
## UNPACK put-in (`SecurityLooks.putting_in`), and after UNPACK (ARCH onward).
func _watch_gait(traits: Array) -> Dictionary:
	var w := _make()
	var p := w.world.passenger(w.send_all([traits])[0])
	var views := _views_of(w)
	var seen := {
		"before": {"walk": 0, "run": 0},
		"inside": {"walk": 0, "run": 0},
		"after": {"walk": 0, "run": 0},
		"worst_speed": 0.0,
		"changes": [],
		"return_walk_ticks": 0,
	}
	var was := ""
	for n in 3000:
		p.late = true
		w.world.step()
		views.draw()
		if w.cleared.has(p.id):
			break
		if not is_nan(SecurityLooks.return_walk_mm(w.world.sim, p)):
			seen["return_walk_ticks"] += 1
		var node := views.node_for(p.id)
		var in_scope := (
			p.stage
			in [
				Passenger.Stage.TO_SECURITY,
				Passenger.Stage.SECURITY_QUEUE,
				Passenger.Stage.SECURITY,
			]
		)
		if node == null or not in_scope or not p.late:
			continue
		var clip: String = node.get_meta(&"clip", "")
		if clip != "walk" and clip != "run":
			continue
		if clip != was and was != "":
			var fade: ClipCrossfade = node.get_meta(&"crossfade")
			seen["changes"].append("%s>%s blending=%s" % [was, clip, fade.blending()])
		was = clip
		var key := "before"
		if p.stage == Passenger.Stage.SECURITY and p.security_phase == SecurityRuntime.Phase.UNPACK:
			key = "inside"
		elif p.stage == Passenger.Stage.SECURITY:
			key = "after"
		if key == "inside" and clip == "walk":
			var body: int = node.get_meta(&"body")
			var step: Vector3 = views._cur[p.id] - views._prev[p.id]
			var step_mm := roundi(step.length() * 1000.0)
			var want := step_mm * SimClock.TICK_RATE / 1000.0 / PassengerLooks.CLIP_WALK_MPS[body]
			var base: float = node.get_meta(&"base_speed", 0.0)
			seen["worst_speed"] = maxf(seen["worst_speed"], absf(base - want))
		seen[key][clip] += 1
		print("tick %d phase %d (%s): %s" % [w.world.clock.tick, p.security_phase, key, clip])
	print("traits %s: %s" % [traits, seen])
	assert_bool(w.cleared.has(p.id)).is_true()
	return seen


## Drawing the runner changes nothing in the sim: one world drawn every tick
## and one never drawn, of one seed, put the runner on the same cells at the
## same distance walked on every tick, and clear it on the same tick. Control:
## the drawn world drew the runner walking over its put-in.
func test_drawing_the_put_in_walk_leaves_the_sim_alone() -> void:
	var drawn := _make()
	var bare := _make()
	var a := drawn.world.passenger(drawn.send_all([[1, false, true]])[0])
	var b := bare.world.passenger(bare.send_all([[1, false, true]])[0])
	var views := _views_of(drawn)
	var walked := 0
	var differ := 0
	var ticks := 0
	for n in 3000:
		a.late = true
		b.late = true
		drawn.world.step()
		bare.world.step()
		views.draw()
		ticks += 1
		var at_a := drawn.world.sim.world_position(a)
		var at_b := bare.world.sim.world_position(b)
		if not at_a.is_equal_approx(at_b) or a.odometer_mm != b.odometer_mm:
			differ += 1
		var node := views.node_for(a.id)
		if node != null and SecurityLooks.putting_in(drawn.world.sim, a):
			walked += int(node.get_meta(&"clip", "") == "walk")
		if drawn.cleared.has(a.id) or bare.cleared.has(b.id):
			break
	print("ticks %d, drawn walking %d, ticks the two differ %d" % [ticks, walked, differ])
	assert_bool(drawn.cleared.has(a.id)).is_true()
	assert_bool(bare.cleared.has(b.id)).is_true()
	assert_int(walked).is_greater(0)
	assert_int(differ).is_equal(0)


func _make() -> SecurityTestWorld:
	var w := SecurityTestWorld.make(true)
	_worlds.append(w)
	return w


func _views_of(w: SecurityTestWorld) -> PassengerViews:
	var views := PassengerTestWorld.views()
	views.clock = w.world.clock
	views.sim = w.world.sim
	add_child(views)
	_views.append(views)
	return views
