class_name ActivityPoses
extends RefCounted
## How a passenger visiting an activity or rest room is drawn (decision
## activity-poses-sit-on-the-lounge-sofa-recline-in-the-nap-pod): on the lounge
## sofa it sits on the piece's seat mount with the sit clips, in the nap pod it
## sits the same way and then leans back against the cushion with the head
## tilted (PodRecline), and in the shower it steps into the cubicle and washes
## there (the looping "shower" clip) under foam and steam (ShowerFoam), its
## icons still showing. Once the lather is fully up its clothes come off: the
## body draws skin where its clothes and shoes were (bare_mesh) until the
## rinse starts. The play area keeps the browse pose: standing in front of the
## piece, facing it. Carry-on bags go down on the floor beside the sofa or pod
## seat while the visitor is on it, and outside the shower door for its stay
## (bags_down(), SecurityLooks.activity_floor()); a showering visitor with bags
## stands at the door to set them down before it steps in and to pick them up
## after it steps out (DOOR_IN_TICKS, DOOR_OUT_TICKS).
##
## The sim runs every activity visit as one SHOP_BROWSE stage at the piece's
## slot cell (ShopLayout), so this view-only helper reads the pose from the
## stage's own clock: it sits down over the first SIT_DOWN_TICKS of the stage
## and stands up over the last STAND_UP_TICKS before the stay ends (the type's
## dwell, or the visit's deadline when that comes first). Everything is worked
## out from the sim each tick, so a load or a clock that went back draws the
## pose for the loaded tick with nothing to reset (anti-pattern
## a-per-id-view-record-holding-a-sim-tick-must-start-over-on-l).
## PassengerViews moves its drawn step toward offset() by at most a walking
## step a tick, so a stay cut short (the deadline re-forecast closer) or a
## piece removed mid-stay eases the body back to the slot cell over a few
## ticks; only the clip switches at once.

enum Kind { NONE, SEAT, RECLINE, SHOWER }

## Piece -> how its visitor is drawn.
const KINDS := {
	&"lounge_sofa": Kind.SEAT,
	&"lounge_armchair": Kind.SEAT,
	&"nap_pod": Kind.RECLINE,
	&"shower_cubicle": Kind.SHOWER,
}
## Piece -> where its visitor's feet go, by slot index, in the piece's own
## frame (metres; x across, y along its front, +y out of the front). The seat
## roots are the .glb's Mount_SitRoot nodes (build_activities_kit.py and
## build_services_kit.py, pinned by test_activity_poses against the imported
## files); the shower spot is the middle of the cubicle's tray.
const ROOTS := {
	&"lounge_sofa": [Vector2(-0.5, 0.45), Vector2(0.5, 0.45)],
	&"lounge_armchair": [Vector2(0.0, 0.45)],
	&"nap_pod": [Vector2(0.0, 0.45)],
	&"shower_cubicle": [Vector2(0.0, 0.0)],
}
## The shower tray's top: a showering passenger stands on it.
const SHOWER_TRAY_M := 0.10
## Ticks of the step from the slot cell onto the seat or into the shower, at
## the start of the stay, and back out at its end (as CafeSim.SHUFFLE_TICKS).
const SHUFFLE_TICKS := 12
## Ticks the nap pod's lean back takes once seated, and the foam's build-up
## once in the shower (and the same again at the end).
const EASE_TICKS := 20
## A showering visitor with bags stands this many ticks at the cubicle door,
## facing it, before it steps in: it sets its bags down outside the door then
## (SecurityLooks), a roller's park included (RollerPark.TICKS_DOWN, 13).
const DOOR_IN_TICKS := 14
## And this many after it has stepped out, facing the door again, picking its
## bags up: the walk off starts as a roller's pick-up is as far on as a gate
## sitter's is when it walks off (RollerPark.UP_LEAD_TICKS).
const DOOR_OUT_TICKS := 10
## A sofa or nap pod visitor with a roller stands this many ticks at its slot
## cell, facing out of the piece, before it steps onto the seat and sits down:
## it sets its bags down standing then (user ruling sitting-down-with-a-roller-
## set-the-bag-down-standing-then-sit, board 76cb23c0). The roller's park
## (RollerPark.TICKS_DOWN, 13) is stamped on the stay's first tick and the hand
## lets go a tick after it ends (SitHold.LET_GO_TICKS). Set down from the seat
## at SHUFFLE_TICKS, the park ran into the sit_idle at 24 ticks, the stoop on a
## seated body.
const SEAT_DOOR_TICKS := 15
## Below this height (metres, the body's rest pose) a showering body's parts
## are its shoes, which come off with the clothes: where the lather's legs
## start (ShowerFoam.PARTS).
const FEET_M := 0.14
## Bones whose vertices are bare skin on every body: the hands.
const SKIN_BONES: Array[String] = ["Hand", "Finger", "Thumb"]

