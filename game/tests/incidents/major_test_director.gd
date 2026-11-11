class_name MajorTestDirector
extends IncidentDirector
## A director for tests of the major incident panel. No major kind exists yet
## (slice G), so this one keeps a scheduled record of a made-up kind, which
## IncidentDirector.present() then turns into an announcement or an offer. It
## needs no clock, flights or passengers: it never rolls or fires.

const KIND := "test_major"


func _ready() -> void:
	pass


## Keeps a scheduled record of KIND and returns its id.
func add_scheduled() -> int:
	var id := _next_id
	_next_id += 1
	(
		_incidents
		. append(
			{
				"id": id,
				"kind": KIND,
				"roll_day": 1,
				"state": IncidentCatalogue.SCHEDULED,
				"fire_tick": 0,
				"cell": IncidentSnapshot.NO_CELL,
				"mess_id": 0,
				"place": "",
				"outcome": "",
				"shown": false,
			}
		)
	)
	return id


## The copy the panel tests give the made-up kind (IncidentPanel.copy_for).
static func copy(kind: String) -> Dictionary:
	if kind != KIND:
		return {}
	return {
		"title": "Test visit",
		"body": "A test crew wants to use your airport.",
		"reward": "Two stars of goodwill.",
		"failure": "They leave and tell their friends.",
	}
