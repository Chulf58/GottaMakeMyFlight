class_name TestArrivalsLifecycleAndIsolation
extends GdUnitTestSuite
## Arrivals Slice A1: end-to-end arriving passenger lifecycle (deplane -> exit
## -> optional amenity -> entrance -> road retire) and complete isolation of
## SecurityForecast, StandingSpots, AirportRating punctuality, BuildUnlocks,
## and IncidentMajors from ARRIVING passengers.

const GameAudioScript := preload("res://audio/game_audio.gd")

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


func test_arriving_passenger_walks_to_road_and_retires_with_arrival_mood() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var place := BuildEdit.place_object(BuildCatalog.AIRSIDE_EXIT_ID, Vector2i(13, 8), 2)
	for edit: BuildEdit in DoorPlacement.edits_for(grid, place):
		assert_bool(grid.apply(edit).ok).is_true()

	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 7)
	_worlds.append(world)
	var rating := auto_free(AirportRating.new()) as AirportRating
	rating.bind(world.clock, world.flights, world.sim)
	var unlocks := auto_free(BuildUnlocks.new()) as BuildUnlocks
	unlocks.rating = rating
	unlocks.passengers = world.sim
	unlocks.manual = true
	add_child(unlocks)

	var finished := []
	world.sim.arrival_finished.connect(func(id: int) -> void: finished.append(id))
	var outcomes := []
	world.sim.outcome.connect(func(id: int, made: bool) -> void: outcomes.append([id, made]))

	var p := PassengerArrivals.spawn(world.sim, PassengerTestWorld.FLIGHT, 0)
	assert_object(p).is_not_null()
	assert_bool(p.is_arriving()).is_true()
	assert_bool(p.cleared).is_true()
	assert_int(p.stage).is_equal(Passenger.Stage.DEPLANING)

	var crossed_landside := false
	for _i in 1500:
		world.step()
		if p.stage == Passenger.Stage.TO_ROAD_EXIT and not p.cleared:
			crossed_landside = true
		if world.sim.get_passenger(p.id) == null:
			break

	assert_bool(crossed_landside).is_true()
	assert_array(finished).is_equal([p.id])
	assert_array(outcomes).is_empty()
	assert_object(world.sim.get_passenger(p.id)).is_null()
	# Isolation: AirportRating made/missed & BuildUnlocks 20-pax stay 0;
	# arriving mood is still recorded in terminal mood.
	assert_bool(rating.has_data()).is_false()
	assert_int(rating.parts()["made"]).is_equal(0)
	assert_int(rating.parts()["missed"]).is_equal(0)
	assert_int(rating.day_totals(0)["arrived"]).is_equal(1)
	assert_int(unlocks.made_total()).is_equal(0)

	# When a departing passenger finishes, arriving mood blends into mood_avg.
	rating.record_passenger(world.clock.tick, true, 60)
	assert_float(rating.parts()["mood_avg"]).is_greater(60.0)


func test_arriving_passenger_isolated_from_forecast_spots_and_vip_incident() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 11)
	_worlds.append(world)

	var p := PassengerArrivals.spawn(world.sim, PassengerTestWorld.FLIGHT, 1)
	assert_object(p).is_not_null()
	var dep_id := world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var dep := world.passenger(dep_id)
	assert_bool(dep.is_departing()).is_true()

	# StandingSpots / BoardingFiles / SecurityForecast ignore ARRIVING pax.
	assert_int(world.sim.standing.spot_of(p.id)).is_equal(StandingSpots.NO_SPOT)
	assert_int(world.sim.standing.shortage(world.sim)).is_equal(0)
	assert_array(world.sim.files.known(world.sim)).is_empty()
	assert_int(SecurityForecast.eta(world.sim, p)).is_greater_equal(JourneyForecast.NEVER)
	assert_dict(SecurityForecast.clearances(world.sim, 0, [p.id])).is_empty()

	# IncidentMajors VIP ignores ARRIVING passenger even on the VIP flight.
	var director := auto_free(IncidentDirector.new()) as IncidentDirector
	director.bind(world.clock, world.flights, world.sim)
	var majors := director._majors
	var vip_inc := {
		"id": 1,
		"kind": IncidentCatalogue.VIP,
		"state": IncidentCatalogue.ACCEPTED,
		"plan": {"flight": PassengerTestWorld.FLIGHT, "target": 0},
	}
	majors.spawned(vip_inc, p.id)
	assert_int(int(vip_inc["plan"]["target"])).is_equal(0)
	majors.spawned(vip_inc, dep_id)
	assert_int(int(vip_inc["plan"]["target"])).is_equal(dep_id)


