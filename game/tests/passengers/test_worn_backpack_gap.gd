class_name TestWornBackpackGap
extends GdUnitTestSuite
## A worn backpack placed by CarryPlace.carry_transform() rests against its
## walker's back (board 4af10dd0: on main it stood about 0.18 m off the
## Spine_03 bone, an air gap behind the back and no straps): on every body
## (PassengerLooks.BODIES, both sexes), in the idle and walk clips at SAMPLES
## moments each, one bag and two (TWO_BAG_SCALE), the body turned two ways,
## the least distance from the back's own vertices to the pack's panel face
## (spike/worn_back_gap.gd) is at most WORN_GAP_M and no back vertex is
## through the panel. The body points are skinned by hand, so a headless run
## reads the clip's pose.

const WornBackGap := preload("res://spike/worn_back_gap.gd")
const FloatCheck := preload("res://spike/carry_float_check.gd")
const CLIPS: Array[String] = ["idle", "walk"]
const SAMPLES := 4
const YAWS: Array[float] = [0.0, 2.2]

var _props: CarryOnProps


func before_test() -> void:
	_props = auto_free(CarryOnProps.new())
	add_child(_props)


## Body `b` at the origin turned to `yaw`, `clip` playing from `at` seconds,
## its carry rig made.
func _body(b: int, clip: String, at: float, yaw: float) -> Node3D:
	var body: Node3D = auto_free(PassengerLooks.SCENES[b].instantiate())
	add_child(body)
	body.rotation.y = yaw
	var player := body.get_node("AnimationPlayer") as AnimationPlayer
	player.play(clip)
	player.seek(fmod(at, player.current_animation_length), true)
	# As PassengerViews marks its pooled characters (carry_place.gd reads it).
	body.set_meta(&"body", b)
	_props._rig(body)
	return body


## The pack worn on `body` as CarryOnProps places it, at `scale_by`.
func _worn(body: Node3D, pack: Node3D, scale_by: float) -> Transform3D:
	var held := {
		"scale": scale_by,
		"bags":
		[{"node": pack, "kind": SecurityLooks.Kind.BACKPACK, "carry": SecurityLooks.Carry.BACK}],
	}
	return CarryPlace.carry_transform(_props, held, body, 0, [CarryOnProps.REACH_BUILT_M])


func test_a_worn_backpack_rests_on_every_back() -> void:
	var pack: Node3D = auto_free(
		InteriorKit.instantiate(SecurityLooks.KIND_PIECES[SecurityLooks.Kind.BACKPACK])
	)
	add_child(pack)
	var measured := 0
	for b in PassengerLooks.BODIES.size():
		var lo := INF
		var hi := -INF
		var fewest := 1 << 30
		var off_back := 0.0
		var least := ""
		for clip in CLIPS:
			for n in SAMPLES:
				for yaw in YAWS:
					var body := _body(b, clip, n * 0.29, yaw)
					await get_tree().process_frame
					await get_tree().process_frame
					for scale_by in [1.0, SecurityLooks.TWO_BAG_SCALE]:
						pack.global_transform = _worn(body, pack, scale_by)
						var got: Array = WornBackGap.gap(body, pack)
						if got[0] < lo:
							var player := body.get_node("AnimationPlayer") as AnimationPlayer
							var local: Vector3 = pack.global_transform.affine_inverse() * got[1]
							least = (
								"%s %.2f s (at %.3f) yaw %.1f scale %.2f, pack-local %s"
								% [
									clip,
									n * 0.29,
									player.current_animation_position,
									yaw,
									scale_by,
									local
								]
							)
						lo = minf(lo, got[0])
						hi = maxf(hi, got[0])
						fewest = mini(fewest, got[2])
						off_back = maxf(off_back, FloatCheck.back_gap(body, pack))
						measured += 1
					remove_child(body)
		print(
			(
				(
					"body %d %s: panel gap %.3f (%s)..%.3f m (0..%.2f), fewest back points in"
					+ " outline %d, FLOAT check off the back %.3f m (0)"
				)
				% [
					b,
					PassengerLooks.BODIES[b],
					lo,
					least,
					hi,
					WornBackGap.WORN_GAP_M,
					fewest,
					off_back
				]
			)
		)
		assert_float(off_back).is_equal(0.0)
		assert_float(hi).is_less_equal(WornBackGap.WORN_GAP_M)
		assert_float(lo).is_greater_equal(0.0)
		assert_int(fewest).is_greater_equal(10)
	assert_int(measured).is_equal(PassengerLooks.BODIES.size() * CLIPS.size() * SAMPLES * 4)


