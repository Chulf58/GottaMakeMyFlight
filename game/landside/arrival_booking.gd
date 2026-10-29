class_name ArrivalBooking
extends RefCounted
## One future passenger on its way to the airport by car or taxi
## (ArrivalBookings). It is in exactly one state: awaiting its vehicle, in
## a vehicle, released (the passenger got out and became a Passenger record)
## or settled (its flight's doors closed while it was still on the road).
## Released and settled bookings are dropped at once, so a live or saved
## booking is always AWAITING or IN_VEHICLE.

enum State { AWAITING, IN_VEHICLE, RELEASED, SETTLED }

var id := 0
## The id of the party's first booking; a party shares one vehicle.
var party := 0
var flight_id := ""
## 0 or 1: which Toon character the passenger is drawn as.
var variant := 0
var arrival := ArrivalTypes.Type.TYPICAL
## When the party means to get out (at the curb or in the car park).
var unload_tick := 0
var kind := LandsideVehicle.Kind.CAR
var intent := LandsideVehicle.Intent.DROP
var state := State.AWAITING
## The vehicle while IN_VEHICLE, else 0.
var vehicle := 0
