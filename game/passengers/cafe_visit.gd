class_name CafeVisit
extends RefCounted
## One passenger's cafe visit, owned by CafeSim. Plain data: the passenger's
## journey stage says which phase the visit is in (a gate STANDING_UP with a
## visit is a guest getting up from a gate seat to go to the cafe).

## How a visit ended, for settlement.
enum Outcome { NONE, COMPLETE, SHORT }

var passenger := 0
var room := 0
## The room's type (RoomTypes: cafe, bar, restaurant or stall), kept so a visit
## whose room is removed is still paid by its own numbers. Not saved: derived
## from the room on load.
var venue: StringName = &"cafe"
var counter := 0
## The seat reserved when the visit was committed, "<table id>:<seat index>";
## empty for a walk-on visit.
var seat_key := ""
## Where the journey goes on after the visit: TO_SECURITY or TO_GATE.
var resume_stage: Passenger.Stage = Passenger.Stage.TO_GATE
## The last tick the guest may start to leave (CafeForecast.deadline()).
var deadline := 0
## When the order is ready, while it is being made.
var service_end := 0
## When a seated guest stands up, once seated.
var dwell_end := 0
var served := false
var outcome: Outcome = Outcome.NONE
## Set once the visit's money is in the wallet.
var settled := false
var amount := 0
## The reserved seat's descriptor (CafeLayout seat entry), derived again on load;
## empty for a walk-on visit.
var seat: Dictionary = {}


## Whether the guest buys at the counter and walks on with no seat (the
## grab-and-go stall): no seat is reserved, and no sit or stand phase follows.
func walk_on() -> bool:
	return RoomTypes.get_type(venue).walk_on
