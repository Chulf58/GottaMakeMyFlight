class_name PassengerThoughts
extends RefCounted
## What a passenger thought of its airport, for the inspect card (decision
## passenger-inspect-thoughts-recorded-at-sim-outcomes-saved-pin-marks-where).
## A thought is recorded where the sim decides an outcome, never guessed from a
## stage change: CafeSim records a meal paid in full and food given up before
## service, ToiletSim relief where it resets the need, PassengerSim's beat a
## long queue, and DecorEffect nice decor where its net effect is positive.
##
## Each passenger keeps its last CAP thoughts in Passenger.thoughts, a flat
## list of STRIDE numbers per thought, oldest first: kind, tick, the cell the
## passenger was on, the facility (a room or station object id, 0 for none)
## and a value (the minutes waited, for a queue). Repeat suppression is kept
## apart in Passenger.thought_marks, one tick per kind (NO_MARK for none), so a
## thought the cap drops does not come back early. Both are saved with the
## passenger (PassengerSnapshot). Thoughts never feed back into the sim.

enum Kind { MEAL, FOOD_GIVEN_UP, TOILET_RELIEF, LONG_QUEUE, NICE_DECOR }

## The most thoughts a passenger keeps; a new one drops the oldest.
const CAP := 5
## Numbers per thought in Passenger.thoughts.
const STRIDE := 6
const NO_MARK := -1
## A wait in a check-in or security queue this long is a long queue.
const LONG_QUEUE_TICKS := 10 * GameCalendar.TICKS_PER_MINUTE
## Nice decor is thought again only this long after the last time.
const DECOR_REPEAT_TICKS := 120 * GameCalendar.TICKS_PER_MINUTE
const TEXT := {
	Kind.MEAL: "That hit the spot",
	Kind.FOOD_GIVEN_UP: "Gave up on getting food",
	Kind.TOILET_RELIEF: "What a relief",
	Kind.LONG_QUEUE: "Waited %d min in the queue",
	Kind.NICE_DECOR: "Nice decor here",
}
const POSITIVE := [Kind.MEAL, Kind.TOILET_RELIEF, Kind.NICE_DECOR]
## Kinds recorded at a facility: a cafe or toilet room, a desk or scanner. Nice
## decor has none (facility 0).
const AT_FACILITY := [Kind.MEAL, Kind.FOOD_GIVEN_UP, Kind.TOILET_RELIEF, Kind.LONG_QUEUE]

const _KIND := 0
const _TICK := 1
const _X := 2
const _Y := 3
const _FACILITY := 4
const _VALUE := 5


## The one recorder: adds a thought to `p`, dropping the oldest past CAP, and
## marks its kind as last thought at `tick`. A thought with no cell, or a
## facility its kind does not take (sound()), would make the save refuse to
## load: it is refused here with an error instead.
static func record(
	p: Passenger, kind: Kind, tick: int, cell: Vector2i, facility := 0, value := 0
) -> void:
	if cell == Passenger.NO_CELL or not sound(kind, facility, value):
		push_error(
			(
				"PassengerThoughts: passenger %d's %s at %s, facility %d, value %d refused"
				% [p.id, Kind.keys()[kind], cell, facility, value]
			)
		)
		return
	p.thoughts.append_array(PackedInt64Array([kind, tick, cell.x, cell.y, facility, value]))
	var extra := p.thoughts.size() - CAP * STRIDE
	if extra > 0:
		p.thoughts = p.thoughts.slice(extra)
	_mark(p, kind, tick)


## Once a beat for a passenger in a check-in or security queue: a wait of
## LONG_QUEUE_TICKS or more is one long-queue thought per queue, started when
## the passenger joined it and updated with the minutes waited while it lasts.
## A long-queue thought the cap dropped is not added again for the same queue.
static func queued(p: Passenger, tick: int) -> void:
	if p.stage not in PassengerSim.QUEUE_STAGES or tick - p.stage_tick < LONG_QUEUE_TICKS:
		return
	@warning_ignore("integer_division")
	var minutes := (tick - p.stage_tick) / GameCalendar.TICKS_PER_MINUTE
	if mark_of(p, Kind.LONG_QUEUE) != p.stage_tick:
		record(p, Kind.LONG_QUEUE, p.stage_tick, p.at, p.station, minutes)
		return
	for start in range(0, p.thoughts.size(), STRIDE):
		var same: bool = p.thoughts[start + _KIND] == Kind.LONG_QUEUE
		if same and p.thoughts[start + _TICK] == p.stage_tick:
			p.thoughts[start + _X] = p.at.x
			p.thoughts[start + _Y] = p.at.y
			p.thoughts[start + _VALUE] = minutes


