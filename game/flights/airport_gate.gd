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
## contract, whose first flight starts ISSUE_LEAD_TICKS after the opening.
##
## When the only path runs through a desk or scanner staff can never work (its
## staff spot blocked, or no way to it from an entrance), the blocker is
## STAFF_SPOT, not NO_PATH: passengers have their way, the staff do not.
##
## The path answers are kept until the grid changes; the staff checks are cheap
## and run on each call. `changed` tells the HUD the blocker may have changed.

signal changed

## What keeps the airport closed, checked in the order NO_GATE, NO_PATH,
## STAFF_SPOT, NO_CHECKIN, NO_SECURITY. NO_GATE: FlightSim has no gate, so no
## flight could be given one (gates come from the placed gate desks, decision
## gates-are-placed-gate-desks-each-desk-links-automatically-to).
## CHECKIN_CLOSED and SECURITY_CLOSED take the place of NO_CHECKIN and
## NO_SECURITY when no desk (or no scanner or lane) is open because the player
## closed every one passengers could use (StationClosures), so the hint asks to
## open one again instead of to hire.
enum Blocker {
	NONE,
	NO_PATH,
	NO_CHECKIN,
	NO_SECURITY,
	STAFF_SPOT,
	NO_GATE,
	CHECKIN_CLOSED,
	SECURITY_CLOSED,
}

## In a scene the wired nodes; tests call bind(). Place this node after the
## PassengerSim, so the layout is rebuilt before this reads it.
@export var flights: FlightSim
@export var staff: StaffSim

## True when open() found gate C full all day and opened with no starter.
## Set only by open(); not saved, so it reads false after a load.
var opened_without_starter := false

var _path_ok := false
## Whether passengers would have a working path if every station were staffed.
var _route_ok := false
var _path_dirty := true


func _ready() -> void:
	if flights == null or staff == null:
		push_error("AirportGate: flights and staff must both be set, so the airport stays closed")
		return
	bind(flights, staff)


## Watches `with_staff` (already bound to its PassengerSim) and its grid, and
## becomes `with_flights`' gate.
func bind(with_flights: FlightSim, with_staff: StaffSim) -> void:
	flights = with_flights
	staff = with_staff
	flights.gate = self
	flights.snapshot_loaded.connect(changed.emit)
	staff.staff_changed.connect(changed.emit)
	staff.member_state_changed.connect(_on_member_state)
	staff.sim.grid.graph_changed.connect(_on_graph_changed)


func is_open() -> bool:
	return flights.opened_tick >= 0


## What keeps the airport closed now, or NONE when it is open or may open.
func blocker() -> Blocker:
	if is_open():
		return Blocker.NONE
	if flights.gate_ids().is_empty():
		return Blocker.NO_GATE
	var path := _path_blocker()
	if path != Blocker.NONE:
		return path
	var desks := staff.sim.layout.desks
	if not _any_open(desks):
		return Blocker.CHECKIN_CLOSED if _player_closed(desks) else Blocker.NO_CHECKIN
	var scanners := staff.sim.layout.scanners
	if not _any_open(scanners):
		return Blocker.SECURITY_CLOSED if _player_closed(scanners) else Blocker.NO_SECURITY
	return Blocker.NONE


## NO_PATH, STAFF_SPOT or NONE, from the path answers kept until the grid
## changes.
func _path_blocker() -> Blocker:
	if _path_dirty:
		_path_ok = RepairPlan.has_working_path(staff.sim.grid, staff.sim.layout)
		_route_ok = _path_ok or RepairPlan.has_working_path(staff.sim.grid, staff.sim.layout, false)
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


## Opens the airport now, ready or not, and accepts the starter contract at
## the first departure minute that leaves ISSUE_LEAD_TICKS after the opening
## and holds gate C free (a later minute only when an offer accepted while
## closed already holds that slot). The slot is found before the airport
## opens, and opening does not change which slots are free, so the opening
## and the starter are one step. When offers accepted while closed fill gate C
## all day, the airport opens with no starter: those offers are its flights,
## and opened_without_starter says so. False (with an error) when already open.
func open() -> bool:
	var terms := {} if is_open() else _starter_terms()
	if not flights.open_airport():
		return false
	opened_without_starter = terms.is_empty()
	if not opened_without_starter:
		flights.accept_contract(terms)
	changed.emit()
	return true


## The starter at the first minute from the lead on that accept_contract
## takes, or {} when every minute of the day clashes.
func _starter_terms() -> Dictionary:
	for minute in GameCalendar.MINUTES_PER_DAY:
		var terms := FlightSim.starter_terms(flights.tick + minute * GameCalendar.TICKS_PER_MINUTE)
		if flights.accept_problem(terms) == "":
			return terms
	return {}


func _any_open(stations: Array[int]) -> bool:
	for station in stations:
		if staff.is_open(station):
			return true
	return false


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
