#!/usr/bin/env python3
"""
Génère tests/fixtures/yaml_cases.json : le corpus de tests du parseur FlatYaml,
avec les valeurs attendues calculées par PyYAML (référence indépendante).

  python tools/yaml_reference.py

Cas « ok »      : la valeur attendue vient de PyYAML (dates lues comme texte).
Cas « erreur »  : le profil plat doit refuser (PyYAML peut accepter : objet
                  imbriqué, texte multiligne… que le profil interdit).
Cas « ambigu »  : YAML 1.1 (PyYAML) et 1.2 (Obsidian) divergent ; FlatYaml lit
                  du texte et avertit. La valeur attendue est fixée ici.
"""
import json
from pathlib import Path

import yaml


class Chargeur(yaml.SafeLoader):
    pass


Chargeur.yaml_implicit_resolvers = {
    k: [(t, r) for t, r in v if t != "tag:yaml.org,2002:timestamp"]
    for k, v in yaml.SafeLoader.yaml_implicit_resolvers.items()
}


def typer(v):
    if v is None:
        return ["null"]
    if isinstance(v, bool):
        return ["bool", v]
    if isinstance(v, int):
        return ["int", v]
    if isinstance(v, float):
        return ["float", v]
    if isinstance(v, str):
        return ["str", v]
    if isinstance(v, list):
        return ["list", [typer(x) for x in v]]
    raise TypeError(type(v))


LONG = "nuit " * 1000

OK = {
    "scalaires simples": "type: personnage\nid: per-12m0sc1s\nschema: 1",
    "accents et guillemets": 'nom: "Élise « la Rouge » Varga"\nalias: \'L\'\'inconnu\'\nsimple: L\'inconnu\nechap: "a \\"b\\" c\\\\d"\nunicode: "\\u00e9t\\u00e9"',
    "liste en bloc": 'aliases:\n  - Le Notaire\n  - "[[Victor Morel]]"\n  - "[[2026-10-10 Valombre - Assemblée#^el-gq9x1xqg]]"',
    "liste compacte": "aliases:\n- a\n- b",
    "liste en ligne": "tags: [exemple, \"b, c\", 'd', 3]",
    "vides": "contre: []\nclan:\nsujets: \n",
    "nombres": "credibilite: 3\nf: 2.5\nneg: -4\nzero: 0",
    "booleens": "moi_present: true\nx: False\ny: TRUE",
    "dates en texte": "date: 2026-10-10\ndate_floue: 2026-04~/..\nautre: \"2026-09\"",
    "url": "url: https://exemple.fr/page?a=b&c=d#ancre",
    "commentaires": "# en tête\ncanal: Gazette de Valombre # fin de ligne\ntitre: \"#salon\"\nlangage: C#",
    "cles avec espaces": "Date de création: 2026-01-01\nnote perso: oui",
    "espaces de fin": "type: lieu   \nnature:   refuge  ",
    "vide total": "",
    "texte long": "contenu: " + LONG.strip(),
    "liste avec commentaire": "presents:\n  - \"[[A]]\"\n  # retiré\n  - \"[[B]]\"\nstatut: actif",
    "valeur avec deux-points sans espace": "heure: 21h30\nratio: a:b",
    "tirets dans le texte": "titre: Victor - le retour\nmoins: -fin",
}

ERREURS = {
    "objet imbriqué": "infos:\n  age: 300",
    "texte multiligne |": "notes: |\n  a\n  b",
    "texte multiligne >": "notes: >\n  a",
    "lien non entre guillemets": "clan: [[Toreador]]",
    "lien non entre guillemets dans une liste": "presents:\n  - [[X]]",
    "clé en double": "statut: actif\nstatut: inconnu",
    "deux-points dans la valeur": "titre: Rapport: Toulouse",
    "ancre": "a: &x 1",
    "alias": "b: *x",
    "objet en ligne": "a: {b: 1}",
    "tabulation": "\taliases: x",
    "guillemet non fermé": 'a: "abc',
    "texte sur deux lignes": "a: abc\n  def",
    "liste de listes": "a:\n  - - x",
    "indentation incohérente": "a:\n  - x\n    - y",
    "étiquette": "a: !!str 3",
    "liste non fermée": "a: [x, y",
}

AMBIGUS = {
    "yes": ("x: yes", {"x": ["str", "yes"]}),
    "zéro initial": ("x: 0042", {"x": ["str", "0042"]}),
    "exposant": ("x: 1e3", {"x": ["str", "1e3"]}),
    "sexagésimal": ("x: 1:30", {"x": ["str", "1:30"]}),
    "on": ("x: On", {"x": ["str", "On"]}),
}


def main():
    cas = []
    for nom, texte in OK.items():
        data = yaml.load(texte, Loader=Chargeur) or {}
        cas.append({"nom": nom, "yaml": texte, "attendu": "ok",
                    "valeur": {k: typer(v) for k, v in data.items()}})
    for nom, texte in ERREURS.items():
        try:
            pyyaml = yaml.load(texte, Loader=Chargeur)
            note = "PyYAML accepte (%s) mais le profil refuse" % type(pyyaml).__name__
        except yaml.YAMLError:
            note = "PyYAML refuse aussi"
        cas.append({"nom": nom, "yaml": texte, "attendu": "erreur", "note": note})
    for nom, (texte, valeur) in AMBIGUS.items():
        cas.append({"nom": nom, "yaml": texte, "attendu": "ambigu", "valeur": valeur,
                    "pyyaml": repr(yaml.load(texte, Loader=Chargeur))})
    dest = Path(__file__).resolve().parent.parent / "tests" / "fixtures" / "yaml_cases.json"
    dest.write_text(json.dumps(cas, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(cas)} cas écrits dans {dest}")


if __name__ == "__main__":
    main()
