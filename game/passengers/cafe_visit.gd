class_name CafeVisit
extends RefCounted
## One passenger's cafe visit, owned by CafeSim. Plain data: the passenger's
## journey stage says which phase the visit is in (a gate STANDING_UP with a
## visit is a guest getting up from a gate seat to go to the cafe).

## How a visit ended, for settlement.
enum Outcome { NONE, COMPLETE, SHORT }

var passenger := 0
var room := 0
var counter := 0
## The seat reserved when the visit was committed, "<table id>:<seat index>".
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
## The reserved seat's descriptor (CafeLayout seat entry), derived again on load.
var seat: Dictionary = {}
