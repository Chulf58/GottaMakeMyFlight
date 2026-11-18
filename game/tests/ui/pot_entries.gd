class_name PotEntries
extends RefCounted
## messages.pot read entry by entry, so a template check sees the whole entry
## (msgctxt, msgid, msgid_plural and a msgstr line) and not just a msgid line.
## Texts are kept as written in the file (escapes not resolved), the same form
## a source string literal has. An entry is one block of fields: a msgctxt or
## msgid line that follows a msgid, or the end of the file, closes the one before.


## Each entry as {"ctx", "id", "plural", "msgstr_keys", "line"}: the texts, the name of
## each msgstr / msgstr[n] field it has (in file order), and the line its first field is on.
static func parse(text: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var cur := {}
	var field := ""
	var number := 0
	for raw in text.replace("\r\n", "\n").split("\n"):
		number += 1
		var row := raw.strip_edges()
		if row == "" or row.begins_with("#"):
			if row == "":
				_close(entries, cur)
				cur = {}
				field = ""
			continue
		var space := row.find(" ")
		var key := row.substr(0, space) if space > 0 else ""
		var body := row.substr(space + 1) if space > 0 else row
		if key == "msgctxt" or key == "msgid":
			if cur.has("id"):
				_close(entries, cur)
				cur = {}
			field = "ctx" if key == "msgctxt" else "id"
			_begin(cur, number)
			cur[field] = _quoted(body)
		elif key == "msgid_plural":
			field = "plural"
			_begin(cur, number)
			cur[field] = _quoted(body)
		elif key.begins_with("msgstr"):
			field = "msgstr"
			_begin(cur, number)
			cur["msgstr_keys"].append(key)
		elif row.begins_with('"') and field != "" and field != "msgstr":
			cur[field] += _quoted(row)
	_close(entries, cur)
	return entries


## How many entries have exactly this context, msgid and plural.
static func count(entries: Array[Dictionary], ctx: String, id: String, plural := "") -> int:
	return _matching(entries, ctx, id, plural).size()


## How many entries with this context, msgid and plural also have the msgstr shape
## their kind needs (see well_formed).
static func complete(entries: Array[Dictionary], ctx: String, id: String, plural := "") -> int:
	return (
		_matching(entries, ctx, id, plural)
		. filter(func(entry: Dictionary) -> bool: return well_formed(entry))
		. size()
	)


## Whether an entry has a msgid and the msgstr fields its kind needs: one plain
## msgstr and no indexed form when there is no msgid_plural; msgstr[0] and msgstr[1]
## and no plain msgstr when there is.
static func well_formed(entry: Dictionary) -> bool:
	if not entry.has("id"):
		return false
	var keys: Array = entry["msgstr_keys"]
	if entry.has("plural"):
		return keys.has("msgstr[0]") and keys.has("msgstr[1]") and not keys.has("msgstr")
	return keys == ["msgstr"]


## Entries that fail well_formed, as "line N: msgid".
static func malformed(entries: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for entry in entries:
		if not well_formed(entry):
			out.append("line %d: %s" % [entry["line"], entry.get("id", "(no msgid)")])
	return out


## Entries whose context and msgid appeared before, as "line N: msgid". The header
## entry (empty msgid) is skipped.
static func duplicates(entries: Array[Dictionary]) -> Array[String]:
	var seen := {}
	var out: Array[String] = []
	for entry in entries:
		if entry.get("id", "") == "":
			continue
		var key := "%s\u0000%s" % [entry.get("ctx", ""), entry["id"]]
		if seen.has(key):
			out.append("line %d: %s" % [entry["line"], entry["id"]])
		seen[key] = true
	return out


static func _begin(cur: Dictionary, number: int) -> void:
	if cur.is_empty():
		cur["line"] = number
		cur["msgstr_keys"] = []


static func _close(entries: Array[Dictionary], cur: Dictionary) -> void:
	if not cur.is_empty():
		entries.append(cur)


static func _quoted(body: String) -> String:
	var text := body.strip_edges()
	return text.substr(1, text.length() - 2) if text.length() >= 2 else ""


static func _matching(
	entries: Array[Dictionary], ctx: String, id: String, plural: String
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in entries:
		if (
			entry.get("ctx", "") == ctx
			and entry.get("id", "") == id
			and entry.get("plural", "") == plural
		):
			out.append(entry)
	return out
