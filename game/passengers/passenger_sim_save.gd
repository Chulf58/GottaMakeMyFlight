class_name PassengerSimSave
extends RefCounted
## The save and load of PassengerSim: the snapshot dictionary, restoring one,
## and the checks SaveGame's staging runs on a save before it installs it.
## Static helpers over a sim; the state stays on the sim.
##
## The history of PassengerSim.SAVE_VERSION (only PassengerSim.SAVE_VERSION
## loads; older saves are refused with no pre-release migration):
## 3: the walks outside carry heights ([x, y, z] apron points).
## 4: hunger, the cafe cooldown and the cafe visits, queues and seats.
## 5: durable made and missed totals, per-flight results and the flights
## already scheduled; settled passengers are retired, so none of these are
## rebuilt from the passenger list.
## 6: each passenger and pending arrival carries its arrival type.
## 7: each passenger carries its security traits (bags, liquids, alarm).
## 8: security service state (SecurityRuntime): each passenger's phase,
## remaining work and resolved incident, and per station the admitted and
## returning passengers, the main position and the berth.
## 9: a lane's unpack work starts at 3 + 4 per bag, not 6 + 8.
## 10: each passenger's toilet need and toilet cooldown, and the toilet visits
## under "toilet" (ToiletSnapshot).
## 11: each passenger's boredom (BoredomSim), kiosk cooldown and the kiosk
## visits under "shop" (ShopSnapshot).
## 12: the help visits and cooldowns of the info desks, under "info_desk"
## (InfoDesk.to_list()).
## 13: each shop visit saves whether it is a fallback (ShopSnapshot).
## 14: each standing passenger's claimed standing spot, under "standing"
## (StandingSpots.to_list()).
## 15: the boarding files, under "boarding" (BoardingFiles.to_dict()), and a
## standing spot kept by a passenger setting off from it for the exit.
## 16: seats and standing spots are chosen near the passenger's own gate desk
## (GateReach).
## 17: each passenger's collect_tick (ParkRecovery). 18: a cafe or toilet visit
## following its moved piece saves its Relocation (CafeSnapshot, ToiletSnapshot).
## 19: a shop or activity visit's Relocation (ShopSnapshot). 20: each
## passenger's thoughts and their repeat marks (PassengerThoughts). 21: each
## passenger's seat placement and seat_exiting (GateRelocation). 22:
## boarding-file wait spots (FileWaiters). 23: a Relocation saves the step its
## visitor had made (reached). 24: each
## passenger's halt_tick (QueueRipple). 25: gate places reserved at security
## admission, under "gate_places" (GateCapacity). 26: a cafe roller turn-back
## saves the step made as Relocation.reached (CafeSim). 27: queue holders
## stand on the hold line behind the lane (TerminalLayout.line_of()) and a
## passenger done at a desk waits on it while every security line is full
## (PassengerStations); the saved shape is the same, but a 26 save's holders
## stand stacked on the lane's last cell. From 17 on, the version before is
## refused, with no migration.
## 28: the claims on the lines' tails (one walker at a time enters a queue).
## 29: standing spots within StandingSpots.DESK_CLEAR_MM of a gate desk are not
## offered, so a version 28 save may claim a spot that no longer exists; it is
## refused with no migration (decision old-saves-are-not-supported-until-after-
## a-release-no-save-mi).
## 30: a gate stander's stand_from, the cell it stepped onto its spot's cell
## from (ParkSide.stand_face()); a version 29 save has none and is refused with
## no migration (the same decision).
## 31: ParkSide's stamps ("park_side", park_side_list()), so a one-bag guest's
## gate chair side survives a load (board 4da2e8ff); a version 30 save has none
## and is refused with no migration (the same decision).
## 32: a walk outside is measured in 3D (Passenger.apron_segment_mm()), and a
## walker of a docking plane boards through the jet bridge (board 927ed9e0), so
## a version 31 save's apron_mm is ground distance along a ground walk; it is
## refused with no migration (the same decision).
## 33: BookingOverrides' extra passengers per occurrence not yet scheduled
## ("booking_overrides", board c6c13a5a); a version 32 save has none and is
## refused with no migration (the same decision).
## 34: the line outside the entrance ("entrance_line", EntranceLine.to_dict()):
## its order, the admitted passengers' claims and the bookings held aboard for
## it (board 66be00a0); a version 33 save, whose arrivals waited on the door
## cell, is refused with no migration (the same decision).
## 35: the entrance line's claims each hold a place on one desk ("stations",
## one per claim) and its own NO_ROUTE marks are listed ("marked"); a version
## 34 save has neither and is refused with no migration (the same decision).
## 36: the entrance line's held bookings stay held while aboard after the
## hold clears, and the ones held on the last step are listed ("held_now"); a
## version 35 save has no such list and is refused with no migration (the
## same decision).
## 37: standalone corridor services (ATM, currency exchange, grab-and-go stall,
## nap pod) save visits with room 0 in CafeSnapshot / ShopSnapshot; a version
## 36 save is refused with no migration (the same decision).
## 38: security overhaul S1: split body_resolved/bag_resolved on passengers and
## daily confiscation bin history ("confiscations"); version 37 saves are
## refused with no migration (the same decision).
## 39: security overhaul S2: Passenger.vip and FAST_TRACK thought; version 38
## saves are refused with no migration (the same decision).
## 40: remote-stand shuttle bus stage (Passenger.Stage.ON_BUS), Passenger.bus_nudged
## and PassengerThoughts.Kind.BUS_RIDE; version 39 saves are refused (no migration).
## 41: missed passenger walk-out phase (Passenger.missed_phase) and MISSED_FLIGHT
## thought; version 40 saves are refused (no migration).


