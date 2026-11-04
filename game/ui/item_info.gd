class_name ItemInfo
extends RefCounted
## The hover card text of every build tray item (decision build-menu-items-show-
## a-hover-card-with-a-description): [what it is, how it works, what it needs or
## costs to run], plain sentences checked against the sim and build rules.
## BuildMenu gives it to the item's card (ItemCardButton). It lives here, keyed
## by tool, so build_menu.gd stays under the gdlint line cap; a test checks that
## every tray item has an entry and every entry an item.

const TEXT := {
	BuildMode.Tool.FLOOR:
	[
		"Floor tile. Passengers can only walk and stand on floor.",
		"Drag a rectangle to lay many tiles at once. Everything else is built on floor.",
		"Land you own. Removing a tile refunds half."
	],
	BuildMode.Tool.WALL:
	[
		"A wall along a tile edge. Passengers cannot cross it and it blocks the view.",
		"Drag along a line to build a row. Walls close in the terminal and its rooms.",
		"One wall per tile edge. Removing it refunds half."
	],
	BuildMode.Tool.GLASS:
	[
		"A glass wall. Passengers cannot cross it, but it lets the view through.",
		"Drag along a line like a wall. Screens and decor can be seen through glass.",
		"Costs more than a plain wall. One per tile edge."
	],
	BuildMode.Tool.DOOR:
	[
		"A door in a wall. Passengers walk through it.",
		"Click a wall edge to put a door in the wall.",
		"A plain wall on each side of it."
	],
	BuildMode.Tool.ENTRANCE:
	[
		"The way into the terminal. Passengers come in here from the road and car parks.",
		"Place it on the outer edge of the terminal, facing in.",
		"The outside edge with no floor behind it. Keep the spot in front clear."
	],
	BuildMode.Tool.EXIT:
	[
		"The way out to the planes. Passengers leave the terminal here to board.",
		"Place it on the outer edge. A gate desk links to an exit that faces north (the planes).",
		"The outside edge with no floor behind it. Keep the spot in front clear."
	],
	BuildMode.Tool.DESK:
	[
		"Where passengers check in and hand over a bag.",
		"A check-in agent works behind it. A belt from its back edge takes bags to a bag room.",
		"An agent hired in Staff, or it stays closed. Keep the spot behind and in front clear."
	],
	BuildMode.Tool.SCANNER:
	[
		"A basic security scanner. Passengers walk through it to be screened.",
		"A security officer works beside it. A full lane is faster but costs more.",
		"An officer hired in Staff, or it stays closed. Keep its staff spot and way in clear."
	],
	BuildMode.Tool.SEATS:
	[
		"A row of seats. Passengers wait here for their flight and their mood recovers.",
		"Place it near the gate and turn it. Waiting passengers sit on it.",
		"No staff and no upkeep. Add enough seats for the passengers waiting."
	],
	BuildMode.Tool.GATE_DESK:
	[
		"Makes a gate. It links to the nearest free north-facing exit; the plane parks out from it.",
		"Each flight is given a gate. A gate takes the next free letter, starting at A.",
		"Within 4 cells of a free north-facing exit, with room for the plane. No staff needed."
	],
	BuildMode.Tool.SCREEN:
	[
		"A floor screen that entertains passengers waiting in front of it.",
		"It covers a fan of floor up to 5 rows ahead. A plain wall blocks it, glass does not.",
		"Costs upkeep every day, inside a room or not."
	],
	BuildMode.Tool.CAFE_ROOM:
	[
		"Marks floor as a cafe. Hungry passengers eat and drink here and their mood rises.",
		"Drag a rectangle, then add a counter and a table. Guests order, then sit at the table.",
		"At least 3x3, with a counter and a table. Needs shop staff, or the counter stays closed."
	],
	BuildMode.Tool.COUNTER:
	[
		"The cafe counter, where guests order.",
		"Place it inside a cafe, bar, restaurant or grab-and-go stall. A server stands there.",
		"Wholly inside the room. Shop staff hired in Staff, and the spot in front clear."
	],
	BuildMode.Tool.TABLE:
	[
		"A table with a seat at each end. Cafe guests sit here to eat.",
		"It seats two. A guest walks from the counter to a free seat.",
		"Inside a cafe, bar or restaurant. A grab-and-go stall needs none."
	],
	BuildMode.Tool.TOILET_ROOM:
	[
		"Marks floor as a toilet. Passengers who need one queue and use a stall.",
		"Drag a rectangle, then add a stall and a sink inside.",
		"At least 2x3, with a stall and a sink. Each stall costs upkeep every day when ready."
	],
	BuildMode.Tool.TOILET_STALL:
	[
		"One toilet stall. One passenger uses it at a time.",
		"Place it inside a toilet room. A passenger walks in from the cell in front.",
		"Keep the spot in front clear. Costs upkeep every day once its room is ready."
	],
	BuildMode.Tool.TOILET_SINK:
	[
		"A sink. A toilet room is not ready without one.",
		"Place it inside a toilet room.",
		"Keep the spot in front clear. No upkeep of its own."
	],
	BuildMode.Tool.KIOSK_ROOM:
	[
		"Marks floor as a kiosk, a small shop. Bored passengers browse here and pay.",
		"Drag a rectangle, then add a counter and display stands. Guests browse at the stands.",
		"At least 3x3, with a counter and a display stand. Shop staff serve at the counter."
	],
	BuildMode.Tool.KIOSK_COUNTER:
	[
		"The kiosk's counter, with a till.",
		"Place it inside a kiosk. A server stands behind it.",
		"Wholly inside the kiosk. Shop staff hired in Staff, and the spot in front clear."
	],
	BuildMode.Tool.PHARMACY_ROOM:
	[
		"Marks floor as a pharmacy. Passengers browse and buy here.",
		"Drag a rectangle, then add a counter and a shelf. Passengers browse at the shelf.",
		"At least 3x3, with a counter and a shelf. Shop staff serve at the counter."
	],
	BuildMode.Tool.DUTY_FREE_ROOM:
	[
		"Marks floor as a duty free shop. Passengers browse and spend more than in a kiosk.",
		"Drag a rectangle, then add a till and shelves. Passengers browse at the shelves.",
		"At least 3x4, with a till and a shelf. Shop staff serve at the till."
	],
	BuildMode.Tool.DUTY_FREE_TILL:
	[
		"The duty free shop's till.",
		"Place it inside a duty free shop. A server stands behind it.",
		"Wholly inside the shop. Shop staff hired in Staff, and the spot in front clear."
	],
	BuildMode.Tool.DUTY_FREE_SHELF:
	[
		"A duty free shelf. Each one gives two browse spots.",
		"Passengers browse from the cells in front of it.",
		"Inside a duty free shop. Keep the cells in front clear."
	],
	BuildMode.Tool.FASHION_ROOM:
	[
		"Marks floor as a fashion store. Passengers browse and spend more than in a kiosk.",
		"Drag a rectangle, then add a till and clothes rails. Passengers browse at the rails.",
		"At least 3x4, with a till and a clothes rail. Shop staff serve at the till."
	],
	BuildMode.Tool.FASHION_TILL:
	[
		"The fashion store's till.",
		"Place it inside a fashion store. A server stands behind it.",
		"Wholly inside the store. Shop staff hired in Staff, and the spot in front clear."
	],
	BuildMode.Tool.FASHION_RAIL:
	[
		"A clothes rail. Each one gives two browse spots.",
		"Passengers browse from the cells in front of it.",
		"Inside a fashion store. Keep the cells in front clear."
	],
	BuildMode.Tool.EXCHANGE_ROOM:
	[
		"Marks floor as a currency exchange. Passengers change money and pay a small fee.",
		"Drag a rectangle, then add a counter. A server works it.",
		"At least 2x3, with a counter and shop staff. A visit does not cure boredom."
	],
	BuildMode.Tool.ATM_ROOM:
	[
		"Marks floor as an ATM room. Passengers take out cash and pay a small fee.",
		"Drag a rectangle, then add an ATM. It is self-service.",
		"At least 1x2, with an ATM. No staff. A visit does not cure boredom."
	],
	BuildMode.Tool.BAR_ROOM:
	[
		"Marks floor as a bar. Guests stay longer than in a cafe, spend more, and gain most mood.",
		"Guests order at a bar counter or a cafe counter and sit at a cafe table.",
		"At least 3x4, with a counter and a table. Shop staff serve at the counter."
	],
	BuildMode.Tool.RESTAURANT_ROOM:
	[
		"Marks floor as a sit-down restaurant. Guests stay the longest and spend the most.",
		"Guests order at a cafe counter and sit at a dining table, a booth or a cafe table.",
		"At least 4x4, with a counter and a table or booth. Shop staff serve at the counter."
	],
	BuildMode.Tool.STALL_ROOM:
	[
		"Marks floor as a grab-and-go stall. Guests buy, pay and walk on, with no seat.",
		"It needs only a grab stall or a cafe counter. A server hands over the order.",
		"At least 3x3, with a counter. Shop staff serve. It earns the least of the food rooms."
	],
	BuildMode.Tool.PLAY_AREA_ROOM:
	[
		"Marks floor as a play area. Passengers stay and play for free and their mood rises.",
		"Drag a rectangle, then add a slide and play blocks. It is self-service.",
		"At least 3x4, with a slide and play blocks. No staff."
	],
	BuildMode.Tool.LOUNGE_ROOM:
	[
		"Marks floor as a lounge. Passengers rest on the sofas for free and their mood rises.",
		"Drag a rectangle, then add a sofa. It is self-service.",
		"At least 2x3, with a sofa. No staff."
	],
	BuildMode.Tool.SHOWER_ROOM:
	[
		"Marks floor as a shower room. Passengers pay to wash during a long wait and gain mood.",
		"Drag a rectangle, then add a shower cubicle. It is self-service.",
		"At least 2x2, with a shower cubicle. No staff. Each stay pays you a fee."
	],
	BuildMode.Tool.NAP_POD_ROOM:
	[
		"Marks floor as a nap pod room. Passengers pay to rest during a long wait and gain mood.",
		"Drag a rectangle, then add a nap pod. It is self-service.",
		"At least 2x2, with a nap pod. No staff. Each stay pays you a fee."
	],
	BuildMode.Tool.KIOSK_DISPLAY:
	[
		"A shelf unit. Each stand gives the kiosk two browse spots.",
		"Passengers browse from the cells in front of it.",
		"Inside a kiosk. Keep the cells in front clear."
	],
	BuildMode.Tool.BELT:
	[
		"A baggage belt. It carries checked bags from a check-in desk to a bag room.",
		"Drag a line. The belt shapes itself at turns and joins. Belts cannot cross.",
		"Start at a check-in desk's back and end in a bag room. A wall in the way blocks it."
	],
	BuildMode.Tool.BAG_ROOM:
	[
		"Where checked bags end up. They are loaded onto the plane from here.",
		"Drag a rectangle, then run a belt into it. The belt's end piece goes inside.",
		"At least 2x2, with a belt end. A bag that arrives after the cutoff misses the plane."
	],
	BuildMode.Tool.CART:
	[
		"A baggage cart on wheels.",
		"It is scenery. Bags move the same without it.",
		"Takes 1x2 tiles. No upkeep."
	],
	BuildMode.Tool.CURB:
	[
		"A curb bay on the road outside. Cars and taxis stop here and drop passengers off.",
		"Click one of the marked spots by the road. Each bay has two berths.",
		"Marked spots only. The nearer an entrance, the shorter the walk."
	],
	BuildMode.Tool.SURFACE_LOT:
	[
		"A car park with 12 spaces. A car pays a fee when it parks.",
		"Click a marked spot. Passengers walk from the car park to an entrance.",
		"Marked spots only. Close it to let it drain before you remove it."
	],
	BuildMode.Tool.MULTI_STOREY:
	[
		"A big car park with 31 spaces. A car pays a fee when it parks.",
		"Click a marked spot. Passengers walk from the car park to an entrance.",
		"Marked spots only. Close it to let it drain before you remove it."
	],
	BuildMode.Tool.LOT_GATE:
	[
		"Opens or closes a car park.",
		"Click a built car park. A closed one takes no new cars and empties out.",
		"A car park can only be removed once no cars are in it."
	],
	BuildMode.Tool.BUY_LAND:
	[
		"Buys a plot of land. You can only build on land you own.",
		"Click a highlighted plot. Its price shows on it and rises with each plot you buy.",
		"A plot next to land you already own."
	],
	BuildMode.Tool.TRAY_TABLE:
	[
		"The tray table of a security lane, where passengers unpack their bags.",
		"It stands beside the arch, on the side the lane's parts go.",
		"Part of a whole lane: arch, tray table, X-ray belt and pickup table."
	],
	BuildMode.Tool.XRAY_BELT:
	[
		"The X-ray belt of a security lane. Bags ride through it.",
		"It stands beside the arch. A lane officer works at it.",
		"Part of a whole lane. Needs a security officer hired in Staff."
	],
	BuildMode.Tool.ARCH:
	[
		"The arch of a security lane. Passengers walk through it.",
		"Place the arch first and the other parts around it. Its front faces the queue.",
		"Part of a whole lane. Keep the spot in front and the walls around the lane clear."
	],
	BuildMode.Tool.PICKUP_TABLE:
	[
		"The pickup table of a security lane, where passengers collect their bags.",
		"It stands past the arch, where cleared passengers leave the lane.",
		"Part of a whole lane: arch, tray table, X-ray belt and pickup table."
	],
	BuildMode.Tool.BUSH:
	[
		"A bush. It calms passengers close to it, a little.",
		"Passengers within a cell or so get calm, which becomes mood. Walls block it.",
		"No upkeep. It earns nothing."
	],
	BuildMode.Tool.PLANTER:
	[
		"A planter. It calms passengers near it, a little.",
		"Passengers within a couple of cells get calm, which becomes mood. Walls block it.",
		"No upkeep. It earns nothing."
	],
	BuildMode.Tool.PLANT_POT:
	[
		"A large plant pot. It calms passengers near it, a little.",
		"Passengers within a couple of cells get calm, which becomes mood. Walls block it.",
		"No upkeep. It earns nothing."
	],
	BuildMode.Tool.TREE:
	[
		"An indoor tree. It calms the passengers around it.",
		"Passengers within a few cells get calm, which becomes mood. Walls block it.",
		"No upkeep. It earns nothing."
	],
	BuildMode.Tool.BENCH:
	[
		"A bench. It calms passengers right next to it, a little.",
		"Passengers do not sit on it. Calm becomes mood, and a wall between them blocks it.",
		"No upkeep. It earns nothing."
	],
	BuildMode.Tool.TREE_BENCH:
	[
		"A bench built around a tree. It calms the passengers near it.",
		"Passengers within a couple of cells get calm, which becomes mood. Walls block it.",
		"No upkeep. It earns nothing."
	],
	BuildMode.Tool.FOUNTAIN:
	[
		"A fountain. It calms the passengers around it the most, with a long reach.",
		"Passengers within a few cells get calm, which becomes mood. Walls block it.",
		"No upkeep. It earns nothing."
	],
	BuildMode.Tool.STATUE:
	[
		"A statue. It calms the passengers around it, with a long reach.",
		"Passengers within a few cells get calm, which becomes mood. Walls block it.",
		"No upkeep. It earns nothing."
	],
	BuildMode.Tool.POST:
	[
		"A metal post. Passengers cannot walk through it.",
		"Use posts and chains to steer a queue. They give no calm.",
		"No upkeep. It earns nothing."
	],
	BuildMode.Tool.CHAIN:
	[
		"A chain between two posts, three cells long. Passengers cannot walk through it.",
		"Use posts and chains to steer a queue. They give no calm.",
		"No upkeep. It earns nothing."
	],
	BuildMode.Tool.BIN:
	[
		"A bin. Passengers drop litter in it instead of leaving it on the floor.",
		"A bin takes litter from visits near it, and a cleaner empties it when it is full.",
		"A cleaner hired in Staff. It gives no calm, and a bin in view takes a little back."
	],
	BuildMode.Tool.BAR_COUNTER:
	[
		"A bar counter, where guests order drinks.",
		"Place it inside a bar. A server stands behind it and guests order from the cell in front.",
		"Wholly inside the bar. Shop staff hired in Staff, and the spot in front clear."
	],
	BuildMode.Tool.GRAB_STALL:
	[
		"A grab-and-go stall, where guests buy and walk on.",
		"Place it inside a grab-and-go room. A server hands over the order.",
		"Wholly inside the room. Shop staff hired in Staff, and the spot in front clear."
	],
	BuildMode.Tool.DINING_TABLE:
	[
		"A restaurant table with four seats.",
		"Place it inside a restaurant. A guest walks from the counter to a free seat.",
		"Wholly inside the restaurant, with the cell behind each chair clear."
	],
	BuildMode.Tool.BOOTH:
	[
		"A restaurant booth with four seats.",
		"Place it inside a restaurant. A guest walks from the counter to a free seat.",
		"Wholly inside the restaurant, with the cell behind each seat clear."
	],
	BuildMode.Tool.INFO_DESK:
	[
		"A staffed desk that helps lost passengers.",
		"A stuck passenger nearby walks over, is helped, gains mood and plans its route again.",
		"Shop staff hired in Staff, or it does nothing. Works on open floor or in a room."
	],
	BuildMode.Tool.INFO_SCREEN:
	[
		"An information display.",
		"Scenery for now: nothing in the game reacts to it.",
		"Costs upkeep every day."
	],
	BuildMode.Tool.EXCHANGE:
	[
		"The currency exchange counter.",
		"Place it inside an exchange room. A server stands behind it and changes money.",
		"Wholly inside the room. Shop staff hired in Staff, and the spot in front clear."
	],
	BuildMode.Tool.ATM:
	[
		"A cash machine. One passenger uses it at a time and pays a small fee.",
		"Place it inside an ATM room. The passenger uses it from the cell in front.",
		"Keep the spot in front clear. No staff and no upkeep."
	],
	BuildMode.Tool.PHARMACY_COUNTER:
	[
		"The pharmacy counter, with a till.",
		"Place it inside a pharmacy. A server stands behind it.",
		"Wholly inside the pharmacy. Shop staff hired in Staff, and the spot in front clear."
	],
	BuildMode.Tool.PHARMACY_SHELF:
	[
		"A pharmacy shelf. Each one gives one browse spot.",
		"Passengers browse from the cell in front of it.",
		"Inside a pharmacy. Keep the cells in front clear."
	],
	BuildMode.Tool.SHOWER:
	[
		"A shower cubicle. One passenger uses it at a time and pays a fee.",
		"Place it inside a shower room. The passenger steps in from the cell in front.",
		"Keep the spot in front clear. No upkeep."
	],
	BuildMode.Tool.NAP_POD:
	[
		"A nap pod. One passenger uses it at a time and pays a fee.",
		"Place it inside a nap pod room. The passenger sits and leans back.",
		"Keep the spot in front clear. No upkeep."
	],
	BuildMode.Tool.SOFA:
	[
		"A two-seat sofa. Lounge guests rest on it.",
		"Place it inside a lounge. Each sofa gives two seats.",
		"No upkeep. The lounge is free to use."
	],
	BuildMode.Tool.ARMCHAIR:
	[
		"A single armchair.",
		"A passenger can sit on it, but a lounge needs a sofa. The armchair does not count.",
		"No upkeep. It earns nothing."
	],
	BuildMode.Tool.WORK_DESK:
	[
		"A work desk.",
		"Scenery for now: nothing in the game reacts to it.",
		"No upkeep. It earns nothing."
	],
	BuildMode.Tool.PLAY_BLOCKS:
	[
		"Play blocks for children.",
		"Place them inside a play area. A play area needs them and a slide.",
		"No upkeep. The play area is free to use."
	],
	BuildMode.Tool.PLAY_SLIDE:
	[
		"A play slide. Children use it from the front.",
		"Place it inside a play area. Each slide gives two play spots.",
		"No upkeep. The play area is free to use."
	],
	BuildMode.Tool.PRIZE_PODIUM:
	[
		"A prize car on a podium. Passengers near it spend a bit more in shops and food rooms.",
		"Waiting passengers who see it lose boredom. A second podium does not stack.",
		"Costs upkeep every day. A plain wall blocks the view."
	],
}


## The three texts of a tool's hover card, or an empty array for a tool with none.
static func of(tool: BuildMode.Tool) -> Array:
	return TEXT.get(tool, [])
