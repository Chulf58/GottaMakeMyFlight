class_name QueueRipple
extends RefCounted
## A desk or security line (its lane, then its hold cells) moves up in a
## ripple (board 34b0c378). Its places
## are 1 m apart, and a roller in the walking pull trails its axle 1.00 to
## 1.04 m behind the body, so a walker that stepped up the moment the one ahead
## set off walked into that roller and stood on it until it was stood up
## beside its walker (headless measure on main 86e3011: 0.131 to 0.138 m from
## the follower's feet, 20 to 28 ticks a move-up).
## - A lane walker more than a place behind the one ahead steps up at once:
##   the cell it steps onto is clear of that walker and its trailing roller
##   (decision hold-line-rebuild-the-security-line-follows-where-people-sta,
##   so a hold line closes its gaps without a pause per place). It walks no
##   further than the cell behind the one ahead (target_index()), so one that
##   halted short of its place is never walked onto.
## - A lane walker behind a walker pulling a roller steps up only once that
##   walker stands on its own place and has stood still STAND_TICKS since its
##   walk ended (Passenger.halt_tick): RollerPark stands the roller up over its
##   STILL_TICKS and QUEUE_STAND_TICKS. Behind a walker with no roller it steps
##   up while that walker walks on, or once it stands on its own place, never
##   while it waits off its place. The front of the lane waits on nobody in
##   the lane.
## - At a desk the front steps onto the desk cell only once the passenger who
##   checked in there, pulling a roller, has walked FRONT_CLEAR_MM away
##   (its path starts on the desk cell), or at once when it stands still
##   there after the tick it left (stuck, so no wait for it would end).
## A walker without a roller ahead is not waited for. Security fronts are not
## held: the admitted passenger walks into the passage. PassengerSim and
## SecurityForecast both step lanes through may_step(), and the desk forecasts
## add desk_waits().

## RollerPark.STILL_TICKS + RollerPark.QUEUE_STAND_TICKS (9.5), rounded up.
const STAND_TICKS := 10
## The walk a desk leaver pulling a roller makes before the front steps onto
## the desk cell.
const FRONT_CLEAR_MM := 1000


## may_step() for queue member `p` of `sim`, on its tick.
static func sim_may_step(sim: PassengerSim, p: Passenger) -> bool:
	var members := sim.queue_of(p.station) + sim.holding_of(p.station)
	var desk := not sim.layout.passages.has(p.station)
	return may_step(sim, p, members, sim.layout.line_of(p.station), sim.tick, desk)


## Whether passenger `p`, in `lane` (a queue's members, lane then holding
## list; their places `cells`, the station's line), may set off for its place
## on tick `now`, so a holder moves up behind the one ahead as a lane walker
## does. `host` has get_passenger() and, for a desk (`desk`),
## passenger_ids(). True when it already stands on its place.
static func may_step(
	host: Object, p: Passenger, lane: Array, cells: Array, now: int, desk: bool
) -> bool:
	var index := lane.find(p.id)
	if p.at == cells[index]:
		return true
	if index > 0:
		var ahead: Passenger = host.get_passenger(lane[index - 1])
		var roller := pulls_roller(ahead)
		var here := cells.find(p.at)
		var there := cells.find(ahead.at)
		if here > 0 and there >= 0 and here - 1 > there + 1:
			# More than a place behind: the cell it steps onto is clear of the
			# one ahead and of the roller trailing it, so it closes the gap now.
			return true
		if ahead.is_moving():
			# Walking off without a roller it leaves nothing behind to walk into.
			return not roller
		if ahead.at != cells[index - 1]:
			return false
		return not roller or now - ahead.halt_tick >= STAND_TICKS
	return not desk or desk_clear(host, cells[0], now)


## The index in `cells` of the place member number `index` of `lane` walks to
## when may_step() lets it set off: its own place, but never the cell the
## member ahead stands on or is walking to, nor a cell before it. A member
## ahead that stands or halts short of its place (the places move up when a
## member leaves while it walks) holds its cell, so the one behind ends one
## cell back of it and steps on once it moves up, instead of walking onto it
## (board c2336d77; decision hold-line-rebuild-the-security-line-follows-
## where-people-sta, rule 1: advancing targets are given out front to back).
## A member ahead whose cell is not in front of this member's own (a walker
## that joined the lane while the holding list waited stands behind it) is
## never walked back to: the member walks to its own place.
## PassengerStations.queue_move() and SecurityForecast._move_up() both take
## their target here.
static func target_index(host: Object, lane: Array, cells: Array, index: int) -> int:
	if index <= 0:
		return index
	var ahead: Passenger = host.get_passenger(lane[index - 1])
	var there := cells.find(ahead.path_end() if ahead.is_moving() else ahead.at)
	var here := cells.find((host.get_passenger(lane[index]) as Passenger).at)
	if there < 0 or (here >= 0 and there >= here):
		return index
	return mini(maxi(index, there + 1), cells.size() - 1)


## Whether no passenger who checked in at desk cell `cell` pulling a roller is
## still within FRONT_CLEAR_MM of walk of it on tick `now`.
static func desk_clear(host: Object, cell: Vector2i, now: int) -> bool:
	for id: int in host.passenger_ids():
		var left: Passenger = host.get_passenger(id)
		if left.stage != Passenger.Stage.TO_SECURITY or not pulls_roller(left):
			continue
		if left.at == cell and not left.is_moving() and left.stage_tick == now:
			return false
		if left.is_moving() and left.path[0] == cell:
			if Passenger.path_mm(left.path) - left.remaining_mm() < FRONT_CLEAR_MM:
				return false
	return true


## The ticks the fronts of desk `station`'s queue in `sim` wait on leavers
## before `p` is served: front_wait_ticks() for each passenger pulling a roller
## served before it, the one being served included. `p` null: a newcomer
## behind everyone in the lane and holding list.
static func desk_waits(sim: PassengerSim, station: int, p: Passenger) -> int:
	var ahead: Array = sim.queue_of(station) + sim.holding_of(station)
	if p != null and ahead.has(p.id):
		ahead = ahead.slice(0, ahead.find(p.id))
	var waits := 0
	for id: int in ahead:
		var left: Passenger = sim.get_passenger(id)
		if pulls_roller(left):
			waits += front_wait_ticks(left)
	return waits


## The ticks a desk front waits on `leaver`, pulling a roller, beyond its walk
## up from the next place: the leaver's walk of FRONT_CLEAR_MM at its pace
## (Passenger.pace_ticks(), a run while late), which starts on the tick it
## leaves (stepped before the front, as an earlier passenger is).
## A leaver stepped after the front makes it wait one tick more.
static func front_wait_ticks(leaver: Passenger) -> int:
	return leaver.pace_ticks(FRONT_CLEAR_MM) - 1


## Whether `p` pulls a roller behind it (SecurityLooks.bag_kind()).
static func pulls_roller(p: Passenger) -> bool:
	for i in p.carry_on:
		if SecurityLooks.bag_kind(p, i) == SecurityLooks.Kind.ROLLER:
			return true
	return false


## Walks `p` `mm` along its path on tick `now`, noting the tick its walk ends.
static func walk(p: Passenger, mm: int, now: int) -> void:
	if not p.is_moving():
		return
	p.walk(mm)
	if not p.is_moving():
		p.halt_tick = now
