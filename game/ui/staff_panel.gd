class_name StaffPanel
extends CanvasLayer
## The hiring panel (Staff S2): for check-in agents, security officers and shop
## staff (servers at cafe and kiosk counters), how many are hired and how many
## are on duty, with Hire and Fire buttons that go through StaffSim. Nobody
## is placed by hand: hired staff walk to a station on their own (ruling
## staff-are-hired-by-role-into-a-pool-and-walk-to-unstaffed-st). A new game
## has no staff, so the panel carries the hint (ruling
## staff-a-new-game-starts-with-an-empty-staff-pool-and-a-hint): once a desk
## stands and no agent is hired it asks for one, and the same for a scanner
## and an officer, and for a ready cafe or kiosk and shop staff; each line
## goes once someone of that role is hired.
## While the airport is closed the hint first names what keeps it closed
## (AirportGate.blocker(), decision airport-opening-design-stays-open-once-
## opened-starter-flight-placed-after-opening); that line goes once it opens.
##
## The card belongs to the bottom category bar (decision hud-layout-bottom-
## category-bar-with-an-item-tray-time-and-fl): the bar's Staff button opens it
## above the bar, in the item tray's place, and a category or a tool closes it.
## The hint is not part of the card: it stays on screen in a card of its own just above
## the bar (above an open tray or card), whether the card is open or not, so a closed
## airport is never hidden behind a closed card. Without a `menu` (a test) the
## card is always shown.

const ROLES: Array[StaffMember.Role] = [
	StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY, StaffMember.Role.SHOP
]
const ROLE_NAMES := {
	StaffMember.Role.CHECKIN: "Check-in agents",
	StaffMember.Role.SECURITY: "Security officers",
	StaffMember.Role.SHOP: "Shop staff",
}
const ROLE_KEYS := {
	StaffMember.Role.CHECKIN: "Checkin",
	StaffMember.Role.SECURITY: "Security",
	StaffMember.Role.SHOP: "Shop",
}
const HINTS := {
	StaffMember.Role.CHECKIN: "Hire a check-in agent",
	StaffMember.Role.SECURITY: "Hire a security officer",
	StaffMember.Role.SHOP: "Hire shop staff",
}
const CLOSED_HINTS := {
	AirportGate.Blocker.NO_PATH:
	(
		"Airport closed: passengers need a way from an entrance through check-in"
		+ " and security to an exit"
	),
	AirportGate.Blocker.STAFF_SPOT:
	(
		"Airport closed: staff can't reach the desk, scanner or lane passengers need."
		+ " Clear its staff spot or the way to it"
	),
	AirportGate.Blocker.NO_CHECKIN: "Airport closed: no check-in agent at a desk",
	AirportGate.Blocker.NO_SECURITY: "Airport closed: no security officer at a scanner or lane",
}
const ROLE_WIDTH := 210.0
## Width of the hint card's text, in layout pixels.
const HINT_W := 560.0

## In a scene the Staff node; tests set it before the panel enters the tree.
@export var staff: StaffSim
## In a scene the AirportGate; without one the hint has only the hiring lines.
@export var gate: AirportGate
## In a scene the BuildMenu whose Staff button opens the card.
@export var menu: BuildMenu

var _card := PanelContainer.new()
var _hint := Label.new()
var _hint_box := PanelContainer.new()
var _hint_bottom := -1.0
## Role -> the Label with its counts, its Hire and its Fire button.
var _counts: Dictionary = {}
var _hire: Dictionary = {}
var _fire: Dictionary = {}


func _ready() -> void:
	_build()
	if menu != null:
		menu.staff_toggled.connect(_on_staff_toggled)
		_card.visible = menu.staff_open
	if staff == null:
		push_error("StaffPanel: no StaffSim is set")
		return
	watch(staff)


## Follows `with_staff`'s hiring and members going on duty, and its grid's
## edits for the hint, and the gate when one is set. The StaffSim must already
## be bound to a PassengerSim.
func watch(with_staff: StaffSim) -> void:
	staff = with_staff
	staff.staff_changed.connect(refresh)
	staff.member_state_changed.connect(_on_member_state)
	staff.sim.grid.graph_changed.connect(_on_graph_changed)
	staff.sim.grid.edit_applied.connect(_on_edit_applied)
	if gate != null:
		gate.changed.connect(refresh)
	refresh()


