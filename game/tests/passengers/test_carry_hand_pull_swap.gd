class_name TestCarryHandPullSwap
extends GdUnitTestSuite
## A roller taken from one hand's carry into the other hand's pull
## (hand.R>pull.L and hand.L>pull.R, CarryLead.hand_pull_path(); user ruling
## 2026-11-17 "In front, at hip height", board 295026a6): the bar is brought
## round in front of the body at about hip height, taken by the other hand
## half way, and the roller trails behind on the new side. Plan data only
## (anti-pattern d655fcc9): the same k gives the same plan, whatever height
## the giving hand is drawn at. Geometric clearance against a skinned walk
## clip (arms left out, they are posed by the reach) is a design check only:
## the windowed crossing probe's SELF_FAIL count is the drawn one (anti-pattern
## a-headless-count-of-body-points-inside-a-carried-bag-reads-0).

const STEPS := 50
const SHOULDER_Y := 1.4
## About hip height: SWAP_HIP_BELOW_M under the shoulder joints (0.95 m here)
## give or take 0.1 m (a standing body's hip joint is 0.9 to 1.0 m up).
const HIP_BAND := Vector2(0.85, 1.05)
## In front of the body at the handover: at least this far ahead of its centre
## (the belly's front is about 0.15 m ahead).
const FRONT_MIN_M := 0.2
const PHASES := 8
## Bones whose vertices are left out of the clearance count: the arms, posed
## in the game by the reach toward the plan's targets, not by the walk clip.
const ARM_WORDS := [
	"Arm", "Hand", "Finger", "Thumb", "Index", "Middle", "Ring", "Pinky", "Shoulder"
]

var _base := 0.0
var _shell := AABB()
## Per body (PassengerLooks.BODIES, first male and first female): walk poses,
## each the body's non-arm vertices in its own frame (facing +z).
var _walks: Array = []


func before() -> void:
	var roller := InteriorKit.instantiate("carry_roller")
	add_child(roller)
	var reach: Node3D = roller.find_child("Pull_Reach", true, false)
	_base = reach.get_meta(&"base", reach.position).z
	var rods: Array = CarryOnProps.REACH_NODES[SecurityLooks.Kind.ROLLER]
	var first := true
	for mi: MeshInstance3D in roller.find_children("*", "MeshInstance3D", true, false):
		var in_rods := false
		var at: Node = mi
		while at != roller:
			in_rods = in_rods or at.name in rods
			at = at.get_parent()
		if in_rods or mi.mesh == null:
			continue
		var part := (
			roller.global_transform.affine_inverse() * mi.global_transform * mi.mesh.get_aabb()
		)
		_shell = part if first else _shell.merge(part)
		first = false
	roller.free()
	for b: int in [0, PassengerLooks.PER_VARIANT]:
		var node := PassengerLooks.SCENES[b].instantiate() as Node3D
		add_child(node)
		var player := node.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.play("walk")
		var poses: Array[PackedVector3Array] = []
		for n in PHASES:
			player.seek(player.current_animation_length * n / PHASES, true)
			poses.append(_skinned_no_arms(node))
		_walks.append(poses)
		node.free()


## Across the whole swap, either hand to the other, at two body headings: the
## bar (the holding hand's target) never goes above the shoulder joints; half
## way it is ahead of the body's centre by FRONT_MIN_M or more and at about hip
## height (HIP_BAND), where the hand changes. Control: path(), which carried
## this move before, takes the bar over the shoulders for the same move.
func test_the_bar_comes_round_the_front_at_hip_height() -> void:
	for yaw: float in [0.0, 0.8]:
		var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(3.0, 0.0, -2.0))
		for gave in 2:
			var highest := -INF
			var old_highest := -INF
			var mid := Vector3.ZERO
			var holders := {}
			for step in STEPS + 1:
				var k := float(step) / STEPS
				var made := _swap(frame, gave, k)
				var plan: Dictionary = made[0]
				var holder: int = plan["holder"]
				holders[holder] = true
				var bar := frame.affine_inverse() * (plan["targets"][holder] as Vector3)
				highest = maxf(highest, bar.y)
				if is_equal_approx(k, 0.5):
					mid = frame.affine_inverse() * ((plan["xf"] as Transform3D) * plan["anchor"])
				var old := CarryLead.path(made[1], made[2], k, frame, made[3], made[4])
				old_highest = maxf(old_highest, (frame.affine_inverse() * (old * made[5])).y)
			print(
				(
					"yaw %.1f hand %d>%d: bar at most %.3f m up (old path %.3f), half way %s"
					% [yaw, gave, 1 - gave, highest, old_highest, mid]
				)
			)
			assert_bool(holders.has(gave) and holders.has(1 - gave)).is_true()
			assert_float(highest).is_less_equal(SHOULDER_Y)
			assert_float(mid.z).is_greater_equal(FRONT_MIN_M)
			assert_float(mid.y).is_between(HIP_BAND.x, HIP_BAND.y)
			assert_float(absf(mid.x)).is_less_equal(0.05)
			assert_float(old_highest).is_greater(SHOULDER_Y - 0.2)