func test_arriving_passenger_can_take_optional_landside_toilet_and_still_exit() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var place_exit := BuildEdit.place_object(BuildCatalog.AIRSIDE_EXIT_ID, Vector2i(13, 8), 2)
	for edit: BuildEdit in DoorPlacement.edits_for(grid, place_exit):
		assert_bool(grid.apply(edit).ok).is_true()
	# Place a ready landside toilet room (3x3) with stall and sink at (18..20, 12..14).
	assert_bool(grid.apply(BuildEdit.place_room(Rect2i(18, 12, 3, 3), &"toilet")).ok).is_true()
	(
		assert_bool(grid.apply(BuildEdit.place_object(&"toilet_stall", Vector2i(18, 12), 0)).ok)
		. is_true()
	)
	(
		assert_bool(grid.apply(BuildEdit.place_object(&"toilet_sink", Vector2i(20, 12), 0)).ok)
		. is_true()
	)

	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 13)
	_worlds.append(world)
	var p := PassengerArrivals.spawn(world.sim, PassengerTestWorld.FLIGHT, 0)
	p.toilet_need = ToiletSim.NEED_MAX
	p.arrival_stop_cap = 1
	var used_toilet := false
	for _i in 1500:
		world.step()
		if p.stage == Passenger.Stage.TOILET_WALK or p.stage == Passenger.Stage.TOILET_USE:
			used_toilet = true
		if world.sim.get_passenger(p.id) == null:
			break
	assert_bool(used_toilet).is_true()
	assert_object(world.sim.get_passenger(p.id)).is_null()


func test_arrivals_cleanup_game_audio_skip_outside_decor_and_use_arrival_spawned() -> void:
	const SITE := preload("res://build/terminal_site.tres")
	var grid := SiteGrid.new(SITE)
	ReferenceTerminal.build(grid)
	var offset := SITE.starter_offset
	var place_exit := BuildEdit.place_object(
		BuildCatalog.AIRSIDE_EXIT_ID, offset + Vector2i(13, 8), 2
	)
	for edit: BuildEdit in DoorPlacement.edits_for(grid, place_exit):
		assert_bool(grid.apply(edit).ok).is_true()
	# Place a plant near the entrance inside landside so indoor decor covers the entrance cell.
	(
		assert_bool(
			grid.apply(BuildEdit.place_object(&"plant_pot_1a", offset + Vector2i(20, 16), 0)).ok
		)
		. is_true()
	)

	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 21)
	world.sim.site = SITE
	_worlds.append(world)
	var audio: Variant = auto_free(GameAudioScript.new())
	audio._bind_passenger_sim(world.sim)

	var dep_spawns := []
	var arr_spawns := []
	world.sim.passenger_spawned.connect(func(id: int) -> void: dep_spawns.append(id))
	world.sim.arrival_spawned.connect(func(id: int) -> void: arr_spawns.append(id))

	var p := PassengerArrivals.spawn(world.sim, PassengerTestWorld.FLIGHT, 0)
	assert_array(dep_spawns).is_empty()
	assert_array(arr_spawns).is_equal([p.id])

	var tested_outside_decor := false
	for _i in 2500:
		world.step()
		if p.stage == Passenger.Stage.TO_ROAD_EXIT and p.walking_outside():
			var mood_before := p.mood
			var thoughts_before := p.thoughts.size()
			world.sim.decor.beat(p)
			assert_int(p.mood).is_equal(mood_before)
			assert_int(p.thoughts.size()).is_equal(thoughts_before)
			tested_outside_decor = true
		if world.sim.get_passenger(p.id) == null:
			break

	assert_bool(tested_outside_decor).is_true()
	assert_bool(audio._prev_stage.has(p.id)).is_false()
	audio._unbind_passenger_sim(world.sim)
