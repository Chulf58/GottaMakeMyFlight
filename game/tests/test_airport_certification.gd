class_name TestAirportCertification
extends GdUnitTestSuite
## Stage 2 S2-D: 1-to-5 star airport certification ladder, cash grants,
## permanent contract fee prestige bonus, RatingBadge progress drawer,
## BigFirsts celebration toast, SaveGame persistence, and DemoMode 2★ cap.

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	DemoMode.clear_override()
	PseudoLocale.disable()


func after_test() -> void:
	DemoMode.clear_override()
	PseudoLocale.disable()
	if _world != null:
		_world.free_all()
		_world = null


func _cert() -> AirportCertification:
	return auto_free(AirportCertification.new()) as AirportCertification


func _metrics(overrides := {}) -> Dictionary:
	var base := {
		"opened": true,
		"made_total": 0,
		"rating_stars": 2.5,
		"made_ratio": 0.80,
		"has_security_lane": false,
		"has_bag_room": false,
	}
	for k in overrides:
		base[k] = overrides[k]
	return base


func test_all_five_milestone_boundaries_grants_and_prestige_bonus() -> void:
	var cert := _cert()
	assert_int(cert.earned_star()).is_equal(0)
	assert_int(cert.prestige_fee_bonus_percent()).is_equal(0)

	# 1★ needs opened AND >= 10 pax made.
	assert_array(cert.evaluate(_metrics({"opened": false, "made_total": 10}))).is_empty()
	assert_array(cert.evaluate(_metrics({"opened": true, "made_total": 9}))).is_empty()
	var a1 := cert.evaluate(_metrics({"opened": true, "made_total": 10}))
	assert_int(a1.size()).is_equal(1)
	assert_int(a1[0]["star"]).is_equal(1)
	assert_str(a1[0]["title"]).is_equal("Local Strip")
	assert_int(a1[0]["grant"]).is_equal(1500)
	assert_int(a1[0]["bonus_percent"]).is_equal(0)
	assert_int(cert.earned_star()).is_equal(1)
	assert_int(cert.prestige_fee_bonus_percent()).is_equal(0)

	# 2★ needs >= 2.0 rating AND >= 50 pax AND security lane built.
	(
		assert_array(
			cert.evaluate(
				_metrics({"made_total": 50, "rating_stars": 1.5, "has_security_lane": true})
			)
		)
		. is_empty()
	)
	(
		assert_array(
			cert.evaluate(
				_metrics({"made_total": 49, "rating_stars": 2.0, "has_security_lane": true})
			)
		)
		. is_empty()
	)
	(
		assert_array(
			cert.evaluate(
				_metrics({"made_total": 50, "rating_stars": 2.0, "has_security_lane": false})
			)
		)
		. is_empty()
	)
	var a2 := cert.evaluate(
		_metrics({"made_total": 50, "rating_stars": 2.0, "has_security_lane": true})
	)
	assert_int(a2.size()).is_equal(1)
	assert_int(a2[0]["star"]).is_equal(2)
	assert_str(a2[0]["title"]).is_equal("Regional Terminal")
	assert_int(a2[0]["grant"]).is_equal(3000)
	assert_int(cert.prestige_fee_bonus_percent()).is_equal(5)

	# 3★ needs >= 3.0 rating, >= 150 pax, bag room built, >= 1 Medium+ departed.
	(
		assert_array(
			(
				cert
				. evaluate(
					_metrics(
						{
							"made_total": 150,
							"rating_stars": 3.0,
							"has_security_lane": true,
							"has_bag_room": true,
						}
					)
				)
			)
		)
		. is_empty()
	)
	cert.record_departure(PlaneClasses.MEDIUM)
	var a3 := (
		cert
		. evaluate(
			_metrics(
				{
					"made_total": 150,
					"rating_stars": 3.0,
					"has_security_lane": true,
					"has_bag_room": true,
				}
			)
		)
	)
	assert_int(a3.size()).is_equal(1)
	assert_int(a3[0]["star"]).is_equal(3)
	assert_str(a3[0]["title"]).is_equal("National Hub")
	assert_int(a3[0]["grant"]).is_equal(6000)
	assert_int(cert.prestige_fee_bonus_percent()).is_equal(10)

	# 4★ needs >= 4.0 rating, >= 400 pax, >= 1 Large departed, >= 85% made rate.
	(
		assert_array(
			(
				cert
				. evaluate(
					_metrics(
						{
							"made_total": 400,
							"rating_stars": 4.0,
							"made_ratio": 0.85,
						}
					)
				)
			)
		)
		. is_empty()
	)
	cert.record_departure(PlaneClasses.LARGE)
	(
		assert_array(
			(
				cert
				. evaluate(
					_metrics(
						{
							"made_total": 400,
							"rating_stars": 4.0,
							"made_ratio": 0.84,
						}
					)
				)
			)
		)
		. is_empty()
	)
	var a4 := (
		cert
		. evaluate(
			_metrics(
				{
					"made_total": 400,
					"rating_stars": 4.0,
					"made_ratio": 0.85,
				}
			)
		)
	)
	assert_int(a4.size()).is_equal(1)
	assert_int(a4[0]["star"]).is_equal(4)
	assert_str(a4[0]["title"]).is_equal("International Gateway")
	assert_int(a4[0]["grant"]).is_equal(12000)
	assert_int(cert.prestige_fee_bonus_percent()).is_equal(15)

	# 5★ needs >= 4.5 rating, >= 800 pax, >= 90% made rate.
	(
		assert_array(
			cert.evaluate(_metrics({"made_total": 800, "rating_stars": 4.5, "made_ratio": 0.89}))
		)
		. is_empty()
	)
	var a5 := cert.evaluate(_metrics({"made_total": 800, "rating_stars": 4.5, "made_ratio": 0.90}))
	assert_int(a5.size()).is_equal(1)
	assert_int(a5[0]["star"]).is_equal(5)
	assert_str(a5[0]["title"]).is_equal("World-Class Airport")
	assert_int(a5[0]["grant"]).is_equal(25000)
	assert_int(cert.prestige_fee_bonus_percent()).is_equal(20)


