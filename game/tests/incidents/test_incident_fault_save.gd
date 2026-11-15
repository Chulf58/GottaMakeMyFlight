class_name TestIncidentFaultSave
extends GdUnitTestSuite
## A true SaveGame round trip of an active scanner fault on the real main
## scene (decision scanner-fault-incident-design-stationfaults-beside-
## stationcl): the staff part keeps the fault and its repair tick (staff save
## version 6), the incidents part keeps its plan (version 5), the loaded game
## reopens the scanner on the same tick as the unbroken one, and a save whose
## two copies of the repair tick disagree is refused. One boot of main.tscn.

const SEED := 4_120_771
const PLAY_TICKS := 200
const REPAIR_IN := 450

var _path := SaveTestKit.run_path("test_incident_fault_save")
var _main: Node
var _save: SaveGame
var _director: IncidentDirector
var _clock: SimClock
var _staff: StaffSim
var _sim: PassengerSim


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	_director = _main.get_node("IncidentDirector")
	_clock = _main.get_node("SimClock")
	_staff = _main.get_node("Staff")
	_sim = _main.get_node("PassengerSim")
	SaveTestKit.start_airport(_main)
	for i in PLAY_TICKS:
		SaveTestKit.step(_main)


func after() -> void:
	_main.free()
	for file in [_path, _path + ".tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


## Faults the first scanner until `repair` and puts its active incident in
## through the director's own load, as a fire leaves them. Returns the station.
func _put_in_fault(repair: int) -> int:
	var station: int = _sim.layout.scanners[0]
	assert_bool(_staff.is_open(station)).is_true()
	assert_bool(_staff.faults.add(station, repair)).is_true()
	var data := _director.to_snapshot()
	var id: int = data["next_id"]
	data["next_id"] = id + 1
	(
		(data["incidents"] as Array)
		. append(
			{
				"id": id,
				"kind": IncidentCatalogue.FAULT,
				"roll_day": GameCalendar.day_of(_clock.tick),
				"state": IncidentCatalogue.ACTIVE,
				"fire_tick": _clock.tick,
				"cell": [-1, -1],
				"mess_id": 0,
				"place": "",
				"outcome": "",
				"shown": false,
				"plan": {"station": station, "repair_tick": repair},
			}
		)
	)
	assert_bool(_director.from_snapshot(data)).is_true()
	return station


## Steps until the scanner opens or `last` passes; the tick it opened, or -1.
func _opens_on(station: int, last: int) -> int:
	while _clock.tick < last:
		SaveTestKit.step(_main)
		if _staff.is_open(station):
			return _clock.tick
	return -1


func test_an_active_fault_round_trips_and_reopens_on_the_same_tick() -> void:
	var repair := _clock.tick + REPAIR_IN
	var station := _put_in_fault(repair)
	assert_bool(_save.save_to_file(_path)).is_true()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_path))
	print(
		(
			"saved staff v%s faults %s, incidents v%s"
			% [
				data["staff"]["save_version"],
				data["staff"]["faults"],
				data["incidents"]["save_version"]
			]
		)
	)
	assert_int(int(data["staff"]["save_version"])).is_equal(6)
	assert_int(int(data["incidents"]["save_version"])).is_equal(5)
	var unbroken := _opens_on(station, repair + 20)
	var ended_unbroken: String = _director.incidents().back()["state"]
	assert_bool(_save.load_from_file(_path)).is_true()
	assert_int(_staff.faults.repair_tick(station)).is_equal(repair)
	assert_str(_staff.closures.status_text(station)).not_contains("Closed by you")
	var plan: Dictionary = _director.active_incidents().back()["plan"]
	assert_int(typeof(plan["repair_tick"])).is_equal(TYPE_INT)
	assert_int(plan["repair_tick"]).is_equal(repair)
	var loaded := _opens_on(station, repair + 20)
	print("repair %d: opened on %d unbroken, %d after the load" % [repair, unbroken, loaded])
	assert_int(unbroken).is_equal(repair)
	assert_int(loaded).is_equal(repair)
	assert_str(ended_unbroken).is_equal(IncidentCatalogue.DONE)
	assert_str(_director.incidents().back()["state"]).is_equal(IncidentCatalogue.DONE)


func test_a_save_whose_fault_copies_disagree_is_refused() -> void:
	var repair := _clock.tick + REPAIR_IN
	var station := _put_in_fault(repair)
	var good := _save.snapshot()
	var data: Dictionary = JSON.parse_string(JSON.stringify(good))
	data["staff"]["faults"] = [[station, repair + 1]]
	var refused := not _save.load_world(data)
	print("refused %s: %s" % [refused, _save.message_text()])
	assert_bool(refused).is_true()
	assert_str(_save.message_text()).contains("is not saved faulted until %d" % repair)
	# The control: the save as written loads.
	assert_bool(_save.load_world(JSON.parse_string(JSON.stringify(good)))).is_true()
	assert_int(_staff.faults.repair_tick(station)).is_equal(repair)
	_opens_on(station, repair + 1)
