class_name FurnitureTools
extends RefCounted
## The build tools for the furniture ids of Furniture 4/4 F4-1 (decisions
## all-11-exported-decor-models-are-placeable-plants-trees-foun and furniture-
## set-modelled-on-copenhagen-airport-decor-calms-pas): decor, the food and
## services kit and the activities kit. Each is a plain object tool, placed and
## removed like a cafe table. Most are objects only, with no room type; the
## pharmacy counter and shelf are what a pharmacy room (F4-5, RoomTypes) needs
## to be ready, and the exchange counter and the ATM what an exchange or ATM
## room (F4-5b) needs. BuildMode holds the Tool enum and answers tool_object()
## from these tables, and BuildMenu shows the cards (PAGES, the pharmacy's
## Stores page and the Money page) after its own.

## Tool -> catalog id.
const OBJECTS := {
	BuildMode.Tool.BUSH: &"bush",
	BuildMode.Tool.PLANTER: &"plant_pot_1a",
	BuildMode.Tool.PLANT_POT: &"plant_pot_2a",
	BuildMode.Tool.TREE: &"tree_indoor",
	BuildMode.Tool.BENCH: &"bench_1a",
	BuildMode.Tool.TREE_BENCH: &"bench_2a_indoor",
	BuildMode.Tool.FOUNTAIN: &"fountain_indoor",
	BuildMode.Tool.STATUE: &"statue_indoor",
	BuildMode.Tool.POST: &"metal_pole",
	BuildMode.Tool.CHAIN: &"metal_pole_chain",
	BuildMode.Tool.BIN: &"trash_can",
	BuildMode.Tool.BAR_COUNTER: &"bar_counter",
	BuildMode.Tool.GRAB_STALL: &"grab_and_go_stall",
	BuildMode.Tool.DINING_TABLE: &"restaurant_table",
	BuildMode.Tool.BOOTH: &"restaurant_booth",
	BuildMode.Tool.INFO_DESK: &"info_desk",
	BuildMode.Tool.INFO_SCREEN: &"info_screen",
	BuildMode.Tool.EXCHANGE: &"currency_exchange",
	BuildMode.Tool.ATM: &"atm",
	BuildMode.Tool.PHARMACY_COUNTER: &"pharmacy_counter",
	BuildMode.Tool.PHARMACY_SHELF: &"pharmacy_shelf",
	BuildMode.Tool.SHOWER: &"shower_cubicle",
	BuildMode.Tool.NAP_POD: &"nap_pod",
	BuildMode.Tool.SOFA: &"lounge_sofa",
	BuildMode.Tool.ARMCHAIR: &"lounge_armchair",
	BuildMode.Tool.WORK_DESK: &"work_desk",
	BuildMode.Tool.PLAY_BLOCKS: &"play_blocks",
	BuildMode.Tool.PLAY_SLIDE: &"play_slide",
	BuildMode.Tool.PRIZE_PODIUM: &"prize_podium",
}