func test_monotonic_non_revocation_ascending_catchup_and_large_counts_for_medium() -> void:
	var cert := _cert()
	# Large plane increments both medium_departed and large_departed.
	cert.record_departure(PlaneClasses.LARGE)
	assert_int(cert.medium_departed()).is_equal(1)
	assert_int(cert.large_departed()).is_equal(1)

	# Jumping straight to meeting 1★..4★ awards sequentially in ascending order.
	var awards := (
		cert
		. evaluate(
			_metrics(
				{
					"opened": true,
					"made_total": 500,
					"rating_stars": 4.0,
					"made_ratio": 0.88,
					"has_security_lane": true,
					"has_bag_room": true,
				}
			)
		)
	)
	assert_int(awards.size()).is_equal(4)
	(
		assert_array(awards.map(func(a: Dictionary) -> int: return int(a["star"])))
		. is_equal([1, 2, 3, 4])
	)
	assert_int(cert.earned_star()).is_equal(4)

	# Re-evaluating never double-awards or revokes when rating/facilities dip later.
	var dip := (
		cert
		. evaluate(
			_metrics(
				{
					"opened": true,
					"made_total": 500,
					"rating_stars": 1.0,
					"made_ratio": 0.10,
					"has_security_lane": false,
					"has_bag_room": false,
				}
			)
		)
	)
	assert_array(dip).is_empty()
	assert_int(cert.earned_star()).is_equal(4)
	assert_int(cert.prestige_fee_bonus_percent()).is_equal(15)


func test_live_grants_paid_once_and_airport_rating_untouched() -> void:
	var finances := auto_free(Finances.new()) as Finances
	var rating := auto_free(AirportRating.new()) as AirportRating
	for i in 10:
		rating.record_passenger(10, true, PassengerSim.MOOD_MAX)
	var rating_before := rating.stars()

	var cert := _cert()
	cert.finances = finances
	cert.rating = rating
	var unlocks := auto_free(BuildUnlocks.new()) as BuildUnlocks
	unlocks.manual = true
	for i in 10:
		unlocks.note_made()
	var flights := auto_free(FlightSim.new()) as FlightSim
	flights.open_airport()
	cert.flights = flights
	cert.unlocks = unlocks

	var balance_before := finances.wallet.balance
	var first := cert.evaluate_live()
	assert_int(first.size()).is_equal(1)
	assert_int(finances.wallet.balance).is_equal(balance_before + 1500)
	# Re-evaluating never double-pays the cash grant.
	assert_array(cert.evaluate_live()).is_empty()
	assert_int(finances.wallet.balance).is_equal(balance_before + 1500)
	# Rolling AirportRating stays untouched by certification awards.
	assert_float(rating.stars()).is_equal(rating_before)


