class_name ItemInfo
extends RefCounted
## The hover card text of every build tray item (decision build-menu-items-show-
## a-hover-card-with-a-description): [what it is, how it works, what it needs or
## costs to run], plain sentences checked against the sim and build rules.
## BuildMenu gives it to the item's card (ItemCardButton). It lives here, keyed
## by tool, so build_menu.gd stays under the gdlint line cap; a test checks that
## every tray item has an entry and every entry an item.
##
## Each sentence sits inside tr() so POT generation reads it; tr() is an instance
## method, so of() builds an ItemInfo to ask. A tool with no card has no branch.


## The three texts of a tool's hover card, or an empty array for a tool with none.
static func of(tool: BuildMode.Tool) -> Array:
	return ItemInfo.new().texts(tool)


## The tools that have a hover card.
static func tools() -> Array[BuildMode.Tool]:
	var found: Array[BuildMode.Tool] = []
	for tool: BuildMode.Tool in BuildMode.Tool.values():
		if not of(tool).is_empty():
			found.append(tool)
	return found


func texts(tool: BuildMode.Tool) -> Array:
	var lines := []
	match tool:
		BuildMode.Tool.FLOOR:
			lines = [
				tr("Floor tile. Passengers can only walk and stand on floor."),
				tr(
					"Drag a rectangle to lay many tiles at once. Everything else is built on floor."
				),
				tr("Land you own. Removing a tile refunds half."),
			]
		BuildMode.Tool.WALL:
			lines = [
				tr("A wall along a tile edge. Passengers cannot cross it and it blocks the view."),
				tr("Drag along a line to build a row. Walls close in the terminal and its rooms."),
				tr("One wall per tile edge. Removing it refunds half."),
			]
		BuildMode.Tool.GLASS:
			lines = [
				tr("A glass wall. Passengers cannot cross it, but it lets the view through."),
				tr("Drag along a line like a wall. Screens and decor can be seen through glass."),
				tr("Costs more than a plain wall. One per tile edge."),
			]
		BuildMode.Tool.DOOR:
			lines = [
				tr("A door in a wall. Passengers walk through it."),
				tr("Click a wall edge to put a door in the wall."),
				tr("A plain wall on each side of it."),
			]
		BuildMode.Tool.ENTRANCE:
			lines = [
				tr(
					"The way into the terminal. Passengers come in here from the road and car parks."
				),
				tr("Place it on the outer edge of the terminal, facing in."),
				tr("The outside edge with no floor behind it. Keep the spot in front clear."),
			]
		BuildMode.Tool.EXIT:
			lines = [
				tr("The way out to the planes. Passengers leave the terminal here to board."),
				tr(
					"Place it on the outer edge. A gate desk links to an exit facing west, north or east."
				),
				tr("The outside edge with no floor behind it. Keep the spot in front clear."),
			]
		BuildMode.Tool.DESK:
			lines = [
				tr("Where passengers check in and hand over a bag."),
				tr(
					"A check-in agent works behind it. A belt from its back edge takes bags to a bag room."
				),
				tr(
					"An agent hired in Staff, or it stays closed. Keep the spot behind and in front clear."
				),
			]
		BuildMode.Tool.SCANNER:
			lines = [
				tr("A basic security scanner. Passengers walk through it to be screened."),
				tr("A security officer works beside it. A full lane is faster but costs more."),
				tr(
					"An officer hired in Staff, or it stays closed. Keep its staff spot and way in clear."
				),
			]
		BuildMode.Tool.SEATS:
			lines = [
				tr(
					"A row of seats. Passengers wait here for their flight and their mood recovers."
				),
				tr("Place it near the gate and turn it. Waiting passengers sit on it."),
				tr("No staff and no upkeep. Add enough seats for the passengers waiting."),
			]
		BuildMode.Tool.GATE_DESK:
			lines = [
				tr(
					# gdlint:ignore = max-line-length
					"Makes a gate. It links to the nearest free exit facing the planes; the plane parks out from it."
				),
				tr(
					"Each flight is given a gate. A gate takes the next free letter, starting at A."
				),
				tr(
					"Within 4 cells of a free exit facing the planes, with room for the plane. No staff needed."
				),
			]
		BuildMode.Tool.BUS_GATE_DESK:
			lines = [
				tr(
					# gdlint:ignore = max-line-length
					"Makes a bus gate. It links to an exit facing the apron with a 16 x 6 m bus bay outside."
				),
				tr("Passengers board shuttle buses here to reach remote stands on the apron."),
				tr(
					# gdlint:ignore = max-line-length
					"Within 4 cells of a free exit with clear 16 x 6 m apron room outside. Staffed by a Gate Agent."
				),
			]
		BuildMode.Tool.REMOTE_STAND:
			lines = [
				tr(
					# gdlint:ignore = max-line-length
					"An apron parking stand with no jet bridge. Serves small, medium or large planes that fit."
				),
				tr(
					# gdlint:ignore = max-line-length
					"Assigned IDs starting at R1 with automatic taxiway paving north to the taxi lane."
				),
				tr(
					# gdlint:ignore = max-line-length
					"Place on an owned apron spot with clear room for aircraft and taxiway access. Requires a Bus gate desk to board."
				),
			]
		BuildMode.Tool.SCREEN:
			lines = [
				tr("A floor screen that entertains passengers waiting in front of it."),
				tr(
					"It covers a fan of floor up to 5 rows ahead. A plain wall blocks it, glass does not."
				),
				tr("Costs upkeep every day, inside a room or not."),
			]
		BuildMode.Tool.CAFE_ROOM:
			lines = [
				tr(
					"Marks floor as a cafe. Hungry passengers eat and drink here and their mood rises."
				),
				tr(
					"Drag a rectangle, then add a counter and a table. Guests order, then sit at the table."
				),
				tr(
					"At least 3x3, with a counter and a table. Needs shop staff, or the counter stays closed."
				),
			]
		BuildMode.Tool.COUNTER:
			lines = [
				tr("The cafe counter, where guests order."),
				tr("Place it inside a cafe or restaurant. A server stands there."),
				tr(
					"Wholly inside the room. Shop staff hired in Staff, and the spot in front clear."
				),
			]
		BuildMode.Tool.TABLE:
			lines = [
				tr("A table with a seat at each end. Cafe guests sit here to eat."),
				tr("It seats two. A guest walks from the counter to a free seat."),
				tr(
					"Inside a cafe. A bar uses bar counters, and a restaurant uses dining tables or booths."
				),
			]
		BuildMode.Tool.TOILET_ROOM:
			lines = [
				tr("Marks floor as a toilet. Passengers who need one queue and use a stall."),
				tr("Drag a rectangle, then add a stall and a sink inside."),
				tr(
					"At least 2x3, with a stall and a sink. Each stall costs upkeep every day when ready."
				),
			]
		BuildMode.Tool.TOILET_STALL:
			lines = [
				tr("One toilet stall. One passenger uses it at a time."),
				tr("Place it inside a toilet room. A passenger walks in from the cell in front."),
				tr("Keep the spot in front clear. Costs upkeep every day once its room is ready."),
			]
		BuildMode.Tool.TOILET_SINK:
			lines = [
				tr("A sink. A toilet room is not ready without one."),
				tr("Place it inside a toilet room."),
				tr("Keep the spot in front clear. No upkeep of its own."),
			]
		BuildMode.Tool.KIOSK_ROOM:
			lines = [
				tr("Marks floor as a kiosk, a small shop. Bored passengers browse here and pay."),
				tr(
					"Drag a rectangle, then add a counter and display stands. Guests browse at the stands."
				),
				tr(
					"At least 3x3, with a counter and a display stand. Shop staff serve at the counter."
				),
			]
		BuildMode.Tool.KIOSK_COUNTER:
			lines = [
				tr("The kiosk's counter, with a till."),
				tr("Place it inside a kiosk. A server stands behind it."),
				tr(
					"Wholly inside the kiosk. Shop staff hired in Staff, and the spot in front clear."
				),
			]
		BuildMode.Tool.PHARMACY_ROOM:
			lines = [
				tr("Marks floor as a pharmacy. Passengers browse and buy here."),
				tr(
					"Drag a rectangle, then add a counter and a shelf. Passengers browse at the shelf."
				),
				tr("At least 3x3, with a counter and a shelf. Shop staff serve at the counter."),
			]
		BuildMode.Tool.DUTY_FREE_ROOM:
			lines = [
				tr(
					"Marks floor as a duty free shop. Passengers browse and spend more than in a kiosk."
				),
				tr(
					"Drag a rectangle, then add a till and shelves. Passengers browse at the shelves."
				),
				tr("At least 3x4, with a till and a shelf. Shop staff serve at the till."),
			]
		BuildMode.Tool.DUTY_FREE_TILL:
			lines = [
				tr("The duty free shop's till."),
				tr("Place it inside a duty free shop. A server stands behind it."),
				tr(
					"Wholly inside the shop. Shop staff hired in Staff, and the spot in front clear."
				),
			]
		BuildMode.Tool.DUTY_FREE_SHELF:
			lines = [
				tr("A duty free shelf. Each one gives two browse spots."),
				tr("Passengers browse from the cells in front of it."),
				tr("Inside a duty free shop. Keep the cells in front clear."),
			]
		BuildMode.Tool.FASHION_ROOM:
			lines = [
				tr(
					"Marks floor as a fashion store. Passengers browse and spend more than in a kiosk."
				),
				tr(
					"Drag a rectangle, then add a till and clothes rails. Passengers browse at the rails."
				),
				tr("At least 3x4, with a till and a clothes rail. Shop staff serve at the till."),
			]
		BuildMode.Tool.FASHION_TILL:
			lines = [
				tr("The fashion store's till."),
				tr("Place it inside a fashion store. A server stands behind it."),
				tr(
					"Wholly inside the store. Shop staff hired in Staff, and the spot in front clear."
				),
			]
		BuildMode.Tool.FASHION_RAIL:
			lines = [
				tr("A clothes rail. Each one gives two browse spots."),
				tr("Passengers browse from the cells in front of it."),
				tr("Inside a fashion store. Keep the cells in front clear."),
			]
		BuildMode.Tool.BAR_ROOM:
			lines = [
				tr(
					"Marks floor as a bar. Guests stay longer than in a cafe, spend more, and gain most mood."
				),
				tr("Guests order at a bar counter and sit on its stools."),
				tr("At least 3x4, with a bar counter. Shop staff serve at the counter."),
			]
		BuildMode.Tool.RESTAURANT_ROOM:
			lines = [
				tr(
					"Marks floor as a sit-down restaurant. Guests stay the longest and spend the most."
				),
				tr("Guests order at a cafe counter and sit at a dining table or a booth."),
				tr(
					"At least 4x4, with a counter and a table or booth. Shop staff serve at the counter."
				),
			]
		BuildMode.Tool.PLAY_AREA_ROOM:
			lines = [
				tr(
					"Marks floor as a play area. Passengers stay and play for free and their mood rises."
				),
				tr("Drag a rectangle, then add a slide and play blocks. It is self-service."),
				tr("At least 3x4, with a slide and play blocks. No staff."),
			]
		BuildMode.Tool.LOUNGE_ROOM:
			lines = [
				tr(
					"Marks floor as a lounge. Passengers rest on the sofas for free and their mood rises."
				),
				tr("Drag a rectangle, then add a sofa. It is self-service."),
				tr("At least 2x3, with a sofa. No staff."),
			]
		BuildMode.Tool.SHOWER_ROOM:
			lines = [
				tr(
					"Marks floor as a shower room. Passengers pay to wash during a long wait and gain mood."
				),
				tr("Drag a rectangle, then add a shower cubicle. It is self-service."),
				tr("At least 2x2, with a shower cubicle. No staff. Each stay pays you a fee."),
			]
		BuildMode.Tool.BREAK_ROOM:
			lines = [
				tr(
					"Marks floor as a break room. Tired staff rest here during lulls to recover energy."
				),
				tr("Drag a rectangle, then add a bench inside. High prestige speeds up recovery."),
				tr("At least 2x3, with a bench. Staff never leave a busy queue mid-rush."),
			]
		BuildMode.Tool.KIOSK_DISPLAY:
			lines = [
				tr("A shelf unit. Each stand gives the kiosk two browse spots."),
				tr("Passengers browse from the cells in front of it."),
				tr("Inside a kiosk. Keep the cells in front clear."),
			]
		BuildMode.Tool.BELT:
			lines = [
				tr("A baggage belt. It carries checked bags from a check-in desk to a bag room."),
				tr("Drag a line. The belt shapes itself at turns and joins. Belts cannot cross."),
				tr(
					"Start at a check-in desk's back and end in a bag room. A wall in the way blocks it."
				),
			]
		BuildMode.Tool.BAG_ROOM:
			lines = [
				tr("Where checked bags end up. They are loaded onto the plane from here."),
				tr("Drag a rectangle, then run a belt into it. The belt's end piece goes inside."),
				tr(
					"At least 2x2, with a belt end. A bag that arrives after the cutoff misses the plane."
				),
			]
		BuildMode.Tool.CART:
			lines = [
				tr("A baggage cart on wheels."),
				tr(
					"Place one in a bag room so a hired Ramp Agent drives checked bags out to the parked plane."
				),
				tr("Needs a Ramp Agent hired in Staff. Takes 1x2 tiles; no upkeep."),
			]
		BuildMode.Tool.CURB:
			lines = [
				tr(
					"A curb bay on the road outside. Cars and taxis stop here and drop passengers off."
				),
				tr("Click one of the marked spots by the road. Each bay has two berths."),
				tr("Marked spots only. The nearer an entrance, the shorter the walk."),
			]
		BuildMode.Tool.SURFACE_LOT:
			lines = [
				tr("A car park with 12 spaces. A car pays a fee when it parks."),
				tr("Click a marked spot. Passengers walk from the car park to an entrance."),
				tr("Marked spots only. Close it to let it drain before you remove it."),
			]
		BuildMode.Tool.MULTI_STOREY:
			lines = [
				tr(
					"A big car park with 31 spaces. A car pays a higher fee than a surface lot when it parks."
				),
				tr("Click a marked spot. Passengers walk from the car park to an entrance."),
				tr("Marked spots only. Close it to let it drain before you remove it."),
			]
		BuildMode.Tool.LOT_GATE:
			lines = [
				tr("Opens or closes a car park."),
				tr("Click a built car park. A closed one takes no new cars and empties out."),
				tr("A car park can only be removed once no cars are in it."),
			]
		BuildMode.Tool.BUY_LAND:
			lines = [
				tr("Buys a plot of land. You can only build on land you own."),
				tr(
					"Click a highlighted plot. Its price shows on it and rises with each plot you buy."
				),
				tr("A plot next to land you already own."),
			]
		BuildMode.Tool.TRAY_TABLE:
			lines = [
				tr("The tray table of a security lane, where passengers unpack their bags."),
				tr("It stands beside the arch, on the side the lane's parts go."),
				tr("Part of a whole lane: arch, tray table, X-ray belt and pickup table."),
			]
		BuildMode.Tool.XRAY_BELT:
			lines = [
				tr("The X-ray belt of a security lane. Bags ride through it."),
				tr("It stands beside the arch. A lane officer works at it."),
				tr("Part of a whole lane. Needs a security officer hired in Staff."),
			]
		BuildMode.Tool.ARCH:
			lines = [
				tr("The arch of a security lane. Passengers walk through it."),
				tr(
					"Place the arch first and the other parts around it. Its front faces the queue."
				),
				tr(
					"Part of a whole lane. Keep the spot in front and the walls around the lane clear."
				),
			]
		BuildMode.Tool.PICKUP_TABLE:
			lines = [
				tr("The pickup table of a security lane, where passengers collect their bags."),
				tr("It stands past the arch, where cleared passengers leave the lane."),
				tr("Part of a whole lane: arch, tray table, X-ray belt and pickup table."),
			]
		BuildMode.Tool.SEARCH_TABLE:
			lines = [
				tr("An inspection table where officers check flagged carry-on bags."),
				tr("Place it beside the lane's side berth. Optional: the lane works without one."),
				tr("No upkeep. Holds the passenger's tray during bag searches."),
			]
		BuildMode.Tool.CONFISCATION_BIN:
			lines = [
				tr("A clear glass bin showing items taken at the security lane today."),
				tr("Place it next to the search table slot. Resets at midnight."),
				tr("No upkeep. Inspect it to see today's strangest finds."),
			]
		BuildMode.Tool.SECURITY_LANE:
			lines = [
				tr("A complete security lane: tray table, X-ray belt, arch and pickup table."),
				tr("Click once to place all four parts together. Press R to turn it."),
				tr("Needs clear floor for the lane, queue, exit and two officer spots."),
			]
		BuildMode.Tool.BUSH:
			lines = [
				tr("A bush. It calms passengers close to it, a little."),
				tr("Passengers within a cell or so get calm, which becomes mood. Walls block it."),
				tr("No upkeep. It earns nothing."),
			]
		BuildMode.Tool.PLANTER:
			lines = [
				tr("A planter. It calms passengers near it, a little."),
				tr(
					"Passengers within a couple of cells get calm, which becomes mood. Walls block it."
				),
				tr("No upkeep. It earns nothing."),
			]
		BuildMode.Tool.PLANT_POT:
			lines = [
				tr("A large plant pot. It calms passengers near it, a little."),
				tr(
					"Passengers within a couple of cells get calm, which becomes mood. Walls block it."
				),
				tr("No upkeep. It earns nothing."),
			]
		BuildMode.Tool.TREE:
			lines = [
				tr("An indoor tree. It calms the passengers around it."),
				tr("Passengers within a few cells get calm, which becomes mood. Walls block it."),
				tr("No upkeep. It earns nothing."),
			]
		BuildMode.Tool.BENCH:
			lines = [
				tr("A bench. It seats two waiting passengers and calms passengers nearby."),
				tr(
					"Gate passengers sit on it. Calm becomes mood, and a wall between them blocks it."
				),
				tr("No upkeep. It earns nothing."),
			]
		BuildMode.Tool.TREE_BENCH:
			lines = [
				tr("A bench built around a tree. It calms the passengers near it."),
				tr(
					"Passengers within a couple of cells get calm, which becomes mood. Walls block it."
				),
				tr("No upkeep. It earns nothing."),
			]
		BuildMode.Tool.FOUNTAIN:
			lines = [
				tr("A fountain. It calms the passengers around it the most, with a long reach."),
				tr("Passengers within a few cells get calm, which becomes mood. Walls block it."),
				tr("No upkeep. It earns nothing."),
			]
		BuildMode.Tool.STATUE:
			lines = [
				tr("A statue. It calms the passengers around it, with a long reach."),
				tr("Passengers within a few cells get calm, which becomes mood. Walls block it."),
				tr("No upkeep. It earns nothing."),
			]
		BuildMode.Tool.POST:
			lines = [
				tr("A retractable-belt stanchion post. Passengers cannot walk through it."),
				tr(
					"Use stanchions and queue belts to steer a queue. They give a little calm nearby."
				),
				tr("No upkeep. It earns nothing."),
			]
		BuildMode.Tool.CHAIN:
			lines = [
				tr(
					"A queue belt between two stanchions, three cells long. Passengers cannot walk through it."
				),
				tr(
					"Use stanchions and queue belts to steer a queue. They give a little calm nearby."
				),
				tr("No upkeep. It earns nothing."),
			]
		BuildMode.Tool.BIN:
			lines = [
				tr("A bin. Passengers drop litter in it instead of leaving it on the floor."),
				tr(
					"A bin takes litter from visits near it, and a cleaner empties it when it is full."
				),
				tr(
					"A cleaner hired in Staff. It gives no calm, and a bin in view takes a little back."
				),
			]
		BuildMode.Tool.BAR_COUNTER:
			lines = [
				tr("A bar counter, where guests order drinks."),
				tr(
					"Place it inside a bar. A server stands behind it and guests order from the cell in front."
				),
				tr(
					"Wholly inside the bar. Shop staff hired in Staff, and the spot in front clear."
				),
			]
		BuildMode.Tool.GRAB_STALL:
			lines = [
				tr("A grab-and-go stall, where guests buy and walk on."),
				tr("Place on terminal floor. A server hands over the order."),
				tr("Shop staff hired in Staff, and the spot in front clear."),
			]
		BuildMode.Tool.DINING_TABLE:
			lines = [
				tr("A restaurant table with four seats."),
				tr("Place it inside a restaurant. A guest walks from the counter to a free seat."),
				tr("Wholly inside the restaurant, with the cell behind each chair clear."),
			]
		BuildMode.Tool.BOOTH:
			lines = [
				tr("A restaurant booth with four seats."),
				tr("Place it inside a restaurant. A guest walks from the counter to a free seat."),
				tr("Wholly inside the restaurant, with the cell behind each seat clear."),
			]
		BuildMode.Tool.INFO_DESK:
			lines = [
				tr("A staffed desk that helps lost passengers."),
				tr(
					"A stuck passenger nearby walks over, is helped, gains mood and plans its route again."
				),
				tr(
					"Shop staff hired in Staff, or it does nothing. Works on open floor or in a room."
				),
			]
		BuildMode.Tool.INFO_SCREEN:
			lines = [
				tr("An information display."),
				tr("Scenery for now: nothing in the game reacts to it."),
				tr("Costs upkeep every day."),
			]
		BuildMode.Tool.EXCHANGE:
			lines = [
				tr("A currency exchange stand. Passengers change money and pay a small fee."),
				tr("Place on terminal floor. A server stands behind it and changes money."),
				tr(
					"Shop staff hired in Staff, and the spot in front clear. Does not cure boredom."
				),
			]
		BuildMode.Tool.ATM:
			lines = [
				tr("A cash machine. One passenger uses it at a time and pays a small fee."),
				tr("Place on terminal floor. The passenger uses it from the cell in front."),
				tr("Keep the spot in front clear. No staff, no upkeep, and does not cure boredom."),
			]
		BuildMode.Tool.PHARMACY_COUNTER:
			lines = [
				tr("The pharmacy counter, with a till."),
				tr("Place it inside a pharmacy. A server stands behind it."),
				tr(
					"Wholly inside the pharmacy. Shop staff hired in Staff, and the spot in front clear."
				),
			]
		BuildMode.Tool.PHARMACY_SHELF:
			lines = [
				tr("A pharmacy shelf. Each one gives one browse spot."),
				tr("Passengers browse from the cell in front of it."),
				tr("Inside a pharmacy. Keep the cells in front clear."),
			]
		BuildMode.Tool.SHOWER:
			lines = [
				tr("A shower cubicle. One passenger uses it at a time and pays a fee."),
				tr("Place it inside a shower room. The passenger steps in from the cell in front."),
				tr("Keep the spot in front clear. No upkeep."),
			]
		BuildMode.Tool.NAP_POD:
			lines = [
				tr("A nap pod. One passenger uses it at a time and pays a fee."),
				tr(
					"Place on terminal floor. The passenger sits and leans back during a long wait."
				),
				tr("Keep the spot in front clear. No staff and no upkeep."),
			]
		BuildMode.Tool.SOFA:
			lines = [
				tr("A two-seat sofa. Lounge guests rest on it."),
				tr("Place it inside a lounge. Each sofa gives two seats."),
				tr("No upkeep. The lounge is free to use."),
			]
		BuildMode.Tool.ARMCHAIR:
			lines = [
				tr("A single armchair."),
				tr(
					"A passenger can sit on it, but a lounge needs a sofa. The armchair does not count."
				),
				tr("No upkeep. It earns nothing."),
			]
		BuildMode.Tool.WORK_DESK:
			lines = [
				tr("A work desk."),
				tr("Scenery for now: nothing in the game reacts to it."),
				tr("No upkeep. It earns nothing."),
			]
		BuildMode.Tool.PLAY_BLOCKS:
			lines = [
				tr("Play blocks for children."),
				tr("Place them inside a play area. A play area needs them and a slide."),
				tr("No upkeep. The play area is free to use."),
			]
		BuildMode.Tool.PLAY_SLIDE:
			lines = [
				tr("A play slide. Children use it from the front."),
				tr("Place it inside a play area. Each slide gives two play spots."),
				tr("No upkeep. The play area is free to use."),
			]
		BuildMode.Tool.PRIZE_PODIUM:
			lines = [
				tr(
					"A prize car on a podium. Passengers near it spend a bit more in shops and food rooms."
				),
				tr("Waiting passengers who see it lose boredom. A second podium does not stack."),
				tr("Costs upkeep every day. A plain wall blocks the view."),
			]
		BuildMode.Tool.AWARD_TROPHY:
			lines = [
				tr("An Annual Airport Awards trophy earned for airport excellence."),
				tr("Place it inside any room to add +30 Room Prestige points."),
				tr("Free to place up to the number of trophies earned. No upkeep."),
			]
	return lines
