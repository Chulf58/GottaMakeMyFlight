class_name ShopVisit
extends RefCounted
## One passenger's kiosk visit, owned by ShopSim. Plain data: the passenger's
## journey stage says which phase the visit is in (a gate STANDING_UP with a
## visit is a passenger getting up from a gate seat to go), and its stage tick
## when the browse ends.

var passenger := 0
var room := 0
## The reserved browse slot: its display stand's object id and its index on
## the stand, held from the commit on, walk included.
var display := 0
var index := 0
## Where the journey goes on after the visit: TO_SECURITY or TO_GATE.
var resume_stage: Passenger.Stage = Passenger.Stage.TO_GATE
## The last tick the passenger may still be browsing
## (VisitForecast.deadline() from the slot, with no delay to leave).
var deadline := 0
## The reserved slot's ShopLayout entry, derived again on load.
var slot: Dictionary = {}


## The slot's key, "<display id>:<index>", as ShopLayout keys it.
func slot_key() -> String:
	return ShopLayout.key_of(display, index)
