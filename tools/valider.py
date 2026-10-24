#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Validateur du format Nosferatu, version 1 (voir FORMAT.md).

Usage :
  python valider.py <coffre_ou_lot>
  python valider.py <lot> --annuaire-externe annuaire.json --strict
  python valider.py <coffre> --generer-annuaire annuaire.json
  python valider.py --nouveaux-ids per 5

Ne modifie jamais aucun fichier. Code de sortie : 0 sans erreur, 1 s'il y a
des erreurs, 2 en cas de problème d'utilisation.
Dépendance : PyYAML (pip install pyyaml).
"""
import argparse
import datetime as _dt
import difflib
import json
import os
import re
import secrets
import sys
import unicodedata
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    print("PyYAML est requis : pip install pyyaml", file=sys.stderr)
    sys.exit(2)

FORMAT_SCHEMA = 1

# --------------------------------------------------------------------------
# Vocabulaires par défaut (surchargés par .nosferatu/config.json s'il existe)
# --------------------------------------------------------------------------
ALPHABET = "0123456789abcdefghjkmnpqrstvwxyz"
ID_RE = re.compile(r"^([a-z]{2,3})-([0-9abcdefghjkmnpqrstvwxyz]{8})$")

PREFIXES = {
    "personnage": "per", "groupe": "grp", "domaine": "dom", "lieu": "lie",
    "objet": "obj", "concept": "cpt", "soiree": "soi", "source": "src",
    "indice": "ind", "evenement": "evt", "faveur": "fav", "dossier": "dos",
    "en_cours": "enc",
}
DOSSIERS_ATTENDUS = {
    "personnage": "Personnages", "groupe": "Groupes", "domaine": "Domaines",
    "lieu": "Lieux", "objet": "Objets", "concept": "Concepts",
    "soiree": "Soirees", "source": "Sources", "indice": "Indices",
    "evenement": "Evenements", "faveur": "Faveurs", "dossier": "Dossiers",
    "en_cours": "En cours",
}

STATUTS_INDICE = ["non_verifie", "corrobore", "conteste", "refute", "obsolete"]
NIVEAUX = ["triviale", "mineure", "majeure", "sang", "vie"]
FIABILITES = ["A", "B", "C", "D", "E", "F"]

VOCAB_DEFAUT = {
    "personnage.statut": ["actif", "torpeur", "disparu", "mort_finale", "inconnu"],  # torpeur : format 1.5
    "personnage.identite": ["connue", "incertaine", "inconnue"],
    "personnage.sanctions": ["chasse_au_sang", "parjure", "banni", "liste_ecarlate", "paria"],
    "personnage.nature": ["vampire", "goule", "revenant", "mortel", "chasseur", "loup_garou", "mage",
                          "fae", "fantome", "demon", "autre"],
    "personnage.rang": ["venerable", "ancien", "ancilla", "nouveau_ne", "infant"],
    "concept.nature": ["discipline", "poste", "tradition", "notion", "rituel", "autre"],
    "groupe.nature": ["clan", "lignee", "secte", "faction", "coterie", "meute", "organisation", "autre"],
    "soiree.nature": ["assemblee", "elysium", "conclave", "reunion", "autre"],
    "source.nature": ["presse", "forum", "discord", "conversation", "document", "note", "analyse"],
    "indice.statut": STATUTS_INDICE,
    "evenement.statut": STATUTS_INDICE,
    "faveur.niveau": NIVEAUX,
    "faveur.statut": ["active", "reclamee", "soldee", "ignoree", "suspendue", "annulee"],
    "dossier.statut": ["ouvert", "en_pause", "resolu", "abandonne"],
    "dossier.priorite": ["haute", "moyenne", "basse"],
    "en_cours.statut": ["a_traiter", "traitee"],
    "element.nature": ["observe", "rapporte", "rumeur", "deduction", "hypothese"],
    "mouvement.mv": ["creation", "reclamation", "paiement", "ignoree", "nouveau_creancier",
                     "nouveau_debiteur", "reduction", "annulation", "suspension", "retablissement"],
    "mouvement.motif": ["echange", "mort_finale", "parjure", "chasse_au_sang", "mort_simulee",
                        "domaine_parjure", "autre"],
}

RELATIONS_DEFAUT = {
    "allie": {"de": ["personnage", "groupe"], "vers": ["personnage", "groupe"]},
    "ennemi": {"de": ["personnage", "groupe"], "vers": ["personnage", "groupe"]},
    "rival": {"de": ["personnage", "groupe"], "vers": ["personnage", "groupe"]},
    "lie_a": {"de": [], "vers": []},
    "membre_de": {"de": ["personnage"], "vers": ["groupe"]},
    "dirige": {"de": ["personnage"], "vers": ["groupe", "domaine", "lieu"]},
    "sire_de": {"de": ["personnage"], "vers": ["personnage"]},
    "mentor_de": {"de": ["personnage"], "vers": ["personnage"]},
    "contact_de": {"de": ["personnage"], "vers": ["personnage"]},
    "sert": {"de": ["personnage"], "vers": ["personnage", "groupe"]},
    "protege": {"de": ["personnage", "groupe"], "vers": ["personnage", "groupe"]},
    "chantage": {"de": ["personnage"], "vers": ["personnage"]},
    "influence": {"de": ["personnage", "groupe"], "vers": []},
    "lien_de_sang": {"de": ["personnage"], "vers": ["personnage"]},
    "present_a": {"de": ["personnage"], "vers": ["soiree"]},
    "possede": {"de": ["personnage", "groupe"], "vers": ["objet", "lieu"]},
    "reside_a": {"de": ["personnage"], "vers": ["lieu", "domaine"]},
    "reconnait": {"de": ["personnage"], "vers": ["personnage"]},
    "sobriquet": {"de": ["personnage"], "vers": ["personnage"]},
    "nomme": {"de": ["personnage"], "vers": ["personnage"]},
}

DOSSIERS_IGNORES_DEFAUT = ["_Import", "_Conflits", "Modeles", "Tableaux", "Pieces"]
DOSSIERS_TOUJOURS_IGNORES = {".git", ".obsidian", ".nosferatu", ".trash"}

# --------------------------------------------------------------------------
# Types de propriétés (un type par nom dans tout le coffre, comme Obsidian)
# --------------------------------------------------------------------------
TEXTE, LISTE, NOMBRE, CASE, DATE = "texte", "liste", "nombre", "case", "date"
TYPES_PROPRIETES = {
    "type": TEXTE, "id": TEXTE, "schema": NOMBRE, "aliases": LISTE, "tags": LISTE,
    "cssclasses": LISTE, "statut": TEXTE, "nature": TEXTE, "clan": TEXTE,
    "domaine": TEXTE, "sire": TEXTE, "identite": TEXTE, "fiabilite": TEXTE,
    "secte": TEXTE, "rang": TEXTE, "generation": NOMBRE, "disciplines": LISTE, "influences": LISTE,
    "region": TEXTE, "detenteur": TEXTE, "lieu": TEXTE, "canal": TEXTE,
    "auteur": TEXTE, "rapporteur": TEXTE, "soiree": TEXTE, "url": TEXTE,
    "relation": TEXTE, "de": TEXTE, "vers": TEXTE, "niveau": TEXTE,
    "debiteur": TEXTE, "creancier": TEXTE, "harpie": TEXTE, "priorite": TEXTE,
    "question": TEXTE, "date_floue": TEXTE,
    "sanctions": LISTE, "peut_etre": LISTE, "titres": LISTE, "presents": LISTE,
    "presents_incertains": LISTE, "absents": LISTE, "pour": LISTE, "contre": LISTE,
    "sujets": LISTE, "participants": LISTE, "indices": LISTE, "devenue": LISTE,
    "credibilite": NOMBRE, "moi_present": CASE, "enregistree": CASE,
    "transferable": CASE, "fiche_reconnaissance": CASE, "date": DATE,
    # format 1.3
    "preseance": LISTE, "rapport": LISTE, "fusionnee_dans": TEXTE, "ancien_type": TEXTE,
    "ancien_id": TEXTE, "date_fusion": DATE,
}
# Propriétés qui doivent contenir un lien (et type attendu de la cible).
PROPS_LIEN = {
    "clan": ["groupe"], "domaine": ["domaine"], "sire": ["personnage"],
    "detenteur": ["personnage", "groupe"], "lieu": ["lieu"],
    "rapporteur": ["personnage"], "soiree": ["soiree"], "de": None, "vers": None,
    "secte": ["groupe"], "fusionnee_dans": None,
    "debiteur": ["personnage"], "creancier": ["personnage"], "harpie": ["personnage"],
}
PROPS_LISTE_LIENS = {
    "peut_etre": ["personnage"], "presents": ["personnage"],
    "presents_incertains": ["personnage"], "absents": ["personnage"],
    "sujets": None, "participants": ["personnage", "groupe"], "indices": ["indice"],
    "devenue": None, "disciplines": ["concept"], "preseance": ["groupe"], "rapport": None,
}
PROPS_REFS_ELEMENTS = {"pour", "contre"}

SPEC_TYPES = {
    "personnage": {"oblig": [], "autorisees": ["clan", "domaine", "statut", "sanctions", "identite",
                                              "peut_etre", "sire", "titres", "fiabilite", "nature",
                                              "secte", "rang", "generation", "disciplines", "influences"]},
    "groupe": {"oblig": [], "autorisees": ["nature", "domaine", "clan", "secte", "disciplines"]},
    "domaine": {"oblig": [], "autorisees": ["region", "preseance"]},
    "lieu": {"oblig": [], "autorisees": ["nature", "domaine"]},
    "objet": {"oblig": [], "autorisees": ["nature", "detenteur", "lieu"]},
    "concept": {"oblig": [], "autorisees": ["nature", "secte"]},
    "soiree": {"oblig": ["date", "domaine"],
               "autorisees": ["nature", "lieu", "moi_present", "presents", "presents_incertains",
                              "absents", "fiabilite", "rapport"]},
    "source": {"oblig": ["nature", "fiabilite"], "date_requise": True,
               "autorisees": ["domaine", "canal", "auteur", "rapporteur", "soiree", "url"]},
    # `pour` est obligatoire, sauf pour une hypothèse de dossier (format 1.4) : voir _valider_indice
    "indice": {"oblig": ["statut", "credibilite"],
               "autorisees": ["pour", "contre", "sujets", "relation", "de", "vers"]},
    "evenement": {"oblig": ["statut", "credibilite"], "date_requise": True,
                  "autorisees": ["domaine", "lieu", "participants", "pour", "contre"]},
    "faveur": {"oblig": ["niveau", "debiteur", "creancier", "statut", "credibilite"],
               "date_requise": True,
               "autorisees": ["domaine", "harpie", "enregistree", "transferable",
                              "fiche_reconnaissance", "pour"]},
    "dossier": {"oblig": ["statut", "question"], "autorisees": ["priorite", "sujets", "indices"]},
    "en_cours": {"oblig": [], "autorisees": ["domaine", "statut", "devenue"]},
}
COMMUNES = ["type", "id", "schema", "aliases", "tags", "cssclasses", "date", "date_floue"]

# --------------------------------------------------------------------------
# Expressions régulières
# --------------------------------------------------------------------------
_PT = r"[0-9X]{4}(?:-(?:0[1-9]|1[0-2]|XX)(?:-(?:0[1-9]|[12][0-9]|3[01]|XX))?)?[~?%]?"
EDTF_RE = re.compile(rf"^(?:inconnue|{_PT}|{_PT}/{_PT}|\.\./{_PT}|{_PT}/\.\.)$")
DATE_EXACTE_RE = re.compile(r"^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$")
LIEN_RE = re.compile(r"(!?)\[\[([^\[\]]+?)\]\]")
LIEN_SEUL_RE = re.compile(r"^\[\[([^\[\]]+?)\]\]$")
BLOC_FIN_RE = re.compile(r"\s\^([A-Za-z0-9-]+)\s*$")
TITRE_RE = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
CHAMP_DEBUT_RE = re.compile(r"\[([a-z_]+)::\s*")
CLE_RE = re.compile(r"^[a-z][a-z0-9_]*$")
FENCE_RE = re.compile(r"^\s*(```|~~~)")
ITEM_RE = re.compile(r"^[-*+]\s+(.*)$")
TACHE_RE = re.compile(r"^\s*[-*+]\s+\[[ xX]\]\s")
CODE_INLINE_RE = re.compile(r"`[^`]*`")
CARACTERES_INTERDITS = set('\\/:*?"<>|#^[]')

# --------------------------------------------------------------------------
# Outils
# --------------------------------------------------------------------------


def nouvel_id(prefixe):
    return prefixe + "-" + "".join(secrets.choice(ALPHABET) for _ in range(8))


def sans_accents(s):
    return "".join(c for c in unicodedata.normalize("NFKD", s) if not unicodedata.combining(c))


def cle_nom(nom):
    """Clé de comparaison des noms de notes (comme Obsidian : insensible à la casse)."""
    return unicodedata.normalize("NFC", nom).casefold()


def decouper_lien(contenu):
    """'Note#^bloc|alias' -> ('Note', '^bloc' ou 'Titre' ou None)."""
    cible = contenu.split("|", 1)[0]
    sous = None
    if "#" in cible:
        cible, sous = cible.split("#", 1)
    cible = cible.strip()
    if "/" in cible:
        cible = cible.rsplit("/", 1)[1]
    if cible.lower().endswith(".md"):
        cible = cible[:-3]
    return cible, (sous.strip() if sous else None)


class ChargeurSansDoublon(yaml.SafeLoader):
    pass


def _construire_mapping(loader, node, deep=False):
    vues = set()
    for cle_node, _ in node.value:
        cle = loader.construct_object(cle_node, deep=deep)
        if cle in vues:
            raise yaml.constructor.ConstructorError(
                None, None, f"clé en double : « {cle} »", cle_node.start_mark)
        vues.add(cle)
    return loader.construct_mapping(node, deep)


ChargeurSansDoublon.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construire_mapping)
# Les dates restent du texte (comme dans Obsidian) : elles sont vérifiées par expression régulière.
ChargeurSansDoublon.yaml_implicit_resolvers = {
    k: [(tag, rx) for tag, rx in v if tag != "tag:yaml.org,2002:timestamp"]
    for k, v in yaml.SafeLoader.yaml_implicit_resolvers.items()
}


class Rapport:
    NIVEAUX = ("ERREUR", "AVERTISSEMENT", "INFO")

    def __init__(self, strict=False):
        self.items = []
        self.strict = strict

    def ajouter(self, niveau, fichier, ligne, message, strict_erreur=False):
        if strict_erreur and self.strict and niveau == "AVERTISSEMENT":
            niveau = "ERREUR"
        self.items.append((niveau, fichier or "", ligne or 0, message))

    def erreur(self, f, l, m):
        self.ajouter("ERREUR", f, l, m)

    def avert(self, f, l, m, strict_erreur=False):
        self.ajouter("AVERTISSEMENT", f, l, m, strict_erreur)

    def info(self, f, l, m):
        self.ajouter("INFO", f, l, m)

    def compte(self, niveau):
        return sum(1 for i in self.items if i[0] == niveau)


# --------------------------------------------------------------------------
# Lecture d'une note
# --------------------------------------------------------------------------


class Note:
    def __init__(self, chemin, rel):
        self.chemin = chemin
        self.rel = rel
        self.nom = unicodedata.normalize("NFC", Path(rel).stem)
        self.fm = None          # dict des propriétés
        self.fm_ok = False
        self.fm_lignes = {}     # clé -> numéro de ligne
        self.corps_debut = 1
        self.type = None
        self.id = None
        self.blocs = {}         # id de bloc -> ligne
        self.liens = []         # (cible, sous, ligne, origine)
        self.elements = []      # dicts
        self.mouvements = []    # dicts


def lire_note(chemin, rel, rapport):
    note = Note(chemin, rel)
    try:
        brut = chemin.read_bytes()
    except OSError as e:
        rapport.erreur(rel, 0, f"lecture impossible : {e}")
        return note
    if brut.startswith(b"\xef\xbb\xbf"):
        rapport.avert(rel, 1, "le fichier commence par un BOM UTF-8 (à retirer)")
        brut = brut[3:]
    try:
        texte = brut.decode("utf-8")
    except UnicodeDecodeError as e:
        rapport.erreur(rel, 0, f"le fichier n'est pas en UTF-8 ({e})")
        return note
    texte = texte.replace("\r\n", "\n").replace("\r", "\n")
    lignes = texte.split("\n")

    # ---- frontmatter
    if lignes and lignes[0].strip() == "---":
        fin = None
        for i in range(1, len(lignes)):
            if lignes[i].strip() == "---":
                fin = i
                break
        if fin is None:
            rapport.erreur(rel, 1, "frontmatter non fermé (ligne « --- » finale manquante)")
            note.corps_debut = len(lignes) + 1
            return note
        fm_lignes = lignes[1:fin]
        note.corps_debut = fin + 2
        _analyser_frontmatter(note, fm_lignes, rapport)
        corps = lignes[fin + 1:]
    else:
        corps = lignes
        note.corps_debut = 1
    _analyser_corps(note, corps, rapport)
    return note


def _analyser_frontmatter(note, fm_lignes, rapport):
    rel = note.rel
    for i, l in enumerate(fm_lignes, start=2):
        m = re.match(r"^([^\s#:][^:]*):", l)
        if m:
            note.fm_lignes.setdefault(m.group(1).strip(), i)
        if re.match(r"^\s*[^\s#][^:]*:\s*[|>][+-]?\d*\s*(#.*)?$", l):
            rapport.erreur(rel, i, "texte sur plusieurs lignes (| ou >) interdit dans les propriétés")
        if re.search(r":\s*[&*][A-Za-z0-9_-]+", l) or re.search(r"(^|\s)!!\w+", l):
            rapport.erreur(rel, i, "ancre, alias ou étiquette YAML (&, *, !!) interdit")
    texte = "\n".join(fm_lignes)
    if not texte.strip():
        note.fm = {}
        note.fm_ok = True
        return
    try:
        donnees = yaml.load(texte, Loader=ChargeurSansDoublon)
    except (ValueError, TypeError) as e:
        rapport.erreur(rel, 2, f"valeur YAML impossible à interpréter : {e}")
        return
    except yaml.YAMLError as e:
        ligne = 0
        mark = getattr(e, "problem_mark", None) or getattr(e, "context_mark", None)
        if mark is not None:
            ligne = mark.line + 2
        msg = getattr(e, "problem", None) or str(e).split("\n")[0]
        rapport.erreur(rel, ligne, f"YAML illisible : {msg}")
        return
    if donnees is None:
        donnees = {}
    if not isinstance(donnees, dict):
        rapport.erreur(rel, 2, "le frontmatter doit être une suite de « clé: valeur »")
        return
    ok = True
    for cle, val in donnees.items():
        ligne = note.fm_lignes.get(str(cle), 2)
        if not isinstance(cle, str):
            rapport.erreur(rel, ligne, f"nom de propriété invalide : {cle!r}")
            ok = False
            continue
        if isinstance(val, dict):
            rapport.erreur(rel, ligne, f"« {cle} » : objet imbriqué interdit (non géré par Obsidian)")
            ok = False
        elif isinstance(val, list):
            if val and all(isinstance(x, list) for x in val) and \
                    all(len(x) == 1 and isinstance(x[0], (list, str)) for x in val):
                rapport.erreur(rel, ligne, f"« {cle} » : lien non entre guillemets "
                                           f"(écrire \"[[Nom]]\")")
                ok = False
            elif any(isinstance(x, (dict, list)) for x in val):
                rapport.erreur(rel, ligne, f"« {cle} » : liste imbriquée ou d'objets interdite")
                ok = False
    note.fm = donnees
    note.fm_ok = ok


def _lire_champs(ligne):
    """Extrait les champs [clé:: valeur]. Retourne (champs, morceaux_a_retirer, erreurs)."""
    champs, spans, erreurs = {}, [], []
    i = 0
    while True:
        m = CHAMP_DEBUT_RE.search(ligne, i)
        if not m:
            break
        if m.start() > 0 and ligne[m.start() - 1] == "[":
            i = m.end()
            continue
        j = m.end()
        prof = 0
        while j < len(ligne):
            if ligne.startswith("[[", j):
                prof += 1
                j += 2
                continue
            if ligne.startswith("]]", j) and prof > 0:
                prof -= 1
                j += 2
                continue
            if ligne[j] == "]" and prof == 0:
                break
            j += 1
        if j >= len(ligne):
            erreurs.append(f"champ « {m.group(1)} » non fermé (crochet ] manquant)")
            break
        cle = m.group(1)
        if cle in champs:
            erreurs.append(f"champ « {cle} » présent deux fois")
        champs[cle] = ligne[m.end():j].strip()
        spans.append((m.start(), j + 1))
        i = j + 1
    return champs, spans, erreurs


def _analyser_corps(note, corps, rapport):
    rel = note.rel
    section = None            # 'elements' | 'mouvements' | None
    dans_code = False
    dernier_item = None
    for k, brute in enumerate(corps):
        num = note.corps_debut + k
        if FENCE_RE.match(brute):
            dans_code = not dans_code
            continue
        if dans_code:
            continue
        ligne = CODE_INLINE_RE.sub("", brute)
        m_titre = TITRE_RE.match(ligne)
        if m_titre:
            niv = len(m_titre.group(1))
            titre = sans_accents(m_titre.group(2)).strip().casefold()
            if niv <= 2:
                section = None
                if niv == 2 and titre in ("elements", "mouvements"):
                    section = titre
            dernier_item = None
        # liens (partout)
        for mlien in LIEN_RE.finditer(ligne):
            cible, sous = decouper_lien(mlien.group(2))
            note.liens.append((cible, sous, num, "corps"))
        # blocs (partout)
        mb = BLOC_FIN_RE.search(ligne)
        if mb:
            bid = mb.group(1)
            if bid in note.blocs:
                rapport.erreur(rel, num, f"identifiant de bloc ^{bid} en double dans la note")
            note.blocs[bid] = num
        if section is None or m_titre:
            continue
        if not ligne.strip():
            continue
        if TACHE_RE.match(ligne):
            rapport.avert(rel, num, "tâche dans une section structurée : la placer sous « ## À faire »")
            continue
        m_item = ITEM_RE.match(ligne)
        if m_item:
            dernier_item = _lire_ligne_structuree(note, section, ligne, num, rapport)
            continue
        if ligne[:1] in (" ", "\t") and dernier_item is not None:
            continue  # commentaire libre indenté
        rapport.avert(rel, num, "contenu non structuré dans la section (conservé, non interprété)")


def _lire_ligne_structuree(note, section, ligne, num, rapport):
    rel = note.rel
    champs, spans, erreurs = _lire_champs(ligne)
    for e in erreurs:
        rapport.erreur(rel, num, e)
    reste = ligne
    for a, b in sorted(spans, reverse=True):
        reste = reste[:a] + reste[b:]
    mb = BLOC_FIN_RE.search(reste)
    bloc = None
    if mb:
        bloc = mb.group(1)
        reste = reste[:mb.start()]
    enonce = ITEM_RE.match(reste.strip() + " ")
    enonce = (enonce.group(1) if enonce else reste).strip()
    entree = {"ligne": num, "champs": champs, "bloc": bloc, "enonce": enonce, "note": note}
    if section == "elements":
        note.elements.append(entree)
    else:
        note.mouvements.append(entree)
    for cle, val in champs.items():
        for mlien in LIEN_RE.finditer(val):
            cible, sous = decouper_lien(mlien.group(2))
            note.liens.append((cible, sous, num, f"champ {cle}"))
    return entree


# --------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------


class Validateur:
    def __init__(self, racine, rapport, annuaire_externe=None):
        self.racine = racine
        self.rapport = rapport
        self.notes = []
        self.fichiers = {}       # cle_nom(nom complet) -> rel  (pièces jointes)
        self.par_nom = {}        # cle_nom(stem) -> [Note]
        self.par_id = {}         # id -> [rel]
        self.blocs = {}          # id bloc -> (rel, nom_note, type 'el'|'mv'|'autre')
        self.elements = {}       # id bloc -> entree
        self.externe = annuaire_externe or {"notes": [], "fichiers": []}
        self.ext_noms = {}       # cle_nom -> dict
        self.ext_blocs = {}      # id -> nom
        self.vocab = {k: list(v) for k, v in VOCAB_DEFAUT.items()}
        self.relations = dict(RELATIONS_DEFAUT)
        self.dossiers_ignores = list(DOSSIERS_IGNORES_DEFAUT)
        self.nb_libres = 0
        self.nb_illisibles = 0
        self._charger_config()

    # ---- configuration
    def _charger_config(self):
        cfg = self.racine / ".nosferatu" / "config.json"
        if not cfg.exists():
            return
        try:
            data = json.loads(cfg.read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            self.rapport.erreur(".nosferatu/config.json", 0, f"configuration illisible : {e}")
            return
        if data.get("schema", FORMAT_SCHEMA) > FORMAT_SCHEMA:
            self.rapport.erreur(".nosferatu/config.json", 0,
                                "version de format plus récente que ce validateur")
        # Les listes du coffre complètent celles du format (FORMAT §11) : rien n'est retiré.
        for cle, val in (data.get("valeurs") or {}).items():
            if isinstance(val, list):
                base = self.vocab.get(cle, [])
                self.vocab[cle] = base + [str(v) for v in val if str(v) not in base]
        rels = data.get("relations")
        if isinstance(rels, list):
            for r in rels:
                if isinstance(r, dict) and r.get("code"):
                    self.relations[r["code"]] = {"de": r.get("de", []), "vers": r.get("vers", [])}
        if isinstance(data.get("dossiers_ignores"), list):
            self.dossiers_ignores = [str(d) for d in data["dossiers_ignores"]]

    # ---- collecte
    def collecter(self):
        # Mêmes règles que l'application : les noms commençant par « . » sont
        # ignorés ; dans les dossiers ignorés (Pieces, Modeles…), aucun fichier
        # n'est lu comme note, mais tous comptent comme pièces jointes (un lien
        # vers eux n'est pas cassé, comme dans Obsidian).
        for dossier, sous, fichiers in os.walk(self.racine):
            d_rel = Path(dossier).relative_to(self.racine)
            sous[:] = sorted(s for s in sous if s not in DOSSIERS_TOUJOURS_IGNORES
                             and not s.startswith("."))
            dans_ignore = d_rel != Path(".") and d_rel.parts[0] in self.dossiers_ignores
            for f in sorted(fichiers):
                if f.startswith("."):
                    continue
                chemin = Path(dossier) / f
                rel = chemin.relative_to(self.racine).as_posix()
                if dans_ignore:
                    self.fichiers.setdefault(cle_nom(f), rel)
                elif f.lower().endswith(".md"):
                    self._verifier_nom_fichier(rel, Path(f).stem)
                    self.notes.append(lire_note(chemin, rel, self.rapport))
                else:
                    self.fichiers[cle_nom(f)] = rel
        for e in self.externe.get("notes", []):
            self.ext_noms[cle_nom(e.get("nom", ""))] = e
            for b in e.get("blocs", []):
                self.ext_blocs[b] = e.get("nom")
        for f in self.externe.get("fichiers", []):
            self.fichiers.setdefault(cle_nom(Path(f).name), f)

    def _verifier_nom_fichier(self, rel, stem):
        if unicodedata.normalize("NFC", stem) != stem:
            self.rapport.avert(rel, 0, "nom de fichier non normalisé (NFC) : accents décomposés")
        interdits = sorted(set(c for c in stem if c in CARACTERES_INTERDITS))
        if interdits:
            self.rapport.erreur(rel, 0, f"caractères interdits dans le nom : {' '.join(interdits)}")
        if stem != stem.strip() or stem.endswith("."):
            self.rapport.erreur(rel, 0, "le nom se termine par une espace ou un point")

    # ---- index global
    def indexer(self):
        for n in self.notes:
            self.par_nom.setdefault(cle_nom(n.nom), []).append(n)
            if isinstance(n.fm, dict) and n.fm:
                t = n.fm.get("type")
                n.type = t if isinstance(t, str) else None
                i = n.fm.get("id")
                n.id = i if isinstance(i, str) else None
                if n.id:
                    self.par_id.setdefault(n.id, []).append(n.rel)
            for bid, ligne in n.blocs.items():
                genre = "el" if bid.startswith("el-") else "mv" if bid.startswith("mv-") else "autre"
                if genre != "autre" and bid in self.blocs:
                    self.rapport.erreur(n.rel, ligne,
                                        f"identifiant ^{bid} déjà utilisé dans {self.blocs[bid][0]}")
                self.blocs.setdefault(bid, (n.rel, n.nom, genre, ligne))
            for el in n.elements:
                if el["bloc"]:
                    self.elements.setdefault(el["bloc"], el)
        for cle, notes in self.par_nom.items():
            if len(notes) > 1:
                for n in notes:
                    autres = ", ".join(x.rel for x in notes if x is not n)
                    self.rapport.erreur(n.rel, 0, f"nom de note en double (aussi : {autres})")
            if cle in self.ext_noms:
                for n in notes:
                    self.rapport.erreur(n.rel, 0, "ce nom existe déjà dans le coffre "
                                        f"({self.ext_noms[cle].get('chemin', '?')})")
        # lot contre le coffre : noms presque identiques et alias qui reprennent un nom existant
        if self.ext_noms:
            ext_plis = {}
            for k, e in self.ext_noms.items():
                ext_plis.setdefault(sans_accents(k), e)
            for cle, notes in self.par_nom.items():
                proche = ext_plis.get(sans_accents(cle))
                if proche is not None and cle not in self.ext_noms:
                    for n in notes:
                        self.rapport.avert(n.rel, 0, "une note au nom presque identique existe déjà dans le coffre "
                                           f"({proche.get('chemin', '?')}) : accents ou majuscules ; gardez-en une seule")
                for n in notes:
                    for a in _liste((n.fm or {}).get("aliases")):
                        if isinstance(a, str) and cle_nom(a) in self.ext_noms:
                            self.rapport.avert(n.rel, 0, f"l'alias « {a} » est déjà le nom d'une note du coffre "
                                               f"({self.ext_noms[cle_nom(a)].get('chemin', '?')}) : deux fiches répondraient à ce nom dans les recherches")
        ext_ids = {e.get("id"): e for e in self.externe.get("notes", []) if e.get("id")}
        for i, rels in self.par_id.items():
            if len(rels) > 1:
                for r in rels:
                    self.rapport.erreur(r, 0, f"identifiant {i} en double ({', '.join(rels)})")
            if i in ext_ids:
                for r in rels:
                    self.rapport.erreur(r, 0, f"identifiant {i} déjà utilisé dans le coffre "
                                        f"({ext_ids[i].get('chemin', '?')})")
        for bid, (rel, _, genre, ligne) in self.blocs.items():
            if genre != "autre" and bid in self.ext_blocs:
                self.rapport.erreur(rel, ligne, f"identifiant ^{bid} déjà utilisé dans le coffre "
                                                f"(note « {self.ext_blocs[bid]} »)")

    # ---- résolution
    def resoudre(self, nom):
        """Retourne ('note', Note) / ('externe', dict) / ('fichier', rel) / (None, None)."""
        cle = cle_nom(nom)
        if cle in self.par_nom:
            return "note", self.par_nom[cle][0]
        if cle in self.ext_noms:
            return "externe", self.ext_noms[cle]
        if cle in self.fichiers:
            return "fichier", self.fichiers[cle]
        if cle + ".md" in self.fichiers:
            return "fichier", self.fichiers[cle + ".md"]
        return None, None

    def type_de(self, nom):
        genre, obj = self.resoudre(nom)
        if genre == "note":
            return obj.type
        if genre == "externe":
            return obj.get("type")
        return None

    def bloc_existe(self, nom_note, bid):
        if bid in self.blocs:
            return cle_nom(self.blocs[bid][1]) == cle_nom(nom_note), self.blocs[bid][:3]
        if bid in self.ext_blocs:
            return cle_nom(self.ext_blocs[bid]) == cle_nom(nom_note), (None, self.ext_blocs[bid], "el")
        return False, None

    # ---- validation générale
    def valider(self):
        for n in self.notes:
            if n.fm is None and n.corps_debut > 1:
                self.nb_illisibles += 1
                self._verifier_liens_note(n)
                continue
            if not isinstance(n.fm, dict) or not n.fm:
                self.nb_libres += 1
                self._verifier_liens_note(n)
                continue
            t = n.fm.get("type")
            if t is None:
                self.nb_libres += 1
            elif not isinstance(t, str) or t not in SPEC_TYPES:
                proche = difflib.get_close_matches(str(t), list(SPEC_TYPES), n=1, cutoff=0.75)
                if proche:
                    self.rapport.avert(n.rel, n.fm_lignes.get("type", 2),
                                       f"type « {t} » inconnu : vouliez-vous « {proche[0]} » ?")
                else:
                    self.rapport.info(n.rel, n.fm_lignes.get("type", 2),
                                      f"type « {t} » non géré : note ignorée par l'index")
                    self.nb_libres += 1
            else:
                self._valider_note_typee(n)
            self._verifier_liens_note(n)
        self._verifier_blocs_structures()

    def _ligne(self, n, cle):
        return n.fm_lignes.get(cle, 2)

    def _valider_note_typee(self, n):
        fm, rel, t = n.fm, n.rel, n.type
        spec = SPEC_TYPES[t]
        # identifiant
        i = fm.get("id")
        if i in (None, ""):
            self.rapport.avert(rel, 2, "id manquant (sera attribué par l'application)", strict_erreur=True)
        elif not isinstance(i, str) or not ID_RE.match(i):
            self.rapport.erreur(rel, self._ligne(n, "id"),
                                f"id « {i} » mal formé (attendu {PREFIXES[t]}-xxxxxxxx)")
        elif ID_RE.match(i).group(1) != PREFIXES[t]:
            self.rapport.erreur(rel, self._ligne(n, "id"),
                                f"préfixe d'id « {ID_RE.match(i).group(1)} » incohérent avec le type "
                                f"{t} (attendu {PREFIXES[t]})")
        # version
        s = fm.get("schema")
        if s is None:
            self.rapport.avert(rel, 2, "schema manquant (attendu 1)", strict_erreur=True)
        elif not isinstance(s, int) or isinstance(s, bool):
            self.rapport.erreur(rel, self._ligne(n, "schema"), "schema doit être un nombre entier")
        elif s > FORMAT_SCHEMA:
            self.rapport.erreur(rel, self._ligne(n, "schema"),
                                f"version de format {s} inconnue de ce validateur")
        # dossier attendu
        premier = rel.split("/", 1)[0] if "/" in rel else ""
        if premier and premier != DOSSIERS_ATTENDUS[t]:
            self.rapport.info(rel, 0, f"note de type {t} rangée hors du dossier "
                                      f"{DOSSIERS_ATTENDUS[t]}/ (sans conséquence)")
        # propriétés
        autorisees = set(COMMUNES) | set(spec["oblig"]) | set(spec["autorisees"])
        for cle, val in fm.items():
            ligne = self._ligne(n, cle)
            if cle not in TYPES_PROPRIETES:
                if CLE_RE.match(cle) or cle in ("aliases", "tags", "cssclasses"):
                    self.rapport.info(rel, ligne, f"propriété inconnue « {cle} » (conservée)")
                else:
                    self.rapport.avert(rel, ligne, f"nom de propriété non conforme : « {cle} »")
                continue
            if cle not in autorisees:
                self.rapport.info(rel, ligne, f"propriété « {cle} » inhabituelle pour le type {t}")
            if isinstance(val, dict) or (isinstance(val, list) and
                                         any(isinstance(x, (dict, list)) for x in val)):
                continue  # déjà signalé comme structure interdite
            self._verifier_type_propriete(n, cle, val, ligne)
        for cle in spec["oblig"]:
            if fm.get(cle) in (None, "", []):
                self.rapport.erreur(rel, 2, f"propriété obligatoire manquante : {cle}")
        # dates
        a_date, a_floue = fm.get("date") not in (None, ""), fm.get("date_floue") not in (None, "")
        if a_date and a_floue:
            self.rapport.avert(rel, self._ligne(n, "date_floue"),
                               "date et date_floue renseignées : n'en garder qu'une")
        if spec.get("date_requise") and not (a_date or a_floue):
            self.rapport.erreur(rel, 2, "date ou date_floue obligatoire (date_floue: inconnue accepté)")
        # énumérations
        self._enum(n, "statut", f"{t}.statut")
        self._enum(n, "nature", f"{t}.nature", souple=(t == "soiree"))
        self._enum(n, "identite", f"{t}.identite")
        self._enum(n, "rang", f"{t}.rang")
        self._enum(n, "niveau", f"{t}.niveau")
        self._enum(n, "priorite", f"{t}.priorite")
        if "fiabilite" in fm and fm["fiabilite"] not in (None, "") and fm["fiabilite"] not in FIABILITES:
            self.rapport.erreur(rel, self._ligne(n, "fiabilite"),
                                f"fiabilite « {fm['fiabilite']} » invalide (A à F)")
        if "credibilite" in fm and fm["credibilite"] not in (None, ""):
            c = fm["credibilite"]
            if isinstance(c, bool) or not isinstance(c, int) or not 1 <= c <= 6:
                self.rapport.erreur(rel, self._ligne(n, "credibilite"),
                                    f"credibilite « {c} » invalide (entier de 1 à 6)")
        if t == "personnage" and isinstance(fm.get("sanctions"), list):
            for v in fm["sanctions"]:
                if v not in self.vocab["personnage.sanctions"]:
                    self.rapport.avert(rel, self._ligne(n, "sanctions"), f"sanction inconnue : {v}")
        # relation d'un indice
        if t == "indice":
            r = [fm.get(k) for k in ("relation", "de", "vers")]
            if any(r) and not all(r):
                self.rapport.erreur(rel, self._ligne(n, "relation"),
                                    "relation, de et vers doivent être renseignés ensemble")
            elif all(r):
                self._verifier_relation(rel, self._ligne(n, "relation"), fm["relation"],
                                        _nom_lien(fm["de"]), _nom_lien(fm["vers"]))
        # vérifications propres au type
        getattr(self, f"_valider_{t}", lambda n: None)(n)

    def _enum(self, n, cle, vocab_cle, souple=False):
        if cle not in n.fm or n.fm[cle] in (None, "") or vocab_cle not in self.vocab:
            return
        v = n.fm[cle]
        if v not in self.vocab[vocab_cle]:
            msg = f"{cle} « {v} » hors liste ({', '.join(self.vocab[vocab_cle])})"
            if souple:
                self.rapport.info(n.rel, self._ligne(n, cle), msg)
            else:
                self.rapport.erreur(n.rel, self._ligne(n, cle), msg)

    def _verifier_type_propriete(self, n, cle, val, ligne):
        rel, attendu = n.rel, TYPES_PROPRIETES[cle]
        if val is None:
            return
        if attendu == TEXTE:
            if isinstance(val, list):
                self.rapport.erreur(rel, ligne, f"« {cle} » doit être un texte, pas une liste")
            elif not isinstance(val, str):
                if cle == "date_floue" and isinstance(val, _dt.date):
                    self.rapport.avert(rel, ligne, "date_floue contient une date exacte : utiliser "
                                                   "la propriété date, ou mettre entre guillemets")
                else:
                    self.rapport.avert(rel, ligne, f"« {cle} » : valeur {val!r} interprétée comme "
                                                   f"{type(val).__name__}, mettre entre guillemets")
            if cle == "date_floue" and not EDTF_RE.match(str(val)):
                self.rapport.erreur(rel, ligne, f"date_floue « {val} » ne respecte pas la "
                                                f"grammaire (voir FORMAT.md §7)")
            if cle in PROPS_LIEN and isinstance(val, str) and not LIEN_SEUL_RE.match(val.strip()):
                self.rapport.avert(rel, ligne, f"« {cle} » devrait être un lien \"[[Nom]]\"")
        elif attendu == LISTE:
            if not isinstance(val, list):
                self.rapport.avert(rel, ligne, f"« {cle} » devrait être une liste (Obsidian)")
                val = [val]
            for x in val:
                if not isinstance(x, str):
                    self.rapport.avert(rel, ligne, f"« {cle} » : élément {x!r} à mettre entre guillemets")
                elif (cle in PROPS_LISTE_LIENS or cle in PROPS_REFS_ELEMENTS) and \
                        not LIEN_SEUL_RE.match(x.strip()):
                    self.rapport.avert(rel, ligne, f"« {cle} » : « {x} » devrait être un lien")
        elif attendu == NOMBRE:
            if isinstance(val, bool) or not isinstance(val, (int, float)):
                self.rapport.erreur(rel, ligne, f"« {cle} » doit être un nombre")
        elif attendu == CASE:
            if not isinstance(val, bool):
                self.rapport.erreur(rel, ligne, f"« {cle} » doit valoir true ou false")
        elif attendu == DATE:
            if isinstance(val, _dt.datetime):
                self.rapport.avert(rel, ligne, "date avec heure : la propriété date attend AAAA-MM-JJ")
            elif isinstance(val, _dt.date):
                pass
            elif isinstance(val, str) and DATE_EXACTE_RE.match(val) and _date_reelle(val):
                pass
            else:
                self.rapport.erreur(rel, ligne, f"date « {val} » invalide : AAAA-MM-JJ exacte "
                                                f"(sinon utiliser date_floue)")

    # ---- par type
    def _valider_soiree(self, n):
        fm = n.fm
        pres = {cle_nom(_nom_lien(x)) for x in _liste(fm.get("presents"))}
        inc = {cle_nom(_nom_lien(x)) for x in _liste(fm.get("presents_incertains"))}
        if pres & inc:
            self.rapport.avert(n.rel, self._ligne(n, "presents_incertains"),
                               "personnage à la fois dans presents et presents_incertains")

    def _valider_source(self, n):
        if n.fm.get("nature") == "analyse":
            for el in n.elements:
                if el["champs"].get("nature") not in (None, "deduction", "hypothese"):
                    self.rapport.erreur(n.rel, el["ligne"], "une analyse ne contient que des "
                                                            "éléments deduction ou hypothese")
        if not n.elements:
            self.rapport.info(n.rel, 0, "source sans section « ## Éléments » ou sans élément")

    def _valider_evenement(self, n):
        if not _liste(n.fm.get("pour")):
            self.rapport.avert(n.rel, 2, "événement sans élément « pour » qui l'atteste")
        self._verifier_refs_elements(n)

    def _hypotheses_de_dossiers(self):
        """Noms (clés) des indices cités par la propriété `indices` d'un dossier."""
        if getattr(self, "_hyp_cache", None) is None:
            self._hyp_cache = set()
            for d in self.notes:
                if isinstance(d.fm, dict) and d.fm.get("type") == "dossier":
                    for ref in _liste(d.fm.get("indices")):
                        nom, _sous = decouper_lien(_contenu_lien(ref))
                        self._hyp_cache.add(cle_nom(nom))
        return self._hyp_cache

    def _valider_indice(self, n):
        if not _liste(n.fm.get("pour")):
            if cle_nom(n.nom) in self._hypotheses_de_dossiers():
                self.rapport.info(n.rel, self._ligne(n, "pour"),
                                  "hypothèse de dossier sans élément « pour » (à compléter)")
            else:
                self.rapport.erreur(n.rel, 2, "propriété obligatoire manquante : pour")
        self._verifier_refs_elements(n)
        if n.fm.get("statut") == "corrobore":
            notes, origines = set(), set()
            for ref in _liste(n.fm.get("pour")):
                nom, sous = decouper_lien(_contenu_lien(ref))
                notes.add(cle_nom(nom))
                bid = sous[1:] if sous and sous.startswith("^") else None
                el = self.elements.get(bid)
                if el:
                    origines.add(self._origine_element(el))
                else:
                    origines.add(("note", cle_nom(nom)))
            if len(notes) < 2:
                self.rapport.avert(n.rel, self._ligne(n, "statut"),
                                   "statut corrobore mais tous les éléments « pour » viennent "
                                   "d'une seule note")
            elif len(origines) < 2:
                self.rapport.avert(n.rel, self._ligne(n, "statut"),
                                   "statut corrobore mais tous les éléments remontent à la même "
                                   "personne : sources non indépendantes ?")

    def _origine_element(self, el):
        par = el["champs"].get("par")
        if par:
            return ("pers", cle_nom(_nom_lien(par)))
        fm = el["note"].fm or {}
        for cle in ("rapporteur", "auteur"):
            if fm.get(cle):
                return ("pers", cle_nom(_nom_lien(str(fm[cle]))))
        return ("note", cle_nom(el["note"].nom))

    def _verifier_refs_elements(self, n):
        pour = [_contenu_lien(x) for x in _liste(n.fm.get("pour"))]
        contre = [_contenu_lien(x) for x in _liste(n.fm.get("contre"))]
        for cle, refs in (("pour", pour), ("contre", contre)):
            for ref in refs:
                nom, sous = decouper_lien(ref)
                if not sous or not sous.startswith("^"):
                    self.rapport.avert(n.rel, self._ligne(n, cle),
                                       f"« {cle} » : [[{ref}]] devrait viser un élément "
                                       f"([[Note#^el-…]])")
                elif not sous[1:].startswith("el-"):
                    self.rapport.avert(n.rel, self._ligne(n, cle),
                                       f"« {cle} » : ^{sous[1:]} n'est pas un identifiant d'élément")
        commun = {cle_nom(x) for x in pour} & {cle_nom(x) for x in contre}
        if commun:
            self.rapport.avert(n.rel, self._ligne(n, "contre"), "un même élément est à la fois "
                                                                 "pour et contre")

    def _valider_faveur(self, n):
        fm, rel = n.fm, n.rel
        etat = {"statut": None, "niveau": None, "debiteur": None, "creancier": None}
        precedent = None
        finaux = {"soldee", "ignoree", "annulee"}
        if not n.mouvements:
            self.rapport.info(rel, 0, "faveur sans journal « ## Mouvements »")
            return
        for k, mv in enumerate(n.mouvements):
            c, ligne = mv["champs"], mv["ligne"]
            genre = c.get("mv")
            if k == 0 and genre != "creation":
                self.rapport.avert(rel, ligne, "le premier mouvement devrait être « creation »")
            if genre == "creation" and k > 0:
                self.rapport.avert(rel, ligne, "« creation » n'est pas le premier mouvement")
            if etat["statut"] in finaux and genre not in (None,):
                self.rapport.avert(rel, ligne, f"mouvement après un statut final ({etat['statut']})")
            if genre == "creation":
                etat["statut"] = "active"
                for cle in ("niveau", "debiteur", "creancier"):
                    if c.get(cle):
                        etat[cle] = c[cle] if cle == "niveau" else _nom_lien(c[cle])
            elif genre == "reclamation":
                if etat["statut"] not in (None, "active"):
                    self.rapport.avert(rel, ligne, f"réclamation alors que le statut est {etat['statut']}")
                etat["statut"] = "reclamee"
            elif genre == "paiement":
                etat["statut"] = "soldee"
            elif genre == "ignoree":
                etat["statut"] = "ignoree"
                if (etat["niveau"] or fm.get("niveau")) in ("majeure", "sang", "vie"):
                    self.rapport.info(rel, ligne, "faveur majeure, de sang ou de vie ignorée : le "
                                                  "débiteur perd du statut (règles du wiki)")
            elif genre == "annulation":
                etat["statut"] = "annulee"
            elif genre == "suspension":
                precedent = etat["statut"]
                etat["statut"] = "suspendue"
            elif genre == "retablissement":
                if etat["statut"] != "suspendue":
                    self.rapport.avert(rel, ligne, "rétablissement d'une faveur non suspendue")
                etat["statut"] = precedent or "active"
            elif genre == "nouveau_creancier":
                if not c.get("creancier"):
                    self.rapport.erreur(rel, ligne, "nouveau_creancier sans champ creancier")
                else:
                    etat["creancier"] = _nom_lien(c["creancier"])
                if fm.get("transferable") is False:
                    self.rapport.avert(rel, ligne, "changement de créancier sur une faveur "
                                                   "marquée transferable: false")
                if c.get("contrepartie"):
                    self._verifier_contrepartie(n, mv, etat["niveau"] or fm.get("niveau"))
            elif genre == "nouveau_debiteur":
                if not c.get("debiteur"):
                    self.rapport.erreur(rel, ligne, "nouveau_debiteur sans champ debiteur")
                else:
                    etat["debiteur"] = _nom_lien(c["debiteur"])
                if c.get("motif") == "mort_finale" and fm.get("enregistree") is not True:
                    self.rapport.avert(rel, ligne, "transmission pour mort finale d'une dette non "
                                                   "enregistrée par une Harpie (non transmissible "
                                                   "selon les règles)")
            elif genre == "reduction":
                nv = c.get("niveau")
                if nv not in NIVEAUX:
                    self.rapport.erreur(rel, ligne, "réduction sans niveau valide")
                else:
                    actuel = etat["niveau"]
                    if actuel in NIVEAUX and NIVEAUX.index(nv) >= NIVEAUX.index(actuel):
                        self.rapport.avert(rel, ligne, f"réduction de {actuel} vers {nv} : le "
                                                       f"niveau devrait baisser")
                    etat["niveau"] = nv
        # comparaison état rejoué / propriétés
        for cle in ("statut", "niveau", "debiteur", "creancier"):
            rejoue = etat[cle]
            if rejoue is None:
                continue
            prop = fm.get(cle)
            prop = _nom_lien(prop) if cle in ("debiteur", "creancier") and isinstance(prop, str) else prop
            if prop is not None and cle_nom(str(prop)) != cle_nom(str(rejoue)):
                self.rapport.avert(rel, self._ligne(n, cle),
                                   f"{cle} = « {prop} » mais le journal des mouvements donne « {rejoue} »")
        # sanctions des parties
        if fm.get("statut") in ("active", "reclamee"):
            for cle in ("debiteur", "creancier"):
                v = fm.get(cle)
                if not isinstance(v, str):
                    continue
                genre, obj = self.resoudre(_nom_lien(v))
                if genre == "note" and isinstance(obj.fm, dict):
                    sanc = _liste(obj.fm.get("sanctions"))
                    if "chasse_au_sang" in sanc:
                        self.rapport.info(rel, 0, f"{cle} sous Chasse au Sang : la faveur devrait "
                                                  f"être suspendue (règles du wiki)")
                    if "parjure" in sanc:
                        self.rapport.info(rel, 0, f"{cle} déclaré Parjure : la faveur devrait être "
                                                  f"annulée (règles du wiki)")

    def _verifier_contrepartie(self, n, mv, niveau_actuel):
        cible = _nom_lien(mv["champs"]["contrepartie"])
        genre, obj = self.resoudre(cible)
        niv_cp = None
        if genre == "note" and isinstance(obj.fm, dict):
            niv_cp = obj.fm.get("niveau")
        elif genre == "externe":
            niv_cp = obj.get("niveau")
        if niv_cp in NIVEAUX and niveau_actuel in NIVEAUX and \
                NIVEAUX.index(niveau_actuel) < NIVEAUX.index(niv_cp):
            self.rapport.avert(n.rel, mv["ligne"],
                               f"échange : la dette transférée ({niveau_actuel}) est inférieure à "
                               f"la contrepartie ({niv_cp})")

    # ---- éléments et mouvements
    def _verifier_blocs_structures(self):
        for n in self.notes:
            if n.elements and n.type not in ("source", "soiree"):
                self.rapport.avert(n.rel, n.elements[0]["ligne"],
                                   "section « Éléments » dans une note qui n'est ni source ni soirée")
            if n.mouvements and n.type != "faveur":
                self.rapport.avert(n.rel, n.mouvements[0]["ligne"],
                                   "section « Mouvements » dans une note qui n'est pas une faveur")
            for el in n.elements:
                self._valider_element(n, el)
            for mv in n.mouvements:
                self._valider_mouvement(n, mv)

    def _verifier_bloc_id(self, n, entree, prefixe):
        b = entree["bloc"]
        if not b:
            self.rapport.avert(n.rel, entree["ligne"], f"ligne sans identifiant ^{prefixe}-… "
                                                       f"(sera attribué par l'application)",
                               strict_erreur=True)
        elif not b.startswith(prefixe + "-") or not ID_RE.match(b):
            self.rapport.avert(n.rel, entree["ligne"], f"identifiant ^{b} non conforme "
                                                       f"(attendu ^{prefixe}-xxxxxxxx)",
                               strict_erreur=True)

    def _valider_element(self, n, el):
        c, ligne, rel = el["champs"], el["ligne"], n.rel
        self._verifier_bloc_id(n, el, "el")
        if not el["enonce"]:
            self.rapport.erreur(rel, ligne, "élément sans énoncé")
        nat = c.get("nature")
        if not nat:
            self.rapport.erreur(rel, ligne, "élément sans [nature:: …]")
        elif nat not in self.vocab["element.nature"]:
            self.rapport.erreur(rel, ligne, f"nature « {nat} » inconnue "
                                            f"({', '.join(self.vocab['element.nature'])})")
        cr = c.get("credibilite")
        if cr is None:
            self.rapport.erreur(rel, ligne, "élément sans [credibilite:: 1-6]")
        elif cr not in ("1", "2", "3", "4", "5", "6"):
            self.rapport.erreur(rel, ligne, f"credibilite « {cr} » invalide (1 à 6)")
        if c.get("date_faits") and not EDTF_RE.match(c["date_faits"]):
            self.rapport.erreur(rel, ligne, f"date_faits « {c['date_faits']} » non conforme (§7)")
        if c.get("jusqu_au") and not EDTF_RE.match(c["jusqu_au"]):
            self.rapport.erreur(rel, ligne, f"jusqu_au « {c['jusqu_au']} » non conforme (§7)")
        if c.get("par") and not LIEN_SEUL_RE.match(c["par"]):
            self.rapport.avert(rel, ligne, "[par:: …] devrait être un lien [[Nom]]")
        r = [c.get(k) for k in ("relation", "de", "vers")]
        if any(r) and not all(r):
            self.rapport.erreur(rel, ligne, "relation, de et vers doivent être renseignés ensemble")
        elif all(r):
            for k in ("de", "vers"):
                if not LIEN_SEUL_RE.match(c[k]):
                    self.rapport.erreur(rel, ligne, f"[{k}:: …] doit être un lien [[Nom]]")
            self._verifier_relation(rel, ligne, c["relation"], _nom_lien(c["de"]), _nom_lien(c["vers"]))
        connus = {"nature", "credibilite", "par", "date_faits", "relation", "de", "vers", "qualificatif",
                  "discipline", "jusqu_au"}
        if "discipline" in c and not LIEN_SEUL_RE.match(c["discipline"]):
            self.rapport.avert(rel, ligne, "[discipline:: …] devrait être un lien [[Discipline]]")
        for k in c:
            if k not in connus:
                self.rapport.info(rel, ligne, f"champ d'élément inconnu « {k} » (conservé)")

    def _valider_mouvement(self, n, mv):
        c, ligne, rel = mv["champs"], mv["ligne"], n.rel
        self._verifier_bloc_id(n, mv, "mv")
        g = c.get("mv")
        if not g:
            self.rapport.erreur(rel, ligne, "mouvement sans [mv:: …]")
        elif g not in self.vocab["mouvement.mv"]:
            self.rapport.erreur(rel, ligne, f"mouvement « {g} » inconnu")
        if not c.get("date"):
            self.rapport.erreur(rel, ligne, "mouvement sans [date:: …]")
        elif not EDTF_RE.match(c["date"]):
            self.rapport.erreur(rel, ligne, f"date « {c['date']} » non conforme (§7)")
        if c.get("niveau") and c["niveau"] not in NIVEAUX:
            self.rapport.erreur(rel, ligne, f"niveau « {c['niveau']} » inconnu")
        if c.get("motif") and c["motif"] not in self.vocab["mouvement.motif"]:
            self.rapport.avert(rel, ligne, f"motif « {c['motif']} » hors liste")
        for k in ("debiteur", "creancier", "harpie", "contrepartie", "source"):
            if c.get(k) and not LIEN_SEUL_RE.match(c[k]):
                self.rapport.avert(rel, ligne, f"[{k}:: …] devrait être un lien [[…]]")
        connus = {"mv", "date", "niveau", "debiteur", "creancier", "motif", "harpie",
                  "contrepartie", "source"}
        for k in c:
            if k not in connus:
                self.rapport.info(rel, ligne, f"champ de mouvement inconnu « {k} » (conservé)")

    def _verifier_relation(self, rel, ligne, code, de, vers):
        if code not in self.relations:
            self.rapport.erreur(rel, ligne, f"relation « {code} » absente du vocabulaire")
            return
        spec = self.relations[code]
        for cote, nom in (("de", de), ("vers", vers)):
            attendus = spec.get(cote) or []
            t = self.type_de(nom)
            if attendus and t and t not in attendus:
                self.rapport.avert(rel, ligne, f"{code} : « {nom} » est de type {t}, attendu "
                                               f"{' ou '.join(attendus)}")

    # ---- liens
    def _verifier_liens_note(self, n):
        liens = list(n.liens)
        if isinstance(n.fm, dict) and n.fm:
            for cle, val in n.fm.items():
                for v in (val if isinstance(val, list) else [val]):
                    if isinstance(v, str):
                        for m in LIEN_RE.finditer(v):
                            cible, sous = decouper_lien(m.group(2))
                            liens.append((cible, sous, n.fm_lignes.get(cle, 2), f"propriété {cle}"))
                if cle in PROPS_LIEN and PROPS_LIEN[cle] and isinstance(val, str):
                    self._verifier_type_cible(n, cle, _nom_lien(val), PROPS_LIEN[cle])
                if cle in PROPS_LISTE_LIENS and PROPS_LISTE_LIENS[cle] and isinstance(val, list):
                    for v in val:
                        if isinstance(v, str):
                            self._verifier_type_cible(n, cle, _nom_lien(v), PROPS_LISTE_LIENS[cle])
        for cible, sous, ligne, origine in liens:
            if not cible:  # lien interne à la note : [[#^bloc]]
                if sous and sous.startswith("^") and sous[1:] not in n.blocs:
                    self.rapport.avert(n.rel, ligne, f"lien vers un bloc absent : #{sous}",
                                       strict_erreur=True)
                continue
            genre, obj = self.resoudre(cible)
            if genre is None:
                self.rapport.avert(n.rel, ligne, f"lien cassé ({origine}) : [[{cible}]]",
                                   strict_erreur=True)
                continue
            if sous and sous.startswith("^"):
                ok, info = self.bloc_existe(cible, sous[1:])
                if info is None:
                    self.rapport.avert(n.rel, ligne, f"bloc introuvable : [[{cible}#{sous}]]",
                                       strict_erreur=True)
                elif not ok:
                    self.rapport.avert(n.rel, ligne, f"le bloc ^{sous[1:]} se trouve dans "
                                                     f"« {info[1]} », pas dans « {cible} »")

    def _verifier_type_cible(self, n, cle, nom, attendus):
        t = self.type_de(nom)
        if t and t not in attendus:
            self.rapport.avert(n.rel, n.fm_lignes.get(cle, 2),
                               f"« {cle} » vise « {nom} » de type {t} (attendu {' ou '.join(attendus)})")

    # ---- annuaire
    def annuaire(self):
        notes = []
        for n in self.notes:
            if not (n.fm_ok and n.fm and n.type in SPEC_TYPES):
                continue
            e = {"nom": n.nom, "type": n.type, "id": n.id, "chemin": n.rel,
                 "aliases": [a for a in _liste(n.fm.get("aliases")) if isinstance(a, str)],
                 "blocs": sorted(b for b in n.blocs if b.startswith(("el-", "mv-")))}
            if n.type == "faveur":
                e["niveau"] = n.fm.get("niveau")
            if n.type in ("personnage", "groupe", "lieu", "domaine"):
                for cle in ("clan", "domaine", "nature", "statut"):
                    if isinstance(n.fm.get(cle), str):
                        e[cle] = n.fm[cle]
            notes.append(e)
        return {"format": "nosferatu-annuaire", "schema": FORMAT_SCHEMA,
                "genere_le": _dt.datetime.now().isoformat(timespec="seconds"),
                "notes": notes, "fichiers": sorted(self.fichiers.values())}


