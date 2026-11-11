# gdlint:disable = max-public-methods
# FlightSim is the one flight data API; ending a contract (end_contract,
# active_contract_ids, contract_end_day) took it past the 20-method cap.
class_name FlightSim
extends Node
## The flight schedule as plain data driven by SimClock ticks. Each flight is
## a record (id, start tick of every state, current state, gate); a tick moves
## it to the next state when that state's start tick arrives. Nodes only read
## it. All times are integer sim ticks (20 per second), so speed and pause
## change nothing here.
##
## Flights come from two places. Accepted contracts (FlightContract) run a
## daily timetable: each day's occurrence is issued ahead of its first state
## (FlightTimetable), named "<contract>-d<day>", and pruned after it departs;
## queries on a pruned occurrence still answer from its immutable contract.
## add_flight adds a one-off flight, which is never pruned; add_default_flight
## is the one-off GMF101 that tests still use.
##
## The airport starts closed and issues no occurrence until it opens
## (decision airport-opening-design-stays-open-once-opened-starter-flight-
## placed-after-opening). AirportGate opens it once it is staffed and has a
## working path, and accepts the STARTER_TERMS contract then; open_airport()
## alone opens it without the starter. It never closes again. A contract
## accepted while closed starts on its first day issued at or after the
## opening (FlightTimetable.opening_day); the days it skipped were never
## flown, so they are never answered as departed.
##
## Gates (decision gates-technical-design-gate-desks-link-to-north-exits-one-
## st, points 4 and 5): gate_ids() lists the gates with a stand, from
## gate_source, and gate_grounds() each one's stand and largest plane class,
## from stand_source. Flights at one gate must not overlap there. The runway,
## the taxi lane and neighbouring stands are booked by GroundPlanner through
## FlightPlans (decision runway-and-taxi-technical-design-movement-plan-
## analytic-bookings-planned-pauses, sections 3, 5, 6 and 8): every flight of a
## day is planned in first-start order and may get a planned pause at a hold
## line (taxi_plan()). An accepted contract gets the best-fit gate its whole
## timetable fits at (the smallest max_class that takes its plane, then the
## lowest letter). An offer is refused with QUIET_NIGHT_TEXT when it departs
## outside 07:00 to 21:00, and with TAXI_BUSY_TEXT when no pause fits it or
## when it would leave an existing contract's occurrence with none (that
## occurrence may gain a pause). reassign_gate and move_contracts move a
## contract's days not yet issued through the same check; the occurrences
## already issued keep their gate, stand and plan.
##
## end_contract stops a contract's future days (decision low-rating-ends-one-
## airline-contract-per-low-day): what it already issued still flies and the
## contract stays on record, but it issues nothing more and no longer holds its
## gate time against new contracts. Taking its flights away must never leave
## another occurrence with no taxi plan, so when the re-plan without them would
## (greedy planning is not monotone) the contract keeps reserving its ground:
## FlightPlans plans its days as unrendered reservations (end_refusal()).
##
## One tick: set the tick, let the gate open the airport, issue due
## occurrences in time order, advance every flight, prune. PassengerSim binds
## after FlightSim, so it sees the result.

signal state_changed(flight_id: String, new_state: int)
## Fires once as a flight enters DOORS_CLOSED. The passenger slice stops
## boarding on it; is_doors_closed() answers the same question as a query.
signal doors_closed(flight_id: String)
## Fires once when a contract's occurrence is issued, after it is recorded,
## before any of its states is due. Never fires on a snapshot load.
signal occurrence_added(flight_id: String)
## Fires once when end_contract stops a contract's future days. Never fires on
## a snapshot load.
signal contract_ended(contract_id: String)
## Fires after from_snapshot() installs a save, so readers of the open state
## (AirportGate) can refresh. The only signal a load emits.
signal snapshot_loaded
## Fires from check_planning_changed() when the gates, their stands, the
## runway's size or its works differ from the last check, so an answer of
## trial_assignment() (an offer card's fit line) may have changed.
signal planning_changed

enum State {
	SCHEDULED,
	APPROACH,
	LANDING,
	TAXI_IN,
	AT_STAND,
	BOARDING,
	DOORS_CLOSED,
	PUSHBACK,
	TAXI_OUT,
	TAKEOFF,
	DEPARTED,
}

const STATE_COUNT := 11
## How long each state lasts in ticks, SCHEDULED to TAKEOFF. DEPARTED is final.
## BOARDING is 1200 ticks (60 s): in the reference terminal the walk from the
## farthest gate seat out through the exit and along the apron to the plane
## door is about 915 ticks at walking pace (test_boarding_window.gd).
## TAXI_IN (1000) and TAXI_OUT (920) keep the peak taxi speed at or under
## 16 m/s on the longest route a legal stand gives, with no pause and with the
## longest pause MovementPlan allows (user-ruled in decision runway-and-taxi-
## technical-design-movement-plan-analytic-bookings-planned-pauses;
## test_airside_stand.gd). Departure is the start of PUSHBACK, so a longer
## TAXI_IN only moves the arrival earlier.
const PHASE_TICKS: Array[int] = [100, 120, 140, 1000, 40, 1200, 60, 120, 920, 200]
const DEFAULT_ID := "GMF101"
## The gate of add_flight and add_default_flight unless told otherwise.
const DEFAULT_GATE := "C"
## The gates with a stand while gate_source is unset: the one stand so far.
const DEFAULT_GATES: Array[String] = [DEFAULT_GATE]
## The contract the airport opens with (Economy 7/8), without its departure
## minute: starter_terms() sets that from the opening tick. Fee and size sit
## inside the offer board's ranges.
const STARTER_TERMS := {
	"id": DEFAULT_ID,
	"airline": "Gotta Air",
	"destination": "Oslo",
	"plane_size": "small",
	"booked_passengers": 12,
	"fee_per_passenger": 25,
}
## 2: occurrences are issued FlightTimetable.ISSUE_LEAD_TICKS (2400, was 1200)
## before their first state, which changes the saved next_day at some ticks.
## 3: the airport's open state (opened_tick, start_day). A version 2 save
## loads as open since tick 0.
## 4: ended contracts (ended: contract id -> its first day never issued). A
## version 2 or 3 save loads with none ended.
## 5: a contract holds its plane class's passenger range (FlightContract.problem),
## so what a save may contain narrowed. A version 4 save is refused; there is no
## migration.
## 6: TAXI_IN and TAXI_OUT last 1000 and 920 ticks (were 600 and 720), so a
## saved occurrence's starts differ for the same contract and day. A version 5
## save is refused; there is no migration.
## 7: taxi plans (Runway R7). Each flight holds the stand it was issued at
## ("stand"), today's pruned occurrences are kept ("landed"), and a load
## re-plans every live flight and refuses a save whose plan fails. Every older
## version is refused; there is no migration.
const SAVE_VERSION := 7
## The refusal of a flight no taxi pause fits (user ruling a-gate-has-no-size-
## planes-use-any-stand-they-fit-neighbours-share-apron-space).
const TAXI_BUSY_TEXT := GroundPlanner.TAXI_BUSY_TEXT
const QUIET_NIGHT_TEXT := "it departs in the quiet night, outside 07:00 to 21:00"
## Formatted with the plane class the runway cannot take.
const RUNWAY_TOO_SHORT_TEXT := "the runway is too short for a %s plane"
## What kind of refusal trial_assignment() reports ("blocker"): bad terms or a
## used id, the runway's size, a clash at every gate that takes the plane, no
## taxi plan, a quiet-night departure, or no gate (with a stand) for the plane.
const BLOCKER_TERMS := "terms"
const BLOCKER_RUNWAY := "runway"
const BLOCKER_GATE := "gate"
const BLOCKER_TAXI := "taxi"
const BLOCKER_NIGHT := "night"
const BLOCKER_STAND := "stand"

