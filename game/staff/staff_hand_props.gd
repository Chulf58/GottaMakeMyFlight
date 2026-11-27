class_name StaffHandProps
extends RefCounted
## Lightweight view-only procedural hand props attached to staff Hand.R / Hand.L
## via BoneAttachment3D without modifying any character .glb skeleton (e7517650).
## Props are visible only in their active matching station pose mode and hidden
## when walking, tucked, idle, pooled, or snapped on load (6d949060).

enum PropKind {
	NONE,
	WAND,
	BOARDING_PASS,
	CLIPBOARD,
	COFFEE_CUP,
	BROOM,
	RAG,
	MARSHAL_WANDS,
	TRASH_BAG,
	COFFEE_MUG,
	PHONE,
	MAGAZINE,
	CLOTH,
}

const TOON_BASE := preload("res://assets/materials/tp_atlas_simple_toon.tres")
const PROP_META := &"staff_hand_props"
const BROOM_CARRY_META := &"broom_carry_arm"
const BAG_CARRY_META := &"bag_carry_arm"
const WEIGHT_MIN := 0.3
const OUTLINE_PX := 1.0
const OUTLINE_BIAS_M := 0.002
const BROOM_SWEEP_POS := Vector3(0.025, 0.075, -0.14)
const BROOM_SWEEP_ROT_DEG := Vector3(90.0, 0.0, 0.0)
const BROOM_CARRY_POS := Vector3(0.032, 0.095, 0.015)
const BROOM_CARRY_ROT_DEG := Vector3(98.0, 0.0, -4.0)
const BROOM_CARRY_UPPER_DEG := 4.0
const BROOM_CARRY_HALF_WIDTH := 0.27
const BROOM_CARRY_UP_DEG := -16.0


class BroomCarryModifier:
	extends CarryArm

	func _process_modification_with_delta(delta: float) -> void:
		super._process_modification_with_delta(delta)
		var skeleton := get_skeleton()
		if skeleton == null:
			return
		var hand_idx := skeleton.find_bone(HANDS[side])
		if hand_idx < 0:
			return
		var hand := skeleton.get_bone_global_pose(hand_idx)
		var axis := hand.basis.y.normalized()
		var thumb_now := hand.basis.z - axis * hand.basis.z.dot(axis)
		var up_proj := Vector3.UP - axis * Vector3.UP.dot(axis)
		if thumb_now.length() > 0.001 and up_proj.length() > 0.001:
			var angle := thumb_now.normalized().signed_angle_to(up_proj.normalized(), axis)
			hand.basis = Basis(axis, angle) * hand.basis
			skeleton.set_bone_global_pose(hand_idx, hand)


const COLOR_WAND_GRIP := Color(0.18, 0.21, 0.27)
const COLOR_WAND_HEAD := Color(0.28, 0.38, 0.52)
const COLOR_WAND_LED := Color(0.96, 0.68, 0.22)
const COLOR_PASS_CARD := Color(0.96, 0.94, 0.88)
const COLOR_PASS_STRIPE := Color(0.16, 0.64, 0.78)
const COLOR_CLIPBOARD_BOARD := Color(0.68, 0.48, 0.28)
const COLOR_CLIPBOARD_PAPER := Color(0.95, 0.95, 0.92)
const COLOR_CLIPBOARD_CLIP := Color(0.32, 0.36, 0.42)
const COLOR_CUP_BODY := Color(0.92, 0.88, 0.80)
const COLOR_CUP_SLEEVE := Color(0.60, 0.40, 0.24)
const COLOR_CUP_COFFEE := Color(0.22, 0.13, 0.08)
const COLOR_MUG_BODY := Color(0.26, 0.62, 0.68)
const COLOR_MUG_RIM := Color(0.96, 0.94, 0.88)
const COLOR_PHONE_CASE := Color(0.18, 0.22, 0.28)
const COLOR_PHONE_SCREEN := Color(0.68, 0.86, 0.96)
const COLOR_MAG_COVER := Color(0.92, 0.44, 0.34)
const COLOR_MAG_PAGES := Color(0.97, 0.95, 0.90)
const COLOR_MAG_STRIPE := Color(0.24, 0.56, 0.72)
const COLOR_CLOTH_MAIN := Color(0.34, 0.72, 0.80)
const COLOR_CLOTH_FOLD := Color(0.56, 0.84, 0.88)
const COLOR_BROOM_POLE := Color(0.62, 0.45, 0.27)
const COLOR_BROOM_HEAD := Color(0.24, 0.48, 0.62)
const COLOR_BROOM_BRISTLE := Color(0.86, 0.78, 0.56)
const COLOR_RAG_CLOTH := Color(0.92, 0.84, 0.32)
const COLOR_MARSHAL_TIP := Color(1.0, 0.56, 0.08)
const COLOR_BAG_BODY := Color(0.16, 0.18, 0.22)
const COLOR_BAG_TIE := Color(0.86, 0.24, 0.22)

