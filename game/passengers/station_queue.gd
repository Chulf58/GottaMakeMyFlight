class_name StationQueue
extends RefCounted
## The external queue rules of a desk or security station, on PassengerSim's
## {"lane", "holding"} record: shared with SecurityForecast's replay, so the
## forecast moves a queue as the sim does.


## Moves passengers from the holding list into free places at the back of
## the lane, first come first; returns them.
static func promote(queue: Dictionary, cells: Array) -> Array[int]:
	var moved: Array[int] = []
	var lane: Array = queue["lane"]
	var holding: Array = queue["holding"]
	while not holding.is_empty() and lane.size() < cells.size():
		var id: int = holding.pop_front()
		lane.append(id)
		moved.append(id)
	return moved


## Puts passenger `id` at the back of the lane, or in the holding list when
## the lane is full; returns whether it got a lane place.
static func join(queue: Dictionary, cells: Array, id: int) -> bool:
	if (queue["lane"] as Array).size() < cells.size():
		(queue["lane"] as Array).append(id)
		return true
	(queue["holding"] as Array).append(id)
	return false