## The clock to follow when this node enters a scene. Tests call bind_clock.
@export var clock: SimClock
## The size the runway starts at. The game scene starts small, per the design,
## and grows through runway works (RunwayWorks); a sim made in code starts with
## a runway that takes every class, so a test sets a smaller one to try the
## limit. A load replaces it.
@export var runway_start: String = PlaneClasses.LARGE:
	set(value):
		runway_start = value
		runway.size = value

## The tick the sim has been told about; set by the clock or a snapshot.
var tick: int = 0
## The tick the airport opened, or -1 while it is closed. Set only by
## open_airport() and from_snapshot(); read it, never write it.
var opened_tick: int = -1
## Asked on each tick while the airport is closed whether it may open
## (AirportGate.try_open). Set by AirportGate.bind(); without one the airport
## stays closed until open_airport() is called.
var gate: AirportGate
## Returns the gate letters that have a stand now, as an Array of Strings
## (gate_ids() sorts them). Gates slice 1b sets it from the placed gate desks;
## tests set it to supply more gates. Unset: DEFAULT_GATES.
var gate_source := Callable()
## Returns gate letter -> {"stand": StandPlacement stand, "max_class": the
## largest plane class it holds} for the gates of gate_source (GateDesks sets
## it). Unset: FlightGround.fallback() for each gate.
var stand_source := Callable()
## The airport's runway. Its size decides the plane classes a contract may have
## (accept_problem) and, through OfferDesk, the classes the offer board draws.
## SaveGame saves it as the "runway" part.
var runway := Runway.new(PlaneClasses.LARGE)
## Contract id -> its recorded start day, the first day that is or will be
## issued (see _start_day): a copy, so readers cannot change it. Writing it is
## an error.
var start_days: Dictionary:
	get:
		return _start_day.duplicate()
	set(_value):
		push_error("FlightSim.start_days is read-only")

## Live flights {id, starts, state, gate, contract, day}, in timetable order
## (FlightTimetable.flight_before), so the order is a function of what is
## live and a load restores it exactly.
## A one-off flight has contract "" and day -1.
var _flights: Array[Dictionary] = []
## Read-only contracts in acceptance order.
var _contracts: Array[Dictionary] = []
## Contract id -> the first day not yet issued.
var _next_day: Dictionary = {}
## Contract id -> its first day that is or will be issued: first_day, or for a
## contract accepted while closed, FlightTimetable.opening_day. Days from
## first_day up to it were skipped, not flown.
var _start_day: Dictionary = {}
## Contract id -> the first day it never issues, for the contracts that ended
## (end_contract). The day is the contract's _next_day when it ended, so it
## equals its _next_day from then on.
var _ended: Dictionary = {}
## Contract id -> true for the ended contracts whose days not yet issued still
## book their ground (end_contract()). Saved: it depends on the world at the
## tick the contract ended, which a load cannot rebuild.
var _reserving: Dictionary = {}
## Today's occurrences pruned from _flights, as their records, so a prune never
## changes a plan (FlightPlans). Dropped once their day is over.
var _landed: Array[Dictionary] = []
var _plans := FlightPlans.new()
## Bumped on every change to the contracts or the flights that can change a
## plan; the day plans in _day_plans are of this revision and of _grounds_key.
var _revision := 0
var _day_plans := {}
var _day_plans_revision := -1
var _grounds_key := ""
var _grounds_tick := -1
## Flights already reported as having no plan, so a view asking every frame
## reports each once.
var _reported := {}
## trial_assignment()'s own planner and day plans of the sim now, kept apart
## from _plans and _day_plans so an advisory trial changes no live planning
## state. Made on the first trial.
var _trial_plans: FlightPlans
var _trial_day_plans := {}
var _trial_plans_key := ""
## The planning state planning_changed last saw (check_planning_changed()).
var _planning_key := ""


func _ready() -> void:
	if clock != null:
		bind_clock(clock)


## Start ticks of every state for a flight whose SCHEDULED state begins at
## `first_tick`.
static func schedule_starts(first_tick: int) -> Array[int]:
	var starts: Array[int] = [first_tick]
	for ticks in PHASE_TICKS:
		starts.append(starts[starts.size() - 1] + ticks)
	return starts


func bind_clock(clock: SimClock) -> void:
	clock.ticked.connect(on_tick)


## STARTER_TERMS departing so that its first state is ISSUE_LEAD_TICKS after
## `now`, rounded up to a whole minute: its first occurrence is issued at
## `now` or within the minute after, never with less than the normal lead.
static func starter_terms(now: int) -> Dictionary:
	var departure := now + FlightTimetable.ISSUE_LEAD_TICKS + FlightTimetable.departure_offset()
	var minutes := -GameCalendar.floor_div(-departure, GameCalendar.TICKS_PER_MINUTE)
	var terms := STARTER_TERMS.duplicate()
	terms["departure_minute"] = GameCalendar.minute_of_day(minutes * GameCalendar.TICKS_PER_MINUTE)
	return terms


## Opens the airport at the current tick; it never closes again. Each contract
## accepted while closed starts on its first day issued at or after now, and
## what is due is issued at once. False (with an error) when already open.
## The starter contract is AirportGate.open()'s, not this.
func open_airport() -> bool:
	if opened_tick >= 0:
		push_error("FlightSim.open_airport: the airport opened at tick %d" % opened_tick)
		return false
	opened_tick = tick
	for contract in _contracts:
		var day := FlightTimetable.opening_day(contract, tick)
		_start_day[contract["id"]] = day
		_next_day[contract["id"]] = day
	# The contracts' days moved, so every cached day plan is of the closed world.
	_changed()
	_issue_due()
	return true


## Adds the one-off flight GMF101, starting at tick 0.
func add_default_flight() -> bool:
	return add_flight(DEFAULT_ID, schedule_starts(0))


