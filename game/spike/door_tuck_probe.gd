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
##   LEAF (board babc77e0, user ruling open-sliding-door-leaves-count-as-
##     obstacles-for-a-pulled-rol): on every pulled frame, the parts of the
##     roller (its body, its rods, its grip bar) and, windowed, the pulling
##     hand that meet an open door leaf. The leaves are the Door_Leaf meshes of
##     the door objects' own nodes (BuildView's, cut away or not), not
##     PullSide's boxes, so the count does not lean on the code it checks. The
##     control: leaves found and pulled frames with a leaf within LEAF_NEAR_M,
##     both above 0. leaf_meshes() and count_leaves() are shared with
##     roller_park_walls_probe.gd.
## In a windowed run the plates are DoorTuckStrip's (a guest crossing a one-cell
## doorway), not PullSwapStrip's. Same run line as roller_trail_probe.gd with
## res://spike/door_tuck_probe.gd.

const DoorTuckStrip := preload("res://spike/door_tuck_strip.gd")
## A leaf this near the roller's axle makes the frame one that could touch it.
const LEAF_NEAR_M := 1.5
## Half size of the pulling hand round its grip point (windowed only).
const HAND_HALF := Vector3(0.04, 0.05, 0.04)
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
var _leaf := new_leaf_tally()
var _leaves: Array[MeshInstance3D] = []


func _initialize() -> void:
	super._initialize()
	if not _headless:
		_strip = DoorTuckStrip.new()


func _collect_walls(world: String) -> void:
	super._collect_walls(world)
	_leaves = leaf_meshes(_build_view, _mode.grid, world)
	_leaf["leaves"] += _leaves.size()


## A fresh LEAF tally.
static func new_leaf_tally() -> Dictionary:
	var out := {"leaves": 0, "frames": 0, "near": 0, "touch": 0, "deep": 0.0}
	for part in ["bag", "rods", "bar", "hand"]:
		out[part] = 0
	return out


## The open door leaves `view` draws on `grid`: the Door_Leaf meshes of every
## door object's node, drawn or cut away. Door walls (a multimesh) are counted
## and printed, not measured: the probe worlds have none.
static func leaf_meshes(view: BuildView, grid: BuildGrid, world: String) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var doors := 0
	for oid in grid.object_ids():
		var node := view.object_node(oid)
		if node == null or not BuildCatalog.is_door(grid.get_object(oid)["def"]):
			continue
		doors += 1
		for mi in node.find_children("Door_Leaf*", "MeshInstance3D", true, false):
			out.append(mi as MeshInstance3D)
	var walls := 0
	for edge in WallCutaway.wall_edges(grid):
		walls += int(grid.wall_kind(Vector2i(edge.x, edge.y), edge.z) == BuildGrid.WallKind.DOOR)
	print("LEAVES %s door objects %d, leaves %d, door walls %d" % [world, doors, out.size(), walls])
	return out


