class_name ListWords
extends RefCounted
## Names joined into one list in the player's language: "Oslo", "Oslo and
## Rome", "Oslo, Rome and Paris". The joins follow CLDR's list patterns (the
## data behind ICU's ListFormatter and JavaScript's Intl.ListFormat): one msgid
## for a list of two, and a start, middle and end join for three or more, each
## in its own context, so a translator sets the conjunction and every
## separator. A list of four reads start(a, middle(b, end(c, d))).
##
## The items come already in the player's words, and nothing here changes
## their case. Static code cannot call tr(), so the joins go through a Words.


## `items` as one list in the player's language, or "" for none.
static func join(items: PackedStringArray) -> String:
	var words := Words.new()
	var count := items.size()
	if count < 3:
		return words.two(items[0], items[1]) if count == 2 else "".join(items)
	var text := words.end(items[count - 2], items[count - 1])
	for at in range(count - 3, 0, -1):
		text = words.middle(items[at], text)
	return words.start(items[0], text)


## tr() is an instance method, so the static join asks a Words.
class Words:
	extends RefCounted

	func two(first: String, second: String) -> String:
		return tr("{first} and {second}", "list of two").format({"first": first, "second": second})

	func start(first: String, rest: String) -> String:
		return tr("{first}, {rest}", "list start").format({"first": first, "rest": rest})

	func middle(item: String, rest: String) -> String:
		return tr("{item}, {rest}", "list middle").format({"item": item, "rest": rest})

	func end(item: String, last: String) -> String:
		return tr("{item} and {last}", "list end").format({"item": item, "last": last})
