class_name TestRollerRollTrack
extends GdUnitTestSuite
## The sim track a roller's floor>pull decides its roll from
## (RollerPark.roll_step(), board c0707a22), read against the move's own
## "since": a restamp reads the same ticks, a first draw past the track's
## reach decides no roll, and a rolled roller is parked and carried from the
## track's sim data, so a walker that turned before a late first draw plans
## the same rolled roller as one drawn every frame (Sol re-checks of c5778e7
## and 57cc65f), standing beside the stood walker, and one that moved before it
## stood tips (Sol final re-check of af14ddf, board bea7e508). Split from
## test_roller_roll_upright.gd (gdlint max-public-methods).

const UP := RollerPark.TICKS_UP
## How far a rolled roller's axle may be from its park beside the body: the
## stood point may sit up to MOVED_M from the first tick's.
const BESIDE_M := RollerPark.MOVED_M + 0.002
## The body's turn from its face as a rolled roller is carried (_carried()).
const TURN_RAD := 0.6


## Steps `bag` through sim ticks `from` to `to` (inclusive) with its walker at
## z `z`, facing yaw 0 (roll_step(), as CarryOnProps.sync() does each tick).
func _ticks(bag: Dictionary, from: int, to: int, z: float) -> void:
	for n in range(from, to + 1):
		RollerPark.roll_step(bag, SecurityLooks.Kind.ROLLER, float(n), Vector3(0.0, 0.0, z), 0.0)


## A first draw more than TRACK_TICKS after the move began finds its first
## tick gone from the track: it decides no roll, and reads no missing tick.
## Control: one TRACK_TICKS - 1 late still holds it and rolls.
func test_a_stamp_past_the_tracks_reach_decides_no_roll() -> void:
	for late: int in [RollerPark.TRACK_TICKS - 1, RollerPark.TRACK_TICKS + 6]:
		var bag := {
			"kind": SecurityLooks.Kind.ROLLER,
			"was": SecurityLooks.Home.FLOOR * 4,
			"carry_from": SecurityLooks.Carry.PULL,
			"from": Transform3D.IDENTITY,
			"changed": 0.0,
		}
		_ticks(bag, 0, late, 0.0)
		bag["since"] = 0.0
		RollerPark.stamp(bag, Transform3D.IDENTITY, 0.0)
		print("stamped %d ticks late: rolls %s" % [late, RollerPark.rolls(bag)])
		assert_bool(bag.has("rolls")).is_true()
		assert_bool(RollerPark.rolls(bag)).is_equal(late < RollerPark.TRACK_TICKS)


## One pick-up of a walker at `points` (its tick position on each sim tick,
## the last held after), facing yaw 0 throughout, stamped on tick `stamp_tick`
## with the body drawn at `drawn` (as CarryPlace stamps it on its first
## frame): {"bag", "plans" (RollerPark.plan()'s roller at the same k's, in its
## park and rolling when it rolls), "frame" (the body those are drawn with:
## where it stood, turned `turn` from the face, so a rolled roller is carried
## through a real body turn, _carried())}.
func _rolled_plans(
	points: Array[Vector3], stamp_tick: int, drawn: Transform3D, turn := 0.0
) -> Dictionary:
	var bag := {
		"kind": SecurityLooks.Kind.ROLLER,
		"led": true,
		"was": SecurityLooks.Home.FLOOR * 4,
		"carry_from": SecurityLooks.Carry.PULL,
		"carry": SecurityLooks.Carry.PULL,
		"home": SecurityLooks.Home.HAND * 4,
		"from": Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.34, 0.0, 0.07)),
		"changed": 0.0,
		"since": 0.0,
	}
	var last := points.size() - 1
	for t in range(0, 31):
		if t == stamp_tick:
			RollerPark.stamp(bag, drawn, 0.0)
			# The take is a pose (RollerPark._taken()); the same in both.
			bag["park_took"] = 0.3
		RollerPark.roll_step(bag, SecurityLooks.Kind.ROLLER, float(t), points[mini(t, last)], 0.0)
	var stood := Transform3D(Basis(Vector3.UP, turn), points[last])
	var grip := stood.origin + Vector3(0.0, 0.8, 0.1)
	var body := {"bar_z": 0.4, "scale": 1.0, "grips": [grip, grip]}
	var start := Transform3D(
		Basis(Vector3.RIGHT, -PI / 2.0), stood.origin + Vector3(0.34, 0.0, 0.07)
	)
	var want := Transform3D(Basis.IDENTITY, stood.origin + Vector3(0.3, 0.0, -0.6))
	var out := []
	for up: float in [0.7, 0.8, 1.2, 1.8]:
		var k := up * UP / CarryLead.ticks_of(bag)
		out.append(RollerPark.plan(bag, k, start, want, stood, {}, body)["xf"])
	return {"bag": bag, "plans": out, "frame": stood}