## Body index (PassengerLooks.BODIES) -> its mesh with clothes and shoes off.
static var _bare := {}


## How `p` is drawn now: NONE unless it is staying at a sofa, armchair, nap
## pod or shower on an activity visit.
static func kind(sim: PassengerSim, p: Passenger) -> Kind:
	var piece := _piece(sim, p)
	if piece.is_empty():
		return Kind.NONE
	return KINDS.get(piece["def"], Kind.NONE)


## The seat pose of a sofa or nap pod visitor now: sitting down over the first
## SIT_DOWN_TICKS of the stay, standing up over its last STAND_UP_TICKS, and
## seated between. UPRIGHT for every other passenger, a showering one included.
static func pose(sim: PassengerSim, p: Passenger) -> StageKinds.Pose:
	var k := kind(sim, p)
	if k != Kind.SEAT and k != Kind.RECLINE:
		return StageKinds.Pose.UPRIGHT
	if _left(sim, p) < PassengerSim.STAND_UP_TICKS:
		return StageKinds.Pose.STANDING_UP
	var sat := sim.tick - p.stage_tick - seat_door(sim, p)
	if sat < 0:
		return StageKinds.Pose.UPRIGHT
	if sat < PassengerSim.SIT_DOWN_TICKS:
		return StageKinds.Pose.SITTING_DOWN
	return StageKinds.Pose.SEATED


## How far (0 to 1) `p` has stepped from its slot cell onto its seat or into
## the shower: up over the first SHUFFLE_TICKS of the stay, down over the last
## (at the shower with bags, inside the door pauses: _in_spent, _out_left).
static func share(sim: PassengerSim, p: Passenger) -> float:
	if kind(sim, p) == Kind.NONE:
		return 0.0
	var step_in := _in_spent(sim, p) / float(SHUFFLE_TICKS)
	var step_out := _out_left(sim, p) / float(SHUFFLE_TICKS)
	return clampf(minf(step_in, step_out), 0.0, 1.0)


## The step from the sim's position (the slot cell) to where `p` is drawn: its
## seat root or the shower tray, times share(). Zero for everyone else, and
## for a visitor whose piece an edit removed.
static func offset(sim: PassengerSim, p: Passenger) -> Vector3:
	var piece := _piece(sim, p)
	if piece.is_empty() or not KINDS.has(piece["def"]):
		return Vector3.ZERO
	var spot := spot_of(sim.grid, piece, piece["index"])
	if KINDS[piece["def"]] == Kind.SHOWER:
		spot.y += SHOWER_TRAY_M
	return (spot - sim.world_position(p)) * share(sim, p)


## Where slot `index` of a piece record has its visitor's feet, in world space
## (the piece drawn as BuildView draws it, ROOTS in its frame); the piece's
## centre for a piece with no such slot.
static func spot_of(grid: BuildGrid, record: Dictionary, index: int) -> Vector3:
	var def := BuildCatalog.get_def(record["def"])
	var cells := def.footprint(record["anchor"], record["facing"])
	var frame := BuildView.object_transform(grid, cells, record["facing"])
	var roots: Array = ROOTS.get(record["def"], [])
	var root: Vector2 = roots[index] if index >= 0 and index < roots.size() else Vector2.ZERO
	return frame * Vector3(root.x, 0.0, root.y)


## The grid direction a staying visitor faces: out of the front of its piece
## (sat on the sofa or in the pod, or looking out of the shower door), except
## that a showering one faces into the cubicle while it steps in, and while it
## stands at the door before that and after its step out (DOOR_IN_TICKS,
## DOOR_OUT_TICKS). Zero for everyone else.
static func facing(sim: PassengerSim, p: Passenger) -> Vector2i:
	var piece := _piece(sim, p)
	if piece.is_empty() or not KINDS.has(piece["def"]):
		return Vector2i.ZERO
	var out := TerminalLayout.front_of(piece["facing"])
	var at_door := _in_spent(sim, p) < SHUFFLE_TICKS or _out_left(sim, p) < 0
	if KINDS[piece["def"]] == Kind.SHOWER and at_door:
		return -out
	return out


