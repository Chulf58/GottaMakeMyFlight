class_name TestFlightContractTraits
extends GdUnitTestSuite
## A contract's traits term (technical design offer-traits-technical-design-
## offertraits-table-frozen-trait): optional in offer terms, always present and
## frozen in a stored contract, checked against the trait table, and kept by a
## JSON save of the flights.

const TRAITS := {"up": "bag_cover", "down": "rush_crowd", "level": 2}

var _sim: FlightSim


func before_test() -> void:
	_sim = auto_free(FlightSim.new()) as FlightSim


static func _terms(id: String, traits: Variant = null) -> Dictionary:
	var terms := TestFlightContracts.terms(id, 600)
	if traits != null:
		terms[FlightContract.TRAITS_KEY] = traits
	return terms


func test_terms_without_traits_make_a_plain_contract() -> void:
	assert_bool(_sim.accept_contract(_terms("PLAIN"))).is_true()
	var traits: Dictionary = _sim.contract_of("PLAIN")["traits"]
	assert_dict(traits).is_empty()
	assert_bool(traits.is_read_only()).is_true()


## Contracts gained the traits term in flight save version 8; a version 7 save
## is refused, with no migration.
func test_a_version_7_save_of_the_flights_is_refused() -> void:
	assert_int(FlightSim.SAVE_VERSION).is_equal(10)
	assert_bool(_sim.accept_contract(_terms("OLD"))).is_true()
	var data: Dictionary = JSON.parse_string(JSON.stringify(_sim.to_snapshot()))
	data["save_version"] = 7
	var loaded: FlightSim = auto_free(FlightSim.new())
	assert_bool(loaded.from_snapshot(data)).is_false()


func test_a_contract_keeps_a_frozen_copy_of_its_traits() -> void:
	var source := TRAITS.duplicate()
	assert_bool(_sim.accept_contract(_terms("PAIRED", source))).is_true()
	source["level"] = 1
	var traits: Dictionary = _sim.contract_of("PAIRED")["traits"]
	assert_dict(traits).is_equal(TRAITS)
	assert_bool(traits.is_read_only()).is_true()


func test_bad_traits_are_refused_in_terms() -> void:
	for bad: Variant in [
		{"up": "shoppers", "down": "rush_crowd", "level": 1},
		{"up": "top_fare", "down": "rush_crowd", "level": 0},
		[],
	]:
		var problem := FlightContract.problem(_terms("BAD", bad), FlightContract.TERM_KEYS)
		assert_str(problem).override_failure_message(str(bad)).is_not_empty()
	assert_bool(_sim.accept_problem(_terms("BAD", {"up": "x"})) != "").is_true()


func test_a_stored_contract_must_hold_its_traits() -> void:
	var stored := _terms("STORED")
	stored["gate"] = FlightSim.DEFAULT_GATE
	stored["first_day"] = 0
	# A stored contract also holds its taxi pair (flight save version 9); this
	# case is about the traits, so the pair is there from the start.
	stored["taxi"] = TaxiTimes.BASE
	assert_str(FlightContract.problem(stored, FlightContract.KEYS)).contains("traits")
	stored["traits"] = {}
	assert_str(FlightContract.problem(stored, FlightContract.KEYS)).is_empty()


func test_traits_survive_a_json_save_of_the_flights() -> void:
	assert_bool(_sim.accept_contract(_terms("SAVED", TRAITS))).is_true()
	var data: Dictionary = JSON.parse_string(JSON.stringify(_sim.to_snapshot()))
	var loaded: FlightSim = auto_free(FlightSim.new())
	assert_bool(loaded.from_snapshot(data)).is_true()
	var traits: Dictionary = loaded.contract_of("SAVED")["traits"]
	assert_dict(traits).is_equal(TRAITS)
	assert_int(typeof(traits["level"])).is_equal(TYPE_INT)
	assert_bool(traits.is_read_only()).is_true()
