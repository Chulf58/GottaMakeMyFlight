class_name TestIncidentPanelCopy
extends GdUnitTestSuite
## The words of the four major incidents in the panel (IncidentCatalogue.
## panel_copy, IncidentCopy.fill; board 03e71ed7): each says the cause, the
## reward and the failure, with the numbers of the incident's own saved plan.
## A MajorTestDirector holds the records, the real catalogue gives the words.

const DEPARTS := 60_000

var _k := IncidentPanelKit.new()


func before_test() -> void:
	_k.build(self)
	_k.panel.copy_for = IncidentCatalogue.panel_copy


func after_test() -> void:
	_k.port.free()


## A major of `kind` with `plan`, presented, and the open dialog's beats + chips + tips + footer.
func _words(kind: String, plan: Dictionary) -> Dictionary:
	var id := _k.director.add_scheduled(kind, plan)
	assert_bool(_k.director.present(id, IncidentCatalogue.is_offer(kind))).is_true()
	assert_bool(_k.panel.is_open()).is_true()
	var dlg := _k.panel.dialog()
	var tips := PackedStringArray()
	for child in dlg.chips_row().get_children():
		var btn := child as Button
		if btn != null:
			tips.append(btn.tooltip_text)
	return {
		"body": "\n".join(dlg.beats()),
		"chips": "\n".join(dlg.chip_texts()),
		"chip_list": dlg.chip_texts(),
		"tips": "\n".join(tips),
		"footer": dlg.footer_text(),
	}


func _assert_scannable_chips(chip_list: PackedStringArray) -> void:
	for chip_label in chip_list:
		var words := chip_label.strip_edges().split(" ", false)
		assert_int(words.size()).is_between(2, 4)


func test_a_rush_card_names_the_counts_the_reward_and_the_failure() -> void:
	var plan := {
		"flights":
		[
			{"flight": "AM-d2", "extra": 4, "departs": DEPARTS},
			{"flight": "BM-d2", "extra": 6, "departs": DEPARTS + 6000},
		],
		"total": 10,
		"until": 79_200,
	}
	var res := _words(IncidentCatalogue.RUSH, plan)
	var text: String = res["body"]
	var chips: String = res["chips"]
	var tips: String = res["tips"]
	print("%s | %s | %s" % [text, chips, tips])
	assert_str(text).contains("10 extra passengers")
	assert_str(text).contains("2 of tomorrow's flights")
	assert_str(text).contains(
		(
			"%s +4, %s +6"
			% [GameCalendar.clock_text(DEPARTS, 0), GameCalendar.clock_text(DEPARTS + 6000, 0)]
		)
	)
	_assert_scannable_chips(res["chip_list"])
	assert_str(chips).contains("Reward:")
	assert_str(chips).contains("Risk:")
	assert_str(tips).contains("Reward: every extra passenger pays the usual fee.")
	assert_str(tips).contains("If it fails:")
	assert_str(res["footer"]).contains(
		IncidentPanel.OFFER_FOOTER if false else IncidentPanel.ANNOUNCE_FOOTER
	)
	assert_str(text).not_contains("{")
	assert_str(chips).not_contains("{")
	assert_str(tips).not_contains("{")
	assert_object(_k.panel.dialog().continue_button()).is_not_null()


func test_an_inspector_card_names_the_window_the_reward_and_the_failure() -> void:
	var plan := {
		"window_from": 50_000,
		"window_to": 58_000,
		"visit_tick": 52_000,
		"max_messes": IncidentTuning.INSPECTOR_MAX_MESSES,
		"max_full_queue": IncidentTuning.INSPECTOR_MAX_FULL_QUEUE,
		"pass_money": IncidentTuning.INSPECTOR_PASS_MONEY,
		"fail_half_stars": IncidentTuning.INSPECTOR_FAIL_HALF_STARS,
	}
	var res := _words(IncidentCatalogue.INSPECTOR, plan)
	var text: String = res["body"]
	var chips: String = res["chips"]
	var tips: String = res["tips"]
	print("%s | %s | %s" % [text, chips, tips])
	assert_str(text).contains(GameCalendar.clock_text(50_000, 0))
	assert_str(text).contains(GameCalendar.clock_text(58_000, 0))
	_assert_scannable_chips(res["chip_list"])
	assert_str(chips).contains("+%d money" % IncidentTuning.INSPECTOR_PASS_MONEY)
	assert_str(chips).contains("-1 star")
	assert_str(tips).contains("%d money" % IncidentTuning.INSPECTOR_PASS_MONEY)
	assert_str(tips).contains("at most %d messes" % IncidentTuning.INSPECTOR_MAX_MESSES)
	assert_str(tips).contains("your rating drops by 1 star")
	assert_str(text).not_contains("{")
	assert_str(chips).not_contains("{")
	assert_str(tips).not_contains("{")


