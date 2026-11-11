class_name TestFlightFit
extends GdUnitTestSuite
## FlightFit.assess: one read-only answer per departure, whether an offer fits
## now and why not (decision airline-offers-2-a-day-fit-the-free-gate-slots-1-
## needs-more, point 2), worked out by FlightSim.trial_assignment on copies of
## the planning state. One gate, C, on the fallback stand, unless a case adds D.

var _sim: FlightSim


func before_test() -> void:
	_sim = auto_free(FlightSim.new()) as FlightSim
	_sim.open_airport()


## Offer terms for a small plane departing at `minute`.
static func terms(id: String, minute: int, size := PlaneClasses.SMALL) -> Dictionary:
	return {
		"id": id,
		"airline": "Gotta Air",
		"destination": "Oslo",
		"departure_minute": minute,
		"plane_size": size,
		"booked_passengers": 12 if size == PlaneClasses.SMALL else 40,
		"fee_per_passenger": 25,
	}


func _two_gates() -> void:
	_sim.gate_source = func() -> Array[String]: return ["C", "D"] as Array[String]


func test_an_empty_airport_fits_every_departure_at_its_gate() -> void:
	for minute in [420, 600, 1260]:
		var assessment := FlightFit.assess(_sim, terms("X", minute))
		print("empty airport %d: %s" % [minute, assessment])
		assert_bool(assessment["fits"]).is_true()
		assert_str(assessment["gate"]).is_equal("C")
		assert_str(assessment["blocker"]).is_empty()
		assert_str(FlightFit.text(assessment, PlaneClasses.SMALL)).is_equal(FlightFit.FITS_TEXT)


## Two hours after A1 the gate is still held (195 minutes), but the runway and
## lane are free then, so a second gate would take it.
func test_a_clash_a_free_gate_would_solve_says_build_another_gate() -> void:
	assert_bool(_sim.accept_contract(terms("A1", 600))).is_true()
	var assessment := FlightFit.assess(_sim, terms("X", 720))
	print("10:00 taken, 12:00: %s" % [assessment])
	assert_bool(assessment["fits"]).is_false()
	assert_str(assessment["blocker"]).is_equal(FlightSim.BLOCKER_GATE)
	assert_bool(assessment["another_gate_helps"]).is_true()
	assert_str(FlightFit.text(assessment, PlaneClasses.SMALL)).is_equal(FlightFit.ANOTHER_GATE_TEXT)
	assert_str(_sim.accept_problem(terms("X", 720))).is_equal(
		"contract X clashes with A1 at gate C"
	)


## At A1's own minute the runway and lane are A1's, so another gate alone
## would not do, and the card does not say it would.
func test_a_clash_on_the_runway_too_is_not_blamed_on_the_gate_alone() -> void:
	assert_bool(_sim.accept_contract(terms("A1", 600))).is_true()
	var assessment := FlightFit.assess(_sim, terms("X", 600))
	print("10:00 taken, 10:00: %s" % [assessment])
	assert_str(assessment["blocker"]).is_equal(FlightSim.BLOCKER_GATE)
	assert_bool(assessment["another_gate_helps"]).is_false()
	assert_str(FlightFit.text(assessment, PlaneClasses.SMALL)).is_equal(
		FlightFit.GATE_AND_TAXI_TEXT
	)


## A second gate really does take the 12:00 flight the one-gate airport could
## not, which is what "build another gate" promised.
func test_another_gate_helps_is_borne_out_by_a_second_gate() -> void:
	assert_bool(_sim.accept_contract(terms("A1", 600))).is_true()
	assert_bool(FlightFit.assess(_sim, terms("X", 720))["another_gate_helps"]).is_true()
	_two_gates()
	var assessment := FlightFit.assess(_sim, terms("X", 720))
	assert_bool(assessment["fits"]).is_true()
	assert_str(assessment["gate"]).is_equal("D")


func test_terms_before_are_planned_as_if_accepted_first() -> void:
	assert_bool(FlightFit.fits(_sim, terms("X", 600))).is_true()
	var after := FlightFit.assess(_sim, terms("X", 600), [terms("Y", 660)])
	assert_str(after["blocker"]).is_equal(FlightSim.BLOCKER_GATE)
	_two_gates()
	after = FlightFit.assess(_sim, terms("X", 600), [terms("Y", 660)])
	assert_bool(after["fits"]).is_true()
	assert_str(after["gate"]).is_equal("D")
	assert_array(_sim.contract_ids()).is_empty()


func test_assessing_changes_nothing() -> void:
	_two_gates()
	assert_bool(_sim.accept_contract(terms("A1", 600))).is_true()
	var before := _sim.to_snapshot()
	for minute in [420, 600, 720, 900, 1260]:
		FlightFit.assess(_sim, terms("X", minute), [terms("Y", 660), terms("Z", 700)])
		_sim.trial_assignment(terms("X", minute), [], true)
	assert_dict(_sim.to_snapshot()).is_equal(before)
	assert_array(_sim.contract_ids()).is_equal(["A1"])
	assert_array(_sim.gate_ids()).is_equal(["C", "D"])


## Fits exactly when the click-time check would accept.
func test_the_assessment_agrees_with_accept_problem() -> void:
	assert_bool(_sim.accept_contract(terms("A1", 600))).is_true()
	assert_bool(_sim.accept_contract(terms("A2", 1000))).is_true()
	var fitting := 0
	for slot in range(OfferBoard.DEPARTURE_SLOTS + 1):
		var minute := OfferBoard.DEPARTURE_FIRST_MINUTE + slot * OfferBoard.DEPARTURE_STEP
		var offer := terms("X", minute)
		var fits := FlightFit.assess(_sim, offer)["fits"] as bool
		assert_bool(fits).is_equal(_sim.accept_problem(offer) == "")
		fitting += 1 if fits else 0
	print("slots that fit beside 10:00 and 16:40: %d" % fitting)
	assert_int(fitting).is_greater(0)


func test_the_runway_and_a_missing_stand_have_their_own_words() -> void:
	_sim.runway.size = PlaneClasses.SMALL
	var runway := FlightFit.assess(_sim, terms("X", 600, PlaneClasses.MEDIUM))
	assert_str(runway["blocker"]).is_equal(FlightSim.BLOCKER_RUNWAY)
	assert_str(FlightFit.text(runway, PlaneClasses.MEDIUM)).is_equal(
		"Runway too short for a medium plane"
	)
	_sim.gate_source = func() -> Array[String]: return [] as Array[String]
	var none := FlightFit.assess(_sim, terms("X", 600))
	assert_str(none["blocker"]).is_equal(FlightSim.BLOCKER_STAND)
	assert_str(FlightFit.text(none, PlaneClasses.SMALL)).is_equal(FlightFit.NO_STAND_TEXT)