## The same rolled roller planned from a stamp on the first tick and one 9
## ticks late (past ROLL_FROM), each within SAME_M (2 mm) and 0.005 rad.
func _assert_same_rolled(label: String, every: Array, late: Array) -> void:
	for i in every.size():
		var a: Transform3D = every[i]
		var b: Transform3D = late[i]
		var gap := a.origin.distance_to(b.origin)
		var turn := a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion())
		print("%s plan %d: %.5f m %.5f rad apart" % [label, i, gap, turn])
		assert_float(gap).override_failure_message(label).is_less(0.002)
		assert_float(turn).override_failure_message(label).is_less(0.005)


## Each planned roller of a rolled `run` (_rolled_plans()) stands beside the
## body it is drawn with: its axle RollerPark.PARK_SIDE_M out on the leading
## hand's side (the right, -x, for hand 0) and PARK_AHEAD_M ahead in the
## body's frame, within BESIDE_M (Sol final re-check of af14ddf: parked from a
## first tick 0.4 m before the stood point, it stood that far off the walker).
## The axle's offset is printed against what it should be.
func _assert_beside(label: String, run: Dictionary) -> void:
	var frame: Transform3D = run["frame"]
	var want := Vector3(-RollerPark.PARK_SIDE_M, 0.0, RollerPark.PARK_AHEAD_M)
	for i in run["plans"].size():
		var xf: Transform3D = run["plans"][i]
		var axle := frame.affine_inverse() * (xf * CarryOnProps.ROLLER_AXLE)
		var off := Vector3(axle.x - want.x, 0.0, axle.z - want.z).length()
		var line := (
			"%s plan %d: axle at x %.4f z %.4f in the body's frame" % [label, i, axle.x, axle.z]
		)
		print("%s, %.4f m off" % [line, off])
		assert_float(off).override_failure_message("%s plan %d" % [label, i]).is_less(BESIDE_M)


## (a) A walker that shifts 0.4 m before tick ROLL_FROM, then stands still to
## ROLL_TO, has moved since its first tick: it tips, drawn every frame or
## first drawn 9 ticks late (Sol final re-check of af14ddf: checked only from
## ROLL_FROM on, it rolled, parked from where it was before the shift).
## Control: the same walker standing still from its first tick rolls.
func test_a_walker_shifted_before_it_stood_tips_at_every_cadence() -> void:
	var points: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	points.append(Vector3(0.4, 0.0, 0.0))
	var every := _rolled_plans(points, 0, Transform3D.IDENTITY)
	var late := _rolled_plans(points, 9, Transform3D(Basis.IDENTITY, Vector3(0.4, 0.0, 0.0)))
	var still: Array[Vector3] = [Vector3.ZERO]
	var control := _rolled_plans(still, 0, Transform3D.IDENTITY)
	var rolled := [
		RollerPark.rolls(every["bag"]),
		RollerPark.rolls(late["bag"]),
		RollerPark.rolls(control["bag"])
	]
	print("shifted: rolls %s every, %s late; still: rolls %s" % rolled)
	assert_bool(every["bag"].has("rolls")).is_true()
	assert_bool(late["bag"].has("rolls")).is_true()
	assert_bool(RollerPark.rolls(every["bag"])).is_false()
	assert_bool(RollerPark.rolls(late["bag"])).is_false()
	assert_bool(RollerPark.rolls(control["bag"])).is_true()


## Whatever the walker did before it stood, a rolled roller stands beside the
## stood walker, never where the walker was on its first tick: a walker still
## from its first tick and one that shifted under MOVED_M roll, and stand
## beside it at both cadences; one that shifted 0.4 m before ROLL_FROM either
## tips or stands beside it too.
func test_a_rolled_roller_stands_beside_the_stood_walker() -> void:
	var still: Array[Vector3] = [Vector3.ZERO]
	var nudged: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	nudged.append(Vector3(0.005, 0.0, 0.0))
	var shifted: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	shifted.append(Vector3(0.4, 0.0, 0.0))
	var walkers := {"still": still, "nudged": nudged, "shifted": shifted}
	var rolled := 0
	for name: String in walkers:
		var points: Array[Vector3] = walkers[name]
		var stood := Transform3D(Basis.IDENTITY, points[-1])
		for late: int in [0, 9]:
			var run := _rolled_plans(points, late, stood if late > 0 else Transform3D.IDENTITY)
			var label := "%s late%d" % [name, late]
			print("%s: rolls %s" % [label, RollerPark.rolls(run["bag"])])
			if name != "shifted":
				assert_bool(RollerPark.rolls(run["bag"])).override_failure_message(label).is_true()
			if RollerPark.rolls(run["bag"]):
				_assert_beside(label, run)
				rolled += 1
	assert_int(rolled).is_greater_equal(4)


