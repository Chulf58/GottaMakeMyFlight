class_name StaffPanel
extends CanvasLayer
## The hiring panel (Staff S2): for check-in agents, security officers, shop
## staff (servers at cafe and kiosk counters) and cleaners, how many are hired
## and how many are on duty (cleaners: cleaning now), with Hire and Fire
## buttons that go through StaffSim. Cleaners have no station, so no hint line
## asks for one. Nobody
## is placed by hand: hired staff walk to a station on their own (ruling
## staff-are-hired-by-role-into-a-pool-and-walk-to-unstaffed-st). A new game
## has no staff, so the panel carries the hint (ruling
## staff-a-new-game-starts-with-an-empty-staff-pool-and-a-hint): once a desk
## stands and no agent is hired it asks for one, and the same for a scanner
## and an officer, and for a ready cafe or kiosk and shop staff; each line
## goes once someone of that role is hired.
## The hint is the checklist card (decision checklist-card-shows-what-the-
## airport-still-needs, ChecklistCard and Checklist): while the airport is
## closed it lists every opening need (AirportGate.unmet()), each ticked when
## done; once it opens it lists the current gaps instead (HintRules causes,
## read every GAP_POLL_S), with the wall gap and hiring lines in both. It hides
## when nothing is left.
##
## The card belongs to the bottom category bar (decision hud-layout-bottom-
## category-bar-with-an-item-tray-time-and-fl): the bar's Staff button opens it
## above the bar, in the item tray's place, and a category or a tool closes it.
## The hint is not part of the card: it stays on screen in a card of its own at
## the top centre (decision status-banner-and-first-time-hints-sit-at-the-top-
## centre), under the top row, whether the card or a build tray is open or not, so
## a closed airport is never hidden behind a closed card and never sits over the
## terminal being built. While the build ghost is over the hint it fades to
## FADED_ALPHA (it never takes a click). Without a `menu` (a test) the card is
## always shown.

const ROLES: Array[StaffMember.Role] = [
	StaffMember.Role.CHECKIN,
	StaffMember.Role.SECURITY,
	StaffMember.Role.SHOP,
	StaffMember.Role.CLEANER,
]
const ROLE_NAMES := {
	StaffMember.Role.CHECKIN: "Check-in agents",
	StaffMember.Role.SECURITY: "Security officers",
	StaffMember.Role.SHOP: "Shop staff",
	StaffMember.Role.CLEANER: "Cleaners",
}
const ROLE_KEYS := {
	StaffMember.Role.CHECKIN: "Checkin",
	StaffMember.Role.SECURITY: "Security",
	StaffMember.Role.SHOP: "Shop",
	StaffMember.Role.CLEANER: "Cleaner",
}
const HINTS := {
	StaffMember.Role.CHECKIN: "Hire a check-in agent",
	StaffMember.Role.SECURITY: "Hire a security officer",
	StaffMember.Role.SHOP: "Hire shop staff",
}
## The banner line for an open wall gap, one for a single run of gap edges and
## one with the count for several. It uses the sign's words, "Wall gap".
const GAP_HINT := "Wall gap: close the open edge of the outer wall, marked in red"
const GAPS_HINT := "%d wall gaps: close the open edges of the outer wall, marked in red"
## The line shown once the airport opens: the starter's airline and destination.
const OPEN_CUE := "Open! Starter contract: %s to %s, daily"
## A column's least width: four roles fit centred over the bar.
const ROLE_WIDTH := 180.0
## Width of the hint card's text, in layout pixels. With its padding the card
## ends left of PassengerHud's flight panel on every window shape: the layout is
## at least 1536 wide (1920 over the 1.25 stretch scale, aspect expand).
const HINT_W := 560.0
## The banner's top edge, under the top row and the Build mode sign (which ends
## at about 64).
const BANNER_TOP := 72.0
## The hint card's opacity while the build ghost is over it, and how fast it
## fades to that or back (opacity per second).
const FADED_ALPHA := 0.35
const FADE_SPEED := 6.0
## Seconds between reads of the gaps once the airport is open: passenger needs
## change with no signal.
const GAP_POLL_S := 1.0

