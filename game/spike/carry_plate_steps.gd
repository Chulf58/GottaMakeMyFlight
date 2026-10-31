extends RefCounted
## Plate helpers for basic_scanner_crossing_probe.gd (board item 5ed915b0, the
## probe defects behind the carry self-clip residuals): sight lines that see a
## mesh from either side, a dark-plate guard, the sim clock stepped to a move's
## moment while it stays paused, the move a bag is about to start (its place
## changed in this tick's sync, not drawn yet), and a detail plate of a bag
## close up. Load with preload(); no class_name.

const PlateSight := preload("res://spike/plate_sight.gd")
const CarryContact := preload("res://spike/carry_contact.gd")

## A plate whose sampled pixels are darker than DARK_LEVEL (every channel) over
## more than DARK_SHARE of the frame is a camera inside or against a mesh.
const DARK_LEVEL := 0.06
## A roller laid down from the pull (RollerPark, TICKS_DOWN 13) is plated on
## the bar late in its stand (k 0.3), then one sim tick apart (1/13) from its
## park into its lay down, the frames a game at 3x draws (one tick a frame),
## and after its let go (the crossing probe's lead plates).
const LEAD_MOMENTS_OF := {
	"ROLLER pull>floor":
	[
		[0.29, 0.31],
		[0.375, 0.395],
		[0.45, 0.47],
		[0.53, 0.55],
		[0.605, 0.625],
		[0.685, 0.70],
		[0.86, 0.97],
	],
}
const DARK_SHARE := 0.35
const DARK_STEP := 16
## A detail plate's camera: this far from the bag's middle, on the line from
## the bag to the close plate's camera.
const DETAIL_M := 1.1
## The sides a detail plate tries, turned about the bag from the close plate's
## side, and the sight lines (of five) that must land on the bag first.
const DETAIL_TURNS: Array[float] = [0.0, PI / 3.0, -PI / 3.0, 2.0 * PI / 3.0, -2.0 * PI / 3.0]
const DETAIL_ON := 3
## The most a plate steps the paused clock between two drawn frames (a frame
## of a normal run at 60 fps and speed 1 is a third of a tick).
const STEP_TICKS := 0.34
## A character standing has its shoulder joints about this high over its feet.
const STANDING_SHOULDER_M := 1.4
## Lower than this share of it a body is crouched (crouch_of()); a body this
## high or higher, standing or near it, keeps the camera as it always was.
const CROUCHED := 0.85


## How low `body` is drawn now, for a close plate's camera (its distance and
## aim times this): its shoulder joints' height over its feet as drawn (the
## carry rig's bone attachments, after the stoop) over STANDING_SHOULDER_M, 0.5
## to CROUCHED, else 1 (standing, or with no carry rig). A body crouched to a bag on the floor
## is about 0.6 m shorter, and a camera framing it as if it stood drew it under
## the probes' CLOSE_MIN_PX (crossing probe, roller laid down by a gate chair).
static func crouch_of(body: Node3D) -> float:
	var rig: Dictionary = body.get_meta(&"carry_rig", {})
	if rig.is_empty():
		return 1.0
	var high := -INF
	for joint: Node3D in rig["shoulders"]:
		high = maxf(high, joint.global_position.y)
	var low := (high - body.global_position.y) / STANDING_SHOULDER_M
	return 1.0 if low > CROUCHED else maxf(low, 0.5)


## Every collider under `holder` (PlateSight.colliders) is hit from either
## side, so a camera inside a closed mesh or behind a one-sided wall has that
## mesh between itself and the subject (a ray that starts inside a mesh or
## meets a back face otherwise passes through it).
static func see_both_sides(holder: Node) -> void:
	for node in holder.find_children("*", "CollisionShape3D", true, false):
		var shape := (node as CollisionShape3D).shape as ConcavePolygonShape3D
		if shape != null:
			shape.backface_collision = true


