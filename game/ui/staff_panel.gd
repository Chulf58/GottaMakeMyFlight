# gdlint:disable = max-public-methods
# StaffPanel exposes query/button accessors for HUD tests; training accessors took it past 20.
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
## closed it lists the opening needs still unmet (AirportGate.unmet(); a met
## need is folded away); once it opens it lists the current gaps instead
## (HintRules causes, read every GAP_POLL_S), with the wall gap and hiring
## lines in both. It hides when nothing is left.
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

signal member_selected(member_id: int)

const ROLES: Array[StaffMember.Role] = [
	StaffMember.Role.CHECKIN,
	StaffMember.Role.SECURITY,
	StaffMember.Role.GATE,
	StaffMember.Role.SHOP,
	StaffMember.Role.CLEANER,
	StaffMember.Role.RAMP,
]
const ROLE_KEYS := {
	StaffMember.Role.CHECKIN: "Checkin",
	StaffMember.Role.SECURITY: "Security",
	StaffMember.Role.GATE: "Gate",
	StaffMember.Role.SHOP: "Shop",
	StaffMember.Role.CLEANER: "Cleaner",
	StaffMember.Role.RAMP: "Ramp",
}
## The English msgids of the hire hints and the wall gap line. Tests compare
## against them; the card's lines are tr() of the same literals (_hire_hint(),
## card_lines()), because the POT extractor reads only literals.
const HINTS := {
	StaffMember.Role.CHECKIN: "Hire a check-in agent",
	StaffMember.Role.SECURITY: "Hire a security officer",
	StaffMember.Role.GATE: "Hire a gate agent",
	StaffMember.Role.SHOP: "Hire shop staff",
}
## The banner line for an open wall gap, one for a single run of gap edges and
## (card_lines()) one with the count for several. It uses the sign's words,
## "Wall gap".
const GAP_HINT := "Wall gap: close the open edge of the outer wall, marked in red"
## A column's least width: five roles fit centred over the bar,
## six fit 1280x720 with single-line headers.
const ROLE_WIDTH := 168.0
const ROLE_WIDTH_SIX := 148.0
const ROLE_SEPARATION := 10
const ROLE_SEPARATION_SIX := 8
const ENERGY_BAR_HEIGHT := 5.0
const ENERGY_RESTED_COLOR := Color(0.35, 0.78, 0.45)
const ENERGY_TIRED_COLOR := Color(0.9, 0.45, 0.25)
const ENERGY_BREAK_COLOR := Color(0.35, 0.65, 0.92)
const PULSE_TINT := Color(1.3, 1.12, 0.55)
const PULSE_STEP_S := 0.22
## The banner's top edge with the departures list off: under the three toggles.
## With the list open the card sits under it (LeftColumn.follow()).
const BANNER_TOP := LeftColumn.LIST_TOP
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
@export var unlocks: BuildUnlocks
@export var finances: Finances

var wallet: Wallet:
	set(value):
		wallet = value
		_bind_wallet()
		if is_node_ready() and staff != null:
			refresh()

## How many whole-grid gap scans have run, for the tests.
var gap_scans := 0

var _card := PanelContainer.new()
var _roles_box := HBoxContainer.new()
var _columns: Dictionary = {}
var _unlocks: BuildUnlocks
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
var _enclosure_token: Array = []
## The gap lines read at the last poll, while the airport is open.
var _gaps: Array[Dictionary] = []
var _since_poll := 0.0
## Role -> the Label with its counts, its Hire and its Fire button.
var _counts: Dictionary = {}
var _energy_scrolls: Dictionary = {}
var _energy_boxes: Dictionary = {}
var _role_titles: Dictionary = {}
var _hire: Dictionary = {}
var _fire: Dictionary = {}
var _bound_wallet: Wallet
var _retired_rows: Array[Node] = []
var _pulsed_hire: Button
var _pulse_tween: Tween


func _ready() -> void:
	_build()
	_resolve_unlocks()
	_sync_role_columns()
	_checklist.row_activated.connect(_on_checklist_row_activated)
	if menu != null:
		menu.staff_toggled.connect(_on_staff_toggled)
		menu.watch_staff_card(_card)
		_card.visible = menu.staff_open
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_fit_card):
		vp.size_changed.connect(_fit_card)
	if staff == null:
		push_error("StaffPanel: no StaffSim is set")
		return
	watch(staff)
	if save_game != null:
		save_game.loaded.connect(_on_loaded)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_retranslate()
	elif what == NOTIFICATION_PREDELETE:
		_flush_retired()


