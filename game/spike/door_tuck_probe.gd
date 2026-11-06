extends "res://spike/roller_trail_probe.gd"
## Door jamb probe of pulled rollers (board cd4ff4e0, user ruling a-guest-
## pulling-a-roller-through-a-doorway-tucks-it-in-line). It is
## roller_trail_probe.gd (same worlds, guests, seeds and tallies) with:
##   JAMB_DEEP: the JAMB wall hit frames (roller_trail_probe's class) as deep
##     as BAR_DEPTH_M or deeper, counted and the first TOP_DEEP printed. The
##     bar is 0 on two seeds.
##   TUCK: the pulled frames drawn with the roller tucked in line behind
##     (RollerPull.tuck_weight() above 0), and the SHIN and HEEL frames among
##     the settled ones (roller_trail_probe's SHIN calls any axle nearer the
##     centre line than TRAIL_SIDE_MIN_M a shin hit, so a tucked frame is one
##     by that measure; the windowed leg check below is the real test).
##   LEGS_REAL (windowed only; a headless skeleton is not posed): on every
##     LEG_EVERY_TUCKED-th settled tucked frame and every LEG_EVERY-th untucked one,
##     the body points (CarryContact, gripping hand left out) inside the
##     roller's meshes, rods included, that belong to a leg bone (Quad, Shin,
##     Foot), and the least gap from the rods (the grip bar to Pull_Reach's
##     base) to each leg bone's segment.
## In a windowed run the plates are DoorTuckStrip's (a guest crossing a one-cell
## doorway), not PullSwapStrip's. Same run line as roller_trail_probe.gd with
## res://spike/door_tuck_probe.gd.

const DoorTuckStrip := preload("res://spike/door_tuck_strip.gd")
const TOP_DEEP := 12
const LEG_EVERY := 32
const LEG_EVERY_TUCKED := 4
const LEG_BONES: Array[String] = ["Quad", "Shin", "Foot"]

var _deep := 0
var _tuck := {
	"pulled": 0,
	"settled": 0,
	"shin": 0,
	"heel": 0,
	"legs_tucked": 0,
	"legs_tucked_hit": 0,
	"legs_other": 0,
	"legs_other_hit": 0,
	"gap_tucked": INF,
	"gap_other": INF,
	"seen": 0,
}


func _initialize() -> void:
	super._initialize()
	if not _headless:
		_strip = DoorTuckStrip.new()


func _classify(
	world: String, p: Passenger, body: Node3D, bag: Node3D, state: Dictionary, found: Dictionary
) -> void:
	var before := int(_cls["JAMB"]["frames"])
	var other := int(_cls["OTHER"]["frames"])
	super._classify(world, p, body, bag, state, found)
	var w := RollerPull.tuck_weight(state, _clock.tick + _clock.alpha)
	if int(_cls["OTHER"]["frames"]) > other:
		# Does the tuck have a part in the OTHER class (the west wall by (10,117))?
		_tuck["other_tucked"] = int(_tuck.get("other_tucked", 0)) + int(w > 0.0)
		if int(_cls["OTHER"]["frames"]) <= TOP_DEEP:
			var seen := [world, p.id, _clock.tick, found["mesh"]["name"], p.at, w, _stage(p)]
			print("OTHER_AT %s id=%d tick=%d %s guest %s tuck=%.2f %s" % seen)
	var jamb := int(_cls["JAMB"]["frames"])
	if jamb == before:
		return
	_deep += int(float(found["depth"]) >= BAR_DEPTH_M)
	if jamb <= TOP_DEEP:
		var frame := Transform3D(Basis(Vector3.UP, body.rotation.y), body.global_position)
		var axle := frame.affine_inverse() * (bag.global_transform * CarryOnProps.ROLLER_AXLE)
		var at := [
			world,
			p.id,
			_clock.tick,
			found["mesh"]["name"],
			p.at.x,
			p.at.y,
			float(found["depth"]),
			RollerPull.tuck_weight(state, _clock.tick + _clock.alpha),
			axle.x,
			axle.z,
			_moving(p, bag),
			_stage(p),
		]
		print(
			(
				(
					"JAMB_AT %s id=%d tick=%d %s guest (%d,%d) depth=%.3f tuck=%.2f axle x=%.3f "
					+ "z=%.3f moving=%s %s"
				)
				% at
			)
		)