func test_a_vip_offer_names_the_flight_the_bonus_and_the_penalty() -> void:
	var plan := {
		"flight": "AM-d1",
		"departs": DEPARTS,
		"bonus": 500,
		"target": 0,
		"good_mood": 75,
		"miss_half_stars": 2,
	}
	var res := _words(IncidentCatalogue.VIP, plan)
	var text: String = res["body"]
	var chips: String = res["chips"]
	var tips: String = res["tips"]
	print("%s | %s | %s" % [text, chips, tips])
	assert_str(text).contains("fly on day 3's %s flight" % GameCalendar.clock_text(DEPARTS, 0))
	_assert_scannable_chips(res["chip_list"])
	assert_str(chips).contains("+500 money")
	assert_str(chips).contains("-1 star")
	assert_str(tips).contains("Reward: 500 money if the VIP makes the flight in a good mood")
	assert_str(tips).contains("a mood of 75 or higher when boarding")
	assert_str(tips).contains("If it fails: your rating drops by 1 star")
	assert_str(res["footer"]).contains(IncidentPanel.OFFER_FOOTER)
	assert_object(_k.panel.dialog().accept_button()).is_not_null()


func test_a_favour_offer_names_the_passengers_the_money_and_the_failure() -> void:
	var plan := {"flight": "AM-d1", "departs": DEPARTS, "extra": 4, "bonus": 300}
	var res := _words(IncidentCatalogue.FAVOUR, plan)
	var text: String = res["body"]
	var chips: String = res["chips"]
	var tips: String = res["tips"]
	print("%s | %s | %s" % [text, chips, tips])
	assert_str(text).contains("fit 4 more passengers")
	_assert_scannable_chips(res["chip_list"])
	assert_str(chips).contains("+300 money")
	assert_str(chips).contains("Risk:")
	assert_str(tips).contains("Reward: 300 money now, and 4 more passengers")
	assert_str(tips).contains("If it fails: the extra passengers need check-in")
	assert_str(text).not_contains("{")
	assert_str(chips).not_contains("{")
	assert_str(tips).not_contains("{")


func test_the_penalty_words_follow_the_half_stars() -> void:
	assert_str(IncidentCopy.stars_text(1)).is_equal("half a star")
	assert_str(IncidentCopy.stars_text(2)).is_equal("1 star")
	assert_str(IncidentCopy.stars_text(3)).is_equal("1.5 stars")
	assert_str(IncidentCopy.stars_text(4)).is_equal("2 stars")


## The saved plan of a VIP flight at 10:29 on day 3.
func _vip_plan() -> Dictionary:
	return {
		"flight": "AM-d3",
		"departs": GameCalendar.tick_at(3, 10 * 60 + 29, 0),
		"bonus": 500,
		"target": 0,
		"good_mood": 75,
		"miss_half_stars": 2,
	}


## A VIP offer that fired on day 2 at 23:50, presented with the clock at `now`.
func _late_offer(now: int) -> int:
	_k.clock.tick = now
	var fired := GameCalendar.tick_at(2, 23 * 60 + 50, 0)
	var id := _k.director.add_scheduled(IncidentCatalogue.VIP, _vip_plan(), fired)
	assert_bool(_k.director.present(id, true)).is_true()
	return id


func test_an_offer_shown_after_midnight_says_today() -> void:
	_late_offer(GameCalendar.tick_at(3, 10, 0))
	assert_bool(_k.panel.is_open()).is_true()
	var text := _k.panel.dialog().body_text()
	print(text)
	assert_str(text).contains("today's 10:29 flight")
	assert_str(text).not_contains("tomorrow")


func test_an_offer_shown_before_midnight_says_tomorrow() -> void:
	_late_offer(GameCalendar.tick_at(2, 23 * 60 + 55, 0))
	assert_str(_k.panel.dialog().body_text()).contains("tomorrow's 10:29 flight")


func test_an_offer_queued_behind_a_dialog_is_worded_when_it_opens() -> void:
	var token := _k.sheet_takes_the_turn()
	_late_offer(GameCalendar.tick_at(2, 23 * 60 + 55, 0))
	assert_bool(_k.panel.is_open()).is_false()
	# Midnight passes while the other dialog is up, then it gives the turn back.
	_k.clock.tick = GameCalendar.tick_at(3, 10, 0)
	_k.clock.holds.release(token)
	assert_bool(_k.panel.is_open()).is_true()
	assert_str(_k.panel.dialog().body_text()).contains("today's 10:29 flight")


