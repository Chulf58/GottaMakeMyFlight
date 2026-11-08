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
## moves on until the places move up. It keeps the wait too when the front of
## the line leaves within STILL_TICKS (desk_front_leaves(),
## security_front_leaves()): the places then move
## up at once, and a stand that began on this tick would tip (Sol re-check of
## 24ac8fe; board e6b4e303). Every other stop keeps the wait: a member
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
		var cells := sim.layout.line_of(p.station)
		var desk := not sim.layout.passages.has(p.station)
		var leaving := false
		if stuck(sim, p, members, cells):
			if desk:
				leaving = desk_front_leaves(sim, members, sim.tick)
			else:
				leaving = security_front_leaves(sim, p.station, members, cells)
		return line_wait(sim, p, members, cells, leaving, desk)
	return RollerPark.STILL_TICKS


## The still ticks line member `p` waits: none when stuck(), unless the front
## of the line is `leaving` (desk_front_leaves(), security_front_leaves()) and
## `p` would step up at once when it does (steps_at_once()), else STILL_TICKS.
## `desk`: the line is a desk's.
static func line_wait(
	host: Object, p: Passenger, lane: Array, cells: Array, leaving := false, desk := false
) -> int:
	if leaving and steps_at_once(host, p, lane, desk):
		return RollerPark.STILL_TICKS
	return 0 if stuck(host, p, lane, cells) else RollerPark.STILL_TICKS


## Whether `p` of `lane` steps up the moment the front leaves and the places
## move up: every member between the front and `p` walks on without waiting
## for a roller to stand (QueueRipple.may_step() lets a walker follow one
## ahead that walks off with no roller at once, and holds it behind one that
## pulls a roller until that one has stood STAND_TICKS), so none of them
## pulls a roller. At a desk (`desk`) the new front is also held while a
## departing front pulling a roller walks FRONT_CLEAR_MM away
## (QueueRipple.desk_clear()), and the walkers behind it with it, so the
## departing front counts as well. A security front walks into the passage and
## holds nobody. Board e6b4e303.
static func steps_at_once(host: Object, p: Passenger, lane: Array, desk := false) -> bool:
	for i in range(0 if desk else 1, lane.find(p.id)):
		if QueueRipple.pulls_roller(host.get_passenger(lane[i])):
			return false
	return true


## Whether the front of desk `lane` finishes its check-in within STILL_TICKS of
## tick `now` (it is served until Passenger.service_end, then leaves the lane
## and the places move up). `host` has get_passenger().
static func desk_front_leaves(host: Object, lane: Array, now: int) -> bool:
	if lane.is_empty():
		return false
	var front: Passenger = host.get_passenger(lane[0])
	return (
		front.stage == Passenger.Stage.CHECKIN and front.service_end - now <= RollerPark.STILL_TICKS
	)


## Whether the front of the security lane of `station` is admitted within
## STILL_TICKS: the station is usable and open, the front stands ready on the
## first cell and SecurityRuntime.ready_front() would take it (a lane scanner's
## incident passenger needs a free berth), the main position is free (nothing
## admitted, or the one in it done with a passage scan within STILL_TICKS) and
## the gate has a place for it (GateCapacity.admit_all(): boarding open, a place
## already held, or the standing room not scarce()), so admit_front() takes it.
## Reads only. A lane scanner's main position frees after the arch walk, which
## this does not predict.
static func security_front_leaves(
	sim: PassengerSim, station: int, lane: Array, cells: Array
) -> bool:
	if lane.is_empty() or cells.is_empty() or not sim.layout.passages.has(station):
		return false
	if not sim.layout.is_usable(station) or sim.staff == null or not sim.staff.is_open(station):
		return false
	var front: Passenger = sim.get_passenger(lane[0])
	if front.stage != Passenger.Stage.SECURITY_QUEUE:
		return false
	if sim.security.ready_front(station, {"lane": lane}, cells, true) == null:
		return false
	if not _main_frees_soon(sim, station):
		return false
	return sim.gates.placed(front, sim) or not sim.gates.scarce(sim, station, front)


## Whether no returner waits for the main position of security `station` and it
## is free, or its passage scan ends within STILL_TICKS.
static func _main_frees_soon(sim: PassengerSim, station: int) -> bool:
	var record := sim.security.record_of(station)
	if record.is_empty():
		return true
	if not (record["returns"] as Array).is_empty():
		return false
	if record["main"] == 0:
		return true
	var main: Passenger = sim.get_passenger(record["main"])
	var scan := SecurityRuntime.Phase.SCAN
	return (
		not sim.security.is_lane(station)
		and main.security_phase == scan
		and main.security_work <= RollerPark.STILL_TICKS * sim.security.rate(station, scan)
	)


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
