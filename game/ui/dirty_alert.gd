class_name DirtyAlert
extends PanelContainer
## The dirty-terminal alert card (decision cleaner-staff-and-messes-visits-
## leave-messes-bins-fill-pooled-cleaners-nearest-mess, point 6; card form from
## decision hud-steal-list-self-clearing-alert-cards-money-hover-departu): a
## small card at the top of the screen that appears when the terminal's mess
## builds up and clears itself when it is clean again. It reads the summed dirt
## of every mess (MessSim.total_dirt()) and tells the player what to do: hire a
## cleaner when none is hired, otherwise place bins or hire more cleaners.
##
## The dirt has a band so the card does not flicker as cleaners work: it
## shows once the dirt reaches SHOW_AT and stays until it falls below
## CLEAR_BELOW. One fresh mess costs MessSim.DIRT, an aged one AGED_DIRT and a
## grown one GROWN_DIRT, so SHOW_AT is about eight fresh messes or three
## grown ones, and the card clears when about three fresh ones are left.

const SHOW_AT := 8
const CLEAR_BELOW := 4
const HIRE_TEXT := "The terminal is getting dirty. Hire a cleaner on the Staff card."
const BINS_TEXT := (
	"The terminal is getting dirty. Place bins near the bar and toilets, "
	+ "or hire more cleaners."
)
## Below the top row (money, rating, offers, day panel), centred, clear of the
## room panel on the left and the departures board below it.
const TOP := 76.0
const WIDTH := 420.0

## The passenger sim whose messes and staff the card reads.
@export var sim: PassengerSim

var _shown := false
var _label := Label.new()


func _ready() -> void:
	name = "DirtyAlert"
	theme = BuildMenu.HUD_THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Top centre, sized to its text up to WIDTH.
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -WIDTH / 2.0
	offset_right = WIDTH / 2.0
	offset_top = TOP
	grow_vertical = Control.GROW_DIRECTION_END
	_label.name = "DirtyAlertText"
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	visible = false


## Whether the card is up when the dirt is `dirt` and it is `was_shown` now:
## shown at SHOW_AT, kept while at or above CLEAR_BELOW, cleared below it.
static func shown_next(was_shown: bool, dirt: int) -> bool:
	if was_shown:
		return dirt >= CLEAR_BELOW
	return dirt >= SHOW_AT


## What the card says for `cleaners` hired.
static func text_for(cleaners: int) -> String:
	return HIRE_TEXT if cleaners <= 0 else BINS_TEXT


## True while the card is up.
func is_shown() -> bool:
	return _shown


## The card's text: empty while it is down.
func card_text() -> String:
	return _label.text if _shown else ""


## Reads the sim's dirt and hired cleaners and updates the card. Does nothing
## without a sim.
func refresh() -> void:
	if sim == null:
		return
	# A sim with no staff pool has hired nobody.
	var cleaners := 0 if sim.staff == null else sim.staff.count(StaffMember.Role.CLEANER)
	refresh_with(sim.messes.total_dirt(), cleaners)


## Updates the card for `dirt` and `cleaners` hired: the visibility follows
## shown_next(), the text follows the hired count.
func refresh_with(dirt: int, cleaners: int) -> void:
	_shown = shown_next(_shown, dirt)
	visible = _shown
	_label.text = text_for(cleaners) if _shown else ""
