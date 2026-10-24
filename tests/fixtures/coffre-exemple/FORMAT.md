# Format du coffre Nosferatu — version 1

*Version du format : 1.3 · Date : 2026-10-21 · Statut : proposition à valider*

*La version 1.1 ajoute le type `en_cours` (note rapide, §9.13). La version 1.2 ajoute des propriétés tirées des règles de la Fédération Camarilla Française (secte, statut d'âge, créature, génération, disciplines, influences, lignées, postes, reconnaissances et sobriquets). Ces ajouts sont tous facultatifs : aucune note existante n'est concernée, et les notes gardent `schema: 1`.*

*La version 1.3 ajoute l'échéance d'un élément (`jusqu_au`, §10.2), l'ordre de préséance des clans d'un domaine (`preseance`, §9.3), l'ordre des informations d'un rapport de soirée (`rapport`, §9.7), la note de renvoi d'une fiche fusionnée (§9.14) et le fichier de configuration du coffre (§17 : table de l'Amirauté, barème des points de statut). Tout est facultatif ; aucune note existante ne change.*

Ce document est la référence unique du format. Il s'adresse à trois lecteurs :

- vous, pour lire et éditer les notes dans Obsidian ;
- l'application Nosferatu Intelligence, qui lit et écrit ces fichiers ;
- toute IA chargée de convertir des données brutes dans ce format.

Tout ce qui n'est pas décrit ici est du texte libre. Il est conservé tel quel, jamais supprimé.

---

## 1. Principes

1. **Le coffre est la source de vérité.** Une note Markdown par chose. L'index SQLite de l'application est jetable et se reconstruit depuis les notes.
2. **Compatible Obsidian sans plugin.** Les propriétés suivent le modèle d'Obsidian : valeurs simples ou listes, jamais d'objets imbriqués. Les liens sont des `[[wikiliens]]`. Dataview est facultatif : les champs entre crochets suivent sa syntaxe, mais ne sont pas nécessaires pour lire les notes.
3. **On écrit une fois, on relie partout.** Une information est écrite à un seul endroit : la soirée, l'article ou la conversation d'où elle vient. Les fiches de personnages la retrouvent par les rétroliens (*backlinks*). On ne recopie jamais une information d'une fiche à l'autre.
4. **Toute information a une provenance.** Un fait n'existe que comme *élément* d'une source datée, évaluée et attribuée. Une déduction ou une hypothèse est marquée comme telle.
5. **On ne tranche pas à la place de l'analyste.** Les statuts (corroboré, contesté…) sont posés par vous. Les outils signalent les incohérences, ils ne décident jamais.
6. **Rien ne disparaît en silence.** Une note mal formée est signalée, jamais corrigée ni supprimée automatiquement.

## 2. Les trois niveaux d'information

| Niveau | Où | Rôle |
|---|---|---|
| **Source** | Note de soirée ou note de source (article, forum, Discord, conversation, document, note perso, analyse) | Le document brut, daté, avec la fiabilité de son origine. |
| **Élément** | Ligne structurée dans la section `## Éléments` d'une source | Une affirmation atomique tirée de cette source : qui dit quoi, sur qui, avec quelle crédibilité. |
| **Indice** | Note dans `Indices/` | Un *faisceau* : une affirmation que vous évaluez, appuyée par plusieurs éléments pour et contre, venant de sources différentes. |

Un élément isolé n'a pas besoin d'indice. On crée un indice quand une même affirmation revient dans plusieurs sources, quand des sources se contredisent, ou quand une affirmation compte pour une enquête.

## 3. Organisation du coffre

```
<coffre>/
  FORMAT.md                 ce document
  .nosferatu/config.json    vocabulaires et réglages (dossier masqué dans Obsidian)
  .nosferatu/tmp/           écritures temporaires de l'application (exclu de Git)
  Personnages/
  Groupes/                  clans, factions, coteries, organisations
  Domaines/                 villes et domaines
  Lieux/
  Objets/
  Concepts/
  Evenements/
  Soirees/2026/             une note par assemblée (ville + date)
  Sources/Presse/  Sources/Forum/  Sources/Discord/  Sources/Conversations/
  Sources/Documents/  Sources/Notes/  Sources/Analyses/
  Indices/
  Faveurs/
  Dossiers/
  En cours/                 notes rapides à trier (type en_cours)
  Pieces/                   pièces jointes (captures, textes bruts longs)
  Modeles/                  modèles Obsidian (ignorés par les outils)
  Tableaux/                 vues Obsidian Bases (ignorées par les outils)
  _Import/                  lots en attente de validation (ignorés par l'index)
  _Conflits/                versions en conflit non résolues (ignorées par l'index)
```

Les dossiers servent à ranger, rien de plus. C'est la propriété `type` qui fait foi. Une note déplacée dans un autre dossier reste valide.

Les dossiers « ignorés » (`Pieces`, `Modeles`, `Tableaux`, `_Import`, `_Conflits`, ou la liste `dossiers_ignores` de `.nosferatu/config.json`) ne sont pas lus comme des notes. Leurs fichiers comptent toutefois comme pièces jointes : un lien `![[capture.png]]` ou `[[2026-10-14 Discord brut]]` vers un fichier de `Pieces/` n'est pas un lien cassé, comme dans Obsidian. Les fichiers et dossiers dont le nom commence par un point (`.git`, `.obsidian`, `.trash`…) sont toujours ignorés.

## 4. Noms de fichiers et liens

### 4.1 Noms

- Le nom du fichier est le **nom affiché** de la chose. Les liens Obsidian s'appuient dessus.
- **Il est unique dans tout le coffre**, sans distinction de majuscules ou d'accents décomposés (normalisation NFC).
- Caractères interdits : `\ / : * ? " < > | # ^ [ ]`, ainsi qu'une espace ou un point en fin de nom.
- Les accents sont autorisés.