## Whether the carry-on bags of `p` are down for its stay now (SecurityLooks
## puts them on the floor): on the sofa or in the nap pod from the moment it is
## on the seat (SHUFFLE_TICKS in; with a roller from the stay's start, standing
## at its slot cell, seat_door()) until it steps off (SHUFFLE_TICKS before the
## end), so it sets them down sitting and picks them up as it leaves the seat;
## at the shower from the start of the stay to DOOR_OUT_TICKS before its end,
## so they are set down at the door before the step in, wait outside it and
## are picked up after the step out.
static func bags_down(sim: PassengerSim, p: Passenger) -> bool:
	match kind(sim, p):
		Kind.SHOWER:
			return _left(sim, p) >= DOOR_OUT_TICKS
		Kind.SEAT, Kind.RECLINE:
			var on_seat := _in_spent(sim, p) >= SHUFFLE_TICKS or seat_door(sim, p) > 0
			return on_seat and _left(sim, p) >= SHUFFLE_TICKS
	return false


## The frame of the stay of `p` in the world: on its slot's seat root (or the
## middle of the shower's floor), turned to face out of the piece (+z out of
## its front, +x on the left of one facing out). The identity for a passenger
## kind() draws as NONE.
static func stay_frame(sim: PassengerSim, p: Passenger) -> Transform3D:
	var piece := _piece(sim, p)
	if piece.is_empty() or not KINDS.has(piece["def"]):
		return Transform3D.IDENTITY
	var out := TerminalLayout.front_of(piece["facing"])
	var at := spot_of(sim.grid, piece, piece["index"])
	return Transform3D(Basis(Vector3.UP, atan2(out.x, out.y)), at)


## How far (0 to 1) a nap pod visitor leans back now: in over EASE_TICKS once
## it has sat down, out over EASE_TICKS before it stands up.
static func recline(sim: PassengerSim, p: Passenger) -> float:
	if kind(sim, p) != Kind.RECLINE:
		return 0.0
	var seated := sim.tick - p.stage_tick - seat_door(sim, p) - PassengerSim.SIT_DOWN_TICKS
	var before_up := _left(sim, p) - PassengerSim.STAND_UP_TICKS
	return smoothstep(0.0, 1.0, minf(seated, before_up) / float(EASE_TICKS))


## Ticks `p` has spent in its current sit_down or stand_up clip: from the
## stay's start or the start of its stand-up on an activity visit, from the
## stage's start on a gate, cafe or toilet seat. Never below 0.
static func clip_ticks(sim: PassengerSim, p: Passenger) -> int:
	var k := kind(sim, p)
	if k == Kind.SEAT or k == Kind.RECLINE:
		if pose(sim, p) == StageKinds.Pose.STANDING_UP:
			return maxi(PassengerSim.STAND_UP_TICKS - 1 - _left(sim, p), 0)
		return maxi(sim.tick - p.stage_tick - seat_door(sim, p), 0)
	return maxi(sim.tick - p.stage_tick, 0)


## Puts the nap pod lean and the shower lather on a passenger's node, each only
## while it is above 0: a PodRecline first on the skeleton (so it runs after
## the animation and before the carry modifiers) and a ShowerFoam child, made
## when needed and freed after, so a passenger that is neither reclining nor
## showering carries neither and costs nothing. While `undressed`, the body
## draws bare_mesh in place of its own mesh, which is kept in the node's
## "dressed" meta and put back the moment `undressed` is false (step-out,
## release).
static func dress(node: Node3D, lean: float, lather: float, undressed := false) -> void:
	if undressed != node.has_meta(&"dressed"):
		var mi := PassengerLooks.body_mesh(node)
		if undressed:
			node.set_meta(&"dressed", mi.mesh)
			mi.mesh = bare_mesh(node.get_meta(&"body"))
		else:
			mi.mesh = node.get_meta(&"dressed")
			node.remove_meta(&"dressed")
	var recline: PodRecline = node.get_meta(&"recline") if node.has_meta(&"recline") else null
	if lean > 0.0 and recline == null:
		recline = PodRecline.new()
		recline.name = "PodRecline"
		var skeleton := node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		skeleton.add_child(recline)
		skeleton.move_child(recline, 0)
		node.set_meta(&"recline", recline)
	elif lean <= 0.0 and recline != null:
		recline.get_parent().remove_child(recline)
		recline.queue_free()
		node.remove_meta(&"recline")
		recline = null
	if recline != null:
		recline.amount = lean
	var foam := node.get_node_or_null("ShowerFoam") as ShowerFoam
	if lather > 0.0 and foam == null:
		foam = ShowerFoam.new()
		node.add_child(foam)
	elif lather <= 0.0 and foam != null:
		node.remove_child(foam)
		foam.queue_free()
		foam = null
	if foam != null:
		foam.set_amount(lather)


