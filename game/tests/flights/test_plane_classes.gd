class_name TestPlaneClasses
extends GdUnitTestSuite
## PlaneClasses (board 77c97755, decision runway-and-taxi-technical-design-
## movement-plan-analytic-bookings-planned-pauses, point 2): every flight has a
## plane class, its model comes from airline and class and is never saved, the
## class radius is the largest own_swing_radius among its models, and the
## offer board holds each class to its passenger range.

const AIRLINES := [
	"Gotta Air",
	"Nordic Wing",
	"Blue Fjord",
	"Sunhop",
	"Polar Jet",
	"Aegean Sky",
	"Skyline Global",
	"Meridian Air",
]

## Airline -> [medium model, large model], written out so that a changed hash or
## class table fails here instead of quietly swapping an airline's plane.
const EXPECTED_MODELS := {
	"Gotta Air": ["tp_plane_04a", "tp_plane_06a"],
	"Nordic Wing": ["tp_plane_05a", "tp_plane_07a"],
	"Blue Fjord": ["tp_plane_04a", "tp_plane_06a"],
	"Sunhop": ["tp_plane_04a", "tp_plane_06a"],
	"Polar Jet": ["tp_plane_04a", "tp_plane_06a"],
	"Aegean Sky": ["tp_plane_05a", "tp_plane_07a"],
	"Skyline Global": ["tp_plane_05a", "tp_plane_07a"],
	"Meridian Air": ["tp_plane_04a", "tp_plane_06a"],
}
## FNV-1a (31 bits) of a few airline ids, from an independent implementation.
const EXPECTED_HASHES := {
	"Gotta Air": 359146478,
	"Nordic Wing": 200086999,
	"Polar Jet": 1860343332,
	"": 0x811C9DC5 & 0x7FFFFFFF,
}


func test_the_same_airline_and_class_always_give_the_expected_model() -> void:
	for airline: String in EXPECTED_MODELS:
		var expected: Array = EXPECTED_MODELS[airline]
		for repeat in 3:
			assert_str(PlaneClasses.model_for(airline, PlaneClasses.MEDIUM)).is_equal(expected[0])
			assert_str(PlaneClasses.model_for(airline, PlaneClasses.LARGE)).is_equal(expected[1])


func test_the_airline_hash_is_the_projects_own_fnv_1a() -> void:
	for airline: String in EXPECTED_HASHES:
		assert_int(PlaneClasses.airline_hash(airline)).is_equal(EXPECTED_HASHES[airline])


func test_a_small_flight_draws_model_03_whatever_the_airline() -> void:
	for airline: String in AIRLINES:
		assert_str(PlaneClasses.model_for(airline, PlaneClasses.SMALL)).is_equal("tp_plane_03a")


func test_medium_and_large_flights_draw_models_of_their_own_class() -> void:
	var medium := {}
	var large := {}
	for airline: String in AIRLINES:
		medium[PlaneClasses.model_for(airline, PlaneClasses.MEDIUM)] = true
		large[PlaneClasses.model_for(airline, PlaneClasses.LARGE)] = true
	print("airline models: medium %s, large %s" % [medium.keys(), large.keys()])
	# Both models of a class are drawn by some airline, so neither is dead art.
	assert_array(medium.keys()).contains_exactly_in_any_order(["tp_plane_04a", "tp_plane_05a"])
	assert_array(large.keys()).contains_exactly_in_any_order(["tp_plane_06a", "tp_plane_07a"])


func test_every_class_model_exists_in_the_plane_table_and_view() -> void:
	for plane_class: String in PlaneClasses.ORDER:
		for model: String in PlaneClasses.CLASSES[plane_class]["models"]:
			assert_bool(PlaneModels.PLANES.has(model)).is_true()
			assert_bool(PlaneView.PLANE_SCENES.has(model)).is_true()


func test_an_unknown_class_is_refused() -> void:
	assert_bool(PlaneClasses.is_plane_class("jumbo")).is_false()
	assert_bool(PlaneClasses.passengers_fit("jumbo", 20)).is_false()
	assert_float(PlaneClasses.swing_radius("jumbo")).is_equal(0.0)
	assert_array(PlaneClasses.passenger_range("jumbo")).is_empty()
	assert_str(PlaneClasses.model_for("Gotta Air", "jumbo")).is_equal("")


func test_the_class_radius_is_the_largest_own_swing_radius_of_its_models() -> void:
	assert_float(PlaneClasses.swing_radius(PlaneClasses.SMALL)).is_equal_approx(8.9, 0.001)
	assert_float(PlaneClasses.swing_radius(PlaneClasses.MEDIUM)).is_equal_approx(20.4, 0.001)
	assert_float(PlaneClasses.swing_radius(PlaneClasses.LARGE)).is_equal_approx(32.7, 0.001)
	# The medium radius is the 05's, not the 04's: the larger member decides.
	var smaller: float = PlaneModels.PLANES["tp_plane_04a"]["own_swing_radius"]
	assert_float(PlaneClasses.swing_radius(PlaneClasses.MEDIUM)).is_greater(smaller)


