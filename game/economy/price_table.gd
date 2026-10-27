class_name PriceTable
extends RefCounted
## What building costs. Every number lives here: the starting budget, the
## per-piece prices and the refund share. Prices are whole numbers. A lookup
## for something with no price returns NO_PRICE, never 0, so a missing entry
## cannot read as "free".

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
	&"seat_row": 250,
	&"entrance_door": 300,
	&"exit_door": 300,
	&"cafe_counter": 600,
	&"cafe_table": 300,
}


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


## What removing a piece that cost `price` pays back, rounded down. A negative
## price (NO_PRICE from a failed lookup) stays NO_PRICE; only a real price of 0
## refunds 0.
static func refund_of(price: int) -> int:
	if price < 0:
		push_error("PriceTable: cannot refund price %d" % price)
		return NO_PRICE
	return price * REFUND_SHARE_PERCENT / 100
