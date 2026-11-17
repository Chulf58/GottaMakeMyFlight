class_name TranslationScan
extends RefCounted
## Finds the lines in a GDScript source that set player-visible text to a string
## literal that does not go through tr() (decision translation-format-po-gettext-
## files-with-tr-and-tr-n-for-all). The guard test (test_translation_guard.gd)
## uses it against game/ui/*.gd and a baseline of the offences that exist today.
##
## A statement starts at `.text =`, `.text +=`, `.tooltip_text =` or `set_text(`
## and runs to the end of its brackets, over as many lines as that takes. Every
## string literal in it with a letter in it must sit inside a real tr(), tr_n(),
## atr() or atr_n() call (the identifier is read whole, so `str(` and `x.tr(` do
## not count). Not counted as text: a comment, a dictionary key inside
## `.format(` (a literal followed by `:`), the first argument of `.get(` or
## `.has(`, a literal in an index like NAMES["a"], a &"StringName" or
## ^"NodePath", and text that is only format specifiers and escapes such as
## "%.1f" or "\n". The values in `.format({...})` and the default in `.get(k, d)`
## are scanned like any other literal. Text held
## in a const or built in a helper is not seen; those stay for review.

const ASSIGN := "(?:\\.text|\\.tooltip_text)\\s*\\+?=(?!=)\\s*|set_text\\("
const FORMAT_SPEC := "%[-+0-9.]*[sdfxXcoi]|%%|\\\\."
## Methods whose FIRST argument is a key, not shown text: `.get("key", default)`.
const KEY_METHODS := ["get", "has"]
const TR_CALLS := ["tr", "tr_n", "atr", "atr_n"]
const MAX_STATEMENT_LINES := 30

static var _assign: RegEx
static var _format: RegEx


static func _regexes() -> void:
	if _assign != null:
		return
	_assign = RegEx.create_from_string(ASSIGN)
	_format = RegEx.create_from_string(FORMAT_SPEC)


## True when `line` starts a text statement with an unrouted literal.
static func offends(line: String) -> bool:
	return not offences(line).is_empty()


## The 1-based first line numbers of the statements in `source` that offend.
static func offending_lines(source: String) -> Array[int]:
	var found: Array[int] = []
	for offence in offences(source):
		found.append(offence["line"])
	return found


## One {"line": n, "text": the statement on one line} per offending statement.
static func offences(source: String) -> Array[Dictionary]:
	_regexes()
	var found: Array[Dictionary] = []
	var lines := source.split("\n")
	for i in lines.size():
		var code := strip_comment(lines[i])
		var start := _assign.search(code)
		if start == null:
			continue
		var expr := code.substr(start.get_end())
		var open: Array[String] = []
		if start.get_string().begins_with("set_text"):
			open.append("other")
		var result := _scan(expr, open)
		var statement := lines[i].strip_edges()
		var next := i + 1
		while (
			not result["open"].is_empty()
			and next < lines.size()
			and next - i <= MAX_STATEMENT_LINES
		):
			expr += " " + strip_comment(lines[next]).strip_edges()
			statement += " " + lines[next].strip_edges()
			result = _scan(expr, open)
			next += 1
		if result["found"]:
			found.append({"line": i + 1, "text": statement})
	return found


## `line` without a trailing # comment; a # inside a string is kept.
static func strip_comment(line: String) -> String:
	var quote := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if quote != "":
			if c == "\\":
				i += 1
			elif c == quote:
				quote = ""
		elif c == '"' or c == "'":
			quote = c
		elif c == "#":
			return line.substr(0, i)
		i += 1
	return line


## Scans `expr` once, starting inside the brackets named in `open`. Returns
## {"found": an unrouted literal with a letter was seen, "open": the bracket
## kinds still open at the end}.
static func _scan(expr: String, open: Array[String]) -> Dictionary:
	var stack: Array[String] = []
	stack.append_array(open)
	var found := false
	var i := 0
	while i < expr.length():
		var c := expr[i]
		if c == '"' or c == "'":
			var end := i + 1
			while end < expr.length() and expr[end] != c:
				end += 1 if expr[end] != "\\" else 2
			var prefix := expr[i - 1] if i > 0 else ""
			var literal := expr.substr(i + 1, end - i - 1)
			if (
				prefix != "&"
				and prefix != "^"
				and _is_text(literal)
				and not _is_exempt(stack, _is_dict_key(expr, end + 1))
			):
				found = true
			i = end + 1
			continue
		if c == "(":
			stack.append(_call_kind(expr, i))
		elif c == "[":
			stack.append("idx" if _follows_value(expr, i) else "other")
		elif c == "{":
			stack.append("other")
		elif c == "," and not stack.is_empty() and stack.back() == "key0":
			stack[stack.size() - 1] = "key1"
		elif c == ")" or c == "]" or c == "}":
			if stack.is_empty():
				break
			stack.pop_back()
		i += 1
	return {"found": found, "open": stack}


