class_name TestSecuritySearchBubbles
extends GdUnitTestSuite
## Frequent diegetic security search feedback (decision
## frequent-security-searches-live-in-world-comic-belt-keys-liq):
## - CarryOnTraits uses 8% alarm and 12% liquids rates (time-only cost)
## - Deterministic tr()-localized comic bubbles during active REPACK
## - "I'm late!" wins priority over security search bubbles (and declutters ahead)
## - Bubbles clear immediately once REPACK completes
## - Inspect card & PassengerThoughts display the matching localized thought
## - Zero modal/right-side alert cards or mood/money penalties triggered

const SAMPLES := 5000
const SEED := 20261123
const TOLERANCE := 0.02

var _security: SecurityTestWorld
var _world: PassengerTestWorld
var _screen: SubViewport


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	PseudoLocale.disable()
	if _screen != null:
		_screen.free()
		_screen = null
	if _security != null:
		_security.world.free_all()
		_security = null
	if _world != null:
		_world.free_all()
		_world = null


func _bubble_of(views: PassengerViews, id: int) -> Label3D:
	return views.node_for(id).get_node("Bubble") as Label3D


func _run_until_repack(w: SecurityTestWorld, id: int, limit := 600) -> bool:
	var guard := 0
	while w.world.passenger(id).security_phase != SecurityRuntime.Phase.REPACK and guard < limit:
		w.world.step()
		guard += 1
	return w.world.passenger(id).security_phase == SecurityRuntime.Phase.REPACK


func test_updated_alarm_and_liquids_rates_match_8_and_12_percent() -> void:
	assert_int(CarryOnTraits.ALARM_PERCENT).is_equal(8)
	assert_int(CarryOnTraits.LIQUIDS_PERCENT).is_equal(12)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var alarms := 0
	var liquids := 0
	for i in SAMPLES:
		var p := Passenger.new()
		CarryOnTraits.draw(rng, p)
		alarms += int(p.alarm)
		liquids += int(p.liquids)
	assert_float(alarms / float(SAMPLES)).is_equal_approx(0.08, TOLERANCE)
	assert_float(liquids / float(SAMPLES)).is_equal_approx(0.12, TOLERANCE)


func test_reason_selection_is_deterministic_per_id_and_uses_right_pool() -> void:
	var seen_alarm := {}
	var seen_liquids := {}
	for pid in range(1, 40):
		var a := Passenger.new()
		a.id = pid
		a.stage = Passenger.Stage.SECURITY
		a.security_phase = SecurityRuntime.Phase.REPACK
		a.alarm = true
		var first_a := SecuritySearchReasons.bubble_of(a)
		var second_a := SecuritySearchReasons.bubble_of(a)
		assert_str(first_a).is_equal(second_a)
		assert_array(SecuritySearchReasons.ALARM_BUBBLES).contains([first_a])
		seen_alarm[first_a] = true

		# When both alarm and liquids are set, alarm pool stays deterministic.
		a.liquids = true
		assert_str(SecuritySearchReasons.bubble_of(a)).is_equal(first_a)

		var l := Passenger.new()
		l.id = pid
		l.stage = Passenger.Stage.SECURITY
		l.security_phase = SecurityRuntime.Phase.REPACK
		l.liquids = true
		var first_l := SecuritySearchReasons.bubble_of(l)
		assert_str(first_l).is_equal(SecuritySearchReasons.bubble_of(l))
		assert_array(SecuritySearchReasons.LIQUIDS_BUBBLES).contains([first_l])
		seen_liquids[first_l] = true

	assert_int(seen_alarm.size()).is_equal(SecuritySearchReasons.ALARM_BUBBLES.size())
	assert_int(seen_liquids.size()).is_equal(SecuritySearchReasons.LIQUIDS_BUBBLES.size())