## On a beat where decor's net effect at `cell` is positive: nice decor, at
## most once every DECOR_REPEAT_TICKS.
static func decor(p: Passenger, tick: int, cell: Vector2i) -> void:
	var last := mark_of(p, Kind.NICE_DECOR)
	if last == NO_MARK or tick - last >= DECOR_REPEAT_TICKS:
		record(p, Kind.NICE_DECOR, tick, cell)


static func count(p: Passenger) -> int:
	@warning_ignore("integer_division")
	return p.thoughts.size() / STRIDE


## The passenger's thoughts newest first, each {kind, tick, cell, facility,
## value, text, positive}.
static func entries(p: Passenger) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(count(p) - 1, -1, -1):
		var start := i * STRIDE
		var kind: Kind = p.thoughts[start + _KIND] as Kind
		var value := p.thoughts[start + _VALUE]
		(
			out
			. append(
				{
					"kind": kind,
					"tick": p.thoughts[start + _TICK],
					"cell": Vector2i(p.thoughts[start + _X], p.thoughts[start + _Y]),
					"facility": p.thoughts[start + _FACILITY],
					"value": value,
					"text": text_of(kind, value),
					"positive": kind in POSITIVE,
				}
			)
		)
	return out


static func text_of(kind: Kind, value: int) -> String:
	return TEXT[kind] % value if kind == Kind.LONG_QUEUE else TEXT[kind]


## The tick `kind` was last thought (a queue: the tick that queue began), or
## NO_MARK.
static func mark_of(p: Passenger, kind: Kind) -> int:
	return p.thought_marks[kind] if p.thought_marks.size() > kind else NO_MARK


## Whether a `kind` thought may carry `facility` and `value`: a facility kind
## (AT_FACILITY) has a positive facility and nice decor none; only a long
## queue has a value (its minutes), never a negative one.
static func sound(kind: int, facility: int, value: int) -> bool:
	if kind < 0 or kind >= Kind.size():
		return false
	if (facility > 0) != (kind in AT_FACILITY) or facility < 0:
		return false
	return value >= 0 if kind == Kind.LONG_QUEUE else value == 0


## Fills `p` from a saved record's "thoughts" and "thought_marks", or returns
## false when either is malformed: whole numbers only, at most CAP thoughts of
## STRIDE numbers, each sound() with its cell on `grid`, and one mark per kind
## (no marks only with no thoughts) where every kept kind's newest thought
## carries its kind's mark. Ticks are checked by ticks_ok().
static func fill(p: Passenger, thoughts: Variant, marks: Variant, grid: BuildGrid) -> bool:
	if typeof(thoughts) != TYPE_ARRAY or typeof(marks) != TYPE_ARRAY:
		return false
	var list: Array = thoughts
	var mark_list: Array = marks
	if list.size() % STRIDE != 0 or list.size() > CAP * STRIDE:
		return false
	var marks_ok := mark_list.size() == Kind.size() or (list.is_empty() and mark_list.is_empty())
	if not marks_ok:
		return false
	for value in list + mark_list:
		if not WholeNumber.is_whole(value):
			return false
	var newest := {}
	for start in range(0, list.size(), STRIDE):
		var kind := int(list[start + _KIND])
		var cell := Vector2i(int(list[start + _X]), int(list[start + _Y]))
		if not sound(kind, int(list[start + _FACILITY]), int(list[start + _VALUE])):
			return false
		if not grid.in_bounds(cell):
			return false
		newest[kind] = int(list[start + _TICK])
	for kind: int in newest:
		if int(mark_list[kind]) != newest[kind]:
			return false
	p.thoughts = PackedInt64Array(list)
	p.thought_marks = PackedInt64Array(mark_list)
	return true


## Whether no thought or mark of `p` is later than `now` (the saved tick), and
## no mark is below NO_MARK.
static func ticks_ok(p: Passenger, now: int) -> bool:
	for start in range(0, p.thoughts.size(), STRIDE):
		if p.thoughts[start + _TICK] < 0 or p.thoughts[start + _TICK] > now:
			return false
	for mark in p.thought_marks:
		if mark < NO_MARK or mark > now:
			return false
	return true


static func _mark(p: Passenger, kind: Kind, tick: int) -> void:
	if p.thought_marks.size() != Kind.size():
		p.thought_marks.resize(Kind.size())
		p.thought_marks.fill(NO_MARK)
	p.thought_marks[kind] = tick