## JSON-safe state for a save (PassengerSim.to_snapshot()). Reads only: it
## changes nothing in the sim or the wallet.
static func to_snapshot(sim: PassengerSim) -> Dictionary:
	if sim.cafes.deadlines_stale:
		push_error("PassengerSim.to_snapshot: a grid edit settles on the next tick; save after it")
		return {}
	var data := PassengerSnapshot.save(
		sim,
		sim._passengers,
		sim._schedule,
		sim._queues,
		sim._next_id,
		[sim._made, sim._missed],
		sim._scheduled.keys()
	)
	data["info_desk"] = sim.info_desks.to_list()
	data["standing"] = sim.standing.to_list()
	data["gate_places"] = sim.gates.to_list(sim)
	data["boarding"] = sim.files.to_dict()
	var claims := {}
	for station: int in sim._claims:
		claims[str(station)] = sim._claims[station]
	data["claims"] = claims
	data["park_side"] = park_side_list(sim)
	data["booking_overrides"] = BookingOverrides.to_list(sim)
	data["entrance_line"] = sim.entrance.to_dict(sim)
	return data


## Restores a to_snapshot() dictionary (PassengerSim.from_snapshot()).
static func from_snapshot(sim: PassengerSim, data: Dictionary) -> bool:
	var loaded := PassengerSnapshot.load(data, sim.grid)
	if loaded.has("error"):
		push_error("PassengerSim.from_snapshot: %s" % loaded["error"])
		return false
	var by_id := {}
	for p: Passenger in loaded["passengers"]:
		by_id[p.id] = p
	var desk_state := checked_info_desks(sim, data, by_id, loaded["tick"])
	if desk_state.has("error"):
		push_error("PassengerSim.from_snapshot: %s" % desk_state["error"])
		return false
	# Standing claims are restored as saved, against spots derived from the
	# loaded grid.
	sim.layout.rebuild(sim.grid)
	var held := checked_standing(sim, data, by_id)
	if held.has("error"):
		push_error("PassengerSim.from_snapshot: %s" % held["error"])
		return false
	var spots: StandingSpots = held["spots"]
	var claims: Dictionary = held
	var boarding := checked_boarding(sim, data, by_id)
	if boarding.has("error"):
		push_error("PassengerSim.from_snapshot: %s" % boarding["error"])
		return false
	# Checked with the rest before anything is installed: a bad save changes
	# nothing.
	var tail_claims := checked_claims(data, by_id)
	if tail_claims.has("error"):
		push_error("PassengerSim.from_snapshot: %s" % tail_claims["error"])
		return false
	var sides := checked_park_side(data, by_id)
	if sides.has("error"):
		push_error("PassengerSim.from_snapshot: %s" % sides["error"])
		return false
	var booking := BookingOverrides.checked(data, sim.flights, sim.flights.epoch)
	if booking.has("error"):
		push_error("PassengerSim.from_snapshot: %s" % booking["error"])
		return false
	var entrance := checked_entrance(data, by_id)
	if entrance.has("error"):
		push_error("PassengerSim.from_snapshot: %s" % entrance["error"])
		return false
	spots.restore(claims["claims"], by_id)
	sim.gates.restore(claims["gate"], spots, by_id)
	sim.standing = spots
	sim.files = boarding["files"]
	sim.entrance = entrance["line"]
	sim.tick = loaded["tick"]
	sim._next_id = loaded["next_id"]
	sim.last_batch_seed = loaded["last_batch_seed"]
	sim.no_shows = loaded["no_shows"]
	sim.flight_results = loaded["flight_results"]
	sim._scheduled = loaded["scheduled"]
	sim._booking_overrides = booking["overrides"]
	sim._made = loaded["made"]
	sim._missed = loaded["missed"]
	sim._schedule = loaded["schedule"]
	sim._queues = loaded["queues"]
	sim._claims = tail_claims["claims"]
	sim.security.restore(loaded["security"])
	sim.security.bins.restore(loaded["confiscations"])
	sim.cafes.restore(loaded["cafe"])
	sim.toilets.restore(loaded["toilet"])
	sim.shops.restore(loaded["shop"])
	sim.info_desks.restore(desk_state)
	sim._passengers = loaded["passengers"]
	# ParkSide's stamped hands as saved, never the ones made after the snapshot:
	# chosen again on load, a one-bag guest's gate chair side could flip with
	# its roller on the floor, once a two-bag neighbour had come after it chose
	# (board 4da2e8ff).
	if sim.has_meta(ParkSide.STAMPS):
		sim.remove_meta(ParkSide.STAMPS)
	if not (sides["stamps"] as Dictionary).is_empty():
		sim.set_meta(ParkSide.STAMPS, sides["stamps"])
	sim._by_id.clear()
	for p in sim._passengers:
		sim._by_id[p.id] = p
		ParkRecovery.on_load(p, sim.tick)
	sim.layout.rebuild(sim.grid)
	sim.routes.clear()
	sim._rederive()
	# A layout built differently from the one saved (a shorter or rerouted
	# line) leaves no queue longer than its line (PassengerStations.fit_line()).
	PassengerStations.fit_lines(sim)
	sim._rederive()
	return true


