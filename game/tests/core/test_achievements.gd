class_name TestAchievements
extends GdUnitTestSuite
## Stage 3 Slice S3-P4b: SteamBridge autoload, 22-achievement Career tracker,
## `-s` profile shield, Auto-Cloud path contract, SaveGame.ensure_achievements()
## live wiring + load suppression, and non-blocking AchievementToast.

const PROFILE_TAG := "achievements_profile"

var _temp_files: Array[String] = []
var _saved_protected_path := Achievements.DEFAULT_PROFILE_PATH


class _MockSteam:
	extends RefCounted
	var running := true
	var cloud_account := true
	var cloud_app := true
	var set_calls: Array[String] = []
	var store_calls := 0

	# gdlint:ignore = function-name
	func isSteamRunning() -> bool:
		return running

	# gdlint:ignore = function-name
	func isCloudEnabledForAccount() -> bool:
		return cloud_account

	# gdlint:ignore = function-name
	func isCloudEnabledForApp() -> bool:
		return cloud_app

	# gdlint:ignore = function-name
	func setAchievement(api_id: String) -> bool:
		set_calls.append(api_id)
		return true

	# gdlint:ignore = function-name
	func storeStats() -> bool:
		store_calls += 1
		return true


func before_test() -> void:
	_saved_protected_path = Achievements.protected_path
	SteamBridge.set_mock_steam(null)


func after_test() -> void:
	SteamBridge.set_mock_steam(null)
	Achievements.protected_path = _saved_protected_path
	for path in _temp_files:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	_temp_files.clear()


func _temp_profile(tag: String) -> String:
	var path := SaveTestKit.run_path(tag)
	_temp_files.append(path)
	return path


func _new_tracker(path: String) -> Achievements:
	var ach: Achievements = auto_free(Achievements.new())
	ach.profile_path = path
	return ach


func _build_prestige_5_lounge(grid: BuildGrid) -> void:
	for y in range(2, 12):
		for x in range(2, 12):
			var floor_edit := BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1)
			assert_bool(grid.apply(floor_edit).ok).is_true()
	assert_bool(grid.apply(BuildEdit.place_room(Rect2i(2, 2, 8, 8), &"cafe")).ok).is_true()
	# 64 - 9 = 55 extra cells -> 14 size pts + 4 trophies (64) + fountain (18) + statue (14) >= 110.
	assert_bool(grid.apply(BuildEdit.place_object(&"award_trophy", Vector2i(3, 3), 0)).ok).is_true()
	assert_bool(grid.apply(BuildEdit.place_object(&"award_trophy", Vector2i(4, 3), 0)).ok).is_true()
	assert_bool(grid.apply(BuildEdit.place_object(&"award_trophy", Vector2i(5, 3), 0)).ok).is_true()
	assert_bool(grid.apply(BuildEdit.place_object(&"award_trophy", Vector2i(6, 3), 0)).ok).is_true()
	(
		assert_bool(grid.apply(BuildEdit.place_object(&"fountain_indoor", Vector2i(3, 5), 0)).ok)
		. is_true()
	)
	(
		assert_bool(grid.apply(BuildEdit.place_object(&"statue_indoor", Vector2i(6, 5), 0)).ok)
		. is_true()
	)


func _build_security_lane(grid: BuildGrid) -> void:
	for y in range(2, 16):
		for x in range(12, 20):
			var floor_edit := BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1)
			assert_bool(grid.apply(floor_edit).ok).is_true()
	for edit in SecurityLaneStamp.edits_for(Vector2i(15, 10), 0):
		assert_bool(grid.apply(edit).ok).is_true()


func _build_ready_bag_room(build_mode: BuildMode) -> void:
	(
		assert_bool(
			build_mode.grid.apply(BuildEdit.place_room(Rect2i(12, 2, 4, 4), &"bag_room")).ok
		)
		. is_true()
	)
	for edit: BuildEdit in (
		DoorPlacement
		. edits_for(
			build_mode.grid,
			BuildEdit.place_object(BuildCatalog.BAY_DOOR_ID, Vector2i(13, 2), 0),
		)
	):
		assert_bool(build_mode.grid.apply(edit).ok).is_true()
	assert_bool(build_mode.lay_belt(Vector2i(11, 3), Vector2i(14, 3)).ok).is_true()