## Adds a one-off flight (tests and debug only; the game adds none). False
## (with an error) when the id is taken or has the occurrence form, `starts` is
## not STATE_COUNT non-decreasing ticks, the gate has no stand, or the flight
## would meet an occurrence at the gate. A one-off is not taxi-planned: it
## books no runway, lane or stand and takes no pause (FlightPlans), so its
## schedule may be any, as the tests' short ones are.
func add_flight(id: String, starts: Array[int], gate := DEFAULT_GATE) -> bool:
	var problem := _one_off_problem(id, starts, gate)
	if problem != "":
		push_error("FlightSim: flight '%s' %s" % [id, problem])
		return false
	_insert(_record(id, starts, gate, "", -1))
	_changed()
	return true


## Accepts an offer's terms (FlightContract.TERM_KEYS) as a contract whose
## first occurrence is the first one whose whole preparation window is still
## ahead, at the best-fit gate its timetable fits at (accept_gate). False (with
## an error) for bad terms, a used id or no gate it fits at. Issues the first
## occurrence at once when it is already due and the airport is open; while it
## is closed the contract waits for the opening.
func accept_contract(terms: Dictionary) -> bool:
	var problem := accept_problem(terms)
	if problem != "":
		push_error("FlightSim.accept_contract: %s" % problem)
		return false
	var contract := _candidate(terms, _assignment(terms)["gate"])
	_contracts.append(contract)
	_next_day[contract["id"]] = contract["first_day"]
	_start_day[contract["id"]] = contract["first_day"]
	_changed()
	_issue_due()
	return true


## Why accept_contract would refuse `terms` right now (bad terms, a used id, a
## plane class the runway cannot take (RUNWAY_TOO_SHORT_TEXT), no gate with a
## stand, a departure in the quiet night (QUIET_NIGHT_TEXT), no gate that takes
## its plane, a clash at every gate that takes it, named for the best fit, or
## TAXI_BUSY_TEXT when a gate is free but no taxi plan fits it or it would
## leave an existing occurrence with none), or "" when it would take them.
## Read-only: it pushes no error and changes nothing, so a caller can ask first.
func accept_problem(terms: Dictionary) -> String:
	var problem := FlightContract.problem(terms, FlightContract.TERM_KEYS)
	if problem == "" and not contract_of(terms["id"]).is_empty():
		problem = "contract id '%s' is already used" % terms["id"]
	if problem == "" and not runway.takes(terms["plane_size"]):
		problem = RUNWAY_TOO_SHORT_TEXT % terms["plane_size"]
	if problem != "":
		return problem
	return _assignment(terms)["problem"]


## The taxi refusal behind accept_problem(`terms`): {"reason": GroundPlanner.
## TAXI_BUSY or QUIET_NIGHT, "flight": the occurrence that no plan fits, its
## own or an existing contract's ("" for QUIET_NIGHT)}, or {} when the terms
## are taken or refused for another reason. Read-only.
func accept_refusal(terms: Dictionary) -> Dictionary:
	if FlightContract.problem(terms, FlightContract.TERM_KEYS) != "":
		return {}
	if not contract_of(terms["id"]).is_empty():
		return {}
	return _assignment(terms)["refusal"]


## The gate accept_contract would give `terms` now: the best-fit gate with a
## stand whose timetable and taxi plans it fits, or "" when it would refuse
## them.
func accept_gate(terms: Dictionary) -> String:
	if accept_problem(terms) != "":
		return ""
	return _assignment(terms)["gate"]


## What accept_contract would do with `terms` if the terms in `before` had been
## accepted first, in that order, worked out on copies of the planning state
## (FlightFit's one way in; nothing is accepted, nothing changes): {"gate": the
## gate it would get or "", "problem": accept_problem's words or "", "blocker":
## "" or a BLOCKER_ value}. Terms in `before` that would be refused leave it
## refused with their own problem. With `ignore_gate_overlap` a clash at a gate
## is not counted and a spare gate is offered as well (_with_spare_gate), so the
## answer says whether the runway and lane would take the flight were a gate
## free.
func trial_assignment(
	terms: Dictionary, before: Array = [], ignore_gate_overlap := false
) -> Dictionary:
	var extra: Array[Dictionary] = []
	for earlier: Dictionary in before:
		var assigned := _trial(earlier, extra, false)
		if assigned["gate"] == "":
			return assigned
		extra.append(_candidate(earlier, assigned["gate"]))
	return _trial(terms, extra, ignore_gate_overlap)


## trial_assignment()'s answer for `terms` beside `extra`, checks of the terms
## first as accept_problem makes them.
func _trial(terms: Dictionary, extra: Array[Dictionary], ignore_gate: bool) -> Dictionary:
	var problem := FlightContract.problem(terms, FlightContract.TERM_KEYS)
	if problem == "" and not contract_of(terms["id"]).is_empty():
		problem = "contract id '%s' is already used" % terms["id"]
	for other in extra:
		if problem == "" and other["id"] == terms["id"]:
			problem = "contract id '%s' is already used" % terms["id"]
	if problem != "":
		return _assigned("", problem, {}, BLOCKER_TERMS)
	if not runway.takes(terms["plane_size"]):
		return _assigned("", RUNWAY_TOO_SHORT_TEXT % terms["plane_size"], {}, BLOCKER_RUNWAY)
	return _assignment(terms, extra, ignore_gate, true)


## The gates with a stand now, sorted, from gate_source (DEFAULT_GATES while it
## is unset). Pushes an error and lists none when the source returns anything
## but an array of distinct, non-empty strings.
func gate_ids() -> Array[String]:
	var listed: Variant = gate_source.call() if gate_source.is_valid() else DEFAULT_GATES
	var gates: Array[String] = []
	if typeof(listed) != TYPE_ARRAY:
		push_error("FlightSim.gate_source must return an array of gate letters")
		return gates
	for gate_id: Variant in listed:
		if typeof(gate_id) != TYPE_STRING or gate_id == "" or gates.has(gate_id):
			push_error("FlightSim.gate_source returned a bad gate list: %s" % [listed])
			return [] as Array[String]
		gates.append(gate_id)
	gates.sort()
	return gates


## Gate letter -> {"stand", "max_class"} for every gate of gate_ids(): from
## stand_source, or FlightGround.fallback() while it is unset. A gate the
## source gives no stand for is reported and left out.
func gate_grounds() -> Dictionary:
	var given: Variant = stand_source.call() if stand_source.is_valid() else null
	var out := {}
	for gate_id in gate_ids():
		var ground: Dictionary = FlightGround.fallback(gate_id)
		if given != null:
			ground = (given as Dictionary).get(gate_id, {})
		if not StandPlacement.is_stand(ground.get("stand")):
			push_error("FlightSim: gate %s has no stand to plan on" % gate_id)
			continue
		out[gate_id] = ground
	return out


