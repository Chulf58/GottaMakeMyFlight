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
		for clip in CLIPS:
			for n in SAMPLES:
				for yaw in YAWS:
					var body := _body(b, clip, n * 0.29, yaw)
					await get_tree().process_frame
					await get_tree().process_frame
					for scale_by in [1.0, SecurityLooks.TWO_BAG_SCALE]:
						pack.global_transform = _worn(body, pack, scale_by)
						var got: Array = WornBackGap.gap(body, pack)
						lo = minf(lo, got[0])
						hi = maxf(hi, got[0])
						fewest = mini(fewest, got[2])
						off_back = maxf(off_back, FloatCheck.back_gap(body, pack))
						measured += 1
					remove_child(body)
		print(
			(
				(
					"body %d %s: panel gap %.3f..%.3f m (0..%.2f), fewest back points in"
					+ " outline %d, FLOAT check off the back %.3f m (0)"
				)
				% [b, PassengerLooks.BODIES[b], lo, hi, WornBackGap.WORN_GAP_M, fewest, off_back]
			)
		)
		assert_float(off_back).is_equal(0.0)
		assert_float(hi).is_less_equal(WornBackGap.WORN_GAP_M)
		assert_float(lo).is_greater_equal(0.0)
		assert_int(fewest).is_greater(20)
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