func test_settlement_applies_prestige_fee_bonus_to_contract_payouts() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(100000))
	_world.flights.open_airport()

	var cert := _cert()
	(
		cert
		. evaluate(
			_metrics(
				{
					"opened": true,
					"made_total": 50,
					"rating_stars": 2.5,
					"has_security_lane": true,
				}
			)
		)
	)
	assert_int(cert.prestige_fee_bonus_percent()).is_equal(5)
	assert_int(cert.apply_prestige_bonus(40)).is_equal(42)

	var settlement := auto_free(Settlement.new()) as Settlement
	settlement.certification = cert
	settlement.bind(_world.sim, _world.sim.wallet)

	var terms := TestFlightContracts.terms("PRESTIGE", 518)
	terms["plane_size"] = PlaneClasses.SMALL
	terms["booked_passengers"] = 4
	terms["fee_per_passenger"] = 40
	assert_bool(_world.flights.accept_contract(terms)).is_true()
	var p := _world.passenger(_world.sim.spawn_now("PRESTIGE-d0"))
	while not p.is_done() and _world.clock.tick < 4000:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)
	# Base fee 40 + 5% prestige = 42 per made passenger (contract fee_per_passenger stays 40).
	assert_int(_world.flights.contract_of("PRESTIGE")["fee_per_passenger"]).is_equal(40)
	assert_int(_world.sim.wallet.balance).is_equal(_world.sim.made_count() * 42)


func test_demo_mode_caps_at_2_star_and_marks_higher_levels_full_game_teasers() -> void:
	DemoMode.set_override_for_test(true)
	var cert := _cert()
	cert.record_departure(PlaneClasses.LARGE)
	var awards := (
		cert
		. evaluate(
			_metrics(
				{
					"opened": true,
					"made_total": 900,
					"rating_stars": 5.0,
					"made_ratio": 1.0,
					"has_security_lane": true,
					"has_bag_room": true,
				}
			),
			DemoMode.is_demo()
		)
	)
	assert_int(awards.size()).is_equal(2)
	assert_int(cert.earned_star()).is_equal(2)
	assert_int(cert.prestige_fee_bonus_percent()).is_equal(5)

	var rows := cert.progress_rows(_metrics({"made_total": 900}), true)
	assert_bool(rows[0]["demo_locked"]).is_false()
	assert_bool(rows[1]["demo_locked"]).is_false()
	for idx in [2, 3, 4]:
		assert_bool(rows[idx]["earned"]).is_false()
		assert_bool(rows[idx]["demo_locked"]).is_true()