## The taxi pauses of live flight `id`: FlightSim.State -> MovementPlan pause
## ({} for none) for TAXI_IN and TAXI_OUT, as FlightPlans planned its day. {}
## for an unknown flight, and for one no plan fits, which is reported once.
func taxi_plan(id: String) -> Dictionary:
	var index := _index_of(id)
	if index < 0:
		return {}
	var plans := _day_plan(FlightPlans.day_of(_flights[index]["starts"]))
	if _flights[index]["contract"] == "":
		return {}
	var result: Dictionary = plans.get(id, {})
	if result.get("ok", false):
		return result["pauses"]
	if not _reported.has(id):
		_reported[id] = true
		push_error(
			(
				"FlightSim: flight %s has no taxi plan (%s); it taxis without a pause"
				% [id, result.get("reason", "not planned")]
			)
		)
	return {}


## Moves a running contract's days not yet issued to `gate_id`. The
## occurrences it already issued keep their gate, stand and plan until they are
## pruned. False (with an error) when reassign_problem names a reason.
func reassign_gate(contract_id: String, gate_id: String) -> bool:
	var problem := reassign_problem(contract_id, gate_id)
	if problem != "":
		push_error("FlightSim.reassign_gate: %s" % problem)
		return false
	_contracts = _replaced(_contracts, _at_gate(contract_of(contract_id), gate_id))
	_changed()
	return true


## Why reassign_gate would refuse to move `contract_id` to `gate_id` now (an
## unknown or ended contract, a gate with no stand, the gate it is at, a gate
## too small for its plane, a clash at the gate, or TAXI_BUSY_TEXT when its
## days there or an existing occurrence would have no taxi plan; its own issued
## occurrences are left out), or "". Read-only.
func reassign_problem(contract_id: String, gate_id: String) -> String:
	var contract := contract_of(contract_id)
	if contract.is_empty():
		return "no contract '%s'" % contract_id
	if _ended.has(contract_id):
		return "contract %s has ended" % contract_id
	if not gate_ids().has(gate_id):
		return "gate '%s' has no stand" % gate_id
	if contract["gate"] == gate_id:
		return "contract %s is already at gate %s" % [contract_id, gate_id]
	return _move_problem(contract, gate_id, _contracts, gate_grounds())


## Where the running contracts at `from_gates` would go if those gates went:
## {"moves": contract id -> its new gate, "stuck": the contract ids no gate of
## `to_gates` takes}. Oldest first, each to the best-fit gate of `to_gates` it
## fits, checked as reassign_problem checks one against the rest as moved so
## far (decision gates-technical-design-gate-desks-link-to-north-exits-one-st,
## point 6). Live flights are not moved: an issued occurrence keeps its gate.
## Read-only; move_contracts() carries a plan out.
func move_plan(from_gates: Array[String], to_gates: Array[String]) -> Dictionary:
	var grounds := gate_grounds()
	var contracts := _contracts.duplicate()
	var moves := {}
	var stuck: Array[String] = []
	for i in contracts.size():
		var contract: Dictionary = contracts[i]
		if not FlightPlans.runs(_world(grounds), contract["id"]):
			continue
		if not from_gates.has(contract["gate"]):
			continue
		var to := ""
		for gate_id in _best_fit(grounds, contract["plane_size"]):
			if to_gates.has(gate_id) and _move_problem(contract, gate_id, contracts, grounds) == "":
				to = gate_id
				break
		if to == "":
			stuck.append(contract["id"])
			continue
		moves[contract["id"]] = to
		contracts[i] = _at_gate(contract, to)
	return {"moves": moves, "stuck": stuck}


## Carries out a move_plan() whose "stuck" is empty, all moves or none: the
## moves are checked in order on a scratch copy of the contracts, each as
## reassign_gate() checks one against the rest as moved so far, and only when
## every one fits does the copy replace the contracts. False (with an error,
## nothing moved) when `plan` has stuck contracts, names a contract that is not
## running, or a move no longer fits (the world changed since the plan).
func move_contracts(plan: Dictionary) -> bool:
	if not (plan["stuck"] as Array).is_empty():
		push_error("FlightSim.move_contracts: contracts %s fit no gate" % [plan["stuck"]])
		return false
	var moves: Dictionary = plan["moves"]
	var grounds := gate_grounds()
	var scratch := _contracts.duplicate()
	var moved := 0
	for i in scratch.size():
		var contract: Dictionary = scratch[i]
		if not moves.has(contract["id"]):
			continue
		var problem := (
			"contract %s has ended" % contract["id"]
			if not FlightPlans.runs(_world(grounds), contract["id"])
			else ""
		)
		if problem == "":
			problem = _move_problem(contract, moves[contract["id"]], scratch, grounds)
		if problem != "":
			push_error("FlightSim.move_contracts: nothing moved: %s" % problem)
			return false
		scratch[i] = _at_gate(contract, moves[contract["id"]])
		moved += 1
	if moved != moves.size():
		push_error("FlightSim.move_contracts: nothing moved: the plan names unknown contracts")
		return false
	_contracts = scratch
	_changed()
	return true


## Ends a contract: no day from its next unissued one on is ever issued, so the
## occurrences already issued still fly and the contract stays on record (its
## fee and terms still answer for them). Its gate time is free for a new
## contract, unless taking its days away would leave another occurrence with
## no taxi plan (end_refusal()): then its days stay booked as reservations,
## never flown, and every plan stays as it was. False (with an error) for an
## unknown or already ended contract or while the airport is closed.
func end_contract(contract_id: String) -> bool:
	if contract_of(contract_id).is_empty():
		push_error("FlightSim.end_contract: no contract '%s'" % contract_id)
		return false
	if _ended.has(contract_id):
		push_error("FlightSim.end_contract: contract '%s' already ended" % contract_id)
		return false
	if opened_tick < 0:
		push_error("FlightSim.end_contract: the airport is closed")
		return false
	var stranded := end_refusal(contract_id)
	_ended[contract_id] = _next_day[contract_id]
	if not stranded.is_empty():
		_reserving[contract_id] = true
	_changed()
	contract_ended.emit(contract_id)
	return true


## The occurrence that ending running contract `contract_id` now and freeing
## its ground would leave with no taxi plan: {"id", "reason"}, or {} when every
## surviving occurrence keeps one (or the contract is not running). Read-only.
func end_refusal(contract_id: String) -> Dictionary:
	if contract_of(contract_id).is_empty() or _ended.has(contract_id):
		return {}
	var world := _world()
	var ended := _ended.duplicate()
	ended[contract_id] = _next_day[contract_id]
	world["ended"] = ended
	var days := FlightPlans.days_from(world, _next_day[contract_id])
	return _plans.refusal(world, _day_plan, days, [])


