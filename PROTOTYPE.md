# Nosferatu Intelligence — version 0.16

*24 octobre 2026 · Godot 4.7.x · format du coffre v1.5 · version PC*

La 0.16 apporte les **statistiques** des personnages et des informations, et le statut **torpeur** (format 1.5). Elle accompagne le lot 6, les 4 604 fiches tirées du registre des personnages. Aucune note existante n'est concernée.

---

## 1. Ce qui change dans la 0.16 : les statistiques

**Où** : Enquête → *Statistiques*. Deux onglets, *Personnages* et *Informations*. Rien n'est écrit dans le coffre ; *Recalculer* relit l'index après une synchronisation.

**Personnages**
- **Filtres** :
  - le statut : Actif, Torpeur, Disparu, Mort finale, Inconnu, Non renseigné. Aucun bouton enfoncé : tous les statuts ; plusieurs : leur réunion ;
  - au moins N **informations** (les éléments qui citent la personne) et au moins N **rétroliens** (les notes qui la citent).
- **Camembert au choix** : statut, âge (statut d'âge), ville (domaine), clan, secte, discipline.
  - Au-delà de dix parts, les plus petites sont réunies en « Autres ».
  - Les disciplines sont celles de la fiche et celles constatées dans un élément `[discipline:: …]` qui cite la personne. Une personne compte une fois par discipline.
  - *Masquer « … »* retire ceux qui n'ont pas de valeur. La case est cochée d'office pour les disciplines, que presque aucune fiche ne porte.
- **Un appui sur une part** (ou sur sa ligne de légende) liste ses personnages dans le tableau de droite ; un second appui la retire.
  - Le tableau se trie par colonne : clan, âge, ville, statut, informations, rétroliens. Par défaut, les plus cités d'abord.
  - Un appui sur une ligne ouvre la fiche.

**Informations** (les éléments de vos notes)
- **Chiffres clés** :
  - le nombre d'informations, et de notes qui les portent ;
  - les **solides** : source A ou B, crédibilité 1 ou 2 ;
  - les **fragiles** : source D ou E, ou crédibilité 4 ou 5 ;
  - les **non évaluées** : ni fiabilité ni crédibilité (F, 6 ou rien) ;
  - les **rumeurs** (nature « rumeur ») et les **improbables** (crédibilité 5).
- **Camembert au choix** : fiabilité de la source (A–F), crédibilité de l'information (1–6), cote complète (B2…), nature, type de note, année, domaine, voix (qui affirme : `par`, sinon l'auteur de la note).
- **Grille de l'Amirauté** : la fiabilité en lignes, la crédibilité en colonnes.
  - Vert : solide ; or puis rouge : de plus en plus fragile ; gris : non évaluée. Plus la case est vive, plus elle est remplie.
  - Un appui sur une case liste ses informations.
- Un filtre par **domaine**.
- Le tableau montre les 1 000 informations les plus récentes de la sélection (date des faits, sinon date de la note). Un appui ouvre la note.

**Sur votre coffre avec le lot 6** (6 660 notes)
- **5 875 personnages**, dont 1 245 cités par au moins une information.
  - Statut : 1 695 disparus, 1 284 en mort finale, 841 actifs, 615 inconnus, 226 en torpeur, 1 214 non renseignés.
  - Âge : 2 614 nouveau-nés, 650 anciens, 615 ancillae, 242 vénérables, 10 infants sous tutelle, 1 744 non renseignés.
  - Secte : 4 525 camaristes (77 %), 204 aubains, 178 anarchs, 32 du Sabbat.
- **5 283 informations** dans 240 notes : 94 % de sources B, 69 % cotées B3 ; 22 % solides, 5 % fragiles.
- Le premier calcul prend 1,2 à 1,4 s ; changer de répartition ou de filtre est ensuite immédiat.

**Ce que les chiffres montrent déjà**
- Parmi les 326 personnages cités au moins cinq fois, 94 % n'ont **pas de statut**.
- Le registre en connaît la plupart, mais le lot 6 ne touche pas aux fiches existantes (règle des lots).
  - 539 fiches existantes ont des champs vides que le registre remplirait : statut 424, âge 384, ville 81, clan 64.
  - 81 fiches ont une valeur différente de celle du registre, à trancher (certaines sont dans les deux cas).
  - Le détail est dans le `_lot.md` du lot 6.

**Format 1.5 : le statut `torpeur`**
- `valider.py` l'accepte, et la liste de choix de la fiche le propose.
- La préparation de séance écarte les personnes en torpeur, comme les disparus et les morts.

## 2. La 0.15 : les hypothèses concurrentes