## The share of `img` (sampled every DARK_STEP pixels) darker than DARK_LEVEL.
static func dark_share(img: Image) -> float:
	var dark := 0
	var seen := 0
	for y in range(0, img.get_height(), DARK_STEP):
		for x in range(0, img.get_width(), DARK_STEP):
			var c := img.get_pixel(x, y)
			seen += 1
			dark += int(maxf(c.r, maxf(c.g, c.b)) < DARK_LEVEL)
	return dark / float(maxi(seen, 1))


## Moves the paused sim clock on by `ticks` (a part of a tick allowed); it is
## paused again before anything draws.
static func step_clock(clock: SimClock, ticks: float) -> void:
	if ticks <= 0.0:
		return
	clock.set_paused(false)
	clock.advance(ticks * SimClock.STEP / clock.speed)
	clock.set_paused(true)


## Whether a sight line from `cam` to `at` hits any collider on the way
## (printed with `tag` when it does).
static func blocked(cam: Camera3D, at: Vector3, tag: String) -> bool:
	var space := cam.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(cam.global_position, at))
	if not hit.is_empty():
		print("INFRAME %s bag blocked by %s" % [tag, (hit.collider as Node).get_meta("mesh", "")])
	return not hit.is_empty()


## Steps the paused clock toward the window [lo, hi] of the move of bag `i` of
## passenger `id` (ticks_to), at most STEP_TICKS at a time with a frame drawn
## after each, so every pose on the way is drawn and checked as in a normal
## run (a jump straight to the moment would skip them).
static func step_to(
	tree: SceneTree, clock: SimClock, props: CarryOnProps, id: int, i: int, lo: float, hi: float
) -> void:
	var ticks := CarryLead.ticks_of(props.bag_state(id, i))
	var left := ticks_to(props.transfer_progress(id, i), lo, hi, ticks)
	while left > 0.0:
		var step := minf(left, STEP_TICKS)
		step_clock(clock, step)
		left -= step
		await tree.process_frame
		await RenderingServer.frame_post_draw


## The ticks to step for a move now at `k` to reach the window [lo, hi]: to its
## middle (to 1 for a window at 1), none when it is already in or past it;
## `ticks` the move's length (CarryLead.ticks_of()).
static func ticks_to(k: float, lo: float, hi: float, ticks := CarryOnProps.TRANSFER_TICKS) -> float:
	if k >= lo:
		return 0.0
	var target := 1.0 if lo >= 1.0 else (lo + hi) * 0.5
	return (target - k) * ticks + (0.01 if lo >= 1.0 else 0.0)


## The move bag `i` of passenger `id` starts on its next draw (its place
## changed in this tick's sync and is not stamped yet), named as
## FloatCheck.move_of names a move ("floor>hand.R"), or "" when none is.
static func pending_move(props: CarryOnProps, id: int, i: int) -> String:
	var bag := props.bag_state(id, i)
	if not bag.has("home") or int(bag["home"]) < 0 or bag["home"] == bag.get("place", bag["home"]):
		return ""
	var ends := []
	for end in [[bag["home"], bag.get("carry_placed", bag["carry"])], [bag["place"], bag["carry"]]]:
		var place: int = end[0]
		if place < 0 or place / 4 != SecurityLooks.Home.HAND:
			ends.append(SecurityLooks.Home.keys()[maxi(place, 0) / 4].to_lower())
		else:
			var carry: String = SecurityLooks.Carry.keys()[maxi(end[1], 0)].to_lower()
			ends.append(carry + [".R", ".L"][(place / 2) % 2])
	return "%s>%s" % ends


## The close plate's key of a move named `move` of a bag of `kind` (hands left
## out), as the probe's LEAD_PLATES list them ("CASE floor>hand").
static func lead_key(kind: SecurityLooks.Kind, move: String) -> String:
	return SecurityLooks.Kind.keys()[kind] + " " + move.replace(".R", "").replace(".L", "")