## Follows `with_staff`'s hiring and members going on duty, and its grid's
## edits for the hint, and the gate when one is set. The StaffSim must already
## be bound to a PassengerSim.
func watch(with_staff: StaffSim) -> void:
	staff = with_staff
	staff.staff_changed.connect(_on_staff_changed)
	staff.member_state_changed.connect(_on_member_state)
	staff.member_energy_changed.connect(_on_member_energy)
	staff.sim.grid.graph_changed.connect(_on_graph_changed)
	staff.sim.grid.edit_applied.connect(_on_edit_applied)
	_bind_wallet()
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


func train_button(member_id: int) -> Button:
	var node_name := "Train%d" % member_id
	for role in _energy_boxes:
		var btn := (_energy_boxes[role] as Node).find_child(node_name, true, false) as Button
		if btn != null:
			return btn
	return null


func member_button(member_id: int) -> Button:
	var node_name := "Member%d" % member_id
	for role in _energy_boxes:
		var btn := (_energy_boxes[role] as Node).find_child(node_name, true, false) as Button
		if btn != null:
			return btn
	return null


func member_name_text(member_id: int) -> String:
	if staff == null:
		return ""
	var m := staff.get_member(member_id)
	if m == null:
		return ""
	return m.display_name if m.display_name != "" else StaffNames.display_name_for(m.id)


func member_level_text(member_id: int) -> String:
	if staff == null:
		return ""
	var m := staff.get_member(member_id)
	if m == null:
		return ""
	return tr("Lv. {level}").format({"level": m.level})


func role_column(role: StaffMember.Role) -> Control:
	return _columns.get(role) as Control


func is_role_visible(role: StaffMember.Role) -> bool:
	var col := role_column(role)
	return col != null and col.visible


func role_tooltip(role: StaffMember.Role) -> String:
	return _role_tooltip(role)


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
	var hired := staff.count(role)
	var leaving := staff.leaving_count(role)
	var off_shift := staff.off_shift_count(role)
	var on_break := staff.on_break_count(role)
	var duty := staff.on_duty_count(role)
	var values := {
		"hired": hired,
		"duty": duty,
		"leaving": leaving,
		"off_shift": off_shift,
		"on_break": on_break,
	}
	var line := ""
	if off_shift > 0 and off_shift == hired and leaving == 0:
		line = tr("{hired} hired, off shift")
	elif role == StaffMember.Role.CLEANER:
		if off_shift > 0:
			line = tr("{hired} hired, {duty} cleaning, {off_shift} off shift")
		elif leaving > 0:
			line = tr("{hired} hired, {duty} cleaning, {leaving} leaving")
		elif on_break > 0:
			line = tr("{hired} hired, {duty} cleaning, {on_break} on break")
		else:
			line = tr("{hired} hired, {duty} cleaning")
	elif leaving > 0:
		line = tr("{hired} hired, {duty} on duty, {leaving} leaving")
	elif on_break > 0:
		line = tr("{hired} hired, {duty} on duty, {on_break} on break")
	else:
		line = tr("{hired} hired, {duty} on duty")
	return line.format(values)


func member_energy_text(member_id: int) -> String:
	if staff == null:
		return ""
	var m := staff.get_member(member_id)
	if m == null:
		return ""
	var line := ""
	if m.is_on_break():
		line = tr("On break {pct}%")
	elif m.is_tired():
		line = tr("Tired {pct}%")
	else:
		line = tr("Rested {pct}%")
	return line.format({"pct": m.energy})


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
		var gap_hint := tr_n(
			"Wall gap: close the open edge of the outer wall, marked in red",
			"{count} wall gaps: close the open edges of the outer wall, marked in red",
			_gap_runs
		)
		out.append(
			Checklist.line(
				gap_hint.format({"count": _gap_runs}),
				false,
				tr("Seals the terminal so roof and rooms work."),
				{"kind": "tool", "tool": BuildMode.Tool.WALL}
			)
		)
	for role in hiring_hint_roles():
		var opening_role := (
			role in [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY, StaffMember.Role.GATE]
		)
		if not (closed and opening_role):
			out.append(
				Checklist.line(
					_hire_hint(role), false, _hire_why(role), {"kind": "staff", "role": role}
				)
			)
	if gate != null and not closed:
		out.append_array(_gaps)
	return out


## Reads the gaps again (open airport only) and refreshes when they changed.
## _process calls it every GAP_POLL_S; tests call it directly.
func poll_gaps() -> void:
	var gaps := _read_gaps()
	if gaps != _gaps:
		_gaps = gaps
		refresh()


func _read_gaps() -> Array[Dictionary]:
	if gate == null or not gate.is_open() or staff == null or staff.sim == null:
		return []
	var world := HintRules.read_world(staff.sim, hiring_hint_roles())
	return Checklist.gap_lines(world, staff.sim.layout.seats.size(), _lock_texts())


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
			if (
				role == StaffMember.Role.GATE
				and not StaffPosts.usable(staff.sim.grid, staff.sim.layout, station)
			):
				continue
			if not staff.closures.is_closed(station):
				roles.append(role)
				break
	return roles


