class_name GateRoller
extends RefCounted
## Where a roller lies at a gate chair (RollerPark.floor_spot()), in the chair
## front's frame (RollerPark.chair_front()): beside the feet of the walker
## standing at the chair front to set it down and pick it up, on its hand's
## side, along its line, RollerPark.FEET_AHEAD_M ahead (user ruling
## roller-laid-down-beside-the-passenger-s-feet-not-ahead). The seated body's
## feet end behind the lying roller (test_gate_chair_roller_spot), so the
## legs drawn at the chair front (standing, and sitting down there before the
## shuffle onto the chair) set how far out it lies.

## How far out the roller's middle lies, by body variant (male, then female;
## PassengerLooks.BODIES) and hand (right, left), the way RollerPark.SEAT_SIDE_M
## is laid out: the least side at which the legs of every body of the variant,
## idle, seated and through the sit_down clip at the chair front, leave the
## roller shell's box (grown by 1 cm) empty, plus 1 cm. The needs
## (test_gate_chair_roller_spot, a chair with no slide): male right 0.39, male
## left 0.435, female right 0.41, female left 0.345. The idle legs alone needed
## female right 0.355 and left 0.29; at 0.365 and 0.34 the windowed probe found
## a female_11 right toe in the roller on the first sit_down frame (board
## 4da2e8ff). At 0.34 for all (board 1fe04f01) the shell took in the near leg of
## every male body. SEAT_SIDE_M itself is not taken: its male left (0.43) and
## female sides (0.32) are short of these needs.
const LIE_SIDE_M: Array = [[0.40, 0.45], [0.42, 0.355]]
## The same for a two-bag guest's roller, drawn at SecurityLooks.TWO_BAG_SCALE,
## and its smaller shell box. The needs: male right 0.315, male left 0.36,
## female right 0.335, female left 0.27 (idle and seated alone: 0.315, 0.345,
## 0.28, 0.215). At LIE_SIDE_M the rollers of two male two-bag neighbours whose
## fixed hands face one gap (SecurityLooks.hand_of()) overlapped by 0.030 m; at
## these they are 0.125 m apart.
const TWO_BAG_SIDE_M: Array = [[0.325, 0.37], [0.345, 0.28]]
## Half the roller shell's width across at scale 1, centred on its middle
## (test_gate_chair_roller_spot measures the shell box: 0.328 m wide).
const SHELL_HALF_M := 0.164
## How far out the roller's middle lies on the side the guest shuffles toward
## to sit down (shuffle_side()), by the chair's slide (short: the seat row's
## end chairs, 0.08 m; far: its middle chair, 0.36 m; GateChairs.CHAIR_OFFSET_M),
## body variant and hand, laid out as LIE_SIDE_M: the least side at which every
## body of the variant, through the sit_down clip at the front and seated along
## the whole shuffle onto the chair, leaves the shell's box (grown by 1 cm)
## empty, plus 1 cm (test_gate_chair_roller_spot). User-ruled 2026-11-09, "Legs
## clear, narrow shift (Recommended)" (board 4da2e8ff): the measured need, not
## the whole slide, which laid the roller 0.06 to 0.2 m further into the gap.
const SHUFFLE_SIDE_M: Array = [
	[[0.435, 0.505], [0.46, 0.395]],
	[[0.575, 0.76], [0.625, 0.58]],
]
## The same for a two-bag guest's roller, drawn at SecurityLooks.TWO_BAG_SCALE.
const TWO_BAG_SHUFFLE_SIDE_M: Array = [
	[[0.35, 0.415], [0.37, 0.305]],
	[[0.465, 0.615], [0.48, 0.435]],
]
## A chair's slide (slide()) this long or longer is far (SHUFFLE_SIDE_M's
## second row); shorter than NO_SLIDE_M is none.
const FAR_SLIDE_M := 0.2
const NO_SLIDE_M := 0.01
## walled_tight() tries the way out to a lying roller at this many shares of
## its side: the step (0.76 m / 8, 0.095 m, or less) is under a two-bag
## roller's width (0.18 m).
const LIE_SAMPLES := 8