## Whether ended contract `contract_id` still reserves its ground.
func is_reserving(contract_id: String) -> bool:
	return _reserving.has(contract_id)


## The contracts that have not ended, in acceptance order (oldest first).
func active_contract_ids() -> Array[String]:
	var ids: Array[String] = []
	for contract in _contracts:
		if not _ended.has(contract["id"]):
			ids.append(contract["id"])
	return ids


## The first day an ended contract never issues, or -1 while it is running or
## unknown.
func contract_end_day(contract_id: String) -> int:
	return _ended.get(contract_id, -1)


func on_tick(new_tick: int) -> void:
	tick = new_tick
	if runway.settle(tick):
		_changed()
	if opened_tick < 0 and gate != null:
		gate.try_open()
	_issue_due()
	for flight in _flights:
		_advance(flight)
	_prune()
	check_planning_changed()


## Emits planning_changed when the gates, their stands, the runway's size or
## its works differ from what the last call saw; the first call only takes note.
## Each tick calls it, and so do start_works and a view that must follow edits
## made while the clock is paused (OfferPanel, every frame it is open).
func check_planning_changed() -> void:
	var key := "%s %s %s" % [gate_grounds(), runway.size, runway.works.fixed_bookings()]
	if key == _planning_key:
		return
	var first := _planning_key == ""
	_planning_key = key
	if not first:
		planning_changed.emit()


## The tick the runway works that build a `target` runway would start if booked
## now: the first stretch of the timetable clear of every booking for the whole
## works (FlightPlans.works_start), or the current tick while the airport is
## closed, when nothing flies. -1 for a size nothing builds and when the next
## days have no such stretch. Read-only.
func works_start(target: String) -> int:
	var ticks := RunwayWorks.ticks(target)
	if ticks == 0:
		return -1
	if opened_tick < 0:
		return tick
	return _plans.works_start(_world(), tick, ticks)


## Books the runway works that build the next size: they start at works_start()
## and, once booked, are a fixed booking in every plan, so offers that would
## use the runway meanwhile are refused (RunwayWorks). While the airport is
## closed the size applies at once and nothing is booked. False (with an error)
## when the runway has no next size, works are already booked, or the
## timetable has no stretch for them.
func start_works(target: String) -> bool:
	var problem := ""
	if target == "" or RunwayWorks.next_size(runway.size) != target:
		problem = "the runway is %s and the works build %s" % [runway.size, target]
	elif runway.works.scheduled():
		problem = RunwayWorks.BOOKED_TEXT
	elif runway.works.start != RunwayWorks.NO_TICK:
		problem = RunwayWorks.HELD_TEXT
	var start := works_start(target) if problem == "" else -1
	if problem == "" and start < 0:
		problem = RunwayWorks.NO_GAP_TEXT
	if problem != "":
		push_error("FlightSim.start_works: %s" % problem)
		return false
	if opened_tick < 0:
		runway.size = target
		check_planning_changed()
		return true
	runway.works.begin(target, start)
	_changed()
	check_planning_changed()
	return true


## Live flights: one-off flights and issued occurrences not yet pruned.
func flight_ids() -> Array[String]:
	var ids: Array[String] = []
	for flight in _flights:
		ids.append(flight["id"])
	return ids


func contract_ids() -> Array[String]:
	var ids: Array[String] = []
	for contract in _contracts:
		ids.append(contract["id"])
	return ids


## The read-only contract, or {} for an unknown id.
func contract_of(contract_id: String) -> Dictionary:
	for contract in _contracts:
		if contract["id"] == contract_id:
			return contract
	return {}


## The contract an occurrence belongs to, or "" for a one-off or unknown flight.
func flight_contract_id(id: String) -> String:
	return _find(id).get("contract", "")


## The gate a live flight holds: for an occurrence issued before its contract
## moved, the contract's old gate. A pruned occurrence answers with its
## contract's gate now. "" for an unknown flight.
func flight_gate(id: String) -> String:
	return _find(id).get("gate", "")


## The live flight holding `gate` now (from its first state until it
## departs), or "". Occurrences at one gate never overlap.
func flight_at_gate(gate: String) -> String:
	for flight in _flights:
		var starts: Array = flight["starts"]
		if flight["gate"] == gate and starts[0] <= tick and tick < starts[State.DEPARTED]:
			return flight["id"]
	return ""


func state_of(id: String) -> int:
	var flight := _find(id)
	return flight["state"] if not flight.is_empty() else -1


func state_start(id: String, state: int) -> int:
	var flight := _find(id)
	return flight["starts"][state] if not flight.is_empty() else -1


## Ticks from the start of BOARDING (x) to the tick the doors close (y).
func boarding_window(id: String) -> Vector2i:
	return Vector2i(state_start(id, State.BOARDING), state_start(id, State.DOORS_CLOSED))


func doors_close_tick(id: String) -> int:
	return state_start(id, State.DOORS_CLOSED)


## True from the moment the doors close until the flight is gone.
func is_doors_closed(id: String) -> bool:
	return state_of(id) >= State.DOORS_CLOSED


## True while any flight is past SCHEDULED and not yet DEPARTED: on approach,
## on the ground or taxiing out. QuietNight reads it.
func has_moving_flight() -> bool:
	for flight in _flights:
		if flight["state"] > State.SCHEDULED and flight["state"] < State.DEPARTED:
			return true
	return false


## The next tick something is due: the next state change of a flight not yet
## departed or, while the airport is open, the next occurrence a running
## contract issues (the tick its passengers are booked). -1 when nothing is.
## Read-only; QuietNight stops a fast-forward ahead of it.
func next_event_tick() -> int:
	var next := -1
	for flight in _flights:
		if flight["state"] < State.DEPARTED:
			next = _earliest(next, flight["starts"][flight["state"] + 1])
	if opened_tick < 0:
		return next
	for contract in _contracts:
		if not _ended.has(contract["id"]):
			var day: int = _next_day[contract["id"]]
			next = _earliest(next, FlightTimetable.issue_tick(contract, day))
	return next


## The earlier of two ticks, where -1 is none.
static func _earliest(a: int, b: int) -> int:
	return b if a < 0 else mini(a, b)


## How far through its current state a flight is at sim time `time` (a tick
## plus the clock's alpha), from 0 to 1. A final state reads 1.
func phase_progress(id: String, time: float) -> float:
	var flight := _find(id)
	var state: int = flight["state"] if not flight.is_empty() else -1
	if state < 0:
		return 0.0
	if state == State.DEPARTED:
		return 1.0
	var start: int = flight["starts"][state]
	var end: int = flight["starts"][state + 1]
	if end <= start:
		return 1.0
	return clampf((time - start) / float(end - start), 0.0, 1.0)


