class_name SitHold
extends RefCounted
## A passenger sitting down with a pulled roller stays standing until the
## roller's pull>floor park ends (RollerPark), then sits (user ruling
## sitting-down-with-a-roller-set-the-bag-down-standing-then-sit, board
## 76cb23c0). The sit clip seated the body in about 3 ticks while the 13-tick
## park kept the carry stoop on, and the stoop's hips drop pushed the seated
## hips 0.6 m under the chair. PassengerViews plays idle for the first
## held_ticks() ticks of the sit-down, then sit_down over the ticks left, so the
## sit ends with the sim's SITTING_DOWN as before. Looks only: no sim change.
## What it does not hold: the sim's shuffle into the seat, which moves the
## standing body back over its first ticks as before.

## The sit clip keeps at least this many ticks however late the park ends.
const MIN_SIT_TICKS := 8
## The sit starts this long after the park ends: the empty hand comes back
## from letting go as fast as it likes and stops on the park's last tick, and
## with the sit clip starting on that frame too the grip's change of step was
## 0.106 m, against 0.077 m a frame later.
const LET_GO_TICKS := 1.0


## How many ticks from the start of `p`'s sit-down (p.stage_tick) it stays
## standing for its roller (`props`' record of it, CarryOnProps): to
## LET_GO_TICKS past the end of a pull>floor park stamped since then, or,
## before the park is stamped (the sit-down's first tick, drawn before the
## bags), as long from now for a roller pulled in the hand. 0 when it sits at
## once (in a toilet stall too: a stall roller goes down by its own moves,
## StallCarry; and on a sofa or nap pod, whose visitor sets its roller down at
## its slot cell before the sit-down starts, ActivityPoses.seat_door()); at most
## SIT_DOWN_TICKS - MIN_SIT_TICKS.
static func held_ticks(props: CarryOnProps, sim: PassengerSim, p: Passenger) -> int:
	if Passenger.in_toilet(p.stage) or ActivityPoses.kind(sim, p) != ActivityPoses.Kind.NONE:
		return 0
	var held := 0.0
	for i in p.carry_on:
		var bag := props.bag_state(p.id, i)
		if int(bag.get("kind", -1)) != SecurityLooks.Kind.ROLLER:
			continue
		var since := float(bag.get("since", -INF))
		var place := int(bag.get("home", -1))
		if bag.get("park", false) and since >= p.stage_tick - 1:
			if CarryLead.start_of(bag)[0] == CarryLead.End.HELD:
				held = maxf(held, since + CarryLead.ticks_of(bag) + LET_GO_TICKS - p.stage_tick)
		elif place >= 0 and place / 4 == SecurityLooks.Home.HAND:
			if bag.get("carry", -1) == SecurityLooks.Carry.PULL and since < p.stage_tick:
				held = maxf(held, RollerPark.TICKS_DOWN + LET_GO_TICKS)
	return clampi(ceili(held), 0, PassengerSim.SIT_DOWN_TICKS - MIN_SIT_TICKS)
