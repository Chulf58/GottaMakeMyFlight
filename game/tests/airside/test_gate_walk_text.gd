class_name TestGateWalkText
extends GdUnitTestSuite
## Where the player reads a gate's walk time (GateWalk; decision gate-walk-time-
## shows-on-desk-card-and-build-caption-longest-walk-from-security): the gate
## desk card says "Walk from security: N min", and in build mode the gate
## caption over the desk gets a third line "N min walk". Nothing is worked out
## again while nothing changes. The edits that change the figures are in
## TestGateWalkEdits. The world is GateWalkWorld: gate A and two security
## scanners, the far one 22 cells from the near one, built once for the file.

var _gate: GateWalkWorld


func before() -> void:
	PassengerTestWorld.tracker = self
	_gate = GateWalkWorld.make(self)
	_gate.attach_views(self)


func after() -> void:
	PassengerTestWorld.tracker = null
	_gate.free_all()


func _captions() -> Array:
	var out := []
	for caption in _gate.view.gate_captions():
		out.append(caption.text)
	return out


func test_the_desk_card_and_the_caption_show_the_longest_walk() -> void:
	_gate.card.refresh()
	_gate.view.refresh_walk()
	var line := _gate.card.field_text("walk")
	var captions := _captions()
	print("card: '%s'; captions %s" % [line, captions])
	assert_str(line).is_equal("Walk from security: 15 min")
	assert_array(captions).is_equal(["Gate A\nup to large planes\n15 min walk"])
	# Biggest plane and status keep their lines.
	assert_str(_gate.card.field_text("planes")).is_equal("Biggest plane: Large")
	assert_str(_gate.card.field_text("status")).is_equal("Status: Linked to Gate A")


func test_nothing_is_worked_out_again_while_nothing_changes() -> void:
	_gate.card.refresh()
	_gate.view.refresh_walk()
	var card_worked := _gate.card.walk.computed
	var view_worked := _gate.view.walk.computed
	for i in 5:
		_gate.world.step()
		_gate.card.refresh()
		_gate.view.refresh_walk()
		await get_tree().process_frame
	print(
		(
			"card worked %d then %d, view %d then %d"
			% [card_worked, _gate.card.walk.computed, view_worked, _gate.view.walk.computed]
		)
	)
	assert_int(card_worked).is_greater(0)
	assert_int(view_worked).is_greater(0)
	assert_int(_gate.card.walk.computed).is_equal(card_worked)
	assert_int(_gate.view.walk.computed).is_equal(view_worked)


func test_a_view_without_a_sim_shows_the_two_line_caption() -> void:
	var bare := GateLinksView.new()
	add_child(bare)
	bare.bind(_gate.world.grid, _gate.gates)
	bare.refresh_walk()
	var captions: Array = bare.gate_captions().map(func(c: Label3D) -> String: return c.text)
	bare.free()
	assert_array(captions).is_equal(["Gate A\nup to large planes"])