| Type | Convention | Exemple |
|---|---|---|
| personnage | Nom tel qu'il est connu | `Victor Morel.md` |
| homonyme | Nom suivi du domaine entre parenthèses | `Marie (Valombre).md` |
| identité inconnue | `Inconnu - description courte` | `Inconnu - Manteau gris.md` |
| soirée | `AAAA-MM-JJ Domaine - Nature` | `2026-10-10 Valombre - Assemblée.md` |
| source | `AAAA-MM-JJ Canal - Titre court` | `2026-10-12 Gazette de Valombre - Nominations.md` |
| indice | Énoncé court | `Victor Morel membre du Cercle des Lanternes.md` |
| événement | `AAAA-MM Description`, ou la description seule si la date est inconnue | `2026-09 Incendie de l'entrepôt des quais.md` |
| faveur | `AAAA-MM-JJ Débiteur envers Créancier`, avec les parties d'origine | `2026-10-10 Victor Morel envers Élise Varga.md` |
| dossier | `Dossier - Question courte` | `Dossier - Allégeances de Victor Morel.md` |

En cas de doublon de nom, ajoutez ` (2)`, ` (3)`…

### 4.2 Liens

- Lien vers une note : `[[Victor Morel]]`, ou `[[Victor Morel|le Notaire]]` pour afficher un autre texte. On n'écrit ni chemin de dossier, ni extension `.md`.
- Lien vers un élément : `[[2026-10-10 Valombre - Assemblée#^el-k2m9x4qp]]`.
- Dans les propriétés, un lien est **toujours entre guillemets** : `clan: "[[Toreador]]"`.
- Les liens vont dans un seul sens. Par exemple, le dossier liste ses indices, mais l'indice ne liste pas ses dossiers : Obsidian et l'application calculent le sens inverse.

### 4.3 Renommer

- **Dans Obsidian :** activez *Réglages → Fichiers et liens → Mettre à jour automatiquement les liens internes*. Obsidian corrige alors les liens tout seul.
- **Dans l'application :** elle fait de même.
- **Ailleurs (Git Bash, explorateur de fichiers) :** les liens cassent. L'application les détecte et propose de les réparer grâce à l'identifiant (§5), qui ne change jamais.

## 5. Identifiants

Chaque note typée porte un identifiant stable dans sa propriété `id`. Chaque élément et chaque mouvement de faveur porte un identifiant de bloc Obsidian (`^el-…`, `^mv-…`).

**Format :** `préfixe-xxxxxxxx`, soit 8 caractères tirés au hasard dans l'alphabet `0123456789abcdefghjkmnpqrstvwxyz` (base 32 de Crockford en minuscules, sans i, l, o, u).

| Type | Préfixe | | Type | Préfixe |
|---|---|---|---|---|
| personnage | `per` | | source | `src` |
| groupe | `grp` | | indice | `ind` |
| domaine | `dom` | | evenement | `evt` |
| lieu | `lie` | | faveur | `fav` |
| objet | `obj` | | dossier | `dos` |
| concept | `cpt` | | élément | `el` |
| soiree | `soi` | | mouvement | `mv` |
| en_cours | `enc` | | | |

**Règles :**
- Un identifiant n'est jamais modifié, jamais réutilisé, et jamais dérivé du nom. Renommer une note ne change donc pas son identifiant.
- Une note copiée doit recevoir un nouvel identifiant.
- Une note créée à la main dans Obsidian peut ne pas avoir d'`id`, ou un élément pas de `^el-` : c'est un avertissement, pas une erreur. L'application propose ensuite d'attribuer les identifiants manquants.
- Les lots d'import produits par une IA doivent, eux, être complets.
- Pour générer des identifiants : `python valider.py --nouveaux-ids per 5`.

## 6. Propriétés (frontmatter)

### 6.1 Profil autorisé

Le frontmatter commence à la première ligne par `---` et se termine par `---`. Il ne contient que des paires `clé: valeur` de premier niveau. Les valeurs possibles sont :

- **texte sur une ligne** (avec un lien éventuel) ;
- **nombre** ;
- **`true` ou `false`** ;
- **date** au format `AAAA-MM-JJ` ;
- **liste** de textes ou de liens (`  - élément` sur une ligne chacun, ou `[a, b]`) ;
- **vide**.

Sont **interdits**, car Obsidian ne les gère pas et l'application refusera de modifier la note :
- les objets imbriqués ;
- les listes de listes ;
- le texte sur plusieurs lignes (`|`, `>`) ;
- les ancres YAML (`&`, `*`) ;
- les étiquettes YAML (`!!`) ;
- les clés en double.

**Recommandations d'écriture :**
- Mettez entre guillemets doubles tout texte qui contient `:` ou `#`, qui commence par un caractère spécial, qui ressemble à un nombre ou à une date, ou qui vaut `oui`, `non`, `yes`, `no`, `on` ou `off`.
- Les commentaires YAML (`#`) sont tolérés, mais l'application demandera votre accord avant de réécrire une note qui en contient.
- Les noms de propriétés sont en minuscules, sans accents, avec `_` comme séparateur. Exceptions : les propriétés standard d'Obsidian `aliases`, `tags` et `cssclasses`.
- Une propriété inconnue est conservée telle quelle et signalée pour information.

### 6.2 Type de chaque propriété

Obsidian impose un même type pour un même nom de propriété dans tout le coffre. Réglez ces types une fois dans Obsidian (icône à gauche de la propriété) :

| Type Obsidian | Propriétés |
|---|---|
| Texte | `type`, `id`, `statut`, `nature`, `clan`, `secte`, `rang`, `domaine`, `sire`, `identite`, `fiabilite`, `region`, `detenteur`, `lieu`, `canal`, `auteur`, `rapporteur`, `soiree`, `url`, `relation`, `de`, `vers`, `niveau`, `debiteur`, `creancier`, `harpie`, `priorite`, `question`, `date_floue`, `fusionnee_dans`, `ancien_type`, `ancien_id` |
| Liste | `aliases`, `tags`, `sanctions`, `peut_etre`, `titres`, `presents`, `presents_incertains`, `absents`, `pour`, `contre`, `sujets`, `participants`, `indices`, `devenue`, `disciplines`, `influences`, `preseance`, `rapport` |
| Nombre | `schema`, `credibilite`, `generation` |
| Case à cocher | `moi_present`, `enregistree`, `transferable`, `fiche_reconnaissance` |
| Date | `date`, `date_fusion` |

### 6.3 Propriétés communes à toutes les notes typées

| Propriété | Obligatoire | Valeur |
|---|---|---|
| `type` | oui | un des types du §9 |
| `id` | oui (toléré absent dans une note faite à la main) | §5 |
| `schema` | oui | `1` |
| `aliases` | non | autres noms, surnoms, titres utilisés pour désigner la chose |
| `tags` | non | étiquettes libres |