func test_catalog_has_22_unique_career_only_achievements() -> void:
	var ach := _new_tracker(_temp_profile(PROFILE_TAG))
	assert_int(ach.total_count()).is_equal(22)
	assert_int(Achievements.CATALOG.size()).is_equal(22)
	var seen := {}
	for entry in Achievements.CATALOG:
		var cid := str(entry.get("id", ""))
		var title := str(entry.get("title", ""))
		var desc := str(entry.get("description", ""))
		assert_str(cid).is_not_empty()
		assert_str(title).is_not_empty()
		assert_str(desc).is_not_empty()
		assert_bool(bool(entry.get("career_only", false))).is_true()
		assert_bool(seen.has(cid)).is_false()
		seen[cid] = true
	assert_bool(Achievements.has_id("OPEN_FOR_BUSINESS")).is_true()
	assert_bool(Achievements.has_id("AIRPORT_OF_YEAR")).is_true()
	assert_bool(Achievements.has_id("NOT_AN_ACHIEVEMENT")).is_false()


func test_career_unlock_is_idempotent_persists_and_rejects_unknown_id() -> void:
	var path := _temp_profile(PROFILE_TAG)
	var ach := _new_tracker(path)
	var events: Array[Array] = []
	ach.unlocked.connect(
		func(id: String, title: String, desc: String) -> void: events.append([id, title, desc])
	)

	assert_bool(ach.unlock("OPEN_FOR_BUSINESS", true)).is_true()
	assert_bool(ach.unlock("OPEN_FOR_BUSINESS", true)).is_false()
	assert_bool(ach.unlock("FIRST_FLIGHT", true)).is_true()
	assert_int(ach.unlocked_count()).is_equal(2)
	assert_array(ach.unlocked_ids()).is_equal(["OPEN_FOR_BUSINESS", "FIRST_FLIGHT"])
	assert_int(events.size()).is_equal(2)
	assert_str(events[0][0]).is_equal("OPEN_FOR_BUSINESS")

	await (
		assert_error(func() -> void: assert_bool(ach.unlock("NO_SUCH_ACH", true)).is_false())
		. is_push_error("Achievements.unlock: unknown achievement id 'NO_SUCH_ACH'")
	)
	assert_int(ach.unlocked_count()).is_equal(2)

	var reloaded := _new_tracker(path)
	assert_bool(reloaded.load_profile()).is_true()
	assert_int(reloaded.unlocked_count()).is_equal(2)
	assert_bool(reloaded.is_unlocked("OPEN_FOR_BUSINESS")).is_true()
	assert_bool(reloaded.is_unlocked("FIRST_FLIGHT")).is_true()


func test_default_profile_is_shielded_in_script_runs() -> void:
	assert_str(Achievements.protected_path).is_equal(Achievements.DEFAULT_PROFILE_PATH)
	assert_bool(Achievements.is_shielded(Achievements.DEFAULT_PROFILE_PATH)).is_true()
	var explicit := _temp_profile("explicit_shield")
	assert_bool(Achievements.is_shielded(explicit)).is_false()

	var seeded_path := _temp_profile("seeded_protected")
	var seed_ach := _new_tracker(seeded_path)
	assert_bool(seed_ach.unlock("OPEN_FOR_BUSINESS", true)).is_true()
	var before_bytes := FileAccess.get_file_as_bytes(seeded_path)
	assert_int(before_bytes.size()).is_greater(0)

	Achievements.protected_path = seeded_path
	assert_bool(Achievements.is_shielded(seeded_path)).is_true()
	var reader := _new_tracker(seeded_path)
	assert_bool(reader.load_profile()).is_true()
	assert_int(reader.unlocked_count()).is_equal(0)
	assert_bool(reader.unlock("FIRST_FLIGHT", true)).is_true()
	assert_bool(reader.save_profile()).is_false()
	assert_array(FileAccess.get_file_as_bytes(seeded_path)).is_equal(before_bytes)