func card() -> PanelContainer:
	return _card


func hire_button(role: StaffMember.Role) -> Button:
	return _hire[role]


func fire_button(role: StaffMember.Role) -> Button:
	return _fire[role]


func hint_label() -> Label:
	return _hint


## Hired and on duty; a member fired mid-service still works until that
## service ends, so it is counted and named as leaving.
func counts_text(role: StaffMember.Role) -> String:
	var text := "%d hired, %d on duty" % [staff.count(role), staff.on_duty_count(role)]
	var leaving := staff.leaving_count(role)
	if leaving > 0:
		text += ", %d leaving" % leaving
	return text


## What keeps the airport closed, if it is, then one line per role whose
## stations stand but nobody of that role is hired and staying (members
## leaving do not count).
func hint_text() -> String:
	var lines := PackedStringArray()
	if gate != null and gate.blocker() != AirportGate.Blocker.NONE:
		lines.append(CLOSED_HINTS[gate.blocker()])
	for role in ROLES:
		if not staff.stations_of(role).is_empty() and _staying(role) == 0:
			lines.append(HINTS[role])
	return "\n".join(lines)


func refresh() -> void:
	for role in ROLES:
		(_counts[role] as Label).text = counts_text(role)
		(_fire[role] as Button).disabled = _staying(role) == 0
	_hint.text = hint_text()
	_hint.visible = _hint.text != ""
	_hint_box.visible = _hint.visible


func _staying(role: StaffMember.Role) -> int:
	return staff.count(role) - staff.leaving_count(role)


func _on_staff_toggled(open: bool) -> void:
	_card.visible = open


func _on_member_state(_id: int, _state: StaffMember.State) -> void:
	refresh()


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	refresh()


## A room edit changes no walk graph, so graph_changed never follows it, and
## StaffSim emits nothing when no one is hired. edit_applied comes before the
## graph_changed of an edit with dirty cells, so only a room edit is taken
## here. StaffSim connected first and has already reconciled its stations.
func _on_edit_applied(_edit: BuildEdit, result: BuildResult) -> void:
	if result.dirty_cells.is_empty():
		refresh()


func _build() -> void:
	_card.name = "StaffCard"
	_card.theme = BuildMenu.HUD_THEME
	BuildMenu.anchor_bottom_centre(_card, BuildMenu.MARGIN + BuildMenu.BAR_H + BuildMenu.GAP)
	add_child(_card)
	var roles := HBoxContainer.new()
	roles.add_theme_constant_override("separation", 14)
	_card.add_child(roles)
	for role in ROLES:
		var column := VBoxContainer.new()
		column.custom_minimum_size = Vector2(ROLE_WIDTH, 0.0)
		roles.add_child(column)
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
	_build_hint()


## The hint sits in a HUD card of its own, centred, growing up from the bottom
## edge _place_hint() gives: just above the bar, above the open tray with its
## status and cost lines, or above the staff card, so it never covers any of them
## and has a backing to read against.
func _build_hint() -> void:
	_hint_box.name = "StaffHintCard"
	_hint_box.theme = BuildMenu.HUD_THEME
	_hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_box.visible = false
	add_child(_hint_box)
	_hint.name = "StaffHint"
	_hint.theme_type_variation = &"HudAttentionText"
	_hint.custom_minimum_size = Vector2(HINT_W, 0.0)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_box.add_child(_hint)
	_place_hint()


func _process(_delta: float) -> void:
	_place_hint()


## Docks the hint card above whatever stands over the bar now.
func _place_hint() -> void:
	var bottom := BuildMenu.MARGIN + BuildMenu.BAR_H + BuildMenu.GAP
	if menu != null and menu.is_tray_open():
		bottom = BuildMenu.tray_stack_top() + BuildMenu.GAP
	elif _card.visible and menu != null:
		bottom += _card.get_combined_minimum_size().y + BuildMenu.GAP
	if not is_equal_approx(bottom, _hint_bottom):
		_hint_bottom = bottom
		BuildMenu.anchor_bottom_centre(_hint_box, bottom)


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label


func _button(row: HBoxContainer, node_name: String, text: String, variation: StringName) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	# A clicked button must not keep keyboard focus: Space (pause) would press it again.
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = variation
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(button)
	return button