Une note **sans** propriété `type` est une note libre : elle est lue pour ses liens et pour la recherche, rien de plus.

## 7. Dates

Il existe deux propriétés de date. Une note utilise **soit** l'une, **soit** l'autre :

- **`date`** : une date **exacte**, `2026-10-10`. C'est une vraie date Obsidian, triable dans les tableaux.
- **`date_floue`** : un texte qui suit un sous-ensemble de la norme EDTF (ISO 8601-2). Elle sert dès que la date n'est pas exacte.

| Écriture | Sens |
|---|---|
| `2026-10` | octobre 2026 (précision au mois) |
| `2026` | en 2026 |
| `2026-10~` | vers octobre 2026 (approximatif) |
| `2026-10?` | octobre 2026, peut-être (incertain) |
| `2026-10%` | approximatif et incertain |
| `19XX` | au XXe siècle, année inconnue |
| `2026-XX` | en 2026, mois inconnu |
| `2026-03/2026-09` | de mars à septembre 2026 |
| `../2026-05` | avant mai 2026 |
| `2026-03/..` | depuis mars 2026 (toujours en cours ou fin inconnue) |
| `inconnue` | aucune idée |

Le calendrier du jeu suit le calendrier réel.

Il faut distinguer deux dates :
- **la date de connaissance**, c'est-à-dire la date de la source : quand vous l'avez appris ;
- **la date des faits**, c'est-à-dire `date_faits` dans un élément : quand c'est arrivé.

La chronologie de l'application sait afficher les deux. Une date incertaine n'est jamais convertie en date exacte.

## 8. Évaluation

On évalue toujours séparément la source et l'information, selon l'échelle dite « Admiralty » utilisée dans le renseignement.

**Fiabilité de la source** (`fiabilite`, sur les sources, les soirées et les personnages informateurs) :

| Code | Sens |
|---|---|
| A | Entièrement fiable |
| B | Habituellement fiable |
| C | Assez fiable |
| D | Habituellement peu fiable |
| E | Non fiable |
| F | Ne peut être évaluée |

**Crédibilité de l'information** (`credibilite`, sur les éléments, les indices, les événements et les faveurs) :

| Code | Sens |
|---|---|
| 1 | Confirmée par d'autres sources indépendantes, ou observée directement sans ambiguïté |
| 2 | Probablement vraie |
| 3 | Possiblement vraie |
| 4 | Douteuse |
| 5 | Improbable |
| 6 | Ne peut être évaluée |

**Règles d'évaluation :**
- Une source fiable peut rapporter une information douteuse, et inversement.
- On ne note jamais `1` un élément qui repose sur un seul rapport.
- En cas de doute, on choisit `F` pour la source et `6` pour l'information.

**Statut d'un indice ou d'un événement** (`statut`). C'est vous qui le posez, jamais l'outil :

| Statut | Sens |
|---|---|
| `non_verifie` | une seule source, ou plusieurs sources qui ne sont pas indépendantes |
| `corrobore` | au moins deux éléments venant de sources indépendantes, sans élément contraire sérieux |
| `conteste` | des éléments pour et des éléments contre |
| `refute` | des éléments contraires décisifs |
| `obsolete` | c'était vrai, mais ce ne l'est plus |

Deux sources ne sont pas indépendantes si l'une répète l'autre. C'est le cas d'un article qui reprend une rumeur entendue à l'Élysée, ou de deux personnages qui tiennent leur information de la même personne. Le validateur et l'application signalent un indice `corrobore` dont tous les éléments viennent d'une même note ou d'une même personne.

## 9. Types de notes

Dans les tableaux ci-dessous, ★ signale une propriété obligatoire. Les propriétés communes du §6.3 ne sont pas répétées.

### 9.1 `personnage` — `Personnages/`

| Propriété | Valeur |
|---|---|
| `clan` | lien vers un groupe |
| `domaine` | lien vers le domaine de rattachement |
| `statut` | `actif` (par défaut), `disparu`, `mort_finale`, `inconnu` |
| `sanctions` | liste parmi `chasse_au_sang`, `parjure`, `banni`, `liste_ecarlate`, `paria` |
| `identite` | `connue` (par défaut), `incertaine`, `inconnue` |
| `peut_etre` | liste de liens vers des personnages qui pourraient être la même personne |
| `sire` | lien vers un personnage |
| `titres` | liste de textes, par exemple `Harpie de Valombre` (postes actuellement connus ; voir les postes au §11.1) |
| `fiabilite` | A à F : fiabilité habituelle de ce personnage comme informateur |
| `nature` | `vampire` (par défaut), `goule`, `revenant`, `mortel`, `chasseur`, `loup_garou`, `mage`, `fae`, `fantome`, `demon`, `autre` |
| `secte` | lien vers un groupe de nature `secte` : Camarilla, Anarchs, Sabbat, Aubains |
| `rang` | statut d'âge : `venerable`, `ancien`, `ancilla`, `nouveau_ne`, `infant` (infant sous tutelle) |
| `generation` | nombre, seulement s'il est connu |
| `disciplines` | liste de liens vers les disciplines constatées chez ce personnage |
| `influences` | liste de textes : influences connues, par exemple `Police (Gotha)` ou `Rue (Pègre)` |

Le corps est libre. Les rubriques suggérées sont `## Portrait` et `## Notes`. On n'y recopie pas les informations venues des sources : elles apparaissent dans les rétroliens.

**Identités incertaines :**
- Un personnage dont on ignore l'identité devient une note `Inconnu - …` avec `identite: inconnue`.
- Lorsqu'on l'identifie, l'application **fusionne** les deux notes, après un aperçu :
  - la fiche gardée reçoit les propriétés qui lui manquaient, les alias de l'autre, l'ancien nom dans `aliases`, son texte (section « Repris de … ») et ses éléments, avec leurs identifiants ;
  - les liens qui visaient l'ancienne fiche visent la fiche gardée, sans changer le texte affiché : `[[Inconnu - Manteau gris]]` devient `[[Victor Morel|Inconnu - Manteau gris]]` ;
  - l'ancienne fiche n'est pas supprimée : elle devient une note de renvoi (§9.14).
- La même fusion sert pour deux fiches en double.