## Books pulled roller `bag` (guest `p`) against `leaves` in `tally`
## (new_leaf_tally()): the roller's meshes, by part (under Pull_Top the grip
## bar, under Pull_Reach the rods, else the bag), and with `hand_at` finite a
## HAND_HALF box there, each tested against every leaf's box. Prints the first
## TOP_DEEP touching frames, with the guest's body at `walker` (when finite)
## in the leaf's frame, so its distance from the door's axis can be read.
static func count_leaves(
	tally: Dictionary,
	leaves: Array[MeshInstance3D],
	p: Passenger,
	bag: Node3D,
	hand_at: Vector3,
	walker := Vector3.INF,
) -> void:
	tally["frames"] += 1
	var axle := bag.global_transform * CarryOnProps.ROLLER_AXLE
	var near: Array[MeshInstance3D] = []
	for leaf in leaves:
		if leaf.global_position.distance_to(axle) < LEAF_NEAR_M:
			near.append(leaf)
	if near.is_empty():
		return
	tally["near"] += 1
	var top := bag.find_child("Pull_Top", true, false)
	var reach := bag.find_child("Pull_Reach", true, false)
	var parts := []
	for mi: MeshInstance3D in bag.find_children("*", "MeshInstance3D", true, false):
		var part := "bag"
		if top != null and (top == mi or top.is_ancestor_of(mi)):
			part = "bar"
		elif reach != null and (reach == mi or reach.is_ancestor_of(mi)):
			part = "rods"
		parts.append([part, _obb(mi.global_transform, mi.get_aabb())])
	if hand_at.is_finite():
		var box := AABB(-HAND_HALF, HAND_HALF * 2.0)
		parts.append(["hand", _obb(Transform3D(Basis.IDENTITY, hand_at), box)])
	var hit := {}
	var touched: MeshInstance3D = null
	for leaf in near:
		var leaf_box := _obb(leaf.global_transform, leaf.get_aabb())
		for entry: Array in parts:
			var depth := _sat(entry[1], leaf_box)
			if depth > 0.0:
				hit[entry[0]] = maxf(float(hit.get(entry[0], 0.0)), depth)
				touched = leaf
	if hit.is_empty():
		return
	tally["touch"] += 1
	for part: String in hit:
		tally[part] += 1
		tally["deep"] = maxf(float(tally["deep"]), float(hit[part]))
	if int(tally["touch"]) <= TOP_DEEP:
		var stage: String = Passenger.Stage.keys()[p.stage]
		# In the touched leaf's frame (x along the wall, z out of it, its middle 0).
		var inv := touched.global_transform.affine_inverse()
		var bar := inv * (top as Node3D).global_position if top != null else Vector3.INF
		var walk := inv * walker if walker.is_finite() else Vector3.INF
		var line := [p.id, p.at.x, p.at.y, stage, hit, inv * axle, bar, walk]
		print("LEAF_AT id=%d cell (%d,%d) %s %s; leaf frame: axle %s bar %s walker %s" % line)


## The LEAF line of `tally` for seed `seed`; the hand is measured windowed only.
static func print_leaves(tally: Dictionary, seed: int, headless: bool) -> void:
	var text := (
		"LEAF seed %d: leaves %d (control, above 0); %d pulled frames, %d with a leaf within"
		+ " %.1f m (control, above 0), %d touching a leaf: bag %d rods %d bar %d hand %s;"
		+ " deepest %.3f m"
	)
	var hand: Variant = "n/a headless" if headless else tally["hand"]
	var near := [tally["near"], LEAF_NEAR_M, tally["touch"], tally["bag"], tally["rods"]]
	print(
		(
			text
			% (
				[seed, tally["leaves"], tally["frames"]]
				+ near
				+ [tally["bar"], hand, tally["deep"]]
			)
		)
	)


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
	var grip := Vector3.INF
	if not _headless:
		grip = _views.carry_on_props().grip_of(body, CarryLead.hand_of(int(state.get("place", 0))))
	count_leaves(_leaf, _leaves, p, bag, grip, body.global_position)
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
	if RollerPull.tuck_weight(state, _clock.tick + _clock.alpha) >= 0.99:
		_asym(p, body, bag, state)
	if not _tuck.has("door_check") and p.at == Vector2i(20, 112):
		# The door strip's doorway test, headless too (the strip runs windowed).
		_tuck["door_check"] = DoorTuckStrip.new()._door_near(_main, body.global_position)
		print("DOOR_CHECK id=%d at %s: doorway %s" % [p.id, p.at, _tuck["door_check"]])