static var _white_tex: ImageTexture
static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}


## Deterministic Break Room hand prop rotated by staff member id.
static func break_prop_for(member_id: int) -> PropKind:
	match posmod(member_id, 3):
		0:
			return PropKind.COFFEE_MUG
		1:
			return PropKind.PHONE
		_:
			return PropKind.MAGAZINE


## Matching StaffStationPose.SubMode for a Break Room prop kind.
static func break_sub_mode_for(kind: PropKind) -> StaffStationPose.SubMode:
	match kind:
		PropKind.COFFEE_MUG:
			return StaffStationPose.SubMode.BREAK_COFFEE
		PropKind.PHONE:
			return StaffStationPose.SubMode.BREAK_PHONE
		PropKind.MAGAZINE:
			return StaffStationPose.SubMode.BREAK_MAGAZINE
	return StaffStationPose.SubMode.NONE


## Which prop should be shown right now for the given pose state.
static func desired_prop(
	mode: StaffStationPose.Mode,
	sub_mode: StaffStationPose.SubMode,
	weight: float,
	sim_time: float,
	seed_id: int,
	walking: bool,
	tucked: bool,
	role: int = -1,
	job_bin: bool = false,
	cleaner_working: bool = false,
	cleaner_patrolling: bool = false,
	cleaner_bag: bool = false,
) -> PropKind:
	if tucked:
		return PropKind.NONE
	if role == StaffMember.Role.CLEANER:
		if cleaner_bag:
			return PropKind.TRASH_BAG
		if cleaner_working:
			return PropKind.RAG if job_bin else PropKind.BROOM
		if cleaner_patrolling:
			return PropKind.BROOM
		return PropKind.NONE
	if (
		mode == StaffStationPose.Mode.RAMP_PUSHBACK
		and sub_mode == StaffStationPose.SubMode.RAMP_GUIDE
		and weight > WEIGHT_MIN
	):
		return PropKind.MARSHAL_WANDS
	if walking or weight <= WEIGHT_MIN:
		return PropKind.NONE
	if mode == StaffStationPose.Mode.BREAK_SEATED or mode == StaffStationPose.Mode.BREAK_CHAT:
		return _break_prop_from_sub(sub_mode)
	if role == StaffMember.Role.RAMP and mode == StaffStationPose.Mode.IDLE_FIDGET:
		if sub_mode == StaffStationPose.SubMode.NONE:
			return PropKind.CLIPBOARD
	match mode:
		StaffStationPose.Mode.SECURITY_SCAN:
			return PropKind.WAND
		StaffStationPose.Mode.GATE:
			return PropKind.BOARDING_PASS
		StaffStationPose.Mode.CHECKIN:
			if StaffStationPose.checkin_prop_active(sim_time, seed_id):
				return PropKind.BOARDING_PASS
		StaffStationPose.Mode.SHOP:
			if sub_mode == StaffStationPose.SubMode.SHOP_INFO_DESK:
				return PropKind.CLIPBOARD
			if (
				(
					sub_mode == StaffStationPose.SubMode.SHOP_CAFE
					or sub_mode == StaffStationPose.SubMode.SHOP_BAR
				)
				and StaffStationPose.cafe_cup_active(sim_time, seed_id)
			):
				return PropKind.COFFEE_CUP
		StaffStationPose.Mode.RAMP_MARSHAL:
			return PropKind.MARSHAL_WANDS
		StaffStationPose.Mode.REACTION_WIPE:
			return PropKind.CLOTH
		StaffStationPose.Mode.REACTION_CLIPBOARD:
			if sub_mode != StaffStationPose.SubMode.REACT_WATCH:
				return PropKind.CLIPBOARD
		StaffStationPose.Mode.IDLE_FIDGET:
			if sub_mode == StaffStationPose.SubMode.LULL_WIPE:
				return PropKind.CLOTH
			if sub_mode == StaffStationPose.SubMode.LULL_CLIPBOARD:
				return PropKind.CLIPBOARD
	return PropKind.NONE


