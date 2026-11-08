class_name QueueStandWait
extends RefCounted
## How long a walker pulling a roller stands still in a queue before the roller
## is stood up beside it (RollerPark.queue_stand()'s `wait`).
## The walking pull trails the roller 1.0 m (RollerPull.TRAIL_M), the pitch of
## a queue place, so with the RollerPark.STILL_TICKS wait a walker that stopped
## left it lying by the next walker's feet for about 10 ticks (board e7028790).
## A walker in a desk or security line (LINE_STAGES) that is stuck stands it up
## at once (decision a-queue-passenger-who-stops-behind-a-standing-member-
## stands, "sooner only when stuck"): it stands on its own place behind a
## member standing still on that member's own place (stuck()), so neither
## moves on until the places move up. Every other stop keeps the wait: a member
## ahead still walking, or standing short of its place, may step on the next
## tick (QueueRipple.may_step(): at once when it pulls no roller), and the
## walker behind with it, which stood the roller and tipped it at once (Sol
## review of 8cf51a0; decision roller-queue-stand-as-built, "no still wait"
## rejected). A boarding file waits RollerPark.FILE_STILL_TICKS.

## The desk and security lines.
const LINE_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.CHECKIN_QUEUE,
	Passenger.Stage.SECURITY_QUEUE,
]


## The still ticks `p` of `sim` waits before its roller is stood up.
static func ticks(sim: PassengerSim, p: Passenger) -> int:
	if p.stage in RollerPark.FILE_STAGES:
		return RollerPark.FILE_STILL_TICKS
	if p.stage in LINE_STAGES:
		var members := sim.queue_of(p.station) + sim.holding_of(p.station)
		return line_wait(sim, p, members, sim.layout.line_of(p.station))
	return RollerPark.STILL_TICKS


## The still ticks line member `p` waits: none when stuck(), else STILL_TICKS.
static func line_wait(host: Object, p: Passenger, lane: Array, cells: Array) -> int:
	return 0 if stuck(host, p, lane, cells) else RollerPark.STILL_TICKS


## Whether queue member `p` is stuck: it stands on its own place and the member
## ahead stands still on its own place, so neither steps on until the places
## move up. `lane` is the station's members (lane, then holding list), `cells`
## its line and `host` has get_passenger(), as for QueueRipple.may_step(). The
## front has no member ahead.
static func stuck(host: Object, p: Passenger, lane: Array, cells: Array) -> bool:
	var index := lane.find(p.id)
	if index <= 0 or index >= cells.size() or p.is_moving() or p.at != cells[index]:
		return false
	var ahead: Passenger = host.get_passenger(lane[index - 1])
	return ahead != null and not ahead.is_moving() and ahead.at == cells[index - 1]
