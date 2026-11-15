extends RefCounted
## Closes the new-game intro for a probe that boots main.tscn. Closing the intro
## asks the incidents question, and its clock hold does not give way to the
## player, so a probe that only calls dismiss_intro() never leaves tick 0. close()
## dismisses the intro and declines the question; every probe that boots the real
## game calls it instead of PassengerHud.dismiss_intro(). Load it with preload();
## it has no class_name, so the spike adds nothing to the game's global class list.
##
## Also holds seed_or_random(), the one place a probe reads --seed=N.


## Dismisses the intro, then declines the incidents question so no incident joins
## the run. Returns "" when the clock is free, else a reason the probe reports as
## PROBE_INVALID before it exits 1.
static func close(main: Node) -> String:
	(main.get_node("PassengerHud") as PassengerHud).dismiss_intro()
	var menu := main.get_node("GameMenu") as GameMenu
	if menu.question() != null:
		menu.question().decline_button().pressed.emit()
	if (main.get_node("SimClock") as SimClock).holds.is_holding():
		return "a dialog still holds the clock after the intro"
	return ""


## A new random seed, or N when the probe was started with `-- --seed=N` to
## replay a run.
static func seed_or_random() -> int:
	var value := randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			value = int(arg.get_slice("=", 1))
	return value