static func _break_prop_from_sub(sub_mode: StaffStationPose.SubMode) -> PropKind:
	match sub_mode:
		StaffStationPose.SubMode.BREAK_COFFEE:
			return PropKind.COFFEE_MUG
		StaffStationPose.SubMode.BREAK_PHONE:
			return PropKind.PHONE
		StaffStationPose.SubMode.BREAK_MAGAZINE:
			return PropKind.MAGAZINE
	return PropKind.NONE


## Updates prop visibility on `node` for the current frame's pose state.
static func update(
	node: Node3D,
	mode: StaffStationPose.Mode,
	sub_mode: StaffStationPose.SubMode,
	weight: float,
	sim_time: float,
	seed_id: int,
	walking: bool,
	tucked: bool,
	role: int = -1,
	job_bin: bool = false,
	cleaner_working: bool = false,
	cleaner_patrolling: bool = false,
	cleaner_bag: bool = false,
) -> void:
	var kind := desired_prop(
		mode,
		sub_mode,
		weight,
		sim_time,
		seed_id,
		walking,
		tucked,
		role,
		job_bin,
		cleaner_working,
		cleaner_patrolling,
		cleaner_bag,
	)
	if kind == PropKind.NONE and not node.has_meta(PROP_META):
		if node.has_meta(BROOM_CARRY_META):
			_set_broom_carry(node, false)
		if node.has_meta(BAG_CARRY_META):
			_set_bag_carry(node, false)
		return
	var rec := _ensure(node)
	if rec.is_empty():
		return
	var props: Dictionary = rec["props"]
	for key: int in props:
		var prop_node := props[key] as Node3D
		prop_node.visible = (key == kind)
	var extra: Dictionary = rec.get("extra", {})
	for key: int in extra:
		for prop_node: Node3D in extra[key]:
			prop_node.visible = (key == kind)
	var carry_broom := kind == PropKind.BROOM and not cleaner_working
	var carry_bag := kind == PropKind.TRASH_BAG and not cleaner_working
	var broom := props.get(PropKind.BROOM) as Node3D
	if broom != null:
		broom.position = BROOM_CARRY_POS if carry_broom else BROOM_SWEEP_POS
		broom.rotation_degrees = BROOM_CARRY_ROT_DEG if carry_broom else BROOM_SWEEP_ROT_DEG
	_set_broom_carry(node, carry_broom)
	_set_bag_carry(node, carry_bag)


## Hides every attached prop on `node` (used on snap/load and pool release).
static func hide_all(node: Node3D) -> void:
	if node == null:
		return
	_set_broom_carry(node, false)
	_set_bag_carry(node, false)
	if not node.has_meta(PROP_META):
		return
	var rec: Dictionary = node.get_meta(PROP_META)
	var props: Dictionary = rec.get("props", {})
	for key: int in props:
		var prop_node := props[key] as Node3D
		if is_instance_valid(prop_node):
			prop_node.visible = false
			if key == PropKind.BROOM:
				prop_node.position = BROOM_SWEEP_POS
				prop_node.rotation_degrees = BROOM_SWEEP_ROT_DEG
	var extra: Dictionary = rec.get("extra", {})
	for key: int in extra:
		for prop_node: Node3D in extra[key]:
			if is_instance_valid(prop_node):
				prop_node.visible = false


## Returns the CarryArm modifier used for cleaner broom carry on `node`, or null.
static func broom_carry_arm_of(node: Node3D) -> CarryArm:
	if node == null or not node.has_meta(BROOM_CARRY_META):
		return null
	return node.get_meta(BROOM_CARRY_META) as CarryArm


static func _set_broom_carry(node: Node3D, carry_active: bool) -> void:
	if not carry_active and not node.has_meta(BROOM_CARRY_META):
		return
	var arm: BroomCarryModifier
	if node.has_meta(BROOM_CARRY_META):
		arm = node.get_meta(BROOM_CARRY_META) as BroomCarryModifier
	else:
		var skeletons := node.find_children("*", "Skeleton3D", true, false)
		if skeletons.is_empty():
			return
		var skeleton := skeletons[0] as Skeleton3D
		arm = BroomCarryModifier.new()
		arm.name = "BroomCarryArm"
		arm.side = 0
		arm.holds = true
		arm.front_weight = 1.0
		arm.front_upper_degrees = BROOM_CARRY_UPPER_DEG
		arm.front_half_width = BROOM_CARRY_HALF_WIDTH
		arm.front_up_degrees = BROOM_CARRY_UP_DEG
		arm.grip_curl = 1.0
		arm.active = false
		skeleton.add_child(arm)
		node.set_meta(BROOM_CARRY_META, arm)
	if is_instance_valid(arm):
		arm.active = carry_active


