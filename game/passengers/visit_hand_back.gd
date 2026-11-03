class_name VisitHandBack
extends RefCounted
## The tick a toilet or cafe visit takes its last step out of the stall or off
## the seat and hands the passenger back to its journey. That tick the journey's
## own walk is not planned: it starts on the next, so no tick moves the
## passenger by two steps at once (board a791eb90; 3c56361 did the same for a
## relocated visit's walk to its new spot).

## The stages whose last tick ends the visit's own movement.
const STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.TOILET_EXIT,
	Passenger.Stage.CAFE_STANDING_UP,
]


## Whether a passenger that began the tick in `from` and is in `now` was handed
## back to its journey this tick.
static func is_hand_back(from: Passenger.Stage, now: Passenger.Stage) -> bool:
	return STAGES.has(from) and StageKinds.facility(now) == StageKinds.Facility.NONE
