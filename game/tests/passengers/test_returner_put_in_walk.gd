extends GdUnitTestSuite
## A running returner (late, on its second pass through a security lane) is
## drawn walking while it puts its bag into the tray, then running on (board
## b1754061, user-ruled 2026-11-17 "Slow to a walk"): the walk clip over its
## put-in (SecurityLooks.putting_in(), PUT_IN_BEFORE_MM before the unpack
## cell's centre to PUT_IN_PAST_MM past it), the run clip outside it. A drawing
## change only: the sim walks the same cells at the same pace either way.

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


## A runner with one bag, drawn every tick: on every moving tick inside its
## put-in it plays the walk clip, at the speed it is walked by; on every
## moving tick of its arch walk outside it, the run clip. Controls: ticks
## were seen inside the window and on both sides of it, and the runner was
## drawn running before the window too (it is a runner, not a walker).
func test_runner_walks_over_its_put_in_and_runs_outside_it() -> void:
	var w := _make()
	var p := w.world.passenger(w.send_all([[1, false, true]])[0])
	var views := _views_of(w)
	var inside := {"walk": 0, "run": 0}
	var before_it := {"walk": 0, "run": 0}
	var after_it := {"walk": 0, "run": 0}
	var worst_speed := 0.0
	for n in 3000:
		p.late = true
		w.world.step()
		views.draw()
		if w.cleared.has(p.id):
			break
		var node := views.node_for(p.id)
		if node == null:
			continue
		var clip: String = node.get_meta(&"clip", "")
		if clip != "walk" and clip != "run":
			continue
		var past := SecurityLooks.return_walk_mm(w.world.sim, p)
		if is_nan(past):
			continue
		var tally := after_it
		if past < -SecurityLooks.PUT_IN_BEFORE_MM:
			tally = before_it
		elif past <= SecurityLooks.PUT_IN_PAST_MM:
			tally = inside
			# The pace drawn on a security tick is the drawn step (a chord
			# across the unpack cell's corner), as for a walker there.
			var body: int = node.get_meta(&"body")
			var step: Vector3 = views._cur[p.id] - views._prev[p.id]
			var step_mm := roundi(step.length() * 1000.0)
			var want := step_mm * SimClock.TICK_RATE / 1000.0 / PassengerLooks.CLIP_WALK_MPS[body]
			var base: float = node.get_meta(&"base_speed", 0.0)
			worst_speed = maxf(worst_speed, absf(base - want))
			print("  step %d mm, clip speed %.3f, want %.3f" % [step_mm, base, want])
		tally[clip] += 1
		print("tick %d past %.0f mm: %s" % [w.world.clock.tick, past, clip])
	print(
		(
			"before %s, inside %s, after %s, worst speed off %.4f"
			% [before_it, inside, after_it, worst_speed]
		)
	)
	assert_bool(w.cleared.has(p.id)).is_true()
	assert_int(inside["walk"]).is_greater(0)
	assert_int(inside["run"]).is_equal(0)
	assert_int(after_it["run"]).is_greater(0)
	assert_int(after_it["walk"]).is_equal(0)
	assert_int(before_it["run"] + after_it["run"]).is_greater(1)
	assert_float(worst_speed).is_less(SPEED_EPS)


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
