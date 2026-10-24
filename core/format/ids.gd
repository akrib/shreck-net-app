extends RefCounted
## Identifiants stables (FORMAT.md §5) : préfixe-xxxxxxxx en base 32 de Crockford.

const ALPHABET := "0123456789abcdefghjkmnpqrstvwxyz"
const PREFIXES := {
	"personnage": "per", "groupe": "grp", "domaine": "dom", "lieu": "lie",
	"objet": "obj", "concept": "cpt", "soiree": "soi", "source": "src",
	"indice": "ind", "evenement": "evt", "faveur": "fav", "dossier": "dos",
}

static var _re: RegEx


static func _regex() -> RegEx:
	if _re == null:
		_re = RegEx.new()
		_re.compile("^([a-z]{2,3})-([0-9abcdefghjkmnpqrstvwxyz]{8})$")
	return _re


static func generate(prefix: String) -> String:
	var bytes := Crypto.new().generate_random_bytes(8)
	var s := prefix + "-"
	for b in bytes:
		s += ALPHABET[b % 32]
	return s


static func is_valid(id: String) -> bool:
	return _regex().search(id) != null


static func prefix_of(id: String) -> String:
	var m := _regex().search(id)
	return m.get_string(1) if m else ""
