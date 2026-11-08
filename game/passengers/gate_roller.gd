class_name GateRoller
extends RefCounted
## Where a roller lies at a gate chair (RollerPark.floor_spot()), in the chair
## front's frame (RollerPark.chair_front()): beside the feet of the walker
## standing at the chair front to set it down and pick it up, on its hand's
## side, along its line, RollerPark.FEET_AHEAD_M ahead (user ruling
## roller-laid-down-beside-the-passenger-s-feet-not-ahead). The seated body's
## feet end behind the lying roller (test_gate_chair_roller_spot), so the
## standing legs set how far out it lies.

## How far out the roller's middle lies, by body variant (male, then female;
## PassengerLooks.BODIES) and hand (right, left), the way RollerPark.SEAT_SIDE_M
## is laid out: the least side at which the idle legs of every body of the
## variant leave the roller shell's box (grown by 1 cm) empty, plus 1 cm. The
## needs (test_roller_stand_clearance, "gate"): male right 0.38 to 0.39, male
## left 0.43 to 0.44, female right 0.345 to 0.355, female left 0.275 to 0.29.
## The female left side keeps the 0.34 it had. At 0.34 for all (board
## 1fe04f01) the shell took in the near leg of every male body and the right
## leg of every female one. SEAT_SIDE_M itself is not taken: its male left
## (0.43) and female sides (0.32) are short of these needs.
const LIE_SIDE_M: Array = [[0.40, 0.45], [0.365, 0.34]]
## The same for a two-bag guest's roller, drawn at SecurityLooks.TWO_BAG_SCALE:
## the least side at which the idle and seated legs of every body of the
## variant leave its smaller shell box (grown by 1 cm) empty, plus 1 cm. The
## needs (test_gate_chair_roller_spot): male right 0.315, male left 0.345,
## female right 0.28, female left 0.215. At LIE_SIDE_M the rollers of two male
## two-bag neighbours whose fixed hands face one gap (SecurityLooks.hand_of())
## overlapped by 0.030 m; at these they are 0.14 m apart.
const TWO_BAG_SIDE_M: Array = [[0.325, 0.355], [0.29, 0.225]]
## Half the roller shell's width across at scale 1, centred on its middle
## (test_gate_chair_roller_spot measures the shell box: 0.328 m wide).
const SHELL_HALF_M := 0.164


## How far out a roller of a body of look `look` (PassengerLooks.BODIES index)
## lies at a gate chair on the side of `hand` (0 right, 1 left), drawn at
## `scale_by`: LIE_SIDE_M at full size, TWO_BAG_SIDE_M smaller.
static func side(look: int, hand: int, scale_by := 1.0) -> float:
	var table: Array = LIE_SIDE_M if scale_by >= 1.0 else TWO_BAG_SIDE_M
	var variant := clampi(look / PassengerLooks.PER_VARIANT, 0, table.size() - 1)
	return table[variant][hand]


## How far out from its chair front the shell of that roller reaches (side()
## plus its half width): two neighbours' rollers in one gap overlap when theirs
## add up past the 1 m between the fronts.
static func reach(look: int, hand: int, scale_by := 1.0) -> float:
	return side(look, hand, scale_by) + SHELL_HALF_M * scale_by


## The roller of `p` led by `hand` lying at its gate chair, in the chair
## front's frame: side() out on the hand's side, FEET_AHEAD_M ahead.
static func spot(p: Passenger, hand: int) -> Transform3D:
	var out := -1.0 if hand == 0 else 1.0
	var look := PassengerLooks.body_of(p.id, p.variant)
	return Transform3D(
		Basis.IDENTITY,
		Vector3(out * side(look, hand, SecurityLooks.bag_scale(p)), 0.0, RollerPark.FEET_AHEAD_M)
	)
