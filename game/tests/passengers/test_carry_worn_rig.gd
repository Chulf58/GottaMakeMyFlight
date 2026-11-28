class_name TestCarryWornRig
extends GdUnitTestSuite
## A worn shoulder tote placed by CarryPlace.carry_transform() on the drawn
## characters (male and female, idle and walk clips, the carry rig and its
## CarryStoop running): standing upright it hangs exactly where it hangs on
## main (strap bar STRAP_OUT_M out from the centre line, upright), at every
## sampled moment of each clip; with the body stooping to its other side's low
## target (a bag on the floor ahead, as the board item a-shoulder-tote-floats-
## 0-39-m-from-the-hand-at-the-end-of-a found it) its drawn strap bar stays
## within the FLOAT check's 0.2 m of the shoulder joint (worn). Uses only what
## main has too, so it runs against main.

const CHARACTERS: Array[String] = [
	"res://assets/people/tcp_male_character_01.glb",
	"res://assets/people/tcp_female_character_01.glb",
]
const CLIPS: Array[String] = ["idle", "walk"]
const SAMPLES := 4
## The FLOAT check's bound for a worn tote (carry_float_check.gd worn_gap()).
const WORN_M := 0.2
## The stooping hand's target, in the body's frame: low ahead on the right.
const LOW_RIGHT := Vector3(-0.3, 0.15, 0.45)

var _props: CarryOnProps


func before_test() -> void:
	_props = auto_free(CarryOnProps.new())
	add_child(_props)


## Old fixed hang prior to board 722abedf: bar hardcoded at STRAP_OUT_M = 0.32 m
## regardless of shoulder bone X (causing narrow female skeletons and stoops to float).
static func _old_fixed_hang(joint: Vector3, side: int, strap_base: Vector3) -> Transform3D:
	var out := Vector3.LEFT if side == 0 else Vector3.RIGHT
	var bar := out * 0.32 + Vector3.BACK * joint.z
	bar.y = joint.y + 0.06
	var basis := Basis(out.cross(Vector3.UP), out, Vector3.UP)
	return Transform3D(basis, bar - basis * (strap_base + Vector3(0.0, 0.0, CarryOnProps.STRAP_M)))


## A character at the origin facing +z, `clip` playing on from `at` seconds.
func _body(path: String, clip: String, at: float) -> Node3D:
	var body: Node3D = auto_free((load(path) as PackedScene).instantiate())
	add_child(body)
	var player := body.get_node("AnimationPlayer") as AnimationPlayer
	player.play(clip)
	player.seek(fmod(at, player.current_animation_length), true)
	return body


## [the drawn tote's transform as CarryOnProps places it (bag 1, the left
## shoulder), its strap bar (world), the left Arm bone (world)].
func _placed(body: Node3D, tote: Node3D) -> Array:
	var held := {
		"scale": 1.0,
		"bags":
		[
			{"node": tote, "kind": SecurityLooks.Kind.SHOULDER},
			{
				"node": tote,
				"kind": SecurityLooks.Kind.SHOULDER,
				"carry": SecurityLooks.Carry.SHOULDER
			},
		],
	}
	var reach := [CarryOnProps.REACH_BUILT_M]
	var xf := CarryPlace.carry_transform(_props, held, body, 1, reach)
	_props._set_reach(tote, SecurityLooks.Kind.SHOULDER, reach[0])
	var top := tote.find_child("Strap_Top", true, false) as Node3D
	var joint: Vector3 = (_props._rig(body)["shoulders"][1] as Node3D).global_position
	return [xf, xf * CarryOnProps._in_piece(top, tote).origin, joint]


func test_a_worn_tote_hangs_as_on_main_upright_and_on_the_shoulder_stooping() -> void:
	var tote: Node3D = auto_free(
		InteriorKit.instantiate(SecurityLooks.KIND_PIECES[SecurityLooks.Kind.SHOULDER])
	)
	var base := CarryOnProps._in_piece(tote.find_child("Strap_Reach", true, false), tote).origin
	var upright := 0
	var stooped := 0
	for path in CHARACTERS:
		for clip in CLIPS:
			for n in SAMPLES:
				var body := _body(path, clip, n * 0.29)
				var rig := _props._rig(body)
				await get_tree().process_frame
				await get_tree().process_frame
				var drawn := _placed(body, tote)
				var joint_upright: Vector3 = drawn[2]
				var top_upright: Vector3 = drawn[1]
				assert_float(top_upright.distance_to(joint_upright)).is_less_equal(0.09)
				var old_top := (
					_old_fixed_hang(joint_upright, 1, base)
					* (base + Vector3(0.0, 0.0, CarryOnProps.STRAP_M))
				)
				if path.contains("female"):
					assert_float(old_top.distance_to(joint_upright)).is_greater(0.10)
				upright += 1
				if n > 0:
					continue
				# Stooping to the right hand's low target, the left joint drawn in.
				var stoop: CarryStoop = rig["stoop"]
				stoop.targets.assign([body.global_transform * LOW_RIGHT])
				stoop.sides.assign([0])
				stoop.weights.assign([1.0])
				stoop.keeps.assign([1.0])
				stoop.drops.assign([CarryStoop.HIPS_ALL])
				await get_tree().process_frame
				await get_tree().process_frame
				var leant := _placed(body, tote)
				var joint: Vector3 = leant[2]
				var gap := maxf(0.0, (leant[1] as Vector3).distance_to(joint) - WORN_M)
				var main_top := (
					_old_fixed_hang(joint, 1, base)
					* (base + Vector3(0.0, 0.0, CarryOnProps.STRAP_M))
				)
				var main_gap := maxf(0.0, main_top.distance_to(joint) - WORN_M)
				print(
					(
						"%s %s stoop %.2f: left joint %.3f out, worn gap %.3f (old 0.32m placement %.3f)"
						% [path.get_file(), clip, stoop.drawn, joint.x, gap, main_gap]
					)
				)
				assert_float(stoop.drawn).is_greater(0.2)
				assert_float(main_gap).is_greater(0.0)
				assert_float(gap).is_equal(0.0)
				stooped += 1
	assert_int(upright).is_equal(CHARACTERS.size() * CLIPS.size() * SAMPLES)
	assert_int(stooped).is_equal(CHARACTERS.size() * CLIPS.size())