func _check_axle(p: Passenger, body: Node3D, bag: Node3D, state: Dictionary) -> void:
	var shin := int(_axles["shin"])
	var heel := int(_axles["heel"])
	var settled := int(_axles["settled"])
	super._check_axle(p, body, bag, state)
	var tucked := RollerPull.tuck_weight(state, _clock.tick + _clock.alpha) > 0.0
	_tuck["pulled"] += int(tucked)
	if int(_axles["settled"]) == settled:
		return
	if tucked:
		_tuck["settled"] += 1
		_tuck["shin"] += int(_axles["shin"]) - shin
		_tuck["heel"] += int(_axles["heel"]) - heel
	var count := "seen_tucked" if tucked else "seen"
	_tuck[count] = int(_tuck.get(count, 0)) + 1
	var every := LEG_EVERY_TUCKED if tucked else LEG_EVERY
	if not _headless and int(_tuck[count]) % every == 0:
		_legs(p, body, bag, tucked)
	if not _tuck.has("door_check") and p.at == Vector2i(20, 112):
		# The door strip's doorway test, headless too (the strip runs windowed).
		_tuck["door_check"] = DoorTuckStrip.new()._door_near(_main, body.global_position)
		print("DOOR_CHECK id=%d at %s: doorway %s" % [p.id, p.at, _tuck["door_check"]])


## LEGS_REAL on one settled frame (see the header).
func _legs(p: Passenger, body: Node3D, bag: Node3D, tucked: bool) -> void:
	var key := "tucked" if tucked else "other"
	var props := _views.carry_on_props()
	var found := CarryChecks.contact_bones(body, CarryChecks.gripping(_sim, p, props), bag)
	var hit := 0
	for name: String in found:
		for bone in LEG_BONES:
			if name.begins_with(bone + "."):
				hit += int(found[name])
	_tuck["legs_" + key] += 1
	_tuck["legs_%s_hit" % key] += int(hit > 0)
	var top := bag.find_child("Pull_Top", true, false) as Node3D
	var reach := bag.find_child("Pull_Reach", true, false) as Node3D
	var skeleton := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	if top == null or reach == null:
		return
	var bar := top.global_transform * Vector3(0.0, 0.0, CarryOnProps.ROLLER_GRIP_PAST_TOP_M)
	var base := reach.global_position
	for side in [".R", ".L"]:
		for k in 2:
			var a := _bone_at(skeleton, LEG_BONES[k] + side)
			var b := _bone_at(skeleton, LEG_BONES[k + 1] + side)
			var gap := _segments_gap(bar, base, a, b)
			_tuck["gap_" + key] = minf(float(_tuck["gap_" + key]), gap)
	if hit > 0 and int(_tuck["legs_%s_hit" % key]) <= TOP_DEEP:
		print("LEGS_AT id=%d tick=%d %s %s" % [p.id, _clock.tick, key, found])


func _bone_at(skeleton: Skeleton3D, name: String) -> Vector3:
	return (
		skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin
	)


## The least distance between segments a0-a1 and b0-b1 (sampled, 1 cm).
static func _segments_gap(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> float:
	var least := INF
	var n := maxi(2, ceili(a0.distance_to(a1) / 0.01))
	for i in n + 1:
		var at := a0.lerp(a1, float(i) / n)
		least = minf(least, at.distance_to(Geometry3D.get_closest_point_to_segment(at, b0, b1)))
	return least


func _print_classes() -> void:
	super._print_classes()
	print("JAMB_DEEP seed %d: %d JAMB frames %.2f m or deeper" % [_seed, _deep, BAR_DEPTH_M])
	var share := 100.0 * int(_tuck["pulled"]) / maxf(float(_all["pull"]), 1.0)
	var tuck_text := "TUCK_SHARE seed %d: TUCK_SIDE_M %.2f, %d of %d pulled frames tucked (%.1f%%)"
	print(tuck_text % [_seed, RollerPull.TUCK_SIDE_M, _tuck["pulled"], _all["pull"], share])
	print("OTHER_TUCKED seed %d: %d OTHER frames tucked" % [_seed, _tuck.get("other_tucked", 0)])
	print(
		(
			"TUCK seed %d: %d pulled frames tucked, %d settled, SHIN %d, HEEL %d among them"
			% [_seed, _tuck["pulled"], _tuck["settled"], _tuck["shin"], _tuck["heel"]]
		)
	)
	if not _headless:
		print(
			(
				(
					"LEGS_REAL seed %d: tucked %d looks, %d with leg points in the roller, "
					+ "least rod-to-leg-bone gap %.3f m; untucked %d looks, %d, gap %.3f m"
				)
				% [
					_seed,
					_tuck["legs_tucked"],
					_tuck["legs_tucked_hit"],
					_tuck["gap_tucked"],
					_tuck["legs_other"],
					_tuck["legs_other_hit"],
					_tuck["gap_other"],
				]
			)
		)
