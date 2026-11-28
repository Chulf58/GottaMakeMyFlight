class_name AirportGate
extends Node
## Whether the airport may open (decision airport-opening-design-stays-open-
## once-opened-starter-flight-placed-after-opening, under ruling the-airport-
## opens-when-staffed-no-flights-are-scheduled-unti). It may once a new
## passenger has a working path (RepairPlan.has_working_path), a check-in agent
## is on duty at a desk and a security officer at a scanner (StaffSim.is_open,
## so a member still walking there, or one leaving, does not count). The
## opening is a latch kept in FlightSim.opened_tick: once open, the airport
## never closes, whoever is fired later.
##
## FlightSim asks try_open() at the start of each tick while closed, before it
## issues anything, so a flight due on the opening tick is issued on it.
## PassengerSim steps the staff later in the tick, so a member who goes on
## duty opens the airport on the next tick. Opening accepts the starter
## contract, timed by StarterSlot, whose first flight is issued on the opening
## tick, and then emits `opened`.
##
## While a bound airport is closed its clock's calendar is held (decision
## closed-airport-calendar-design-an-explicit-calendar-epoch-pa, ruling day-
## clock-stops-until-the-airport-opens-the-opening-call-pau): no game minute or
## day passes, while staff still walk to their stations. Opening starts it
## (FlightSim.open_airport).
##
## When the only path runs through a desk or scanner staff can never work (its
## staff spot blocked, or no way to it from an entrance), the blocker is
## STAFF_SPOT, not NO_PATH: passengers have their way, the staff do not.
##
## The path answers are kept until the grid changes; the staff checks are cheap
## and run on each call. `changed` tells the HUD the blocker may have changed.

signal changed
## The airport just opened, on tick `tick`, with its starter accepted and its
## first occurrence issued. Emitted inside that tick when try_open() opens it,
## so a listener that holds the clock (the opening call) stops the frame on the
## opening tick (SimClock.advance) and the first passengers move only after.
signal opened(tick: int)

## What keeps the airport closed, checked in the order NO_GATE, NO_PATH,
## STAFF_SPOT, NO_CHECKIN, NO_SECURITY, NO_GATE_AGENT. NO_GATE: FlightSim has no
## gate, so no flight could be given one (gates come from the placed gate desks,
## decision gates-are-placed-gate-desks-each-desk-links-automatically-to).
## CHECKIN_CLOSED and SECURITY_CLOSED take the place of NO_CHECKIN and
## NO_SECURITY when no desk (or no scanner or lane) is open because the player
## closed every one passengers could use (StationClosures), so the hint asks to
## open one again instead of to hire. NO_GATE_AGENT: a gate desk stands but has
## no Gate Agent on duty.
enum Blocker {
	NONE,
	NO_PATH,
	NO_CHECKIN,
	NO_SECURITY,
	STAFF_SPOT,
	NO_GATE,
	CHECKIN_CLOSED,
	SECURITY_CLOSED,
	NO_GATE_AGENT,
}

## In a scene the wired nodes; tests call bind(). Place this node after the
## PassengerSim, so the layout is rebuilt before this reads it.
@export var flights: FlightSim
@export var staff: StaffSim

## Always false: open() no longer opens without a starter (StarterSlot).
## ui/staff_panel.gd still reads it; it goes once that file stops.
var opened_without_starter := false

var _path_ok := false
## Whether passengers would have a working path if every station were staffed.
var _route_ok := false
var _path_dirty := true
var _path_linked := true
## Whether open() has said that no starter slot is free, so it says it once.
var _no_slot_said := false


func _ready() -> void:
	if flights == null or staff == null:
		push_error("AirportGate: flights and staff must both be set, so the airport stays closed")
		return
	bind(flights, staff)


## Watches `with_staff` (already bound to its PassengerSim) and its grid, and
## becomes `with_flights`' gate. While the airport is closed, the calendar of
## `with_flights`' clock is held.
func bind(with_flights: FlightSim, with_staff: StaffSim) -> void:
	flights = with_flights
	staff = with_staff
	flights.gate = self
	if not is_open() and flights.clock != null:
		flights.clock.hold_calendar()
	flights.snapshot_loaded.connect(changed.emit)
	staff.staff_changed.connect(changed.emit)
	staff.member_state_changed.connect(_on_member_state)
	staff.sim.grid.graph_changed.connect(_on_graph_changed)


func is_open() -> bool:
	return flights.opened_tick >= 0


## What keeps the airport closed now, or NONE when it is open or may open:
## the first of unmet().
func blocker() -> Blocker:
	var all := unmet()
	return Blocker.NONE if all.is_empty() else all[0]


