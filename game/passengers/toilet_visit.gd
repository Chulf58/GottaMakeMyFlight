class_name ToiletVisit
extends RefCounted
## One passenger's toilet visit, owned by ToiletSim. Plain data: the
## passenger's journey stage says which phase the visit is in (a gate
## STANDING_UP with a visit is a passenger getting up from a gate seat to go),
## and its stage tick when the timed phases end.

var passenger := 0
var room := 0
## The reserved stall's object id, held from the commit on, walk included.
var stall_id := 0
## Where the journey goes on after the visit: TO_SECURITY or TO_GATE.
var resume_stage: Passenger.Stage = Passenger.Stage.TO_GATE
## The last tick the passenger may start to leave the stall seat
## (VisitForecast.deadline() with ToiletSim.LEAVE_TICKS).
var deadline := 0
## The reserved stall's ToiletLayout entry, derived again on load.
var stall: Dictionary = {}