static func _set_bag_carry(node: Node3D, carry_active: bool) -> void:
	if not carry_active and not node.has_meta(BAG_CARRY_META):
		return
	var arm: CarryArm
	if node.has_meta(BAG_CARRY_META):
		arm = node.get_meta(BAG_CARRY_META) as CarryArm
	else:
		var skeletons := node.find_children("*", "Skeleton3D", true, false)
		if skeletons.is_empty():
			return
		var skeleton := skeletons[0] as Skeleton3D
		arm = CarryArm.new()
		arm.name = "BagCarryArm"
		arm.side = 0
		arm.holds = true
		arm.angle_degrees = 15.0
		arm.swing_kept = 0.28
		arm.lean_back_degrees = -6.0
		arm.rest_twist_weight = 1.0
		arm.twist_degrees = 6.0
		arm.grip_curl = 1.0
		arm.active = false
		skeleton.add_child(arm)
		node.set_meta(BAG_CARRY_META, arm)
	if is_instance_valid(arm):
		arm.active = carry_active


## Currently visible PropKind on `node`, or PropKind.NONE.
static func active_prop(node: Node3D) -> PropKind:
	if node == null or not node.has_meta(PROP_META):
		return PropKind.NONE
	var rec: Dictionary = node.get_meta(PROP_META)
	var props: Dictionary = rec.get("props", {})
	for key: int in props:
		var prop_node := props[key] as Node3D
		if is_instance_valid(prop_node) and prop_node.visible:
			return key as PropKind
	var extra: Dictionary = rec.get("extra", {})
	for key: int in extra:
		for prop_node: Node3D in extra[key]:
			if is_instance_valid(prop_node) and prop_node.visible:
				return key as PropKind
	return PropKind.NONE


## Returns the primary prop Node3D for `kind` on `node` (lazily attaching if needed).
static func prop_node(node: Node3D, kind: PropKind) -> Node3D:
	if kind == PropKind.NONE or node == null:
		return null
	var rec := _ensure(node)
	if rec.is_empty():
		return null
	return (rec["props"] as Dictionary).get(kind)


## Returns all prop Node3Ds for `kind` on `node` (including dual-hand companions).
static func prop_nodes(node: Node3D, kind: PropKind) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if kind == PropKind.NONE or node == null:
		return out
	var rec := _ensure(node)
	if rec.is_empty():
		return out
	var primary: Node3D = (rec["props"] as Dictionary).get(kind)
	if primary != null:
		out.append(primary)
	var extra: Dictionary = rec.get("extra", {})
	if extra.has(kind):
		for n: Node3D in extra[kind]:
			out.append(n)
	return out


static func _ensure(node: Node3D) -> Dictionary:
	if node.has_meta(PROP_META):
		return node.get_meta(PROP_META)
	var skeletons := node.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return {}
	var skeleton := skeletons[0] as Skeleton3D
	var att_r := _attach(skeleton, "Hand.R", "StaffProp_R")
	var att_l := _attach(skeleton, "Hand.L", "StaffProp_L")
	var props := {
		PropKind.WAND: _add_prop(att_r, _build_wand()),
		PropKind.BOARDING_PASS: _add_prop(att_r, _build_boarding_pass()),
		PropKind.COFFEE_CUP: _add_prop(att_r, _build_coffee_cup()),
		PropKind.CLIPBOARD: _add_prop(att_l, _build_clipboard()),
		PropKind.BROOM: _add_prop(att_r, _build_broom()),
		PropKind.RAG: _add_prop(att_r, _build_rag()),
		PropKind.MARSHAL_WANDS: _add_prop(att_r, _build_marshal_wand("MarshalWandR", true)),
		PropKind.COFFEE_MUG: _add_prop(att_r, _build_coffee_mug()),
		PropKind.PHONE: _add_prop(att_r, _build_phone()),
		PropKind.MAGAZINE: _add_prop(att_r, _build_magazine()),
		PropKind.CLOTH: _add_prop(att_r, _build_cloth()),
		PropKind.TRASH_BAG: _add_prop(att_r, _build_trash_bag()),
	}
	var extra := {
		PropKind.MARSHAL_WANDS: [_add_prop(att_l, _build_marshal_wand("MarshalWandL", false))],
	}
	var rec := {"att_r": att_r, "att_l": att_l, "props": props, "extra": extra}
	node.set_meta(PROP_META, rec)
	return rec