## The cards, as BuildMenu.ITEMS: [name, thumbnail, size text, hover card
## text]. The thumbnail
## is the catalog id (render_kit_thumbnails.py); the size comes from the
## catalog, so the text is empty. A name has to fit a card's 100 px.
const ITEMS := {
	BuildMode.Tool.BUSH:
	[
		"Bush",
		"bush",
		"",
		[
			"A bush. It calms passengers close to it, a little.",
			"Passengers within a cell or so get calm, which becomes mood. Walls block it.",
			"No upkeep. It earns nothing."
		]
	],
	BuildMode.Tool.PLANTER:
	[
		"Planter",
		"plant_pot_1a",
		"",
		[
			"A planter. It calms passengers near it, a little.",
			"Passengers within a couple of cells get calm, which becomes mood. Walls block it.",
			"No upkeep. It earns nothing."
		]
	],
	BuildMode.Tool.PLANT_POT:
	[
		"Plant pot",
		"plant_pot_2a",
		"",
		[
			"A large plant pot. It calms passengers near it, a little.",
			"Passengers within a couple of cells get calm, which becomes mood. Walls block it.",
			"No upkeep. It earns nothing."
		]
	],
	BuildMode.Tool.TREE:
	[
		"Tree",
		"tree_indoor",
		"",
		[
			"An indoor tree. It calms the passengers around it.",
			"Passengers within a few cells get calm, which becomes mood. Walls block it.",
			"No upkeep. It earns nothing."
		]
	],
	BuildMode.Tool.BENCH:
	[
		"Bench",
		"bench_1a",
		"",
		[
			"A bench. It calms passengers right next to it, a little.",
			"Passengers do not sit on it. Calm becomes mood, and a wall between them blocks it.",
			"No upkeep. It earns nothing."
		]
	],
	BuildMode.Tool.TREE_BENCH:
	[
		"Tree bench",
		"bench_2a_indoor",
		"",
		[
			"A bench built around a tree. It calms the passengers near it.",
			"Passengers within a couple of cells get calm, which becomes mood. Walls block it.",
			"No upkeep. It earns nothing."
		]
	],
	BuildMode.Tool.FOUNTAIN:
	[
		"Fountain",
		"fountain_indoor",
		"",
		[
			"A fountain. It calms the passengers around it the most, with a long reach.",
			"Passengers within a few cells get calm, which becomes mood. Walls block it.",
			"No upkeep. It earns nothing."
		]
	],
	BuildMode.Tool.STATUE:
	[
		"Statue",
		"statue_indoor",
		"",
		[
			"A statue. It calms the passengers around it, with a long reach.",
			"Passengers within a few cells get calm, which becomes mood. Walls block it.",
			"No upkeep. It earns nothing."
		]
	],
	BuildMode.Tool.POST:
	[
		"Post",
		"metal_pole",
		"",
		[
			"A metal post. Passengers cannot walk through it.",
			"Use posts and chains to steer a queue. They give no calm.",
			"No upkeep. It earns nothing."
		]
	],
	BuildMode.Tool.CHAIN:
	[
		"Chain",
		"metal_pole_chain",
		"",
		[
			"A chain between two posts, three cells long. Passengers cannot walk through it.",
			"Use posts and chains to steer a queue. They give no calm.",
			"No upkeep. It earns nothing."
		]
	],
	BuildMode.Tool.BIN:
	[
		"Bin",
		"trash_can",
		"",
		[
			"A bin. Passengers drop litter in it instead of leaving it on the floor.",
			"A bin takes litter from visits near it, and a cleaner empties it when it is full.",
			"A cleaner hired in Staff. It gives no calm, and a bin in view takes a little back."
		]
	],
	BuildMode.Tool.BAR_COUNTER:
	[
		"Bar counter",
		"bar_counter",
		"",
		[
			"A bar counter for show.",
			"A bar room works with the cafe counter and table, not with this piece.",
			"No upkeep. It earns nothing."
		]
	],
	BuildMode.Tool.GRAB_STALL:
	[
		"Grab stall",
		"grab_and_go_stall",
		"",
		[
			"A grab-and-go stall for show.",
			"A grab-and-go room works with the cafe counter, not with this piece.",
			"No upkeep. It earns nothing."
		]
	],
	BuildMode.Tool.DINING_TABLE:
	[
		"Dining table",
		"restaurant_table",
		"",
		[
			"A restaurant table for show.",
			"A restaurant room works with the cafe counter and table, not with this piece.",
			"No upkeep. It earns nothing."
		]
	],
	BuildMode.Tool.BOOTH:
	[
		"Booth",
		"restaurant_booth",
		"",
		[
			"A restaurant booth for show.",
			"A restaurant room works with the cafe counter and table, not with this piece.",
			"No upkeep. It earns nothing."
		]
	],
	BuildMode.Tool.INFO_DESK:
	[
		"Info desk",
		"info_desk",
		"",
		[
			"A staffed desk that helps lost passengers.",
			"A stuck passenger nearby walks over, is helped, gains mood and plans its route again.",
			"Shop staff hired in Staff, or it does nothing. Works on open floor or in a room."
		]
	],
	BuildMode.Tool.INFO_SCREEN:
	[
		"Info screen",
		"info_screen",
		"",
		[
			"An information display.",
			"Scenery for now: nothing in the game reacts to it.",
			"Costs upkeep every day."
		]
	],
	# On the Money page beside their rooms ("Exchange", "ATM"), as the pharmacy
	BuildMode.Tool.EXCHANGE:
	[
		# counter is beside the Pharmacy card.
		"Counter",
		"currency_exchange",
		"",
		[
			"The currency exchange counter.",
			"Place it inside an exchange room. A server stands behind it and changes money.",
			"Wholly inside the room. Shop staff hired in Staff, and the spot in front clear."
		]
	],
	BuildMode.Tool.ATM:
	[
		"Cash machine",
		"atm",
		"",
		[
			"A cash machine. One passenger uses it at a time and pays a small fee.",
			"Place it inside an ATM room. The passenger uses it from the cell in front.",
			"Keep the spot in front clear. No staff and no upkeep."
		]
	],
	BuildMode.Tool.PHARMACY_COUNTER:
	[
		"Counter",
		"pharmacy_counter",
		"",
		[
			"The pharmacy counter, with a till.",
			"Place it inside a pharmacy. A server stands behind it.",
			"Wholly inside the pharmacy. Shop staff hired in Staff, and the spot in front clear."
		]
	],
	BuildMode.Tool.PHARMACY_SHELF:
	[
		"Shelf",
		"pharmacy_shelf",
		"",
		[
			"A pharmacy shelf. Each one gives one browse spot.",
			"Passengers browse from the cell in front of it.",
			"Inside a pharmacy. Keep the cells in front clear."
		]
	],
	BuildMode.Tool.SHOWER:
	[
		"Shower",
		"shower_cubicle",
		"",
		[
			"A shower cubicle. One passenger uses it at a time and pays a fee.",
			"Place it inside a shower room. The passenger steps in from the cell in front.",
			"Keep the spot in front clear. No upkeep."
		]
	],
	BuildMode.Tool.NAP_POD:
	[
		"Nap pod",
		"nap_pod",
		"",
		[
			"A nap pod. One passenger uses it at a time and pays a fee.",
			"Place it inside a nap pod room. The passenger sits and leans back.",
			"Keep the spot in front clear. No upkeep."
		]
	],
	BuildMode.Tool.SOFA:
	[
		"Sofa",
		"lounge_sofa",
		"",
		[
			"A two-seat sofa. Lounge guests rest on it.",
			"Place it inside a lounge. Each sofa gives two seats.",
			"No upkeep. The lounge is free to use."
		]
	],
	BuildMode.Tool.ARMCHAIR:
	[
		"Armchair",
		"lounge_armchair",
		"",
		[
			"A single armchair.",
			"A passenger can sit on it, but a lounge needs a sofa. The armchair does not count.",
			"No upkeep. It earns nothing."
		]
	],
	BuildMode.Tool.WORK_DESK:
	[
		"Work desk",
		"work_desk",
		"",
		[
			"A work desk.",
			"Scenery for now: nothing in the game reacts to it.",
			"No upkeep. It earns nothing."
		]
	],
	BuildMode.Tool.PLAY_BLOCKS:
	[
		"Play blocks",
		"play_blocks",
		"",
		[
			"Play blocks for children.",
			"Place them inside a play area. A play area needs them and a slide.",
			"No upkeep. The play area is free to use."
		]
	],
	BuildMode.Tool.PLAY_SLIDE:
	[
		"Play slide",
		"play_slide",
		"",
		[
			"A play slide. Children use it from the front.",
			"Place it inside a play area. Each slide gives two play spots.",
			"No upkeep. The play area is free to use."
		]
	],
	BuildMode.Tool.PRIZE_PODIUM:
	[
		"Prize podium",
		"prize_podium",
		"",
		[
			"A prize car on a podium. Passengers near it spend a bit more in shops and food rooms.",
			"Waiting passengers who see it lose boredom. A second podium does not stack.",
			"Costs upkeep every day. A plain wall blocks the view."
		]
	],
}