func test_rating_badge_drawer_and_big_firsts_celebration() -> void:
	DemoMode.set_override_for_test(true)
	var rating := auto_free(AirportRating.new()) as AirportRating
	for i in 10:
		rating.record_passenger(10, true, PassengerSim.MOOD_MAX)
	var cert := _cert()
	cert.rating = rating
	cert.evaluate(_metrics({"opened": true, "made_total": 10}))

	var badge := auto_free(RatingBadge.new()) as RatingBadge
	badge.rating = rating
	badge.certification = cert
	add_child(badge)

	assert_bool(badge.cert_chip().visible).is_true()
	assert_str(badge.cert_chip().text).contains("1★")
	assert_float(badge.card().get_combined_minimum_size().x).is_less_equal(TopRow.RATING_W)
	assert_bool(badge.is_drawer_open()).is_false()
	assert_bool(badge.is_in_group(TopRow.SHEET_GROUP)).is_true()

	# With no rating data, CertChip is omitted so "No flights yet" stays within TopRow.RATING_W.
	var empty_rating := auto_free(AirportRating.new()) as AirportRating
	badge.watch(empty_rating)
	assert_bool(badge.cert_chip().visible).is_false()
	assert_float(badge.card().get_combined_minimum_size().x).is_less_equal(TopRow.RATING_W)
	assert_str(badge.card().tooltip_text).contains("1★")

	# PseudoLocale: with data stays <= TopRow.RATING_W; without data omits CertChip.
	PseudoLocale.enable()
	badge.watch(rating)
	assert_float(badge.card().get_combined_minimum_size().x).is_less_equal(TopRow.RATING_W)
	badge.watch(empty_rating)
	assert_bool(badge.cert_chip().visible).is_false()
	assert_str(badge.card().tooltip_text).contains("1★")
	PseudoLocale.disable()
	badge.watch(rating)

	badge.press()
	assert_bool(badge.is_drawer_open()).is_true()
	assert_bool(badge.is_open()).is_true()
	assert_object(badge.sheet()).is_same(badge.drawer())
	assert_float(badge.drawer().position.x).is_greater_equal(TopRow.SHEET_MIN_LEFT)
	var drawer_layer := badge.drawer().get_parent() as CanvasLayer
	assert_object(drawer_layer).is_not_null()
	assert_int(drawer_layer.layer).is_equal(TopRow.SHEET_LAYER)
	var rows_box := badge.drawer().find_child("CertRows", true, false) as VBoxContainer
	assert_object(rows_box).is_not_null()
	assert_int(rows_box.get_child_count()).is_equal(5)
	# 3★..5★ show "In the full game" in DemoMode.
	var row3 := rows_box.get_child(2)
	var labels := row3.find_children("*", "Label", true, false)
	var texts := labels.map(func(l: Node) -> String: return (l as Label).text)
	assert_bool(texts.has(BuildUnlocks.IN_FULL_GAME_TEXT)).is_true()

	# Esc / build_tool_none closes the drawer.
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	badge._unhandled_input(esc)
	assert_bool(badge.is_drawer_open()).is_false()

	# Outside click closes the drawer; inside click keeps it open.
	badge.open()
	assert_bool(badge.is_drawer_open()).is_true()
	var inside_click := InputEventMouseButton.new()
	inside_click.button_index = MOUSE_BUTTON_LEFT
	inside_click.pressed = true
	inside_click.position = badge.drawer().position + Vector2(10.0, 10.0)
	badge._input(inside_click)
	assert_bool(badge.is_drawer_open()).is_true()
	var outside_click := InputEventMouseButton.new()
	outside_click.button_index = MOUSE_BUTTON_LEFT
	outside_click.pressed = true
	outside_click.position = Vector2(20.0, 400.0)
	badge._input(outside_click)
	assert_bool(badge.is_drawer_open()).is_false()

	# TopRow.close_others closes sibling sheets when RatingBadge opens.
	var fake_sheet := auto_free(_FakeTopSheet.new()) as _FakeTopSheet
	fake_sheet.add_to_group(TopRow.SHEET_GROUP)
	add_child(fake_sheet)
	fake_sheet.open_sheet()
	assert_bool(fake_sheet.open).is_true()
	badge.open()
	assert_bool(fake_sheet.open).is_false()
	assert_bool(badge.is_open()).is_true()
	TopRow.close_others(fake_sheet)
	assert_bool(badge.is_open()).is_false()

	var toast_layer := (
		auto_free(BigFirsts.show_certification(2, "Regional Terminal", 3000, 5)) as CanvasLayer
	)
	add_child(toast_layer)
	var title_lbl := toast_layer.find_child("CertificationTitle", true, false) as Label
	var body_lbl := toast_layer.find_child("CertificationBody", true, false) as Label
	assert_str(title_lbl.text).contains("2★")
	assert_str(title_lbl.text).contains("Regional Terminal")
	assert_str(body_lbl.text).contains("3000")
	assert_str(body_lbl.text).contains("5%")


func test_current_metrics_empty_window_and_flight_departed_signal_and_max_balance_clamp() -> void:
	var rating := auto_free(AirportRating.new()) as AirportRating
	var flights := auto_free(FlightSim.new()) as FlightSim
	flights.open_airport()
	var cert := _cert()
	cert.bind(flights, rating, null, null, null, null, null)

	# When made + missed == 0, current_metrics() reports made_ratio == -1.0, blocking 4★/5★.
	var metrics := cert.current_metrics()
	assert_bool(metrics["opened"]).is_true()
	assert_float(float(metrics["made_ratio"])).is_less(0.0)
	cert.record_departure(PlaneClasses.LARGE)
	var jumped := (
		cert
		. evaluate(
			{
				"opened": true,
				"made_total": 900,
				"rating_stars": 5.0,
				"made_ratio": metrics["made_ratio"],
				"has_security_lane": true,
				"has_bag_room": true,
			}
		)
	)
	assert_int(cert.earned_star()).is_equal(3)
	assert_int(jumped.size()).is_equal(3)

	# apply_prestige_bonus clamps safely to Wallet.MAX_BALANCE.
	assert_int(cert.prestige_fee_bonus_percent()).is_equal(10)
	assert_int(cert.apply_prestige_bonus(Wallet.MAX_BALANCE)).is_equal(Wallet.MAX_BALANCE)

	# FlightSim.state_changed(DEPARTED) updates departure counts via _on_flight_state.
	var med_terms := TestFlightContracts.terms("MEDSIG", 520)
	med_terms["plane_size"] = PlaneClasses.MEDIUM
	med_terms["booked_passengers"] = 24
	med_terms["fee_per_passenger"] = 30
	assert_bool(flights.accept_contract(med_terms)).is_true()
	var med_before := cert.medium_departed()
	flights.state_changed.emit("MEDSIG-d0", FlightSim.State.DEPARTED)
	assert_int(cert.medium_departed()).is_equal(med_before + 1)