static func _attach(skeleton: Skeleton3D, bone: String, node_name: String) -> BoneAttachment3D:
	var att := BoneAttachment3D.new()
	att.name = node_name
	att.bone_name = bone
	skeleton.add_child(att)
	return att


static func _add_prop(parent: BoneAttachment3D, prop: Node3D) -> Node3D:
	prop.visible = false
	parent.add_child(prop)
	return prop


## Hand.R axes: +Y along fingers, +Z thumb side, +X palm normal.
static func _build_wand() -> Node3D:
	var root := Node3D.new()
	root.name = "Wand"
	root.position = Vector3(0.028, 0.085, 0.016)
	root.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	var grip := _part(
		"Grip",
		_cyl_mesh("wand_grip", 0.015, 0.014, 0.11),
		COLOR_WAND_GRIP,
		Vector3(0.0, -0.01, 0.0),
	)
	var paddle := _part(
		"Paddle",
		_box_mesh("wand_paddle", Vector3(0.018, 0.16, 0.052)),
		COLOR_WAND_HEAD,
		Vector3(0.0, 0.115, 0.0),
	)
	var led := _part(
		"Led",
		_box_mesh("wand_led", Vector3(0.022, 0.022, 0.056)),
		COLOR_WAND_LED,
		Vector3(0.0, 0.05, 0.0),
	)
	root.add_child(grip)
	root.add_child(paddle)
	root.add_child(led)
	return root


static func _build_boarding_pass() -> Node3D:
	var root := Node3D.new()
	root.name = "BoardingPass"
	root.position = Vector3(0.024, 0.135, 0.018)
	root.rotation_degrees = Vector3(0.0, 12.0, -8.0)
	var card := _part(
		"Card",
		_box_mesh("pass_card", Vector3(0.005, 0.13, 0.072)),
		COLOR_PASS_CARD,
		Vector3.ZERO,
	)
	var stripe := _part(
		"Stripe",
		_box_mesh("pass_stripe", Vector3(0.007, 0.028, 0.074)),
		COLOR_PASS_STRIPE,
		Vector3(0.0, 0.036, 0.0),
	)
	root.add_child(card)
	root.add_child(stripe)
	return root


## Hand.L axes: +Y along fingers, +Z thumb (upward when gripping), -X palm normal.
static func _build_clipboard() -> Node3D:
	var root := Node3D.new()
	root.name = "Clipboard"
	root.position = Vector3(-0.028, 0.095, 0.020)
	root.rotation_degrees = Vector3(0.0, -18.0, 14.0)
	var board := _part(
		"Board",
		_box_mesh("clip_board", Vector3(0.012, 0.17, 0.22)),
		COLOR_CLIPBOARD_BOARD,
		Vector3.ZERO,
	)
	var paper := _part(
		"Paper",
		_box_mesh("clip_paper", Vector3(0.005, 0.135, 0.18)),
		COLOR_CLIPBOARD_PAPER,
		Vector3(-0.006, 0.0, -0.006),
	)
	var clip := _part(
		"Clip",
		_box_mesh("clip_metal", Vector3(0.018, 0.056, 0.024)),
		COLOR_CLIPBOARD_CLIP,
		Vector3(-0.003, 0.0, 0.092),
	)
	root.add_child(board)
	root.add_child(paper)
	root.add_child(clip)
	return root


## Hand.R thumb-up grip aligns upright cup cylinder along Hand.R +Z.
static func _build_coffee_cup() -> Node3D:
	var root := Node3D.new()
	root.name = "CoffeeCup"
	root.position = Vector3(0.036, 0.088, 0.018)
	root.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var body := _part(
		"Body",
		_cyl_mesh("cup_body", 0.036, 0.027, 0.098),
		COLOR_CUP_BODY,
		Vector3.ZERO,
	)
	var sleeve := _part(
		"Sleeve",
		_cyl_mesh("cup_sleeve", 0.035, 0.032, 0.038),
		COLOR_CUP_SLEEVE,
		Vector3(0.0, -0.004, 0.0),
	)
	var coffee := _part(
		"Coffee",
		_cyl_mesh("cup_top", 0.033, 0.033, 0.006),
		COLOR_CUP_COFFEE,
		Vector3(0.0, 0.048, 0.0),
	)
	root.add_child(body)
	root.add_child(sleeve)
	root.add_child(coffee)
	return root


