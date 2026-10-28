class_name CarryOnTraits
extends RefCounted
## What a passenger brings to security (decision
## carry-on-at-security-costs-time-only-0-2-carry-on-bags-add-s): 0 to 2
## carry-on bags, a liquids flag and an alarm flag. All three are drawn at
## spawn from the sim RNG, always, so the number of draws per passenger never
## depends on the result. Nothing reads them yet; security service time does
## in a later change.

## Whole percent of passengers per bag count, index = bags. A tuning
## placeholder: most travellers carry one, a quarter carry two.
const BAG_SHARES: Array[int] = [20, 55, 25]
const MAX_BAGS := 2
## Whole percent of passengers who carry liquids and who set off the alarm.
const LIQUIDS_PERCENT := 10
const ALARM_PERCENT := 5
## The RNG draws one passenger takes: bags, liquids, alarm, in that order.
const DRAWS := 3


## Sets `p`'s carry_on, liquids and alarm from `rng`, in that order.
static func draw(rng: RandomNumberGenerator, p: Passenger) -> void:
	var roll := rng.randi_range(0, 99)
	p.carry_on = MAX_BAGS
	for bags in BAG_SHARES.size():
		roll -= BAG_SHARES[bags]
		if roll < 0:
			p.carry_on = bags
			break
	p.liquids = rng.randi_range(0, 99) < LIQUIDS_PERCENT
	p.alarm = rng.randi_range(0, 99) < ALARM_PERCENT