## JSON-safe state for a save.
func to_snapshot() -> Dictionary:
	return FlightSnapshot.save(
		tick, opened_tick, _contracts, _start_day, _next_day, _ended, _reserving, _flights, _landed
	)


## Restores a to_snapshot() dictionary, including one that went through JSON
## (which turns ints into floats). Pushes an error and returns false, leaving
## the sim unchanged, when anything is missing, mistyped or inconsistent, when
## a live flight's stand is not its gate's, or when a live flight's re-plan
## fails. Emits only snapshot_loaded: what the save had issued stays issued.
func from_snapshot(data: Dictionary) -> bool:
	var loaded := FlightSnapshot.load(data, gate_ids())
	var problem: String = loaded.get("error", "")
	if problem == "":
		problem = _load_plan_problem(loaded)
	if problem != "":
		push_error("FlightSim.from_snapshot: %s" % problem)
		return false
	tick = loaded["tick"]
	opened_tick = loaded["opened_tick"]
	_contracts = loaded["contracts"]
	_start_day = loaded["start_day"]
	_next_day = loaded["next_day"]
	_ended = loaded["ended"]
	_reserving = loaded["reserving"]
	_flights = loaded["flights"]
	_landed = loaded["landed"]
	_changed()
	snapshot_loaded.emit()
	return true


## Why from_snapshot() would refuse `data` with the gates and grounds now, or
## "": what it checks, without installing anything or pushing an error. SaveGame
## stages a load with it.
func load_problem(data: Dictionary) -> String:
	var loaded := FlightSnapshot.load(data, gate_ids())
	if loaded.has("error"):
		return loaded["error"]
	return _load_plan_problem(loaded)


## Why a FlightSnapshot.load() result could not be installed with the gates'
## grounds now: a live flight at a stand other than its gate's, a live flight
## or a running or reserving contract too big for its gate's max_class, or a
## request of any day the sim will fly (FlightPlans.horizon(): live and landed
## flights, and every running or reserving contract's occurrences) that has no
## taxi plan; "" for none.
func _load_plan_problem(loaded: Dictionary) -> String:
	for contract: Dictionary in loaded["contracts"]:
		if not runway.takes(contract["plane_size"]):
			return (
				"contract %s is a %s plane but the runway is %s"
				% [contract["id"], contract["plane_size"], runway.size]
			)
	var grounds := gate_grounds()
	var world := {
		"contracts": loaded["contracts"],
		"start_day": loaded["start_day"],
		"next_day": loaded["next_day"],
		"ended": loaded["ended"],
		"reserving": loaded["reserving"],
		"flights": loaded["flights"],
		"landed": loaded["landed"],
		"grounds": grounds,
		"works": runway.works.fixed_bookings(),
	}
	for flight: Dictionary in loaded["flights"]:
		var ground: Dictionary = grounds.get(flight["gate"], {})
		if ground.is_empty() or ground["stand"] != flight["stand"]:
			return "flight %s is not at its gate's stand" % flight["id"]
		var plane_class := FlightPlans.flight_class(world, flight)
		if not FlightGround.class_fits(plane_class, ground["max_class"]):
			return (
				"flight %s needs a %s gate, but gate %s takes %s"
				% [flight["id"], plane_class, flight["gate"], ground["max_class"]]
			)
	for contract: Dictionary in loaded["contracts"]:
		if not FlightPlans.runs(world, contract["id"]):
			continue
		var ground: Dictionary = grounds.get(contract["gate"], {})
		if not FlightGround.class_fits(contract["plane_size"], ground.get("max_class", "")):
			return (
				"contract %s needs a %s gate, but gate %s takes %s"
				% [
					contract["id"],
					contract["plane_size"],
					contract["gate"],
					ground.get("max_class", "none")
				]
			)
	for day in FlightPlans.horizon(world):
		var plans := _plans.plan_day(world, day)
		for request: Dictionary in FlightPlans.requests(world, day):
			var result: Dictionary = plans[request["id"]]
			if not result["ok"]:
				return "flight %s has no taxi plan: %s" % [request["id"], _ground_text(result)]
	return ""


## A flight record with the state it is in at the current tick, at its gate's
## stand now.
func _record(
	id: String, starts: Array[int], gate: String, contract: String, day: int
) -> Dictionary:
	return {
		"id": id,
		"starts": starts.duplicate(),
		"state": FlightTimetable.state_at(starts, tick),
		"gate": gate,
		"contract": contract,
		"day": day,
		"stand": gate_grounds().get(gate, {}).get("stand", {}),
	}


func _one_off_problem(id: String, starts: Array[int], gate: String) -> String:
	if id == "" or _index_of(id) >= 0:
		return "has an empty or used id"
	if not FlightTimetable.parse_occurrence(id).is_empty():
		return "has an id of the contract occurrence form"
	if not FlightTimetable.starts_valid(starts):
		return "needs %d non-decreasing start ticks, 0 or more" % STATE_COUNT
	if not gate_ids().has(gate):
		return "is at gate '%s', which has no stand" % gate
	return _one_off_clash(starts, gate)


## What a one-off at `gate` with `starts` would meet at the gate: a running
## contract's days, or an issued occurrence. Other one-offs at the gate are not
## checked here (the planner books their stand).
func _one_off_clash(starts: Array[int], gate: String) -> String:
	for contract in _contracts:
		if not _ended.has(contract["id"]):
			if FlightTimetable.contract_meets(contract, gate, starts):
				return "would hold gate %s during contract %s" % [gate, contract["id"]]
	# Issued occurrences hold the gate they were issued at: an ended contract's,
	# or one issued before its contract moved.
	for flight in _flights:
		if flight["contract"] != "":
			if FlightTimetable.shares_gate(gate, starts, flight["gate"], flight["starts"]):
				return "would hold gate %s during %s" % [gate, flight["id"]]
	return ""


## The contract `terms` would become now at `gate_id`, with its first day.
## Terms must be valid.
func _candidate(terms: Dictionary, gate_id: String) -> Dictionary:
	var fields := terms.duplicate()
	fields["gate"] = gate_id
	fields["first_day"] = 0
	fields["first_day"] = FlightTimetable.first_day(fields, tick)
	return FlightContract.make(fields)


## A read-only copy of `contract` at `gate_id`.
static func _at_gate(contract: Dictionary, gate_id: String) -> Dictionary:
	var fields := contract.duplicate()
	fields["gate"] = gate_id
	return FlightContract.make(fields)


