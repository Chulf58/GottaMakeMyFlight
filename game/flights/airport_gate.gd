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
## The path answer is kept until the grid changes; the staff checks are cheap
## and run on each call. `changed` tells the HUD the blocker may have changed.

signal changed

## What keeps the airport closed, checked in this order.
enum Blocker { NONE, NO_PATH, NO_CHECKIN, NO_SECURITY }

## In a scene the wired nodes; tests call bind(). Place this node after the
## PassengerSim, so the layout is rebuilt before this reads it.
@export var flights: FlightSim
@export var staff: StaffSim

var _path_ok := false
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
	if _path_dirty:
		_path_ok = RepairPlan.has_working_path(staff.sim.grid, staff.sim.layout)
		_path_dirty = false
	if not _path_ok:
		return Blocker.NO_PATH
	if not _any_open(staff.sim.layout.desks):
		return Blocker.NO_CHECKIN
	if not _any_open(staff.sim.layout.scanners):
		return Blocker.NO_SECURITY
	return Blocker.NONE


func ready_to_open() -> bool:
	return not is_open() and blocker() == Blocker.NONE


## Opens the airport when it is ready. Called by FlightSim on each tick while
## it is closed. True when it opened.
func try_open() -> bool:
	return ready_to_open() and open()


## Opens the airport now, ready or not, and accepts the starter contract at
## the first departure minute that leaves ISSUE_LEAD_TICKS after the opening
## and holds gate C free (a later minute only when an offer accepted while
## closed already holds that slot). False (with an error) when already open.
func open() -> bool:
	if not flights.open_airport():
		return false
	var terms := _starter_terms()
	if terms.is_empty():
		push_error("AirportGate: gate %s has no free slot for the starter" % FlightSim.DEFAULT_GATE)
	else:
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


func _on_member_state(_id: int, _state: StaffMember.State) -> void:
	changed.emit()


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	_path_dirty = true
	changed.emit()