## The probe's MOVE_PLATES kind of a move named `move` of a bag of `kind` by a
## passenger whose repack is done (`repacked`): "roller_lower",
## "repack_pickup_case", or "".
static func move_plate_kind(kind: SecurityLooks.Kind, move: String, repacked: bool) -> String:
	var ends := move.split(">")
	if ends.size() != 2:
		return ""
	var roller := kind == SecurityLooks.Kind.ROLLER
	if roller and ends[0].begins_with("hand") and ends[1].begins_with("pull"):
		return "roller_lower"
	if kind == SecurityLooks.Kind.CASE and ends[0] == "floor" and ends[1].begins_with("hand"):
		return "repack_pickup_case" if repacked else ""
	return ""


## Whether a move named `move` of a bag of `kind` is still to be plated: a
## booth move plate (`move_plates` kinds not in `move_plated`, only `near` a
## booth), else a hand-led move plate (`lead_plates` keys not in
## `lead_plated`, only once `lead_open`).
static func wanted(
	kind: SecurityLooks.Kind,
	move: String,
	repacked: bool,
	near: bool,
	plated: Array[Dictionary],
	lead_open: bool,
	lead_plates: Array[String]
) -> bool:
	if move == "":
		return false
	var plate := move_plate_kind(kind, move, repacked)
	if plate != "" and not plated[0].has(plate) and near:
		return true
	var key := lead_key(kind, move)
	return lead_open and key in lead_plates and not plated[1].has(key)


## One contact sheet of the hand-led move plates (lead_*.png) in `dir`, four
## across, saved there as contact_sheet_lead.png. Moved from the probe.
static func lead_sheet(dir: String) -> void:
	var names: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		if file.begins_with("lead_") and file.ends_with(".png"):
			names.append(file)
	names.sort()
	if names.is_empty():
		return
	var cell := Vector2i(480, 270)
	var sheet := Image.create(
		cell.x * 4, cell.y * ceili(names.size() / 4.0), false, Image.FORMAT_RGB8
	)
	for n in names.size():
		var img := Image.load_from_file(dir.path_join(names[n]))
		img.convert(Image.FORMAT_RGB8)
		img.resize(cell.x, cell.y)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, cell), Vector2i(n % 4, n / 4) * cell)
	sheet.save_png(dir.path_join("contact_sheet_lead.png"))
	print("LEAD_SHEET %s plates=%s" % [dir.path_join("contact_sheet_lead.png"), names])


## A detail plate of `bag`: `cam` DETAIL_M from the bag's middle, or further
## for the whole bag to fit (a roller with its rods out), aimed at it; the
## sight lines go to its biggest mesh (its case: the whole bag's middle can be
## in the air between the rods),
## tried from the side `cam` is on now and then DETAIL_TURNS about the bag;
## saved to `path` from the first side where the bag's drawn bounds project
## inside `frame` (probe._box_in_frame), at least DETAIL_ON of five sight lines
## land on the bag first (its own passenger in front of it counts against it
## here, every mesh seen from either side) and the plate is not dark. `owners`
## are the meshes that can block. Returns whether it was saved; the camera is
## left where it was put.
static func detail_plate(
	probe: SceneTree,
	cam: Camera3D,
	body: Node3D,
	bag: Node3D,
	owners: Array[Node],
	frame: Rect2,
	path: String
) -> bool:
	var box := AABB()
	var core := AABB()
	var first := true
	for mi: MeshInstance3D in bag.find_children("*", "MeshInstance3D", true, false):
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		core = b if b.get_volume() > core.get_volume() else core
		first = false
	var centre := box.get_center()
	var reach := maxf(DETAIL_M, box.size.length() * 0.55 / tan(deg_to_rad(cam.fov) * 0.5))
	var away := cam.global_position - centre
	var tag := path.get_file().get_basename()
	for turn: float in DETAIL_TURNS:
		cam.global_position = centre + (Basis(Vector3.UP, turn) * away).normalized() * reach
		cam.look_at(centre)
		for f in 2:
			await probe.process_frame
		await RenderingServer.frame_post_draw
		var img := probe.root.get_texture().get_image()
		var holder := PlateSight.colliders(probe.root, owners, {body: "subject", bag: "bag"})
		see_both_sides(holder)
		await probe.physics_frame
		await probe.physics_frame
		var bounds: Dictionary = holder.get_meta("bounds")
		var side := "%s turn %.2f" % [tag, turn]
		var ok: bool = (
			bounds.has("bag") and probe.call("_box_in_frame", cam, bounds["bag"], frame, side)
		)
		var on := lines_on_bag(cam, core)
		var dark := dark_share(img)
		print("INFRAME %s bag_lines_first_on=%d/5 dark=%.2f" % [side, on, dark])
		ok = ok and on >= DETAIL_ON and dark < DARK_SHARE
		holder.free()
		if ok and img.save_png(path) == OK:
			print("PLATE saved %s size=%s" % [path, img.get_size()])
			return true
	print("DETAIL_PLATE missed %s" % tag)
	return false