## `contracts` with the one of `contract`'s id replaced by it.
static func _replaced(contracts: Array[Dictionary], contract: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for other in contracts:
		out.append(contract if other["id"] == contract["id"] else other)
	return out


## The gates of `grounds` that take a `plane_class` plane, best fit first: the
## smallest max_class, then the lowest letter (decision runway-and-taxi-
## technical-design-movement-plan-analytic-bookings-planned-pauses, section 3).
static func _best_fit(grounds: Dictionary, plane_class: String) -> Array[String]:
	var out: Array[String] = []
	for gate_id: String in grounds:
		if FlightGround.class_fits(plane_class, grounds[gate_id]["max_class"]):
			out.append(gate_id)
	out.sort_custom(
		func(a: String, b: String) -> bool:
			var size_a := PlaneClasses.ORDER.find(grounds[a]["max_class"])
			var size_b := PlaneClasses.ORDER.find(grounds[b]["max_class"])
			return size_a < size_b if size_a != size_b else a < b
	)
	return out


## {"gate": the best-fit gate the contract made of valid `terms` fits at, or
## ""; "problem": "" or why none fits; "refusal": the taxi refusal behind a
## TAXI_BUSY_TEXT or QUIET_NIGHT_TEXT problem, else {}; "blocker": "" or the
## kind of refusal, a BLOCKER_ value}. A departure in the quiet night fails at
## every gate, so it is named first. Then a gate that is free but has no taxi
## plan names TAXI_BUSY_TEXT, else the best fit's clash. `extra` are contracts
## (made by _candidate) planned as if already accepted, and they must still
## plan beside it. With `ignore_gate` a clash at a gate is not counted, so the
## result says whether the shared ground would take the flight if its gate
## were free (trial_assignment).
func _assignment(
	terms: Dictionary, extra: Array[Dictionary] = [], ignore_gate := false, trial := false
) -> Dictionary:
	var gates := gate_ids()
	if gates.is_empty():
		return _assigned("", "no gate has a stand", {}, BLOCKER_STAND)
	var probe := _candidate(terms, gates[0])
	if not GroundPlanner.keeps_quiet_night(FlightTimetable.starts_for(probe, probe["first_day"])):
		var night := {"reason": GroundPlanner.QUIET_NIGHT, "flight": ""}
		return _assigned("", QUIET_NIGHT_TEXT, night, BLOCKER_NIGHT)
	var grounds := gate_grounds()
	if ignore_gate:
		grounds = _with_spare_gate(grounds)
	var running: Array[Dictionary] = []
	running.append_array(_contracts)
	running.append_array(extra)
	var clash := ""
	var busy := {}
	for gate_id in _best_fit(grounds, terms["plane_size"]):
		var candidate := _candidate(terms, gate_id)
		var problem := "" if ignore_gate else _gate_problem(candidate, running)
		if problem != "":
			clash = problem if clash == "" else clash
			continue
		var from_day: int = candidate["first_day"]
		for other in extra:
			from_day = mini(from_day, other["first_day"])
		var refusal := _contracts_refusal(
			running + [candidate], candidate, from_day, grounds, extra, trial
		)
		if refusal.is_empty():
			return _assigned(gate_id, "", {}, "")
		if busy.is_empty():
			busy = {"reason": refusal["reason"], "flight": refusal["id"]}
	if not busy.is_empty():
		var kind := BLOCKER_NIGHT if busy["reason"] == GroundPlanner.QUIET_NIGHT else BLOCKER_TAXI
		return _assigned("", _ground_text(busy), busy, kind)
	if clash != "":
		return _assigned("", clash, {}, BLOCKER_GATE)
	return _assigned("", "no gate takes a %s plane" % terms["plane_size"], {}, BLOCKER_STAND)


## `grounds` with one spare gate added: the first free letter, on a stand
## FlightGround.FALLBACK_SPACING_M east of the eastmost stand, taking any class.
## The run that ignores gate overlap tries it as well, so a flight that meets
## only the planes parked at today's stands can still be told another gate
## would help; the runway and the lane it shares stay booked as they are. Not
## guaranteed: that the player could place a stand there.
static func _with_spare_gate(grounds: Dictionary) -> Dictionary:
	var east: Dictionary = {}
	for gate_id: String in grounds:
		var stand: Dictionary = grounds[gate_id]["stand"]
		if east.is_empty() or float(stand["x"]) > float(east["x"]):
			east = stand
	var out := grounds.duplicate()
	for letter in FlightGround.LETTERS:
		if not grounds.has(letter) and not east.is_empty():
			var spare := east.duplicate()
			spare["x"] = float(east["x"]) + FlightGround.FALLBACK_SPACING_M
			out[letter] = {"stand": spare, "max_class": PlaneClasses.LARGE}
			break
	return out


## An _assignment() result.
static func _assigned(
	gate_id: String, problem: String, refusal: Dictionary, blocker: String
) -> Dictionary:
	return {"gate": gate_id, "problem": problem, "refusal": refusal, "blocker": blocker}


## Why running contract `contract` could not move to `gate_id` beside
## `contracts` (its own entry there is replaced): the gate is too small for its
## plane, it would meet another flight at the gate, or TAXI_BUSY_TEXT; "".
func _move_problem(
	contract: Dictionary, gate_id: String, contracts: Array[Dictionary], grounds: Dictionary
) -> String:
	var ground: Dictionary = grounds.get(gate_id, {})
	if not FlightGround.class_fits(contract["plane_size"], ground.get("max_class", "")):
		return "gate %s takes no %s plane" % [gate_id, contract["plane_size"]]
	var moved := _at_gate(contract, gate_id)
	var problem := _gate_problem(moved, contracts)
	if problem != "":
		return problem
	var refusal := _contracts_refusal(
		_replaced(contracts, moved), moved, _next_day[contract["id"]], grounds
	)
	return _ground_text(refusal) if not refusal.is_empty() else ""


## The taxi refusal ({"id", "reason"}) of the world with `contracts` in place
## of the running ones, on every day from `from_day` whose plan can differ, for
## `subject` (a contract, new or moved, whose own occurrences must plan) or an
## existing flight it would leave with no plan; {} for none. Every new
## contract in `contracts` starts on its first_day. The contracts of `also`
## (new ones planned as if already accepted) must plan too. A `trial` plans
## both worlds on the trial planner (_trial_plans), never on the live one.
func _contracts_refusal(
	contracts: Array,
	subject: Dictionary,
	from_day: int,
	grounds: Dictionary,
	also := [],
	trial := false
) -> Dictionary:
	var world := _world(grounds)
	world["contracts"] = contracts
	var start_day: Dictionary = _start_day.duplicate()
	var next_day: Dictionary = _next_day.duplicate()
	for contract: Dictionary in contracts:
		if not _next_day.has(contract["id"]):
			start_day[contract["id"]] = contract["first_day"]
			next_day[contract["id"]] = contract["first_day"]
	world["start_day"] = start_day
	world["next_day"] = next_day
	var subjects := [subject["id"]]
	for contract: Dictionary in also:
		subjects.append(contract["id"])
	var days := FlightPlans.days_from(world, from_day)
	if trial:
		return _trial_planner().refusal(world, _trial_day_plan, days, subjects)
	return _plans.refusal(world, _day_plan, days, subjects)


## The player's words for a taxi refusal ({"reason"}).
static func _ground_text(refusal: Dictionary) -> String:
	if refusal["reason"] == GroundPlanner.QUIET_NIGHT:
		return QUIET_NIGHT_TEXT
	if refusal["reason"] == GroundPlanner.BAD_ROUTE:
		return "its taxi route cannot be booked"
	return TAXI_BUSY_TEXT


## Why `contract` could not run beside `contracts` at its gate: a running
## contract, or a live flight (a one-off, or an issued occurrence of another
## contract, which keeps the gate it was issued at), that it would meet there;
## "" for none. Its own issued occurrences are left out: they are days it no
## longer issues. The shared ground is GroundPlanner's (_contracts_refusal).
func _gate_problem(contract: Dictionary, contracts: Array[Dictionary]) -> String:
	for other in contracts:
		if other["id"] == contract["id"] or _ended.has(other["id"]):
			continue
		if FlightTimetable.contracts_share_gate(contract, other):
			return (
				"contract %s clashes with %s at gate %s"
				% [contract["id"], other["id"], other["gate"]]
			)
	for flight in _flights:
		if flight["contract"] == contract["id"]:
			continue
		if FlightTimetable.contract_meets(contract, flight["gate"], flight["starts"]):
			return (
				"contract %s clashes with flight %s at gate %s"
				% [contract["id"], flight["id"], flight["gate"]]
			)
	return ""


## The planning world of the sim now (FlightPlans), on `grounds`.
func _world(grounds := {}) -> Dictionary:
	return {
		"contracts": _contracts,
		"start_day": _start_day,
		"next_day": _next_day,
		"ended": _ended,
		"reserving": _reserving,
		"flights": _flights,
		"landed": _landed,
		"grounds": grounds if not grounds.is_empty() else gate_grounds(),
		"works": runway.works.fixed_bookings(),
	}


## The plan of calendar day `day` for the sim now, cached until the contracts,
## the flights or the gates' grounds change.
func _day_plan(day: int) -> Dictionary:
	var grounds := gate_grounds()
	var key := str(grounds)
	if _day_plans_revision != _revision or key != _grounds_key:
		_day_plans.clear()
		_day_plans_revision = _revision
		_grounds_key = key
	if not _day_plans.has(day):
		_day_plans[day] = _plans.plan_day(_world(grounds), day)
	return _day_plans[day]


## The plan of calendar day `day` for the sim now as the trial planner makes
## it: the same plan _day_plan() gives (planning is a function of the world),
## cached apart from it, so a trial never fills, reads or replans the live
## planner or its cache.
func _trial_day_plan(day: int) -> Dictionary:
	var grounds := gate_grounds()
	var key := "%d %s %s" % [_revision, grounds, runway.works.fixed_bookings()]
	if key != _trial_plans_key:
		_trial_day_plans.clear()
		_trial_plans_key = key
	if not _trial_day_plans.has(day):
		_trial_day_plans[day] = _trial_planner().plan_day(_world(grounds), day)
	return _trial_day_plans[day]


## The trial planner, made on first use.
func _trial_planner() -> FlightPlans:
	if _trial_plans == null:
		_trial_plans = FlightPlans.new()
	return _trial_plans


## A change to the contracts or flights that can change a plan.
func _changed() -> void:
	_revision += 1
	_reported.clear()


## Issues every occurrence whose issue tick has come, oldest first (then by
## contract order and day), so the order never depends on dictionary order.
## Nothing while the airport is closed.
func _issue_due() -> void:
	if opened_tick < 0:
		return
	var due: Array = []
	for index in _contracts.size():
		var contract := _contracts[index]
		if _ended.has(contract["id"]):
			continue
		var day: int = _next_day[contract["id"]]
		while FlightTimetable.issue_tick(contract, day) <= tick:
			due.append([FlightTimetable.issue_tick(contract, day), index, day])
			day += 1
	due.sort_custom(_issued_before)
	for entry in due:
		_issue(_contracts[entry[1]], entry[2])


## Orders [issue tick, contract index, day] entries field by field.
static func _issued_before(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


func _issue(contract: Dictionary, day: int) -> void:
	var id := FlightTimetable.occurrence_id(contract["id"], day)
	var starts := FlightTimetable.starts_for(contract, day)
	_insert(_record(id, starts, contract["gate"], contract["id"], day))
	_next_day[contract["id"]] = day + 1
	occurrence_added.emit(id)


func _insert(record: Dictionary) -> void:
	var at := _flights.size()
	while at > 0 and FlightTimetable.flight_before(record, _flights[at - 1]):
		at -= 1
	_flights.insert(at, record)


## Drops each departed occurrence an hour after it departs, keeping it in
## _landed for the rest of its day, and drops the landed occurrences of days
## gone (no plan of today depends on them).
func _prune() -> void:
	for i in range(_flights.size() - 1, -1, -1):
		var flight := _flights[i]
		if flight["contract"] == "":
			continue
		var contract := contract_of(flight["contract"])
		if tick >= FlightTimetable.prune_tick(contract, flight["day"]):
			_landed.append(flight)
			_flights.remove_at(i)
	var today := GameCalendar.day_of(tick)
	for i in range(_landed.size() - 1, -1, -1):
		if FlightPlans.day_of(_landed[i]["starts"]) < today:
			_landed.remove_at(i)
			for day: int in _day_plans.keys():
				if day < today:
					_day_plans.erase(day)
	for day: int in _trial_day_plans.keys():
		if day < today:
			_trial_day_plans.erase(day)


func _advance(flight: Dictionary) -> void:
	var starts: Array = flight["starts"]
	while flight["state"] < State.DEPARTED and tick >= starts[flight["state"] + 1]:
		flight["state"] += 1
		state_changed.emit(flight["id"], flight["state"])
		if flight["state"] == State.DOORS_CLOSED:
			doors_closed.emit(flight["id"])


## The live record, or for an issued occurrence that was pruned, a departed
## record rebuilt from its contract; {} for anything else, including the days
## a contract skipped while the airport was closed.
func _find(id: String) -> Dictionary:
	var index := _index_of(id)
	if index >= 0:
		return _flights[index]
	var parts := FlightTimetable.parse_occurrence(id)
	if parts.is_empty():
		return {}
	var contract := contract_of(parts["contract"])
	var day: int = parts["day"]
	if contract.is_empty():
		return {}
	if day < _start_day[contract["id"]] or day >= _next_day[contract["id"]]:
		return {}
	var record := _record(
		id, FlightTimetable.starts_for(contract, day), contract["gate"], contract["id"], day
	)
	record["state"] = State.DEPARTED
	return record


func _index_of(id: String) -> int:
	for i in _flights.size():
		if _flights[i]["id"] == id:
			return i
	return -1
