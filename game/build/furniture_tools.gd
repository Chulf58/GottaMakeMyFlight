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

## The cards, as BuildMenu.ITEMS: [name, thumbnail, size text]. The thumbnail
## is the catalog id (render_kit_thumbnails.py); the size comes from the
## catalog, so the text is empty. A name has to fit a card's 100 px.
const ITEMS := {
	BuildMode.Tool.BUSH: ["Bush", "bush", ""],
	BuildMode.Tool.PLANTER: ["Planter", "plant_pot_1a", ""],
	BuildMode.Tool.PLANT_POT: ["Plant pot", "plant_pot_2a", ""],
	BuildMode.Tool.TREE: ["Tree", "tree_indoor", ""],
	BuildMode.Tool.BENCH: ["Bench", "bench_1a", ""],
	BuildMode.Tool.TREE_BENCH: ["Tree bench", "bench_2a_indoor", ""],
	BuildMode.Tool.FOUNTAIN: ["Fountain", "fountain_indoor", ""],
	BuildMode.Tool.STATUE: ["Statue", "statue_indoor", ""],
	BuildMode.Tool.POST: ["Post", "metal_pole", ""],
	BuildMode.Tool.CHAIN: ["Chain", "metal_pole_chain", ""],
	BuildMode.Tool.BIN: ["Bin", "trash_can", ""],
	BuildMode.Tool.BAR_COUNTER: ["Bar counter", "bar_counter", ""],
	BuildMode.Tool.GRAB_STALL: ["Grab stall", "grab_and_go_stall", ""],
	BuildMode.Tool.DINING_TABLE: ["Dining table", "restaurant_table", ""],
	BuildMode.Tool.BOOTH: ["Booth", "restaurant_booth", ""],
	BuildMode.Tool.INFO_DESK: ["Info desk", "info_desk", ""],
	BuildMode.Tool.INFO_SCREEN: ["Info screen", "info_screen", ""],
	# On the Money page beside their rooms ("Exchange", "ATM"), as the pharmacy
	# counter is beside the Pharmacy card.
	BuildMode.Tool.EXCHANGE: ["Counter", "currency_exchange", ""],
	BuildMode.Tool.ATM: ["Cash machine", "atm", ""],
	BuildMode.Tool.PHARMACY_COUNTER: ["Counter", "pharmacy_counter", ""],
	BuildMode.Tool.PHARMACY_SHELF: ["Shelf", "pharmacy_shelf", ""],
	BuildMode.Tool.SHOWER: ["Shower", "shower_cubicle", ""],
	BuildMode.Tool.NAP_POD: ["Nap pod", "nap_pod", ""],
	BuildMode.Tool.SOFA: ["Sofa", "lounge_sofa", ""],
	BuildMode.Tool.ARMCHAIR: ["Armchair", "lounge_armchair", ""],
	BuildMode.Tool.WORK_DESK: ["Work desk", "work_desk", ""],
	BuildMode.Tool.PLAY_BLOCKS: ["Play blocks", "play_blocks", ""],
	BuildMode.Tool.PLAY_SLIDE: ["Play slide", "play_slide", ""],
	BuildMode.Tool.PRIZE_PODIUM: ["Prize podium", "prize_podium", ""],
}

## Cards that show what the placed piece costs to run per game day.
const RUNNING_COSTS := {
	BuildMode.Tool.INFO_SCREEN: PriceTable.INFO_SCREEN_UPKEEP,
	BuildMode.Tool.PRIZE_PODIUM: PriceTable.PRIZE_CAR_UPKEEP,
}

## The pages of the Furniture category (BuildMenu.CATEGORIES names them), each
## with at most four cards: a tray holds four cards and the Rotate and Next
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
