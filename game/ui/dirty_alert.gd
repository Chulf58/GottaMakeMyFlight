class_name DirtyAlert
extends RefCounted
## The dirty-terminal alert (decision cleaner-staff-and-messes-visits-leave-
## messes-bins-fill-pooled-cleaners-nearest-mess, point 6), one of the causes
## of the alert cards (AlertStack, HUD 1/7). It was a card of its own until the
## stack was built (decision dirty-terminal-alert-as-built-standalone-dirtyalert-
## card-sho). It reads the summed dirt of every mess (MessSim.total_dirt()) and
## tells the player what to do: hire a cleaner when none is hired, otherwise
## place bins or hire more cleaners. A click on its card steps through the
## dirtiest messes.
##
## The dirt has a band so the card does not flicker as cleaners work: it
## shows once the dirt reaches SHOW_AT and stays until it falls below
## CLEAR_BELOW. One fresh mess costs MessSim.DIRT, an aged one AGED_DIRT and a
## grown one GROWN_DIRT, so SHOW_AT is about eight fresh messes or three
## grown ones, and the card clears when about three fresh ones are left.

const KEY := &"dirty_terminal"
const TITLE := "Dirty terminal"
const SHOW_AT := 8
const CLEAR_BELOW := 4
const HIRE_TEXT := "The terminal is getting dirty. Hire a cleaner on the Staff card."
const BINS_TEXT := (
	"The terminal is getting dirty. Place bins near the bar and toilets, "
	+ "or hire more cleaners."
)

## The passenger sim whose messes and staff the alert reads. A different sim is
## a different world, so the alert starts again (reset()).
var sim: PassengerSim:
	set(value):
		sim = value
		reset()

var _shown := false
var _text := ""


## Whether the alert is up when the dirt is `dirt` and it is `was_shown` now:
## shown at SHOW_AT, kept while at or above CLEAR_BELOW, cleared below it.
static func shown_next(was_shown: bool, dirt: int) -> bool:
	if was_shown:
		return dirt >= CLEAR_BELOW
	return dirt >= SHOW_AT


## What the alert says for `cleaners` hired.
static func text_for(cleaners: int) -> String:
	return HIRE_TEXT if cleaners <= 0 else BINS_TEXT


## Puts the alert back as at the start: down, with its dirt read afresh at the
## next refresh(). An alert that was up does not carry over to another world or
## a load; the dirt then has to reach SHOW_AT again.
func reset() -> void:
	_shown = false
	_text = ""


## True while the alert is up.
func is_shown() -> bool:
	return _shown


## The alert's text: empty while it is down.
func card_text() -> String:
	return _text if _shown else ""


## Reads the sim's dirt and hired cleaners and updates the alert. Does nothing
## without a sim.
func refresh() -> void:
	if sim == null:
		return
	# A sim with no staff pool has hired nobody.
	var cleaners := 0 if sim.staff == null else sim.staff.count(StaffMember.Role.CLEANER)
	refresh_with(sim.messes.total_dirt(), cleaners)


## Updates the alert for `dirt` and `cleaners` hired: whether it is up follows
## shown_next(), the text follows the hired count.
func refresh_with(dirt: int, cleaners: int) -> void:
	_shown = shown_next(_shown, dirt)
	_text = text_for(cleaners) if _shown else ""


## The alert as an AlertBoard cause, from the last refresh(): none while it is
## down, else one pointing at the dirtiest messes (most dirt first, then by id).
## The band is its own hysteresis, so it waits no ticks either way.
func cause() -> Array[Dictionary]:
	if not _shown:
		return []
	var targets: Array[Vector3] = []
	if sim != null:
		var messes: Array[Dictionary] = []
		for id in sim.messes.mess_ids():
			messes.append(sim.messes.get_mess(id))
		var tick := sim.tick
		messes.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				var da := MessSim.dirt_of(a, tick)
				var db := MessSim.dirt_of(b, tick)
				return da > db or (da == db and int(a["id"]) < int(b["id"]))
		)
		for mess in messes.slice(0, AlertSources.MAX_TARGETS):
			targets.append(sim.grid.cell_to_world(mess["cell"]))
	return [
		{
			"key": KEY,
			"title": TITLE,
			"detail": _text,
			"targets": targets,
			"show_after": 0,
			"clear_after": 0,
		}
	]