**Personne surveillée :** l'étiquette `surveille` dans `tags` (bouton *Surveiller* de l'application) fait signaler chaque nouvel élément qui cite la fiche. Ce qui a déjà été vu est retenu par l'application, sur chaque ordinateur ; la note ne change pas.

### 9.2 `groupe` — `Groupes/`

| Propriété | Valeur |
|---|---|
| `nature` | `clan`, `lignee`, `secte`, `faction`, `coterie`, `meute`, `organisation`, `autre` |
| `domaine` | lien, si le groupe est local |
| `clan` | pour une lignée : lien vers son clan d'origine |
| `secte` | lien vers la secte du groupe, s'il en a une |
| `disciplines` | pour un clan ou une lignée : liste de liens vers ses disciplines de clan |

### 9.3 `domaine` — `Domaines/`

Une ville ou un domaine.

| Propriété | Valeur |
|---|---|
| `region` | texte |
| `preseance` | liste de liens vers les clans (ou lignées), dans l'ordre de préséance du domaine. Le rapport de soirée range les présents dans cet ordre. Une lignée absente de la liste suit son clan d'origine ; un clan absent vient après les clans listés. |

Exemple :

```yaml
preseance:
  - "[[Ventrue]]"
  - "[[Toréador]]"
  - "[[Gangrel]]"
```

### 9.4 `lieu` — `Lieux/`

| Propriété | Valeur |
|---|---|
| `nature` | texte libre (refuge, Élysée, bar…) |
| `domaine` | lien |

### 9.5 `objet` — `Objets/`

| Propriété | Valeur |
|---|---|
| `nature` | texte libre |
| `detenteur` | lien vers le détenteur actuellement connu |
| `lieu` | lien |

### 9.6 `concept` — `Concepts/`

Une notion, un rite, une règle sociale, une discipline, un poste.

| Propriété | Valeur |
|---|---|
| `nature` | facultatif : `discipline`, `poste`, `tradition`, `notion`, `rituel`, `autre` |
| `secte` | pour un poste : lien vers la secte où il existe |

### 9.7 `soiree` — `Soirees/AAAA/`

Une assemblée de vampires dans un domaine, à une date donnée. C'est **aussi une source** : celle de vos observations directes.

| Propriété | Valeur |
|---|---|
| `date` ★ | date exacte de la soirée |
| `domaine` ★ | lien |
| `nature` | `assemblee` (par défaut), `elysium`, `conclave`, `reunion`, `autre` |
| `lieu` | lien |
| `moi_present` | `true` ou `false` |
| `presents` | liste de liens : présence constatée |
| `presents_incertains` | liste de liens : présence supposée ou personnage non identifié avec certitude |
| `absents` | liste de liens : absences remarquées |
| `fiabilite` | A à F pour celui qui prend les notes (par défaut `A` pour vos propres notes) |
| `rapport` | liste de liens : l'ordre des informations du rapport de soirée (voir ci-dessous) |

Corps :

```markdown
# Assemblée de Valombre — 10 octobre 2026

## Déroulé
Texte libre : chronologie de la soirée, ambiance, discours.

## Éléments
- … (lignes structurées, §10)

## À faire
- [ ] Demander à [[Élise Varga]] qui a enregistré la faveur.
```

Une présence rapportée par une autre source, comme un compte rendu publié sur le forum, ne s'ajoute pas à `presents`. Elle s'écrit comme un élément de cette source avec `[relation:: present_a]`. L'application fusionne les deux pour afficher qui était présent, et selon qui.

**Rapport de soirée.** L'application en tire un rapport :
- les présents, rangés par clan selon la `preseance` du domaine (§9.3), puis par statut d'âge, du plus vieux au plus jeune, puis par statut de fonction (postes) et par reconnaissances, à la date de la soirée (§11.1) ;
- les informations : les éléments de la soirée, ceux des sources dont la propriété `soiree` vise cette soirée (une conversation tenue pendant la soirée, par exemple), et ce que la liste `rapport` cite ;
- l'ordre de ces informations est celui de `rapport`, puis l'ordre naturel pour celles qui n'y figurent pas encore. `rapport` contient des liens vers des éléments (`[[Note#^el-…]]`) ou vers des notes entières (un événement, un indice ; une source y vaut pour tous ses éléments).

```yaml
rapport:
  - "[[2026-10-10 Conversation avec Élise#^el-4kq2m8xd]]"
  - "[[2026-10 Incident du vestiaire]]"
  - "[[2026-10-10 Valombre - Assemblée#^el-k2m9x4qp]]"
```

La fiabilité et la crédibilité modifiées depuis le rapport s'écrivent dans la note d'où vient l'information, jamais dans le rapport.

### 9.8 `source` — `Sources/<Nature>/`

| Propriété | Valeur |
|---|---|
| `nature` ★ | `presse`, `forum`, `discord`, `conversation`, `document`, `note`, `analyse` |
| `date` ou `date_floue` ★ | date de publication ou de l'échange |
| `fiabilite` ★ | A à F |
| `domaine` | lien |
| `canal` | nom du journal, section du forum ou salon Discord |
| `auteur` | lien vers l'auteur en jeu, ou texte s'il n'a pas de fiche |
| `rapporteur` | lien vers la personne qui vous l'a transmis, si elle diffère de l'auteur |
| `soiree` | lien vers la soirée concernée |
| `url` | adresse d'origine, si elle existe |

Corps :

```markdown
# Titre de la source

## Contenu
Texte intégral ou résumé fidèle. Un contenu très long va dans Pieces/
et s'insère ici avec ![[fichier.txt]].

## Éléments
- … (lignes structurées, §10)
```

**Découpage :** une note par article, par fil ou rapport de forum, par conversation. Une conversation Discord correspond à un salon et à un échange continu : on ouvre une nouvelle note après une longue pause ou un changement de jour.

**Analyses :** une source de nature `analyse` contient des déductions et des hypothèses, les vôtres ou celles d'une IA. Ses éléments sont uniquement de nature `deduction` ou `hypothese`. Une analyse produite par une IA porte `auteur: "Claude"` et `fiabilite: F`.

### 9.9 `indice` — `Indices/`

