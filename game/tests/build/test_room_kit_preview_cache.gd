class_name TestRoomKitPreviewCache
extends GdUnitTestSuite
## Regression tests for board f02052f2: StarterKitTool and TemplatePaste cache
## their placement/price previews across steady frames and wallet ticks,
## invalidate on cell/rotation/arm/disarm/unlock/grid changes, and keep exact
## parity with sim rules.

const SAVED_ROOM := Rect2i(2, 2, 3, 3)
const TEST_CENTRE := Vector2i(11, 7)

var _finances: Finances
var _unlocks: BuildUnlocks
var _mode: BuildMode
var _clean_snapshot := {}


func before() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_unlocks = BuildUnlocks.new()
	_unlocks.rating = auto_free(AirportRating.new())
	_unlocks.passengers = auto_free(PassengerSim.new())
	_unlocks.manual = true
	add_child(_unlocks)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.finances = _finances
	_mode.unlocks = _unlocks
	add_child(_mode)
	_mode.set_process(false)
	var floor_edits: Array[BuildEdit] = []
	for y in range(2, 16):
		for x in range(2, 16):
			floor_edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(floor_edits)
	var room := _mode.grid.apply(BuildEdit.place_room(SAVED_ROOM, &"cafe")).room_id
	assert_int(room).is_greater(0)
	var counter := BuildEdit.place_object(&"cafe_counter", Vector2i(2, 2), 0)
	assert_bool(_mode.grid.apply(counter).ok).is_true()
	var table := BuildEdit.place_object(&"cafe_table", Vector2i(4, 4), 0)
	assert_bool(_mode.grid.apply(table).ok).is_true()
	assert_object(_mode.templates.save_room(room)).is_not_null()
	_mode.clear_undo()
	_clean_snapshot = _mode.grid.to_snapshot()


func after() -> void:
	_mode.free()
	_unlocks.free()
	_finances.free()


func before_test() -> void:
	_mode.starter_kit.disarm()
	_mode.templates.disarm()
	_mode.require_unlocks = false
	(
		assert_bool(
			_unlocks.from_snapshot({"tier": 1, "made": 0, "shown": [], "seen": [], "firsts": []})
		)
		. is_true()
	)
	assert_bool(_mode.grid.from_snapshot(_clean_snapshot)).is_true()
	_mode.clear_undo()
	_finances.wallet.balance = 100000


func test_starter_kit_cache_hits_on_steady_hover_and_price_calls() -> void:
	var kit := _mode.starter_kit
	kit.arm(&"toilet")
	var base_plans := kit._plan_builds
	var base_ghosts := kit._ghost_builds

	kit._hover(TEST_CENTRE)
	var price := kit.preview_price_at(TEST_CENTRE)
	var planned := kit.plan_at(TEST_CENTRE)
	assert_int(kit._plan_builds).is_equal(base_plans + 1)
	assert_int(kit._ghost_builds).is_equal(base_ghosts + 1)
	assert_int(price.x).is_greater(0)
	assert_vector(price).is_equal(Vector2i(int(planned["net"]), int(planned["net"])))
	assert_bool((planned["result"] as BuildResult).ok).is_true()

	for _i in 10:
		kit._hover(TEST_CENTRE)
		assert_vector(kit.preview_price_at(TEST_CENTRE)).is_equal(price)
		assert_bool((kit.plan_at(TEST_CENTRE)["result"] as BuildResult).ok).is_true()

	assert_int(kit._plan_builds).is_equal(base_plans + 1)
	assert_int(kit._ghost_builds).is_equal(base_ghosts + 1)


