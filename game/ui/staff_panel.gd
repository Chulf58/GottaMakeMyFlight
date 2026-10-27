class_name StaffPanel
extends CanvasLayer
## The hiring panel (Staff S2): for check-in agents and security officers, how
## many are hired and how many are on duty, with Hire and Fire buttons that go
## through StaffSim. Nobody is placed by hand: hired staff walk to a station
## on their own (ruling staff-are-hired-by-role-into-a-pool-and-walk-to-
## unstaffed-st). A new game has no staff, so the panel carries the hint
## (ruling staff-a-new-game-starts-with-an-empty-staff-pool-and-a-hint): once a
## desk stands and no agent is hired it asks for one, and the same for a
## scanner and an officer; each line goes once someone of that role is hired.
##
## It sits at the left edge, centred vertically, below the money slot and the
## room panel (top-left) and above the follow text (bottom-left), in the
## shared HUD theme set on its card. The HUD layout ruling puts Staff in the
## bottom category bar later; until then this card is its place.

const ROLES: Array[StaffMember.Role] = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
const ROLE_NAMES := {
	StaffMember.Role.CHECKIN: "Check-in agents",
	StaffMember.Role.SECURITY: "Security officers",
}
const ROLE_KEYS := {
	StaffMember.Role.CHECKIN: "Checkin",
	StaffMember.Role.SECURITY: "Security",
}
const HINTS := {
	StaffMember.Role.CHECKIN: "Hire a check-in agent",
	StaffMember.Role.SECURITY: "Hire a security officer",
}
const LEFT := 16.0
const WIDTH := 260.0

## In a scene the Staff node; tests set it before the panel enters the tree.
@export var staff: StaffSim

var _card := PanelContainer.new()
var _hint := Label.new()
## Role -> the Label with its counts, its Hire and its Fire button.
var _counts: Dictionary = {}
var _hire: Dictionary = {}
var _fire: Dictionary = {}


func _ready() -> void:
	_build()
	if staff == null:
		push_error("StaffPanel: no StaffSim is set")
		return
	watch(staff)


## Follows `with_staff`'s hiring and members going on duty, and its grid's
## edits for the hint. The StaffSim must already be bound to a PassengerSim.
func watch(with_staff: StaffSim) -> void:
	staff = with_staff
	staff.staff_changed.connect(refresh)
	staff.member_state_changed.connect(_on_member_state)
	staff.sim.grid.graph_changed.connect(_on_graph_changed)
	refresh()


func card() -> PanelContainer:
	return _card


func hire_button(role: StaffMember.Role) -> Button:
	return _hire[role]


func fire_button(role: StaffMember.Role) -> Button:
	return _fire[role]


func hint_label() -> Label:
	return _hint


func counts_text(role: StaffMember.Role) -> String:
	return "%d hired, %d on duty" % [staff.count(role), staff.on_duty_count(role)]


## One line per role whose stations stand but nobody of that role is hired.
func hint_text() -> String:
	var lines := PackedStringArray()
	for role in ROLES:
		if not staff.stations_of(role).is_empty() and staff.count(role) == 0:
			lines.append(HINTS[role])
	return "\n".join(lines)


func refresh() -> void:
	for role in ROLES:
		(_counts[role] as Label).text = counts_text(role)
		(_fire[role] as Button).disabled = staff.count(role) == 0
	_hint.text = hint_text()
	_hint.visible = _hint.text != ""


func _on_member_state(_id: int, _state: StaffMember.State) -> void:
	refresh()


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	refresh()


func _build() -> void:
	_card.name = "StaffCard"
	_card.theme = BuildMenu.HUD_THEME
	_card.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_card.offset_left = LEFT
	_card.offset_top = 0.0
	_card.offset_bottom = 0.0
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.custom_minimum_size = Vector2(WIDTH, 0.0)
	add_child(_card)
	var column := VBoxContainer.new()
	_card.add_child(column)
	column.add_child(_label("Staff", &"HudTitle"))
	for role in ROLES:
		column.add_child(_label(ROLE_NAMES[role], &"HudCardName"))
		var counts := _label("", &"HudSmall")
		counts.name = "%sCounts" % ROLE_KEYS[role]
		column.add_child(counts)
		_counts[role] = counts
		var row := HBoxContainer.new()
		column.add_child(row)
		_hire[role] = _button(row, "Hire%s" % ROLE_KEYS[role], "Hire", &"HudButtonTeal")
		_fire[role] = _button(row, "Fire%s" % ROLE_KEYS[role], "Fire", &"HudButtonCoral")
		(_hire[role] as Button).pressed.connect(func() -> void: staff.hire(role))
		(_fire[role] as Button).pressed.connect(func() -> void: staff.fire(role))
	_hint.name = "StaffHint"
	_hint.theme_type_variation = &"HudAttentionText"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.visible = false
	column.add_child(_hint)


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label


func _button(row: HBoxContainer, node_name: String, text: String, variation: StringName) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.theme_type_variation = variation
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(button)
	return button