func test_the_passenger_ranges_are_the_ruled_ones() -> void:
	assert_array(PlaneClasses.passenger_range(PlaneClasses.SMALL)).is_equal([8, 16])
	assert_array(PlaneClasses.passenger_range(PlaneClasses.MEDIUM)).is_equal([24, 48])
	assert_array(PlaneClasses.passenger_range(PlaneClasses.LARGE)).is_equal([48, 120])
	for plane_class: String in PlaneClasses.ORDER:
		var limits := PlaneClasses.passenger_range(plane_class)
		assert_bool(PlaneClasses.passengers_fit(plane_class, limits[0])).is_true()
		assert_bool(PlaneClasses.passengers_fit(plane_class, limits[1])).is_true()
		assert_bool(PlaneClasses.passengers_fit(plane_class, limits[0] - 1)).is_false()
		assert_bool(PlaneClasses.passengers_fit(plane_class, limits[1] + 1)).is_false()


func test_every_offer_board_range_sits_inside_its_class_range() -> void:
	var tables: Array = [OfferBoard.STARTER_SIZES]
	tables.append_array(OfferBoard.TIER_SIZES)
	for sizes: Dictionary in tables:
		for plane_class: String in sizes:
			var booked: Array = sizes[plane_class]
			assert_bool(PlaneClasses.passengers_fit(plane_class, booked[0])).is_true()
			assert_bool(PlaneClasses.passengers_fit(plane_class, booked[1])).is_true()


func test_the_starter_contract_fits_its_class() -> void:
	var terms := FlightSim.STARTER_TERMS
	var fits := PlaneClasses.passengers_fit(terms["plane_size"], terms["booked_passengers"])
	assert_bool(fits).is_true()


func test_a_saved_offer_at_the_class_limits_loads() -> void:
	var cases: Array = [
		["small", 8, "Gotta Air"],
		["small", 16, "Gotta Air"],
		["medium", 24, "Gotta Air"],
		["medium", 48, "Gotta Air"],
		["large", 48, "Polar Jet"],
		["large", 120, "Skyline Global"],
	]
	for case in cases:
		var data := _save_with(case[2], case[0], case[1])
		var board := OfferBoard.new()
		assert_bool(board.from_snapshot(data)).override_failure_message(str(case)).is_true()
		assert_int(board.open_offers().size()).is_equal(OfferBoard.OFFERS_PER_DAY)


func test_a_drawn_offer_always_has_a_count_its_class_allows() -> void:
	for seed_value in [1, 2, 3, 99, 123456]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for tier in OfferBoard.MAX_TIER + 1:
			var board := OfferBoard.new()
			board.ensure_day(0, rng, tier)
			for offer in board.open_offers():
				var fits := PlaneClasses.passengers_fit(
					offer["plane_size"], offer["booked_passengers"]
				)
				assert_bool(fits).override_failure_message(str(offer)).is_true()


func test_a_plane_view_picks_the_model_from_its_flights_airline_and_class() -> void:
	var cases: Array = [
		["Gotta Air", "small", 12, "tp_plane_03a"],
		["Nordic Wing", "medium", 40, PlaneClasses.model_for("Nordic Wing", "medium")],
		["Blue Fjord", "medium", 40, PlaneClasses.model_for("Blue Fjord", "medium")],
		["Polar Jet", "large", 90, PlaneClasses.model_for("Polar Jet", "large")],
	]
	for case in cases:
		var sim := auto_free(FlightSim.new()) as FlightSim
		sim.open_airport()
		var terms := _terms("C1", TestFlightContracts.bootstrap_minute(), case[1], case[2], case[0])
		assert_bool(sim.accept_contract(terms)).is_true()
		var view := _new_view(sim)
		var flight := _first_flight_of(sim, "C1")
		print("view model: %s %s -> %s" % [case[0], case[1], view.model_of(flight)])
		assert_str(flight).is_not_empty()
		assert_str(view.model_of(flight)).is_equal(case[3])
		view.show_model(view.model_of(flight))
		assert_str(view.model_name).is_equal(case[3])


func test_a_plane_view_swaps_its_model_rather_than_stacking_a_second() -> void:
	var view := _new_view(auto_free(FlightSim.new()) as FlightSim)
	assert_str(view.model_name).is_equal("tp_plane_03a")
	view.show_model("tp_plane_07a")
	assert_str(view.model_name).is_equal("tp_plane_07a")
	assert_int(view.get_node("Pivot").get_child_count()).is_equal(1)
	assert_int(view.get_node("FarShadow").get_child_count()).is_equal(1)
	view.show_model("tp_plane_03a")
	assert_str(view.model_name).is_equal("tp_plane_03a")
	assert_int(view.get_node("Pivot").get_child_count()).is_equal(1)
	assert_int(view.get_node("FarShadow").get_child_count()).is_equal(1)
	# A name that is no plane model leaves the view as it was.
	view.show_model("tp_plane_99z")
	assert_str(view.model_name).is_equal("tp_plane_03a")