## Hides the banner while a first-time hint (Hints) takes its slot above the
## bar, and brings it back when the hint ends (decision first-time-hints-above-
## the-build-bar-moment-of-need-per-profile-memory, point 1).
func set_hint_yielded(yielded: bool) -> void:
	_hint_yielded = yielded
	_hint_box.visible = _checklist.has_visible_content() and not _hint_yielded


func _on_staff_changed() -> void:
	if gate != null and gate.is_open() and staff != null and staff.sim != null:
		_gaps = _read_gaps()
		_since_poll = 0.0
	refresh()


func refresh() -> void:
	_bind_wallet()
	_track_opening()
	_sync_role_columns()
	for role in ROLES:
		var counts_lbl := _counts[role] as Label
		counts_lbl.text = counts_text(role)
		var col := _columns.get(role) as Control
		var col_w := col.custom_minimum_size.x if col != null else ROLE_WIDTH
		_fit_single_line(counts_lbl, HudLayout.CAPTION, col_w)
		(_fire[role] as Button).disabled = _staying(role) == 0
		_refresh_energy_box(role)
	var prep_note := ""
	if gate != null and gate.flights != null and gate.flights.opened_tick < 0:
		prep_note = tr("Prep time — clock starts when staff reach stations")
	_checklist.set_prep_note(prep_note)
	if gate != null and not gate.is_open():
		_gaps = []
	var lines := card_lines()
	_checklist.show_lines(_card_title(lines), lines)
	_checklist.set_milestone(_milestone_text())
	_hint.visible = _hint.text != "" or not lines.is_empty()
	_hint_box.visible = _checklist.has_visible_content() and not _hint_yielded
	_fit_card()
	if is_inside_tree():
		_fit_card.call_deferred()


## "To open the airport" while closed, or "Ready: the airport opens on the next
## tick" once every opening line is done (the airport opens on the tick after the
## last member goes on duty, and a paused clock holds the card there with every
## line folded away); once open (or with no gate) the starter line while it shows,
## over "Your airport needs" when any line is left.
func _card_title(lines: Array[Dictionary]) -> String:
	if gate != null and not gate.is_open():
		if gate.ready_to_open():
			return tr("Ready: the airport opens on the next tick")
		return tr("To open the airport")
	var parts := PackedStringArray()
	if _open_cue != "":
		parts.append(_open_cue)
	if not lines.is_empty():
		parts.append(tr("Your airport needs"))
	return "\n".join(parts)