## Every blocker that keeps the airport closed now, in blocker() order, or
## none when it is open or may open. The checklist card lists them all (decision
## checklist-card-shows-what-the-airport-still-needs). NO_PATH and STAFF_SPOT
## never come together, and at most one of each check-in pair and each
## security pair comes.
func unmet() -> Array[Blocker]:
	var out: Array[Blocker] = []
	if is_open():
		return out
	var no_gate := flights.gate_ids().is_empty()
	if no_gate:
		out.append(Blocker.NO_GATE)
	var path := _path_blocker(no_gate)
	if path != Blocker.NONE:
		out.append(path)
	var desks := staff.sim.layout.desks
	if not _any_open(desks):
		out.append(Blocker.CHECKIN_CLOSED if _player_closed(desks) else Blocker.NO_CHECKIN)
	var scanners := staff.sim.layout.scanners
	if not _any_open(scanners):
		out.append(Blocker.SECURITY_CLOSED if _player_closed(scanners) else Blocker.NO_SECURITY)
	var gate_desks := _linked_gate_desks()
	if not gate_desks.is_empty() and not _any_open(gate_desks):
		if _all_spots_unworkable(gate_desks):
			if not out.has(Blocker.STAFF_SPOT) and not out.has(Blocker.NO_PATH):
				out.append(Blocker.STAFF_SPOT)
		else:
			out.append(Blocker.NO_GATE_AGENT)
	return out


## NO_PATH, STAFF_SPOT or NONE, from the path answers kept until the grid
## changes. When by_gate is on and no gate is linked yet (NO_GATE), check
## physical reachability to placed exit doors so an unlinked starter exit
## does not emit a false NO_PATH.
func _path_blocker(no_gate := false) -> Blocker:
	var linked_exits := not (no_gate and staff.sim.layout.by_gate)
	if _path_dirty or _path_linked != linked_exits:
		_path_linked = linked_exits
		_path_ok = RepairPlan.has_working_path(staff.sim.grid, staff.sim.layout, true, linked_exits)
		_route_ok = (
			_path_ok
			or RepairPlan.has_working_path(staff.sim.grid, staff.sim.layout, false, linked_exits)
		)
		_path_dirty = false
	if not _route_ok:
		return Blocker.NO_PATH
	return Blocker.STAFF_SPOT if not _path_ok else Blocker.NONE


func ready_to_open() -> bool:
	return not is_open() and blocker() == Blocker.NONE


## Opens the airport when it is ready. Called by FlightSim on each tick while
## it is closed. True when it opened.
func try_open() -> bool:
	return ready_to_open() and open()


## Opens the airport now, ready or not, and accepts the starter contract in
## the slot StarterSlot finds, then emits `opened`. The slot is found before
## the opening commits, at the epoch the opening freezes (the calendar is held,
## so E is already this tick), and opening does not change which slots are
## free, so the opening and the starter are one step. When offers accepted
## while closed leave no slot all day, the airport stays closed and a warning
## says why, once: it never opens without a starter. False (with an error)
## when already open.
func open() -> bool:
	var terms := {} if is_open() else StarterSlot.terms(flights)
	if not is_open() and terms.is_empty():
		if not _no_slot_said:
			_no_slot_said = true
			push_warning(
				"AirportGate: no starter slot is free all day, so the airport stays closed"
			)
		return false
	if not flights.open_airport():
		return false
	flights.accept_contract(terms)
	changed.emit()
	opened.emit(flights.opened_tick)
	return true


func _any_open(stations: Array[int]) -> bool:
	for station in stations:
		if staff.is_open(station):
			return true
	return false


func _linked_gate_desks() -> Array[int]:
	var out: Array[int] = []
	if not staff.sim.layout.by_gate:
		return out
	for id in staff.sim.layout.gate_desk_ids.values():
		out.append(int(id))
	out.sort()
	return out


func _all_spots_unworkable(stations: Array[int]) -> bool:
	for station in stations:
		if not staff.spot_blocked(station) and not staff.spot_unreachable(station):
			return false
	return true


## Whether the player closed at least one of `stations` and every other one
## passengers could use (TerminalLayout.is_usable()).
func _player_closed(stations: Array[int]) -> bool:
	var closed := false
	for station in stations:
		if staff.closures.is_closed(station):
			closed = true
		elif staff.sim.layout.is_usable(station):
			return false
	return closed


func _on_member_state(_id: int, _state: StaffMember.State) -> void:
	changed.emit()


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	_path_dirty = true
	changed.emit()
