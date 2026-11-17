extends GdUnitTestSuite
## A running returner (late, on its second pass through a security lane) is
## drawn walking while it puts its bags into the tray, then running on (board
## b1754061, user-ruled 2026-11-17 "Slow to a walk"): the walk clip over its
## put-in, the run clip outside it. A drawing change only: the sim walks the
## same cells at the same pace either way.

## The walk clip's speed may differ from the speed walked by at most this.
const SPEED_EPS := 0.001
## The span drawn at a walk, mm from the unpack cell's centre along the arch
## walk (SecurityLooks.return_walk_mm()): the whole 1 m put-in, 750 mm before
## the centre to 250 mm past it (user-ruled 2026-11-17 through the question
## form, "1 m, the put-in (Recommended)"). Written out here, not read from
## SecurityLooks, so a change of the window there fails this test.
const WALK_FROM_MM := -750.0
const WALK_TO_MM := 250.0

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


## A runner with one bag: the walk clip on every moving tick inside the 1 m
## span, at the speed it is drawn moving; the run clip on every moving tick of
## its arch walk before and after it; and each change between the two blends
## from the pose drawn (no pop). Controls: ticks on both sides and inside.
func test_runner_walks_over_its_put_in_and_runs_outside_it() -> void:
	var seen := _watch_gait([1, false, true])
	_assert_walks_over_the_span(seen)


## A runner with two bags puts both in over the same 1 m (one after the other,
## SecurityLooks.put_in_window()), so it walks over the whole of it too.
func test_two_bag_runner_walks_over_its_put_in_and_runs_outside_it() -> void:
	var seen := _watch_gait([2, false, true])
	_assert_walks_over_the_span(seen)


## A runner with no bags has nothing to put in: it runs its whole arch walk.
## Control: it walked the arch walk (ticks seen on it, inside the span too).
func test_no_bag_returner_keeps_running() -> void:
	var seen := _watch_gait([0, false, true])
	var arch: int = seen["before"]["run"] + seen["inside"]["run"] + seen["after"]["run"]
	assert_int(seen["inside"]["run"]).is_greater(0)
	assert_int(arch).is_greater(1)
	assert_int(_walks(seen)).is_equal(0)


## A late passenger on its first and only pass (no alarm) never walks the arch
## walk of a returner: it runs every moving tick at security. Control: it was
## drawn moving at security, and never on a returner's arch walk.
func test_late_passenger_without_a_second_pass_keeps_running() -> void:
	var seen := _watch_gait([1, false, false])
	assert_int(seen["off"]["run"]).is_greater(0)
	var arch: int = seen["before"]["run"] + seen["inside"]["run"] + seen["after"]["run"]
	assert_int(arch).is_equal(0)
	assert_int(_walks(seen)).is_equal(0)


func _assert_walks_over_the_span(seen: Dictionary) -> void:
	assert_int(seen["inside"]["walk"]).is_greater(0)
	assert_int(seen["inside"]["run"]).is_equal(0)
	assert_int(seen["before"]["run"]).is_greater(0)
	assert_int(seen["before"]["walk"]).is_equal(0)
	assert_int(seen["after"]["run"]).is_greater(0)
	assert_int(seen["after"]["walk"]).is_equal(0)
	assert_int(seen["off"]["walk"]).is_equal(0)
	assert_float(seen["worst_speed"]).is_less(SPEED_EPS)
	assert_array(seen["changes"]).contains_exactly(
		["run>walk blending=true", "walk>run blending=true"]
	)


func _walks(seen: Dictionary) -> int:
	var total := 0
	for key in ["before", "inside", "after", "off"]:
		total += int(seen[key]["walk"])
	return total


## Sends one passenger with `traits` ([bags, liquids, alarm]) through the lane,
## kept late every tick and drawn every tick, and tallies its clip on every
## moving tick at security it is drawn late on: on a returner's arch walk before, inside or after
## the WALK_FROM_MM to WALK_TO_MM span, or off it ("off"). Records how far the
## walk clip's speed is from the drawn step's inside the span, and each clip
## change on the arch walk with whether a blend began on it. Prints each tick.
func _watch_gait(traits: Array) -> Dictionary:
	var w := _make()
	var p := w.world.passenger(w.send_all([traits])[0])
	var views := _views_of(w)
	var seen := {
		"before": {"walk": 0, "run": 0},
		"inside": {"walk": 0, "run": 0},
		"after": {"walk": 0, "run": 0},
		"off": {"walk": 0, "run": 0},
		"worst_speed": 0.0,
		"changes": [],
	}
	var was := ""
	for n in 3000:
		p.late = true
		w.world.step()
		views.draw()
		if w.cleared.has(p.id):
			break
		var node := views.node_for(p.id)
		# Only ticks it is drawn late on: the sim can clear the flag in a step
		# (a not-late passenger walks anywhere, as before this change).
		if node == null or p.stage != Passenger.Stage.SECURITY or not p.late:
			continue
		var clip: String = node.get_meta(&"clip", "")
		if clip != "walk" and clip != "run":
			continue
		var past := SecurityLooks.return_walk_mm(w.world.sim, p)
		if is_nan(past):
			seen["off"][clip] += 1
			continue
		if clip != was and was != "":
			var fade: ClipCrossfade = node.get_meta(&"crossfade")
			seen["changes"].append("%s>%s blending=%s" % [was, clip, fade.blending()])
		was = clip
		var key := "after"
		if past < WALK_FROM_MM:
			key = "before"
		elif past <= WALK_TO_MM:
			key = "inside"
		if key == "inside" and clip == "walk":
			# The pace drawn on a security tick is the drawn step (a chord
			# across the unpack cell's corner), as for a walker there.
			var body: int = node.get_meta(&"body")
			var step: Vector3 = views._cur[p.id] - views._prev[p.id]
			var step_mm := roundi(step.length() * 1000.0)
			var want := step_mm * SimClock.TICK_RATE / 1000.0 / PassengerLooks.CLIP_WALK_MPS[body]
			var base: float = node.get_meta(&"base_speed", 0.0)
			seen["worst_speed"] = maxf(seen["worst_speed"], absf(base - want))
		seen[key][clip] += 1
		print("tick %d past %.0f mm: %s" % [w.world.clock.tick, past, clip])
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