**La méthode**
- On ne retient pas l'hypothèse qui a le plus de confirmations, mais celle qui est **la moins contredite**.
- Un élément qui va dans le sens de toutes les hypothèses ne départage rien.

**Dans vos notes : rien de nouveau à apprendre**
- Les **hypothèses** d'un dossier sont ses **indices** (propriété `indices`).
- Un élément cité dans le `pour` d'un indice est *cohérent* avec cette hypothèse ; dans son `contre`, *incohérent*.
- Les éléments à juger sans les avoir encore classés vont dans une section du dossier, « Éléments examinés » : `- [[Note#^el-…]]`.

**Le tableau** (bouton *Tableau des hypothèses* d'un dossier, ou *Hypothèses* dans Enquête → Dossiers)
- **Colonnes** : les hypothèses, avec leur rang. Le rang 1, en vert, est la moins contredite.
  - Le score est la somme des poids des éléments incohérents.
  - Le poids d'un élément est la fiabilité de sa note × sa crédibilité (table de l'Amirauté).
- **Lignes** : les éléments.
  - Ceux qui départagent viennent d'abord ; les autres sont grisés.
  - Un lien vers un élément absent est signalé en jaune.
- **Juger** : un appui sur une case la fait passer de « · » (pas jugé) à ✓ cohérent, puis ✗ incohérent, puis de nouveau « · ».
  - Le jugement s'écrit dans `pour` ou `contre` de l'indice.
  - Un élément dont on retire le dernier jugement reste dans le tableau, comme élément examiné.
  - Pendant qu'on juge, lignes et colonnes ne bougent pas ; seul le rang change.
- **+ Hypothèse** : vous écrivez l'affirmation. Elle devient un indice *non vérifié*, de crédibilité 6, avec les sujets du dossier, et s'ajoute à ses `indices`.
- **+ Élément à examiner** : un élément choisi dans vos notes s'ajoute à la section « Éléments examinés » du dossier.

**Format 1.4**
- Un indice cité par un dossier peut rester sans `pour` : `valider.py` le signale en simple information (« à compléter »), et non plus en erreur.
- Un indice qui n'est l'hypothèse d'aucun dossier doit toujours avoir au moins un `pour`.

**Pour commencer**
- Vos dossiers n'ont pas encore d'indices. Ouvrez-en un, par exemple « Qu'est-ce que l'hématothèque, et qui y a accès ? ».
- Écrivez deux ou trois hypothèses avec *+ Hypothèse*, puis jugez les éléments que vous ajoutez.

## 3. La 0.14 : à trancher, questions pour la soirée

**Enquête → À trancher** (nouvel onglet)

L'application repère ce que vos notes disent de contradictoire :

| Point | Quand |
|---|---|
| Vu à deux endroits | une personne notée à deux endroits la même nuit (comme dans les alibis) |
| Deux sires | deux sires différents pour un même infant, sur la fiche ou dans des éléments `sire_de` |
| Allié et ennemi | deux personnes dites à la fois alliées et ennemies : ont-elles changé ? |
| Poste tenu deux fois | Prince, Sénéchal, Shérif, Fléau, Maître des Harpies ou Harpie majeure d'un même lieu, écrit sur deux fiches de personnes en vie |
| Faveur et mort | des faveurs en cours dont une partie est morte ou disparue : à solder, annuler ou transmettre ? |
| Même personne ? | deux fiches marquées « peut-être la même personne », ou qui partagent un nom ou un alias |

- Les éléments de crédibilité 5 (réfutés) ne comptent pas.
- Chaque point montre les notes en cause, à ouvrir d'un appui.
  - *Fusionner…*, pour deux fiches qui sont peut-être la même personne : l'aperçu de fusion habituel, qui demande confirmation.
  - *Voir la nuit*, pour une double présence : les alibis de cette nuit-là.
  - *Écarter* : ce n'est pas une contradiction. Le choix vaut pour cet ordinateur, et *Tout réafficher* le défait.
- Sur votre coffre : 11 points, dont les 4 faveurs de Salvatore Castellucci envers Hyacinthe Dezsoli (il est en mort finale) et 10 doutes d'identité (Miranda et Marie Gauthier, Sebastian et Sébastien Guiseppe, Nix et Nyx…).

**Préparer une séance**
- **Deux colonnes.** À gauche, les alertes puis les **personnes probables dans un tableau triable** : clan, âge, postes, nombre de fois, dernière fois, et comment on le sait.
  - *vue* (en vert) : dans vos présents au moins une fois ;
  - *rapportée* : seulement par des comptes rendus ;
  - *incertaine* : seulement en présence incertaine ;
  - *rattachée* : jamais vue, fiche du domaine.

  *Avec les moins probables* ajoute, en gris, les personnes vues il y a plus d'un an. À droite : les questions, les faveurs, les tâches, les nouveautés.