| Propriété | Valeur |
|---|---|
| `statut` ★ | §8 |
| `credibilite` ★ | 1 à 6, votre évaluation de l'ensemble |
| `pour` ★ | liste de liens vers des éléments (`[[Note#^el-…]]`), au moins un |
| `contre` | liste de liens vers des éléments contraires |
| `sujets` | liste de liens vers les entités concernées |
| `relation`, `de`, `vers` | à renseigner ensemble pour un indice qui décrit une relation (vocabulaire du §11) |
| `date` ou `date_floue` | période où l'affirmation est vraie. Exemple : `2026-03~/..` pour « depuis mars environ » ; `2025/2026-09` pour une relation rompue en septembre |

Le corps contient l'énoncé en titre, puis `## Analyse` en texte libre.

### 9.10 `evenement` — `Evenements/`

Un fait qui s'est produit, daté si possible. C'est une affirmation évaluée, au même titre qu'un indice.

| Propriété | Valeur |
|---|---|
| `statut` ★ | §8 |
| `credibilite` ★ | 1 à 6 |
| `date` ou `date_floue` ★ | `date_floue: inconnue` est accepté |
| `domaine`, `lieu` | liens |
| `participants` | liste de liens |
| `pour`, `contre` | listes de liens vers des éléments (`pour` fortement recommandé) |

### 9.11 `faveur` — `Faveurs/`

Une dette entre deux Semblables, selon le système de faveurs de votre chronique.

| Propriété | Valeur |
|---|---|
| `niveau` ★ | `triviale`, `mineure`, `majeure`, `sang`, `vie` (dans cet ordre croissant) |
| `debiteur` ★ | lien : celui qui doit, **actuellement** |
| `creancier` ★ | lien : celui à qui c'est dû, **actuellement** |
| `statut` ★ | voir le tableau des statuts ci-dessous |
| `credibilite` ★ | 1 à 6 : certitude que cette faveur existe telle que décrite (`1` si vous en êtes partie) |
| `date` ou `date_floue` ★ | date de contraction |
| `domaine` | lien vers le domaine d'enregistrement |
| `harpie` | lien vers la Harpie qui l'a enregistrée |
| `enregistree` | `true` si elle a été validée par une Harpie. Seules ces dettes sont transmissibles à la mort finale. |
| `transferable` | `true` par défaut. Les dettes sont transférables sauf stipulation contraire. |
| `fiche_reconnaissance` | `true` si la fiche hors-jeu de reconnaissance de dette existe |
| `pour` | liste de liens vers les éléments qui attestent la faveur, quand vous n'en êtes pas partie |

**Statuts d'une faveur :**

| Statut | Sens |
|---|---|
| `active` | due, pas encore réclamée |
| `reclamee` | le créancier l'a réclamée ; le paiement est en cours |
| `soldee` | payée |
| `ignoree` | ignorée formellement par le débiteur |
| `suspendue` | suspendue par une Chasse au Sang visant l'une des parties ; elle redevient active si la chasse est levée |
| `annulee` | nulle et non avenue : parjure, mort simulée, domaine déclaré parjure |

Corps :

```markdown
# Victor Morel envers Élise Varga

## Stipulations
Texte libre : clauses citées lors de l'enregistrement.

## Mouvements
- Contractée devant la Harpie. [mv:: creation] [date:: 2026-10-10] [niveau:: mineure] [debiteur:: [[Victor Morel]]] [creancier:: [[Élise Varga]]] [harpie:: [[Armand Lescure]]] ^mv-2f7k1q9d
- Réclamée en public. [mv:: reclamation] [date:: 2026-11-14] ^mv-8c3w5n0r
```

Les propriétés donnent l'**état courant**. Les mouvements, dans l'ordre chronologique, constituent le **journal**. Le validateur rejoue le journal et signale toute divergence entre les deux.

**Mouvements** (`mv`), obligatoires : `mv` et `date`, la date suivant la grammaire floue du §7.

| `mv` | Champs requis | Effet |
|---|---|---|
| `creation` | facultatifs : `niveau`, `debiteur`, `creancier`, `harpie` | statut `active` ; doit être le premier mouvement |
| `reclamation` | — | `active` → `reclamee` |
| `paiement` | — | → `soldee` |
| `ignoree` | — | → `ignoree` |
| `nouveau_creancier` | `creancier` | changement de créancier : échange ou transmission au sire |
| `nouveau_debiteur` | `debiteur` | changement de débiteur : transmission à un infant ou à un disciple |
| `reduction` | `niveau` (inférieur) | la dette est réduite d'un niveau |
| `annulation` | `motif` conseillé | → `annulee` |
| `suspension` | `motif` conseillé | → `suspendue` |
| `retablissement` | — | `suspendue` → statut précédent |

Champs facultatifs d'un mouvement :
- `motif` : `echange`, `mort_finale`, `parjure`, `chasse_au_sang`, `mort_simulee`, `domaine_parjure`, `autre` ;
- `harpie` : lien ;
- `contrepartie` : lien vers la faveur échangée en paiement ;
- `source` : lien vers l'élément qui documente le mouvement.

**Contrôles tirés des règles de votre wiki.** Ce sont des avertissements, jamais des blocages :
- Une transmission pour mort finale d'une dette non enregistrée par une Harpie est signalée.
- Un changement de créancier sur une dette `transferable: false` est signalé.
- Une `contrepartie` de niveau supérieur à la dette échangée est signalée : la dette transférée doit être de niveau supérieur ou égal.
- Une faveur `majeure`, `sang` ou `vie` ignorée est signalée, car le débiteur perd du statut.
- Une faveur encore active dont une partie est marquée `chasse_au_sang` ou `parjure` est signalée.
- **Délai indicatif après réclamation :**
  - triviale : 1 séance ou 1 nuit ;
  - mineure : 2 séances ou 1 mois, le plus long des deux ;
  - majeure : 6 séances ou 3 mois, le plus long des deux ;
  - sang et vie : non précisé.

### 9.12 `dossier` — `Dossiers/`

| Propriété | Valeur |
|---|---|
| `statut` ★ | `ouvert`, `en_pause`, `resolu`, `abandonne` |
| `question` ★ | la question centrale, sur une ligne |
| `priorite` | `haute`, `moyenne`, `basse` |
| `sujets` | liste de liens vers les entités concernées |
| `indices` | liste de liens vers les indices du dossier |

Le corps est libre : hypothèses, contradictions, pistes. Les choses à rechercher et les prochaines actions s'écrivent comme des tâches `- [ ]`.

### 9.13 `en_cours` — `En cours/`

