class_name TestGateWalkEdits
extends GdUnitTestSuite
## The gate walk readout (GateWalk) follows the edits that change a route, from
## events alone: the desk card and the build caption are never asked per frame
## (the tests call neither refresh_walk() nor a poll; they step the sim and
## wait a frame, as the game does). One worker world has seats, one has none,
## so its gate's first place is a standing spot. Each case puts back what it
## took (GateWalkWorld.restore_scanners()).

var _seated: GateWalkWorld
var _seatless: GateWalkWorld


func before() -> void:
	PassengerTestWorld.tracker = self
	_seated = GateWalkWorld.make(self, true)
	_seated.attach_views(self)
	_seatless = GateWalkWorld.make(self, false)
	_seatless.attach_views(self)


func after() -> void:
	PassengerTestWorld.tracker = null
	_seated.free_all()
	_seatless.free_all()


func after_test() -> void:
	_seated.restore_scanners()
	_seatless.restore_scanners()


func _captions(gate: GateWalkWorld) -> Array:
	var out := []
	for caption in gate.view.gate_captions():
		out.append(caption.text)
	return out


func _remove(gate: GateWalkWorld, station: int) -> void:
	var removed := gate.world.grid.apply(BuildEdit.remove_object(station))
	assert_bool(removed.ok).override_failure_message(removed.reason_text()).is_true()


## One sim tick and a frame, so the standing spots are derived again and the
## views' deferred refresh has run.
func _settle(gate: GateWalkWorld) -> void:
	gate.world.step()
	await get_tree().process_frame
	gate.card.refresh()


func test_an_edit_that_changes_the_route_changes_both_readouts() -> void:
	_seated.card.refresh()
	var before_line := _seated.card.field_text("walk")
	var before_caption: String = _captions(_seated)[0]
	var worked := _seated.card.walk.computed
	# The far scanner goes: the longest walk is now from the near exit.
	_remove(_seated, _seated.far_station)
	await _settle(_seated)
	var after_line := _seated.card.field_text("walk")
	var after_caption: String = _captions(_seated)[0]
	print(
		(
			"card '%s' then '%s'; caption '%s' then '%s'"
			% [before_line, after_line, before_caption, after_caption]
		)
	)
	assert_str(before_line).is_equal("Walk from security: 15 min")
	assert_str(after_line).is_equal("Walk from security: 4 min")
	assert_str(after_caption).is_equal("Gate A\nup to large planes\n4 min walk")
	assert_str(before_caption).is_equal("Gate A\nup to large planes\n15 min walk")
	assert_int(_seated.card.walk.computed).is_equal(worked + 1)


func test_with_no_security_exit_the_card_says_no_route_and_the_caption_drops_the_line() -> void:
	_seated.card.refresh()
	_remove(_seated, _seated.far_station)
	_remove(_seated, _seated.near_station)
	await _settle(_seated)
	print("card '%s'; captions %s" % [_seated.card.field_text("walk"), _captions(_seated)])
	assert_str(_seated.card.field_text("walk")).is_equal("Walk from security: no route")
	assert_array(_captions(_seated)).is_equal(["Gate A\nup to large planes"])


func test_a_seatless_gate_goes_from_no_route_to_a_walk_when_a_route_opens() -> void:
	var gate := _seatless
	gate.card.refresh()
	_remove(gate, gate.far_station)
	_remove(gate, gate.near_station)
	await _settle(gate)
	var closed_line := gate.card.field_text("walk")
	var closed_captions := _captions(gate)
	# The route opens: a scanner is built again. Until the next tick the
	# standing spots are not derived again, and whatever is read then is not kept.
	gate.near_station = PassengerTestWorld.place(
		gate.world.grid, &"security_scanner", GateWalkWorld.NEAR_SCANNER, 0
	)
	await get_tree().process_frame
	var stale_worked := gate.view.walk.computed
	# A read while the spots are stale is worked out each time, never kept.
	var asked := gate.card.walk
	var asked_before := asked.computed
	asked.minutes("A")
	asked.minutes("A")
	var stale_reads := asked.computed - asked_before
	var was_stale := gate.world.sim.standing.stale
	await _settle(gate)
	var open_line := gate.card.field_text("walk")
	var open_captions := _captions(gate)
	print(
		(
			"closed '%s' %s; open '%s' %s (view worked %d then %d)"
			% [
				closed_line,
				closed_captions,
				open_line,
				open_captions,
				stale_worked,
				gate.view.walk.computed,
			]
		)
	)
	assert_str(closed_line).is_equal("Walk from security: no route")
	assert_array(closed_captions).is_equal(["Gate A\nup to large planes"])
	assert_bool(was_stale).is_true()
	assert_int(stale_reads).is_equal(2)
	assert_bool(gate.world.sim.standing.stale).is_false()
	assert_int(gate.view.walk.computed).is_greater(stale_worked)
	var card_form := RegEx.create_from_string("^Walk from security: [1-9]\\d* min$")
	var caption_form := RegEx.create_from_string(
		"^Gate A\\nup to large planes\\n[1-9]\\d* min walk$"
	)
	assert_bool(card_form.search(open_line) != null).override_failure_message(open_line).is_true()
	assert_array(open_captions).has_size(1)
	(
		assert_bool(caption_form.search(open_captions[0]) != null)
		. override_failure_message(open_captions[0])
		. is_true()
	)
