extends RefCounted
## Normalisation de texte : minuscules sans accents, pour la recherche et la
## comparaison des noms (Obsidian compare les noms sans tenir compte de la casse).

const _ACCENTS := {
	"à": "a", "á": "a", "â": "a", "ã": "a", "ä": "a", "å": "a", "ā": "a",
	"ç": "c", "ć": "c", "č": "c",
	"è": "e", "é": "e", "ê": "e", "ë": "e", "ē": "e", "ę": "e", "ě": "e",
	"ì": "i", "í": "i", "î": "i", "ï": "i", "ī": "i",
	"ñ": "n", "ń": "n", "ň": "n",
	"ò": "o", "ó": "o", "ô": "o", "õ": "o", "ö": "o", "ø": "o", "ō": "o",
	"ù": "u", "ú": "u", "û": "u", "ü": "u", "ū": "u", "ů": "u",
	"ý": "y", "ÿ": "y",
	"ś": "s", "š": "s", "ź": "z", "ż": "z", "ž": "z", "ř": "r", "ł": "l",
	"œ": "oe", "æ": "ae", "ß": "ss",
	"’": "'", "‘": "'", "«": "\"", "»": "\"", "“": "\"", "”": "\"",
}


## Clé de comparaison d'un nom de note (insensible à la casse).
static func name_key(s: String) -> String:
	return s.strip_edges().to_lower()


## Texte replié : minuscules, sans accents, pour la recherche simple.
static func fold(s: String) -> String:
	var low := s.to_lower()
	if low.to_utf8_buffer().size() == low.length():
		return low  # texte entièrement ASCII : rien à remplacer
	for k in _ACCENTS:
		if low.contains(k):
			low = low.replace(k, _ACCENTS[k])
	return low
