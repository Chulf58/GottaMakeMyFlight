class_name BubbleWords
extends RefCounted
## A passenger's speech bubble in the player's words. PassengerSim.bubble_text()
## and BubbleDeclutter.LATE_TEXT stay English: they key the bubble's rank and the
## tests. PassengerViews calls say() at the moment it sets a bubble's text and
## measures the translated text (decision translation-format-po-gettext-files-
## with-tr-and-tr-n-for-all). Words.msgids() lists every English bubble text
## inside tr() so POT generation finds it; test_bubble_words.gd checks the list
## against the sim's texts.

const CONTEXT := "speech bubble"

static var _words := Words.new()


## `english`, a bubble text the sim gave, in the player's words; "" stays "".
static func say(english: String) -> String:
	if english == "":
		return ""
	return TranslationServer.translate(english, CONTEXT)


## Every English bubble text the sim can give, for the completeness test.
static func msgids() -> Array[String]:
	return _words.msgids()


class Words:
	extends RefCounted

	## Never called: every bubble text inside tr(), so POT generation finds it.
	func msgids() -> Array[String]:
		return [
			tr("I'm late!", "speech bubble"),
			tr("Missed my flight!", "speech bubble"),
			tr("Where is check-in?", "speech bubble"),
			tr("Where is security?", "speech bubble"),
			tr("Queue full", "speech bubble"),
			tr("I can't get there", "speech bubble"),
			tr("The exit is blocked", "speech bubble"),
			tr("The gate is full", "speech bubble"),
			tr("Check-in is closed", "speech bubble"),
			tr("Security is closed", "speech bubble"),
			tr("Gate is closed", "speech bubble"),
			tr("Forgot my belt!", "speech bubble"),
			tr("Keys in pocket!", "speech bubble"),
			tr("Coins in pocket!", "speech bubble"),
			tr("Oversized shampoo!", "speech bubble"),
			tr("Too much liquid!", "speech bubble"),
			tr("Forgot my water bottle!", "speech bubble"),
		]