Une note rapide : un bloc-notes pris sur le vif, à trier plus tard. On y écrit librement, sans structure.

| Propriété | Valeur |
|---|---|
| `date` | date de la prise de note |
| `domaine` | lien, facultatif |
| `statut` | `a_traiter` (par défaut) ou `traitee` |
| `devenue` | liste de liens vers les notes créées à partir de celle-ci |

Nom : `AAAA-MM-JJ HHhMM Note rapide`, par exemple `2026-10-19 01h52 Note rapide.md`.

Quand on la « transforme », l'application crée la nouvelle note (soirée, personnage, source…) en y reprenant le texte. La note rapide n'est **ni supprimée ni déplacée** : elle passe en `statut: traitee`, et `devenue` pointe vers le résultat. Elle reste ainsi la trace de ce que vous avez noté sur le moment. Vous pouvez la supprimer vous-même dans Obsidian si vous n'en voulez plus.

### 9.14 Note de renvoi (fiche fusionnée)

Quand une fiche est fusionnée dans une autre (§9.1), elle devient une note libre, sans `type`, qui ne compte plus comme fiche :

| Propriété | Valeur |
|---|---|
| `fusionnee_dans` | lien vers la fiche gardée |
| `date_fusion` | date de la fusion |
| `ancien_type`, `ancien_id` | son type et son identifiant d'avant |

Son corps renvoie vers la fiche gardée, puis conserve **en entier** le texte d'origine de la note, propriétés comprises, dans un bloc de code : rien n'y est indexé ni compté deux fois, et rien n'est perdu. Vous pouvez la supprimer vous-même dans Obsidian si vous n'en voulez plus.

## 10. Lignes structurées (éléments et mouvements)

Deux sections du corps sont lues par les outils :
- `## Éléments`, dans les soirées et les sources ;
- `## Mouvements`, dans les faveurs.

Ailleurs, le corps est libre.

### 10.1 Grammaire

```
- <énoncé avec [[liens]]> [clé:: valeur] [clé:: valeur] ^el-xxxxxxxx
    - commentaire libre facultatif (indenté)
```

- La section commence au titre de niveau 2 et s'arrête au titre suivant de niveau 1 ou 2.
- Chaque **élément est un point de liste de premier niveau** (`- ` en début de ligne) qui tient sur **une seule ligne**, même longue.
- Les **champs** s'écrivent `[clé:: valeur]`, selon la syntaxe des champs en ligne de Dataview. Une valeur peut contenir un lien : `[par:: [[Élise Varga]]]`. Une même clé n'apparaît qu'une fois par ligne.
- La ligne se termine par l'**identifiant de bloc** : une espace, `^`, puis l'identifiant (§5).
- L'**énoncé** est le texte qui reste une fois les champs et l'identifiant retirés. Il ne doit pas être vide. C'est une phrase autonome, et les entités concernées y sont liées : c'est ce qui crée les rétroliens.
- Les sous-points indentés sont des commentaires libres. Leurs liens sont indexés.
- Tout autre contenu dans la section, comme un paragraphe ou une ligne sans identifiant, est conservé et signalé. Les tâches `- [ ]` n'ont rien à faire dans ces sections : mettez-les sous `## À faire`.

### 10.2 Champs d'un élément

| Champ | Obligatoire | Valeur |
|---|---|---|
| `nature` | oui | voir le tableau des natures ci-dessous |
| `credibilite` | oui | 1 à 6 (§8) |
| `par` | non | lien vers celui qui affirme, s'il diffère de l'auteur ou du rapporteur de la source. Indispensable dans une conversation à plusieurs. |
| `date_faits` | non | date floue (§7) des faits rapportés, seulement si elle est indiquée |
| `relation`, `de`, `vers` | non, mais ensemble | l'élément décrit une relation (vocabulaire du §11) |
| `qualificatif` | non | pour une reconnaissance, un sobriquet ou une nomination : le mot donné ou le poste, par exemple `Courageux` ou `Prévôt de Lyon` |
| `discipline` | non | lien vers la discipline employée, quand l'élément rapporte un pouvoir constaté : `[discipline:: [[Domination]]]`. Les fiches de personnages en déduisent les disciplines constatées et les clans compatibles. |
| `jusqu_au` | non | échéance (§7) de ce que dit l'élément : une reconnaissance, une tance ou une nomination « pour trois mois », une probation. `[jusqu_au:: 2026-11-28]` ; au mois (`2026-12`), elle court jusqu'à la fin du mois. Passé cette date, l'élément reste vrai pour le passé, mais ne compte plus dans le statut en cours. |

**Natures d'un élément :**

| `nature` | Sens |
|---|---|
| `observe` | vu ou entendu directement par l'auteur de la note |
| `rapporte` | affirmé de première main par `par`, ou à défaut par l'auteur de la source |
| `rumeur` | relayé de seconde main, ou d'origine inconnue |
| `deduction` | conclusion tirée d'autres éléments (citez-les en sous-point) |
| `hypothese` | supposition non démontrée |

Exemples :

```markdown
- [[Victor Morel]] dit avoir rejoint le [[Cercle des Lanternes]] « au printemps ». [nature:: rapporte] [credibilite:: 3] [date_faits:: 2026-04~] [relation:: membre_de] [de:: [[Victor Morel]]] [vers:: [[Cercle des Lanternes]]] ^el-k2m9x4qp
- [[Élise Varga]] est arrivée après le discours d'ouverture. [nature:: observe] [credibilite:: 1] ^el-3vq8z0hd
- On murmure que [[Victor Morel]] doit une faveur de sang à un ancien de [[Valombre]]. [nature:: rumeur] [credibilite:: 4] ^el-9m2rwx6b
```

## 11. Vocabulaire des relations

Les relations s'expriment dans les éléments (`relation`, `de`, `vers`) et dans les indices relationnels. Le vocabulaire ci-dessous est toujours disponible ; `.nosferatu/config.json` peut l'étendre ou changer les libellés, mais jamais en retirer. Il en va de même pour les listes de valeurs (`valeurs`) du fichier de configuration : elles s'ajoutent aux listes du format.