func test_late_wins_priority_over_security_bubble_and_bubble_clears_when_done() -> void:
	_security = SecurityTestWorld.make(true)
	var id := _security.send(1, false, true)
	assert_bool(_run_until_repack(_security, id)).is_true()
	var p := _security.world.passenger(id)
	var expected := SecuritySearchReasons.bubble_of(p)
	assert_str(expected).is_not_empty()
	assert_str(_security.world.sim.bubble_text(p)).is_equal(expected)

	# "I'm late!" wins over the security search bubble on the same passenger.
	p.late = true
	assert_str(_security.world.sim.bubble_text(p)).is_equal(BubbleDeclutter.LATE_TEXT)
	p.late = false
	assert_str(_security.world.sim.bubble_text(p)).is_equal(expected)

	# BubbleDeclutter keeps "I'm late!" over an overlapping security search bubble.
	var late_entry := BubbleDeclutter.entry(
		200,
		BubbleDeclutter.LATE_TEXT,
		BubbleDeclutter.NO_QUEUE,
		Rect2(Vector2.ZERO, Vector2(80, 24))
	)
	var search_entry := BubbleDeclutter.entry(
		id, expected, BubbleDeclutter.NO_QUEUE, Rect2(Vector2(4, 4), Vector2(80, 24))
	)
	assert_array(BubbleDeclutter.hidden([search_entry, late_entry])).is_equal([id])

	# BubbleDeclutter shows active security search bubbles live in the default view.
	assert_str(BubbleDeclutter.shown_text(expected, false, false, false)).is_equal(expected)
	assert_str(BubbleDeclutter.shown_text("Queue full", false, false, false)).is_empty()

	# Clears immediately when REPACK ends.
	while p.security_phase == SecurityRuntime.Phase.REPACK:
		_security.world.step()
	assert_bool(p.incident_resolved).is_true()
	assert_str(_security.world.sim.bubble_text(p)).is_empty()


func test_views_show_live_bubble_in_default_view_and_clear_on_finish() -> void:
	_security = SecurityTestWorld.make(true)
	var id := _security.send(1, true, false)
	_screen = SubViewport.new()
	_screen.size = Vector2i(1280, 720)
	add_child(_screen)
	var views := PassengerTestWorld.views()
	views.clock = _security.world.clock
	views.sim = _security.world.sim
	_screen.add_child(views)
	PassengerTestWorld.ensure_overlay(views)
	var rig := TycoonCamera.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	_screen.add_child(rig)
	rig.set_process(false)
	camera.make_current()

	assert_bool(_run_until_repack(_security, id)).is_true()
	var p := _security.world.passenger(id)
	var want := SecuritySearchReasons.bubble_of(p)
	assert_array(SecuritySearchReasons.LIQUIDS_BUBBLES).contains([want])
	var pos := _security.world.sim.world_position(p)
	camera.global_position = pos + Vector3(0.0, 8.0, 6.0)
	camera.look_at(pos + Vector3(0.0, 1.5, 0.0))
	views.sync()
	views.draw()
	var label := _bubble_of(views, id)
	assert_bool(views.all_bubbles).is_false()
	assert_bool(label.visible).is_true()
	assert_str(label.text).is_equal(want)

	while p.security_phase == SecurityRuntime.Phase.REPACK:
		_security.world.step()
	views.sync()
	views.draw()
	assert_str(label.text).is_empty()