func _opening_counts() -> Dictionary:
	var layout := staff.sim.layout
	var grid := staff.sim.grid
	return {
		"entrances": layout.entrances.size(),
		"desks": layout.desks.size(),
		"scanners": layout.scanners.size(),
		"exits": layout.open_exits(grid).size(),
		"seats": layout.seats.size(),
		"checkin_staying": _staying(StaffMember.Role.CHECKIN),
		"security_staying": _staying(StaffMember.Role.SECURITY),
		"gate_staying": _staying(StaffMember.Role.GATE),
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
			_open_cue = tr("Open! Starter contract: {airline} to {destination}, daily").format(
				{"airline": contract["airline"], "destination": contract["destination"]}
			)
	_was_open = open


## The hire line for a role (see HINTS).
func _hire_hint(role: StaffMember.Role) -> String:
	match role:
		StaffMember.Role.CHECKIN:
			return tr("Hire a check-in agent")
		StaffMember.Role.SECURITY:
			return tr("Hire a security officer")
		StaffMember.Role.GATE:
			return tr("Hire a gate agent")
		StaffMember.Role.RAMP:
			return tr("Hire a ramp agent")
	return tr("Hire shop staff")


func _hire_why(role: StaffMember.Role) -> String:
	match role:
		StaffMember.Role.CHECKIN:
			return tr("Stations stay closed until an agent is hired.")
		StaffMember.Role.SECURITY:
			return tr("Stations stay closed until an officer is hired.")
		StaffMember.Role.GATE:
			return tr("Gate desks stay closed until an agent is hired.")
		StaffMember.Role.RAMP:
			return tr("Checked bags wait until a ramp agent drives the cart.")
	return tr("Counters stay closed until shop staff arrive.")


func _milestone_text() -> String:
	if gate == null or not gate.is_open() or _unlocks == null:
		return ""
	if _unlocks.tier() >= BuildUnlocks.CAFE_TIER:
		return ""
	if menu != null and menu.build_mode != null and not menu.build_mode.require_unlocks:
		return ""
	var need := int(BuildUnlocks.TIERS[BuildUnlocks.CAFE_TIER - 1]["passengers"])
	var done := mini(_unlocks.made_total(), need)
	return tr("Serve {done}/{need} passengers to unlock Cafe & Baggage").format(
		{"done": done, "need": need}
	)


func _role_tooltip(role: StaffMember.Role) -> String:
	match role:
		StaffMember.Role.CHECKIN:
			return tr(
				"Works check-in desks to tag bags and print boarding passes. Hire 1 per open desk."
			)
		StaffMember.Role.SECURITY:
			return tr(
				# gdlint:ignore = max-line-length
				"Runs security scanners and lanes to clear passengers and carry-on bags. Hire 1 per open scanner."
			)
		StaffMember.Role.GATE:
			return tr(
				"Works gate desks to start boarding and announce flights. Hire 1 per gate desk."
			)
		StaffMember.Role.SHOP:
			return tr(
				"Runs cafe, bar, restaurant, and shop counters. Hire once you build a cafe or shop."
			)
		StaffMember.Role.CLEANER:
			return tr("Mops terminal messes and empties full bins. Hire when litter builds up.")
	return tr(
		"Drives baggage carts between your Bag Room and parked planes. Hire once you build a Bag Room."
	)


## The Hire button's text: "Hire" with the role's daily wage (decision first-time-
## hints-gain-place-gate-desk-and-place-seats-the-hi), e.g. "Hire · 60/day".
func hire_text(role: StaffMember.Role) -> String:
	return tr("Hire · {wage}/day", "staff button").format({"wage": PriceTable.wage_of(role)})


## The column title of a role.
func _role_name(role: StaffMember.Role) -> String:
	match role:
		StaffMember.Role.CHECKIN:
			return tr("Check-in agents")
		StaffMember.Role.SECURITY:
			return tr("Security officers")
		StaffMember.Role.GATE:
			return tr("Gate agents")
		StaffMember.Role.SHOP:
			return tr("Shop staff")
		StaffMember.Role.RAMP:
			return tr("Ramp agents")
	return tr("Cleaners")


func _staying(role: StaffMember.Role) -> int:
	return staff.count(role) - staff.leaving_count(role)


func _on_staff_toggled(open: bool) -> void:
	_card.visible = open
	if open and staff != null:
		refresh()
	elif open:
		_fit_card()
	if not open:
		_stop_hire_pulse()


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_fit_card):
		vp.size_changed.disconnect(_fit_card)
	_unbind_wallet()
	_stop_hire_pulse()


func _resolve_wallet() -> Wallet:
	var found: Wallet = null
	if wallet != null:
		found = wallet
	elif finances != null:
		found = finances.wallet
	elif menu != null and menu.build_mode != null and menu.build_mode.wallet() != null:
		found = menu.build_mode.wallet()
	elif save_game != null and save_game.finances != null:
		found = save_game.finances.wallet
	elif staff != null and staff.sim != null and staff.sim.wallet != null:
		found = staff.sim.wallet
	elif get_parent() != null:
		var node := get_parent().get_node_or_null("Finances") as Finances
		if node != null:
			found = node.wallet
	return found


func _bind_wallet() -> void:
	var resolved := _resolve_wallet()
	if resolved == _bound_wallet:
		return
	_unbind_wallet()
	_bound_wallet = resolved
	if _bound_wallet != null:
		_bound_wallet.changed.connect(_on_wallet_changed)


func _unbind_wallet() -> void:
	if _bound_wallet != null and _bound_wallet.changed.is_connected(_on_wallet_changed):
		_bound_wallet.changed.disconnect(_on_wallet_changed)
	_bound_wallet = null


func _on_wallet_changed(_balance: int) -> void:
	if _card.visible and staff != null:
		for role in ROLES:
			_refresh_energy_box(role)
		_fit_card()
		if is_inside_tree():
			_fit_card.call_deferred()


func _on_member_state(_id: int, _state: StaffMember.State) -> void:
	refresh()


func _on_member_energy(_id: int, _energy: int) -> void:
	if _card.visible:
		for role in ROLES:
			_refresh_energy_box(role)
		_fit_card()
		if is_inside_tree():
			_fit_card.call_deferred()


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
	_sync_role_columns()
	if gate != null:
		_on_snapshot_loaded()
	else:
		_scan_gaps()
		refresh()


func _on_tier_changed(_tier: int) -> void:
	_sync_role_columns()
	refresh()


func _on_unlock_outcome(_id: int, made: bool) -> void:
	if made:
		refresh()