## How many of five sight lines from `cam` to `box` (its middle and four points
## a sixth of its size out across and up) hit a body tagged "bag" first.
static func lines_on_bag(cam: Camera3D, box: AABB) -> int:
	var space := cam.get_world_3d().direct_space_state
	var right := cam.global_transform.basis.x
	var up := cam.global_transform.basis.y
	var reach := box.size.length() / 6.0
	var on := 0
	for off in [Vector3.ZERO, right * reach, -right * reach, up * reach, -up * reach]:
		var at: Vector3 = box.get_center() + off
		var to := at + (at - cam.global_position).normalized() * 3.0
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(cam.global_position, to))
		if not hit.is_empty() and str((hit.collider as Node).get_meta("subject", "")) == "bag":
			on += 1
	return on


## The SELF check of the head and neck at a hand-led move's plate moment (a
## floor set-down or pickup stoops over the bag; the booth SELF check counts
## only bags whose home is a hand): how many vertices skinned mostly to a bone
## named Head* or Neck* lie inside a mesh of `bag`, and their least gap to the
## bag's mesh bounds (a box at least as big as the mesh, so the gap is never
## overstated). Prints SELF_HEAD with the bones and point count seen (the
## control), and PROBE_INVALID when any is inside. Returns the count inside.
static func head_in_bag(body: Node3D, bag: Node3D, key: String, k: float) -> int:
	var named: Array = CarryContact.body_points_owned(body, [])
	var meshes := []
	for mi: MeshInstance3D in bag.find_children("*", "MeshInstance3D", true, false):
		meshes.append([mi.global_transform, mi.get_aabb(), mi.mesh.get_faces()])
	var bones := {}
	var inside := 0
	var gap := INF
	for n in (named[0] as PackedVector3Array).size():
		var bone: String = named[1][n]
		if not (bone.begins_with("Head") or bone.begins_with("Neck")):
			continue
		bones[bone] = bones.get(bone, 0) + 1
		var point: Vector3 = named[0][n]
		for mesh: Array in meshes:
			var xf: Transform3D = mesh[0]
			var box: AABB = mesh[1]
			var local := xf.affine_inverse() * point
			if box.grow(0.001).has_point(local) and CarryContact._odd(local, mesh[2]):
				inside += 1
			gap = minf(gap, point.distance_to(xf * local.clamp(box.position, box.end)))
	print("SELF_HEAD %s k=%.2f inside=%d gap_m=%.3f bones=%s" % [key, k, inside, gap, bones])
	if bones.is_empty() or inside > 0:
		print("PROBE_INVALID SELF_HEAD %s: head or neck in its bag, or no head points" % key)
	return inside + int(bones.is_empty())