## How far out a roller of a body of look `look` (PassengerLooks.BODIES index)
## lies at a gate chair on the side of `hand` (0 right, 1 left), drawn at
## `scale_by`: LIE_SIDE_M at full size, TWO_BAG_SIDE_M smaller.
static func side(look: int, hand: int, scale_by := 1.0) -> float:
	var table: Array = LIE_SIDE_M if scale_by >= 1.0 else TWO_BAG_SIDE_M
	var variant := clampi(look / PassengerLooks.PER_VARIANT, 0, table.size() - 1)
	return table[variant][hand]


## side() at a chair whose seat lies `slide` m to the left of its front (slide(),
## negative to the right): on the side the guest shuffles toward to sit down,
## out to SHUFFLE_SIDE_M for the chair's slide (short or far) if that is
## further, as the seated feet move across the roller's line on the way to
## the chair; on the other side, or with no slide, side() itself. The seat
## row's middle chair (0.36 m to the left) has its roller laid on its right
## first (ParkSide.gap_hand()), the side away from the shuffle (decision
## gate-chair-roller-lies-opposite-the-sit-down-shuffle-on-a-ch): at side() on
## its left, the seated feet of a guest shuffling onto it were 264 body points
## deep in the roller (board 4da2e8ff).
static func shuffle_side(look: int, hand: int, scale_by: float, slide_m: float) -> float:
	var toward := (hand == 1 and slide_m > 0.0) or (hand == 0 and slide_m < 0.0)
	if not toward or absf(slide_m) < NO_SLIDE_M:
		return side(look, hand, scale_by)
	var table: Array = SHUFFLE_SIDE_M if scale_by >= 1.0 else TWO_BAG_SHUFFLE_SIDE_M
	var variant := clampi(look / PassengerLooks.PER_VARIANT, 0, 1)
	var far := 1 if absf(slide_m) >= FAR_SLIDE_M else 0
	return maxf(side(look, hand, scale_by), table[far][variant][hand])


## How far out from its chair front the shell of that roller reaches
## (shuffle_side() plus its half width): two neighbours' rollers in one gap
## overlap when theirs add up past the 1 m between the fronts.
static func reach(look: int, hand: int, scale_by := 1.0, slide_m := 0.0) -> float:
	return shuffle_side(look, hand, scale_by, slide_m) + SHELL_HALF_M * scale_by


## How far to the left (m, + the left hand's side of a guest at the front
## facing out of the chair; - the right) the chair of seat cell `seat` lies
## from its front `front` across, in the seat row placed as `piece`
## (Relocation.placement()): GateChairs.CHAIR_OFFSET_M turned with the row,
## the step GateChairs.offset() draws the shuffle with. 0 for no piece, a cell
## outside its footprint or no front.
static func slide(piece: Dictionary, seat: Vector2i, front: Vector2i) -> float:
	if piece.is_empty() or seat == Passenger.NO_CELL or front == Passenger.NO_CELL:
		return 0.0
	var def := BuildCatalog.get_def(piece["def"])
	if def == null:
		return 0.0
	var index := def.footprint(piece["anchor"], piece["facing"]).find(seat)
	if index < 0 or index >= GateChairs.CHAIR_OFFSET_M.size():
		return 0.0
	var step := BuildObjectDef.rotate_point(
		Vector2(GateChairs.CHAIR_OFFSET_M[index], 0.0), piece["facing"]
	)
	var out := front - seat
	var left := Basis(Vector3.UP, atan2(out.x, out.y)).x
	return Vector3(step.x, 0.0, step.y).dot(left)


## slide() of the gate chair `p` is bound for or at (its seat_piece), 0 away
## from one (a security repack's floor).
static func slide_of(p: Passenger) -> float:
	if p.stage not in ParkSide.GATE_STAGES:
		return 0.0
	return slide(p.seat_piece, p.seat_cell, p.seat_front)


## The roller of `p` led by `hand` lying at its gate chair, in the chair
## front's frame: shuffle_side() out on the hand's side, FEET_AHEAD_M ahead.
static func spot(p: Passenger, hand: int) -> Transform3D:
	return _lying(p, hand, slide_of(p))