func _resolve_unlocks() -> void:
	_unlocks = unlocks
	if _unlocks == null and menu != null and menu.build_mode != null:
		_unlocks = menu.build_mode.unlocks
	if _unlocks != null:
		if not _unlocks.tier_changed.is_connected(_on_tier_changed):
			_unlocks.tier_changed.connect(_on_tier_changed)
		if (
			_unlocks.passengers != null
			and not _unlocks.passengers.outcome.is_connected(_on_unlock_outcome)
		):
			_unlocks.passengers.outcome.connect(_on_unlock_outcome)


func _unlocks_required() -> bool:
	return menu == null or menu.build_mode == null or menu.build_mode.require_unlocks


func _ramp_visible() -> bool:
	return _unlocks == null or not _unlocks_required() or _unlocks.tier() >= BuildUnlocks.CAFE_TIER


func _shop_visible() -> bool:
	if _unlocks == null or not _unlocks_required() or _unlocks.tier() >= BuildUnlocks.CAFE_TIER:
		return true
	if (
		staff != null
		and (
			staff.count(StaffMember.Role.SHOP) > 0
			or not staff.stations_of(StaffMember.Role.SHOP).is_empty()
		)
	):
		return true
	return false


func _sync_role_columns() -> void:
	var ramp_col: Control = _columns.get(StaffMember.Role.RAMP)
	if ramp_col != null:
		ramp_col.visible = _ramp_visible()
	var shop_col: Control = _columns.get(StaffMember.Role.SHOP)
	if shop_col != null:
		shop_col.visible = _shop_visible()
	var visible_count := 0
	for role in _columns:
		if (_columns[role] as Control).visible:
			visible_count += 1
	var col_w := ROLE_WIDTH_SIX if visible_count >= 6 else ROLE_WIDTH
	var sep := ROLE_SEPARATION_SIX if visible_count >= 6 else ROLE_SEPARATION
	_roles_box.add_theme_constant_override("separation", sep)
	for role in _columns:
		(_columns[role] as Control).custom_minimum_size = Vector2(col_w, 0.0)
		if _role_titles.has(role):
			var title_lbl := _role_titles[role] as Label
			title_lbl.custom_minimum_size.x = col_w
			_fit_single_line(title_lbl, HudLayout.CAPTION, col_w)
		if _counts.has(role):
			var counts_lbl := _counts[role] as Label
			counts_lbl.custom_minimum_size.x = col_w
			_fit_single_line(counts_lbl, HudLayout.CAPTION, col_w)
	_fit_card()


func _fit_card() -> void:
	var vp := get_viewport()
	var viewport_h := vp.get_visible_rect().size.y if vp != null else 864.0
	var bottom_clear := float(BuildMenu.MARGIN + BuildMenu.BAR_H + BuildMenu.GAP)
	var max_card_h := maxf(120.0, viewport_h - TopRow.SHEET_TOP - bottom_clear)
	var style := _card.get_theme_stylebox("panel")
	var card_pad := style.get_minimum_size().y if style != null else 0.0
	var max_chrome := 0.0
	for role in _columns:
		var col := _columns[role] as VBoxContainer
		if col == null or not col.visible:
			continue
		var scroll := _energy_scrolls.get(role) as ScrollContainer
		var col_sep := col.get_theme_constant("separation")
		var chrome := 0.0
		var child_count := 0
		for child in col.get_children():
			var ctrl := child as Control
			if ctrl == null or not ctrl.visible or ctrl == scroll:
				continue
			chrome += ctrl.get_combined_minimum_size().y
			child_count += 1
		if scroll != null and scroll.visible:
			child_count += 1
		chrome += maxf(0, child_count - 1) * col_sep
		max_chrome = maxf(max_chrome, chrome)
	var max_energy_h := maxf(0.0, max_card_h - card_pad - max_chrome)
	for role in _energy_scrolls:
		var scroll := _energy_scrolls[role] as ScrollContainer
		var box := _energy_boxes.get(role) as VBoxContainer
		if scroll == null or box == null or not scroll.visible:
			continue
		var wanted := minf(box.get_combined_minimum_size().y, max_energy_h)
		if not is_equal_approx(scroll.custom_minimum_size.y, wanted):
			scroll.custom_minimum_size.y = wanted
	_card.reset_size()
	BuildMenu.anchor_bottom_centre(_card, bottom_clear)


func _on_flight_state(id: String, new_state: int) -> void:
	if (
		_open_cue != ""
		and new_state == FlightSim.State.DEPARTED
		and gate.flights.flight_contract_id(id) == FlightSim.DEFAULT_ID
	):
		_open_cue = ""
		refresh()


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	var grid := staff.sim.grid
	if [grid.grid_id(), grid.enclosure_version()] != _enclosure_token:
		_scan_gaps()
	refresh()


