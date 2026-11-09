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
	# A gate desk is priced like a check-in desk.
	&"gate_desk": 400,
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
	# Decor (Furniture 4/4): no running cost and it earns nothing, it calms
	# passengers nearby, so it is priced by size and showiness. A post or a bin
	# is cheaper than a seat row, a bench or planter about a cafe table's half,
	# the tree bench, fountain and statue are the showpieces.
	&"metal_pole": 40,
	&"metal_pole_chain": 60,
	&"trash_can": 60,
	&"bush": 80,
	&"plant_pot_1a": 100,
	&"bench_1a": 120,
	&"plant_pot_2a": 150,
	&"tree_indoor": 500,
	&"bench_2a_indoor": 900,
	&"statue_indoor": 1200,
	&"fountain_indoor": 1500,
	# Services (Furniture 3b): food pieces sit around the cafe's 600 counter and
	# 300 table, a four-seat table or booth a step above the cafe's two-seat
	# table; the desks and booths are about a check-in desk (400) to a counter.
	&"bar_counter": 700,
	&"grab_and_go_stall": 500,
	&"restaurant_table": 450,
	&"restaurant_booth": 600,
	&"info_desk": 400,
	&"info_screen": 300,
	&"currency_exchange": 800,
	&"atm": 600,
	&"pharmacy_counter": 700,
	&"pharmacy_shelf": 250,
	# Retail (F4-5): a duty free or fashion till is a counter with a till, about
	# the pharmacy counter; a shelf or rail of goods a step above the pharmacy
	# shelf, as those stores earn more per visit.
	&"duty_free_till": 700,
	&"fashion_till": 700,
	&"duty_free_shelf": 300,
	&"fashion_rail": 300,
	# Paid services: a shower and a nap pod earn a fee per use (SHOWER_FEE,
	# NAP_POD_FEE) and cost no upkeep.
	&"shower_cubicle": 500,
	&"nap_pod": 600,
	# Activities (Furniture 3): play pieces and the lounge are plain furniture, a
	# sofa a little over a seat row; the work desk has lights and two seats. The
	# prize podium is the dearest piece in the terminal because it holds a car
	# (decision furniture-set-modelled-on-copenhagen-airport-decor-calms-pas);
	# it has a running cost (PRIZE_CAR_UPKEEP).
	&"play_blocks": 350,
	&"play_slide": 450,
	&"lounge_sofa": 350,
	&"lounge_armchair": 200,
	&"work_desk": 500,
	&"prize_podium": 3000,
}

## What the landside build tools cost (decision landside-parking-kinds-a-cheap-
## surface-lot-and-an-expensive; Landside 3/4). Tuning values, to be checked in
## a playtest: a curb bay (two berths) costs about a cafe table, a surface lot
## (12 spaces) about three check-in desks, a multi-storey (31 spaces) about four
## times a lot. A car pays SURFACE_LOT_FEE once when it parks, so a lot earns
## its price back after about 60 cars.
const LANDSIDE_PRICES := {
	&"curb_bay": 300,
	&"surface_lot": 1200,
	&"multi_storey": 5000,
}

## What a land plot costs, by how many plots the player has bought before it
## (user ruling land-plot-price-rises-with-each-plot-bought-from-a-small-tun:
## cheap first plots, each buy makes the next dearer, location plays no part).
## Past the end each plot costs the last step more again (price_of_land_plot()).
## Tuning values, to be checked in a playtest: the first plot is about a
## sixth of the floor it holds (625 tiles at FLOOR_PRICE), the tenth more than
## the starting budget.
const LAND_PLOT_PRICES: Array[int] = [
	2500, 3500, 5000, 7000, 9500, 12500, 16000, 20000, 24500, 29500
]

## What the runway works cost, by the size they build (decision runway-upgrade-
## works-wait-for-a-timetable-gap-passengers-per-plane-class; design section 7).
## Placeholders, to be tuned by playtest: a medium runway about two land plots,
## a large one more than the starting budget twice over.
const RUNWAY_PRICES := {"medium": 15000, "large": 40000}

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
## What the prize car on its podium costs to run per game day (decision
## furniture-set-modelled-on-copenhagen-airport-decor-calms-pas: it costs money
## to place and run). A tuning value: a little under a shop server's wage, as
## the car pays back through the extra shop spend around it.
const PRIZE_CAR_UPKEEP := 40
## What an info screen costs to run per game day, like a screen stand (a
## display, so a screen's upkeep, decision shops-and-food-stalls-earn-per-visit-
## toilets-and-screens-cos).
const INFO_SCREEN_UPKEEP := 6
## What a passenger pays for one shower and one nap-pod stay: paid services, so
## they earn per use and have no upkeep. Tuning values: a shower is a little
## over a cafe visit (base spend 15), a nap a little under it.
const SHOWER_FEE := 25
const NAP_POD_FEE := 20

## What one hired member of a role costs per game day (ruling staff-wages-
## charged-daily-at-midnight-unpaid-wages-carried-as-owed). Tuning values, to
## be checked in a playtest. One entry per StaffMember.Role; a test keeps the
## two in step. A shop server earns a little less than a check-in agent: about
## four full cafe visits (base spend 15) a day pay for one. A cleaner earns
## less than a server (decision cleaner-staff-and-messes-visits-leave-messes-
## bins-fill-pooled-cleaners-nearest-mess: about 40 a day, no shifts).
const WAGES := {
	StaffMember.Role.CHECKIN: 60,
	StaffMember.Role.SECURITY: 90,
	StaffMember.Role.SHOP: 50,
	StaffMember.Role.CLEANER: 40,
}

## The share of its fee an airline pays for a passenger who makes the flight
## but whose bag missed it (ruling baggage-rides-a-player-built-belt-from-check-
## in-to-a-bag-roo: the reduction is a tuning value, to be checked in a
## playtest).
const MISSED_BAG_FEE_PERCENT := 50


static func price_of_floor() -> int:
	return FLOOR_PRICE


## The price of the works that build a runway of `size`, NO_PRICE for a size
## nothing builds (small is where a game starts).
static func runway_price(size: String) -> int:
	return RUNWAY_PRICES.get(size, NO_PRICE)


## The price of the next land plot after `bought` plots (LAND_PLOT_PRICES),
## NO_PRICE for a negative count.
static func price_of_land_plot(bought: int) -> int:
	if bought < 0:
		push_error("PriceTable: no land price after %d plots" % bought)
		return NO_PRICE
	var last := LAND_PLOT_PRICES.size() - 1
	if bought <= last:
		return LAND_PLOT_PRICES[bought]
	var step := LAND_PLOT_PRICES[last] - LAND_PLOT_PRICES[last - 1]
	return LAND_PLOT_PRICES[last] + (bought - last) * step


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


## What a landside build costs (LANDSIDE_PRICES); an unknown id has no price.
static func price_of_landside(id: StringName) -> int:
	if not LANDSIDE_PRICES.has(id):
		push_error("PriceTable: no price for landside build '%s'" % id)
		return NO_PRICE
	return LANDSIDE_PRICES[id]


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
