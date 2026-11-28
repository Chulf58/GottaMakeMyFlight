class_name StaffInspect
extends PanelContainer
## Bottom-right inspect card for a selected hired staff member (decision
## 94ec8fbe part 1, 8f51e09c): real name, role and training tier, 1-2 cozy
## quirks, live activity, energy bar, live contextual thought, Focus button,
## and Close button. Docked via BottomDocks (RIGHT_FLOOR_GROUP) and mutually
## exclusive with PassengerInspect / BuiltItemCard.

signal closed
signal focus_requested(member_id: int)

const ENERGY_BAR_HEIGHT := 6.0

var staff: StaffSim
var views: StaffCharacters
var camera: TycoonCamera
var unlocks: BuildUnlocks
var selected_id := 0

var _name := Label.new()
var _close := Button.new()
var _role := Label.new()
var _quirks := Label.new()
var _activity := Label.new()
var _energy_box := VBoxContainer.new()
var _energy_label := Label.new()
var _energy_bar := ProgressBar.new()
var _energy_fill := StyleBoxFlat.new()
var _thought := Label.new()
var _focus := Button.new()
var _last_energy_state := -1


func _init() -> void:
	name = "StaffInspect"
	visible = false
	theme = BuildMenu.HUD_THEME
	add_to_group(BottomDocks.RIGHT_FLOOR_GROUP)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	root.add_child(header)
	_name.name = "StaffName"
	_name.theme_type_variation = &"HudLarge"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_name)
	_close.name = "CloseButton"
	_close.text = tr("×")
	_close.focus_mode = Control.FOCUS_NONE
	_close.theme_type_variation = &"HudButtonCompact"
	_close.tooltip_text = tr("Close")
	_close.pressed.connect(press_close)
	header.add_child(_close)

	_role.name = "StaffRole"
	_role.theme_type_variation = &"HudSmall"
	_role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_role)

	_quirks.name = "StaffQuirks"
	_quirks.theme_type_variation = &"HudHint"
	_quirks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_quirks)

	_activity.name = "StaffActivity"
	_activity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_activity)

	_energy_box.add_theme_constant_override("separation", 2)
	root.add_child(_energy_box)
	_energy_label.name = "StaffEnergy"
	_energy_label.theme_type_variation = &"HudSmall"
	_energy_box.add_child(_energy_label)
	_energy_bar.name = "StaffEnergyBar"
	_energy_bar.show_percentage = false
	_energy_bar.min_value = StaffMember.ENERGY_MIN
	_energy_bar.max_value = StaffMember.ENERGY_MAX
	_energy_bar.custom_minimum_size = Vector2(0.0, ENERGY_BAR_HEIGHT)
	_energy_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_energy_fill.bg_color = StaffPanel.ENERGY_RESTED_COLOR
	_energy_bar.add_theme_stylebox_override("fill", _energy_fill)
	_energy_box.add_child(_energy_bar)

	_thought.name = "StaffThought"
	_thought.theme_type_variation = &"HudHint"
	_thought.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_thought)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	root.add_child(actions)
	_focus.name = "FocusButton"
	_focus.text = tr("Focus")
	_focus.focus_mode = Control.FOCUS_NONE
	_focus.theme_type_variation = &"HudButtonTeal"
	_focus.tooltip_text = tr("Focus camera on this staff member")
	_focus.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_focus.pressed.connect(press_focus)
	actions.add_child(_focus)


func _ready() -> void:
	fit()
	get_viewport().size_changed.connect(fit)
	var menu := get_node_or_null("../../BuildMenu") as BuildMenu
	if menu != null and menu.is_node_ready():
		menu.bar().minimum_size_changed.connect(fit)
		if menu.tray() != null:
			menu.tray().visibility_changed.connect(fit)
		if menu.status_card() != null:
			menu.status_card().visibility_changed.connect(fit)
		menu.staff_toggled.connect(_on_staff_toggled)
	var panel := get_node_or_null("../../StaffPanel") as StaffPanel
	if panel != null and panel.card() != null:
		panel.card().resized.connect(fit)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_retranslate()


func _retranslate() -> void:
	_close.tooltip_text = tr("Close")
	_focus.text = tr("Focus")
	_focus.tooltip_text = tr("Focus camera on this staff member")
	refresh()


func _on_staff_toggled(_open: bool) -> void:
	fit()


## Bottom-right, clear of CategoryBar, BuildTray, StaffCard, and DebugCorner/DebugPanel.
func fit() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var layer := viewport.get_visible_rect().size
	var menu := get_node_or_null("../../BuildMenu") as BuildMenu
	var has_menu := is_instance_valid(menu) and menu.is_node_ready()
	var bar_w := 0.0 if not has_menu else menu.bar().get_combined_minimum_size().x
	var tray_open := has_menu and menu.is_tray_open()
	var stack_top := menu.stack_top() if has_menu else float(BuildMenu.MARGIN + BuildMenu.BAR_H)
	var width := float(HudLayout.RAIL_W)
	var bottom := BottomDocks.right_floor_bottom(
		get_tree(), layer, width, bar_w, tray_open, stack_top, self
	)
	custom_minimum_size = Vector2(width, 0.0)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_right = -float(HudLayout.MARGIN)
	offset_left = -float(HudLayout.MARGIN) - width
	offset_top = -bottom
	offset_bottom = -bottom
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN


## Refreshes card contents for `selected_id`; updates labels only on change to
## avoid layout flicker and calls reset_size() on visibility/text change.
func refresh() -> void:
	var m := _selected()
	if m == null:
		if visible:
			visible = false
			fit()
			reset_size()
		return
	var pax_sim := staff.sim if staff != null else null
	var next_name := m.display_name if m.display_name != "" else StaffNames.display_name_for(m.id)
	var role_name := StaffNames.role_label(m.role)
	var next_role := (
		tr("{role} · Lv. {level}").format({"role": role_name, "level": m.level})
		if StaffSim.is_role_trainable(m.role)
		else role_name
	)
	var translated_quirks := PackedStringArray()
	for q in m.quirks:
		translated_quirks.append(StaffNames.translate_quirk(q))
	var next_quirks := " · ".join(translated_quirks)
	var next_activity := StaffNames.activity_text(pax_sim, m)
	var show_energy := _energy_visible()
	var next_energy := tr("Energy {pct}%").format({"pct": m.energy}) if show_energy else ""
	var thought := StaffNames.live_thought(pax_sim, m)
	var next_thought := tr('"{thought}"').format({"thought": thought}) if thought != "" else ""
	var layout_dirty := not visible
	visible = true
	layout_dirty = _set_label(_name, next_name) or layout_dirty
	layout_dirty = _set_label(_role, next_role) or layout_dirty
	layout_dirty = _set_label(_quirks, next_quirks) or layout_dirty
	if _quirks.visible != (next_quirks != ""):
		_quirks.visible = next_quirks != ""
		layout_dirty = true
	layout_dirty = _set_label(_activity, next_activity) or layout_dirty
	if _energy_box.visible != show_energy:
		_energy_box.visible = show_energy
		layout_dirty = true
	layout_dirty = _set_label(_energy_label, next_energy) or layout_dirty
	layout_dirty = _set_label(_thought, next_thought) or layout_dirty
	if _thought.visible != (next_thought != ""):
		_thought.visible = next_thought != ""
		layout_dirty = true
	if show_energy:
		if not is_equal_approx(_energy_bar.value, float(m.energy)):
			_energy_bar.value = float(m.energy)
		var energy_state := 2 if m.is_on_break() else (1 if m.is_tired() else 0)
		if energy_state != _last_energy_state:
			_last_energy_state = energy_state
			_energy_fill.bg_color = (
				StaffPanel.ENERGY_BREAK_COLOR
				if energy_state == 2
				else (
					StaffPanel.ENERGY_TIRED_COLOR
					if energy_state == 1
					else StaffPanel.ENERGY_RESTED_COLOR
				)
			)
	var prev_bottom := offset_bottom
	fit()
	if layout_dirty or not is_equal_approx(prev_bottom, offset_bottom):
		reset_size()


func press_focus() -> void:
	if selected_id == 0:
		return
	focus_requested.emit(selected_id)
	if camera == null:
		return
	var m := _selected()
	if m == null:
		return
	if views != null and views.node_for(selected_id) != null:
		views.select(selected_id)
		camera.follow(views.follow_anchor)
		return
	if staff != null and staff.sim != null:
		var target: Variant = null
		if m.station != 0:
			target = staff.sim.grid.cell_to_world(staff.spot_of(m.station, m.slot))
		elif not m.in_pool():
			target = staff.world_position(m)
		elif not staff.sim.layout.entrances.is_empty():
			var door := staff.sim.layout.door_cell(staff.sim.grid, staff.sim.layout.entrances[0])
			target = staff.sim.grid.cell_to_world(door)
		if target != null:
			camera.glide_to(target, minf(camera.distance, AlertStack.JUMP_DISTANCE))


func press_close() -> void:
	selected_id = 0
	if views != null and views.selected_id != 0:
		views.select(0)
	if camera != null:
		camera.stop_follow()
	refresh()
	closed.emit()


func name_text() -> String:
	return _name.text


func role_text() -> String:
	return _role.text


func quirks_text() -> String:
	return _quirks.text if _quirks.visible else ""


func activity_text() -> String:
	return _activity.text


func energy_text() -> String:
	return _energy_label.text if _energy_box.visible else ""


func _energy_visible() -> bool:
	if staff != null and staff.sim != null and staff.sim.build_mode != null:
		if not staff.sim.build_mode.require_unlocks:
			return true
	if unlocks != null:
		return unlocks.allows(BuildMode.Tool.BREAK_ROOM)
	if staff != null:
		return staff.is_energy_enabled()
	return true


func thought_text() -> String:
	return _thought.text if _thought.visible else ""


func focus_button() -> Button:
	return _focus


func close_button() -> Button:
	return _close


func _set_label(label: Label, next_text: String) -> bool:
	if label.text == next_text:
		return false
	label.text = next_text
	return true


func _selected() -> StaffMember:
	if staff == null or selected_id == 0:
		return null
	return staff.get_member(selected_id)