def _date_reelle(texte):
    try:
        _dt.date.fromisoformat(texte)
        return True
    except ValueError:
        return False


def _liste(v):
    if v is None:
        return []
    return v if isinstance(v, list) else [v]


def _contenu_lien(v):
    m = LIEN_SEUL_RE.match(str(v).strip())
    return m.group(1) if m else str(v).strip()


def _nom_lien(v):
    return decouper_lien(_contenu_lien(v))[0]


# --------------------------------------------------------------------------
# Programme principal
# --------------------------------------------------------------------------


def main(argv=None):
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(encoding="utf-8")
        except (ValueError, OSError):
            pass
    p = argparse.ArgumentParser(description="Validateur du format Nosferatu v1 (ne modifie rien).")
    p.add_argument("chemin", nargs="?", help="coffre ou lot d'import à vérifier")
    p.add_argument("--annuaire-externe", help="annuaire JSON du coffre existant (pour un lot)")
    p.add_argument("--generer-annuaire", help="écrit l'annuaire JSON du chemin vérifié")
    p.add_argument("--strict", action="store_true",
                   help="identifiants manquants et liens cassés deviennent des erreurs")
    p.add_argument("--sans-info", action="store_true", help="masque les messages INFO")
    p.add_argument("--nouveaux-ids", nargs=2, metavar=("PREFIXE", "N"),
                   help="génère N identifiants (ex. : --nouveaux-ids per 5)")
    a = p.parse_args(argv)

    if a.nouveaux_ids:
        prefixe, nb = a.nouveaux_ids
        if prefixe not in set(PREFIXES.values()) | {"el", "mv"}:
            print(f"préfixe inconnu : {prefixe}", file=sys.stderr)
            return 2
        for _ in range(int(nb)):
            print(nouvel_id(prefixe))
        return 0
    if not a.chemin:
        p.print_help()
        return 2
    racine = Path(a.chemin).resolve()
    if not racine.is_dir():
        print(f"dossier introuvable : {racine}", file=sys.stderr)
        return 2
    externe = None
    if a.annuaire_externe:
        try:
            externe = json.loads(Path(a.annuaire_externe).read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            print(f"annuaire illisible : {e}", file=sys.stderr)
            return 2

    rapport = Rapport(strict=a.strict)
    v = Validateur(racine, rapport, externe)
    v.collecter()
    v.indexer()
    v.valider()

    par_type = {}
    for n in v.notes:
        if n.type in SPEC_TYPES:
            par_type[n.type] = par_type.get(n.type, 0) + 1
    nb_el = sum(len(n.elements) for n in v.notes)
    nb_mv = sum(len(n.mouvements) for n in v.notes)
    print(f"== Validation Nosferatu v{FORMAT_SCHEMA} : {racine} ==")
    print("Notes typées : " + (", ".join(f"{t} {c}" for t, c in sorted(par_type.items())) or "aucune"))
    print(f"Notes libres : {v.nb_libres} · notes illisibles : {v.nb_illisibles} · "
          f"éléments : {nb_el} · mouvements : {nb_mv}")
    print()
    ordre = {"ERREUR": 0, "AVERTISSEMENT": 1, "INFO": 2}
    for niveau, f, l, msg in sorted(rapport.items, key=lambda x: (x[1], x[2], ordre[x[0]])):
        if a.sans_info and niveau == "INFO":
            continue
        pos = f"{f}:{l}" if l else f
        print(f"{niveau:<13} {pos}  {msg}")
    print()
    print(f"Résumé : {rapport.compte('ERREUR')} erreur(s), {rapport.compte('AVERTISSEMENT')} "
          f"avertissement(s), {rapport.compte('INFO')} info(s)")

    if a.generer_annuaire:
        Path(a.generer_annuaire).write_text(
            json.dumps(v.annuaire(), ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"Annuaire écrit : {a.generer_annuaire}")
    return 1 if rapport.compte("ERREUR") else 0


if __name__ == "__main__":
    sys.exit(main())
