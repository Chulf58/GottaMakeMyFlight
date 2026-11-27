class_name PassengerBags
extends RefCounted
## The bag line on the inspect card (decision follow-invitation-and-passenger-
## card-a-click-a-passenger-fir): what the passenger carries on (the carry-on
## count and the liquids flag, CarryOnTraits) and where the checked bag is (its
## Bag.State, or not dropped yet, or none). Read from the passenger and the
## baggage sim only; nothing is saved for it. The pieces are joined by ListWords,
## so a translator owns the separators:
## "1 carry-on bag, carrying liquids and a checked bag on the belt".

enum Checked { NOT_YET, NONE, AT_DESK, ON_BELT, STUCK, IN_ROOM, LOADED, MISSED }

## The stages before the desk has taken the checked bag.
const BEFORE_DROP: Array[Passenger.Stage] = [
	Passenger.Stage.SPAWNED,
	Passenger.Stage.TO_CHECKIN,
	Passenger.Stage.CHECKIN_QUEUE,
	Passenger.Stage.CHECKIN,
]


## The line for `p`, given the baggage sim `baggage` (null where there is none:
## the checked bag is then not mentioned).
static func line(p: Passenger, baggage: BaggageSim) -> String:
	var words := Words.new()
	var parts := PackedStringArray([words.carry_on(p.carry_on)])
	if p.liquids and p.carry_on > 0:
		parts.append(words.liquids())
	if baggage != null:
		parts.append(words.checked(checked_state(p, baggage.bag_of_passenger(p.id))))
	return ListWords.join(parts)


## Where `p`'s checked bag is: `bag` is the baggage sim's bag of the passenger,
## or null for none kept.
static func checked_state(p: Passenger, bag: Bag) -> Checked:
	if p.is_arriving():
		return Checked.NONE
	if bag == null:
		return Checked.NOT_YET if BEFORE_DROP.has(p.stage) else Checked.NONE
	match bag.state:
		Bag.State.AT_DESK:
			return Checked.AT_DESK
		Bag.State.RIDING:
			return Checked.ON_BELT
		Bag.State.BLOCKED:
			return Checked.STUCK
		Bag.State.IN_ROOM:
			return Checked.IN_ROOM
		Bag.State.LOADED:
			return Checked.LOADED
	return Checked.MISSED


## tr() is an instance method, so the static line asks a Words. msgids() lists
## every sentence for POT generation and for the coverage test.
class Words:
	extends RefCounted

	func carry_on(count: int) -> String:
		if count <= 0:
			return tr("No carry-on bags")
		return tr_n("{count} carry-on bag", "{count} carry-on bags", count).format({"count": count})

	func liquids() -> String:
		return tr("carrying liquids")

	func checked(state: Checked) -> String:
		var text := tr("a checked bag that missed the plane")
		match state:
			Checked.NOT_YET:
				text = tr("a checked bag still to drop off")
			Checked.NONE:
				text = tr("no checked bag")
			Checked.AT_DESK:
				text = tr("a checked bag at the desk")
			Checked.ON_BELT:
				text = tr("a checked bag on the belt")
			Checked.STUCK:
				text = tr("a checked bag stuck on the belt")
			Checked.IN_ROOM:
				text = tr("a checked bag in the bag room")
			Checked.LOADED:
				text = tr("a checked bag loaded on the plane")
		return text

	func msgids() -> PackedStringArray:
		var out := PackedStringArray([tr("No carry-on bags"), tr("carrying liquids")])
		out.append(tr_n("{count} carry-on bag", "{count} carry-on bags", 1))
		for state in Checked.values():
			out.append(checked(state))
		return out