## ASYM: a fully tucked settled frame in the body's frame, mirrored so the
## pulling hand's side is +x for both hands (x out, y up, z ahead): the axle,
## the grip, the bar (rod top), the rod base (Pull_Reach), the pulling side's
## and the other side's Quad, Shin and Foot, and the least gap from the rods
## to the pulling side's thigh and shin segments. Summed per hand.
func _asym(p: Passenger, body: Node3D, bag: Node3D, state: Dictionary) -> void:
	var hand := CarryLead.hand_of(int(state.get("place", 0)))
	var frame := Transform3D(Basis(Vector3.UP, body.rotation.y), body.global_position)
	var to := frame.affine_inverse()
	var flip := Vector3(-1.0 if hand == 0 else 1.0, 1.0, 1.0)
	var top := bag.find_child("Pull_Top", true, false) as Node3D
	var reach := bag.find_child("Pull_Reach", true, false) as Node3D
	var skeleton := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var own := ".R" if hand == 0 else ".L"
	var far := ".L" if hand == 0 else ".R"
	var bar := top.global_transform * Vector3(0.0, 0.0, CarryOnProps.ROLLER_GRIP_PAST_TOP_M)
	var pts := {
		"axle": bag.global_transform * CarryOnProps.ROLLER_AXLE,
		"grip": _views.carry_on_props().grip_of(body, hand),
		"bar": bar,
		"rod_base": reach.global_position,
		"spine_01": (_views.carry_on_props()._rig(body)["pivot"] as Node3D).global_position,
	}
	for bone in LEG_BONES:
		pts[bone + "_own"] = _bone_at(skeleton, bone + own)
		pts[bone + "_far"] = _bone_at(skeleton, bone + far)
	var gap := minf(
		_segments_gap(bar, pts["rod_base"], pts["Quad_own"], pts["Shin_own"]),
		_segments_gap(bar, pts["rod_base"], pts["Shin_own"], pts["Foot_own"])
	)
	var key := "asym%d" % hand
	var acc: Dictionary = _tuck.get_or_add(key, {"n": 0, "gap_min": INF, "gap_sum": 0.0})
	acc["n"] += 1
	acc["gap_min"] = minf(float(acc["gap_min"]), gap)
	acc["gap_sum"] += gap
	for name: String in pts:
		var local: Vector3 = (to * (pts[name] as Vector3)) * flip
		acc[name] = (acc.get(name, Vector3.ZERO) as Vector3) + local
		if name == "Foot_own":
			acc["foot_z_min"] = minf(float(acc.get("foot_z_min", INF)), local.z)
			acc["foot_z_max"] = maxf(float(acc.get("foot_z_max", -INF)), local.z)
	if int(acc["n"]) == 1:
		print("ASYM_FIRST hand=%d id=%d tick=%d gap=%.3f" % [hand, p.id, _clock.tick, gap])


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
	print_leaves(_leaf, _seed, _headless)
	if int(_leaf["leaves"]) <= 0 or int(_leaf["near"]) <= 0:
		_invalid("no door leaf was found, or no pulled roller came near one")
	print("JAMB_DEEP seed %d: %d JAMB frames %.2f m or deeper" % [_seed, _deep, BAR_DEPTH_M])
	var share := 100.0 * int(_tuck["pulled"]) / maxf(float(_all["pull"]), 1.0)
	var tuck_text := "TUCK_SHARE seed %d: TUCK_SIDE_M %.2f, %d of %d pulled frames tucked (%.1f%%)"
	print(tuck_text % [_seed, RollerPull.TUCK_SIDE_M, _tuck["pulled"], _all["pull"], share])
	print("OTHER_TUCKED seed %d: %d OTHER frames tucked" % [_seed, _tuck.get("other_tucked", 0)])
	for hand in 2:
		var acc: Dictionary = _tuck.get("asym%d" % hand, {})
		if acc.is_empty():
			print("ASYM seed %d hand %d: no fully tucked settled frame" % [_seed, hand])
			continue
		var n := float(acc["n"])
		var head := "ASYM seed %d hand %d: %d frames, rod-to-own-leg gap least %.3f mean %.3f"
		print(head % [_seed, hand, acc["n"], acc["gap_min"], float(acc["gap_sum"]) / n])
		print("  own foot z %.3f to %.3f" % [acc["foot_z_min"], acc["foot_z_max"]])
		for name: String in acc:
			if acc[name] is Vector3:
				print("  mean %s (out, up, ahead) %s" % [name, (acc[name] as Vector3) / n])
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
