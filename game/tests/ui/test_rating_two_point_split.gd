class_name TestRatingTwoPointSplit
extends GdUnitTestSuite
## Two Point split (decision 4cf71a6b): live 3-day AirportRating displays as a
## 0-100% quality score across RatingBadge, tooltips, certification criteria,
## BuildUnlocks copy, OfferPanel warnings/loyalty, DemoEndCard, DeparturesBoard,
## and PaWords, reserving 1-5★ exclusively for AirportCertification milestones.


func after_test() -> void:
	DemoMode.clear_override()


func test_quality_percent_maps_star_bounds_cleanly() -> void:
	assert_int(AirportRating.quality_percent(0.0)).is_equal(0)
	assert_int(AirportRating.quality_percent(1.0)).is_equal(20)
	assert_int(AirportRating.quality_percent(1.5)).is_equal(30)
	assert_int(AirportRating.quality_percent(2.0)).is_equal(40)
	assert_int(AirportRating.quality_percent(2.5)).is_equal(50)
	assert_int(AirportRating.quality_percent(3.0)).is_equal(60)
	assert_int(AirportRating.quality_percent(3.5)).is_equal(70)
	assert_int(AirportRating.quality_percent(4.0)).is_equal(80)
	assert_int(AirportRating.quality_percent(4.5)).is_equal(90)
	assert_int(AirportRating.quality_percent(5.0)).is_equal(100)
	assert_int(AirportRating.quality_percent(-1.0)).is_equal(0)
	assert_int(AirportRating.quality_percent(6.5)).is_equal(100)


func test_rating_badge_displays_percentage_quality_and_reserves_stars_for_certification() -> void:
	var rating := auto_free(AirportRating.new()) as AirportRating
	var cert := auto_free(AirportCertification.new()) as AirportCertification
	cert.rating = rating
	(
		cert
		. evaluate(
			{
				"opened": true,
				"made_total": 10,
				"rating_stars": 4.5,
				"has_security_lane": false,
				"has_bag_room": false,
				"made_ratio": 0.9,
			}
		)
	)
	var badge := auto_free(RatingBadge.new()) as RatingBadge
	badge.rating = rating
	badge.certification = cert
	add_child(badge)

	assert_str(badge.label().text).is_equal("No flights yet")
	assert_int(badge.shown_quality()).is_equal(0)
	assert_bool(badge.cert_chip().visible).is_false()
	for child in badge.card().find_children("*", "Control", true, false):
		assert_bool(child is RatingBadge.StarRow).is_false()

	for i in 9:
		rating.record_passenger(10, true, 90)
	rating.record_passenger(10, false, 0)
	assert_float(rating.stars()).is_equal(4.5)
	assert_int(badge.shown_quality()).is_equal(90)
	assert_str(badge.label().text).is_equal("90%")
	assert_float(badge.quality_meter().ratio).is_equal_approx(0.9, 0.001)
	assert_str(badge.label().text).not_contains("4.5")
	assert_str(badge.label().text).not_contains("★")
	assert_bool(badge.cert_chip().visible).is_true()
	assert_str(badge.cert_chip().text).is_equal("1★")
	for child in badge.card().find_children("*", "Control", true, false):
		assert_bool(child is RatingBadge.StarRow).is_false()


func test_rating_badge_tooltip_and_drawer_show_quality_percent_and_cert_stars() -> void:
	var rating := auto_free(AirportRating.new()) as AirportRating
	for i in 5:
		rating.record_passenger(10, true, PassengerSim.MOOD_MAX)
		rating.record_passenger(10, false, 0)
	for i in 4:
		rating.record_bag(10, true)
	rating.record_bag(10, false)
	assert_bool(rating.add_adjustment("vip", 10, 500, -2)).is_true()

	var cert := auto_free(AirportCertification.new()) as AirportCertification
	cert.rating = rating
	(
		cert
		. evaluate(
			{
				"opened": true,
				"made_total": 10,
				"rating_stars": rating.stars(),
				"has_security_lane": false,
				"has_bag_room": false,
				"made_ratio": 0.5,
			}
		)
	)
	var badge := auto_free(RatingBadge.new()) as RatingBadge
	badge.rating = rating
	badge.certification = cert
	add_child(badge)

	var tip := badge.card().tooltip_text
	assert_str(tip).contains("Airport quality: 50%")
	assert_str(tip).contains("Made it: 50%")
	assert_str(tip).contains("Mood: 100%")
	assert_str(tip).contains("Bags: 80% (4 of 5)")
	assert_str(tip).contains("Incident adjustment: -20%")
	assert_str(tip).contains("Days counted: 1 of 3")
	assert_str(tip).contains("Certification: 1★ Local Strip (+0% contract fees)")
	assert_str(tip).not_contains("Airport rating:")
	assert_str(tip).not_contains("2.5 of 5")
	assert_str(tip).not_contains("stars")

	badge.open()
	var rows := badge.drawer().find_child("CertRows", true, false) as VBoxContainer
	var tier2_texts: Array[String] = []
	for node in rows.get_child(1).find_children("*", "Label", true, false):
		tier2_texts.append((node as Label).text)
	var joined := "\n".join(tier2_texts)
	assert_str(joined).contains("2★ Regional Terminal")
	assert_str(joined).contains("Quality: 50% / 40%")
	assert_str(joined).not_contains("★\n")
	assert_str(joined).not_contains("/ 2.0★")


