class_name RatingFormula
extends RefCounted
## The airport's star rating as pure functions of passenger counts, and the
## tuning values the decision leaves to us (airport-rating-1-5-stars-over-a-
## rolling-3-days-mostly-made-o): the made share is the big part, the mood the
## passengers who made it leave with is the smaller one.

## Share of the score from passengers who made their flight, and from their
## average mood (missed passengers leave at mood 0 by the sim's own rule, so
## the mood part averages over the ones who made it only).
const WEIGHT_MADE := 0.7
const WEIGHT_MOOD := 0.3
## The rating looks at the current in-game day and the two before it.
const WINDOW_DAYS := 3
## Below this an airline sends a warning.
const WARN_BELOW := 2.0
## An airline ends its contract after the warning day and two more low days,
## counted at day ends.
const LOW_DAYS_TO_END := 3
## The low-day count an airline's ending leaves behind (decision low-rating-
## ends-one-airline-contract-per-low-day, user-ruled "One more per extra low
## day"): one short of LOW_DAYS_TO_END, so each further low day ends one more
## airline, and a day that is not low resets the count to 0 and stops the run.
const LOW_DAYS_AFTER_END := LOW_DAYS_TO_END - 1
## Stars that unlock the first and second airline tier (the offer board's
## thresholds; below the first is tier 0).
const TIER_STARS: Array[float] = [3.0, 4.0]
## What a new airport shows before any passenger has been recorded: clear of the
## warning, short of the first unlock.
const STARTING_STARS := 2.5
const MIN_STARS := 1.0
const MAX_STARS := 5.0
## Most passengers one day may hold (a save is refused above it).
const MAX_DAY_COUNT := 1000000
## Keeps an exact half-step tie (4.25) from rounding down on float noise.
const TIE_EPSILON := 1e-9


## Stars from pooled counts: `mood_sum` is the sum of the mood of the `made`
## passengers at exit. 1 to 5 in half steps; no passengers gives STARTING_STARS.
static func stars(made: int, missed: int, mood_sum: int) -> float:
	var total := made + missed
	if total == 0:
		return STARTING_STARS
	var made_share := float(made) / total
	var mood_share := 0.0
	if made > 0:
		mood_share = float(mood_sum) / (made * PassengerSim.MOOD_MAX)
	var score := WEIGHT_MADE * made_share + WEIGHT_MOOD * mood_share
	var raw := MIN_STARS + (MAX_STARS - MIN_STARS) * score
	var half_steps := floorf(raw * 2.0 + 0.5 + TIE_EPSILON)
	return clampf(half_steps / 2.0, MIN_STARS, MAX_STARS)


## How many TIER_STARS thresholds `stars` meets, 0 to TIER_STARS.size().
static func tier(stars_value: float) -> int:
	var met := 0
	for threshold in TIER_STARS:
		if stars_value >= threshold:
			met += 1
	return met