## How much foam (0 to 1) covers a showering visitor now: building up over
## EASE_TICKS as it steps in, rinsed off over EASE_TICKS before it steps out.
static func foam(sim: PassengerSim, p: Passenger) -> float:
	if kind(sim, p) != Kind.SHOWER:
		return 0.0
	var spent := _in_spent(sim, p)
	return smoothstep(0.0, 1.0, minf(spent, _out_left(sim, p)) / float(EASE_TICKS))


## True while a showering visitor's lather is fully up: its clothes are off
## from then until the rinse starts, so the body is never bare outside a full
## lather.
static func bare(sim: PassengerSim, p: Passenger) -> bool:
	return foam(sim, p) >= 1.0


## True while a showering visitor stands in the cubicle between its step in and
## its step out: it plays the looping washing clip then.
static func washing(sim: PassengerSim, p: Passenger) -> bool:
	return kind(sim, p) == Kind.SHOWER and share(sim, p) >= 1.0


## Seconds into the washing clip `p` is now: from the end of its step in.
static func wash_seconds(sim: PassengerSim, p: Passenger) -> float:
	return maxi(_in_spent(sim, p) - SHUFFLE_TICKS, 0) * SimClock.STEP


## Body `body`'s mesh with its clothes and shoes off, made on first use and
## shared by every showering passenger of that body (no passenger's own mesh or
## material is changed). Surface 0 is the body's other parts as imported;
## surface 1 is its clothes' triangles (PassengerLooks.cloth_split) and the
## shoes' (any corner below FEET_M, so a shoe triangle reaching up past the
## line comes off too), every vertex's UV moved to one texel of that body's
## own hand skin (skin_uv), on the same shared atlas material.
static func bare_mesh(body: int) -> Mesh:
	if _bare.has(body):
		return _bare[body]
	var plain := PassengerLooks.plain_mesh(body)
	var arrays := plain.surface_get_arrays(0)
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var other := PackedInt32Array()
	var skin := PackedInt32Array()
	for t in range(0, index.size(), 3):
		var corners := [index[t], index[t + 1], index[t + 2]]
		var off := not colors.is_empty() and colors[corners[0]].r > 0.5
		for v: int in corners:
			off = off or verts[v].y < FEET_M
		var into := skin if off else other
		into.append_array(corners)
	var flags: int = (plain as ArrayMesh).surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var mesh := ArrayMesh.new()
	arrays[Mesh.ARRAY_INDEX] = other
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	uvs.fill(skin_uv(body))
	arrays[Mesh.ARRAY_INDEX] = skin
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	for i in 2:
		mesh.surface_set_material(i, plain.surface_get_material(0))
	_bare[body] = mesh
	return mesh


## The atlas UV of body `body`'s skin: the hand vertex (SKIN_BONES, outside
## the clothes' mark) whose atlas colour is nearest the mean of all of them.
static func skin_uv(body: int) -> Vector2:
	var node := PassengerLooks.SCENES[body].instantiate()
	var skeleton := node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var plain := PassengerLooks.plain_mesh(body)
	var arrays := plain.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / uvs.size()
	var skin_bone := {}
	for b in skeleton.get_bone_count():
		for part in SKIN_BONES:
			if part in skeleton.get_bone_name(b):
				skin_bone[b] = true
	node.free()
	var atlas := atlas_image(plain)
	var hands: Array[Vector2] = []
	var tones: Array[Color] = []
	var mean := Color(0.0, 0.0, 0.0, 0.0)
	for v in uvs.size():
		if not colors.is_empty() and colors[v].r > 0.5:
			continue
		var top := 0
		for k in per:
			if weights[v * per + k] > weights[v * per + top]:
				top = k
		if skin_bone.has(bones[v * per + top]):
			var tone := atlas_colour(atlas, uvs[v])
			hands.append(uvs[v])
			tones.append(tone)
			mean += tone
	if hands.is_empty():
		push_error("ActivityPoses: %s has no hand skin" % PassengerLooks.BODIES[body])
		return uvs[0]
	mean /= float(hands.size())
	var best := 0
	for i in hands.size():
		if _distance(tones[i], mean) < _distance(tones[best], mean):
			best = i
	return hands[best]


