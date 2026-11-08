class_name QueueStandWait
extends RefCounted
## How long a walker pulling a roller stands still in a queue before the roller
## is stood up beside it (RollerPark.queue_stand()'s `wait`).
## The walking pull trails the roller 1.0 m (RollerPull.TRAIL_M), the pitch of
## a queue place, so with the RollerPark.STILL_TICKS wait a walker that stopped
## left it lying by the next walker's feet for about 10 ticks (board e7028790).
## A walker in a desk or security line (LINE_STAGES) that stops behind a member
## standing still stands it up at once (decision
## a-queue-passenger-who-stops-behind-a-standing-member-stands). Behind a
## member still walking it keeps the wait: a walker stepping up one place
## after it moves on again soon (QueueRipple) and would stand the roller and
## tip it at once (decision roller-queue-stand-as-built, "no still wait"
## rejected). A member standing short of its own place counts as standing:
## requiring its own place left the "held still" rows of
## game/spike/queue_spacing_probe.gd (check-in seeds 2 and 4, security seeds
## 2 and 4) at 8, 8, 16 and 8 frames of a roller within 0.30 m of a body,
## against 4, 4, 9 and 4 without, with no more stands tipped within 4 ticks
## of standing up. A boarding file
## waits RollerPark.FILE_STILL_TICKS.

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
		if behind_still(sim, p, sim.queue_of(p.station) + sim.holding_of(p.station)):
			return 0
	return RollerPark.STILL_TICKS


## Whether queue member `p` stands behind one standing still: `lane` is the
## station's members (lane, then holding list) and `host` has get_passenger(),
## as for QueueRipple.may_step(). The front has no member ahead.
static func behind_still(host: Object, p: Passenger, lane: Array) -> bool:
	var index := lane.find(p.id)
	if index <= 0:
		return false
	var ahead: Passenger = host.get_passenger(lane[index - 1])
	return ahead != null and not ahead.is_moving()