func test_incident_panel_chips_and_tips_never_overlap_footer_or_buttons() -> void:
	var cases := [
		{
			"kind": IncidentCatalogue.RUSH,
			"plan":
			{
				"flights":
				[
					{"flight": "AM-d2", "extra": 4, "departs": DEPARTS},
					{"flight": "BM-d2", "extra": 6, "departs": DEPARTS + 6000},
				],
				"total": 10,
				"until": 79_200,
			},
		},
		{
			"kind": IncidentCatalogue.INSPECTOR,
			"plan":
			{
				"window_from": 50_000,
				"window_to": 58_000,
				"visit_tick": 52_000,
				"max_messes": IncidentTuning.INSPECTOR_MAX_MESSES,
				"max_full_queue": IncidentTuning.INSPECTOR_MAX_FULL_QUEUE,
				"pass_money": IncidentTuning.INSPECTOR_PASS_MONEY,
				"fail_half_stars": IncidentTuning.INSPECTOR_FAIL_HALF_STARS,
			},
		},
		{
			"kind": IncidentCatalogue.VIP,
			"plan":
			{
				"flight": "AM-d1",
				"departs": DEPARTS,
				"bonus": 500,
				"target": 0,
				"good_mood": 75,
				"miss_half_stars": 2,
			},
		},
		{
			"kind": IncidentCatalogue.FAVOUR,
			"plan": {"flight": "AM-d1", "departs": DEPARTS, "extra": 4, "bonus": 300},
		},
	]
	for vp_size: Vector2i in [Vector2i(1280, 720), Vector2i(1536, 864)]:
		_k.port.size = vp_size
		for entry: Dictionary in cases:
			var kind: String = entry["kind"]
			var offer := IncidentCatalogue.is_offer(kind)
			var id := _k.director.add_scheduled(kind, entry["plan"])
			assert_bool(_k.director.present(id, offer)).is_true()
			var dlg := _k.panel.dialog()
			await get_tree().process_frame
			await get_tree().process_frame
			_assert_no_dialog_overlaps(dlg, "%s @ %s" % [kind, vp_size])
			for child in dlg.chips_row().get_children():
				var chip := child as Button
				if chip == null:
					continue
				chip.pressed.emit()
				await get_tree().process_frame
				await get_tree().process_frame
				assert_bool(dlg.chip_tip().visible).is_true()
				_assert_no_dialog_overlaps(
					dlg, "%s tip(%s) @ %s" % [kind, chip.tooltip_text, vp_size]
				)
			if offer:
				dlg.decline_button().pressed.emit()
			else:
				dlg.finish_reveal()
				dlg.continue_button().pressed.emit()
				if dlg.is_inside_tree() and not dlg.is_dismissed():
					dlg.finish_reveal()
					dlg.continue_button().pressed.emit()
			await get_tree().process_frame


func _assert_no_dialog_overlaps(dlg: IntroDialogue, tag: String) -> void:
	var box: Rect2 = dlg.part_rects()["box"]
	var body_scroll: Rect2 = dlg.part_rects()["body"]
	var chips_rect := dlg.chips_row().get_global_rect()
	var footer := dlg.find_child("Footer", true, false) as Label
	var footer_rect := footer.get_global_rect()
	var tip := dlg.chip_tip()
	var buttons: Array[Button] = []
	for btn in [
		dlg.continue_button(), dlg.accept_button(), dlg.decline_button(), dlg.action_button()
	]:
		if btn != null and btn.is_visible_in_tree():
			buttons.append(btn)

	assert_bool(box.grow(0.5).encloses(chips_rect)).override_failure_message(tag).is_true()
	assert_bool(box.grow(0.5).encloses(footer_rect)).override_failure_message(tag).is_true()
	assert_bool(chips_rect.intersects(body_scroll)).override_failure_message(tag).is_false()
	assert_bool(chips_rect.intersects(footer_rect)).override_failure_message(tag).is_false()
	for child in dlg.chips_row().get_children():
		var chip := child as Control
		if chip == null:
			continue
		var chip_rect := chip.get_global_rect()
		assert_bool(box.grow(0.5).encloses(chip_rect)).override_failure_message(tag).is_true()
		assert_bool(chip_rect.intersects(footer_rect)).override_failure_message(tag).is_false()
		for btn in buttons:
			var hit := chip_rect.intersects(btn.get_global_rect())
			assert_bool(hit).override_failure_message(tag).is_false()
	for btn in buttons:
		var btn_rect := btn.get_global_rect()
		assert_bool(box.grow(0.5).encloses(btn_rect)).override_failure_message(tag).is_true()
		assert_bool(chips_rect.intersects(btn_rect)).override_failure_message(tag).is_false()
		assert_bool(footer_rect.intersects(btn_rect)).override_failure_message(tag).is_false()
	if tip.visible:
		var tip_rect := tip.get_global_rect()
		assert_bool(box.grow(0.5).encloses(tip_rect)).override_failure_message(tag).is_true()
		assert_bool(tip_rect.intersects(chips_rect)).override_failure_message(tag).is_false()
		assert_bool(tip_rect.intersects(footer_rect)).override_failure_message(tag).is_false()
		for btn in buttons:
			(
				assert_bool(tip_rect.intersects(btn.get_global_rect()))
				. override_failure_message(tag)
				. is_false()
			)
