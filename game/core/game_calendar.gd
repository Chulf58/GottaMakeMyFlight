class_name GameCalendar
extends RefCounted
## The in-game day and time of day, as pure functions of a tick and the
## calendar epoch E (decision closed-airport-calendar-design-an-explicit-
## calendar-epoch-pa). The calendar maps tick - E: E is calendar day 0 at
## 06:00. SimClock owns and saves E (SimClock.epoch): it equals the tick while
## a gate-bound airport is closed, so no minute or day passes then, and it
## freezes at the opening tick. Every call takes E explicitly, with no default,
## so a caller that forgot it fails to parse instead of reading raw ticks. The
## clock runs the full 24 hours. Ticks before E floor into earlier days.

## One game minute per real second at 1x. At this rate the flight phases read
## as real airport times: boarding (1200 ticks) is one hour and a whole
## turnaround (2580 ticks) just over two. A day is 24 real minutes at 1x and
## 8 at 3x, so a play session sees several days.
const TICKS_PER_MINUTE := 20
const MINUTES_PER_DAY := 24 * 60
const TICKS_PER_DAY := TICKS_PER_MINUTE * MINUTES_PER_DAY
const DAYS_PER_YEAR := 10
## The calendar starts (at E) at 06:00 on day 0.
const START_MINUTE := 6 * 60
const START_TICK_OF_DAY := START_MINUTE * TICKS_PER_MINUTE


static func day_of(tick: int, epoch: int) -> int:
	return floor_div(tick - epoch + START_TICK_OF_DAY, TICKS_PER_DAY)


## Ticks since midnight, 0 to TICKS_PER_DAY - 1.
static func tick_of_day(tick: int, epoch: int) -> int:
	return posmod(tick - epoch + START_TICK_OF_DAY, TICKS_PER_DAY)


## Whether `tick` is the last of its day: the next tick is the first of the next.
static func is_last_tick_of_day(tick: int, epoch: int) -> bool:
	return tick_of_day(tick, epoch) == TICKS_PER_DAY - 1


## Minutes since midnight, 0 to MINUTES_PER_DAY - 1.
static func minute_of_day(tick: int, epoch: int) -> int:
	@warning_ignore("integer_division")
	return tick_of_day(tick, epoch) / TICKS_PER_MINUTE


## The 24-hour clock, "06:00".
static func clock_text(tick: int, epoch: int) -> String:
	var minute := minute_of_day(tick, epoch)
	@warning_ignore("integer_division")
	return "%02d:%02d" % [minute / 60, minute % 60]


## The tick of midnight starting `day`; before E for day 0, which starts at 06:00.
static func day_start(day: int, epoch: int) -> int:
	return epoch + day * TICKS_PER_DAY - START_TICK_OF_DAY


## The tick at `minute` past midnight on `day`.
static func tick_at(day: int, minute: int, epoch: int) -> int:
	return day_start(day, epoch) + minute * TICKS_PER_MINUTE


## Integer division rounded down, for negative ticks too. `divisor` is positive.
static func floor_div(value: int, divisor: int) -> int:
	@warning_ignore("integer_division")
	return (value - posmod(value, divisor)) / divisor


## Completed airport years at `day`: days 0..9 -> 0, 10..19 -> 1, 20..29 -> 2.
static func year_of(day: int) -> int:
	return floor_div(day, DAYS_PER_YEAR)


## Day index within the current airport year, 0 to DAYS_PER_YEAR - 1.
static func day_of_year(day: int) -> int:
	return posmod(day, DAYS_PER_YEAR)
