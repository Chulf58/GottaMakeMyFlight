class_name BuiltItemCard
extends VBoxContainer
## The selected built item's content inside the passenger inspect window
## (decision built-items-selectable-reuse-the-selection-window-move-delete-
## close-open): its name, then one line each for where it is, its reachable
## seats (only when some cannot be reached), status (open or closed and why),
## a gate desk's biggest plane and walk from security (GateWalk), staff, queue
## and upkeep, a line left out when
## it does not apply. Info
## only; the actions come in later slices. PassengerInspect shows this in place
## of the passenger rows while a BuiltSelection holds an item.
##
## What the grid decides (name, room, upkeep, the item's kind, a room's
## counters and readiness) is worked out when the selection or the grid
## changes. What the sim decides (open or closed, staff, queue) is worked out
## again once per sim tick, and when staff are hired, fired or change state.

## What a selected object is, by its catalog identity. Staff work a DESK, a
## SCANNER, an ARCH with a whole lane (an incomplete one is just unready) and a
## COUNTER; a GATE_DESK links to a gate; a LANE_PART belongs to an arch's lane.
enum Kind { PLAIN, DESK, SCANNER, ARCH, COUNTER, GATE_DESK, LANE_PART, ROOM, LANDSIDE }

## What a piece that is not a room costs to run per game day, by catalog id
## (the same charges Settlement books at midnight).
const PIECE_UPKEEP := {
	&"screen_stand": PriceTable.SCREEN_UPKEEP,
	&"prize_podium": PriceTable.PRIZE_CAR_UPKEEP,
	&"info_screen": PriceTable.INFO_SCREEN_UPKEEP,
}
## The staffed and linked pieces by catalog id; the other lane parts and the
## counters are found by SecurityLanes.is_part() and ShopCounters.
const KIND_OF_DEF := {
	&"checkin_desk": Kind.DESK,
	&"security_scanner": Kind.SCANNER,
	SecurityLanes.ARCH: Kind.ARCH,
	GateDesks.DESK: Kind.GATE_DESK,
}
const FIELDS: Array[String] = [
	"where", "seats", "status", "planes", "walk", "staff", "queue", "upkeep"
]
## A linked gate desk's biggest plane: its gate's max_class (GateDesks; decision
## runway-and-taxi-technical-design-movement-plan-analytic-bookings-planned-
## pauses, section 3).
const PLANES_TEXT := "Biggest plane: %s"
const NO_PLANE_TEXT := "Biggest plane: none, no room outside the exit"
## A seat piece some of whose seats a guest cannot reach (a booth with an end
## against a wall; decision restaurant-booth-against-a-wall-counts-only-
## reachable-seats) says how many of its seats count.
const SEATS_REACHABLE_TEXT := "%d of %d seats reachable"

var sim: PassengerSim
var selection: BuiltSelection
var build_mode: BuildMode
## The gate links, for a gate desk's status; optional.
var gates: GateDesks
## A gate desk's walk from security (worked out again only after an edit).
var walk := GateWalk.new()

## How many times each half was worked out, for the tests.
var static_builds := 0
var live_builds := 0

var _name := Label.new()
var _labels := {}
## The grid-derived part: "kind", "name", the texts that never change with the
## sim ("where", "upkeep"), and per kind "id", "counters", "ready" (a room's
## RoomStatus), "arch", "plan_kind"/"spot"/"capacity". Empty for no selection.
var _static := {}
var _static_key := ""
var _static_stale := true
## The sim-derived part, and the tick and staff state it was worked out for.
var _live := {}
var _live_tick := -1
var _live_stale := true
var _live_closed := false
var _watched_grid: BuildGrid
var _watched_staff: StaffSim


func _init() -> void:
	name = "BuiltItemCard"
	visible = false
	add_theme_constant_override("separation", 2)
	_name.name = "ItemName"
	_name.theme_type_variation = &"HudLarge"
	add_child(_name)
	for field in FIELDS:
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_labels[field] = label
		add_child(label)
	(_labels["where"] as Label).theme_type_variation = &"HudHint"
	walk.changed.connect(invalidate)


## Shows the selected item, or hides the card with none.
func refresh() -> void:
	if selection == null or sim == null or build_mode == null:
		visible = false
		return
	_watch()
	var key := selection.key()
	if key != _static_key or _static_stale:
		_static = _build_static()
		static_builds += 1
		_static_key = key
		_static_stale = false
		_live_stale = true
	visible = not _static.is_empty()
	if not visible:
		return
	# A car park's car count scans the vehicles, so it follows the tick; its open or
	# closed flag is one read, so a change of it alone also rebuilds.
	var closed_changed: bool = _static["kind"] == Kind.LANDSIDE and _lot_closed() != _live_closed
	if _live_stale or closed_changed or sim.tick != _live_tick:
		_live = _build_live()
		live_builds += 1
		_live_tick = sim.tick
		_live_stale = false
		_show()


