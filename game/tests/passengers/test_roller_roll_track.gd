class_name TestRollerRollTrack
extends GdUnitTestSuite
## The sim track a roller's floor>pull decides its roll from
## (RollerPark.roll_step(), board c0707a22), read against the move's own
## "since": a restamp reads the same ticks, a first draw past the track's
## reach decides no roll, and a rolled roller is parked and carried from the
## track's sim data, so a walker that moved or turned before a late first
## draw plans the same rolled roller as one drawn every frame (Sol re-checks
## of c5778e7 and 57cc65f). Split from test_roller_roll_upright.gd (gdlint
## max-public-methods).

const UP := RollerPark.TICKS_UP


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


## One rolled pick-up of a walker at `points` (its tick position on each sim
## tick, the last held after), facing yaw 0 throughout, stamped on tick
## `stamp_tick` with the body drawn at `drawn` (as CarryPlace stamps it on its
## first frame): the planned roller (RollerPark.plan()) at the same k's, in
## its park and rolling, drawn with the body where it stood.
func _rolled_plans(points: Array[Vector3], stamp_tick: int, drawn: Transform3D) -> Array:
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
	assert_bool(RollerPark.rolls(bag)).is_true()
	var stood := Transform3D(Basis.IDENTITY, points[last])
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
	return out


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


## (a) A walker that shifts 0.4 m before tick ROLL_FROM, then stands to
## ROLL_TO (so it rolls): drawn every frame it is stamped where it was before
## the shift, first drawn 9 ticks late where it stood. Its roller is parked
## from the first tick's sim point and face, so both plan the same roller
## (Sol re-check of 57cc65f: parked in the drawn stamp's frame they differed
## by the shift for good).
func test_a_walker_shifted_before_it_stood_plans_the_same_at_every_cadence() -> void:
	var points: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	points.append(Vector3(0.4, 0.0, 0.0))
	var every := _rolled_plans(points, 0, Transform3D.IDENTITY)
	var late := _rolled_plans(points, 9, Transform3D(Basis.IDENTITY, Vector3(0.4, 0.0, 0.0)))
	_assert_same_rolled("shifted", every, late)


## (b) A walker that turns in place before a late stamp (its body drawn at yaw
## 1.0 on the late frame, 0 on the first): the same rolled roller, parked
## facing the first tick's face, not the drawn body's yaw.
func test_a_walker_turned_before_a_late_stamp_plans_the_same_at_every_cadence() -> void:
	var points: Array[Vector3] = [Vector3.ZERO]
	var every := _rolled_plans(points, 0, Transform3D.IDENTITY)
	var late := _rolled_plans(points, 9, Transform3D(Basis(Vector3.UP, 1.0), Vector3.ZERO))
	_assert_same_rolled("turned", every, late)


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