## In a scene the Staff node; tests set it before the panel enters the tree.
@export var staff: StaffSim
## In a scene the AirportGate; without one the hint has only the hiring lines.
@export var gate: AirportGate
## In a scene the BuildMenu whose Staff button opens the card.
@export var menu: BuildMenu
## In a scene the SaveGame: once a load has installed every part the hint is
## rebuilt from the loaded world (decision loading-a-save-always-comes-back-
## paused-at-1x-speed-with-hin). Optional.
@export var save_game: SaveGame

## How many whole-grid gap scans have run, for the tests.
var gap_scans := 0

var _card := PanelContainer.new()
var _checklist := ChecklistCard.new()
## The card's title line.
var _hint := _checklist.title_label()
var _hint_box := PanelContainer.new()
## True while a first-time hint holds the banner's slot (set_hint_yielded()).
var _hint_yielded := false
## Whether the gate was open at the last refresh, so an opening is seen once.
var _was_open := false
## The starter line while it shows, "" otherwise.
var _open_cue := ""
## How many runs of open edges the outer wall has, read again on every edit.
var _gap_runs := 0
## The gap lines read at the last poll, while the airport is open.
var _gaps: Array[Dictionary] = []
var _since_poll := 0.0
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
	if save_game != null:
		save_game.loaded.connect(_on_loaded)


## Follows `with_staff`'s hiring and members going on duty, and its grid's
## edits for the hint, and the gate when one is set. The StaffSim must already
## be bound to a PassengerSim.
func watch(with_staff: StaffSim) -> void:
	staff = with_staff
	staff.staff_changed.connect(refresh)
	staff.member_state_changed.connect(_on_member_state)
	staff.sim.grid.graph_changed.connect(_on_graph_changed)
	staff.sim.grid.edit_applied.connect(_on_edit_applied)
	_scan_gaps()
	if gate != null:
		gate.changed.connect(refresh)
		gate.flights.snapshot_loaded.connect(_on_snapshot_loaded)
		gate.flights.state_changed.connect(_on_flight_state)
		_was_open = gate.is_open()
	refresh()


func card() -> PanelContainer:
	return _card


func hire_button(role: StaffMember.Role) -> Button:
	return _hire[role]


func fire_button(role: StaffMember.Role) -> Button:
	return _fire[role]


## The card's title line ("To open the airport", the starter line or "Your
## airport needs"), shown whenever the card is.
func hint_label() -> Label:
	return _hint


func checklist() -> ChecklistCard:
	return _checklist


## The banner card the hint sits in.
func hint_card() -> Control:
	return _hint_box


## Hired and on duty; a member fired mid-service still works until that
## service ends, so it is counted and named as leaving. A cleaner is on duty
## all day once hired, so its second count is how many are cleaning now.
func counts_text(role: StaffMember.Role) -> String:
	var working := "cleaning" if role == StaffMember.Role.CLEANER else "on duty"
	var text := "%d hired, %d %s" % [staff.count(role), staff.on_duty_count(role), working]
	var leaving := staff.leaving_count(role)
	if leaving > 0:
		text += ", %d leaving" % leaving
	return text


## What the card still asks for, one line each: the starter line while it
## shows, then the text of every card line not yet done (card_lines()).
func hint_text() -> String:
	var lines := PackedStringArray()
	if _open_cue != "":
		lines.append(_open_cue)
	for entry in card_lines():
		if not entry["done"]:
			lines.append(entry["text"])
	return "\n".join(lines)