func _scan_gaps() -> void:
	gap_scans += 1
	var grid := staff.sim.grid
	_enclosure_token = [grid.grid_id(), grid.enclosure_version()]
	_gap_runs = EnclosureGaps.gap_runs(grid).size()


## A room edit changes no walk graph, so graph_changed never follows it, and
## StaffSim emits nothing when no one is hired. An edit with dirty cells is
## followed by graph_changed (once for a whole batch), which scans, so only an
## edit without dirty cells is taken here. StaffSim connected first and has
## already reconciled its stations.
func _on_edit_applied(_edit: BuildEdit, result: BuildResult) -> void:
	if result.dirty_cells.is_empty():
		var grid := staff.sim.grid
		if [grid.grid_id(), grid.enclosure_version()] != _enclosure_token:
			_scan_gaps()
		refresh()


func _build() -> void:
	_card.name = "StaffCard"
	_card.theme = BuildMenu.HUD_THEME
	_card.add_to_group(BottomDocks.BOTTOM_STACK_GROUP)
	BuildMenu.anchor_bottom_centre(_card, BuildMenu.MARGIN + BuildMenu.BAR_H + BuildMenu.GAP)
	add_child(_card)
	_roles_box.add_theme_constant_override("separation", ROLE_SEPARATION)
	_card.add_child(_roles_box)
	for role in ROLES:
		var tip := _role_tooltip(role)
		var column := VBoxContainer.new()
		column.custom_minimum_size = Vector2(ROLE_WIDTH, 0.0)
		column.mouse_filter = Control.MOUSE_FILTER_PASS
		column.tooltip_text = tip
		_columns[role] = column
		_roles_box.add_child(column)
		var role_title := _single_line_label(_role_name(role), &"HudCardName")
		role_title.name = "%sTitle" % ROLE_KEYS[role]
		role_title.custom_minimum_size.x = ROLE_WIDTH
		role_title.mouse_filter = Control.MOUSE_FILTER_PASS
		role_title.tooltip_text = tip
		_role_titles[role] = role_title
		column.add_child(role_title)
		var counts := _single_line_label("", &"HudSmall")
		counts.name = "%sCounts" % ROLE_KEYS[role]
		counts.custom_minimum_size.x = ROLE_WIDTH
		counts.add_theme_font_size_override("font_size", HudLayout.CAPTION)
		counts.mouse_filter = Control.MOUSE_FILTER_PASS
		counts.tooltip_text = tip
		column.add_child(counts)
		_counts[role] = counts
		var row := VBoxContainer.new()
		row.name = "%sActions" % ROLE_KEYS[role]
		row.add_theme_constant_override("separation", 4)
		column.add_child(row)
		_hire[role] = _button(row, "Hire%s" % ROLE_KEYS[role], hire_text(role), &"HudButtonTeal")
		(_hire[role] as Button).tooltip_text = tip
		_fire[role] = _button(
			row, "Fire%s" % ROLE_KEYS[role], tr("Fire", "staff button"), &"HudButtonCoral"
		)
		(_hire[role] as Button).pressed.connect(func() -> void: staff.hire(role))
		(_fire[role] as Button).pressed.connect(func() -> void: staff.fire(role))
		var energy_scroll := ScrollContainer.new()
		energy_scroll.name = "%sEnergyScroll" % ROLE_KEYS[role]
		energy_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		energy_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		energy_scroll.visible = false
		column.add_child(energy_scroll)
		_energy_scrolls[role] = energy_scroll
		var energy_box := VBoxContainer.new()
		energy_box.name = "%sEnergy" % ROLE_KEYS[role]
		energy_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		energy_box.add_theme_constant_override("separation", 2)
		energy_box.visible = false
		energy_scroll.add_child(energy_box)
		_energy_boxes[role] = energy_box
	_build_hint()


func _on_checklist_row_activated(action: Dictionary) -> void:
	if menu == null or action.is_empty():
		return
	var kind := str(action.get("kind", ""))
	if kind == "tool":
		menu.focus_tool(int(action.get("tool", BuildMode.Tool.NONE)))
	elif kind == "staff":
		if not menu.staff_open:
			menu.press_staff()
		if action.has("role"):
			_pulse_hire(action["role"] as StaffMember.Role)


func _pulse_hire(role: StaffMember.Role) -> void:
	_stop_hire_pulse()
	var btn := _hire.get(role) as Button
	if btn == null:
		return
	_pulsed_hire = btn
	_pulse_tween = create_tween()
	for i in 3:
		_pulse_tween.tween_property(btn, "modulate", PULSE_TINT, PULSE_STEP_S)
		_pulse_tween.tween_property(btn, "modulate", Color.WHITE, PULSE_STEP_S)
	_pulse_tween.finished.connect(
		func() -> void:
			_pulsed_hire = null
			_pulse_tween = null
	)


