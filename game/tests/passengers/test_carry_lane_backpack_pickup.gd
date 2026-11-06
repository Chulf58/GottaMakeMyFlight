class_name TestCarryLaneBackpackPickup
extends GdUnitTestSuite
## A backpack taken out of its tray at a security lane's pickup table and put
## on the back (board 41c159bc): the hand holding it stays under the shoulder
## joint, and a backpack carried alone is led by the hand on the table's side,
## so the pack never crosses the front of the body. Drawn through the real sim
## and views with the walker's clips played by sim time, a third of a tick a
## frame, as the crossing probe plates it.
##
## Body points inside the pack are printed, not checked: headless they read 0
## where the windowed spike/backpack_pickup_probe.gd reads up to 158 a frame
## for the same move (the leading hand's fingers in the pack), so this count
## cannot fail on the clip. The windowed probe is the check for it.
##
## The world is SecurityTestWorld's lane rooted at the arch on (5, 6), built on
## either side (the crossing probe's lane is LEFT: its pickup table is on the
## walker's left, away from the bag's own open-side right hand).

const CarryContact := preload("res://spike/carry_contact.gd")
const CarryChecks := preload("res://spike/carry_probe_checks.gd")

## [bags, body (PassengerLooks.BODIES), lane side]: a male and a female body
## with the backpack alone, and with a second bag, on both lane sides.
const SENT := [
	[1, 0, SecurityLanes.LEFT],
	[1, 6, SecurityLanes.LEFT],
	[2, 1, SecurityLanes.LEFT],
	[2, 8, SecurityLanes.LEFT],
	[1, 0, SecurityLanes.RIGHT],
	[1, 6, SecurityLanes.RIGHT],
	[2, 1, SecurityLanes.RIGHT],
	[2, 8, SecurityLanes.RIGHT],
]
## Furthest the holding hand's grip may go past the body's centre line to the
## other side. Unfixed, the right hand took the pack from a table on the left
## 0.22 m past it, 1.52 m up and 0.46 m ahead of the chest.
const CROSS_MAX_M := 0.1

var _world: SecurityTestWorld
var _views: PassengerViews
var _subject: Passenger
## Which of the subject's bags is the backpack.
var _bag := 0


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


## A new lane world on side `mirror` with the views drawing, and one passenger
## sent to it with `bags` bags, a backpack among them, drawn with body `body`;
## others are cleared and sent on to the gate.
func _send(bags: int, body: int, mirror: int) -> void:
	_free()
	_world = SecurityTestWorld.make(true, 7, mirror)
	_views = PassengerTestWorld.views()
	_views.clock = _world.world.clock
	_views.sim = _world.world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	var variant := body / PassengerLooks.PER_VARIANT
	for i in 200:
		var p := _world.world.passenger(_world.send(bags))
		if PassengerLooks.body_of(p.id, variant) == body:
			for b in bags:
				if SecurityLooks.bag_kind(p, b) == SecurityLooks.Kind.BACKPACK:
					p.variant = variant
					_subject = p
					_bag = b
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


