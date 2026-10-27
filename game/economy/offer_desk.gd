class_name OfferDesk
extends Node
## The scene's one OfferBoard, and the day-boundary hook that feeds it: on a new
## game the clock's current day gets its offers, and each time SimClock enters
## a new day (GameCalendar.day_of) OfferBoard.ensure_day expires yesterday's
## open offers and draws today's from SimClock.rng. The calendar is derived
## from the tick, so the desk keeps no day of its own that a save would hold:
## the whole-world save (Economy 8/8) saves board.to_snapshot() beside SimClock's
## snapshot, whose rng seed and state the next day's draw continues from.

## The clock to follow when this node enters a scene. Tests call bind_clock.
@export var clock: SimClock

var board := OfferBoard.new()

var _day := -1


func _ready() -> void:
	if clock != null:
		bind_clock(clock)


## Follows `sim_clock` and draws offers for its current day if the board has none.
func bind_clock(sim_clock: SimClock) -> void:
	clock = sim_clock
	_day = GameCalendar.day_of(clock.tick)
	board.ensure_day(_day, clock.rng)
	clock.ticked.connect(on_tick)


func on_tick(tick: int) -> void:
	var day := GameCalendar.day_of(tick)
	if day == _day:
		return
	_day = day
	board.ensure_day(day, clock.rng)
