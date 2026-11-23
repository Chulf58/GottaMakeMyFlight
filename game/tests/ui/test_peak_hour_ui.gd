class_name TestPeakHourUi
extends GdUnitTestSuite
## Stage 2 S2-B UI tests: OfferPanel peak rush chips ("Morning Peak +15%" /
## "Evening Peak +15%") and FlightPlanner subtle amber peak bands + "Peak" tags.

const LAYOUTS := [Vector2i(1920, 1080), Vector2i(1280, 720)]


func _rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func test_offer_panel_renders_peak_chips_only_on_non_charter_peak_offers() -> void:
	for size: Vector2i in LAYOUTS:
		var port := auto_free(SubViewport.new()) as SubViewport
		port.size = size
		add_child(port)
		var sim := FlightSim.new()
		sim.open_airport()
		port.add_child(sim)

		var records := TestOfferBoard.day_records(1, [480, 720, 1080])
		records[0]["fee_per_passenger"] = OfferBoard.apply_peak_bonus(50, 480)
		records[2]["fee_per_passenger"] = OfferBoard.apply_peak_bonus(50, 1080)
		var desk_peak := OfferDesk.new()
		desk_peak.runway = Runway.new(PlaneClasses.LARGE)
		port.add_child(desk_peak)
		assert_bool(desk_peak.board.from_snapshot(TestOfferBoard.save_of(records))).is_true()

		var panel := OfferPanel.new()
		panel.desk = desk_peak
		panel.flights = sim
		port.add_child(panel)
		panel.open()
		await await_idle_frame()

		var morning_chip := panel.card("O1N1").find_child("PeakChip_O1N1", true, false) as Control
		var offpeak_chip := panel.card("O1N2").find_child("PeakChip_O1N2", true, false) as Control
		var evening_chip := panel.card("O1N3").find_child("PeakChip_O1N3", true, false) as Control
		assert_object(morning_chip).is_not_null()
		assert_object(offpeak_chip).is_null()
		assert_object(evening_chip).is_not_null()
		assert_str(panel.card_text("O1N1")).contains("Morning Peak +15%")
		assert_str(panel.card_text("O1N2")).not_contains("Peak")
		assert_str(panel.card_text("O1N3")).contains("Evening Peak +15%")
		assert_bool(_rect(panel.card("O1N1")).encloses(_rect(morning_chip))).is_true()
		assert_bool(_rect(panel.card("O1N3")).encloses(_rect(evening_chip))).is_true()

		# Odd hours at 06:00 and 22:00 must never show peak chips.
		var odd := TestOfferBoard.day_records(2, [360, 720, 1320])
		odd[0]["traits"] = {"up": OfferTraits.TOP_FARE, "down": OfferTraits.ODD_HOURS, "level": 1}
		odd[0]["fee_per_passenger"] = OfferTraits.fee_of(50, odd[0]["traits"])
		odd[2]["traits"] = {"up": OfferTraits.TOP_FARE, "down": OfferTraits.ODD_HOURS, "level": 1}
		odd[2]["fee_per_passenger"] = OfferTraits.fee_of(50, odd[2]["traits"])
		var desk_odd := OfferDesk.new()
		desk_odd.runway = Runway.new(PlaneClasses.LARGE)
		port.add_child(desk_odd)
		assert_bool(desk_odd.board.from_snapshot(TestOfferBoard.save_of(odd))).is_true()
		var panel_odd := OfferPanel.new()
		panel_odd.desk = desk_odd
		panel_odd.flights = sim
		port.add_child(panel_odd)
		panel_odd.open()
		await await_idle_frame()
		assert_object(panel_odd.card("O2N1").find_child("PeakChip_O2N1", true, false)).is_null()
		assert_object(panel_odd.card("O2N3").find_child("PeakChip_O2N3", true, false)).is_null()
		assert_str(panel_odd.card_text("O2N1")).not_contains("Peak")
		assert_str(panel_odd.card_text("O2N3")).not_contains("Peak")


func test_flight_planner_renders_aligned_amber_peak_bands_and_labels() -> void:
	for size: Vector2i in LAYOUTS:
		var sim := auto_free(FlightSim.new()) as FlightSim
		sim.open_airport()
		sim.gate_source = func() -> Array[String]: return ["A", "B"] as Array[String]
		var terms := TestFlightContracts.terms("PK1", 1080)
		terms["destination"] = "Oslo"
		assert_bool(sim.accept_contract(terms)).is_true()
		var clock := auto_free(SimClock.new()) as SimClock

		var port := auto_free(SubViewport.new()) as SubViewport
		port.size = size
		add_child(port)
		var planner := FlightPlanner.new()
		planner.flights = sim
		planner.clock = clock
		port.add_child(planner)
		planner.open()
		await await_idle_frame()
		await await_idle_frame()

		var track := planner.part("Track_A")
		var hours := planner.part("Hours")
		assert_object(track).is_not_null()
		assert_object(hours).is_not_null()
		var track_rect := _rect(track)
		var hours_rect := _rect(hours)

		for band in FlightPlanner.peak_bands():
			var wave: String = band["wave"]
			var start_min: int = band["start_minute"]
			var end_min: int = band["end_minute"]
			var expected_left := (
				track_rect.position.x + track_rect.size.x * float(start_min) / 1440.0
			)
			var expected_right := (
				track_rect.position.x + track_rect.size.x * float(end_min) / 1440.0
			)

			var band_ctrl := planner.part("PeakBand_A_%s" % wave) as ColorRect
			assert_object(band_ctrl).is_not_null()
			var band_rect := _rect(band_ctrl)
			assert_float(band_rect.position.x).is_equal_approx(expected_left, 1.5)
			assert_float(band_rect.end.x).is_equal_approx(expected_right, 1.5)
			assert_float(band_ctrl.color.a).is_greater(0.05)
			assert_float(band_ctrl.color.a).is_less(0.35)

			var tag := planner.part("PeakTag_%s" % wave) as ColorRect
			var peak_label := planner.part("PeakLabel_%s" % wave) as Label
			assert_object(tag).is_not_null()
			assert_object(peak_label).is_not_null()
			assert_str(peak_label.text).is_equal("Peak")
			var tag_rect := _rect(tag)
			assert_float(tag_rect.position.x).is_equal_approx(expected_left, 1.5)
			assert_float(tag_rect.end.x).is_equal_approx(expected_right, 1.5)
			# Peak header sits cleanly above the hour labels without vertical overlap.
			assert_float(tag_rect.end.y).is_less_equal(hours_rect.position.y + 0.5)

		# Flight bar draws as a later sibling on top of the peak bands.
		var bar := planner.bar_button("PK1", 0)
		var evening_band := planner.part("PeakBand_A_evening")
		assert_object(bar).is_not_null()
		assert_int(bar.get_index()).is_greater(evening_band.get_index())