func test_unlock_offer_and_end_card_copy_use_quality_percent_not_stars() -> void:
	assert_str(BuildUnlocks.requirement_text(2)).is_equal(
		"Unlocks at 40% quality and 20 passengers"
	)
	assert_str(BuildUnlocks.requirement_text(3)).is_equal(
		"Unlocks at 60% quality and 120 passengers"
	)
	assert_str(BuildUnlocks.requirement_text(4)).is_equal(
		"Unlocks at 80% quality and 600 passengers"
	)

	var rating := auto_free(AirportRating.new()) as AirportRating
	var pax := auto_free(PassengerSim.new()) as PassengerSim
	var unlocks := auto_free(BuildUnlocks.new()) as BuildUnlocks
	unlocks.rating = rating
	unlocks.passengers = pax
	unlocks.manual = true
	add_child(unlocks)
	var lock_line := unlocks.unlock_text(BuildMode.Tool.CAFE_ROOM)
	assert_str(lock_line).is_equal(
		"Unlocks at 40% quality and 20 passengers (now 50% quality, 0 passengers)"
	)
	assert_str(lock_line).not_contains("stars")

	var warn := OfferPanel.warning_message(0)
	assert_str(warn).contains("below 40%")
	assert_str(warn).not_contains("stars")

	var clock := auto_free(SimClock.new()) as SimClock
	add_child(clock)
	var flights := auto_free(FlightSim.new()) as FlightSim
	add_child(flights)
	var bag := auto_free(BaggageSim.new()) as BaggageSim
	add_child(bag)
	var desk := auto_free(OfferDesk.new()) as OfferDesk
	desk.clock = clock
	desk.rating = rating
	desk.flights = flights
	desk.baggage = bag
	desk.runway = Runway.new(PlaneClasses.LARGE)
	add_child(desk)
	var records := TestOfferBoard.day_records(12, [600, 720, 840])
	records[0]["traits"] = {}
	records[0]["fee_per_passenger"] = 52
	records[0][OfferBoard.LOYAL_KEY] = true
	records[0][OfferBoard.LOYAL_TIER_KEY] = OfferBoard.LOYALTY_TIER_GOLD
	records[1]["airline"] = "Sunhop"
	records[2]["airline"] = "Sunhop"
	var offer_data := TestOfferBoard.save_of(records)
	offer_data["loyalty"] = {"Gotta Air": {"days": OfferBoard.LOYALTY_GOLD_DAYS, "last_day": 11}}
	assert_bool(desk.board.from_snapshot(offer_data)).is_true()
	var offer_panel := auto_free(OfferPanel.new()) as OfferPanel
	offer_panel.desk = desk
	offer_panel.flights = flights
	add_child(offer_panel)
	offer_panel.open()
	var loyal_label := offer_panel.trait_row("O12N1").get_node("Loyal") as Label
	assert_str(loyal_label.tooltip_text).contains("60%+ quality")
	assert_str(loyal_label.tooltip_text).not_contains("3★")

	for i in 9:
		rating.record_passenger(10, true, 90)
	rating.record_passenger(10, false, 0)
	DemoMode.set_override_for_test(true)
	var end_card := auto_free(DemoEndCard.new()) as DemoEndCard
	end_card.rating = rating
	add_child(end_card)
	assert_bool(end_card.open()).is_true()
	var end_panel := end_card.panel()
	var end_texts: Array[String] = []
	for node in end_panel.find_children("*", "Label", true, false):
		end_texts.append((node as Label).text)
	var end_joined := "\n".join(end_texts)
	assert_str(end_joined).contains("Airport quality")
	assert_str(end_joined).contains("90%")
	assert_str(end_joined).not_contains("stars")
	for child in end_panel.find_children("*", "Control", true, false):
		assert_bool(child is RatingBadge.StarRow).is_false()

	var board := auto_free(DeparturesBoard.new()) as DeparturesBoard
	add_child(board)
	var on_time := board.find_child("OnTime", true, false) as Label
	assert_str(on_time.tooltip_text).contains("quality score")
	assert_str(on_time.tooltip_text).not_contains("star rating")

	var pa := PaWords.star_milestone("4.0")
	assert_str(pa).contains("80%")
	assert_str(pa).not_contains("stars")
