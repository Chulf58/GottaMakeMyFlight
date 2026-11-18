class_name PassengerNames
extends RefCounted
## A passenger's name for the inspect card (decision follow-invitation-and-
## passenger-card-a-click-a-passenger-fir). Like WishTable's wish it is derived
## from a salted hash of the passenger id and never saved, so a save, a load and
## a replay give every passenger the same name. One international pool, in plain
## letters, and not translated: a name is the same in every language.

## Mixed into the id before hashing, apart from WishTable.SALT, so a name and a
## wish are separate draws.
const SALT := 0x2B7E1516
const FIRST: Array[String] = [
	"Aiko",
	"Amara",
	"Anders",
	"Bruno",
	"Camila",
	"Chidi",
	"Dara",
	"Diego",
	"Elif",
	"Emil",
	"Farah",
	"Felix",
	"Gita",
	"Hana",
	"Henrik",
	"Ilse",
	"Ivan",
	"Jamal",
	"Joon",
	"Kasia",
	"Kofi",
	"Lena",
	"Leo",
	"Lucia",
	"Mateo",
	"Mei",
	"Nadia",
	"Noor",
	"Olga",
	"Omar",
	"Priya",
	"Rafael",
	"Rosa",
	"Sam",
	"Sofia",
	"Tariq",
	"Thandi",
	"Tomas",
	"Uma",
	"Yuki",
]
const LAST: Array[String] = [
	"Adeyemi",
	"Andersen",
	"Banerjee",
	"Bianchi",
	"Castillo",
	"Chen",
	"Costa",
	"Dubois",
	"Fischer",
	"Garcia",
	"Haddad",
	"Ivanov",
	"Jensen",
	"Kamau",
	"Kim",
	"Kowalski",
	"Larsen",
	"Lopez",
	"Mbeki",
	"Mori",
	"Murphy",
	"Nakamura",
	"Novak",
	"Okafor",
	"Ortiz",
	"Patel",
	"Petrov",
	"Quinn",
	"Rossi",
	"Santos",
	"Schmidt",
	"Silva",
	"Singh",
	"Tanaka",
	"Torres",
	"Ueda",
	"Vargas",
	"Wagner",
	"Yilmaz",
	"Zhang",
]


## The name of passenger `passenger_id`: a first and a last name.
static func name_of(passenger_id: int) -> String:
	var drawn := _mix(_mix(passenger_id) ^ SALT)
	var first: String = FIRST[drawn % FIRST.size()]
	var last: String = LAST[_mix(drawn ^ SALT) % LAST.size()]
	return "%s %s" % [first, last]


## A 32-bit integer mixer (a non-negative result), the one WishTable uses.
static func _mix(value: int) -> int:
	var x := value & 0xFFFFFFFF
	x = ((x >> 16) ^ x) * 0x45D9F3B & 0xFFFFFFFF
	x = ((x >> 16) ^ x) * 0x45D9F3B & 0xFFFFFFFF
	return (x >> 16) ^ x