## Works the sim-derived lines out again on the next refresh, whatever the tick.
func invalidate() -> void:
	_live_stale = true


func name_text() -> String:
	return _name.text if visible else ""


func field_text(field: String) -> String:
	var label: Label = _labels[field]
	return label.text if label.visible and visible else ""


func _show() -> void:
	_name.text = _static["name"]
	for field in FIELDS:
		var label: Label = _labels[field]
		label.text = _static.get(field, _live.get(field, ""))
		label.visible = label.text != ""


## Follows the grid's edits and the staff's changes, which make the cached
## lines stale; reconnects when the sim's grid or staff is another object.
func _watch() -> void:
	if sim.grid != _watched_grid:
		_watched_grid = sim.grid
		_watched_grid.graph_changed.connect(_on_grid_changed)
		_watched_grid.edit_applied.connect(_on_grid_edit)
		_static_stale = true
	if sim.staff != _watched_staff:
		_watched_staff = sim.staff
		if _watched_staff != null:
			_watched_staff.staff_changed.connect(invalidate)
			_watched_staff.member_state_changed.connect(_on_member_state)
		_live_stale = true


func _on_grid_changed(_cells: Array[Vector2i]) -> void:
	_static_stale = true


func _on_grid_edit(_edit: BuildEdit, _result: BuildResult) -> void:
	_static_stale = true


func _on_member_state(_id: int, _state: StaffMember.State) -> void:
	invalidate()


# ------------------------------------------------------------ the grid half


func _build_static() -> Dictionary:
	match selection.kind:
		BuiltSelection.Kind.OBJECT:
			return _object_static(selection.id)
		BuiltSelection.Kind.ROOM:
			return _room_static(selection.id)
		BuiltSelection.Kind.LANDSIDE:
			return _landside_static()
	return {}


func _object_static(object_id: int) -> Dictionary:
	var grid := sim.grid
	var record := grid.get_object(object_id)
	if record.is_empty():
		return {}
	var def_id := StringName(record["def"])
	var out := {"kind": _kind_of(def_id, object_id), "id": object_id}
	var def := BuildCatalog.get_def(def_id)
	out["name"] = def.display_name
	var reachable := RoomRules.reachable_seats(grid, object_id).size()
	if reachable < def.seats.size():
		out["seats"] = SEATS_REACHABLE_TEXT % [reachable, def.seats.size()]
	var room_id := grid.room_at(record["anchor"])
	if room_id != 0:
		out["where"] = "In %s" % RoomTypes.get_type(grid.get_room(room_id)["type"]).display_name
	var upkeep: int = PIECE_UPKEEP.get(def_id, 0)
	if upkeep > 0:
		out["upkeep"] = BuildMenu.RUNNING_COST_TEXT % upkeep
	return out


## The kind of object `def_id` is; a counter is one by ShopCounters.
func _kind_of(def_id: StringName, object_id: int) -> Kind:
	if KIND_OF_DEF.has(def_id):
		return KIND_OF_DEF[def_id]
	if SecurityLanes.is_part(def_id):
		return Kind.LANE_PART
	return Kind.COUNTER if ShopCounters.is_counter(sim.grid, object_id) else Kind.PLAIN


func _room_static(room_id: int) -> Dictionary:
	var ready := RoomRules.status(sim.grid, room_id)
	if ready == null:
		return {}
	var out := {"kind": Kind.ROOM, "id": room_id, "name": ready.type_name, "ready": ready}
	var counters: Array[int] = []
	var ids := sim.grid.object_ids()
	ids.sort()
	for id in ids:
		if ShopCounters.room_of(sim.grid, id) == room_id:
			counters.append(id)
	out["counters"] = counters
	if ready.ok and ready.upkeep > 0:
		out["upkeep"] = BuildMenu.RUNNING_COST_TEXT % ready.upkeep
	return out


func _landside_static() -> Dictionary:
	var plan := selection.plan_of(build_mode.landside_placement())
	if plan == null:
		return {}
	return {
		"kind": Kind.LANDSIDE,
		"name": LandsidePlacement.NAMES[plan.kind],
		"spot": plan.spot,
		"is_lot": LandsidePlacement.is_lot(plan.kind),
		"capacity": plan.capacity,
		"unit": "berths" if plan.kind == LandsidePlacement.Kind.CURB else "spaces",
	}


# ------------------------------------------------------------ the sim half


func _build_live() -> Dictionary:
	var out := {}
	match _static["kind"]:
		Kind.DESK, Kind.SCANNER, Kind.COUNTER:
			out = _station_live([_static["id"]])
		Kind.ARCH:
			out = _arch_live(_static["id"])
		Kind.GATE_DESK:
			out = {
				"status": _gate_status(_static["id"]),
				"planes": _gate_planes(_static["id"]),
				"walk": _gate_walk(_static["id"]),
			}
		Kind.LANE_PART:
			var in_lane := sim.layout.security_lanes.lane_of_piece(_static["id"]) != 0
			var text := "Part of a ready security lane" if in_lane else "Not in a whole lane"
			out = {"status": "Status: %s" % text}
		Kind.ROOM:
			out = _room_live()
		Kind.LANDSIDE:
			out = _landside_live()
	return out


