class_name TestGateCardTranslation
extends GdUnitTestSuite
## The gate desk card and the gate caption say the waiting line through
## GateDesks.waiting_text() and the walk line through GateWalk.card_line()
## (Sol review of the merged translation lanes, finding 2). The caption's own
## lines are checked in test_world_caption_translation.gd (board t7); here only
## its waiting line is. Fixture: the second shell past the west
## spur of test_spur_move_waiting_gate, where gate A waits for the taxiway works.

const SITE := preload("res://build/terminal_site.tres")
const WEST_SHELL := Vector2i(-62, 0)

var _base: SiteGrid
var _grid: SiteGrid
var _flights: FlightSim
var _gates: GateDesks
var _desk := 0


func before() -> void:
	_base = SpurMoveKit.base_grid()
	for result in _base.apply_batch(
		ReferenceTerminal.shell_edits(SITE.starter_offset + WEST_SHELL)
	):
		assert_bool(result.ok).is_true()


func before_test() -> void:
	_grid = _base.clone() as SiteGrid
	_flights = auto_free(FlightSim.new()) as FlightSim
	_flights.open_airport()
	_gates = auto_free(GateDesks.new()) as GateDesks
	add_child(_gates)
	_gates.bind(_grid, _flights)
	_grid.guard = _gates.edit_problem
	var at := SpurMoveKit.WEST_EXIT + SITE.starter_offset + WEST_SHELL
	assert_bool(_grid.apply(BuildEdit.remove_wall(at, BuildGrid.Side.WEST)).ok).is_true()
	assert_bool(_grid.apply(BuildEdit.place_object(&"exit_door", at, 3)).ok).is_true()
	var desk := SpurMoveKit.WEST_DESK + SITE.starter_offset + WEST_SHELL
	var placed := _grid.apply(BuildEdit.place_object(GateDesks.DESK, desk, 0))
	assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()
	_desk = placed.object_id


## A pseudolocalized string without its bracket and padding lead: "[___Cafe___]"
## becomes "Cafe___]". The bracket itself is asserted by the caller.
func _bare(text: String) -> String:
	assert_str(text).starts_with("[")
	return text.lstrip("[_")


func after_test() -> void:
	PseudoLocale.disable()
	TranslationServer.pseudolocalization_enabled = false
	TranslationServer.reload_pseudolocalization()


func test_the_card_and_the_caption_say_the_waiting_line_in_the_players_words() -> void:
	assert_bool(_gates.waits_on_spur("A")).is_true()
	var card := auto_free(BuiltItemCard.new()) as BuiltItemCard
	card.gates = _gates
	assert_str(card._gate_planes(_desk)).is_equal(GateDesks.WAITING_TEXT)
	assert_str(GateLinksView.caption_text("A", "", GateWalk.NO_ROUTE, true)).is_equal(
		"Gate A\n%s" % GateDesks.WAITING_TEXT
	)
	PseudoLocale.enable(0.4)
	var on_card := card._gate_planes(_desk)
	var on_caption := GateLinksView.caption_text("A", "", GateWalk.NO_ROUTE, true)
	print("waiting: card '%s' | caption '%s'" % [on_card, on_caption])
	assert_str(on_card).is_equal(GateDesks.waiting_text())
	assert_str(on_card).starts_with("[")
	var caption_lines := on_caption.split("\n")
	assert_str(_bare(caption_lines[0])).starts_with("Gate A")
	assert_str(caption_lines[1]).is_equal(GateDesks.waiting_text())


func test_the_card_walk_line_is_one_translated_template() -> void:
	assert_str(GateWalk.card_line(12)).is_equal("Walk from security: 12 min")
	assert_str(GateWalk.card_line(GateWalk.NO_ROUTE)).is_equal("Walk from security: no route")
	PseudoLocale.enable(0.4)
	var minutes := GateWalk.card_line(12)
	var none := GateWalk.card_line(GateWalk.NO_ROUTE)
	print("walk: '%s' | '%s'" % [minutes, none])
	assert_str(_bare(minutes)).starts_with("Walk from security: 12 min")
	assert_str(_bare(none)).starts_with("Walk from security: no route")
