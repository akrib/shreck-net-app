extends RefCounted
## Noms de fichiers mal encodés (« Kr├Âner » pour « Kröner ») : de l'UTF-8 lu
## comme de l'OEM 850 (code page DOS d'Europe de l'Ouest), ce que font certains
## extracteurs de zip sous Windows quand l'archive ne déclare pas l'UTF-8.
## `fix()` rend le nom d'origine ; il ne touche qu'aux suites qui commencent par
## un caractère de dessin de boîte (├, ─, ┬…), jamais aux accents ordinaires.

## Octets 0x80 à 0xFF de l'OEM 850, dans l'ordre.
const CP850_HIGH := "ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜø£Ø×ƒáíóúñÑªº¿®¬½¼¡«»░▒▓│┤ÁÂÀ©╣║╗╝¢¥┐└┴┬├─┼ãÃ╚╔╩╦╠═╬¤ðÐÊËÈıÍÎÏ┘┌█▄¦Ì▀ÓßÔÒõÕµþÞÚÛÙýÝ¯´\u00ad±‗¾¶§÷¸°¨·¹³²■\u00a0"


## Le nom contient-il une suite mal encodée ?
static func suspect(s: String) -> bool:
	for i in s.length():
		var u := s.unicode_at(i)
		if u >= 0x2500 and u <= 0x257F:
			return true
	return false


## Nom réparé, ou le nom tel quel s'il n'y a rien à réparer. Seules les lettres
## codées sur deux octets en UTF-8 (accents latins, ę, ł, ő…) sont concernées.
static func fix(s: String) -> String:
	if not suspect(s):
		return s
	var out := ""
	var i := 0
	while i < s.length():
		var u := s.unicode_at(i)
		if u >= 0x2500 and u <= 0x257F and i + 1 < s.length():
			var lead := CP850_HIGH.find(s[i])
			var cont := CP850_HIGH.find(s[i + 1])
			if lead >= 0x42 and lead <= 0x5F and cont >= 0 and cont <= 0x3F:
				out += PackedByteArray([0x80 + lead, 0x80 + cont]).get_string_from_utf8()
				i += 2
				continue
		out += s[i]
		i += 1
	return out
