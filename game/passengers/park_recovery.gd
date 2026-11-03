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
## as the stand-up's floor>pull does, SecurityLooks._rolled_up()). A seat
## removed once the park is over (still sitting down, or seated) holds the
## walker the same from that tick (board 6981b7ac): the roller lies parked, so
## the pick-up starts then, where a walker set off at once had its hand reach
## back and the bag jump into it. A walker late as it began sitting down
## (Passenger.sat_late, note_sitting()) is not held; one turning late while
## held waits to the end. sat_late is noted on the tick after the sit-down
## began, so a frame that drew several ticks at once can have seen a later
## lateness. A load releases a walker at once (on_load()).

## Ticks of the pick-up (floor>pull) the walker stands for: to the end of the
## lift to the park (RollerPark.LIFT_END) and one tick more, since the body is
## drawn moving over the tick before the sim's first step. Set off 9 ticks in
## (RollerPark.UP_LEAD_TICKS, as a walker standing up does) it was drawn
## walking at k 0.52, before the lift ended. The rest of the pick-up (the park,
## cut short, and the tip into the pull) is drawn as the walker goes, as it is
## for one walking off from a stand-up.
const COLLECT_TICKS := ceili(RollerPark.TICKS_UP * RollerPark.LIFT_END) + 1
## A gate sitter with a roller stands this many ticks at the chair front after
## its stand-up, picking the roller up (stand_up_ticks()): the pick-up's lift,
## as a collecting walker's (COLLECT_TICKS).
const UP_HOLD_TICKS := ceili(RollerPark.TICKS_UP) + 1


## Whether `p` (of `sim`, its seat already released by the sim) loses its seat
## with a roller among its bags, sitting down or seated: in the middle of the
## roller's park (sitting down less than RollerPark.TICKS_DOWN ticks), or once
## it is over (decision seat-lost-after-a-roller-park-a-seated-passenger-still-
## stand, board 6981b7ac), the bag then lying parked on the floor. If so it is
## to stand where it is to the tick collect_of() gives, kept on `p`.
static func on_seat_lost(sim: PassengerSim, p: Passenger) -> void:
	if p.stage != Passenger.Stage.SITTING_DOWN and p.stage != Passenger.Stage.SEATED:
		return
	if not _has_roller(p):
		return
	# A walker late as it began sitting down carried its roller lifted in the
	# hand (CarryOnProps._lifted()) and set it down with no park, so there is
	# nothing to wait for: held, it could miss its flight. One that turned late
	# after has its park run on (RollerPark.holds_lift()) and is held.
	if p.sat_late:
		return
	var parked_at := p.stage_tick
	if p.stage == Passenger.Stage.SEATED or sim.tick - parked_at >= ceili(RollerPark.TICKS_DOWN):
		# The park is over and the roller lies parked: the pick-up starts now.
		parked_at = sim.tick - ceili(RollerPark.TICKS_DOWN)
	p.collect_tick = collect_of(parked_at)


## Notes on `p` (of `sim`, at the start of a tick, before any step) whether it
## was late as it began sitting down at a gate seat: on the tick after, p.late
## is what the view saw when it stamped the roller's move (it syncs between
## ticks), lifted in the hand or parked (CarryOnProps._lifted()).
static func note_sitting(sim: PassengerSim, p: Passenger) -> void:
	if p.stage == Passenger.Stage.SITTING_DOWN and sim.tick - p.stage_tick == 1:
		p.sat_late = p.late


## Whether `p`'s collect_tick is one the sim could have saved at `tick`: none,
## or on its way to the gate with a roller, collecting to a tick after `tick`
## and no further on than a whole hold.
static func valid(p: Passenger, tick: int) -> bool:
	if p.collect_tick == 0:
		return true
	var ahead := p.collect_tick - tick
	return (
		p.stage == Passenger.Stage.TO_GATE
		and _has_roller(p)
		and ahead > 0
		and ahead <= ceili(RollerPark.TICKS_DOWN) + COLLECT_TICKS
	)


## On a load at `tick`: a walker collecting its roller sets off at once (it
## plans its way on the next tick, PassengerSim._to_spot()). The view drops
## every carry record on a load and draws the bag at its home, in the pull,
## so a walker kept waiting stood by a roller it already had.
static func on_load(p: Passenger, tick: int) -> void:
	if p.collect_tick == 0:
		return
	p.collect_tick = 0
	p.stage_tick = tick + 1


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


## How many ticks the gate-chair stand-up (STANDING_UP) of `p` lasts: the
## stand-up, then for a passenger with a roller UP_HOLD_TICKS more, standing
## at the chair front while the roller is taken off the floor into the pull
## (decision standing-up-with-a-roller-stand-up-then-pick-up-then-walk). The
## pick-up began RollerPark.UP_LEAD_TICKS before the stand-up ended, on a body
## still rising: with the roller beside the feet and the back bent at most 45
## degrees the hand fell short and the bag jumped 0.11 to 0.31 m into it. The
## sim, the journey forecast and the view all read it here.
static func stand_up_ticks(p: Passenger) -> int:
	return PassengerSim.STAND_UP_TICKS + (UP_HOLD_TICKS if _has_roller(p) else 0)


static func _has_roller(p: Passenger) -> bool:
	for i in p.carry_on:
		if SecurityLooks.bag_kind(p, i) == SecurityLooks.Kind.ROLLER:
			return true
	return false