## Discriminating control: the same pack moved 0.15 m further off the back
## reads a gap over WORN_GAP_M (and the FLOAT check reads it off the back),
## and moved the other way past its own gap reads negative.
func test_the_gap_sees_a_pack_off_the_back_and_one_through_it() -> void:
	var pack: Node3D = auto_free(
		InteriorKit.instantiate(SecurityLooks.KIND_PIECES[SecurityLooks.Kind.BACKPACK])
	)
	add_child(pack)
	var body := _body(0, "idle", 0.0, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var worn := _worn(body, pack, 1.0)
	var off := worn.basis.y.normalized()
	pack.global_transform = worn
	var base: float = WornBackGap.gap(body, pack)[0]
	pack.global_transform = worn.translated(off * 0.15)
	var away: Array = WornBackGap.gap(body, pack)
	var float_off := FloatCheck.back_gap(body, pack)
	pack.global_transform = worn.translated(-off * (base + 0.03))
	var into: Array = WornBackGap.gap(body, pack)
	print(
		(
			(
				"worn gap %.3f; 0.15 m off: gap %.3f, FLOAT check off the back %.3f; moved in"
				+ " past it: gap %.3f"
			)
			% [base, away[0], float_off, into[0]]
		)
	)
	assert_float(away[0]).is_greater(WornBackGap.WORN_GAP_M + 0.1)
	assert_float(float_off).is_greater(0.1)
	assert_float(into[0]).is_less(0.0)


## The tray>back move (decision backpack-tray-back-move-as-built-the-table-
## side-hand-leads-held-over-its-loop) ends exactly where the pack is worn now,
## on a male and a female body, so it does not jump when the move ends; just
## before its end it is already within a few cm of it. The move is planned as
## TestCarryLaneBackpackPickup plans it, its end from CarryPlace.carry_transform().
func test_the_tray_to_back_move_ends_on_the_new_pose() -> void:
	var pack: Node3D = auto_free(
		InteriorKit.instantiate(SecurityLooks.KIND_PIECES[SecurityLooks.Kind.BACKPACK])
	)
	add_child(pack)
	for b in [0, PassengerLooks.PER_VARIANT + 3]:
		var body := _body(b, "idle", 0.0, 0.0)
		await get_tree().process_frame
		await get_tree().process_frame
		var want := _worn(body, pack, 1.0)
		pack.global_position = Vector3(0.6, 0.8, 0.4)
		var start := pack.global_transform
		var held := {"homes": [SecurityLooks.Home.HAND]}
		var bag := {
			"node": pack,
			"kind": SecurityLooks.Kind.BACKPACK,
			"home": SecurityLooks.Home.TRAY * 4,
			"place": SecurityLooks.Home.HAND * 4,
			"changed": 10.0,
			"carry": SecurityLooks.Carry.BACK,
			"carry_placed": SecurityLooks.Carry.BACK,
		}
		var dims := {
			"hand": 0,
			"grips": [Vector3(-0.2, 0.9, 0.05), Vector3(0.2, 0.9, 0.05)],
			"shoulders_y": [1.42, 1.42],
			"bar_z": 0.0,
			"scale": 1.0,
			"strap_top": Vector3.ZERO,
		}
		var flags := {
			"in_stall": false,
			"hand_carry": false,
			"from_floor": false,
			"to_floor": false,
			"hand": 0,
			"clear": CarryOnProps.TRANSFER_CLEAR_M,
			"yaw": 0.0,
		}
		CarryPlace._stamp(_props, held, bag, body, want, 0)
		var frame := body.global_transform
		var end: Dictionary = CarryLead.plan(bag, 1.0, start, want, frame, flags, dims)
		var near: Dictionary = CarryLead.plan(bag, 0.98, start, want, frame, flags, dims)
		var at_end := (end["xf"] as Transform3D).origin.distance_to(want.origin)
		var turn := (end["xf"] as Transform3D).basis.orthonormalized().get_rotation_quaternion()
		var angle := turn.angle_to(want.basis.orthonormalized().get_rotation_quaternion())
		var before := (near["xf"] as Transform3D).origin.distance_to(want.origin)
		print(
			(
				"body %d %s tray>back: end of move vs worn %.5f m, %.4f rad, holder %d; at k 0.98 %.3f m"
				% [b, PassengerLooks.BODIES[b], at_end, angle, end["holder"], before]
			)
		)
		assert_float(at_end).is_less(0.001)
		assert_float(angle).is_less(0.001)
		assert_int(end["holder"]).is_equal(-1)
		assert_float(before).is_less(0.05)
		remove_child(body)