func test_save_game_round_trip_and_corrupt_certification_rejection() -> void:
	var cert := _cert()
	cert.record_departure(PlaneClasses.LARGE)
	(
		cert
		. evaluate(
			_metrics(
				{
					"opened": true,
					"made_total": 160,
					"rating_stars": 3.5,
					"has_security_lane": true,
					"has_bag_room": true,
				}
			)
		)
	)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(cert.to_save_dict()))
	var restored := _cert()
	assert_bool(restored.from_save_dict(saved)).is_true()
	assert_int(restored.earned_star()).is_equal(3)
	assert_int(restored.medium_departed()).is_equal(1)
	assert_int(restored.large_departed()).is_equal(1)
	assert_int(restored.prestige_fee_bonus_percent()).is_equal(10)

	# Corrupt snapshots are refused and leave existing state unchanged.
	var bad_star := saved.duplicate(true)
	bad_star["earned_star"] = 6
	var bad_depart := saved.duplicate(true)
	bad_depart["medium_departed"] = 0
	var bad_extra := saved.duplicate(true)
	bad_extra["extra"] = 1
	for bad: Dictionary in [bad_star, bad_depart, bad_extra, {"save_version": 99}]:
		assert_str(AirportCertification.validation_problem(bad)).is_not_empty()
		assert_bool(restored.from_save_dict(bad)).is_false()
	assert_int(restored.earned_star()).is_equal(3)

	# Whole-world SaveGame integration check on main.tscn.
	var main := SaveTestKit.boot(self, 4_242_026)
	var save := SaveTestKit.save_game(main)
	var badge := main.get_node("RatingBadge") as RatingBadge
	var main_cert := save.ensure_certification()
	main_cert.record_departure(PlaneClasses.MEDIUM)
	var snap: Dictionary = JSON.parse_string(JSON.stringify(save.snapshot(), "", true, true))
	assert_int(int(snap["save_version"])).is_greater_equal(35)
	assert_bool(snap.has("certification")).is_true()
	assert_int(int(snap["certification"]["medium_departed"])).is_equal(1)

	badge.open()
	assert_bool(badge.is_drawer_open()).is_true()
	main_cert.reset()
	assert_int(main_cert.medium_departed()).is_equal(0)
	assert_bool(save.load_world(snap)).is_true()
	assert_int(main_cert.medium_departed()).is_equal(1)
	# Successful load closes the open certification drawer.
	assert_bool(badge.is_drawer_open()).is_false()

	# SaveGame._on_certified spawns a toast child under SaveGame that cleans up cleanly.
	var unlocks := main.get_node("BuildUnlocks") as BuildUnlocks
	var flights := main.get_node("FlightSim") as FlightSim
	flights.open_airport()
	for i in 10:
		unlocks.note_made()
	var awarded := main_cert.evaluate_live()
	assert_int(awarded.size()).is_equal(1)
	assert_object(save.get_node_or_null("CertificationToastLayer")).is_not_null()

	# Corrupt save load leaves live certification state and clock tick untouched.
	var tick_before := save.clock.tick
	var star_before := main_cert.earned_star()
	var med_before := main_cert.medium_departed()
	var large_before := main_cert.large_departed()
	var bad_world := snap.duplicate(true)
	bad_world["certification"]["earned_star"] = 4
	bad_world["certification"]["large_departed"] = 0
	assert_bool(save.load_world(bad_world)).is_false()
	assert_str(save.message_text()).contains("certification")
	assert_int(save.clock.tick).is_equal(tick_before)
	assert_int(main_cert.earned_star()).is_equal(star_before)
	assert_int(main_cert.medium_departed()).is_equal(med_before)
	assert_int(main_cert.large_departed()).is_equal(large_before)
	main.free()


class _FakeTopSheet:
	extends Node
	var open := false

	func open_sheet() -> void:
		open = true

	func close() -> void:
		open = false

	func is_open() -> bool:
		return open