func test_sandbox_mode_never_unlocks_career_achievements() -> void:
	var path := _temp_profile("sandbox_gate")
	var ach := _new_tracker(path)
	assert_bool(ach.unlock("OPEN_FOR_BUSINESS", false)).is_false()
	assert_bool(ach.unlock("CERT_1_STAR", false)).is_false()
	assert_int(ach.unlocked_count()).is_equal(0)

	var flights: FlightSim = auto_free(FlightSim.new())
	flights.opened_tick = 10
	var eval_empty := ach.evaluate_world(flights, null, null, null, null, null, null, null, false)
	assert_array(eval_empty).is_empty()
	assert_int(ach.unlocked_count()).is_equal(0)

	var save: SaveGame = auto_free(SaveGame.new())
	var clock: SimClock = auto_free(SimClock.new())
	var rating: AirportRating = auto_free(AirportRating.new())
	var pax: PassengerSim = auto_free(PassengerSim.new())
	var unlocks: BuildUnlocks = auto_free(BuildUnlocks.new())
	unlocks.manual = true
	unlocks.rating = rating
	unlocks.passengers = pax
	save.clock = clock
	save.flights = flights
	save.rating = rating
	save.passengers = pax
	save.unlocks = unlocks
	add_child(clock)
	add_child(flights)
	add_child(rating)
	add_child(pax)
	add_child(unlocks)
	add_child(save)
	save.apply_rules(GameRules.make_sandbox(true, true), false)
	var live_ach := save.ensure_achievements()
	live_ach.profile_path = path

	assert_bool(save.is_career_mode()).is_false()
	save.ensure_certification().certified.emit({"star": 1, "title": "Local Strip"})
	(
		save
		. ensure_awards()
		. ceremony_due
		. emit(
			{
				"won_count": 1,
				"categories": [{"id": &"airport_of_the_year", "won": true}],
			}
		)
	)
	unlocks.tier_changed.emit(2)
	assert_int(live_ach.unlocked_count()).is_equal(0)


func test_steam_bridge_no_ops_without_steam_and_forwards_to_mock() -> void:
	assert_str(SteamBridge.AUTO_CLOUD_SAVE_DIR).is_equal("user://saves")
	assert_str(SteamBridge.ACHIEVEMENTS_PATH).is_equal("user://achievements.json")
	assert_bool(SteamBridge.is_steam_available()).is_false()
	assert_bool(SteamBridge.is_cloud_enabled()).is_false()
	assert_bool(SteamBridge.unlock_achievement("OPEN_FOR_BUSINESS")).is_false()

	var mock := _MockSteam.new()
	SteamBridge.set_mock_steam(mock)
	assert_bool(SteamBridge.is_steam_available()).is_true()
	assert_bool(SteamBridge.is_cloud_enabled()).is_true()

	var ach := _new_tracker(_temp_profile("steam_mock"))
	assert_bool(ach.unlock("OPEN_FOR_BUSINESS", true)).is_true()
	assert_bool(ach.unlock("OPEN_FOR_BUSINESS", true)).is_false()
	assert_array(mock.set_calls).is_equal(["OPEN_FOR_BUSINESS"])
	assert_int(mock.store_calls).is_equal(1)

	mock.running = false
	assert_bool(SteamBridge.is_steam_available()).is_false()
	assert_bool(SteamBridge.unlock_achievement("FIRST_FLIGHT")).is_false()
	assert_array(mock.set_calls).is_equal(["OPEN_FOR_BUSINESS"])


