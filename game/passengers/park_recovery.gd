class_name ParkRecovery
extends RefCounted
## A walker whose gate seat is removed while its roller parks to go onto the
## floor (RollerPark's pull>floor, from the tick it starts sitting down)
## collects the bag before it walks off (decision roller-park-interrupted-by-a-
## lost-seat-the-passenger-collect, board d425a825). The view holds the park to
## its end (RollerPark.hold_park()) and then takes the bag off the floor into
## the pull (floor>pull); set off on its new route at once, the walker went at
## walking pace from about 12 ticks into the park, its hand reached back 0.3 to
## 1.06 m for the bag, and the bag jumped 0.41 to 0.70 m into the hand.
## So the sim keeps the walker where it stands until the park's ticks and the
## pick-up's have run (Passenger.collect_tick), and only then sends it on its
## way. Timed by the sim clock from the tick it started sitting down, never by
## a drawn hand reaching the bag.
## What it does not guarantee: the view stamping the park on the tick the walker
## started sitting down (it stamps a change of home on the frame that sees it,
## as the stand-up's floor>pull does, SecurityLooks._rolled_up()); and a seat
## removed once the park is over (still sitting down, or seated) is left as it
## was: the walker goes at once. The sim does not know whether the view parked
## the roller (a walker late as it sat down set it down from the hand, with no
## park), so such a walker stands the same ticks.

## Ticks of the pick-up (floor>pull) the walker stands for: to the end of the
## lift to the park (RollerPark.LIFT_END) and one tick more, since the body is
## drawn moving over the tick before the sim's first step. Set off 9 ticks in
## (RollerPark.UP_LEAD_TICKS, as a walker standing up does) it was drawn
## walking at k 0.52, before the lift ended. The rest of the pick-up (the park,
## cut short, and the tip into the pull) is drawn as the walker goes, as it is
## for one walking off from a stand-up.
const COLLECT_TICKS := ceili(RollerPark.TICKS_UP * RollerPark.LIFT_END) + 1


## Whether `p` (of `sim`, its seat already released by the sim) loses its seat
## in the middle of a roller's park: sitting down at a gate seat less than
## RollerPark.TICKS_DOWN ticks, with a roller among its bags. If so it is to
## stand where it is to the tick collect_of() gives, kept on `p`.
static func on_seat_lost(sim: PassengerSim, p: Passenger) -> void:
	if p.stage != Passenger.Stage.SITTING_DOWN:
		return
	if sim.tick - p.stage_tick >= ceili(RollerPark.TICKS_DOWN) or not _has_roller(p):
		return
	p.collect_tick = collect_of(p.stage_tick)


## The tick a walker that started sitting down on `sat_tick` and lost its seat
## during the park walks on: the park to its end, then COLLECT_TICKS of the
## roller taken off the floor into the pull, standing still.
static func collect_of(sat_tick: int) -> int:
	return sat_tick + ceili(RollerPark.TICKS_DOWN) + COLLECT_TICKS


## Whether `p` (of `sim`, on its way to the gate) still stands collecting its
## bag on this tick. Once it is done its collect_tick is cleared and its way to
## the gate starts again on this tick (stage_tick), so it chooses a seat or a
## standing spot now (PassengerSim._to_spot() chooses on the tick its stage
## began, else on its next beat, PassengerSim.BEAT_TICKS: let go 9 ticks into
## the pick-up, it was first drawn moving at the pick-up's end).
static func collecting(sim: PassengerSim, p: Passenger) -> bool:
	if p.collect_tick == 0:
		return false
	if sim.tick < p.collect_tick:
		return true
	p.collect_tick = 0
	p.stage_tick = sim.tick
	return false


static func _has_roller(p: Passenger) -> bool:
	for i in p.carry_on:
		if SecurityLooks.bag_kind(p, i) == SecurityLooks.Kind.ROLLER:
			return true
	return false
