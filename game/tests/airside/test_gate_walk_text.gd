class_name TestGateWalkText
extends GdUnitTestSuite
## Where the player reads a gate's walk time (GateWalk; decision gate-walk-time-
## shows-on-desk-card-and-build-caption-longest-walk-from-security): the gate
## desk card says "Walk from security: N min", and in build mode the gate
## caption over the desk gets a third line "N min walk". Both follow an edit
## that changes the route, and nothing is worked out again while nothing
## changes. With no route the card says so and the caption has no third line.
## The world is GateWalkWorld: gate A and two security scanners, the far one
## 22 cells from the near one.

var _gate: GateWalkWorld
var _mode: BuildMode
var _finances: Finances
var _card: BuiltItemCard
var _view: GateLinksView


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_gate = GateWalkWorld.make(self)
	var sim := _gate.world.sim
	# The card wants a build mode (it reads only a landside pick from it); in
	# the tree, so its own member nodes are parented and freed with it.
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.site = GateWalkWorld.SITE
	_mode.finances = _finances
	add_child(_mode)
	_mode.set_process(false)
	_card = BuiltItemCard.new()
	_card.sim = sim
	_card.build_mode = _mode
	_card.gates = _gate.gates
	_card.selection = BuiltSelection.new()
	_card.selection.kind = BuiltSelection.Kind.OBJECT
	_card.selection.id = _gate.desk
	add_child(_card)
	_view = GateLinksView.new()
	add_child(_view)
	_view.bind(_gate.world.grid, _gate.gates)
	_view.bind_walk(sim)


func after_test() -> void:
	_view.free()
	_card.free()
	_mode.free()
	_finances.free()
	_gate.free_all()


func _captions() -> Array:
	var out := []
	for caption in _view.gate_captions():
		out.append(caption.text)
	return out


func _refresh() -> void:
	_card.invalidate()
	_card.refresh()
	_view.refresh_walk()


func test_the_desk_card_and_the_caption_show_the_longest_walk() -> void:
	_card.refresh()
	_view.refresh_walk()
	var line := _card.field_text("walk")
	var captions := _captions()
	print("card: '%s'; captions %s" % [line, captions])
	assert_str(line).is_equal("Walk from security: 15 min")
	assert_array(captions).is_equal(["Gate A\nup to large planes\n15 min walk"])
	# Biggest plane and status keep their lines.
	assert_str(_card.field_text("planes")).is_equal("Biggest plane: Large")
	assert_str(_card.field_text("status")).is_equal("Status: Linked to Gate A")


func test_nothing_is_worked_out_again_while_nothing_changes() -> void:
	_refresh()
	var walk := _card.walk
	var worked := walk.computed
	var view_worked := _view.walk.computed
	for i in 5:
		_gate.world.step()
		_refresh()
	print(
		(
			"worked %d then %d (view %d then %d)"
			% [worked, walk.computed, view_worked, _view.walk.computed]
		)
	)
	assert_int(worked).is_equal(1)
	assert_int(walk.computed).is_equal(worked)
	assert_int(_view.walk.computed).is_equal(view_worked)


func test_an_edit_that_changes_the_route_changes_both_readouts() -> void:
	_refresh()
	var before_line := _card.field_text("walk")
	var before_caption: String = _captions()[0]
	var worked := _card.walk.computed
	# The far scanner goes: the longest walk is now from the near exit.
	var removed := _gate.world.grid.apply(BuildEdit.remove_object(_gate.far_station))
	assert_bool(removed.ok).override_failure_message(removed.reason_text()).is_true()
	_gate.world.step()
	_refresh()
	var after_line := _card.field_text("walk")
	var after_caption: String = _captions()[0]
	print(
		(
			"card '%s' then '%s'; caption '%s' then '%s'"
			% [before_line, after_line, before_caption, after_caption]
		)
	)
	assert_str(before_line).is_equal("Walk from security: 15 min")
	assert_str(after_line).is_not_equal(before_line)
	assert_str(after_line).starts_with("Walk from security: ")
	assert_str(after_line).ends_with(" min")
	assert_str(after_caption).is_not_equal(before_caption)
	assert_str(after_caption).ends_with(" min walk")
	assert_int(_card.walk.computed).is_equal(worked + 1)


func test_with_no_security_exit_the_card_says_no_route_and_the_caption_drops_the_line() -> void:
	_refresh()
	for station in [_gate.far_station, _gate.near_station]:
		var removed := _gate.world.grid.apply(BuildEdit.remove_object(station))
		assert_bool(removed.ok).override_failure_message(removed.reason_text()).is_true()
	_gate.world.step()
	_refresh()
	print("card '%s'; captions %s" % [_card.field_text("walk"), _captions()])
	assert_str(_card.field_text("walk")).is_equal("Walk from security: no route")
	assert_array(_captions()).is_equal(["Gate A\nup to large planes"])


func test_a_view_without_a_sim_shows_the_two_line_caption() -> void:
	var bare := GateLinksView.new()
	add_child(bare)
	bare.bind(_gate.world.grid, _gate.gates)
	bare.refresh_walk()
	var captions: Array = bare.gate_captions().map(func(c: Label3D) -> String: return c.text)
	bare.free()
	assert_array(captions).is_equal(["Gate A\nup to large planes"])
