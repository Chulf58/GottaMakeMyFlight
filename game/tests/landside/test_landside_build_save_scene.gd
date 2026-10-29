class_name TestLandsideBuildSaveScene
extends GdUnitTestSuite
## The landside build tools in the real main scene: BuildMode is wired to the
## scene's LandsideSim, a build there is paid from the scene's wallet, and
## what the player built, closed and paid survives a whole-world save and load
## (Landside 3/4). One boot of main.tscn for the file.

const SEED := 12
const IN_LOT_0 := Vector3(32.0, 0.0, -22.0)
const IN_MULTI := Vector3(0.0, 0.0, -8.0)
const IN_BAY_1 := Vector3(20.0, 0.0, -57.0)

var _main: Node
var _mode: BuildMode
var _sim: LandsideSim
var _save: SaveGame


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_mode = _main.get_node("BuildMode")
	_sim = _main.get_node("LandsideSim")
	_save = SaveTestKit.save_game(_main)


func after() -> void:
	_main.free()


func _wallet() -> Wallet:
	return (_main.get_node("Finances") as Finances).wallet


func _build(tool: BuildMode.Tool, point: Vector3) -> void:
	_mode.set_tool(tool)
	assert_bool(_mode.apply_at(point).ok).is_true()
	_mode.set_tool(BuildMode.Tool.NONE)


func test_a_build_in_the_scene_is_paid_and_survives_a_save_and_load() -> void:
	assert_object(_mode.landside).is_same(_sim)
	var start := _wallet().balance
	_build(BuildMode.Tool.SURFACE_LOT, IN_LOT_0)
	_build(BuildMode.Tool.MULTI_STOREY, IN_MULTI)
	_build(BuildMode.Tool.CURB, IN_BAY_1)
	_build(BuildMode.Tool.LOT_GATE, IN_LOT_0)
	assert_int(_wallet().balance).is_equal(start - 1200 - 5000 - 300)
	var expected_balance := _wallet().balance
	var data := _save.snapshot()
	assert_bool(data.is_empty()).is_false()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(data, "", true, true))
	# Play the world on from the save: take it all back down.
	_mode.set_tool(BuildMode.Tool.LOT_GATE)
	_mode.apply_at(IN_LOT_0)
	_mode.set_tool(BuildMode.Tool.REMOVE)
	assert_bool(_mode.apply_at(IN_LOT_0).ok).is_true()
	assert_bool(_mode.apply_at(IN_MULTI).ok).is_true()
	assert_bool(_mode.apply_at(IN_BAY_1).ok).is_true()
	assert_array(_sim.lots_built).is_equal([false, false])
	assert_bool(_save.load_world(saved)).is_true()
	assert_array(_sim.lots_built).is_equal([true, true])
	assert_array(_sim.lots_closed).is_equal([true, false])
	assert_array(_sim.lots_paid).is_equal([1200, 5000])
	assert_array(_sim.curbs_built).is_equal([false, true])
	assert_array(_sim.curbs_paid).is_equal([0, 300])
	assert_int(_wallet().balance).is_equal(expected_balance)