| Code | Lecture | Sens | De → vers |
|---|---|---|---|
| `allie` | est allié de | symétrique | personnage/groupe ↔ personnage/groupe |
| `ennemi` | est ennemi de | symétrique | idem |
| `rival` | est rival de | symétrique | idem |
| `lie_a` | est lié à (nature inconnue) | symétrique | toute entité |
| `membre_de` | est membre de | dirigé | personnage → groupe |
| `dirige` | dirige | dirigé | personnage → groupe, domaine, lieu |
| `sire_de` | est le sire de (inverse : infant de) | dirigé | personnage → personnage |
| `mentor_de` | est le mentor de (inverse : disciple de) | dirigé | personnage → personnage |
| `contact_de` | est un contact ou informateur de | dirigé | personnage → personnage |
| `sert` | est au service de | dirigé | personnage → personnage/groupe |
| `protege` | protège | dirigé | personnage/groupe → personnage/groupe |
| `chantage` | fait chanter | dirigé | personnage → personnage |
| `influence` | a de l'influence sur | dirigé | personnage/groupe → toute entité |
| `lien_de_sang` | est lié par le sang à (vers = régnant) | dirigé | personnage → personnage |
| `present_a` | était présent à | dirigé | personnage → soirée |
| `possede` | possède | dirigé | personnage/groupe → objet/lieu |
| `reside_a` | réside à | dirigé | personnage → lieu/domaine |
| `reconnait` | a reconnu (patronage) | dirigé | personnage → personnage ; `qualificatif` = la reconnaissance |
| `sobriquet` | a affublé d'un sobriquet | dirigé | personnage → personnage ; `qualificatif` = le sobriquet |
| `nomme` | a nommé à un poste | dirigé | personnage → personnage ; `qualificatif` = le poste |

Exemple :

```markdown
- [[Armand Lescure]] reconnaît [[Élise Varga]] « Avisée » devant la cour. [nature:: observe] [credibilite:: 1] [relation:: reconnait] [de:: [[Armand Lescure]]] [vers:: [[Élise Varga]]] [qualificatif:: Avisée] ^el-7d2k9m4q
```

L'application regroupe ces éléments sur la fiche de la personne : reconnaissances et sobriquets reçus, postes, avec qui les a donnés et selon quelle source.

### 11.1 Postes et statut (règles de la Fédération)

Les postes s'écrivent dans `titres`, suivis du domaine : `Prévôt de Lyon`. L'application propose les postes suivants :

| Secte | Postes |
|---|---|
| Camarilla | Prince, Duc, Marquis, Seigneur, Sénéchal, Bailli, Fléau, Gardien d'Élysée, Prévôt, Maître des Harpies, Sentinelle, Héraut, Harpie, Primogène, Fouet, Justicar, Archonte, Alastor, Servire |
| Anarchs | Baron, Défenseur, Gendarme, Architecte, Ambassadeur |
| Sabbat | Régent, Cardinal, Archevêque, Évêque, Templier, Paladin, Priscus, Ductus, Prêtre, Abbé |

Le statut d'âge (`rang`) suit la hiérarchie des règles : Vénérable > Ancien > Ancilla > Nouveau-né > Infant sous tutelle. Les Anarchs et les Aubains n'ont pas de statut camariste : leur `secte` suffit à le dire.

**Statut en cours à une date** (rapport de soirée). L'ordre suivi est : statut d'âge, puis statut de fonction, puis reconnaissances. L'application calcule, pour une date :
- les **postes** : `titres` de la fiche, et éléments `nomme` dont le `qualificatif` est le poste. Un poste suivi d'un autre domaine que celui de la soirée (`Prévôt de Lyon` à Valombre) est affiché mais ne compte pas ;
- les **reconnaissances** (`reconnait`) et les **tances** (`sobriquet`) reçues : comptées si leur date (`date_faits`, ou celle de la note) précède la date, si leur échéance `jusqu_au` n'est pas passée, et si leur crédibilité va de 1 à 3. Une même reconnaissance rapportée par plusieurs notes ne compte qu'une fois ;
- les **points de statut** selon le barème de `.nosferatu/config.json` (§17). Sans barème : 1 point par poste, +1 par reconnaissance, −1 par tance.

Les présents sont rangés par statut d'âge, puis par points de postes, puis par points de reconnaissances et de tances.

**Relation supposée, rompue, temporaire :**
- Une relation **supposée** est un élément ou un indice de faible crédibilité, ou au statut `non_verifie`.
- Une relation **rompue** ou **temporaire** est un indice dont la période est fermée, par exemple `2025/2026-09`.

**Dettes :** elles ne sont pas des relations. Ce sont des notes `faveur`, que le graphe affiche à part.

## 12. Tâches et préparation de séance

Toute tâche Obsidian `- [ ] …` placée hors des sections structurées est une action ouverte. Vous la cochez `- [x]` une fois faite.

Pour la préparation de séance, l'application regroupe les tâches ouvertes :
- par personnes liées dans la tâche ;
- par domaine de la note ;
- par dossier.

## 13. Validation

`outils/valider.py` vérifie un coffre ou un lot, sans jamais rien modifier. Il demande Python 3 et PyYAML (`pip install pyyaml`) :

```
python valider.py <chemin>                       # vérifie tout
python valider.py <lot> --annuaire-externe annuaire.json --strict
python valider.py <coffre> --generer-annuaire annuaire.json
python valider.py --nouveaux-ids per 5
```

| Niveau | Exemples | Conséquence |
|---|---|---|
| **ERREUR** | YAML illisible, objet imbriqué, identifiant en double, nom de fichier en double, valeur hors liste pour une propriété obligatoire | L'application ne modifie pas la note. Un lot d'import est refusé. |
| **AVERTISSEMENT** | lien cassé, identifiant manquant, statut `corrobore` sans sources indépendantes, journal de faveur incohérent | La note est indexée et le problème est listé dans le diagnostic. |
| **INFO** | propriété inconnue, note libre, rappel tiré des règles de faveurs | Simple signalement. |

L'option `--strict` (pour les lots d'import) transforme en erreurs les identifiants manquants et les liens cassés.

## 14. Versions et migrations

