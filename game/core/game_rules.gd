class_name GameRules
extends RefCounted
## Active game mode and sandbox toggles (decision stage-3-free-build-sandbox-
## mode-picker-and-rules). Career is the default; Free-Build Sandbox adds
## unlimited_funds (or a $250,000 budget when off) and unlock_all (all tiers
## and land plots unlocked from the start).

const SAVE_VERSION := 1
const SANDBOX_BUDGET := 250_000
## Half of Wallet.MAX_BALANCE so neither spending nor demolition refunds hit
## WALLET_FULL or CANT_AFFORD while keeping settlement and drag previews valid.
const UNLIMITED_BUDGET := Wallet.MAX_BALANCE / 2
const SNAPSHOT_KEYS := ["save_version", "sandbox", "unlimited_funds", "unlock_all"]

var sandbox: bool = false
var unlimited_funds: bool = false
var unlock_all: bool = false


static func career() -> GameRules:
	return GameRules.new()


static func make_sandbox(
	with_unlimited_funds: bool = true, with_unlock_all: bool = true
) -> GameRules:
	var rules := GameRules.new()
	rules.sandbox = true
	rules.unlimited_funds = with_unlimited_funds
	rules.unlock_all = with_unlock_all
	return rules


## Clamps `rules` to Career when null, Career, or running in DemoMode.
static func effective(rules: GameRules) -> GameRules:
	if rules == null or DemoMode.is_demo() or not rules.sandbox:
		return career()
	return rules.duplicate_rules()


## Empty string when `data` is a valid saved GameRules dictionary, else the reason.
static func validation_problem(data: Variant) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "rules must be a dictionary"
	var dict := data as Dictionary
	for key in dict.keys():
		if not SNAPSHOT_KEYS.has(key):
			return "unknown key '%s'" % key
	for key in SNAPSHOT_KEYS:
		if not dict.has(key):
			return "missing key '%s'" % key
	if not WholeNumber.is_whole(dict["save_version"]) or int(dict["save_version"]) != SAVE_VERSION:
		return "save_version must be %d" % SAVE_VERSION
	for key in ["sandbox", "unlimited_funds", "unlock_all"]:
		if typeof(dict[key]) != TYPE_BOOL:
			return "'%s' must be true or false" % key
	if not bool(dict["sandbox"]) and (bool(dict["unlimited_funds"]) or bool(dict["unlock_all"])):
		return "Career rules cannot enable sandbox toggles"
	return ""


## True when the save file at `path` holds valid Sandbox rules. Never mutates or logs errors.
static func save_is_sandbox(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var text := FileAccess.get_file_as_string(path)
	if FileAccess.get_open_error() != OK:
		return false
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return false
	var data := json.data as Dictionary
	if not data.has("rules") or validation_problem(data["rules"]) != "":
		return false
	return bool((data["rules"] as Dictionary)["sandbox"])


func is_sandbox() -> bool:
	return sandbox


func is_career_mode() -> bool:
	return not sandbox


func effective_unlimited_funds() -> bool:
	return sandbox and unlimited_funds and not DemoMode.is_demo()


func effective_unlock_all() -> bool:
	return sandbox and unlock_all and not DemoMode.is_demo()


func starting_budget() -> int:
	if not sandbox:
		return PriceTable.STARTING_BUDGET
	if unlimited_funds:
		return UNLIMITED_BUDGET
	return SANDBOX_BUDGET


func duplicate_rules() -> GameRules:
	var copy := GameRules.new()
	copy.sandbox = sandbox
	copy.unlimited_funds = unlimited_funds
	copy.unlock_all = unlock_all
	return copy


func to_save_dict() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"sandbox": sandbox,
		"unlimited_funds": unlimited_funds,
		"unlock_all": unlock_all,
	}


func from_save_dict(data: Variant) -> bool:
	var problem := validation_problem(data)
	if problem != "":
		push_error("GameRules.from_save_dict: %s" % problem)
		return false
	var dict := data as Dictionary
	sandbox = bool(dict["sandbox"])
	unlimited_funds = bool(dict["unlimited_funds"])
	unlock_all = bool(dict["unlock_all"])
	return true
