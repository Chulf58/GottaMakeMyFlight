class_name TestTemplatePasteUnlocks
extends GdUnitTestSuite
## A template paste is held to the build unlocks (decision build-unlocks-need-
## stars-and-passengers-served-hunger-cafe-a): a template holding a room or a
## piece of a locked tier is refused whole, with the lock text as the reason,
## so the Templates page is no way round the Build menu. The cafe saved here is
## a locked room with locked pieces; it is pasted on bare ground centred on
## (14, 14), so a refusal that leaked would lay floor and charge for it.

const CAFE := Rect2i(3, 3, 5, 4)
const BARE_CENTRE := Vector2i(14, 14)

var _mode: BuildMode
var _finances: Finances
var _paste: TemplatePaste
var _unlocks: BuildUnlocks


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_unlocks = auto_free(BuildUnlocks.new())
	_unlocks.rating = auto_free(AirportRating.new())
	_unlocks.passengers = auto_free(PassengerSim.new())
	_unlocks.manual = true
	add_child(_unlocks)
	var site := SiteDefinition.new()
	site.grid_size = Vector2i(20, 20)
	site.obstacles = [] as Array[Vector2i]
	_mode = BuildMode.new()
	_mode.site = site
	_mode.finances = _finances
	_mode.unlocks = _unlocks
	_mode.require_unlocks = true
	add_child(_mode)
	LandKit.own_all(_mode.land_tool.land)
	_mode.set_process(false)
	_paste = _mode.templates
	var edits: Array[BuildEdit] = []
	for y in range(2, 9):
		for x in range(2, 10):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	var room := _commit(BuildEdit.place_room(CAFE, &"cafe")).room_id
	_commit(BuildEdit.place_object(&"cafe_counter", Vector2i(4, 3), 0))
	_commit(BuildEdit.place_object(&"cafe_table", Vector2i(4, 5), 0))
	_mode.clear_undo()
	assert_object(_paste.save_room(room)).is_not_null()
	_paste.arm(0)


func after_test() -> void:
	_mode.free()
	_finances.free()


## A setup edit goes straight to the transaction: building the saved cafe is
## not under test, pasting it is.
func _commit(edit: BuildEdit) -> BuildResult:
	var plan: Array[BuildEdit] = [edit]
	var result := BuildTransaction.commit_plan(_mode.grid, plan, _mode.wallet())
	var why := "setup edit refused: %s" % result.reason_text()
	assert_bool(result.ok).override_failure_message(why).is_true()
	return result


func test_a_template_with_a_locked_room_and_pieces_is_refused_whole() -> void:
	var snapshot := _mode.grid.to_snapshot()
	var balance := _mode.wallet().balance
	var result := _paste.paste_at(BARE_CENTRE)
	print(
		(
			"locked paste: %s (%s), balance %d -> %d"
			% [result.ok, result.reason_text(), balance, _mode.wallet().balance]
		)
	)
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(BuildResult.Reason.LOCKED)
	assert_str(result.reason_text()).contains("Unlocks at 2 stars and 50 passengers")
	assert_int(_paste.check_at(BARE_CENTRE).reason).is_equal(BuildResult.Reason.LOCKED)
	assert_str(_paste.status_text()).contains("Unlocks at 2 stars and 50 passengers")
	assert_dict(_mode.grid.to_snapshot()).is_equal(snapshot)
	assert_int(_mode.wallet().balance).is_equal(balance)
	assert_int(_mode.undo_history().size()).is_equal(0)


## The control: the same paste goes down and is charged once the tier is open.
func test_the_same_paste_is_placed_once_the_tier_is_open() -> void:
	assert_bool(_unlocks.from_snapshot({"tier": 2, "made": 50})).is_true()
	var balance := _mode.wallet().balance
	var result := _paste.paste_at(BARE_CENTRE)
	print("unlocked paste: %s, balance %d -> %d" % [result.ok, balance, _mode.wallet().balance])
	assert_bool(result.ok).is_true()
	assert_int(_mode.grid.floor_at(BARE_CENTRE)).is_equal(BuildGrid.FLOOR_TILE)
	assert_int(_mode.wallet().balance).is_less(balance)
	assert_int(_mode.undo_history().size()).is_equal(1)


## A mode that requires the gate and has none refuses the paste too.
func test_a_paste_with_a_required_but_missing_gate_is_refused() -> void:
	_mode.unlocks = null
	var result := _paste.paste_at(BARE_CENTRE)
	assert_int(result.reason).is_equal(BuildResult.Reason.LOCKED)
	assert_str(result.reason_text()).contains(BuildUnlocks.NOT_WIRED_TEXT)
	assert_int(_mode.grid.floor_at(BARE_CENTRE)).is_equal(BuildGrid.FLOOR_NONE)


## A toilet (a tier 1 room) saved with a baggage belt in it. The Belt tool is
## tier 2 and places through its own path with no catalog object, so the belt
## has to be held to the tool by id: the toilet alone would paste at tier 1.
func _arm_toilet_with_belt() -> void:
	var floor_edits: Array[BuildEdit] = []
	for y in range(2, 6):
		for x in range(10, 14):
			floor_edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(floor_edits)
	var room := _commit(BuildEdit.place_room(Rect2i(10, 2, 3, 3), &"toilet")).room_id
	_commit(BuildEdit.place_object(&"baggage_belt", Vector2i(11, 3), 0))
	_mode.clear_undo()
	var saved := _paste.save_room(room)
	assert_object(saved).is_not_null()
	var kept := saved.pieces.filter(func(p: Dictionary) -> bool: return p["def"] == &"baggage_belt")
	assert_int(kept.size()).is_equal(1)
	_paste.arm(_paste.library.size() - 1)


func test_a_tier_1_template_holding_a_belt_is_refused_whole() -> void:
	_arm_toilet_with_belt()
	var snapshot := _mode.grid.to_snapshot()
	var balance := _mode.wallet().balance
	var result := _paste.paste_at(BARE_CENTRE)
	print("belt paste: %s (%s)" % [result.ok, result.reason_text()])
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(BuildResult.Reason.LOCKED)
	assert_dict(_mode.grid.to_snapshot()).is_equal(snapshot)
	assert_int(_mode.wallet().balance).is_equal(balance)
	assert_int(_mode.undo_history().size()).is_equal(0)


## The control: the same belt template goes down once the Belt tool is open.
func test_the_same_belt_template_is_placed_at_tier_2() -> void:
	_arm_toilet_with_belt()
	assert_bool(_unlocks.from_snapshot({"tier": 2, "made": 50})).is_true()
	var balance := _mode.wallet().balance
	var result := _paste.paste_at(BARE_CENTRE)
	print(
		"unlocked belt paste: %s, balance %d -> %d" % [result.ok, balance, _mode.wallet().balance]
	)
	assert_bool(result.ok).is_true()
	assert_int(_mode.grid.floor_at(BARE_CENTRE)).is_equal(BuildGrid.FLOOR_TILE)
	assert_int(_mode.wallet().balance).is_less(balance)
	assert_int(_mode.undo_history().size()).is_equal(1)