- Chaque note typée porte `schema: 1`.
- Les versions 1.1 (type `en_cours`), 1.2 (propriétés tirées des règles) et 1.3 (échéances, préséance, rapport de soirée, notes de renvoi, configuration) ne changent aucune note existante et ne demandent aucune migration.
- Les outils lisent les versions qu'ils connaissent. Une note de version supérieure est affichée en lecture seule, avec un message.
- Toute évolution du format incrémente la version et documente sa migration dans ce fichier.
- Une migration n'est lancée que :
  - sur commande explicite ;
  - après un aperçu de la liste des notes concernées ;
  - sur un dépôt Git sans modification en attente, ce qui sert de sauvegarde vérifiée ;
  - note par note, sans jamais réécrire une note qu'elle ne concerne pas.

## 15. Lots d'import

Un lot est un dossier `_Import/AAAA-MM-JJ sujet/` qui reproduit l'arborescence du coffre. Il contient :

- uniquement des **notes nouvelles**, complètes, avec leurs identifiants ;
- un fichier `_lot.md`, qui est le rapport du lot :
  - origine des données ;
  - nombre de notes par type ;
  - nouvelles entités créées ;
  - doutes d'identification ;
  - **modifications proposées** sur des notes existantes, à appliquer à la main ou par l'application après approbation ;
  - résultat du validateur.

Un lot ne modifie jamais une note existante. Il est validé avec `--strict` contre l'annuaire du coffre avant d'être intégré.

Contre l'annuaire du coffre, le validateur et l'application signalent :

| Cas | Niveau |
|---|---|
| nom ou identifiant déjà présent dans le coffre | ERREUR : la note n'est pas intégrable |
| nom identique aux accents ou aux majuscules près (« Toreador » / « Toréador ») | AVERTISSEMENT : gardez-en une seule |
| alias qui reprend le nom d'une note du coffre | AVERTISSEMENT : deux notes répondraient à ce nom dans les recherches |

Un lot peut donner à toutes ses notes une même étiquette (`tags`), pour les retrouver ou les retirer en bloc.

## 16. Ce que les outils calculent sans le stocker

Rien de ce qui suit n'est écrit dans les notes : tout est recalculé à partir d'elles.

- les rétroliens et mentions de chaque fiche ;
- la présence aux soirées : `presents`, complété par les éléments `present_a`, avec leur provenance ;
- le graphe : relations des éléments et des indices, faveurs, sire, clan, coprésence ;
- la chronologie, par date des faits ou par date de connaissance ;
- pour chaque faisceau : nombre de sources, sources indépendantes, contradictions ;
- l'état et le délai des faveurs ;
- les questions ouvertes ;
- les chemins les plus probables entre deux fiches (§17, table de l'Amirauté) ;
- le statut en cours d'un personnage à une date (§11.1) et le rapport d'une soirée (§9.7) ;
- les alertes : échéances `jusqu_au` proches ou passées depuis peu, faveurs réclamées dont le délai est dépassé (§9.11), sanctions en cours, nouveaux éléments sur les personnes surveillées ;
- la fiabilité proposée d'un informateur : ses affirmations (`par`, sinon auteur ou rapporteur de la source) confirmées ou réfutées par les indices et événements qui les citent, sinon par leur crédibilité 1 ou 5. La lettre n'est écrite dans `fiabilite` que si vous l'acceptez.
- les alibis : où était chacun telle nuit, d'après `presents`, `presents_incertains`, `absents`, les `participants` d'un événement non réfuté, et les éléments ou indices `present_a`. La date d'une présence est la `date_faits` de l'élément, sinon la date de la soirée ou de l'événement visé. Les personnes notées à deux endroits la même nuit, et celles présentes à plusieurs incidents, sont signalées.

## 17. Fichier de configuration du coffre

`.nosferatu/config.json` est facultatif. Les sections suivantes sont lues ; une section absente prend les valeurs par défaut, une valeur invalide est ignorée.

| Section | Rôle |
|---|---|
| `dossiers_ignores` | dossiers qui ne sont pas lus comme des notes (§3) |
| `relations`, `valeurs` | vocabulaires ajoutés à ceux du format (§11) |
| `faveurs` | délais indicatifs par niveau (§9.11) |
| `moi` | votre personnage, en lien : signature du rapport de soirée |
| `preseance` | ordre de préséance par défaut, pour les domaines qui n'ont pas de `preseance` (§9.3) |
| `amiraute` | probabilité donnée à chaque lettre et à chaque chiffre de l'échelle (§8), pour les chemins les plus probables |
| `statut` | barème des points de statut (§11.1) |

Valeurs par défaut de `amiraute` : A et 1 = 0,95 ; B et 2 = 0,8 ; C et 3 = 0,6 ; D et 4 = 0,4 ; E et 5 = 0,2 ; F et 6 (« ne peut être évaluée ») = 0,5, c'est-à-dire neutre. Un lien vaut fiabilité × crédibilité ; un chemin vaut le produit de ses liens. Plusieurs attestations d'un même lien se renforcent si elles viennent de notes et de personnes différentes ; un indice ne fait qu'un avec les notes de ses éléments `pour`.

```json
{
  "moi": "[[Hermès]]",
  "preseance": ["[[Ventrue]]", "[[Toréador]]", "[[Gangrel]]"],
  "amiraute": {
    "fiabilite": {"A": 0.95, "B": 0.8, "C": 0.6, "D": 0.4, "E": 0.2, "F": 0.5},
    "credibilite": {"1": 0.95, "2": 0.8, "3": 0.6, "4": 0.4, "5": 0.2, "6": 0.5}
  },
  "statut": {
    "poste_defaut": 1,
    "postes": {"Prince": 5, "Sénéchal": 4, "Primogène": 3, "Harpie": 2},
    "reconnaissance": 1,
    "tance": -1
  }
}
```

Les nombres de l'exemple `statut` sont à régler selon votre chronique.

## Annexe — Réglages Obsidian conseillés

- *Fichiers et liens* :
  - mise à jour automatique des liens internes : **activée** ;
  - utiliser les `[[wikiliens]]` : **activé** ;
  - format des nouveaux liens : **le plus court possible** ;
  - emplacement des pièces jointes : `Pieces`.
- *Fichiers et liens → Fichiers exclus* : `_Import`, `_Conflits` (facultatif, pour ne pas polluer la recherche).
- *Modèles* (module principal) : dossier `Modeles`.
- *Bases* (module principal, Obsidian 1.9 et suivants) : le dossier `Tableaux` contient des vues d'essai (faveurs en cours, soirées, indices à examiner). Leur syntaxe suit la documentation d'Obsidian, mais elles n'ont pas encore été ouvertes dans votre version.
