class_name TestUnlockGuideFirstOrder
extends GdUnitTestSuite
## The first major incident shows the guide's big-firsts dialog before the
## incident's own notice, whose line says "Its notice says what it is". Both
## answer IncidentDirector.major_presented and take the clock's turn in the order
## they connected, which is the order of their nodes in the main scene: the
## HUD, which holds the guide, comes before the IncidentPanel.

const MAIN := "res://main/main.tscn"

var _port: SubViewport
var _clock: SimClock
var _director: MajorTestDirector
var _unlocks: BuildUnlocks
var _guide: UnlockGuide
var _panel: IncidentPanel
var _save: SaveGame
var _changes: Array[bool] = []


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1920, 1080)
	add_child(_port)
	_clock = SimClock.new()
	_port.add_child(_clock)
	_director = MajorTestDirector.new()
	_port.add_child(_director)
	_unlocks = BuildUnlocks.new()
	_unlocks.rating = auto_free(AirportRating.new())
	_unlocks.passengers = auto_free(PassengerSim.new())
	_unlocks.manual = true
	_port.add_child(_unlocks)
	_save = SaveGame.new()
	_port.add_child(_save)
	_changes.clear()
	# The guide first, as the HUD's is in the main scene, then the panel.
	_guide = UnlockGuide.new()
	_guide.save_game = _save
	_guide.dialog_changed.connect(func(open: bool) -> void: _changes.append(open))
	_guide.mode = UnlockGuide.Mode.PROFILE
	_guide.unlocks = _unlocks
	_guide.clock = _clock
	_guide.director = _director
	_port.add_child(_guide)
	_panel = IncidentPanel.new()
	_panel.director = _director
	_panel.clock = _clock
	_panel.copy_for = MajorTestDirector.copy
	_port.add_child(_panel)


func after_test() -> void:
	_port.free()


func test_the_big_firsts_dialog_shows_before_the_incident_notice() -> void:
	var id := _director.add_scheduled()
	assert_bool(_director.present(id, false)).is_true()
	assert_bool(_guide.is_open()).is_true()
	assert_bool(_panel.is_open()).is_false()
	_guide.answer_ring()
	assert_str(_guide.dialog().body_text()).is_equal(BigFirsts.body_for([BigFirsts.INCIDENT]))
	_guide.dismiss()
	assert_bool(_guide.is_open()).is_false()
	assert_bool(_panel.is_open()).is_true()
	assert_str(_panel.dialog().body_text()).contains("A test crew")


## A guide dialog is already open when the major comes: the first waits behind
## it, and closing it moves straight to the first, never to the notice.
func test_a_first_queued_behind_an_open_dialog_still_shows_before_the_notice() -> void:
	_guide.open_dialog([2])
	_guide.answer_ring()
	assert_bool(_guide.is_open()).is_true()
	var id := _director.add_scheduled()
	assert_bool(_director.present(id, false)).is_true()
	assert_bool(_panel.is_open()).is_false()
	_guide.dismiss()
	assert_bool(_guide.is_open()).is_true()
	assert_bool(_panel.is_open()).is_false()
	assert_str(_guide.dialog().body_text()).is_equal(BigFirsts.body_for([BigFirsts.INCIDENT]))
	assert_bool(_clock.paused).is_true()
	_guide.dismiss()
	assert_bool(_guide.is_open()).is_false()
	assert_bool(_panel.is_open()).is_true()
	assert_str(_panel.dialog().body_text()).contains("A test crew")
	_panel.dialog().dismiss()
	assert_bool(_clock.paused).is_false()


func test_a_second_major_shows_only_the_incident_notice() -> void:
	var first := _director.add_scheduled()
	_director.present(first, false)
	_guide.dismiss()
	_panel.dialog().dismiss()
	assert_bool(_panel.is_open()).is_false()
	var second := _director.add_scheduled()
	_director.present(second, false)
	assert_bool(_guide.is_open()).is_false()
	assert_bool(_panel.is_open()).is_true()


func test_the_main_scene_puts_the_hud_before_the_incident_panel() -> void:
	var state := (load(MAIN) as PackedScene).get_state()
	var hud := -1
	var panel := -1
	for i in state.get_node_count():
		if state.get_node_path(i) != NodePath("."):
			if str(state.get_node_name(i)) == "PassengerHud":
				hud = i
			elif str(state.get_node_name(i)) == "IncidentPanel":
				panel = i
	print("main.tscn node order: PassengerHud %d, IncidentPanel %d" % [hud, panel])
	assert_int(hud).is_greater(-1)
	assert_int(panel).is_greater(hud)


## One open and one close for the guide, however many dialogs it showed in a
## row: the HUD counts them, and an open without a close keeps the camera off
## (test_unlock_guide_camera_gate.gd).
func test_an_in_place_swap_sends_one_open_and_one_close() -> void:
	_guide.open_dialog([2])
	_guide.answer_ring()
	_director.present(_director.add_scheduled(), false)
	_guide.dismiss()
	assert_array(_changes).is_equal([true])
	_guide.dismiss()
	assert_array(_changes).is_equal([true, false])