## Cards that show what the placed piece costs to run per game day.
const RUNNING_COSTS := {
	BuildMode.Tool.INFO_SCREEN: PriceTable.INFO_SCREEN_UPKEEP,
	BuildMode.Tool.PRIZE_PODIUM: PriceTable.PRIZE_CAR_UPKEEP,
}

## The pages of the Furniture category (BuildMenu.CATEGORIES names them), each
## with at most four cards: a tray holds four cards and the Next
## column in BuildMenu.COLUMN_W, and no more. The pharmacy counter and shelf
## are on the pharmacy's Stores page (BuildMenu.CATEGORIES), beside its room,
## and the exchange counter and the ATM on the Money page, beside theirs.
const PAGES := [
	[BuildMode.Tool.BUSH, BuildMode.Tool.PLANTER, BuildMode.Tool.PLANT_POT, BuildMode.Tool.TREE],
	[
		BuildMode.Tool.BENCH,
		BuildMode.Tool.TREE_BENCH,
		BuildMode.Tool.FOUNTAIN,
		BuildMode.Tool.STATUE
	],
	[BuildMode.Tool.POST, BuildMode.Tool.CHAIN, BuildMode.Tool.BIN],
	[
		BuildMode.Tool.BAR_COUNTER,
		BuildMode.Tool.GRAB_STALL,
		BuildMode.Tool.DINING_TABLE,
		BuildMode.Tool.BOOTH,
	],
	[BuildMode.Tool.INFO_DESK, BuildMode.Tool.INFO_SCREEN],
	[BuildMode.Tool.SHOWER, BuildMode.Tool.NAP_POD],
	[BuildMode.Tool.SOFA, BuildMode.Tool.ARMCHAIR, BuildMode.Tool.WORK_DESK],
	[BuildMode.Tool.PLAY_BLOCKS, BuildMode.Tool.PLAY_SLIDE, BuildMode.Tool.PRIZE_PODIUM],
]
