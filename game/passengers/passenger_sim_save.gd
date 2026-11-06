class_name PassengerSimSave
extends RefCounted
## The save and load of PassengerSim: the snapshot dictionary, restoring one,
## and the checks SaveGame's staging runs on a save before it installs it.
## Static helpers over a sim; the state stays on the sim.
##
## The history of PassengerSim.SAVE_VERSION:
## 3: the walks outside carry heights ([x, y, z] apron points).
## 4: hunger, the cafe cooldown and the cafe visits, queues and seats.
## 5: durable made and missed totals, per-flight results and the flights
## already scheduled; settled passengers are retired, so none of these are
## rebuilt from the passenger list.
## 6: each passenger and pending arrival carries its arrival type.
## 7: each passenger carries its security traits (bags, liquids, alarm). A
## version 6 save is migrated with zero bags and no flags; older ones are
## refused.
## 8: security service state (SecurityRuntime): each passenger's phase,
## remaining work and resolved incident, and per station the admitted and
## returning passengers, the main position and the berth. A version 7 save
## keeps a basic scanner's service in progress exactly as it was.
## 9: a lane's unpack work starts at 3 + 4 per bag, not 6 + 8. A version 8
## save has its unpack work left scaled to the new start.
## 10: each passenger's toilet need and toilet cooldown, and the toilet visits
## under "toilet" (ToiletSnapshot). Versions 6 to 9 are migrated: each
## passenger gets ToiletSim.migrated_need() of its id, and nobody is on a
## toilet visit.
## 11: each passenger's boredom (BoredomSim). Versions 6 to 10 are migrated:
## each passenger gets BoredomSim.start_of() of its id; a version 10 save keeps
## its toilet needs, cooldowns and visits as saved. Version 11 also holds each
## passenger's kiosk cooldown and the kiosk visits under "shop" (ShopSnapshot);
## an older save gets no cooldown and no kiosk visits.
## 12: the help visits and cooldowns of the info desks, under "info_desk"
## (InfoDesk.to_list()). A version 11 save is refused; a migrated older save has
## none.
## 13: each shop visit saves whether it is a fallback (ShopSnapshot). Versions
## 11 and 12 are refused, with no migration (decision old-saves-are-not-
## supported-until-after-a-release-no-save-mi).
## 14: each standing passenger's claimed standing spot, under "standing"
## (StandingSpots.to_list()). Version 13 is refused, with no migration; a
## migrated older save has no claims.
## 15: the boarding files, under "boarding" (BoardingFiles.to_dict()), and a
## standing spot kept by a passenger setting off from it for the exit. Version
## 14 is refused, with no migration; a migrated older save has no files, so one
## taken while anyone walked out to the plane is refused.
## 16: seats and standing spots are chosen near the passenger's own gate desk
## (GateReach), so a version 15 save, whose claims followed the old global
## nearest rule, is refused with no migration (decision old-saves-are-not-
## supported-until-after-a-release-no-save-mi).
## 17: each passenger's collect_tick (ParkRecovery); a migrated older save
## collects nothing. 18: a cafe or toilet visit following its moved piece saves
## its Relocation (CafeSnapshot, ToiletSnapshot). 19: a shop or activity
## visit's Relocation (ShopSnapshot). 20: each passenger's thoughts and their
## repeat marks (PassengerThoughts). 21: each passenger's seat placement and
## seat_exiting (GateRelocation). 22: boarding-file wait spots (FileWaiters).
## 23: a Relocation saves the step its visitor had made (reached). 24: each
## passenger's halt_tick (QueueRipple). 25: gate places reserved at security
## admission, under "gate_places" (GateCapacity). 26: a cafe roller turn-back
## saves the step made as Relocation.reached (CafeSim). 27: queue holders
## stand on the hold line behind the lane (TerminalLayout.line_of()) and a
## passenger done at a desk waits on it while every security line is full
## (PassengerStations); the saved shape is the same, but a 26 save's holders
## stand stacked on the lane's last cell. From 17 on, the version before is
## refused, with no migration.
## 28: the claims on the lines' tails (one walker at a time enters a queue).


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
	# A save migrated from before version 12 (PassengerSnapshot) has no info
	# desk state: none is live. A version 12 save must carry it.
	var desk_state := checked_info_desks(sim, data, by_id, loaded["tick"])
	if desk_state.has("error"):
		push_error("PassengerSim.from_snapshot: %s" % desk_state["error"])
		return false
	# Standing claims are restored as saved, against spots derived from the
	# loaded grid; a save migrated from before version 14 has none.
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
	spots.restore(claims["claims"], by_id)
	sim.gates.restore(claims["gate"], spots, by_id)
	sim.standing = spots
	sim.files = boarding["files"]
	sim.tick = loaded["tick"]
	sim._next_id = loaded["next_id"]
	sim.last_batch_seed = loaded["last_batch_seed"]
	sim.no_shows = loaded["no_shows"]
	sim.flight_results = loaded["flight_results"]
	sim._scheduled = loaded["scheduled"]
	sim._made = loaded["made"]
	sim._missed = loaded["missed"]
	sim._schedule = loaded["schedule"]
	sim._queues = loaded["queues"]
	var tail_claims := checked_claims(data, by_id)
	if tail_claims.has("error"):
		push_error("PassengerSim.from_snapshot: %s" % tail_claims["error"])
		return false
	sim._claims = tail_claims["claims"]
	sim.security.restore(loaded["security"])
	sim.cafes.restore(loaded["cafe"])
	sim.toilets.restore(loaded["toilet"])
	sim.shops.restore(loaded["shop"])
	sim.info_desks.restore(desk_state)
	sim._passengers = loaded["passengers"]
	sim._by_id.clear()
	for p in sim._passengers:
		sim._by_id[p.id] = p
		ParkRecovery.on_load(p, sim.tick)
		# A save from before version 14 stands passengers with no spot. Each is
		# sent back to the gate with a cleared path; its stage tick is the next
		# tick, so it plans a seat or spot then (GateCapacity.to_spot()).
		if (
			p.stage == Passenger.Stage.STANDING
			and sim.standing.spot_of(p.id) == StandingSpots.NO_SPOT
		):
			p.stage = Passenger.Stage.TO_GATE
			p.stage_tick = sim.tick + 1
			p.clear_path()
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
	var current := int(data["save_version"]) >= PassengerSim.SAVE_VERSION
	var claims := spots.checked(data.get("standing", []), by_id, current)
	if not data.has("standing") and current:
		claims = {"error": "missing key 'standing'"}
	if claims.has("error"):
		return claims
	var gate := GateCapacity.checked(
		data.get("gate_places", []), by_id, sim, spots, claims["claims"]
	)
	if not data.has("gate_places") and current:
		gate = {"error": "missing key 'gate_places'"}
	if gate.has("error"):
		return gate
	claims["gate"] = gate
	claims["spots"] = spots
	return claims