static func _build_coffee_mug() -> Node3D:
	var root := Node3D.new()
	root.name = "CoffeeMug"
	root.position = Vector3(0.036, 0.088, 0.018)
	root.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var body := _part(
		"Body",
		_cyl_mesh("mug_body", 0.038, 0.035, 0.092),
		COLOR_MUG_BODY,
		Vector3.ZERO,
	)
	var rim := _part(
		"Rim",
		_cyl_mesh("mug_rim", 0.040, 0.040, 0.012),
		COLOR_MUG_RIM,
		Vector3(0.0, 0.044, 0.0),
	)
	var coffee := _part(
		"Coffee",
		_cyl_mesh("mug_top", 0.034, 0.034, 0.006),
		COLOR_CUP_COFFEE,
		Vector3(0.0, 0.048, 0.0),
	)
	var handle := _part(
		"Handle",
		_box_mesh("mug_handle", Vector3(0.022, 0.052, 0.014)),
		COLOR_MUG_BODY,
		Vector3(-0.042, 0.0, 0.0),
	)
	root.add_child(body)
	root.add_child(rim)
	root.add_child(coffee)
	root.add_child(handle)
	return root


static func _build_phone() -> Node3D:
	var root := Node3D.new()
	root.name = "Phone"
	root.position = Vector3(0.030, 0.100, 0.015)
	root.rotation_degrees = Vector3(8.0, 22.0, -14.0)
	var chassis := _part(
		"Chassis",
		_box_mesh("phone_chassis", Vector3(0.012, 0.145, 0.078)),
		COLOR_PHONE_CASE,
		Vector3.ZERO,
	)
	var screen := _part(
		"Screen",
		_box_mesh("phone_screen", Vector3(0.005, 0.130, 0.068)),
		COLOR_PHONE_SCREEN,
		Vector3(-0.006, 0.0, 0.0),
	)
	root.add_child(chassis)
	root.add_child(screen)
	return root


static func _build_magazine() -> Node3D:
	var root := Node3D.new()
	root.name = "Magazine"
	root.position = Vector3(0.034, 0.125, 0.022)
	root.rotation_degrees = Vector3(10.0, -32.0, -16.0)
	var pages := _part(
		"Pages",
		_box_mesh("mag_pages", Vector3(0.018, 0.22, 0.17)),
		COLOR_MAG_PAGES,
		Vector3.ZERO,
	)
	var cover := _part(
		"Cover",
		_box_mesh("mag_cover", Vector3(0.006, 0.218, 0.168)),
		COLOR_MAG_COVER,
		Vector3(0.009, 0.0, 0.0),
	)
	var stripe := _part(
		"Stripe",
		_box_mesh("mag_stripe", Vector3(0.008, 0.038, 0.154)),
		COLOR_MAG_STRIPE,
		Vector3(0.010, 0.062, 0.0),
	)
	root.add_child(pages)
	root.add_child(cover)
	root.add_child(stripe)
	return root


static func _build_cloth() -> Node3D:
	var root := Node3D.new()
	root.name = "WipeCloth"
	root.position = Vector3(0.032, 0.088, 0.014)
	root.rotation_degrees = Vector3(12.0, 10.0, -8.0)
	var pad := _part(
		"Pad",
		_box_mesh("cloth_pad", Vector3(0.032, 0.13, 0.13)),
		COLOR_CLOTH_MAIN,
		Vector3.ZERO,
	)
	var fold := _part(
		"Fold",
		_box_mesh("cloth_fold", Vector3(0.022, 0.095, 0.095)),
		COLOR_CLOTH_FOLD,
		Vector3(-0.012, 0.01, 0.0),
	)
	root.add_child(pad)
	root.add_child(fold)
	return root


