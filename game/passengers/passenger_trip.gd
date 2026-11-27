class_name PassengerTrip
extends RefCounted
## The one-line trip reason on the inspect card (decision follow-invitation-and-
## passenger-card-a-click-a-passenger-fir): how the passenger turned up (the
## arrival type) and what they hope to buy (WishTable). Both come from the
## passenger's saved arrival type and id, so the line is the same after a load.
## Each of the 15 lines is a whole sentence, so a translator owns its order.

## English lines by arrival type, then by wish (WishTable.NONE, then the kind).
const LINES := {
	ArrivalTypes.Type.RUSHED:
	{
		WishTable.NONE: "Cutting it fine, no shopping planned",
		&"kiosk": "Cutting it fine, hoping for a quick stop at the kiosk",
		&"pharmacy": "Cutting it fine, needs the pharmacy",
		&"duty_free": "Cutting it fine, hoping for duty free",
		&"fashion": "Cutting it fine, hoping to browse the fashion shop",
	},
	ArrivalTypes.Type.TYPICAL:
	{
		WishTable.NONE: "Right on time, no shopping planned",
		&"kiosk": "Right on time, hoping for a quick stop at the kiosk",
		&"pharmacy": "Right on time, needs the pharmacy",
		&"duty_free": "Right on time, hoping for duty free",
		&"fashion": "Right on time, hoping to browse the fashion shop",
	},
	ArrivalTypes.Type.RELAXED:
	{
		WishTable.NONE: "Early bird, no shopping planned",
		&"kiosk": "Early bird, hoping for a quick stop at the kiosk",
		&"pharmacy": "Early bird, needs the pharmacy",
		&"duty_free": "Early bird, hoping for duty free",
		&"fashion": "Early bird, hoping to browse the fashion shop",
	},
}

const ARRIVAL_LINE := "Arriving passenger, heading out of the terminal"


## The trip line of passenger `p`, in the player's words.
static func line(p: Passenger) -> String:
	return TranslationServer.translate(english(p))


## The English msgid of `p`'s trip line.
static func english(p: Passenger) -> String:
	if p.is_arriving():
		return ARRIVAL_LINE
	return (LINES[p.arrival_type] as Dictionary)[WishTable.of(p)]


## The trip lines inside tr(), for POT generation; a test checks they match LINES.
class Words:
	extends RefCounted

	func msgids() -> PackedStringArray:
		return PackedStringArray(
			[
				tr("Cutting it fine, no shopping planned"),
				tr("Cutting it fine, hoping for a quick stop at the kiosk"),
				tr("Cutting it fine, needs the pharmacy"),
				tr("Cutting it fine, hoping for duty free"),
				tr("Cutting it fine, hoping to browse the fashion shop"),
				tr("Right on time, no shopping planned"),
				tr("Right on time, hoping for a quick stop at the kiosk"),
				tr("Right on time, needs the pharmacy"),
				tr("Right on time, hoping for duty free"),
				tr("Right on time, hoping to browse the fashion shop"),
				tr("Early bird, no shopping planned"),
				tr("Early bird, hoping for a quick stop at the kiosk"),
				tr("Early bird, needs the pharmacy"),
				tr("Early bird, hoping for duty free"),
				tr("Early bird, hoping to browse the fashion shop"),
				tr("Arriving passenger, heading out of the terminal"),
			]
		)
