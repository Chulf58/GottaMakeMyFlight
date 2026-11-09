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
	var out := -1.0 if hand == 0 else 1.0
	var look := PassengerLooks.body_of(p.id, p.variant)
	var lies := shuffle_side(look, hand, SecurityLooks.bag_scale(p), slide_of(p))
	return Transform3D(Basis.IDENTITY, Vector3(out * lies, 0.0, RollerPark.FEET_AHEAD_M))