static func _build_broom() -> Node3D:
	var root := Node3D.new()
	root.name = "Broom"
	root.position = BROOM_SWEEP_POS
	root.rotation_degrees = BROOM_SWEEP_ROT_DEG
	var pole := _part(
		"Pole",
		_cyl_mesh("broom_pole", 0.014, 0.014, 1.32),
		COLOR_BROOM_POLE,
		Vector3(0.0, -0.24, 0.0),
	)
	var head := _part(
		"Head",
		_box_mesh("broom_head", Vector3(0.24, 0.045, 0.065)),
		COLOR_BROOM_HEAD,
		Vector3(0.0, -0.90, 0.0),
	)
	var bristles := _part(
		"Bristles",
		_box_mesh("broom_bristles", Vector3(0.25, 0.08, 0.07)),
		COLOR_BROOM_BRISTLE,
		Vector3(0.0, -0.96, 0.0),
	)
	root.add_child(pole)
	root.add_child(head)
	root.add_child(bristles)
	return root


static func _build_rag() -> Node3D:
	var root := Node3D.new()
	root.name = "Rag"
	root.position = Vector3(0.032, 0.09, 0.014)
	root.rotation_degrees = Vector3(8.0, 12.0, -6.0)
	var cloth := _part(
		"Cloth",
		_box_mesh("rag_cloth", Vector3(0.045, 0.14, 0.12)),
		COLOR_RAG_CLOTH,
		Vector3.ZERO,
	)
	root.add_child(cloth)
	return root


static func _build_marshal_wand(node_name: String, right_hand: bool) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.position = Vector3(0.026 if right_hand else -0.026, 0.09, 0.018)
	root.rotation_degrees = Vector3(-10.0, 0.0, 0.0)
	var grip := _part(
		"Grip",
		_cyl_mesh("mw_grip", 0.016, 0.015, 0.12),
		COLOR_WAND_GRIP,
		Vector3(0.0, 0.0, 0.0),
	)
	var cone := _part(
		"Cone",
		_cyl_mesh("mw_cone", 0.022, 0.018, 0.24),
		COLOR_MARSHAL_TIP,
		Vector3(0.0, 0.18, 0.0),
		1.65,
	)
	root.add_child(grip)
	root.add_child(cone)
	return root


static func _build_trash_bag() -> Node3D:
	var root := Node3D.new()
	root.name = "TrashBag"
	# Centered inside gripped Hand.R palm so gathered neck sits in fist and sack hangs along +Y.
	root.position = Vector3(0.026, 0.092, 0.012)
	var crest := _part(
		"Crest",
		_cyl_mesh("bag_crest", 0.044, 0.022, 0.042),
		COLOR_BAG_BODY,
		Vector3(0.0, -0.028, 0.0),
	)
	var tie := _part(
		"Tie",
		_cyl_mesh("bag_tie", 0.028, 0.028, 0.026),
		COLOR_BAG_TIE,
		Vector3(0.0, 0.002, 0.0),
	)
	var neck := _part(
		"Neck",
		_cyl_mesh("bag_neck", 0.024, 0.058, 0.072),
		COLOR_BAG_BODY,
		Vector3(0.0, 0.046, 0.0),
	)
	var shoulder := _part(
		"Shoulder",
		_cyl_mesh("bag_shoulder", 0.058, 0.124, 0.112),
		COLOR_BAG_BODY,
		Vector3(0.0, 0.134, 0.0),
	)
	var body := _part(
		"Body",
		_cyl_mesh("bag_body", 0.124, 0.132, 0.136),
		COLOR_BAG_BODY,
		Vector3(0.0, 0.252, 0.0),
	)
	var base := _part(
		"Base",
		_cyl_mesh("bag_base", 0.132, 0.076, 0.064),
		COLOR_BAG_BODY,
		Vector3(0.0, 0.348, 0.0),
	)
	root.add_child(crest)
	root.add_child(tie)
	root.add_child(neck)
	root.add_child(shoulder)
	root.add_child(body)
	root.add_child(base)
	return root