## The standing spots derived from the loaded grid and the saved claims,
## checked against `by_id` (the loaded passengers by id): {"spots":
## StandingSpots, "claims": {passenger: spot}} or {"error": why}. Needs the
## layout rebuilt from the grid. Changes no sim state: from_snapshot() installs
## the result, and SaveGame's staging runs the same check, so the two agree.
static func checked_standing(sim: PassengerSim, data: Dictionary, by_id: Dictionary) -> Dictionary:
	var spots := StandingSpots.new()
	spots.rebuild(sim)
	if not data.has("standing"):
		return {"error": "missing key 'standing'"}
	var claims := spots.checked(data["standing"], by_id, true)
	if claims.has("error"):
		return claims
	if not data.has("gate_places"):
		return {"error": "missing key 'gate_places'"}
	var gate := GateCapacity.checked(data["gate_places"], by_id, sim, spots, claims["claims"])
	if gate.has("error"):
		return gate
	claims["gate"] = gate
	claims["spots"] = spots
	return claims


## The info desk state in `data` checked against `by_id` (the loaded
## passengers by id) at the saved tick `at`: InfoDesk.checked()'s dictionary or
## {"error": why}. Changes no sim state: from_snapshot() installs the result,
## and SaveGame's staging runs the same check.
static func checked_info_desks(
	sim: PassengerSim, data: Dictionary, by_id: Dictionary, at: int
) -> Dictionary:
	if not data.has("info_desk"):
		return {"error": "missing key 'info_desk'"}
	return InfoDesk.checked(data["info_desk"], by_id, at, sim.grid)