func test_save_game_wiring_unlocks_live_signals_suppresses_load_and_cleans_toast() -> void:
	var save: SaveGame = auto_free(SaveGame.new())
	var clock: SimClock = auto_free(SimClock.new())
	var flights: FlightSim = auto_free(FlightSim.new())
	var pax: PassengerSim = auto_free(PassengerSim.new())
	var rating: AirportRating = auto_free(AirportRating.new())
	var unlocks: BuildUnlocks = auto_free(BuildUnlocks.new())
	unlocks.manual = true
	unlocks.rating = rating
	unlocks.passengers = pax
	var build_mode: BuildMode = auto_free(BuildMode.new())
	build_mode.grid = BuildGrid.new()
	var baggage: BaggageSim = auto_free(BaggageSim.new())
	baggage.grid = build_mode.grid
	var offer_desk: OfferDesk = auto_free(OfferDesk.new())
	offer_desk.clock = clock
	offer_desk.rating = rating
	offer_desk.flights = flights
	offer_desk.baggage = baggage
	flights.clock = clock

	save.clock = clock
	save.flights = flights
	save.passengers = pax
	save.rating = rating
	save.unlocks = unlocks
	save.build_mode = build_mode
	save.offer_desk = offer_desk
	save.baggage = baggage
	save.quick_save_path = _temp_profile("quick_dummy")

	add_child(clock)
	add_child(flights)
	add_child(pax)
	add_child(rating)
	add_child(unlocks)
	add_child(build_mode)
	add_child(offer_desk)
	add_child(baggage)
	add_child(save)
	baggage.grid = build_mode.grid

	var ach := save.ensure_achievements()
	ach.profile_path = _temp_profile("live_wiring")
	assert_bool(save.is_career_mode()).is_true()

	# Loading suppression prevents unlocks while SaveGame.load_world installs snapshots.
	ach.set_loading(true)
	save.ensure_certification().certified.emit({"star": 1, "title": "Local Strip"})
	assert_bool(ach.is_unlocked("CERT_1_STAR")).is_false()
	ach.set_loading(false)

	# Live certification signal unlocks CERT_1_STAR and spawns AchievementToast under SaveGame.
	save.ensure_certification().certified.emit({"star": 1, "title": "Local Strip"})
	assert_bool(ach.is_unlocked("CERT_1_STAR")).is_true()
	var toast := save.get_node_or_null(NodePath(AchievementToast.LAYER_NAME)) as AchievementToast
	assert_object(toast).is_not_null()
	assert_str(toast.achievement_id()).is_equal("CERT_1_STAR")
	assert_str(toast.title_label().text).is_equal("Local Strip")
	assert_int(toast.process_mode).is_equal(Node.PROCESS_MODE_INHERIT)
	var timer := toast.get_node_or_null("AchievementTimer") as Timer
	assert_object(timer).is_not_null()
	assert_int(timer.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)

	# Live awards ceremony unlocks ANNUAL_AWARD and AIRPORT_OF_YEAR and replaces toast cleanly.
	(
		save
		. ensure_awards()
		. ceremony_due
		. emit(
			{
				"won_count": 2,
				"categories":
				[
					{"id": &"on_time", "won": true},
					{"id": &"airport_of_the_year", "won": true},
				],
			}
		)
	)
	assert_bool(ach.is_unlocked("ANNUAL_AWARD")).is_true()
	assert_bool(ach.is_unlocked("AIRPORT_OF_YEAR")).is_true()
	var toast2 := save.get_node_or_null(NodePath(AchievementToast.LAYER_NAME)) as AchievementToast
	assert_object(toast2).is_not_null()
	assert_str(toast2.achievement_id()).is_equal("AIRPORT_OF_YEAR")

	# Live room prestige L5, security lane, and ready bag room via BuildMode.grid_changed.
	_build_prestige_5_lounge(build_mode.grid)
	_build_security_lane(build_mode.grid)
	_build_ready_bag_room(build_mode)
	build_mode.grid_changed.emit()
	assert_bool(ach.is_unlocked("ROOM_PRESTIGE_5")).is_true()
	assert_bool(ach.is_unlocked("SECURITY_PRO")).is_true()
	assert_bool(ach.is_unlocked("BAGGAGE_MASTER")).is_true()

	# Live BuildUnlocks.tier_changed unlocks TIER_2_UNLOCK.
	unlocks.tier_changed.emit(2)
	assert_bool(ach.is_unlocked("TIER_2_UNLOCK")).is_true()

	# Live PassengerSim.outcome unlocks PAX_50.
	pax._made = 50
	pax.outcome.emit(1, true)
	assert_bool(ach.is_unlocked("PAX_50")).is_true()

	# Live AirportGate.opened unlocks OPEN_FOR_BUSINESS.
	var staff: StaffSim = auto_free(StaffSim.new())
	staff.sim = pax
	var gate: AirportGate = auto_free(AirportGate.new())
	gate.flights = flights
	gate.staff = staff
	flights.gate = gate
	save.ensure_achievements()
	gate.opened.emit(1)
	assert_bool(ach.is_unlocked("OPEN_FOR_BUSINESS")).is_true()

	# Live flight departure unlocks FIRST_FLIGHT + MEDIUM_RUNWAY + LARGE_RUNWAY.
	flights.runway.size = PlaneClasses.LARGE
	assert_bool(flights.open_airport()).is_true()
	var large_terms := TestFlightContracts.terms("LRG1", 13 * 60)
	large_terms["plane_size"] = PlaneClasses.LARGE
	large_terms["booked_passengers"] = 80
	assert_bool(flights.accept_contract(large_terms)).is_true()
	flights.on_tick(5000)
	assert_array(flights.flight_ids()).contains(["LRG1-d0"])
	flights.state_changed.emit("LRG1-d0", FlightSim.State.DEPARTED)
	assert_bool(ach.is_unlocked("FIRST_FLIGHT")).is_true()
	assert_bool(ach.is_unlocked("LARGE_RUNWAY")).is_true()

	var med_terms := TestFlightContracts.terms("MED1", 20 * 60)
	med_terms["plane_size"] = PlaneClasses.MEDIUM
	med_terms["booked_passengers"] = 30
	assert_bool(flights.accept_contract(med_terms)).is_true()
	flights.on_tick(13500)
	assert_array(flights.flight_ids()).contains(["MED1-d0"])
	flights.state_changed.emit("MED1-d0", FlightSim.State.DEPARTED)
	assert_bool(ach.is_unlocked("MEDIUM_RUNWAY")).is_true()

	# Live OfferBoard.changed unlocks AIRLINE_GOLD and HUB_PARTNER.
	var airline := OfferBoard.AIRLINES[0]
	for d in OfferBoard.LOYALTY_GOLD_DAYS:
		offer_desk.board.note_flown(airline, d, 1)
	var hub_terms := TestFlightContracts.terms("HUB1", 9 * 60)
	hub_terms[FlightContract.IS_HUB_KEY] = true
	assert_bool(flights.accept_contract(hub_terms)).is_true()
	offer_desk.board.changed.emit()
	assert_bool(ach.is_unlocked("AIRLINE_GOLD")).is_true()
	assert_bool(ach.is_unlocked("HUB_PARTNER")).is_true()

	# evaluate_world() checks AIRPORT_OF_YEAR via AirportAwards last report too.
	var awards := save.ensure_awards()
	awards._last_report = {
		"won_count": 1,
		"categories": [{"id": &"airport_of_the_year", "won": true}],
	}
	var eval_ach := _new_tracker(_temp_profile("eval_all"))
	var eval_newly := eval_ach.evaluate_world(
		flights,
		pax,
		unlocks,
		save.ensure_certification(),
		awards,
		offer_desk,
		build_mode,
		baggage,
		true
	)
	(
		assert_array(eval_newly)
		. contains(
			[
				"OPEN_FOR_BUSINESS",
				"FIRST_FLIGHT",
				"PAX_50",
				"AIRLINE_GOLD",
				"HUB_PARTNER",
				"SECURITY_PRO",
				"BAGGAGE_MASTER",
				"ROOM_PRESTIGE_5",
				"AIRPORT_OF_YEAR",
			]
		)
	)

	# Toast dismiss frees cleanly with 0 orphans.
	var active_toast := (
		save.get_node_or_null(NodePath(AchievementToast.LAYER_NAME)) as AchievementToast
	)
	assert_object(active_toast).is_not_null()
	active_toast.dismiss()
	await await_idle_frame()
	assert_object(save.get_node_or_null(NodePath(AchievementToast.LAYER_NAME))).is_null()


