class_name IncidentTuning
extends RefCounted
## The numbers of the four major incidents, in one place (decisions daily-
## incidents-technical-design-incidentdirector-shared-clo and incident-rating-
## effects-are-penalties-only-incident-rewards). Every value is a tuning value
## the user has yet to rule on. Rewards are paid as Wallet.Category.INCIDENT
## money; rating costs are half stars of penalty (1 to RatingAdjustments.
## MAX_HALF_STAR_DELTA), never a positive adjustment.

## The roll weight of each major when it is allowed (the quiet day is 4, a
## spill up to 4). Holiday rush, VIP and favour need a running contract.
const INSPECTOR_WEIGHT := 2
const RUSH_WEIGHT := 2
const VIP_WEIGHT := 2
const FAVOUR_WEIGHT := 2
## The airline tier (RatingFormula.tier) each major needs.
const INSPECTOR_TIER := 0
const RUSH_TIER := 0
const VIP_TIER := 1
const FAVOUR_TIER := 1

## Inspector: passes with at most this many messes on the floor and at most
## this many passengers stuck in a full queue at the visit tick.
const INSPECTOR_MAX_MESSES := 2
const INSPECTOR_MAX_FULL_QUEUE := 0
## Money for a pass, and the rating penalty (half stars) for a fail.
const INSPECTOR_PASS_MONEY := 400
const INSPECTOR_FAIL_HALF_STARS := 2

## Holiday rush: extra passengers per flight (capped by the plane class
## maximum) on at most this many of the next day's flights.
const RUSH_EXTRA := 6
const RUSH_MAX_FLIGHTS := 3

## VIP: the passenger must make the flight with at least this mood (0 to 100;
## passengers start at 70). Money for a good arrival, the penalty (half stars)
## for a miss. Made with a lower mood changes nothing.
const VIP_GOOD_MOOD := 75
const VIP_BONUS_MONEY := 500
const VIP_MISS_HALF_STARS := 2

## Airline favour: extra passengers on one flight (capped by its headroom)
## and the money paid when the player accepts.
const FAVOUR_EXTRA := 8
const FAVOUR_BONUS_MONEY := 300
