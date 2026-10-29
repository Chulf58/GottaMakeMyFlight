class_name LandsideVehicle
extends RefCounted
## A car or taxi on the landside (LandsideSim), as plain data: which lane it
## is on and how far along it in whole mm, or which berth or parking slot it
## stands in.

enum Kind { TAXI, CAR }
## DROP: let the passengers out at the curb. PARK: park in a car park; a car
## that finds no free space turns into DROP before the turn.
enum Intent { DROP, PARK }
## DRIVE and QUEUE are on road_in or a lot's access lane (QUEUE when it
## could not move a full step); DWELL is in a curb berth; PARKED in a slot;
## LEAVE on road_out or a lot's exit lane.
enum Stage { DRIVE, QUEUE, DWELL, LEAVE, PARKED }
enum Lane { ROAD_IN, ACCESS, ROAD_OUT, LOT_EXIT, BERTH, SLOT }

const MAX_PARTY := {Kind.TAXI: 2, Kind.CAR: 4}

var id := 0
var kind := Kind.CAR
var intent := Intent.DROP
## The bookings still aboard, in booking id order.
var bookings: Array[int] = []
var lane := Lane.ROAD_IN
## Along the lane, in mm. Below 0 on road_in: waiting off the map to enter.
var pos_mm := 0
var stage := Stage.DRIVE
## The berth (BERTH) or the reserved or held slot (ACCESS, SLOT) index, else -1.
var stop := -1
## The lot spot (ACCESS, SLOT, LOT_EXIT) index, else -1.
var lot := -1
## The tick the stage last changed; in DWELL the tick its passengers got out.
var stage_tick := 0
## PARKED: the absolute tick the car leaves; else 0.
var leave_tick := 0
