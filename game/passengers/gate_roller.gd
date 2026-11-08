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


## How far out (LIE_SIDE_M) a roller of a body of look `look`
## (PassengerLooks.BODIES index) lies at a gate chair on the side of `hand`
## (0 right, 1 left).
static func side(look: int, hand: int) -> float:
	var variant := clampi(look / PassengerLooks.PER_VARIANT, 0, LIE_SIDE_M.size() - 1)
	return LIE_SIDE_M[variant][hand]


## The roller of `p` led by `hand` lying at its gate chair, in the chair
## front's frame: side() out on the hand's side, FEET_AHEAD_M ahead.
static func spot(p: Passenger, hand: int) -> Transform3D:
	var out := -1.0 if hand == 0 else 1.0
	var look := PassengerLooks.body_of(p.id, p.variant)
	return Transform3D(
		Basis.IDENTITY, Vector3(out * side(look, hand), 0.0, RollerPark.FEET_AHEAD_M)
	)