func test_real_save_game_load_world_suppresses_achievement_unlocks() -> void:
	GameBoot.pending_rules = GameRules.career()
	GameBoot.load_path = ""
	var port: SubViewport = auto_free(SubViewport.new())
	port.size = Vector2i(1280, 720)
	add_child(port)
	var main := SaveTestKit.boot(port, 4_242_424)
	var save := SaveTestKit.save_game(main)
	var ach := save.ensure_achievements()
	ach.profile_path = _temp_profile("real_load_suppress")
	assert_bool(save.is_career_mode()).is_true()

	var snap: Dictionary = JSON.parse_string(JSON.stringify(save.snapshot(), "", true, true))
	snap["certification"]["earned_star"] = 1
	snap["unlocks"]["tier"] = 2
	snap["unlocks"]["made"] = 25

	ach.profile_path = _temp_profile("real_load_clean")
	assert_bool(ach.load_profile()).is_true()
	assert_int(ach.unlocked_count()).is_equal(0)

	assert_bool(save.load_world(snap)).is_true()
	assert_bool(ach.is_loading()).is_false()
	assert_int(ach.unlocked_count()).is_equal(0)
	assert_object(save.get_node_or_null(NodePath(AchievementToast.LAYER_NAME))).is_null()
	GameBoot.pending_rules = null
	GameBoot.clear_new_airport()
