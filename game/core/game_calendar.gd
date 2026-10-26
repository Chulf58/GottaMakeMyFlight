class_name GameCalendar
extends RefCounted
## The in-game day and time of day, as pure functions of SimClock.tick. The
## calendar holds no state, so it needs no snapshot: saving the tick saves
## the date. Tick 0 is day 0 at 06:00, when a new game starts. The clock runs
## the full 24 hours. Ticks before the start floor into earlier days.

## One game minute per real second at 1x. At this rate the flight phases read
## as real airport times: boarding (1200 ticks) is one hour and a whole
## turnaround (2580 ticks) just over two. A day is 24 real minutes at 1x and
## 8 at 3x, so a play session sees several days.
const TICKS_PER_MINUTE := 20
const MINUTES_PER_DAY := 24 * 60
const TICKS_PER_DAY := TICKS_PER_MINUTE * MINUTES_PER_DAY
## A new game starts at 06:00 on day 0.
const START_MINUTE := 6 * 60
const START_TICK_OF_DAY := START_MINUTE * TICKS_PER_MINUTE


static func day_of(tick: int) -> int:
	return floor_div(tick + START_TICK_OF_DAY, TICKS_PER_DAY)


## Ticks since midnight, 0 to TICKS_PER_DAY - 1.
static func tick_of_day(tick: int) -> int:
	return posmod(tick + START_TICK_OF_DAY, TICKS_PER_DAY)


## Minutes since midnight, 0 to MINUTES_PER_DAY - 1.
static func minute_of_day(tick: int) -> int:
	@warning_ignore("integer_division")
	return tick_of_day(tick) / TICKS_PER_MINUTE


## The 24-hour clock, "06:00".
static func clock_text(tick: int) -> String:
	var minute := minute_of_day(tick)
	@warning_ignore("integer_division")
	return "%02d:%02d" % [minute / 60, minute % 60]


## The tick of midnight starting `day`; negative for day 0, which starts at 06:00.
static func day_start(day: int) -> int:
	return day * TICKS_PER_DAY - START_TICK_OF_DAY


## The tick at `minute` past midnight on `day`.
static func tick_at(day: int, minute: int) -> int:
	return day_start(day) + minute * TICKS_PER_MINUTE


## Integer division rounded down, for negative ticks too. `divisor` is positive.
static func floor_div(value: int, divisor: int) -> int:
	@warning_ignore("integer_division")
	return (value - posmod(value, divisor)) / divisor