## The boarding files in `data` checked against `by_id`, with this sim's grid
## and layout (rebuilt from the grid): {"files": BoardingFiles} or {"error":
## why}. Changes no sim state: from_snapshot() installs the result, and
## SaveGame's staging runs the same check.
static func checked_boarding(sim: PassengerSim, data: Dictionary, by_id: Dictionary) -> Dictionary:
	if not data.has("boarding"):
		return {"error": "missing key 'boarding'"}
	var standing := checked_standing(sim, data, by_id)
	return BoardingFiles.checked(data["boarding"], by_id, sim, standing)


## ParkSide's stamps (the hand a one-bag guest lays its roller down with at a
## seat, chosen once per seat) of `sim`'s passengers, by passenger id: a list
## of {"passenger": id, "seat": the seat's key, "hand": 0 or 1}.
static func park_side_list(sim: PassengerSim) -> Array:
	var stamps: Dictionary = sim.get_meta(ParkSide.STAMPS, {})
	var ids: Array = stamps.keys()
	ids.sort()
	var out := []
	for id: int in ids:
		if sim._by_id.has(id):
			var stamp: Array = stamps[id]
			out.append({"passenger": id, "seat": stamp[0], "hand": stamp[1]})
	return out


## The saved ParkSide stamps (park_side_list()) checked against the loaded
## passengers `by_id`: {"stamps": {id: [seat key, hand]}} or {"error": why}.
## Each names a saved passenger once, a seat key and a hand of 0 or 1.
static func checked_park_side(data: Dictionary, by_id: Dictionary) -> Dictionary:
	if not data.has("park_side"):
		return {"error": "missing key 'park_side'"}
	var stamps := {}
	var list: Variant = data["park_side"]
	if typeof(list) != TYPE_ARRAY:
		return {"error": "park_side must be a list"}
	for entry: Variant in list:
		if (
			typeof(entry) != TYPE_DICTIONARY
			or (entry as Dictionary).size() != 3
			or not WholeNumber.is_whole(entry.get("passenger"))
			or typeof(entry.get("seat")) != TYPE_STRING
			or not WholeNumber.is_whole(entry.get("hand"))
			or int(entry["hand"]) not in [0, 1]
		):
			return {"error": "park side %s is malformed" % str(entry).left(80)}
		var id := int(entry["passenger"])
		if not by_id.has(id) or stamps.has(id):
			return {"error": "park side %d is not one saved passenger's" % id}
		stamps[id] = [entry["seat"], int(entry["hand"])]
	return {"stamps": stamps}


## The saved line outside the entrance: {"line": EntranceLine} or
## {"error": why}.
static func checked_entrance(data: Dictionary, by_id: Dictionary) -> Dictionary:
	if not data.has("entrance_line"):
		return {"error": "entrance_line missing"}
	return EntranceLine.checked(data["entrance_line"], by_id)


## The saved claims on the lines' tails: station -> the id of a saved
## passenger, or an error.
static func checked_claims(data: Dictionary, by_id: Dictionary) -> Dictionary:
	if not data.has("claims"):
		return {"error": "claims missing"}
	var claims := {}
	if typeof(data["claims"]) != TYPE_DICTIONARY:
		return {"error": "claims must be a dictionary"}
	for key: Variant in data["claims"]:
		var id: Variant = data["claims"][key]
		if not str(key).is_valid_int() or not WholeNumber.is_whole(id) or not by_id.has(int(id)):
			return {"error": "claim %s is not a saved passenger" % [key]}
		claims[int(str(key))] = int(id)
	return {"claims": claims}
