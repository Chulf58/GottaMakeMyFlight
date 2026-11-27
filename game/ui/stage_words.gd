class_name StageWords
extends RefCounted
## What a followed passenger is doing, in the player's words: the stage text on
## the follow line (PassengerHud.follow_text). Static code cannot call tr(), so
## the inner Words class does; each line is one whole sentence with a named
## {placeholder} for a shop or room, in the "passenger activity" context
## (decision translation-format-po-gettext-files-with-tr-and-tr-n-for-all).
## A shop's name comes from ShopSim.store_name(), which lower-cases each word
## unless it is all capitals, so its msgid is looked up in the "room name,
## mid-sentence" context DisplayWords keeps; the one capitalised word is "ATM".

const ACTIVITY_CONTEXT := "passenger activity"
const SHOP_CONTEXT := "room name, mid-sentence"

static var _words := Words.new()


## What `p` is doing: its stage's text, naming the shop it is visiting when it
## has a visit under way (store_name() is empty when there is no visit or its
## room is gone, so the stage text is there below), or the venue's words for a
## visit to the stall, bar or restaurant.
static func text(passenger_sim: PassengerSim, p: Passenger) -> String:
	var cafe_visit := passenger_sim.cafes.visit_of(p.id)
	if cafe_visit != null:
		var venue := _words.venue(cafe_visit.venue, p.stage)
		if venue != "":
			return venue
	if p.stage == Passenger.Stage.SHOP_WALK or p.stage == Passenger.Stage.SHOP_BROWSE:
		var store := passenger_sim.shops.store_name(p.id)
		if store != "":
			var type := passenger_sim.shops.visit_type(p.id)
			var shop := TranslationServer.translate(store, SHOP_CONTEXT)
			if type.activity and p.stage == Passenger.Stage.SHOP_BROWSE:
				return _words.activity(type.id, shop)
			return _words.shop(p.stage, shop, type.relieves_boredom)
	return _words.stage(p.stage)