func test_starter_kit_ignores_non_flipping_wallet_ticks_and_flips_on_affordability() -> void:
	var kit := _mode.starter_kit
	kit.arm(&"toilet")
	var cost := kit.preview_price_at(TEST_CENTRE).x
	assert_int(cost).is_greater(0)

	_finances.wallet.balance = cost + 500
	kit._hover(TEST_CENTRE)
	var plans := kit._plan_builds
	var ghosts := kit._ghost_builds

	_finances.wallet.balance = cost + 25
	kit._hover(TEST_CENTRE)
	assert_int(kit._plan_builds).is_equal(plans)
	assert_int(kit._ghost_builds).is_equal(ghosts)
	assert_bool((kit.plan_at(TEST_CENTRE)["result"] as BuildResult).ok).is_true()

	_finances.wallet.balance = cost - 1
	kit._hover(TEST_CENTRE)
	assert_int(kit._plan_builds).is_equal(plans)
	assert_int(kit._ghost_builds).is_equal(ghosts + 1)
	var short_result: BuildResult = kit.plan_at(TEST_CENTRE)["result"]
	assert_bool(short_result.ok).is_false()
	assert_int(short_result.reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_vector(kit.preview_price_at(TEST_CENTRE)).is_equal(Vector2i(cost, cost))

	_finances.wallet.balance = cost
	kit._hover(TEST_CENTRE)
	assert_int(kit._plan_builds).is_equal(plans)
	assert_int(kit._ghost_builds).is_equal(ghosts + 2)
	assert_bool((kit.plan_at(TEST_CENTRE)["result"] as BuildResult).ok).is_true()


func test_starter_kit_invalidates_on_cell_rotate_arm_disarm_and_grid_edit() -> void:
	var kit := _mode.starter_kit
	kit.arm(&"toilet")
	kit._hover(TEST_CENTRE)
	var plans := kit._plan_builds

	kit._hover(TEST_CENTRE + Vector2i(1, 0))
	assert_int(kit._plan_builds).is_equal(plans + 1)
	plans = kit._plan_builds

	kit.rotate_turns()
	kit._hover(TEST_CENTRE + Vector2i(1, 0))
	assert_int(kit._plan_builds).is_equal(plans + 1)
	plans = kit._plan_builds

	kit.arm(&"cafe")
	kit._hover(TEST_CENTRE)
	assert_int(kit._plan_builds).is_equal(plans + 1)
	plans = kit._plan_builds

	kit.disarm()
	assert_vector(kit.preview_price_at(TEST_CENTRE)).is_equal(Vector2i.ZERO)
	kit.arm(&"toilet")
	kit._hover(TEST_CENTRE)
	assert_int(kit._plan_builds).is_equal(plans + 1)
	plans = kit._plan_builds

	# Block the south doorway threshold cell (11, 9) via a grid edit.
	var bin := BuildEdit.place_object(&"trash_can", Vector2i(11, 9), 0)
	assert_bool(_mode.grid.apply(bin).ok).is_true()
	kit._hover(TEST_CENTRE)
	assert_int(kit._plan_builds).is_equal(plans + 1)
	var refused: BuildResult = kit.plan_at(TEST_CENTRE)["result"]
	assert_bool(refused.ok).is_false()
	assert_int(refused.reason).is_equal(BuildResult.Reason.DOOR_FRONT_BLOCKED)
	assert_vector(kit.preview_price_at(TEST_CENTRE)).is_equal(Vector2i.ZERO)


func test_starter_kit_place_matches_warm_preview_cost_and_invalidates_after_commit() -> void:
	var kit := _mode.starter_kit
	kit.arm(&"toilet")
	kit._hover(TEST_CENTRE)
	var cost := kit.preview_price_at(TEST_CENTRE).x
	var before_balance := _finances.wallet.balance

	var placed := kit.place_at(TEST_CENTRE)
	assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()
	assert_int(before_balance - _finances.wallet.balance).is_equal(cost)

	var after_result: BuildResult = kit.plan_at(TEST_CENTRE)["result"]
	assert_bool(after_result.ok).is_false()
	assert_int(after_result.reason).is_equal(BuildResult.Reason.ROOM_OVERLAP)
	kit._hover(TEST_CENTRE)
	assert_str(kit.status_text()).contains("Placed")
	kit._hover(TEST_CENTRE + Vector2i(1, 0))
	assert_str(kit.status_text()).not_contains("Placed")


func test_template_paste_cache_hits_and_flips_on_affordability() -> void:
	var paste := _mode.templates
	paste.arm(0)
	var base_plans := paste._plan_builds
	var base_ghosts := paste._ghost_builds

	paste._hover(TEST_CENTRE)
	var price := paste.preview_price_at(TEST_CENTRE)
	var planned := paste.plan_at(TEST_CENTRE)
	assert_int(paste._plan_builds).is_equal(base_plans + 1)
	assert_int(paste._ghost_builds).is_equal(base_ghosts + 1)
	assert_int(price.x).is_greater(0)
	assert_bool((planned["result"] as BuildResult).ok).is_true()

	for _i in 10:
		paste._hover(TEST_CENTRE)
		assert_vector(paste.preview_price_at(TEST_CENTRE)).is_equal(price)
		assert_bool((paste.plan_at(TEST_CENTRE)["result"] as BuildResult).ok).is_true()

	assert_int(paste._plan_builds).is_equal(base_plans + 1)
	assert_int(paste._ghost_builds).is_equal(base_ghosts + 1)

	_finances.wallet.balance = price.y + 42
	paste._hover(TEST_CENTRE)
	assert_int(paste._plan_builds).is_equal(base_plans + 1)
	assert_int(paste._ghost_builds).is_equal(base_ghosts + 1)

	_finances.wallet.balance = price.y - 1
	paste._hover(TEST_CENTRE)
	assert_int(paste._plan_builds).is_equal(base_plans + 1)
	assert_int(paste._ghost_builds).is_equal(base_ghosts + 2)
	var short_result: BuildResult = paste.plan_at(TEST_CENTRE)["result"]
	assert_bool(short_result.ok).is_false()
	assert_int(short_result.reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_vector(paste.preview_price_at(TEST_CENTRE)).is_equal(price)

	_finances.wallet.balance = price.y
	paste._hover(TEST_CENTRE)
	assert_int(paste._plan_builds).is_equal(base_plans + 1)
	assert_int(paste._ghost_builds).is_equal(base_ghosts + 3)
	assert_bool((paste.plan_at(TEST_CENTRE)["result"] as BuildResult).ok).is_true()


func test_template_paste_invalidates_on_cell_rotate_unlocks_grid_and_paste() -> void:
	var paste := _mode.templates
	paste.arm(0)
	paste._hover(TEST_CENTRE)
	var plans := paste._plan_builds

	paste._hover(TEST_CENTRE + Vector2i(1, 0))
	assert_int(paste._plan_builds).is_equal(plans + 1)
	plans = paste._plan_builds

	paste.rotate_turns()
	paste._hover(TEST_CENTRE + Vector2i(1, 0))
	assert_int(paste._plan_builds).is_equal(plans + 1)
	plans = paste._plan_builds

	# Locking the cafe template tier invalidates the cached acceptance.
	_mode.require_unlocks = true
	paste._hover(TEST_CENTRE)
	assert_int(paste._plan_builds).is_equal(plans + 1)
	plans = paste._plan_builds
	var locked_res: BuildResult = paste.plan_at(TEST_CENTRE)["result"]
	assert_int(locked_res.reason).is_equal(BuildResult.Reason.LOCKED)

	(
		assert_bool(
			_unlocks.from_snapshot({"tier": 2, "made": 20, "shown": [], "seen": [], "firsts": []})
		)
		. is_true()
	)
	paste._hover(TEST_CENTRE)
	assert_int(paste._plan_builds).is_equal(plans + 1)
	assert_bool((paste.plan_at(TEST_CENTRE)["result"] as BuildResult).ok).is_true()

	var price := paste.preview_price_at(TEST_CENTRE).x
	var before_balance := _finances.wallet.balance
	var pasted := paste.paste_at(TEST_CENTRE)
	assert_bool(pasted.ok).override_failure_message(pasted.reason_text()).is_true()
	assert_int(before_balance - _finances.wallet.balance).is_equal(price)
	assert_bool((paste.plan_at(TEST_CENTRE)["result"] as BuildResult).ok).is_false()