## The same k gives the same plan: planned twice, and with the giving hand
## drawn 0.2 m higher (the hand this move poses, anti-pattern d655fcc9), every
## target and the bag's place are the same. Control: the targets do move
## through the swap.
func test_the_same_k_gives_the_same_plan() -> void:
	var frame := Transform3D(Basis(Vector3.UP, 0.8), Vector3(3.0, 0.0, -2.0))
	var moved := 0.0
	for gave in 2:
		var last := Vector3.ZERO
		for step in STEPS + 1:
			var k := float(step) / STEPS
			var a: Dictionary = _swap(frame, gave, k)[0]
			var b: Dictionary = _swap(frame, gave, k)[0]
			var c: Dictionary = _swap(frame, gave, k, 0.2)[0]
			for hand in 2:
				var at: Vector3 = a["targets"][hand]
				assert_float(at.distance_to(b["targets"][hand])).is_equal(0.0)
				assert_float(at.distance_to(c["targets"][hand])).is_less_equal(0.0001)
			var xf: Transform3D = a["xf"]
			assert_bool(xf.is_equal_approx(c["xf"])).is_true()
			var holding: Vector3 = a["targets"][a["holder"]]
			if step > 0:
				moved += holding.distance_to(last)
			last = holding
	print("targets moved %.3f m in all over both swaps" % moved)
	assert_float(moved).is_greater(1.0)


## Design check (not the drawn count, which is the windowed crossing probe's
## SELF_FAIL): the roller's shell, placed where the plan puts it, takes in no
## more non-arm vertices of a walking male or female body than path() (which
## carried this move before) at any k of either swap, and a tenth of path()'s
## total or less. The ends are the move's own (this rig's pull end touches a
## striding leg). Control: the same bag at the handover turned as it started
## (upright, no swap_lean()) takes in the legs.
func test_the_roller_keeps_off_the_walking_legs() -> void:
	var frame := Transform3D.IDENTITY
	var hits := 0
	var old_hits := 0
	var upright := 0
	for w in _walks.size():
		for gave in 2:
			for step in STEPS + 1:
				var k := float(step) / STEPS
				var made := _swap(frame, gave, k)
				var plan: Dictionary = made[0]
				var xf: Transform3D = plan["xf"]
				var old := CarryLead.path(made[1], made[2], k, frame, made[3], made[4])
				var now_in := 0
				var old_in := 0
				for points: PackedVector3Array in _walks[w]:
					now_in += _inside(points, xf)
					old_in += _inside(points, old)
					if step == STEPS / 2:
						var held: Vector3 = plan["anchor"]
						var bar: Vector3 = xf * held
						var stood := Transform3D(made[1].basis, bar - made[1].basis * held)
						upright += _inside(points, stood)
				if now_in > 0:
					print(
						"body %d hand %d k %.2f: %d in (path() %d)" % [w, gave, k, now_in, old_in]
					)
				assert_int(now_in).is_less_equal(old_in)
				hits += now_in
				old_hits += old_in
	print(
		(
			"walking body vertices in the roller: %d (path() %d); upright at the handover %d"
			% [hits, old_hits, upright]
		)
	)
	assert_int(upright).is_greater(0)
	assert_int(old_hits).is_greater(0)
	assert_int(hits * 10).is_less_equal(old_hits)