func _stop_hire_pulse() -> void:
	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
	if _pulsed_hire != null and is_instance_valid(_pulsed_hire):
		_pulsed_hire.modulate = Color.WHITE
	_pulsed_hire = null


## The hint sits in a HUD card of its own in the top-left column, LIST_W wide,
## so it has a backing to read against.
func _build_hint() -> void:
	_hint_box.name = "StaffHintCard"
	_hint_box.theme = BuildMenu.HUD_THEME
	_hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_box.visible = false
	add_child(_hint_box)
	_hint.name = "StaffHint"
	_hint_box.add_child(_checklist)
	_hint_box.add_to_group(LeftColumn.CARD_GROUP)
	LeftColumn.dock_card(_hint_box)


func _process(delta: float) -> void:
	LeftColumn.follow(_hint_box)
	_fit_checklist()
	if gate != null and gate.is_open():
		_since_poll += delta
		if _since_poll >= GAP_POLL_S:
			_since_poll = 0.0
			poll_gaps()
	var ghost := Rect2()
	if menu != null:
		ghost = GhostBounds.build_rect(menu.build_mode, get_viewport().get_camera_3d())
	fade_for(ghost, delta)


## Folds the checklist's lowest lines into "+N more" when the card would reach
## the Templates dock, the bar's left end, or an open bottom menu stack.
func _fit_checklist() -> void:
	var bar_w := 0.0 if menu == null else menu.bar().get_combined_minimum_size().x
	var layer := get_viewport().get_visible_rect().size
	var room := maxf(
		0.0, LeftColumn.room_below(_hint_box.offset_top, layer, bar_w) - float(HudLayout.GAP)
	)
	room = minf(room, _menu_stack_room(layer))
	_checklist.fit(room - _hint_box.get_theme_stylebox("panel").get_minimum_size().y)


func _menu_stack_room(layer: Vector2) -> float:
	if menu == null:
		return INF
	var col_left := float(HudLayout.MARGIN)
	var col_right := col_left + float(HudLayout.LIST_W) + float(HudLayout.GAP)
	var floor_y := layer.y
	if menu.is_tray_open() and menu.tray().is_visible_in_tree():
		var tray_rect := menu.tray().get_global_rect()
		if tray_rect.end.x > col_left and tray_rect.position.x < col_right:
			floor_y = minf(floor_y, layer.y - menu.stack_top() - float(HudLayout.GAP))
	for control: Control in [menu.status_card(), _card]:
		if control == null or not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		if rect.end.x > col_left and rect.position.x < col_right:
			floor_y = minf(floor_y, rect.position.y - float(HudLayout.GAP))
	return maxf(0.0, floor_y - _hint_box.offset_top)


## Fades the hint card to FADED_ALPHA while `ghost` (the build ghost's bounds on
## screen, empty when there is none) overlaps it, and back to full opacity when
## it does not, `delta` seconds of the fade. While covered by a build ghost,
## actionable checklist rows also switch to click-through so grid clicks land.
func fade_for(ghost: Rect2, delta: float) -> void:
	HudLayout.fade_under_ghost(_hint_box, ghost, delta, FADED_ALPHA, FADE_SPEED)
	var covered := (
		ghost.has_area() and _hint_box.visible and _hint_box.get_global_rect().intersects(ghost)
	)
	_checklist.set_click_through(covered)


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _single_line_label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


func _fit_single_line(label: Label, base_size: int, width: float) -> void:
	var font := label.get_theme_font("font")
	if font != null and label.text != "":
		label.add_theme_font_size_override(
			"font_size", HudLayout.fit_size(label.text, font, base_size, width, 1)
		)
	else:
		label.add_theme_font_size_override("font_size", base_size)


func _button(row: Control, node_name: String, text: String, variation: StringName) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	# A clicked button must not keep keyboard focus: Space (pause) would press it again.
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = variation
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(button)
	return button


func _retranslate() -> void:
	for role in ROLES:
		var tip := _role_tooltip(role)
		if _columns.has(role):
			(_columns[role] as Control).tooltip_text = tip
		if _role_titles.has(role):
			(_role_titles[role] as Label).text = _role_name(role)
			(_role_titles[role] as Label).tooltip_text = tip
		if _counts.has(role):
			(_counts[role] as Label).tooltip_text = tip
		if _hire.has(role):
			(_hire[role] as Button).text = hire_text(role)
			(_hire[role] as Button).tooltip_text = tip
		if _fire.has(role):
			(_fire[role] as Button).text = tr("Fire", "staff button")
	if _open_cue != "" and gate != null:
		var contract := gate.flights.contract_of(FlightSim.DEFAULT_ID)
		if not contract.is_empty():
			_open_cue = tr("Open! Starter contract: {airline} to {destination}, daily").format(
				{"airline": contract["airline"], "destination": contract["destination"]}
			)
	if staff != null:
		if gate != null and gate.is_open():
			var world := HintRules.read_world(staff.sim, hiring_hint_roles())
			_gaps = Checklist.gap_lines(world, staff.sim.layout.seats.size(), _lock_texts())
		refresh()


