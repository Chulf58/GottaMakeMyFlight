class_name TestIncidentMain
extends GdUnitTestSuite
## The IncidentDirector on the real main scene: wired to the clock, the
## quiet-night stop and the save; off in a world no new-game dialog made; a
## scheduled spill fires at its saved tick at a check-in or security spot and
## posts its card on the rail; a save taken between the roll and the fire plays
## on exactly like the unbroken run (SaveTestKit checksum); the card comes back
## after a load; and a save without the part, or with a malformed one, is
## refused at staging with nothing installed. One boot of main.tscn.

const SEED := 2_611_311

var _path := SaveTestKit.run_path("test_incident_main")
var _main: Node
var _save: SaveGame
var _director: IncidentDirector
var _clock: SimClock
var _rail: AlertStack


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	_director = _main.get_node("IncidentDirector")
	_clock = _main.get_node("SimClock")
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	SaveTestKit.step(_main)
	_rail = get_tree().get_first_node_in_group(AlertStack.GROUP) as AlertStack


func after() -> void:
	_main.free()
	for file in [_path, _path + ".tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


## A scheduled spill as a roll leaves it, `ahead` ticks from now, put in
## through the director's own load. Returns its card's rail key.
func _schedule_spill(ahead: int) -> StringName:
	var data := _director.to_snapshot()
	var id: int = data["next_id"]
	data["next_id"] = id + 1
	(
		(data["incidents"] as Array)
		. append(
			{
				"id": id,
				"kind": IncidentCatalogue.SPILL,
				"roll_day": GameCalendar.day_of(_clock.tick),
				"state": IncidentCatalogue.SCHEDULED,
				"fire_tick": _clock.tick + ahead,
				"cell": [-1, -1],
				"mess_id": 0,
				"place": "",
				"outcome": "",
				"shown": false,
				"plan": {},
			}
		)
	)
	assert_bool(_director.from_snapshot(data)).is_true()
	return IncidentCards.key_of({"id": id})


func _steps(count: int) -> void:
	for i in count:
		SaveTestKit.step(_main)


func _card_words(key: StringName) -> String:
	var card := _rail.notice_card(key)
	if card == null:
		return ""
	var words := PackedStringArray()
	for label in card.find_children("*", "Label", true, false):
		words.append((label as Label).text)
	return " / ".join(words)


func test_the_scene_wires_the_director_and_starts_with_incidents_off() -> void:
	var quiet := _main.get_node("QuietNight") as QuietNight
	assert_object(quiet.incidents).is_same(_director)
	assert_object(_save.incidents).is_same(_director)
	assert_object((_main.get_node("IncidentCards") as IncidentCards).director).is_same(_director)
	assert_object(_director.passengers).is_same(_main.get_node("PassengerSim"))
	assert_bool(_director.is_enabled()).is_false()
	assert_bool(_save.snapshot().has("incidents")).is_true()
	assert_object(_rail).is_not_null()


func test_the_scene_wires_the_major_panel_to_the_director_clock_and_save() -> void:
	var panel := _main.get_node("IncidentPanel") as IncidentPanel
	assert_object(panel.director).is_same(_director)
	assert_object(panel.clock).is_same(_clock)
	assert_object(panel.save_game).is_same(_save)
	assert_bool(panel.is_open()).is_false()


func test_a_spill_fires_at_its_tick_and_posts_a_card_naming_the_cause() -> void:
	var places := _director.spill_places()
	print("places: %s" % [places])
	assert_int(places.size()).is_greater(0)
	var messes := (_main.get_node("PassengerSim") as PassengerSim).messes
	var before_count := messes.mess_count()
	var key := _schedule_spill(5)
	var fire: int = _director.incidents().back()["fire_tick"]
	_steps(4)
	assert_int(messes.mess_count()).is_equal(before_count)
	assert_object(_rail.notice_card(key)).is_null()
	_steps(1)
	assert_int(_clock.tick).is_equal(fire)
	var active := _director.active_incidents()
	assert_int(active.size()).is_equal(1)
	assert_int(messes.mess_count()).is_equal(before_count + 1)
	assert_int(messes.get_mess(active[0]["mess_id"])["kind"]).is_equal(MessSim.Kind.SPILL)
	var words := _card_words(key)
	print("card: %s" % words)
	assert_str(words).contains("Spill near %s" % active[0]["place"])
	assert_str(words).contains("A passenger dropped a coffee.")
	assert_str(words).contains("Hire a cleaner to clean it.")
	# The card comes back after the rail resets, as it does after a load.
	_rail.reset()
	assert_str(_card_words(key)).contains("Spill near")
	# Cleaned: the incident ends and its card goes.
	assert_bool(messes.clean(active[0]["mess_id"])).is_true()
	_steps(1)
	assert_int(_director.active_incidents().size()).is_equal(0)
	assert_object(_rail.notice_card(key)).is_null()


func test_a_save_between_the_roll_and_the_fire_plays_on_identically() -> void:
	var key := _schedule_spill(30)
	var fire: int = _director.incidents().back()["fire_tick"]
	_steps(10)
	assert_bool(_save.save_to_file(_path)).is_true()
	var saved_tick := _clock.tick
	_steps(40)
	var unbroken := SaveTestKit.checksum(_main)
	var fired: Dictionary = _director.incidents().back()
	print("unbroken at %d: %s" % [_clock.tick, fired])
	assert_int(_clock.tick).is_greater(fire)
	assert_str(fired["state"]).is_equal(IncidentCatalogue.ACTIVE)
	assert_bool(_save.load_from_file(_path)).is_true()
	assert_int(_clock.tick).is_equal(saved_tick)
	assert_str(_director.incidents().back()["state"]).is_equal(IncidentCatalogue.SCHEDULED)
	_steps(40)
	print("replayed at %d: %s" % [_clock.tick, _director.incidents().back()])
	assert_str(SaveTestKit.checksum(_main)).is_equal(unbroken)
	assert_str(_card_words(key)).contains("Spill near")
	# Saved while active, the card is posted again by the load alone.
	assert_bool(_save.save_to_file(_path)).is_true()
	assert_bool(_save.load_from_file(_path)).is_true()
	assert_str(_card_words(key)).contains("Spill near")


func test_a_save_without_the_incidents_part_is_refused_and_changes_nothing() -> void:
	_steps(1)
	var data: Dictionary = JSON.parse_string(JSON.stringify(_save.snapshot()))
	data.erase("incidents")
	_assert_refused(data, "missing key 'incidents'")


func test_a_malformed_incidents_part_is_refused_at_staging_and_changes_nothing() -> void:
	_steps(1)
	var data: Dictionary = JSON.parse_string(JSON.stringify(_save.snapshot()))
	data["incidents"]["enabled"] = "yes"
	_assert_refused(data, "incidents: enabled must be a bool")


## An active spill must name a SPILL mess of the same save at its own cell
## (IncidentSnapshot.links_problem at staging): a missing mess, a mess of
## another kind or another cell refuses the whole load and installs nothing;
## the unchanged save loads.
func test_an_active_spill_without_its_mess_in_the_save_is_refused() -> void:
	_schedule_spill(2)
	_steps(2)
	var active := _director.active_incidents()
	assert_int(active.size()).is_greater(0)
	var spill: Dictionary = active.back()
	var good: Dictionary = JSON.parse_string(JSON.stringify(_save.snapshot()))
	var at := -1
	var saved_incidents: Array = good["incidents"]["incidents"]
	for index in saved_incidents.size():
		if int(saved_incidents[index]["id"]) == spill["id"]:
			at = index
	assert_int(at).is_greater_equal(0)
	var no_mess := good.duplicate(true)
	no_mess["incidents"]["incidents"][at]["mess_id"] = 999
	_assert_refused(no_mess, "no mess 999")
	var litter := good.duplicate(true)
	for mess: Dictionary in litter["messes"]["messes"]:
		if int(mess["id"]) == spill["mess_id"]:
			mess["kind"] = MessSim.Kind.LITTER
	_assert_refused(litter, "not a spill")
	var moved := good.duplicate(true)
	var cell: Vector2i = spill["cell"]
	moved["incidents"]["incidents"][at]["cell"] = [cell.x + 1, cell.y]
	_assert_refused(moved, "not at the incident's cell")
	# The control: the save as taken loads.
	assert_bool(_save.load_world(good)).is_true()
	assert_int(_director.active_incidents().size()).is_equal(active.size())


## Moved on from the save first, so any part installed from it would show.
func _assert_refused(data: Dictionary, reason: String) -> void:
	_steps(3)
	var before_sum := SaveTestKit.checksum(_main)
	var tick := _clock.tick
	assert_bool(_save.load_world(data)).is_false()
	print("refused: %s" % _save.message_text())
	assert_str(_save.message_text()).contains(reason)
	assert_int(_clock.tick).is_equal(tick)
	assert_str(SaveTestKit.checksum(_main)).is_equal(before_sum)