## One hand to pull swap of a roller from hand `gave` (0 right) at `k`, the
## body at `frame`, the giving hand drawn `raised` higher than its carry:
## [the plan, start, want (world), the bag's start in the body's frame, the
## flags, the bar as held at the start (its own frame)].
func _swap(frame: Transform3D, gave: int, k: float, raised := 0.0) -> Array:
	var side := -1.0 if gave == 0 else 1.0
	var grips := [Vector3(-0.26, 0.80, 0.02), Vector3(0.26, 0.80, 0.02)]
	var from := CarryHand.carried(
		grips[gave], Vector3(0.0, 0.8, 0.0), 0.0, 1.0, SecurityLooks.Kind.ROLLER
	)
	var axle := Vector3(-side * 0.35, 0.04, -0.8)
	var want := RollerPull.pulled(grips[1 - gave], axle, 1.0)
	var rods := RollerPull.pull_length(grips[1 - gave], axle, 1.0, _base)
	var bag := {
		"kind": SecurityLooks.Kind.ROLLER,
		"home": (SecurityLooks.Home.HAND * 2 + (1 - gave)) * 2,
		"carry": SecurityLooks.Carry.PULL,
		"was": (SecurityLooks.Home.HAND * 2 + gave) * 2 + 1,
		"carry_from": SecurityLooks.Carry.HAND,
		"from": from,
		"anchor_from": CarryOnProps.ROLLER_HANDLE,
	}
	var into := CarryLead.carry_t(k, bag)
	var bar_z := (
		lerpf(CarryOnProps.REACH_BUILT_M, rods, into) + _base + CarryOnProps.ROLLER_GRIP_PAST_TOP_M
	)
	var drawn := [frame * grips[0], frame * grips[1]]
	drawn[gave] += Vector3.UP * raised
	var body := {
		"hand": gave,
		"grips": drawn,
		"shoulders_y": [SHOULDER_Y, SHOULDER_Y],
		"bar_z": bar_z,
		"scale": 1.0,
		"strap_top": Vector3.ZERO,
	}
	var flags := {
		"in_stall": false,
		"hand_carry": false,
		"hand": gave,
		"yaw": frame.basis.get_euler().y,
		"clear": CarryOnProps.TRANSFER_CLEAR_M,
	}
	assert_bool(CarryLead.is_hand_pull_swap(bag, false)).is_true()
	var start := frame * from
	var plan := CarryLead.plan(bag, k, start, frame * want, frame, flags, body)
	var bar := Vector3(0.0, CarryOnProps.ROLLER_AXLE.y, bar_z)
	return [plan, start, frame * want, from, flags, bar]


func _inside(points: PackedVector3Array, placed: Transform3D) -> int:
	var to_bag := placed.affine_inverse()
	var count := 0
	for v in points:
		count += int(_shell.has_point(to_bag * v))
	return count


## The vertices of `node`'s body mesh in the pose its skeleton holds now,
## skinned by hand (linear blend), in `node`'s frame, but those mostly on an
## arm bone (ARM_WORDS).
static func _skinned_no_arms(node: Node3D) -> PackedVector3Array:
	var mi := PassengerLooks.body_mesh(node)
	var skeleton := mi.get_node(mi.skeleton) as Skeleton3D
	var to_node := node.global_transform.affine_inverse() * skeleton.global_transform
	var mats: Array[Transform3D] = []
	var arm: Array[bool] = []
	for bind in mi.skin.get_bind_count():
		var name := mi.skin.get_bind_name(bind)
		var bone := skeleton.find_bone(name) if name != "" else mi.skin.get_bind_bone(bind)
		mats.append(to_node * skeleton.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind))
		var bone_name := skeleton.get_bone_name(bone)
		arm.append(ARM_WORDS.any(func(word: String) -> bool: return bone_name.contains(word)))
	var out := PackedVector3Array()
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / verts.size()
		for k in verts.size():
			var v := Vector3.ZERO
			var most := 0
			for j in per:
				v += (mats[bones[k * per + j]] * verts[k]) * weights[k * per + j]
				if weights[k * per + j] > weights[k * per + most]:
					most = j
			if not arm[bones[k * per + most]]:
				out.append(v)
	return out
