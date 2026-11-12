class_name IncidentCards
extends Node
## The alert cards of the minor incidents (decision daily-incidents-small-ones-
## just-happen-with-a-card-and-a-cau): when an incident happens, a coral notice
## on the right rail (AlertStack.post_notice) names it and its cause, "Spill
## near Check-in" over "A passenger dropped a coffee. A cleaner will mop it
## up.", or "Hire a cleaner to clean it." while no cleaner is hired. The card
## stays until the incident is over or the player clicks it away; a minor never
## pauses the game. An accepted VIP gets one result card of the same look when
## it ends: made in a good mood (the bonus), made below the mood bar (no bonus)
## or missed (the rating penalty). The inspector's visit gets one when it
## resolves: passed (the money) or failed (the rating penalty). Notices are not
## saved, so after the rail resets (a load or a new world, reset_done) or the
## director loads (restored), every incident still active and every VIP or
## inspector result still kept is posted again.

## The incidents whose cards these are. A scene must set it; tests call bind().
@export var director: IncidentDirector

## The rail the cards go on; found through its group when unset.
var rail: AlertStack

var _watched_rail_id := 0


func _ready() -> void:
	if director == null:
		push_error("IncidentCards: no director set, so no incident card is shown")
		return
	bind(director)


func bind(with_director: IncidentDirector) -> void:
	director = with_director
	director.started.connect(_post)
	director.ended.connect(_on_ended)
	director.restored.connect(post_active)
	director.vip_resolved.connect(_post_result)
	director.inspector_resolved.connect(_post_result)


## The rail key of an incident's card.
static func key_of(incident: Dictionary) -> StringName:
	return StringName("incident_%d" % incident["id"])


## Posts the card of every active incident and the result card of every VIP
## that has its result again, replacing any still up.
func post_active() -> void:
	for incident in director.active_incidents():
		_post(incident)
	for incident in director.incidents():
		_post_result(incident)


## The result card of a finished VIP or inspector visit, told once when it ends
## (a coral card that stays until clicked away, like a minor's). Nothing for any
## other incident or a VIP dropped without a result.
func _post_result(incident: Dictionary) -> void:
	var words := IncidentCopy.vip_result(incident)
	if words.is_empty():
		words = IncidentCopy.inspector_result(incident)
	if words.is_empty():
		return
	var on := _rail()
	if on == null:
		push_warning("IncidentCards: no alert rail to show incident %d" % incident["id"])
		return
	var key := key_of(incident)
	var card := OfferPanel.coral_card(key, words["title"], words["detail"])
	card.name = "IncidentNotice_%s" % key
	on.post_notice(key, card, 0.0, words["title"], words["detail"])


func _post(incident: Dictionary) -> void:
	var on := _rail()
	if on == null:
		push_warning("IncidentCards: no alert rail to show incident %d" % incident["id"])
		return
	var key := key_of(incident)
	var title := IncidentCatalogue.card_title(incident)
	var detail := IncidentCatalogue.card_detail(incident, director.cleaner_hired())
	var card := OfferPanel.coral_card(key, title, detail)
	card.name = "IncidentNotice_%s" % key
	on.post_notice(key, card, 0.0, title, detail)


func _on_ended(incident: Dictionary) -> void:
	var on := _rail()
	if on != null:
		on.drop_notice(key_of(incident))


## The rail, found through its group the first time; its reset_done is
## followed so the cards come back after the rail drops them.
func _rail() -> AlertStack:
	if not is_instance_valid(rail):
		rail = get_tree().get_first_node_in_group(AlertStack.GROUP) as AlertStack
	if rail != null and rail.get_instance_id() != _watched_rail_id:
		_watched_rail_id = rail.get_instance_id()
		rail.reset_done.connect(post_active)
	return rail