## The card's lines (Checklist lines): while the airport is closed every
## opening need, ticked or not; a line naming an open gap in the outer wall
## (the red bars and "Wall gap" signs GapMarkers draws); one line per role whose
## stations stand but nobody of that role is hired and staying (members leaving
## do not count), except check-in and security while closed, whose opening
## lines already say to hire; and once open the gaps read at the last poll.
func card_lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var closed := gate != null and not gate.is_open()
	if closed:
		out.append_array(Checklist.opening_lines(gate.unmet(), _opening_counts()))
	if _gap_runs > 0:
		out.append(Checklist.line(GAP_HINT if _gap_runs == 1 else GAPS_HINT % _gap_runs, false))
	for role in hiring_hint_roles():
		if not (closed and role in [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]):
			out.append(Checklist.line(HINTS[role], false))
	if gate != null and not closed:
		out.append_array(_gaps)
	return out


## Reads the gaps again (open airport only) and refreshes when they changed.
## _process calls it every GAP_POLL_S; tests call it directly.
func poll_gaps() -> void:
	var gaps: Array[Dictionary] = []
	if gate != null and gate.is_open():
		var world := HintRules.read_world(staff.sim, hiring_hint_roles())
		gaps = Checklist.gap_lines(world, staff.sim.layout.seats.size(), _lock_texts())
	if gaps != _gaps:
		_gaps = gaps
		refresh()


## The roles whose hire line the banner shows: stations of the role stand that
## the player has not closed (StationClosures), and nobody of it is hired and
## staying. A closed station asks for nobody. The first-time hints compare this
## by meaning, so a hint does not repeat a hire the banner already asks for.
func hiring_hint_roles() -> Array[StaffMember.Role]:
	var roles: Array[StaffMember.Role] = []
	for role in ROLES:
		if _staying(role) != 0:
			continue
		for station in staff.stations_of(role):
			if not staff.closures.is_closed(station):
				roles.append(role)
				break
	return roles


## Hides the banner while a first-time hint (Hints) takes its slot above the
## bar, and brings it back when the hint ends (decision first-time-hints-above-
## the-build-bar-moment-of-need-per-profile-memory, point 1).
func set_hint_yielded(yielded: bool) -> void:
	_hint_yielded = yielded
	_hint_box.visible = _hint.visible and not _hint_yielded


## Anchors `card` at the top centre, growing down from BANNER_TOP. The
## first-time hint card uses it too, so the two sit in the same place.
static func anchor_banner(card: Control) -> void:
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.0
	card.anchor_bottom = 0.0
	card.offset_left = 0.0
	card.offset_right = 0.0
	card.offset_top = BANNER_TOP
	card.offset_bottom = BANNER_TOP
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_END


func refresh() -> void:
	_track_opening()
	for role in ROLES:
		(_counts[role] as Label).text = counts_text(role)
		(_fire[role] as Button).disabled = _staying(role) == 0
	var lines := card_lines()
	_checklist.show_lines(_card_title(lines), lines)
	_hint.visible = _hint.text != "" or not lines.is_empty()
	_hint_box.visible = _hint.visible and not _hint_yielded


## "To open the airport" while closed; once open (or with no gate) the starter
## line while it shows, over "Your airport needs" when any line is left.
func _card_title(lines: Array[Dictionary]) -> String:
	if gate != null and not gate.is_open():
		return Checklist.TITLE_CLOSED
	var parts := PackedStringArray()
	if _open_cue != "":
		parts.append(_open_cue)
	if not lines.is_empty():
		parts.append(Checklist.TITLE_OPEN)
	return "\n".join(parts)


func _opening_counts() -> Dictionary:
	var layout := staff.sim.layout
	return {
		"desks": layout.desks.size(),
		"scanners": layout.scanners.size(),
		"seats": layout.seats.size(),
		"checkin_staying": _staying(StaffMember.Role.CHECKIN),
		"security_staying": _staying(StaffMember.Role.SECURITY),
	}


## Why each gap line's build tool cannot be picked yet (BuildUnlocks.lock_text),
## when the scene's build mode gates tools; empty without a menu.
func _lock_texts() -> Dictionary:
	var texts := {}
	if menu == null or menu.build_mode == null:
		return texts
	var mode := menu.build_mode
	for tool: BuildMode.Tool in Checklist.GAP_TOOLS.values():
		texts[tool] = BuildUnlocks.lock_text(mode.unlocks, mode.require_unlocks, tool)
	return texts