func _flush_retired() -> void:
	for node in _retired_rows:
		if is_instance_valid(node):
			node.free()
	_retired_rows.clear()


func _refresh_energy_box(role: StaffMember.Role) -> void:
	var box := _energy_boxes.get(role) as VBoxContainer
	var scroll := _energy_scrolls.get(role) as ScrollContainer
	if box == null or staff == null:
		return
	for child in box.get_children():
		box.remove_child(child)
		_retired_rows.append(child)
	if not _retired_rows.is_empty() and is_inside_tree():
		_flush_retired.call_deferred()
	var members: Array[StaffMember] = []
	for id in staff.member_ids():
		var m := staff.get_member(id)
		if m != null and m.role == role and m.state != StaffMember.State.WALKING_OUT:
			members.append(m)
	box.visible = not members.is_empty()
	if scroll != null:
		scroll.visible = not members.is_empty()
		if members.is_empty():
			scroll.custom_minimum_size.y = 0.0
	if members.is_empty():
		return
	var active_wallet := _resolve_wallet()
	for m in members:
		var member_id := m.id
		var entry := VBoxContainer.new()
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.add_theme_constant_override("separation", 1)
		var name_btn := Button.new()
		name_btn.name = "Member%d" % member_id
		name_btn.text = member_name_text(member_id)
		name_btn.focus_mode = Control.FOCUS_NONE
		name_btn.theme_type_variation = &"HudButtonCompact"
		name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_btn.clip_text = true
		name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_btn.add_theme_font_size_override("font_size", HudLayout.CAPTION)
		name_btn.tooltip_text = tr("Inspect {name}").format({"name": name_btn.text})
		name_btn.pressed.connect(func() -> void: member_selected.emit(member_id))
		entry.add_child(name_btn)
		var lbl := _label(member_energy_text(m.id), &"HudSmall")
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.add_child(lbl)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.min_value = StaffMember.ENERGY_MIN
		bar.max_value = StaffMember.ENERGY_MAX
		bar.value = m.energy
		bar.custom_minimum_size = Vector2(0.0, ENERGY_BAR_HEIGHT)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill := StyleBoxFlat.new()
		fill.bg_color = (
			ENERGY_BREAK_COLOR
			if m.is_on_break()
			else (ENERGY_TIRED_COLOR if m.is_tired() else ENERGY_RESTED_COLOR)
		)
		bar.add_theme_stylebox_override("fill", fill)
		entry.add_child(bar)
		if StaffSim.is_role_trainable(role):
			var train_row := HBoxContainer.new()
			train_row.add_theme_constant_override("separation", 4)
			var lv_lbl := _label(member_level_text(m.id), &"HudSmall")
			lv_lbl.name = "Level%d" % m.id
			lv_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
			lv_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			train_row.add_child(lv_lbl)
			if m.level < StaffMember.LEVEL_MAX:
				var cost := PriceTable.staff_train_cost(m.level)
				var btn := Button.new()
				btn.name = "Train%d" % m.id
				btn.text = tr("Train ${cost}").format({"cost": cost})
				btn.focus_mode = Control.FOCUS_NONE
				btn.theme_type_variation = &"HudButtonCompact"
				btn.add_theme_font_size_override("font_size", HudLayout.CAPTION)
				var cannot_train := m.leaving or m.state == StaffMember.State.LEAVING_SHIFT
				btn.disabled = (
					cannot_train or (active_wallet != null and not active_wallet.can_afford(cost))
				)
				btn.tooltip_text = tr("Upgrade work speed to +{pct}%").format({"pct": m.level * 15})
				btn.pressed.connect(func() -> void: staff.train(member_id, _resolve_wallet()))
				train_row.add_child(btn)
			else:
				var max_lbl := _label(tr("Max"), &"HudSmall")
				max_lbl.name = "Max%d" % m.id
				max_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
				train_row.add_child(max_lbl)
			entry.add_child(train_row)
		else:
			var fixed_lbl := _label(tr("Fixed speed"), &"HudHint")
			fixed_lbl.name = "FixedSpeed%d" % m.id
			fixed_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			entry.add_child(fixed_lbl)
		box.add_child(entry)
