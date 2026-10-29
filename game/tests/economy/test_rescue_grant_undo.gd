class_name TestRescueGrantUndo
extends GdUnitTestSuite
## A rescue grant cannot be farmed with remove-then-undo (decision
## build-mode-undo-design-action-receipts-with-before-values-at, point 5): the
## grant's payment clears the build history, so the pieces removed to get stuck
## cannot be undone back while the grant stays in the wallet.

var _world: PassengerTestWorld
var _mode: BuildMode
var _finances: Finances
var _grant: RescueGrant


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.finances = _finances
	add_child(_mode)
	ReferenceTerminal.build(_mode.grid)
	_world = PassengerTestWorld.make(_mode.grid, FlightSim.schedule_starts(100000))
	_world.sim.wallet = _finances.wallet
	assert_bool(_finances.wallet.from_snapshot({"balance": "0"})).is_true()
	_grant = auto_free(RescueGrant.new())
	_grant.bind(_world.clock, _world.sim, _finances.wallet)


func after_test() -> void:
	_world.free_all()
	_world = null
	_mode.free()
	_finances.free()


func test_removing_to_get_stuck_then_undoing_keeps_no_grant_undo() -> void:
	var scanners: Array = ReferenceTerminal.object_ids(_mode.grid)["scanners"]
	assert_bool(scanners.is_empty()).is_false()
	_mode.set_tool(BuildMode.Tool.REMOVE)
	for id in scanners:
		var anchor: Vector2i = _mode.grid.get_object(id)["anchor"]
		assert_bool(_mode.apply_at(_mode.grid.cell_to_world(anchor)).ok).is_true()
	# Control: before the grant, every removal can be undone.
	assert_int(_mode.undo_history().size()).is_equal(scanners.size())
	assert_bool(_grant.evaluate()).is_true()
	var granted := _finances.wallet.balance
	print("grant %d, steps left %d" % [granted, _mode.undo_history().size()])
	assert_int(granted).is_greater(0)
	assert_int(_mode.undo_history().size()).is_equal(0)
	assert_object(_mode.undo()).is_null()
	for id in scanners:
		assert_dict(_mode.grid.get_object(id)).is_empty()
	assert_int(_finances.wallet.balance).is_equal(granted)
