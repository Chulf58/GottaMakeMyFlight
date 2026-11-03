class_name TestCarryLanePickupLift
extends GdUnitTestSuite
## A hard case or a roller taken out of its tray at a security lane's pickup
## table into the hand (board 2fd0356b): the grip does not climb with the hand
## the move poses, and no part of the body is inside the bag on any frame.
## Drawn through the real sim and views with the walker's clips played by sim
## time, a third of a tick a frame, as the crossing probe plates it.
##
## The world is SecurityTestWorld's lane rooted at the arch on (5, 6).

const CarryContact := preload("res://spike/carry_contact.gd")
const CarryChecks := preload("res://spike/carry_probe_checks.gd")

## Highest the gripping hand may be over the feet in the move: the path's end
## (CarryLead.FLOOR_CASE_END_M) plus the knee lift it rises with
## (CarryOnProps.KNEE_LIFT_M) and 0.13 m for the grip drawn over its target.
## With the end following the hand the grip climbed to 1.66 m (case) and
## 1.56 m (roller).
const GRIP_TOP_M := 1.45

var _world: SecurityTestWorld
var _views: PassengerViews
var _subject: Passenger


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	_free()


func _free() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _world != null:
		_world.world.free_all()
		_world = null
	_subject = null


## A new lane world with the views drawing, and one passenger sent to it whose
## single bag is of `kind` (others are cleared and sent on to the gate).
func _send(kind: SecurityLooks.Kind) -> void:
	_free()
	_world = SecurityTestWorld.make(true)
	_views = PassengerViews.new()
	_views.clock = _world.world.clock
	_views.sim = _world.world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	for i in 60:
		var p := _world.world.passenger(_world.send(1))
		if SecurityLooks.bag_kind(p, 0) == kind:
			_subject = p
			return
		p.cleared = true
		p.stage = Passenger.Stage.TO_GATE


## One frame a third of a tick on, the subject's clips played by the same sim
## time (played by the headless frame's own time they hardly move).
func _frame() -> void:
	var seconds := SimClock.STEP / 3.0
	_world.world.clock.advance(seconds)
	var body := _views.node_for(_subject.id)
	if body != null:
		var player := body.get_node("AnimationPlayer") as AnimationPlayer
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.advance(seconds)
	await get_tree().process_frame
	await get_tree().create_timer(0.0, true, false, true).timeout
	_views.carry_on_props()._unposed()


## Follows the subject's bag 0 out of its tray at the pickup table into the
## hand. Returns {"frames", "top" (highest grip over the feet), "ahead" (the
## grip's forward offset in the body's frame at that frame), "k_top", "inside"
## (body points inside the bag, summed), "worst" (most in one frame)}.
func _tray_to_hand() -> Dictionary:
	var props := _views.carry_on_props()
	var sim := _world.world.sim
	var out := {"frames": 0, "top": -INF, "ahead": 0.0, "k_top": 0.0, "inside": 0, "worst": 0}
	var was_tray := false
	var in_move := false
	for i in 6000:
		await _frame()
		var st := props.bag_state(_subject.id, 0)
		if not st.has("home"):
			continue
		var home := int(st["home"]) / 4
		var k := props.transfer_progress(_subject.id, 0)
		if not in_move:
			if home == SecurityLooks.Home.TRAY and _subject.stage == Passenger.Stage.SECURITY:
				was_tray = true
			elif was_tray and home == SecurityLooks.Home.HAND and k < 1.0:
				in_move = true
			if not in_move:
				continue
		if k >= 1.0:
			break
		var body := _views.node_for(_subject.id)
		var bag: Node3D = props.props_of(_subject.id)["bags"][0]
		var hand := SecurityLooks.hand_of(sim, _subject, 0)
		var grip := body.global_transform.affine_inverse() * props.grip_of(body, hand)
		var own := CarryContact.body_points(body, CarryChecks.gripping(sim, _subject))
		var hits := CarryContact.inside_meshes(own, bag)
		out["frames"] += 1
		out["inside"] += hits
		out["worst"] = maxi(out["worst"], hits)
		if grip.y > out["top"]:
			out["top"] = grip.y
			out["ahead"] = grip.z
			out["k_top"] = k
	return out


## A hard case and a roller lifted out of their trays at the pickup table into
## the hand: the grip stays under GRIP_TOP_M and no body point is inside the
## bag. Control: each move was followed over all its frames.
func test_out_of_a_lane_tray_the_grip_stays_low_and_clear_of_the_body() -> void:
	for kind in [SecurityLooks.Kind.CASE, SecurityLooks.Kind.ROLLER]:
		_send(kind)
		assert_object(_subject).is_not_null()
		var seen := await _tray_to_hand()
		print(
			(
				"tray>hand kind %d: frames %d, grip top %.3f m (%.3f ahead, k %.2f), inside %d (worst %d)"
				% [
					kind,
					seen["frames"],
					seen["top"],
					seen["ahead"],
					seen["k_top"],
					seen["inside"],
					seen["worst"]
				]
			)
		)
		assert_int(seen["frames"]).is_greater_equal(CarryOnProps.TRANSFER_TICKS * 3 - 1)
		assert_float(seen["top"]).is_less(GRIP_TOP_M)
		assert_int(seen["inside"]).is_equal(0)
