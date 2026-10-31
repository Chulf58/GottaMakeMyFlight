class_name ActivityCarry
extends RefCounted
## CarryOnProps' part for an activity visitor's floor bags (decision
## activity-poses-sit-on-the-lounge-sofa-recline-in-the-nap-pod): they stand at
## spots fixed in the world (SecurityLooks.activity_floor) while the body steps
## onto a seat and off, or into the shower and out, and a pick-up starts from
## where the bag stands, not from a spot held in the stepping body's frame
## (from_world, as for a tray or a toilet stall). Kept out of CarryOnProps,
## which is at the line cap.
##
## The record keeps the visit's spots ("fixed_kept") past the tick the visit
## ends, so a pick-up stamped as a visit is cut short (the piece removed, the
## stay ended early) still starts fixed; they go once no bag's stamped home is
## the floor. Nothing here outlives a record: a load starts every record over
## (PassengerViews.snap, CarryOnProps.release), and a bag of a new record has
## no move to start.


## Updates `held` (CarryOnProps' record of `p`, `count` bags) for this tick:
## "fixed_floor" the spots of the visit now (empty when not on one), and
## "fixed_kept" the last non-empty spots until no bag rests on them.
static func sync(held: Dictionary, sim: PassengerSim, p: Passenger, count: int) -> void:
	var spots := SecurityLooks.activity_floor(sim, p, count)
	held["fixed_floor"] = spots
	if not spots.is_empty():
		held["fixed_kept"] = spots
		return
	for bag: Dictionary in held.get("bags", []):
		var home: int = bag.get("home", -1)
		if home >= 0 and home / 4 == SecurityLooks.Home.FLOOR:
			return
	held.erase("fixed_kept")


## Floor bag `i` of `count` of record `held` (bounds `box`, drawn at
## `scale_by`) as placed now: at its stall spot in a toilet stall
## (StallCarry.floor_place), at its fixed spot on an activity visit
## (SecurityLooks.on_floor); empty when neither, for the passenger's frame.
static func fixed_place(
	held: Dictionary, box: AABB, scale_by: float, i: int, count: int
) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if not (held.get("stall", {}) as Dictionary).is_empty():
		out.append(StallCarry.floor_place(held["stall"], box, scale_by, i, count))
	elif not (held.get("fixed_floor", []) as Array).is_empty():
		out.append(SecurityLooks.on_floor(held["fixed_floor"][i], box, scale_by))
	return out


## Whether a move stamped from place `at` (a CarryOnProps place, home * 4 + ...)
## of a bag in record `held` starts from an activity visit's fixed floor spot.
static func fixed_start(held: Dictionary, at: int) -> bool:
	if at < 0 or at / 4 != SecurityLooks.Home.FLOOR:
		return false
	return not (held.get("fixed_kept", []) as Array).is_empty()
