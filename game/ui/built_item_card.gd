class_name BuiltItemCard
extends VBoxContainer
## The selected built item's content inside the passenger inspect window
## (decision built-items-selectable-reuse-the-selection-window-move-delete-
## close-open): its name, then one line each for status (open or closed and
## why), staff, queue and upkeep, a line left out when it does not apply. Info
## only; the actions come in later slices. PassengerInspect shows this in place
## of the passenger rows while a BuiltSelection holds an item.

## What a piece that is not a room costs to run per game day, by catalog id
## (the same charges Settlement books at midnight).
const PIECE_UPKEEP := {
	&"screen_stand": PriceTable.SCREEN_UPKEEP,
	&"prize_podium": PriceTable.PRIZE_CAR_UPKEEP,
	&"info_screen": PriceTable.INFO_SCREEN_UPKEEP,
}

var sim: PassengerSim
var selection: BuiltSelection
var build_mode: BuildMode

var _name := Label.new()
var _status := Label.new()
var _staff := Label.new()
var _queue := Label.new()
var _upkeep := Label.new()
var _where := Label.new()


func _init() -> void:
	name = "BuiltItemCard"
	visible = false
	add_theme_constant_override("separation", 2)
	_name.name = "ItemName"
	_name.theme_type_variation = &"HudLarge"
	add_child(_name)
	for label in [_where, _status, _staff, _queue, _upkeep]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(label)
	_where.theme_type_variation = &"HudHint"


## Shows the selected item, or hides the card with none.
func refresh() -> void:
	var lines := lines_for()
	visible = not lines.is_empty()
	if not visible:
		return
	_name.text = lines["name"]
	var labels := {"where": _where, "status": _status, "staff": _staff, "queue": _queue}
	labels["upkeep"] = _upkeep
	for key: String in labels:
		var label: Label = labels[key]
		label.text = lines.get(key, "")
		label.visible = label.text != ""


## The card's texts by field ("name", "where", "status", "staff", "queue",
## "upkeep"; a field is left out when it does not apply), or an empty
## dictionary for no selection.
func lines_for() -> Dictionary:
	if selection == null or sim == null or build_mode == null:
		return {}
	match selection.kind:
		BuiltSelection.Kind.OBJECT:
			return _object_lines(selection.id)
		BuiltSelection.Kind.ROOM:
			return _room_lines(selection.id)
		BuiltSelection.Kind.LANDSIDE:
			return _landside_lines()
	return {}


func name_text() -> String:
	return _name.text if visible else ""


func field_text(field: String) -> String:
	var labels := {"where": _where, "status": _status, "staff": _staff, "queue": _queue}
	labels["upkeep"] = _upkeep
	var label: Label = labels[field]
	return label.text if label.visible and visible else ""


func _object_lines(object_id: int) -> Dictionary:
	var grid := sim.grid
	var record := grid.get_object(object_id)
	if record.is_empty():
		return {}
	var def := BuildCatalog.get_def(record["def"])
	var out := {"name": def.display_name}
	var room_id := grid.room_at(record["anchor"])
	if room_id != 0:
		out["where"] = "In %s" % RoomTypes.get_type(grid.get_room(room_id)["type"]).display_name
	if _is_station(object_id):
		out["status"] = _station_status(object_id)
		out["staff"] = _staff_text([object_id])
		var waiting := _waiting_at(object_id)
		out["queue"] = "Queue: %d waiting" % waiting
	var upkeep: int = PIECE_UPKEEP.get(StringName(record["def"]), 0)
	if upkeep > 0:
		out["upkeep"] = _upkeep_text(upkeep)
	return out


func _room_lines(room_id: int) -> Dictionary:
	var grid := sim.grid
	var status := RoomRules.status(grid, room_id)
	if status == null:
		return {}
	var out := {"name": status.type_name}
	out["status"] = _room_status(room_id, status)
	var counters := _counters_in(room_id)
	if not counters.is_empty():
		out["staff"] = _staff_text(counters)
		var waiting := 0
		for counter in counters:
			waiting += _waiting_at(counter)
		out["queue"] = "Queue: %d waiting" % waiting
	var upkeep := RoomRules.daily_upkeep(grid, room_id)
	if upkeep > 0:
		out["upkeep"] = _upkeep_text(upkeep)
	return out


func _landside_lines() -> Dictionary:
	var plan := selection.plan_of(build_mode.landside_placement())
	if plan == null:
		return {}
	var out := {"name": LandsidePlacement.NAMES[plan.kind]}
	var closed := LandsidePlacement.is_lot(plan.kind) and sim.landside.lots_closed[plan.spot]
	out["status"] = "Status: Closed" if closed else "Status: Open"
	var unit := "berths" if plan.kind == LandsidePlacement.Kind.CURB else "spaces"
	out["queue"] = "Cars: %d of %d %s" % [plan.cars, plan.capacity, unit]
	return out


## A desk, a scanner or a shop or cafe counter: what staff work.
func _is_station(object_id: int) -> bool:
	return (
		sim.layout.desks.has(object_id)
		or sim.layout.scanners.has(object_id)
		or ShopCounters.is_counter(sim.grid, object_id)
	)


func _station_status(station: int) -> String:
	if sim.staff == null or sim.staff.is_open(station):
		return "Status: Open"
	var reason := MissSignals.closed_reason(sim, station)
	if reason == "" and ShopCounters.closed(sim).has(station):
		reason = MissSignals.NO_STAFF_REASON
	if reason == "":
		return "Status: Not in use"
	return "Status: Closed, %s" % reason.to_lower()


func _room_status(room_id: int, status: RoomRules.RoomStatus) -> String:
	if not status.ok:
		return "Status: Not ready, %s" % status.notes[0].to_lower()
	if not _counters_in(room_id).is_empty() and not ShopCounters.room_open(sim, room_id):
		return "Status: Closed, %s" % MissSignals.NO_STAFF_REASON.to_lower()
	return "Status: Open"


## "Staff: 1 on duty", "Staff: 1 on the way" or "Staff: none", over `stations`.
func _staff_text(stations: Array[int]) -> String:
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


func _counters_in(room_id: int) -> Array[int]:
	var out: Array[int] = []
	var ids := sim.grid.object_ids()
	ids.sort()
	for id in ids:
		if ShopCounters.room_of(sim.grid, id) == room_id:
			out.append(id)
	return out


static func _upkeep_text(amount: int) -> String:
	return BuildMenu.RUNNING_COST_TEXT % amount