- **Questions pour la soirée**, en tête de la colonne de droite :
  1. les points à trancher qui touchent une personne attendue ;
  2. vos dossiers et indices ouverts ;
  3. ce qui manque aux fiches des personnes venues au moins deux fois (« Sur Hector (Annecy), vu 8 fois : clan, statut d'âge ? »), douze au plus, les plus vues d'abord.

  *Copier* emporte ces questions dans la fiche de séance.
- **Faveurs en cours** : seulement celles dont une partie est une personne attendue, les réclamées puis les plus récentes d'abord.

**Nouvelle note**
- Le curseur est dans le premier champ (le nom d'un personnage) ; **Entrée** crée la note.
- « À compléter » n'apparaît qu'après une première saisie ou un essai de création.

## 4. La 0.13 : lisibilité, suite

**Recherche au clavier** (Fiches)
- **Ctrl+F**, quelques lettres, puis **Entrée** : la première fiche trouvée s'ouvre.
- Le nom exact vient en tête, puis les noms qui commencent par ce que vous avez tapé, puis ceux qui le contiennent, puis le texte. « valomb » ouvre donc le domaine Valombre plutôt qu'une soirée qui contient le mot.
- **↓** passe dans le tableau et **Entrée** ouvre la ligne choisie ; **↑** sur la première ligne, ou **Échap**, revient à la recherche.

**Rapport de soirée : présences rapportées en étiquettes**
- Une étiquette par personne (nom et âge), rangée par clan : les 21 présences d'un compte rendu de Grenoble tiennent sur un écran.
- Le survol d'un nom donne ses points de statut, postes et reconnaissances.
- Un appui ouvre un menu : *Ouvrir la fiche*, *Lire le compte rendu*, *Je l'ai vu(e)*. Ce dernier l'ajoute à vos présents.
- Le compte rendu n'est cité qu'une fois, en tête, avec *Lire le compte rendu*.
- Les menus et listes déroulantes de toute l'application sont aux couleurs de l'interface.

**Graphe**
- Quand la souris passe sur un lien, une bulle dit **tous les liens entre les deux fiches** : le sens, la relation, et la source avec sa crédibilité.
- À faible zoom, le nom d'un point s'écrit dès qu'on le survole.
- La **légende reste visible** dans le panneau de droite, avec les vrais traits, tirets et points.

**Enquête → Informateurs**
- En tête, un encadré **À revoir** liste ceux dont la lettre proposée diffère de la fiche, avec *Appliquer*.
- Tous les informateurs suivent dans un **tableau triable** : lettre proposée, lettre actuelle, affirmations confirmées, réfutées, non tranchées.

**Préparer une séance**
- L'écran s'ouvre sur le dernier domaine choisi dans un formulaire, sinon sur celui de la soirée la plus récente, et non plus sur le premier domaine par ordre alphabétique.
- **Personnes probables** : celles vues dans le domaine depuis moins d'un an. Les autres (vues avant, ou seulement rattachées au domaine) sont repliées à part.
- **Morts et disparus** : écartés des personnes probables. L'alerte ne les rappelle que s'ils ont été vus ici depuis moins d'un an, et la sanction d'un mort (Chasse au Sang…) n'est plus signalée.
- Sur votre coffre, pour Grenoble : 5 alertes au lieu de 21, et 67 personnes probables au lieu de 422.
- *Son rapport* ouvre directement le rapport de la dernière soirée.

## 5. La 0.12 : corbeille et lisibilité

**Supprimer une note**
- Bouton **Supprimer…**, en rouge, sur une note. La confirmation dit combien de notes la citent encore : leurs liens mèneront à une note absente.
- La note n'est pas effacée. Elle part dans le dossier `.trash/` du coffre, à son chemin d'origine (`.trash/Personnages/X.md`).
  - C'est la corbeille d'Obsidian : ni l'application ni Obsidian ne la lisent plus.
  - Git y voit un simple déplacement.
- **Réglages → Corbeille** liste les notes supprimées, les plus récentes d'abord, y compris celles qu'Obsidian y a mises.
  - *Restaurer* remet la note à sa place. Rien n'est écrasé : si une note du même nom existe déjà, la restauration est refusée.
  - *Effacer…* et *Vider la corbeille…* effacent pour de bon, après confirmation, et seulement dans `.trash/`.
- Une note modifiée ailleurs depuis son ouverture n'est pas déplacée.

**La fiche** (personnage, groupe, lieu…)
- En tête, des étiquettes : clan, statut d'âge, secte, domaine, postes, statut.
- Puis les actions (graphe, chemin, où était-il, surveiller, fusionner) et vos notes.
- **« Ce que disent vos sources »** passe dans la colonne large : les présences sur une ligne de temps, les mentions dépliées.
- Le formulaire des propriétés et les rétroliens restent dans le panneau de droite.
- Les boîtes de dialogue sont en français et aux couleurs de l'application.

**Fiches : un tableau**
- Les types se choisissent d'un appui, avec leur nombre (« Personnage 1271 »). Toutes les fiches du type s'affichent : plus de limite à 300.
- Une colonne par propriété utile :
  - personnage : clan, âge, secte, domaine, statut ;
  - faveur : niveau, débiteur, créancier, statut ;
  - source : nature, auteur, fiabilité ; et ainsi de suite.
- **Un appui sur un titre de colonne trie la liste**, un second inverse l'ordre. L'âge se trie du Vénérable au Nouveau-né, pas par ordre alphabétique.
- Soirées, sources, faveurs et événements vont du plus récent au plus ancien.
- Seules les exceptions ressortent : « Mort finale » ou « Disparu » en orange, « Actif » n'est pas répété.
- La recherche va jusqu'à 1 000 résultats, et se trie de même.

**Accueil**
- La carte des notes rapides n'apparaît que s'il y a quelque chose à trier. Sinon, la tuile *Note rapide* le dit.
- Nouvelle tuile *Alibis*.
- En bas, deux colonnes :
  - les **dernières soirées**, chacune avec un bouton *Rapport* ;
  - les notes **modifiées récemment**, avec leur type et l'heure ou la date.

**Enquête**
- **Alibis → Telle nuit** : les présents d'un lieu sont regroupés par source. La source est écrite une fois, avec *Lire la source*, puis viennent les noms en étiquettes. Un lieu seul prend toute la largeur.
- **Chronologie** : les faits d'une même source à une même date forment une seule entrée, un fait par ligne. Les présences y sont réunies par lieu. Sur votre coffre avec le lot de Grenoble, on passe de 4 429 entrées à 1 234.
- **Faveurs** : un tableau « qui doit à qui ».
  - Une ligne par couple : combien, de quel niveau, la plus récente, l'état, les non enregistrées, une Chasse au Sang.
  - Un couple qui a plusieurs faveurs se déplie d'un appui ; une faveur s'ouvre d'un appui.
- Les onglets vides (indices, dossiers, à faire) disent à quoi ils servent et comment les remplir.

**Rapport de soirée : présences rapportées**
- Les présences citées par un compte rendu rattaché à la soirée (éléments « était présent à ») sont listées à part, sous vos présents, rangées par clan.
- Elles ne se mélangent pas à vos présents :
  - *Je l'ai vu(e)* en fait un présent ;
  - *Compte rendu* ouvre la source.
- Elles ne sont plus répétées dans les informations.

## 6. La 0.11 : les alibis

L'application calcule **où était chacun**, d'après vos notes. Elle n'écrit rien.

**D'où viennent les présences**

| Source | Force de la présence |
|---|---|
| Présents d'une soirée | sûre |
| Présents incertains | douteuse |
| Absences remarquées | absence |
| Participants d'un événement | sûre s'il est corroboré, probable sinon ; rien s'il est réfuté |
| Élément « était présent à » | crédibilité 1–2 : sûre ; 3 (ou 6) : probable ; 4–5 : douteuse. Une déduction ou une hypothèse reste douteuse. |
| Indice « était présent à » | sûre s'il est corroboré, probable si sa crédibilité est 2 ou 3, douteuse sinon ; rien s'il est réfuté |

- **La date** : la date des faits de l'élément, sinon celle de la soirée ou de l'événement visé, sinon celle de la soirée où l'élément est noté. Une soirée datée du 14 couvre la nuit du 14 au 15.
- **Ailleurs** : deux présences sont à des endroits différents quand leurs lieux sont connus et différents ; à défaut de lieux, quand leurs domaines diffèrent. Sinon, on ne sait pas : ni alibi, ni contradiction.
- Seules les présences sûres ou probables fournissent un alibi ou une contradiction.

**Enquête → Alibis**, trois vues :
- **Telle nuit** : une nuit documentée dans la liste, ou une date tapée (2026-10-14).
  - Un cadre par lieu, avec ses présents.
  - En tête et en rouge, les personnes notées à deux endroits cette nuit-là.
  - En gris, les absences remarquées et les présences douteuses.
  - En dessous, à titre indicatif, les présences à une date approximative qui inclut ce jour (« en octobre »).
- **Incidents en commun** : cochez des événements ou des soirées, puis lisez le tableau personnes × incidents.

  | Case | Sens |
  |---|---|
  | ● sur place | à l'incident lui-même, ou à son lieu le même jour ; sûr, probable ou douteux |
  | ⚠ mais vu ailleurs | sur place, mais aussi noté ailleurs cette nuit-là |
  | ✗ vu ailleurs | un alibi : présence sûre ou probable, la même nuit, ailleurs |
  | ✗ absence remarquée | absent de cette soirée |
  | ≈ date compatible | à son lieu, à une date approximative qui recouvre celle de l'incident |
  | · dans le domaine | même nuit, même domaine, lieu inconnu |

  - En tête : qui était sur place à **tous** les incidents choisis.
  - Le survol d'une case dit d'où vient l'information ; un clic sur un nom ouvre sa fiche.
  - Les personnes vues ailleurs à chaque incident ne sont pas listées.
- **Une personne** : ses présences sur la ligne de temps, la date au survol, et en rouge les nuits où elle est notée à deux endroits.

**Sur les fiches**
- **Personnage** : la section « Présences aux soirées » devient **« Où était-il ? »**, une ligne de temps compacte. Son titre signale les nuits où la personne est notée à deux endroits.
- **Soirée** : boutons *Qui était où cette nuit-là* et *Comparer à d'autres incidents*.
- **Événement** : bouton *Comparer à d'autres incidents*.

**Pour en tirer parti**
- Notez les présents des soirées, ainsi que les participants et le lieu des événements.
- Donnez une date au jour près quand vous la connaissez.
- Pour un témoignage (« X était aux docks ce soir-là »), ajoutez un élément « était présent à » avec la date des faits.

## 7. La 0.10 : la fiabilité calculée des informateurs

L'application **propose** la lettre A–F d'un personnage comme informateur, d'après ce qu'il a affirmé et ce qu'il en est advenu. Elle n'écrit rien sans votre accord.

**Ses affirmations**
- Les éléments dont il est la voix : champ « Dit par » (`par`). Sans ce champ, c'est l'auteur de la source, ou à défaut celui qui l'a transmise (`rapporteur`).
- Seuls comptent les éléments observés, rapportés ou les rumeurs. Les déductions et hypothèses ne sont pas les siennes, et les analyses sont exclues.

**Ce qu'il en est advenu**
1. D'abord les **indices et événements** qui citent l'affirmation :

| L'affirmation est… | dans un indice corroboré (ou obsolète) | dans un indice réfuté |
|---|---|---|
| dans `pour` | confirmée | réfutée |
| dans `contre` | réfutée | confirmée |

   Contesté ou non vérifié : non tranchée. Des verdicts contradictoires : non tranchée.
2. Sinon, sa **crédibilité** : 1 = confirmée, 5 = réfutée. Les autres ne tranchent pas.

**La lettre proposée**

| Affirmations tranchées | Lettre |
|---|---|
| moins de 3 | F (ne peut être évaluée) |
| au moins 8, aucune réfutée | A |
| 80 % confirmées ou plus | B |
| 60 % ou plus | C |
| 40 % ou plus | D |
| moins | E |

**Où la voir**
- Sur la **fiche** d'un personnage, dans le panneau de droite : « Fiabilité comme informateur ». On y voit la lettre proposée et l'actuelle, le bilan, puis chaque affirmation (réfutées d'abord) avec la note qui la tranche ; un clic ouvre la note.
- Dans **Enquête → Informateurs** : tous les informateurs. Ceux dont la lettre proposée diffère de la fiche viennent d'abord, en or.
- **Appliquer** écrit la lettre dans la fiche (propriété `fiabilite`), qui sert ensuite aux chemins probables.

## 8. La 0.9 : les alertes

**Où les voir**
- Sur l'**accueil**, une carte rouge : le nombre d'alertes, dont les urgentes, et les cinq premières.
- Dans **Enquête → Alertes** : toutes, les urgentes d'abord.
- Un clic ouvre la note concernée.

**Ce qui est signalé**

| Alerte | Quand | Niveau |
|---|---|---|
| Échéance | une reconnaissance, une tance, une nomination ou une probation avec `jusqu_au` qui expire dans les 30 jours | à surveiller |
| Échéance passée | la même, expirée depuis moins de 30 jours | pour information |
| Faveur en retard | une faveur **réclamée** dont le délai est dépassé, compté depuis le mouvement « reclamation » | urgent |
| Faveur sans date | une faveur réclamée sans mouvement « reclamation » : le délai ne peut pas être suivi | pour information |
| Sanction | Chasse au Sang (urgent) ; parjure, liste écarlate, paria, banni (à surveiller). Rien pour un personnage en mort finale. | selon le cas |
| Faveur et sanction | une faveur encore active dont une partie est chassée ou parjure : à suspendre ou à annuler ? | à surveiller |
| Personne surveillée | un nouvel élément qui la cite | à surveiller |

- **Délais des faveurs** : ceux de votre configuration (`faveurs`, dans `.nosferatu/config.json`), sinon ceux du format.
  - triviale : 1 séance ;
  - mineure : 2 séances et 1 mois ;
  - majeure : 6 séances et 3 mois ;
  - sang et vie : pas de délai, donc pas d'alerte.

  Les séances sont les soirées du domaine de la faveur tenues depuis la réclamation.

**Surveiller une personne**
- Bouton **Surveiller** sur une fiche de personnage ou de groupe. Il ajoute l'étiquette `surveille`, qu'Obsidian voit aussi.
- Ce qui est déjà connu ne fait pas d'alerte : seuls les éléments suivants qui la citent sont signalés.
- Ouvrir sa fiche vaut consultation : l'alerte disparaît. Le bouton **Vu**, dans la liste d'alertes, fait de même sans ouvrir la fiche.
- Ce qui a été vu est retenu sur chaque ordinateur ; la note n'est pas modifiée pour cela.
- **Ne plus surveiller** retire l'étiquette.

## 9. La 0.8 : version PC, plein écran

**PC seulement, en plein écran**
- L'application démarre en plein écran. **F11**, ou Réglages → *Plein écran / fenêtre*, bascule ; le choix est retenu.
- La version Android est retirée pour l'instant, avec ses tests : préréglage d'export, disposition téléphone, permissions, clavier virtuel.

**Menus escamotables**
- Une flèche **‹ ›** au bord de l'écran cache un menu ou le fait revenir. L'espace libéré va à l'écran de travail, et l'état de chaque menu est retenu.
- **Menu de gauche** : aussi avec **Ctrl+B**.
- **Graphe** : il occupe toute la place. Les commandes, les filtres et les liens du point choisi sont dans un panneau à droite.
- **Note** : le texte et l'ajout d'élément à gauche ; la fiche (propriétés, renseignements calculés, rétroliens) dans un panneau à droite.

**Lisibilité**
- En plein écran, le texte des notes, des formulaires, de la séance et des réglages tient dans une colonne de lecture centrée : plus de lignes de 1 800 pixels.
- Le rapport de soirée met côte à côte les présents et les informations.
- Les titres ne se coupent plus au milieu d'un mot.

**Chronologie sur une ligne verticale** (Enquête → Chronologie)
- Plus de date écrite : chaque entrée est un point sur une ligne continue, de la plus récente à la plus ancienne.
- **La date s'affiche au survol**, à gauche de la ligne.
- Point plein : date exacte. Cercle : date approximative ou incertaine. Un trait sur la ligne marque le changement d'année.
- Les dates en tête des noms de notes (« 2026-10-12 Gazette… ») ne sont plus affichées dans la chronologie.

## 10. Rappel de la 0.7

**Listes « nature » des sources**
- Chaque nature est précédée de sa fiabilité par défaut : « B · Note personnelle », « C · Discord », « F · Analyse »…
- C'est un simple affichage : le nom des fichiers ne change pas.

**Le graphe**
- Il se dézoome beaucoup plus : jusqu'à voir un coffre entier d'un coup.
- Le bouton **Voir tout** cadre tous les points. Tant que vous ne touchez pas au zoom, le graphe se recadre seul pendant qu'il se met en place.
- Sans fiche au centre, vous choisissez le nombre de fiches : 120 ou 300 les plus reliées, ou **toutes**.
- Les points ne s'éparpillent plus : un grand coffre reste compact, et la mise en place est trois à quatre fois plus rapide (environ 20 ms par étape pour 1 000 fiches).
- À faible zoom, seuls les noms utiles restent écrits : le point touché, ses voisins, le centre.

**Chemin entre deux fiches** (Enquête → *Chemin entre deux fiches*, bouton *Chemin vers…* d'une fiche, ou *Chemin depuis ici* sur un point du graphe)
- Vous choisissez un départ et une arrivée. L'écran montre les 3, 5 ou 8 chemins **les plus probables**, du plus sûr au moins sûr.
- Chaque lien vaut **fiabilité de la source × crédibilité de l'information** :

| Amirauté | A ou 1 | B ou 2 | C ou 3 | D ou 4 | E ou 5 | F ou 6 |
|---|---|---|---|---|---|---|
| Valeur | 0,95 | 0,8 | 0,6 | 0,4 | 0,2 | 0,5 (neutre) |

  Exemple : une conversation notée C sur une information notée 2 vaut 0,6 × 0,8 = 48 %. Un chemin vaut le produit de ses liens.
- La fiabilité est celle de la personne qui parle (`par`) si vous l'avez évaluée, sinon celle de la note.
- Un lien attesté par plusieurs notes ou personnes différentes est **renforcé**. Deux mentions de la même note ou de la même personne ne comptent qu'une fois, et un indice ne fait qu'un avec les éléments qu'il cite.
- Pour chaque étape : la relation, la note d'origine, sa date, sa cote A–F/1–6. Un clic ouvre la note.
- **Filtres** :
  - relations, indices ;
  - faveurs : le « chemin de levier » ;
  - clan, secte, domaine : exclus par défaut, sinon tout le monde est relié par la Camarilla ;
  - vus ensemble en soirée ;
  - types de relations à exclure ;
  - crédibilité maximale ;
  - ignorer F et 6 ;
  - période : 10, 5, 2 ans ou la dernière année.
- La table de conversion se règle dans `.nosferatu/config.json` (FORMAT.md §17).

**Rapport de soirée** (tuile de l'accueil, Enquête, ou bouton *Rapport de soirée* d'une soirée)
- **Présents** :
  - rangés par clan, dans l'ordre de **préséance du domaine** ;
  - puis par statut d'âge, du plus vieux au plus jeune ;
  - puis par postes, puis par reconnaissances et tances **en cours à la date de la soirée**.
- Pour chacun : statut d'âge, **points de statut**, postes, reconnaissances et tances, avec qui les a données. Les expirées et les douteuses sont affichées mais pas comptées. Un poste d'un autre domaine (« Prévôt de Lyon » à Grenoble) ne compte pas.
- On ajoute un présent d'après une fiche existante, ou en créant une fiche minimale. On le retire, ou on le passe en « incertain ».
- **Informations** : les éléments de la soirée, ceux des sources rattachées à la soirée (propriété *Soirée concernée*, par exemple une conversation tenue ce soir-là), et les éléments ou notes que vous y liez.
  - Les flèches ↑ ↓ changent l'ordre. Il est enregistré dans la soirée (propriété `rapport`).
  - La **fiabilité (A–F)** et la **crédibilité (1–6)** se modifient sur place. Elles s'écrivent dans la note d'origine de l'information.
  - *+ Nouvelle* écrit une information dans la soirée.
- **Copier le texte** : un rapport prêt à publier sur le forum ou Discord, avec les présentations protocolaires, les informations dans l'ordre et votre signature (`moi` dans la configuration).
  - Par défaut, sans les cotes et sans vos hypothèses ni déductions.
  - Deux boutons les ajoutent.
- **Préséance** : sur la fiche du domaine, propriété *Préséance des clans*. Une lignée suit son clan d'origine.
- **Points de statut** : barème par défaut de 1 point par poste du domaine, +1 par reconnaissance, −1 par tance. Il se règle selon votre chronique dans la configuration, section `statut` (FORMAT.md §17).

**Échéance d'un élément**
- *Plus de détails → Jusqu'au* : pour une reconnaissance, une tance ou une nomination « pour trois mois ».
- Elle s'écrit `[jusqu_au:: 2026-11-28]`. Une échéance au mois (`2026-12`) court jusqu'à la fin du mois.

**Fusionner deux fiches** (bouton sur une fiche de personnage, de groupe, de lieu…)
- Vous choisissez l'autre fiche. Un aperçu montre ce qui sera écrit, avec un bouton pour garder l'autre fiche.
- La fiche gardée reçoit les propriétés qui lui manquaient, les alias de l'autre et son nom en alias, son texte (section « Repris de … ») et ses éléments.
- Les liens suivent sans changer le texte affiché : `[[Inconnu - Manteau gris]]` devient `[[Victor Morel|Inconnu - Manteau gris]]`.
- Une personne déjà présente à une soirée n'y reste pas en « incertain ».
- **Rien n'est supprimé** : l'ancienne fiche devient une note de renvoi qui garde son contenu d'origine en entier.
- Si une note a été modifiée ailleurs pendant ce temps, tout s'arrête, et l'écran dit ce qui a déjà été écrit.
- Synchronisez avec Git juste avant : c'est votre retour en arrière.

**Identifiants manquants**
- Une note dont des éléments n'ont pas d'identifiant le signale, avec le bouton *Attribuer les identifiants manquants*.
- Seuls `^el-…` et `^mv-…` sont ajoutés en fin de ligne.
- Le rapport de soirée les attribue aussi, au premier déplacement d'une information.

**Corrigé**
- Une source créée sans canal ne s'appelle plus « … null - … ».

**Format 1.3**

Tout est facultatif, et aucune note existante ne change :
- `jusqu_au`, l'échéance d'un élément ;
- `preseance`, sur un domaine ;
- `rapport`, sur une soirée ;
- la note de renvoi d'une fiche fusionnée ;
- les sections `moi`, `preseance`, `amiraute` et `statut` de `.nosferatu/config.json` (FORMAT.md §17).

`valider.py` les connaît.

## 11. Installation

1. Décompressez l'archive à la place de l'ancienne.
2. Ouvrez `project.godot` dans Godot 4.7.x.
3. Lancez avec F5. Vos réglages et le chemin du coffre sont conservés.
4. Pour un exécutable : Projet → Exporter → Windows (ou Linux).

L'index ne change pas de version : pas de reconstruction au premier lancement.

## 12. Ce que j'ai vérifié de mon côté

- **704 vérifications automatiques** réussies.
  - Statistiques : informations et rétroliens d'une fiche (la note elle-même exclue), disciplines de la fiche et constatées comptées une fois, filtres par statut et par nombres, répartitions (le non renseigné en dernier), cote de l'Amirauté, ordre de l'échelle, années (date des faits, sinon de la note), voix, chiffres clés.
  - Hypothèses concurrentes : lecture des indices d'un dossier, éléments examinés, élément introuvable, poids, éléments qui départagent, classement ; écriture d'un jugement (et son retrait sans toucher aux autres), nouvelle hypothèse ajoutée au dossier, élément à examiner.
  - `valider.py` 1.5 : statut `torpeur` ; hypothèse de dossier sans `pour` en information, indice isolé sans `pour` en erreur.
  - Points à trancher, questions pour la soirée, recherche, préparation de séance (la torpeur écartée comme la mort), tableau triable, corbeille, liste des fiches, rapport de soirée, alibis, fiabilité calculée, alertes.
- **Parcours automatique de l'interface** en 1920 × 1080 : 146 vérifications réussies, dont : les statistiques (une part choisie détaille ses personnages, le filtre « au moins une information », « Masquer « Aucune connue » », une case de la grille de l'Amirauté liste ses informations) ; le tableau des hypothèses ; l'onglet À trancher ; supprimer une note puis la restaurer.
- **Sur une copie de votre coffre avec les lots 5 et 6** (6 660 notes) :
  - le lot 6 s'intègre sans problème : 4 627 notes ajoutées, aucune note existante modifiée ;
  - statistiques : 1,2 à 1,4 s au premier calcul ;
  - À trancher : 89 points, dont 88 doutes d'identité (les homonymes du registre marqués « peut-être »).
- **Pas vérifié** : l'affichage sur votre écran (taille, mise à l'échelle) et le presse-papiers de Windows.

## 13. Vos données

- Le Markdown reste la seule source de vérité. L'index se reconstruit à tout moment.
- Toute écriture est sûre :
  - elle passe par un fichier temporaire, puis elle est vérifiée ;
  - un conflit avec GitSync ou Obsidian est détecté, et votre version est gardée dans `_Conflits/`.
- L'application n'efface aucune note d'elle-même. *Supprimer…* déplace la note dans la corbeille `.trash/`, d'où on la restaure ; seul l'effacement depuis la corbeille, après confirmation, supprime un fichier.
- Elle ne modifie jamais une note à partir d'un lot : elle n'ajoute que des notes neuves.

## 14. Arborescence

```
core/model/      types de notes, champs, listes de choix, noms de fichiers ; dates floues
core/format/     propriétés, note, lignes structurées, identifiants
core/storage/    accès au dossier, écriture sûre, corbeille
core/index/      index SQLite, recherche, requêtes de l'enquête
core/sync/       synchronisation et vérification
core/analysis/   graphe, chemins probables, rapport de soirée, alertes, informateurs, alibis, points à trancher, hypothèses concurrentes, préparation de séance, statistiques
core/exchange/   export pour Claude, import des lots
core/app/        façade AppService, fusion de fiches, banc
ui/screens/      accueil, nouvelle note, fiches, note, enquête, graphe et chemins, rapport, séance, hypothèses, statistiques, échanges, réglages, diagnostic, banc
ui/widgets/      éditeur de champ, sélecteur, renseignements calculés, vue du graphe, fusion, tableau triable,
                 panneau escamotable, colonne de lecture, ligne de temps, liste d'alertes, fiabilité d'un informateur, alibis, camembert
tests/, tools/   tests, parcours d'interface, captures, contrôle d'un lot réel, valider.py
```
