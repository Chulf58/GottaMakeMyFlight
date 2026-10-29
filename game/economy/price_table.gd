class_name PriceTable
extends RefCounted
## What building, staffing and running rooms cost. Every number lives here: the
## starting budget, the per-piece prices, the refund share, the daily wages and
## the daily toilet upkeep. Prices are whole numbers. A lookup for something
## with no price returns NO_PRICE, never 0, so a missing entry cannot read as
## "free".

## Returned for an unknown object id or a wall kind with no price.
const NO_PRICE := -1

const STARTING_BUDGET := 20000
## Share of the price paid back when a floor tile, wall or object is removed.
const REFUND_SHARE_PERCENT := 50

const FLOOR_PRICE := 25
const WALL_PRICES := {
	BuildGrid.WallKind.PLAIN: 40,
	BuildGrid.WallKind.GLASS: 70,
	BuildGrid.WallKind.DOOR: 90,
}
## One entry per BuildCatalog id; a test keeps the two in step.
const OBJECT_PRICES := {
	&"checkin_desk": 400,
	&"security_scanner": 900,
	# Security lane parts: 2500 for a whole lane, under three basic scanners
	# (2700) but well over two (decision security-tiers-the-old-single-scanner-
	# stays-as-a-cheap-basic: the lane is the bigger, faster upgrade, run by one
	# officer). The arch and the X-ray belt are the machines; the tables are
	# plain furniture, a little under a cafe table.
	&"security_arch": 1100,
	&"xray_belt": 900,
	&"tray_table": 250,
	&"pickup_table": 250,
	&"seat_row": 250,
	&"entrance_door": 300,
	&"exit_door": 300,
	&"cafe_counter": 600,
	&"cafe_table": 300,
	# Belt pieces: a straight run is a little over a wall's price so a long
	# line from check-in is a real spend; the end is the dear piece (roller
	# slide, bumper, beacon). The cart is a plain dolly.
	&"baggage_belt": 50,
	&"baggage_belt_corner": 60,
	&"baggage_belt_feed": 90,
	&"baggage_belt_end": 200,
	&"baggage_cart": 120,
	# Toilet pieces: a stall (partition, door, pan) costs about a cafe table; the
	# sink is plain plumbing. The stall is the one with a running cost.
	&"toilet_stall": 300,
	&"toilet_sink": 150,
	# Kiosk pieces: the counter is a till and a short counter, cheaper than the
	# cafe's; a display stand is a shelf unit.
	&"kiosk_counter": 400,
	&"kiosk_display": 200,
	# A screen stand (Boredom 4/5): a display on a floor stand, dearer than a
	# seat row; it earns nothing and has a running cost.
	&"screen_stand": 350,
}

## What a ready toilet room costs to run per stall per game day (decision
## toilet-design-queue-free-reservable-stalls-per-stall-daily-u, point 2),
## charged at midnight with the wages. A tuning value, to be checked in a
## playtest: three stalls are half a check-in agent's wage.
const TOILET_STALL_UPKEEP := 10
## What one screen stand costs to run per game day, in a room or not
## (decisions boredom-and-shops-design-boredom-need-while-waiting-kiosk-sh,
## point 3, and shops-and-food-stalls-earn-per-visit-toilets-and-screens-cos),
## charged at midnight with the toilet upkeep. A tuning value, to be checked in
## a playtest: a little under a stall, as one screen is a single display.
const SCREEN_UPKEEP := 6

## What one hired member of a role costs per game day (ruling staff-wages-
## charged-daily-at-midnight-unpaid-wages-carried-as-owed). Tuning values, to
## be checked in a playtest. One entry per StaffMember.Role; a test keeps the
## two in step. A shop server earns a little less than a check-in agent: about
## four full cafe visits (base spend 15) a day pay for one.
const WAGES := {
	StaffMember.Role.CHECKIN: 60,
	StaffMember.Role.SECURITY: 90,
	StaffMember.Role.SHOP: 50,
}

## The share of its fee an airline pays for a passenger who makes the flight
## but whose bag missed it (ruling baggage-rides-a-player-built-belt-from-check-
## in-to-a-bag-roo: the reduction is a tuning value, to be checked in a
## playtest).
const MISSED_BAG_FEE_PERCENT := 50


static func price_of_floor() -> int:
	return FLOOR_PRICE


## `kind` is a BuildGrid.WallKind. NONE and out-of-range kinds have no price.
static func price_of_wall(kind: int) -> int:
	if not WALL_PRICES.has(kind):
		push_error("PriceTable: no price for wall kind %d" % kind)
		return NO_PRICE
	return WALL_PRICES[kind]


static func price_of_object(id: StringName) -> int:
	if not OBJECT_PRICES.has(id):
		push_error("PriceTable: no price for object '%s'" % id)
		return NO_PRICE
	return OBJECT_PRICES[id]


## The daily wage of a `role` (a StaffMember.Role); an unknown role has none.
static func wage_of(role: int) -> int:
	if not WAGES.has(role):
		push_error("PriceTable: no wage for staff role %d" % role)
		return NO_PRICE
	return WAGES[role]


## The fee paid for a passenger whose bag missed the flight, rounded down. A
## negative fee (NO_PRICE) stays NO_PRICE, so a failed lookup never reads as a
## cut fee.
static func fee_after_missed_bag(fee: int) -> int:
	if fee < 0:
		push_error("PriceTable: cannot cut fee %d" % fee)
		return NO_PRICE
	return fee * MISSED_BAG_FEE_PERCENT / 100


## What removing a piece that cost `price` pays back, rounded down. A negative
## price (NO_PRICE from a failed lookup) stays NO_PRICE; only a real price of 0
## refunds 0.
static func refund_of(price: int) -> int:
	if price < 0:
		push_error("PriceTable: cannot refund price %d" % price)
		return NO_PRICE
	return price * REFUND_SHARE_PERCENT / 100