## The info desk state in `data` checked against `by_id` (the loaded
## passengers by id) at the saved tick `at`: InfoDesk.checked()'s dictionary or
## {"error": why}. A save migrated from before version 12 has none (none is
## live); a current one must carry it. Changes no sim state: from_snapshot()
## installs the result, and SaveGame's staging runs the same check.
static func checked_info_desks(
	sim: PassengerSim, data: Dictionary, by_id: Dictionary, at: int
) -> Dictionary:
	var state := InfoDesk.checked(data.get("info_desk", InfoDesk.EMPTY), by_id, at, sim.grid)
	if not data.has("info_desk") and int(data["save_version"]) >= PassengerSim.SAVE_VERSION:
		return {"error": "missing key 'info_desk'"}
	return state


## The boarding files in `data` checked against `by_id`, with this sim's grid
## and layout (rebuilt from the grid): {"files": BoardingFiles} or {"error":
## why}. A migrated older save has none; a current one must carry them. Changes
## no sim state: from_snapshot() installs the result, and SaveGame's staging
## runs the same check.
static func checked_boarding(sim: PassengerSim, data: Dictionary, by_id: Dictionary) -> Dictionary:
	var standing := checked_standing(sim, data, by_id)
	var saved: Variant = data.get("boarding", BoardingFiles.EMPTY)
	var files_state := BoardingFiles.checked(saved, by_id, sim, standing)
	if not data.has("boarding") and int(data["save_version"]) >= PassengerSim.SAVE_VERSION:
		return {"error": "missing key 'boarding'"}
	return files_state


## The saved claims on the lines' tails (version 28): station -> the id of a
## saved passenger, or an error. A version 27 save has none.
static func checked_claims(data: Dictionary, by_id: Dictionary) -> Dictionary:
	var claims := {}
	if not data.has("claims"):
		if int(data["save_version"]) >= PassengerSim.SAVE_VERSION:
			return {"error": "claims missing"}
		return {"claims": claims}
	if typeof(data["claims"]) != TYPE_DICTIONARY:
		return {"error": "claims must be a dictionary"}
	for key: Variant in data["claims"]:
		var id: Variant = data["claims"][key]
		if not str(key).is_valid_int() or not WholeNumber.is_whole(id) or not by_id.has(int(id)):
			return {"error": "claim %s is not a saved passenger" % [key]}
		claims[int(str(key))] = int(id)
	return {"claims": claims}