func test_a_one_off_flight_is_drawn_as_the_starters_small_plane() -> void:
	var sim := auto_free(FlightSim.new()) as FlightSim
	assert_bool(sim.add_flight("ONEOFF", FlightSim.schedule_starts(0))).is_true()
	var view := _new_view(sim)
	assert_str(view.model_of("ONEOFF")).is_equal("tp_plane_03a")
	assert_str(view.model_name).is_equal("tp_plane_03a")


## Every model's door is placed where model 05's is, moved only by its
## door_shift(): model 04 parks STOP_BACK_M further out, away from the terminal
## (decision plane-04-stops-further-out-with-the-passenger-walk-ending-at).
func test_every_model_puts_its_passenger_door_where_model_05s_stand_door_is() -> void:
	var reference: Vector3 = (
		PlaneModels.PLANES["tp_plane_05a"]["doors"][0] + PlaneClasses.REFERENCE_OFFSET
	)
	for model: String in PlaneModels.PLANES:
		var door: Vector3 = PlaneModels.PLANES[model]["doors"][0]
		var placed := PlaneClasses.stand_offset(model) + door
		var shift := PlaneClasses.door_shift(model)
		print("%s door placed at %s (reference %s, shift %s)" % [model, placed, reference, shift])
		assert_float(placed.x).is_equal_approx(reference.x, 0.001)
		assert_float(placed.z).is_equal_approx(reference.z + shift.z, 0.001)
		assert_float(shift.x).is_equal(0.0)
		var expected := -1.5 if model == "tp_plane_04a" else 0.0
		assert_float(shift.z).is_equal_approx(expected, 0.001)
	# Model 05 keeps the placement the stand was built around.
	var own := PlaneClasses.stand_offset("tp_plane_05a")
	assert_float(own.z).is_equal_approx(PlaneClasses.REFERENCE_OFFSET.z, 0.001)
	assert_float(own.x).is_equal_approx(0.0, 0.001)


## StandPlacement parks model 05 so its door is at door_point (to 0.2 m along
## the plane), and every model's door is placed at its own door_point too. A
## model's nose lands near model 05's, always on the plane side of the wall
## line.
func test_every_model_on_a_stand_has_its_door_at_the_stand_door_and_its_nose_off_the_wall() -> void:
	var stand := StandPlacement.make(1, 100.0, 40.0)
	var base := StandPlacement.stand_point(stand)
	var wall_z := float(stand["wall_z"])
	var nose_05 := base.z + StandPlacement.NOSE_M
	for model: String in PlaneModels.PLANES:
		var row: Dictionary = PlaneModels.PLANES[model]
		var offset := PlaneClasses.stand_offset(model)
		var door_z := StandPlacement.door_point(stand, model).z
		var door_at: Vector3 = base + offset + row["doors"][0]
		var nose_at: float = base.z + offset.z + row["nose"]
		print(
			(
				"%s on the stand: door z %.2f (stand door %.2f), nose %.2f (05 nose %.2f), wall %.2f"
				% [model, door_at.z, door_z, nose_at, nose_05, wall_z]
			)
		)
		assert_float(door_at.z).is_equal_approx(door_z, 0.2)
		assert_float(nose_at).is_less(wall_z)
		assert_float(absf(nose_at - nose_05)).is_less(2.1)


func test_the_starters_small_plane_is_moved_up_to_the_stand_not_centred() -> void:
	# The case the review found: model 03 centred on the pose point left its nose
	# about 11.6 m short of the wall and its door 9 m from where passengers walk.
	var centred: float = PlaneModels.PLANES["tp_plane_03a"]["model_offset"].z
	var placed := PlaneClasses.stand_offset("tp_plane_03a").z
	assert_float(placed - centred).is_greater(7.0)


## A view of `sim` in the tree, not drawing (it has no airside to read paths from).
func _new_view(sim: FlightSim) -> PlaneView:
	var view := PlaneView.new()
	view.sim = sim
	view.clock = auto_free(SimClock.new()) as SimClock
	add_child(view)
	view.set_process(false)
	return auto_free(view) as PlaneView


## The id of the first live flight of contract `contract_id`.
func _first_flight_of(sim: FlightSim, contract_id: String) -> String:
	for id in sim.flight_ids():
		if sim.flight_contract_id(id) == contract_id:
			return id
	return ""


## A one-day save holding the day's whole offer set, the first being the case.
func _save_with(airline: String, plane_size: String, booked: int) -> Dictionary:
	var offers := TestOfferBoard.day_records(0, [480, 540, 600])
	offers[0]["airline"] = airline
	offers[0]["plane_size"] = plane_size
	offers[0]["booked_passengers"] = booked
	offers[0]["fee_per_passenger"] = OfferBoard.TIER_FEES[OfferBoard.tier_of(airline)][0]
	return TestOfferBoard.save_of(offers)


func _terms(id: String, minute: int, size: String, booked: int, airline: String) -> Dictionary:
	return {
		"id": id,
		"airline": airline,
		"destination": "Oslo",
		"departure_minute": minute,
		"plane_size": size,
		"booked_passengers": booked,
		"fee_per_passenger": 25,
	}
