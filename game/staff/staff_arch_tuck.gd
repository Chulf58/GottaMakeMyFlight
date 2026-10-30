class_name StaffArchTuck
extends RefCounted
## A staff member tucks its arms in toward the body while it walks through a
## security lane's arch, as a passenger's free arms do there
## (SecurityLooks.in_arch_passage(), BoothCarry): the arch is narrowed to fit
## inside its cell beside a wall, 0.76 m clear (decision security-lane-arch-is-
## narrowed-to-fit-inside-its-cell-beside-a), and the plain walk swing put the
## hands through its posts (board item staff-tuck-their-arms-through-security-
## arches-staff-walk-thr). StaffCharacters keeps one record per member: it
## starts the turn in or out on the tick the member's passage state changes
## (update()), reads the eased weight between ticks (weight()) and poses the
## arms with it (pose()). The arms are posed by two CarryArm modifiers holding
## nothing, in CarryArm's front pose, aimed as a passenger's tucked free hand
## (BoothCarry.free_hand_width()).

## How long the turn in or out takes, as the passengers' tuck
## (CarryOnProps.TRANSFER_TICKS).
const TUCK_TICKS := CarryOnProps.TRANSFER_TICKS


## Whether `m` stands in a security lane's arch or walks into one now. Leaving,
## the arch cell counts until it arrives in the cell past it (`at` is the arch
## until then). The staff side of SecurityLooks.in_arch_passage().
static func in_arch_passage(grid: BuildGrid, m: StaffMember) -> bool:
	if m.in_pool():
		return false
	if SecurityLooks.def_at(grid, m.at) == SecurityLanes.ARCH:
		return true
	if not m.is_moving():
		return false
	return SecurityLooks.def_at(grid, m.path[m.path_index + 1]) == SecurityLanes.ARCH


## How far `record` has tucked in at sim time `now`: 0 swinging, 1 tucked. The
## turn eases out (fast at first) over TUCK_TICKS from where the last one began.
## A turn that began after `now` (a record kept across a load that went back in
## time) reads settled at its target.
static func weight(record: Dictionary, now: float) -> float:
	var target := 1.0 if record.get("tuck", false) else 0.0
	if not record.has("since") or now < record["since"]:
		return target
	var k := clampf((now - record["since"]) / TUCK_TICKS, 0.0, 1.0)
	return lerpf(record["from"], target, 1.0 - (1.0 - k) * (1.0 - k))


## Starts the turn in or out at `tick` when `inside` (in_arch_passage()) has
## changed. A new (empty) record starts settled, so no turn is seen: a member
## drawn for the first time (a hire at the entrance), and every member after a
## load, since StaffCharacters starts its records over on each snapped sync.
static func update(record: Dictionary, inside: bool, tick: float) -> void:
	if not record.has("tuck"):
		record["tuck"] = inside
		return
	if inside != record["tuck"]:
		record["from"] = weight(record, tick)
		record["since"] = tick
		record["tuck"] = inside


## Poses the arms of `body` (a Toon character) `tuck` of the way in; at 0 they
## keep the animation's swing. The two modifiers are made on the first tuck.
static func pose(body: Node3D, tuck: float) -> void:
	if tuck <= 0.0 and not body.has_meta(&"tuck_arms"):
		return
	for arm: CarryArm in arms_of(body):
		arm.active = tuck > 0.0
		arm.front_weight = tuck
		arm.front_half_width = BoothCarry.free_hand_width(false, tuck)


## The two tuck modifiers on `body`'s skeleton (right arm, then left), made
## when first asked for. They hold nothing: a free hand comes forward only.
static func arms_of(body: Node3D) -> Array[CarryArm]:
	if body.has_meta(&"tuck_arms"):
		return body.get_meta(&"tuck_arms")
	var skeleton := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var arms: Array[CarryArm] = []
	for side in CarryArm.ARM_BONES.size():
		var arm := CarryArm.new()
		arm.name = "TuckArm%d" % side
		arm.side = side
		arm.holds = false
		arm.active = false
		skeleton.add_child(arm)
		arms.append(arm)
	body.set_meta(&"tuck_arms", arms)
	return arms
