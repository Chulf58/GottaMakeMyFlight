class_name TestLandPlotsSave
extends GdUnitTestSuite
## Which land snapshots LandPlots.problem() accepts for a save: only states a
## game can reach, a new game's start land (the starter plots and their ring,
## columns 4 and 5 of the first site, rows 3 to 5) plus plots bought one at a time beside owned
## land. A plot listed twice, a missing start plot, a wrong `bought` count and
## a plot not joined to the start land by an edge are each refused.

const SITE := preload("res://build/terminal_site.tres")
## The plots a new game owns, row by row.
const START: Array[Vector2i] = [
	Vector2i(4, 3), Vector2i(5, 3), Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5), Vector2i(5, 5)
]


## A snapshot of the start land plus `extra` plots and `bought`.
func _save_of(extra: Array, bought: int, drop := -1) -> Dictionary:
	var owned := []
	for i in START.size():
		if i != drop:
			owned.append([START[i].x, START[i].y])
	owned.append_array(extra)
	return {"plot_counts": [12, 6], "owned": owned, "bought": bought}


func test_a_save_of_start_land_plus_a_plot_bought_beside_it_is_accepted() -> void:
	assert_str(LandPlots.problem(_save_of([], 0), SITE)).is_empty()
	assert_str(LandPlots.problem(_save_of([[6, 4]], 1), SITE)).is_empty()
	# Joined through a bought plot, not to the start land directly.
	assert_str(LandPlots.problem(_save_of([[6, 4], [7, 4]], 2), SITE)).is_empty()


func test_a_save_listing_a_plot_twice_is_refused() -> void:
	assert_str(LandPlots.problem(_save_of([[5, 3]], 0), SITE)).contains("twice")


func test_a_save_missing_a_start_land_plot_is_refused() -> void:
	# (5, 3) is the corner plot of the ring; the rest of the save is sound.
	assert_str(LandPlots.problem(_save_of([], 0, 1), SITE)).contains("start land")


func test_a_save_whose_bought_count_does_not_match_the_plots_is_refused() -> void:
	assert_str(LandPlots.problem(_save_of([[6, 4]], 0), SITE)).contains("'bought'")
	assert_str(LandPlots.problem(_save_of([], 1), SITE)).contains("'bought'")


func test_a_save_with_a_plot_cut_off_from_the_start_land_is_refused() -> void:
	# The count is right (one plot beyond the start land), only the join fails.
	assert_str(LandPlots.problem(_save_of([[7, 0]], 1), SITE)).contains("not joined")
	# (6, 2) touches the start land at a corner only.
	assert_str(LandPlots.problem(_save_of([[6, 2]], 1), SITE)).contains("not joined")