## spot() at a chair of slide `slide_m`, `share` of the way out to its side.
static func _lying(p: Passenger, hand: int, slide_m: float, share := 1.0) -> Transform3D:
	var out := -1.0 if hand == 0 else 1.0
	var look := PassengerLooks.body_of(p.id, p.variant)
	var lies := shuffle_side(look, hand, SecurityLooks.bag_scale(p), slide_m) * share
	return Transform3D(Basis.IDENTITY, Vector3(out * lies, 0.0, RollerPark.FEET_AHEAD_M))


## Whether gate seat `seat` (a TerminalLayout seat) has no room for the lying
## roller of `p` beside its front: the roller, at its own side (spot() for
## that chair) and size, reaches into a wall (ParkWalls.inside(),
## PullSide.walls_near(), the sim's own walls) or lies past one, on each side
## it could lie on. The way out is tried at LIE_SAMPLES shares of its side, each
## step under a two-bag roller's width: the middle chair's far side (0.76 m)
## laid it wholly past a wall on the 1 m front's edge, in no wall at its spot.
## A one-bag guest's roller can lie on either side (ParkSide); a two-bag
## guest's only on its own bag's hand. Such a chair is never given to a
## guest with a roller (user ruling a-roller-guest-is-never-given-a-gate-
## chair-walled-tight-on-b, board f1fc1e54): walled on both sides of its 1 m
## front, no side clears the legs (finding d15d7455: ParkWalls pushed the
## roller back into them, up to 0.179 m). False for a guest with no roller.
## ParkSide.hand() lays the roller on the one side that fits when only one
## does (clear_hand()), so a guest seated here lies in neither a wall nor its
## legs.
static func walled_tight(sim: PassengerSim, p: Passenger, seat: Dictionary) -> bool:
	if not ParkRecovery.has_roller(p):
		return false
	var front: Vector2i = seat["front"]
	var cell: Vector2i = seat["cell"]
	var slide_m := slide(Relocation.placement(sim.grid, seat["object_id"]), cell, front)
	var frame := ParkSide._frame(sim, front, front - cell)
	var walls := PullSide.walls_near(sim.grid, frame.origin)
	for hand in _hands(p):
		if _lies_clear(p, frame, walls, slide_m, hand):
			return false
	return true


## The hand (0 right, 1 left) a one-bag guest `p` bound for a gate chair lays
## its roller down with when exactly one side has room for it (the side walled_tight()
## lets the chair through on), else -1: both sides fit, none does, or the guest
## has two bags (each lies on its own bag's hand) or no roller.
static func clear_hand(sim: PassengerSim, p: Passenger) -> int:
	if p.carry_on >= 2 or not ParkRecovery.has_roller(p):
		return -1
	var out := p.seat_front - p.seat_cell
	var frame := ParkSide._frame(sim, p.seat_front, out)
	var walls := PullSide.walls_near(sim.grid, frame.origin)
	var slide_m := slide_of(p)
	var fits: Array[int] = []
	for hand in _hands(p):
		if _lies_clear(p, frame, walls, slide_m, hand):
			fits.append(hand)
	return fits[0] if fits.size() == 1 else -1


## The hands `p`'s roller can lie on: either for a one-bag guest, the roller
## bag's own for a two-bag guest.
static func _hands(p: Passenger) -> Array[int]:
	var hands: Array[int] = [0, 1]
	if p.carry_on >= 2:
		hands = []
		for i in 2:
			if SecurityLooks.bag_kind(p, i) == SecurityLooks.Kind.ROLLER:
				hands.append(i)
	return hands


## Whether the roller of `p` lying on `hand` at a chair whose front stands in
## `frame` (slide `slide_m`) meets no wall of `walls` and lies past none, at
## any of LIE_SAMPLES shares of the way out.
static func _lies_clear(
	p: Passenger, frame: Transform3D, walls: Array, slide_m: float, hand: int
) -> bool:
	var scale_by := SecurityLooks.bag_scale(p)
	for n in range(1, LIE_SAMPLES + 1):
		var lying := frame * _lying(p, hand, slide_m, n / float(LIE_SAMPLES))
		lying = Transform3D(lying.basis.scaled(Vector3.ONE * scale_by), lying.origin)
		if ParkWalls.inside(lying, walls):
			return false
	return true