## Follows the subject's backpack out of its tray onto the back. Returns
## {"frames", "inside" (body points inside the pack, summed), "worst" (most in
## one frame), "k_worst", "bones" (at the worst frame), "tray_x" (the tray's
## side in the body's frame, at the move's first frame), "holder" (the hand
## that held it), "held" (frames it was held), "top" (highest grip over the
## feet while held), "k_top", "shoulder" (that hand's shoulder joint then),
## "cross" (furthest the grip went past the centre line to the far side)}.
func _tray_to_back() -> Dictionary:
	var props := _views.carry_on_props()
	var sim := _world.world.sim
	var out := {
		"frames": 0,
		"inside": 0,
		"worst": 0,
		"k_worst": -1.0,
		"bones": {},
		"tray_x": 0.0,
		"holder": -1,
		"held": 0,
		"top": -INF,
		"k_top": -1.0,
		"shoulder": 0.0,
		"cross": -INF,
	}
	var was_tray := false
	var in_move := false
	for i in 6000:
		await _frame()
		var st := props.bag_state(_subject.id, _bag)
		if not st.has("home"):
			continue
		var home := int(st["home"]) / 4
		var k := props.transfer_progress(_subject.id, _bag)
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
		var bag: Node3D = props.props_of(_subject.id)["bags"][_bag]
		var to_body := body.global_transform.affine_inverse()
		if out["frames"] == 0:
			out["tray_x"] = (to_body * bag.global_position).x
		var gripping := CarryChecks.gripping(sim, _subject)
		var hits := CarryContact.inside_meshes(CarryContact.body_points(body, gripping), bag)
		out["frames"] += 1
		out["inside"] += hits
		if hits > out["worst"]:
			out["worst"] = hits
			out["k_worst"] = k
			out["bones"] = CarryChecks.contact_bones(body, gripping, bag)
		var holder := int(props.bag_state(_subject.id, _bag).get("held_by", -1))
		if holder < 0:
			continue
		var grip := to_body * props.grip_of(body, holder)
		# The body faces +Z: its right (hand 0) is -X.
		var far := grip.x if holder == 0 else -grip.x
		out["holder"] = holder
		out["held"] += 1
		out["cross"] = maxf(out["cross"], far)
		if grip.y > out["top"]:
			out["top"] = grip.y
			out["k_top"] = k
			out["shoulder"] = (to_body * props._shoulder_of(body, holder)).y
	return out


## A backpack lifted out of its tray at the pickup table onto the back, on
## either side of a lane: the highest grip while the hand holds it is under
## that hand's shoulder joint (body points inside it printed only, see above);
## carried alone it is held by the hand on the table's side and never goes
## past the centre line. Controls: the move was followed over all its frames,
## a hand held the pack, and the lanes put the table on both sides.
func test_out_of_a_lane_tray_onto_the_back_the_table_side_hand_leads() -> void:
	var sides := {}
	for sent: Array in SENT:
		_send(sent[0], sent[1], sent[2])
		assert_object(_subject).is_not_null()
		var seen := await _tray_to_back()
		print(
			(
				(
					"tray>back bags %d body %d lane %d bag %d: frames %d held %d by %d,"
					+ " tray x %.2f, inside %d (worst %d at k %.2f, %s), grip top %.3f m"
					+ " at k %.2f, shoulder %.3f m, past centre %.3f m"
				)
				% [
					sent[0],
					sent[1],
					sent[2],
					_bag,
					seen["frames"],
					seen["held"],
					seen["holder"],
					seen["tray_x"],
					seen["inside"],
					seen["worst"],
					seen["k_worst"],
					seen["bones"],
					seen["top"],
					seen["k_top"],
					seen["shoulder"],
					seen["cross"],
				]
			)
		)
		assert_int(seen["frames"]).is_greater_equal(CarryOnProps.TRANSFER_TICKS * 3 - 1)
		assert_int(seen["held"]).is_greater(0)
		assert_float(seen["top"]).is_less(seen["shoulder"])
		if sent[0] == 1:
			sides[signf(seen["tray_x"])] = true
			assert_int(seen["holder"]).is_equal(0 if seen["tray_x"] < 0.0 else 1)
			assert_float(seen["cross"]).is_less(CROSS_MAX_M)
	assert_int(sides.size()).is_equal(2)


## CarryLead.back_lead(): from the resting end's position alone (never the hand
## as drawn), the hand on its side, for a body turned any way; the bag's own
## hand for an end near the centre line, and for two bags.
func test_back_lead_is_the_hand_on_the_resting_end_side() -> void:
	for yaw in [0.0, PI / 2.0, 2.5]:
		var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(3.0, 0.2, -1.0))
		var left := frame * Vector3(0.8, 0.75, 0.3)
		var right := frame * Vector3(-0.8, 0.75, 0.3)
		var ahead := frame * Vector3(0.05, 0.75, 0.8)
		assert_int(CarryLead.back_lead(0, left, frame, 1.0)).is_equal(1)
		assert_int(CarryLead.back_lead(1, right, frame, 1.0)).is_equal(0)
		assert_int(CarryLead.back_lead(1, left, frame, 1.0)).is_equal(1)
		assert_int(CarryLead.back_lead(0, ahead, frame, 1.0)).is_equal(0)
		assert_int(CarryLead.back_lead(1, ahead, frame, 1.0)).is_equal(1)
		assert_int(CarryLead.back_lead(0, left, frame, SecurityLooks.TWO_BAG_SCALE)).is_equal(0)