## Takes the starter line when the gate has opened since the last refresh with
## a starter contract; an airport that opened with none has no line.
func _track_opening() -> void:
	if gate == null:
		return
	var open := gate.is_open()
	if open and not _was_open:
		_since_poll = GAP_POLL_S
	if open and not _was_open and not gate.opened_without_starter:
		var contract := gate.flights.contract_of(FlightSim.DEFAULT_ID)
		if not contract.is_empty():
			_open_cue = OPEN_CUE % [contract["airline"], contract["destination"]]
	_was_open = open


func _staying(role: StaffMember.Role) -> int:
	return staff.count(role) - staff.leaving_count(role)


func _on_staff_toggled(open: bool) -> void:
	_card.visible = open


func _on_member_state(_id: int, _state: StaffMember.State) -> void:
	refresh()


## A load opens or closes the airport without an opening to announce. The gate
## may refresh this panel first and see a closed-to-open change, so the line is
## dropped and the open state re-read here, whichever ran first.
func _on_snapshot_loaded() -> void:
	_open_cue = ""
	_scan_gaps()
	_was_open = gate.is_open()
	refresh()


## The flights part installs before the staff and the gates, so the refresh at
## its snapshot_loaded saw half a world; this one runs when the load is done.
func _on_loaded(ok: bool) -> void:
	if not ok:
		return
	if gate != null:
		_on_snapshot_loaded()
	else:
		_scan_gaps()
		refresh()


func _on_flight_state(id: String, new_state: int) -> void:
	if (
		_open_cue != ""
		and new_state == FlightSim.State.DEPARTED
		and gate.flights.flight_contract_id(id) == FlightSim.DEFAULT_ID
	):
		_open_cue = ""
		refresh()


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	_scan_gaps()
	refresh()


func _scan_gaps() -> void:
	gap_scans += 1
	_gap_runs = EnclosureGaps.gap_runs(staff.sim.grid).size()


## A room edit changes no walk graph, so graph_changed never follows it, and
## StaffSim emits nothing when no one is hired. An edit with dirty cells is
## followed by graph_changed (once for a whole batch), which scans, so only an
## edit without dirty cells is taken here. StaffSim connected first and has
## already reconciled its stations.
func _on_edit_applied(_edit: BuildEdit, result: BuildResult) -> void:
	if result.dirty_cells.is_empty():
		_scan_gaps()
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


## The hint sits in a HUD card of its own at the top centre, growing down from
## BANNER_TOP, so it has a backing to read against.
func _build_hint() -> void:
	_hint_box.name = "StaffHintCard"
	_hint_box.theme = BuildMenu.HUD_THEME
	_hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_box.visible = false
	add_child(_hint_box)
	_hint.name = "StaffHint"
	_hint.custom_minimum_size = Vector2(HINT_W, 0.0)
	_hint_box.add_child(_checklist)
	anchor_banner(_hint_box)


func _process(delta: float) -> void:
	if gate != null and gate.is_open():
		_since_poll += delta
		if _since_poll >= GAP_POLL_S:
			_since_poll = 0.0
			poll_gaps()
	var ghost := Rect2()
	if menu != null:
		ghost = GhostBounds.build_rect(menu.build_mode, get_viewport().get_camera_3d())
	fade_for(ghost, delta)


## Fades the hint card to FADED_ALPHA while `ghost` (the build ghost's bounds on
## screen, empty when there is none) overlaps it, and back to full opacity when
## it does not, `delta` seconds of the fade. The card never takes a click, so
## the ghost shows through and the pointer reaches the grid under it.
func fade_for(ghost: Rect2, delta: float) -> void:
	var covered := (
		ghost.has_area() and _hint_box.visible and _hint_box.get_global_rect().intersects(ghost)
	)
	var target := FADED_ALPHA if covered else 1.0
	_hint_box.modulate.a = move_toward(_hint_box.modulate.a, target, delta * FADE_SPEED)


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