class Words:
	extends RefCounted

	## The one shop name that is not lower case (ShopSim.store_name()).
	func shop_names() -> PackedStringArray:
		return PackedStringArray([tr("ATM", "room name, mid-sentence")])

	func shop(stage: int, shop_name: String, relieves_boredom: bool) -> String:
		var values := {"shop": shop_name}
		if stage == Passenger.Stage.SHOP_WALK:
			return tr("Heading to the {shop}", "passenger activity").format(values)
		if relieves_boredom:
			return tr("Browsing at the {shop}", "passenger activity").format(values)
		return tr("Using the {shop}", "passenger activity").format(values)

	func activity(room_type: StringName, shop_name: String) -> String:
		var values := {"shop": shop_name}
		match room_type:
			&"play_area":
				return tr("Playing in the {shop}", "passenger activity").format(values)
			&"lounge":
				return tr("Relaxing in the {shop}", "passenger activity").format(values)
			&"shower":
				return tr("Using the {shop}", "passenger activity").format(values)
			&"nap_pod":
				return tr("Resting in the {shop}", "passenger activity").format(values)
		return tr("Browsing at the {shop}", "passenger activity").format(values)

	## The venue's words for a cafe stage, or "" when the venue has none for it.
	func venue(venue_id: StringName, stage: int) -> String:
		match venue_id:
			&"stall":
				return _stall(stage)
			&"bar":
				return _bar(stage)
			&"restaurant":
				return _restaurant(stage)
		return ""

	func _stall(stage: int) -> String:
		match stage:
			Passenger.Stage.CAFE_WALK:
				return tr("Heading to the food stall", "passenger activity")
			Passenger.Stage.CAFE_QUEUE:
				return tr("Queuing at the food stall", "passenger activity")
			Passenger.Stage.CAFE_ORDER:
				return tr("Grabbing a snack", "passenger activity")
		return ""

	func _bar(stage: int) -> String:
		var text := ""
		match stage:
			Passenger.Stage.CAFE_WALK:
				text = tr("Heading to the bar", "passenger activity")
			Passenger.Stage.CAFE_QUEUE:
				text = tr("Queuing at the bar", "passenger activity")
			Passenger.Stage.CAFE_ORDER:
				text = tr("Ordering a drink", "passenger activity")
			Passenger.Stage.CAFE_TO_SEAT:
				text = tr("Taking a drink to a seat", "passenger activity")
			Passenger.Stage.CAFE_SITTING_DOWN:
				text = tr("Sitting down at the bar", "passenger activity")
			Passenger.Stage.CAFE_SEATED:
				text = tr("Having a drink", "passenger activity")
			Passenger.Stage.CAFE_STANDING_UP:
				text = tr("Leaving the bar", "passenger activity")
		return text

	func _restaurant(stage: int) -> String:
		var text := ""
		match stage:
			Passenger.Stage.CAFE_WALK:
				text = tr("Heading to the restaurant", "passenger activity")
			Passenger.Stage.CAFE_QUEUE:
				text = tr("Queuing at the restaurant", "passenger activity")
			Passenger.Stage.CAFE_ORDER:
				text = tr("Ordering a meal", "passenger activity")
			Passenger.Stage.CAFE_TO_SEAT:
				text = tr("Taking a meal to a table", "passenger activity")
			Passenger.Stage.CAFE_SITTING_DOWN:
				text = tr("Sitting down at the restaurant", "passenger activity")
			Passenger.Stage.CAFE_SEATED:
				text = tr("Having a meal", "passenger activity")
			Passenger.Stage.CAFE_STANDING_UP:
				text = tr("Leaving the restaurant", "passenger activity")
		return text

	func stage(stage_id: int) -> String:
		var text := ""
		match stage_id:
			Passenger.Stage.SPAWNED:
				text = tr("Arriving", "passenger activity")
			Passenger.Stage.TO_CHECKIN:
				text = tr("Heading to check-in", "passenger activity")
			Passenger.Stage.CHECKIN_QUEUE:
				text = tr("Queuing for check-in", "passenger activity")
			Passenger.Stage.CHECKIN:
				text = tr("Checking in", "passenger activity")
			Passenger.Stage.TO_SECURITY:
				text = tr("Heading to security", "passenger activity")
			Passenger.Stage.SECURITY_QUEUE:
				text = tr("Queuing for security", "passenger activity")
			Passenger.Stage.SECURITY:
				text = tr("Going through security", "passenger activity")
			Passenger.Stage.TO_GATE:
				text = tr("Heading to the gate", "passenger activity")
			Passenger.Stage.SITTING_DOWN:
				text = tr("Sitting down", "passenger activity")
			Passenger.Stage.SEATED:
				text = tr("Waiting at the gate", "passenger activity")
			Passenger.Stage.STANDING:
				text = tr("Standing at the gate", "passenger activity")
			Passenger.Stage.STANDING_UP:
				text = tr("Getting up to board", "passenger activity")
			Passenger.Stage.TO_EXIT:
				text = tr("Heading to the exit", "passenger activity")
			Passenger.Stage.APRON:
				text = tr("Walking to the plane", "passenger activity")
			Passenger.Stage.ON_BUS:
				text = tr("On the shuttle bus", "passenger activity")
			Passenger.Stage.DEPLANING:
				text = tr("Deplaning", "passenger activity")
			Passenger.Stage.TO_AIRSIDE_EXIT:
				text = tr("Leaving airside", "passenger activity")
			Passenger.Stage.TO_ROAD_EXIT:
				text = tr("Leaving the terminal", "passenger activity")
			Passenger.Stage.TO_PARKED_CAR:
				text = tr("Walking to parked car", "passenger activity")
			Passenger.Stage.TO_CURB_PICKUP:
				text = tr("Walking to curb pickup", "passenger activity")
			Passenger.Stage.WAIT_CURB_PICKUP:
				text = tr("Waiting for pickup taxi", "passenger activity")
			Passenger.Stage.TO_CLAIM:
				text = tr("Walking to baggage claim", "passenger activity")
			Passenger.Stage.AT_CLAIM:
				text = tr("Waiting at baggage claim", "passenger activity")
			Passenger.Stage.MADE:
				text = tr("Boarded", "passenger activity")
			Passenger.Stage.MISSED:
				text = tr("Missed the flight", "passenger activity")
		if text == "":
			text = _facility_stage(stage_id)
		return text

	func _facility_stage(stage_id: int) -> String:
		var text := ""
		match stage_id:
			Passenger.Stage.CAFE_WALK:
				text = tr("Heading to the cafe", "passenger activity")
			Passenger.Stage.CAFE_QUEUE:
				text = tr("Queuing at the cafe", "passenger activity")
			Passenger.Stage.CAFE_ORDER:
				text = tr("Ordering a coffee", "passenger activity")
			Passenger.Stage.CAFE_TO_SEAT:
				text = tr("Taking a coffee to a seat", "passenger activity")
			Passenger.Stage.CAFE_SITTING_DOWN:
				text = tr("Sitting down at the cafe", "passenger activity")
			Passenger.Stage.CAFE_SEATED:
				text = tr("Having a coffee", "passenger activity")
			Passenger.Stage.CAFE_STANDING_UP:
				text = tr("Leaving the cafe", "passenger activity")
			Passenger.Stage.TOILET_WALK:
				text = tr("Heading to the toilet", "passenger activity")
			Passenger.Stage.TOILET_ENTER:
				text = tr("Going into a toilet stall", "passenger activity")
			Passenger.Stage.TOILET_SITTING_DOWN:
				text = tr("In a toilet stall", "passenger activity")
			Passenger.Stage.TOILET_USE:
				text = tr("In a toilet stall", "passenger activity")
			Passenger.Stage.TOILET_STANDING_UP:
				text = tr("In a toilet stall", "passenger activity")
			Passenger.Stage.TOILET_EXIT:
				text = tr("Leaving the toilet", "passenger activity")
			Passenger.Stage.SHOP_WALK:
				text = tr("Heading to a shop", "passenger activity")
			Passenger.Stage.SHOP_BROWSE:
				text = tr("Browsing at a shop", "passenger activity")
		if text == "":
			push_error("StageWords: no text for stage %d" % stage_id)
		return text