## The lead of a backpack's tray>back move stamped again while the hand is
## still reaching for it (CarryLead.at_start(): the same move,
## CarryPlace._stamp keeps its start) stays the hand of the body's frame as
## the move first started, though the body has turned half round since: the
## frame of the restamp put the tray on the other side and switched the hand
## mid-reach (Sol review, board 41c159bc). Control: a new move stamped from the
## turned body is led by the other hand, so the turn would switch it.
func test_a_restamp_in_the_reach_keeps_the_lead_of_the_move_start() -> void:
	var kind := SecurityLooks.Kind.BACKPACK
	var tray_at := SecurityLooks.Home.TRAY * 4
	var hand_at := SecurityLooks.Home.HAND * 4
	var props := auto_free(CarryOnProps.new()) as CarryOnProps
	var body := auto_free(Node3D.new()) as Node3D
	var node := auto_free(Node3D.new()) as Node3D
	add_child(body)
	add_child(node)
	# The tray on the body's left (+X; the body faces +Z), the bag's own hand the right.
	node.global_position = Vector3(0.6, 0.8, 0.4)
	var want := CarryWorn.worn_back(Transform3D(Basis(), Vector3(0.0, 1.35, -0.05)), 0.0, 1.0)
	var held := {"homes": [SecurityLooks.Home.HAND]}
	var bag := {
		"node": node,
		"kind": kind,
		"home": tray_at,
		"place": hand_at,
		"changed": 10.0,
		"carry": SecurityLooks.Carry.BACK,
		"carry_placed": SecurityLooks.Carry.BACK,
	}
	var dims := {
		"hand": 0,
		"grips": [Vector3(-0.2, 0.9, 0.05), Vector3(0.2, 0.9, 0.05)],
		"shoulders_y": [1.42, 1.42],
		"bar_z": 0.0,
		"scale": 1.0,
		"strap_top": Vector3.ZERO,
	}
	var flags := {
		"in_stall": false,
		"hand_carry": false,
		"from_floor": false,
		"to_floor": false,
		"hand": 0,
		"clear": CarryOnProps.TRANSFER_CLEAR_M,
		"yaw": 0.0,
	}
	var start := node.global_transform
	var k := CarryLead.REACH_SHARE * 0.5
	CarryPlace._stamp(props, held, bag, body, want, 0)
	var first: Array = (
		CarryLead.plan(bag, k, start, want, body.global_transform, flags, dims)["loops"]
	)
	# Drawn in the reach; the body turns half round; the move is stamped again.
	bag["placed_k"] = k
	assert_bool(CarryLead.at_start(bag, k)).is_true()
	body.rotate_y(PI)
	flags["yaw"] = PI
	bag["changed"] = 11.0
	CarryPlace._stamp(props, held, bag, body, want, 0)
	var again: Array = (
		CarryLead.plan(bag, k, start, want, body.global_transform, flags, dims)["loops"]
	)
	# A new move from the turned body: the other hand.
	var fresh := bag.duplicate()
	fresh.erase("start_body")
	var turned: Array = (
		CarryLead.plan(fresh, k, start, want, body.global_transform, flags, dims)["loops"]
	)
	print(
		"lead loops: first %s, restamped %s, new from the turned body %s" % [first, again, turned]
	)
	assert_array(first).is_equal([false, true])
	assert_array(again).is_equal(first)
	assert_array(turned).is_equal([true, false])