static func _is_text(literal: String) -> bool:
	var rest := _format.sub(literal, "", true)
	for i in rest.length():
		var c := rest.unicode_at(i)
		if (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c > 127:
			return true
	return false


## True for a literal that is not shown text: inside tr(), in an index, the
## first argument of `.get(`/`.has(`, or a dictionary key inside `.format(`.
static func _is_exempt(stack: Array[String], is_key: bool) -> bool:
	if stack.has("tr") or stack.has("idx"):
		return true
	if not stack.is_empty() and stack.back() == "key0":
		return true
	return is_key and stack.has("fmt")


## True when the next character after `at` (spaces skipped) is the `:` of a dictionary entry.
static func _is_dict_key(expr: String, at: int) -> bool:
	while at < expr.length() and expr[at] == " ":
		at += 1
	return at < expr.length() and expr[at] == ":"


## "tr" for a real translation call, "fmt" for `.format(`, "key0" for the first
## argument of `.get(`/`.has(`, else "other".
static func _call_kind(expr: String, paren: int) -> String:
	var start := paren
	while start > 0 and _is_word(expr[start - 1]):
		start -= 1
	var ident := expr.substr(start, paren - start)
	if start > 0 and expr[start - 1] == ".":
		if ident == "format":
			return "fmt"
		return "key0" if KEY_METHODS.has(ident) else "other"
	return "tr" if TR_CALLS.has(ident) else "other"


## True when the `[` at `bracket` indexes a value (NAMES[...]) and does not open an array.
static func _follows_value(expr: String, bracket: int) -> bool:
	var at := bracket - 1
	while at >= 0 and expr[at] == " ":
		at -= 1
	return at >= 0 and (_is_word(expr[at]) or expr[at] == ")" or expr[at] == "]")


static func _is_word(c: String) -> bool:
	return c == "_" or (c >= "0" and c <= "9") or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")


## Counts of the offences under `dir` (game/ui/*.gd), keyed "file<TAB>line text".
static func count_dir(dir: String) -> Dictionary:
	var counts := {}
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".gd"):
			continue
		for offence in offences(FileAccess.get_file_as_string("%s/%s" % [dir, file])):
			var key := "%s\t%s" % [file, offence["text"]]
			counts[key] = int(counts.get(key, 0)) + 1
	return counts


## The baseline file: one "file<TAB>count<TAB>line text" per line, # comments allowed.
static func parse_baseline(text: String) -> Dictionary:
	var counts := {}
	for line in text.split("\n"):
		if line.strip_edges() == "" or line.begins_with("#"):
			continue
		var parts := line.trim_suffix("\r").split("\t", true, 2)
		counts["%s\t%s" % [parts[0], parts[2]]] = int(parts[1])
	return counts


## The baseline file text for `counts`, sorted so a regenerated file diffs cleanly.
static func format_baseline(counts: Dictionary) -> String:
	var keys := counts.keys()
	keys.sort()
	var out := ""
	for key: String in keys:
		var parts := key.split("\t", true, 1)
		out += "%s\t%d\t%s\n" % [parts[0], counts[key], parts[1]]
	return out


## {"new": keys with more occurrences than the baseline allows, "gone": keys
## with fewer than it lists}, so the baseline only ever shrinks.
static func diff(current: Dictionary, baseline: Dictionary) -> Dictionary:
	var added: Array[String] = []
	var gone: Array[String] = []
	for key: String in current:
		if int(current[key]) > int(baseline.get(key, 0)):
			added.append(key.replace("\t", " | "))
	for key: String in baseline:
		if int(current.get(key, 0)) < int(baseline[key]):
			gone.append(key.replace("\t", " | "))
	added.sort()
	gone.sort()
	return {"new": added, "gone": gone}