## The decompressed atlas image a body mesh's material samples.
static func atlas_image(mesh: Mesh) -> Image:
	var material := mesh.surface_get_material(0) as ShaderMaterial
	var atlas := (material.get_shader_parameter("albedo_texture") as Texture2D).get_image()
	atlas.decompress()
	return atlas


## The colour of `atlas` at UV `uv`, at the nearest texel.
static func atlas_colour(atlas: Image, uv: Vector2) -> Color:
	var size := Vector2i(atlas.get_width(), atlas.get_height())
	return atlas.get_pixelv(Vector2i(uv * Vector2(size)).clamp(Vector2i.ZERO, size - Vector2i.ONE))


static func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## The visited piece's grid record with "index" (the slot index) added, for a
## passenger staying on an activity visit; empty otherwise or once an edit
## removed the piece.
static func _piece(sim: PassengerSim, p: Passenger) -> Dictionary:
	if p.stage != Passenger.Stage.SHOP_BROWSE:
		return {}
	var visit := sim.shops.visit_of(p.id)
	if visit == null:
		return {}
	var type := RoomTypes.get_type(_room_type_id(sim, visit))
	var record := sim.grid.get_object(visit.display)
	if type == null or not type.activity or record.is_empty():
		return {}
	record["index"] = visit.index
	return record


static func _room_type_id(sim: PassengerSim, visit: ShopVisit) -> StringName:
	var room := sim.grid.get_room(visit.room)
	return room.get("type", &"") if not room.is_empty() else &""


## Ticks the stay has left after this one: the stage ends on the tick the
## dwell is reached (ShopSim.step settles it) or on the visit's deadline,
## whichever comes first, so the last tick drawn staying has 0 left.
static func _left(sim: PassengerSim, p: Passenger) -> int:
	var visit := sim.shops.visit_of(p.id)
	var type := RoomTypes.get_type(_room_type_id(sim, visit))
	var end := mini(p.stage_tick + ShopSim.browse_ticks(type), visit.deadline)
	return end - 1 - sim.tick


## Ticks since `p` started its step onto its seat or into the shower: from the
## stay's start, or at the shower with bags from DOOR_IN_TICKS after it
## (negative before that).
static func _in_spent(sim: PassengerSim, p: Passenger) -> int:
	return sim.tick - p.stage_tick - _door(sim, p, DOOR_IN_TICKS) - seat_door(sim, p)


## Ticks left until `p` has stepped off its seat or out of the shower: the
## stay's ticks left (_left), or at the shower with bags DOOR_OUT_TICKS fewer
## (negative after that).
static func _out_left(sim: PassengerSim, p: Passenger) -> int:
	return _left(sim, p) - _door(sim, p, DOOR_OUT_TICKS)


## `ticks` for a showering visitor with bags, which waits at the door to set
## them down or pick them up; 0 for everyone else.
static func _door(sim: PassengerSim, p: Passenger, ticks: int) -> int:
	return ticks if p.carry_on > 0 and kind(sim, p) == Kind.SHOWER else 0


## SEAT_DOOR_TICKS for a sofa or nap pod visitor carrying a roller, which
## stands at its slot cell to set it down before it sits; 0 for everyone else.
static func seat_door(sim: PassengerSim, p: Passenger) -> int:
	var k := kind(sim, p)
	if k != Kind.SEAT and k != Kind.RECLINE:
		return 0
	for i in p.carry_on:
		if SecurityLooks.bag_kind(p, i) == SecurityLooks.Kind.ROLLER:
			return SEAT_DOOR_TICKS
	return 0