func test_inspect_thought_matches_bubble_routes_through_tr_and_no_alerts_or_penalties() -> void:
	_security = SecurityTestWorld.make(true)
	var wallet := Wallet.new(500)
	_security.world.sim.wallet = wallet
	var id := _security.send(1, false, true)
	var p := _security.world.passenger(id)
	var mood_before := p.mood
	var money_before := wallet.balance

	assert_bool(_run_until_repack(_security, id)).is_true()
	var bubble := SecuritySearchReasons.bubble_of(p)
	var idx := SecuritySearchReasons.reason_index(p.id, true)
	var want_thought := SecuritySearchReasons.ALARM_THOUGHTS[idx]

	# No mood/money penalty and no modal/alert stack causes triggered.
	assert_int(p.mood).is_equal(mood_before)
	assert_int(wallet.balance).is_equal(money_before)
	assert_array(AlertSources.queue_full(_security.world.sim)).is_empty()
	assert_array(AlertSources.no_route(_security.world.sim)).is_empty()
	assert_array(AlertSources.gate_full(_security.world.sim)).is_empty()
	assert_array(AlertSources.closed_stations(_security.world.sim)).is_empty()

	# Recorded PassengerThoughts entry matches the alarm reason and scanner station.
	var entries := PassengerThoughts.entries(p)
	assert_int(entries.size()).is_equal(1)
	assert_int(entries[0]["kind"]).is_equal(PassengerThoughts.Kind.SECURITY_ALARM)
	assert_int(entries[0]["facility"]).is_equal(_security.station)
	assert_bool(entries[0]["positive"]).is_false()
	assert_str(entries[0]["text"]).is_equal(want_thought)
	assert_str(PassengerInspect.now_line(_security.world.sim, p)).is_equal(
		'Security search: "%s"' % bubble
	)

	# Pseudolocalization proves bubble, now_line, and thought all route through tr().
	PseudoLocale.enable(0.4)
	var tr_bubble := BubbleWords.say(bubble)
	var tr_now := PassengerInspect.now_line(_security.world.sim, p)
	var tr_thought: String = PassengerThoughts.entries(p)[0]["text"]
	assert_str(tr_bubble).starts_with("[")
	assert_str(tr_bubble.lstrip("[_")).starts_with(bubble)
	assert_str(tr_now).starts_with("[")
	assert_str(tr_now).contains(bubble)
	assert_str(tr_thought).starts_with("[")
	assert_str(tr_thought.lstrip("[_")).starts_with(want_thought)
	PseudoLocale.disable()

	# Snapshot round-trip keeps the security search thought with no schema bump.
	var snap: Dictionary = JSON.parse_string(JSON.stringify(_security.world.sim.to_snapshot()))
	var loaded_world := SecurityTestWorld.make(true)
	assert_bool(loaded_world.world.sim.from_snapshot(snap)).is_true()
	var loaded_p := loaded_world.world.passenger(id)
	assert_array(PassengerThoughts.entries(loaded_p)).is_equal(PassengerThoughts.entries(p))
	loaded_world.world.free_all()

	# Once REPACK ends, now_line clears while the thought stays in the log.
	while p.security_phase == SecurityRuntime.Phase.REPACK:
		_security.world.step()
	assert_str(PassengerInspect.now_line(_security.world.sim, p)).is_empty()
	assert_int(PassengerThoughts.entries(p).size()).is_equal(1)


func test_every_new_security_search_msgid_is_in_messages_pot() -> void:
	var entries := PotEntries.parse(FileAccess.get_file_as_string("res://locale/messages.pot"))
	for msg: String in SecuritySearchReasons.ALARM_BUBBLES + SecuritySearchReasons.LIQUIDS_BUBBLES:
		assert_int(PotEntries.count(entries, BubbleWords.CONTEXT, msg)).is_equal(1)
		assert_int(PotEntries.complete(entries, BubbleWords.CONTEXT, msg)).is_equal(1)
	for msg: String in (
		SecuritySearchReasons.ALARM_THOUGHTS + SecuritySearchReasons.LIQUIDS_THOUGHTS
	):
		assert_int(PotEntries.count(entries, "", msg)).is_equal(1)
		assert_int(PotEntries.complete(entries, "", msg)).is_equal(1)
	assert_int(PotEntries.count(entries, "", 'Security search: \\"{reason}\\"')).is_equal(1)
	assert_int(PotEntries.complete(entries, "", 'Security search: \\"{reason}\\"')).is_equal(1)
