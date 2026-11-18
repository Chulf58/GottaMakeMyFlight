class_name FollowInvite
extends RefCounted
## What the follow hint reads and does (decision follow-invitation-and-
## passenger-card-a-click-a-passenger-fir): the hint "Click a passenger to
## follow them to their flight" is due while a passenger is in the terminal and
## none is selected, and its Show me button selects one the way a click does.
## Nothing shows in the world until the player clicks (the calm view), so the
## button is the only help the hint gives.


## The two facts HintRules.causes() reads for the follow hint: "follow_ready"
## (a passenger is drawn in the terminal) and "followed" (a passenger or a
## vehicle is selected, which counts the hint as seen).
static func read(sim: PassengerSim, views: PassengerViews, landside: LandsideViews) -> Dictionary:
	var selected := views != null and views.selected_id != 0
	if landside != null and landside.selected_id != 0:
		selected = true
	return {"follow_ready": candidate(sim, views) != 0, "followed": selected}


## The passenger Show me picks, or 0 for none: the one with the longest way to
## go (the earliest stage, then the lowest id), so the player sees a whole trip.
static func candidate(sim: PassengerSim, views: PassengerViews) -> int:
	if sim == null or views == null:
		return 0
	var best := 0
	var best_stage := 0
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if p == null or p.is_done() or not views.shows(p):
			continue
		if best == 0 or p.stage < best_stage:
			best = id
			best_stage = p.stage
	return best


## Selects the candidate as a click on them does: their bubble shows (the
## selected passenger's is pinned) and the camera follows them, easing there.
## Returns the passenger's id, or 0 when nobody is in the terminal.
static func show_me(
	sim: PassengerSim, views: PassengerViews, camera: TycoonCamera, landside: LandsideViews
) -> int:
	var id := candidate(sim, views)
	if id == 0:
		return 0
	if landside != null:
		landside.select(0)
	views.selected_id = id
	if camera != null:
		camera.follow(views.follow_anchor)
	return id