static func _part(
	part_name: String, mesh: Mesh, color: Color, pos: Vector3, light_gain := 1.0
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.material_override = _material(color, light_gain)
	mi.position = pos
	return mi


static func _material(color: Color, light_gain := 1.0) -> ShaderMaterial:
	var key := "%d:%s" % [color.to_rgba32(), str(light_gain)]
	if _materials.has(key):
		return _materials[key]
	if _white_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.set_pixel(0, 0, Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	var mat := TOON_BASE.duplicate() as ShaderMaterial
	mat.set_shader_parameter("albedo_texture", _white_tex)
	mat.set_shader_parameter("albedo_tint", color)
	mat.set_shader_parameter("light_gain", light_gain)
	if mat.next_pass is ShaderMaterial:
		var outline := (mat.next_pass as ShaderMaterial).duplicate() as ShaderMaterial
		outline.set_shader_parameter("outline_px", OUTLINE_PX)
		outline.set_shader_parameter("depth_bias_m", OUTLINE_BIAS_M)
		mat.next_pass = outline
	_materials[key] = mat
	return mat


static func _box_mesh(key: String, size: Vector3) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var box := BoxMesh.new()
	box.size = size
	var mesh := _to_welded_mesh(box)
	_meshes[key] = mesh
	return mesh


static func _cyl_mesh(key: String, top_r: float, bottom_r: float, height: float) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var cyl := CylinderMesh.new()
	cyl.top_radius = top_r
	cyl.bottom_radius = bottom_r
	cyl.height = height
	cyl.radial_segments = 10
	cyl.rings = 1
	var mesh := _to_welded_mesh(cyl)
	_meshes[key] = mesh
	return mesh


static func _to_welded_mesh(prim: PrimitiveMesh) -> ArrayMesh:
	var arrays := prim.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var custom := PackedByteArray()
	if not verts.is_empty() and normals.size() == verts.size():
		custom = _welded_custom0(verts, normals, indices)
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	var mesh := ArrayMesh.new()
	var flags := 0
	if not custom.is_empty():
		flags = Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh


static func _welded_custom0(
	verts: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array
) -> PackedByteArray:
	var pos_keys: Array[Vector3i] = []
	pos_keys.resize(verts.size())
	var sum_by_pos := {}
	var weight_by_pos := {}
	for vi in verts.size():
		var v := verts[vi]
		pos_keys[vi] = Vector3i(roundi(v.x * 10000.0), roundi(v.y * 10000.0), roundi(v.z * 10000.0))
	var tri_count := indices.size() if not indices.is_empty() else verts.size()
	for base in range(0, tri_count, 3):
		var idx0 := indices[base] if not indices.is_empty() else base
		var idx1 := indices[base + 1] if not indices.is_empty() else base + 1
		var idx2 := indices[base + 2] if not indices.is_empty() else base + 2
		var p := [verts[idx0], verts[idx1], verts[idx2]]
		var idxs := [idx0, idx1, idx2]
		for k in 3:
			var ea: Vector3 = p[(k + 1) % 3] - p[k]
			var eb: Vector3 = p[(k + 2) % 3] - p[k]
			var la := ea.length()
			var lb := eb.length()
			if la < 1e-6 or lb < 1e-6:
				continue
			var angle := acos(clampf(ea.dot(eb) / (la * lb), -1.0, 1.0))
			if angle <= 1e-6:
				continue
			var ci: int = idxs[k]
			var key := pos_keys[ci]
			sum_by_pos[key] = sum_by_pos.get(key, Vector3.ZERO) + normals[ci].normalized() * angle
			weight_by_pos[key] = float(weight_by_pos.get(key, 0.0)) + angle
	var smooth_by_pos := {}
	for key: Vector3i in sum_by_pos:
		var total_w := float(weight_by_pos[key])
		var sum_n: Vector3 = sum_by_pos[key]
		if total_w > 0.0 and sum_n.length() > 0.15 * total_w:
			smooth_by_pos[key] = sum_n.normalized()
	var min_dot_by_pos := {}
	for vi in verts.size():
		var key := pos_keys[vi]
		if smooth_by_pos.has(key):
			var d: float = (smooth_by_pos[key] as Vector3).dot(normals[vi].normalized())
			min_dot_by_pos[key] = minf(float(min_dot_by_pos.get(key, 1.0)), d)
	var custom := PackedByteArray()
	custom.resize(verts.size() * 4)
	for vi in verts.size():
		var key := pos_keys[vi]
		var n := normals[vi].normalized()
		var miter := 1.0
		if smooth_by_pos.has(key):
			n = smooth_by_pos[key]
			var min_d := float(min_dot_by_pos[key])
			if min_d > 0.2:
				miter = clampf(1.0 / min_d, 1.0, 1.5)
		var off := vi * 4
		custom[off] = clampi(roundi((n.x * 0.5 + 0.5) * 255.0), 0, 255)
		custom[off + 1] = clampi(roundi((n.y * 0.5 + 0.5) * 255.0), 0, 255)
		custom[off + 2] = clampi(roundi((n.z * 0.5 + 0.5) * 255.0), 0, 255)
		var a_f := 0.6 + 0.4 * clampf((miter - 1.0) / 0.5, 0.0, 1.0)
		custom[off + 3] = clampi(roundi(a_f * 255.0), 0, 255)
	return custom