## (b) A walker that turns in place before a late stamp (its body drawn at yaw
## 1.0 on the late frame, 0 on the first): the same rolled roller, parked
## facing the first tick's face, not the drawn body's yaw. Both are then
## carried through a real body turn (drawn TURN_RAD from the face, _carried()):
## still the same, and beside the turned body, on its hand's side.
func test_a_walker_turned_before_a_late_stamp_plans_the_same_at_every_cadence() -> void:
	var points: Array[Vector3] = [Vector3.ZERO]
	var every := _rolled_plans(points, 0, Transform3D.IDENTITY, TURN_RAD)
	var late := _rolled_plans(
		points, 9, Transform3D(Basis(Vector3.UP, 1.0), Vector3.ZERO), TURN_RAD
	)
	assert_bool(RollerPark.rolls(every["bag"])).is_true()
	assert_bool(RollerPark.rolls(late["bag"])).is_true()
	_assert_same_rolled("turned", every["plans"], late["plans"])
	_assert_beside("turned every", every)
	_assert_beside("turned late9", late)
	# Control: carried with the body, the roller turned with it, away from where
	# it stood in the face's frame.
	var unturned := _rolled_plans(points, 0, Transform3D.IDENTITY)
	var a: Transform3D = every["plans"][2]
	var b: Transform3D = unturned["plans"][2]
	print("turned body: roller %.4f m from the unturned one" % a.origin.distance_to(b.origin))
	assert_float(a.origin.distance_to(b.origin)).is_greater(0.1)


## A pick-up first drawn on a frame where its walker has no face any more
## (sit_face() NAN on the late draw, the face held on its first tick) is still a
## seat's: "faced", so BoothRoller.fix_start() keeps the walls round where it
## stood on that first tick, the same as a stamp drawn on its first tick, not
## round the body drawn late (Sol final re-check of af14ddf: the draw-time face
## lost the walls).
func test_a_late_stamp_with_no_face_keeps_the_seat_walls() -> void:
	var grid := BuildGrid.new()
	var cell := Vector2i(10, 10)
	grid._set_wall(cell, BuildGrid.Side.EAST, BuildGrid.WallKind.PLAIN)
	var sim: PassengerSim = auto_free(PassengerSim.new())
	sim.grid = grid
	var at := grid.cell_to_world(cell)
	var near := PullSide.walls_near(grid, at)
	assert_int(near.size()).is_greater(0)
	var boxes := []
	for late: int in [0, 9]:
		var bag := {
			"kind": SecurityLooks.Kind.ROLLER,
			"was": SecurityLooks.Home.FLOOR * 4,
			"carry_from": SecurityLooks.Carry.PULL,
			"from": Transform3D.IDENTITY,
			"changed": 0.0,
			"since": 0.0,
		}
		for t in range(0, late + 1):
			RollerPark.roll_step(bag, SecurityLooks.Kind.ROLLER, float(t), at, 0.0)
		# Drawn late 4 m on and with no face, as a walker gone from its seat.
		var drawn := Transform3D(Basis.IDENTITY, at + Vector3(4.0, 0.0, 0.0))
		var body := Transform3D(Basis.IDENTITY, at) if late == 0 else drawn
		RollerPark.stamp(bag, body, 0.0 if late == 0 else NAN)
		BoothRoller.fix_start(bag, false, sim, body)
		var kept: Array = bag.get("wall_boxes", [])
		print("late%d: faced %s, %d wall boxes" % [late, bag.get("faced", false), kept.size()])
		assert_bool(bag.get("faced", false)).override_failure_message("late%d" % late).is_true()
		assert_array(bag.get("wall_boxes", [])).override_failure_message("late%d" % late).is_equal(
			near
		)
		boxes.append(bag.get("wall_boxes", []))
	assert_array(boxes[1]).is_equal(boxes[0])


## A move stamped again while its hand still reaches (CarryPlace: it keeps its
## "since", its "changed" is new) reads the same sim track and rolls as one
## stamped once (Sol re-check of c5778e7: keyed to "changed" it never rolled).
func test_a_move_stamped_again_while_reaching_still_rolls() -> void:
	var bag := {
		"kind": SecurityLooks.Kind.ROLLER,
		"was": SecurityLooks.Home.FLOOR * 4,
		"carry_from": SecurityLooks.Carry.PULL,
		"from": Transform3D.IDENTITY,
		"since": 0.0,
		"changed": 0.0,
	}
	_ticks(bag, 0, 0, 0.0)
	RollerPark.stamp(bag, Transform3D.IDENTITY, 0.0)
	_ticks(bag, 1, 2, 0.0)
	bag["changed"] = 2.0
	RollerPark.stamp(bag, Transform3D.IDENTITY, 0.0)
	_ticks(bag, 3, int(RollerPark.ROLL_TO), 0.0)
	assert_bool(RollerPark.rolls(bag)).is_true()
	assert_float(CarryLead.ticks_of(bag)).is_equal(UP + RollerPark.ROLL_TICKS)
	# Stamped again after the decision too: decided the same, from the track.
	RollerPark.stamp(bag, Transform3D.IDENTITY, 0.0)
	assert_bool(RollerPark.rolls(bag)).is_true()
	assert_vector(bag["roll_at"]).is_equal(Vector3.ZERO)