## Status, staff and queue of the staff-worked `stations`.
func _station_live(stations: Array) -> Dictionary:
	var waiting := 0
	for station in stations:
		waiting += _waiting_at(station)
	return {
		"status": _station_status(stations[0]),
		"staff": _staff_text(stations),
		"queue": "Queue: %d waiting" % waiting,
	}


func _arch_live(arch: int) -> Dictionary:
	var lanes := sim.layout.security_lanes
	if not lanes.is_complete(arch):
		return {"status": "Status: Not ready, %s" % lanes.status_text(arch).to_lower()}
	return _station_live([arch])


## "Linked to Gate B", or why the desk is unlinked (GateLinksView.caption_for).
func _gate_status(desk: int) -> String:
	if gates == null:
		return ""
	for binding in gates.bindings:
		if binding["desk"] == desk:
			return "Status: Linked to Gate %s" % binding["gate"]
	var reason: Dictionary = gates.unlinked().get(desk, {})
	if reason.is_empty():
		return "Status: Not linked yet"
	return "Status: %s" % GateLinksView.caption_for(reason).to_lower()


## "Biggest plane: Medium" for a linked desk's gate, or "" for an unlinked desk.
func _gate_planes(desk: int) -> String:
	if gates == null:
		return ""
	for binding in gates.bindings:
		if binding["desk"] == desk:
			var plane_class := gates.max_class(binding["gate"])
			if plane_class == "":
				return NO_PLANE_TEXT
			return PLANES_TEXT % plane_class.capitalize()
	return ""


## "Walk from security: 12 min" for a linked desk's gate, "...: no route" when no
## security exit reaches it, or "" for an unlinked desk. GateWalk answers from
## its last result until the grid or the gate links change.
func _gate_walk(desk: int) -> String:
	if gates == null:
		return ""
	for binding in gates.bindings:
		if binding["desk"] == desk:
			walk.bind(sim, gates)
			return GateWalk.card_line(walk.minutes(binding["gate"]))
	return ""


func _room_live() -> Dictionary:
	var ready: RoomRules.RoomStatus = _static["ready"]
	var counters: Array[int] = _static["counters"]
	var out := {}
	if not ready.ok:
		out["status"] = "Status: Not ready, %s" % ready.notes[0].to_lower()
	elif not counters.is_empty() and not ShopCounters.room_open(sim, _static["id"]):
		out["status"] = "Status: Closed, %s" % MissSignals.NO_STAFF_REASON.to_lower()
	else:
		out["status"] = "Status: Open"
	if not counters.is_empty():
		var staff_and_queue := _station_live(counters)
		out["staff"] = staff_and_queue["staff"]
		out["queue"] = staff_and_queue["queue"]
	return out


## Whether the selected car park is closed (a curb bay never is).
func _lot_closed() -> bool:
	return _static["is_lot"] and sim.landside.lots_closed[_static["spot"]]


func _landside_live() -> Dictionary:
	var land := sim.landside
	var spot: int = _static["spot"]
	var closed := _lot_closed()
	_live_closed = closed
	var cars := land.lot_cars(spot) if _static["is_lot"] else land.curb_cars(spot)
	return {
		"status": "Status: Closed" if closed else "Status: Open",
		"queue": "Cars: %d of %d %s" % [cars, _static["capacity"], _static["unit"]],
	}


func _station_status(station: int) -> String:
	if sim.staff == null or sim.staff.is_open(station):
		return "Status: Open"
	var reason := MissSignals.closed_reason(sim, station)
	if reason == "" and ShopCounters.closed(sim).has(station):
		reason = MissSignals.NO_STAFF_REASON
	if reason == "":
		return "Status: Not in use"
	return "Status: Closed, %s" % reason.to_lower()


## "Staff: 1 on duty", "Staff: 1 on the way" or "Staff: none", over `stations`.
func _staff_text(stations: Array) -> String:
	var on_duty := 0
	var coming := 0
	if sim.staff != null:
		for station in stations:
			for slot in [StaffMember.Slot.PRIMARY, StaffMember.Slot.HELPER]:
				var member := sim.staff.get_member(sim.staff.staff_at(station, slot))
				if member == null:
					continue
				if member.state == StaffMember.State.ON_DUTY:
					on_duty += 1
				else:
					coming += 1
	var parts := PackedStringArray()
	if on_duty > 0:
		parts.append("%d on duty" % on_duty)
	if coming > 0:
		parts.append("%d on the way" % coming)
	return "Staff: %s" % (", ".join(parts) if not parts.is_empty() else "none")


## Passengers in a station's lane and holding area; a counter's cafe lane too.
func _waiting_at(station: int) -> int:
	return (
		sim.queue_of(station).size()
		+ sim.holding_of(station).size()
		+ sim.cafes.queue_of(station).size()
	)
