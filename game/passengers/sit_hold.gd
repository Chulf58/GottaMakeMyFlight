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
		if SecurityLooks.bag_kind(p, i) != SecurityLooks.Kind.ROLLER:
			continue
		var bag := props.bag_state(p.id, i)
		var since := float(bag.get("since", -INF))
		var place := int(bag.get("home", -1))
		if bag.get("park", false) and since >= p.stage_tick - 1:
			if CarryLead.start_of(bag)[0] == CarryLead.End.HELD:
				held = maxf(held, since + CarryLead.ticks_of(bag) + LET_GO_TICKS - p.stage_tick)
		elif place >= 0 and place / 4 == SecurityLooks.Home.HAND:
			if bag.get("carry", -1) == SecurityLooks.Carry.PULL and since < p.stage_tick:
				held = maxf(held, RollerPark.TICKS_DOWN + LET_GO_TICKS)
		elif int(bag.get("was", -1)) < 0 and not _late_at_start(sim, p):
			# A bag with no record, or drawn for the first time with no move
			# before it: the views started over on a load (PassengerViews.snap())
			# and the roller is drawn at its home with no park to read the hold
			# from. The hold is as long as a pull>floor park, from the sit-down's
			# start, the same as before the load. A walker late as it began
			# sitting down set its roller down from the hand with no park, so
			# there is no hold to make up.
			held = maxf(held, RollerPark.TICKS_DOWN + LET_GO_TICKS)
	return clampi(ceili(held), 0, PassengerSim.SIT_DOWN_TICKS - MIN_SIT_TICKS)


## Whether `p` was late as it began sitting down: sat_late once
## ParkRecovery.note_sitting() has noted it (a tick after the sit-down began),
## and on the sit-down's first tick, before that, its lateness now.
static func _late_at_start(sim: PassengerSim, p: Passenger) -> bool:
	return p.sat_late or (p.late and sim.tick - p.stage_tick < 1)


## Where `p` stands on the first tick of its sit-down at a gate chair or a cafe
## seat, the chair front, in the world: the gate seat's front cell, or the cafe
## seat's approach cell (where PassengerSim.world_position() and
## CafeSim.seat_position() put it before their shuffle begins). Read from the
## seat each time, never kept per passenger, so a load puts it back to the same
## place; null with no such seat.
static func chair_front(sim: PassengerSim, p: Passenger) -> Variant:
	match StageKinds.location(p.stage):
		StageKinds.Location.GATE_SEAT:
			if p.seat_cell != Passenger.NO_CELL and p.seat_front != Passenger.NO_CELL:
				return sim.grid.cell_to_world(p.seat_front)
		StageKinds.Location.FACILITY_SEAT:
			var visit := sim.cafes.visit_of(p.id)
			if visit != null and not visit.seat.is_empty():
				return sim.grid.cell_to_world(visit.seat["approach"])
	return null


## The offset from `now` (where PassengerViews would draw `p` this tick) to
## where it stands while it sets its roller down at a gate chair or cafe seat
## (user ruling roller-laid-down-beside-the-passenger-s-feet-not-ahead): at
## chair_front(), for held_ticks(), then easing into the seat over the sit_down
## clip. The sim's shuffle into the seat (its first 8 ticks at a gate chair, 12
## at a cafe seat) drew a standing body sliding back 0.55 m.
static func offset(props: CarryOnProps, sim: PassengerSim, p: Passenger, now: Vector3) -> Vector3:
	var held := 0
	if StageKinds.pose(p.stage) == StageKinds.Pose.SITTING_DOWN:
		held = held_ticks(props, sim, p)
	var front: Variant = chair_front(sim, p)
	if held <= 0 or front == null:
		return Vector3.ZERO
	var into := ActivityPoses.clip_ticks(sim, p) - held
	var u := 0.0 if into < 0 else smoothstep(0.0, PassengerSim.SIT_DOWN_TICKS - held, into)
	return ((front as Vector3) - now) * (1.0 - u)
