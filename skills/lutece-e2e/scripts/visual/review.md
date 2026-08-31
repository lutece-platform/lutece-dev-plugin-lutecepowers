# Revue visuelle IA (Phase 4) — procédure

> ## ⚠️ Confidentialité — à lire avant d'ouvrir la première capture
>
> Les captures d'un environnement de recette contiennent des **données personnelles réelles** :
> noms de sociétés, noms et prénoms, adresses postales, numéros de téléphone, adresses de courriel.
> Un passage complet en produit vite plusieurs centaines (run réel : **199 PNG**, plus un **PDF de
> 18 Mo** qui les agrège toutes).
>
> Règles, sans exception :
> - **ne pas versionner** `report/screenshots/`, `report/rapport.pdf`, `report/rapport.html`,
>   `preuves/`, ni les captures collées dans un compte rendu ;
> - **ne pas transmettre** le PDF de rapport hors du cercle habilité à voir ces données — c'est le
>   fichier le plus dangereux du lot, parce qu'il concentre tout en une pièce jointe ;
> - le **projet de tests reste hors du dépôt applicatif** ; vérifier qu'il y reste (un `git status`
>   dans le dépôt applicatif ne doit jamais mentionner ces fichiers) ;
> - les preuves durables vont dans **`preuves/`** — archive **locale, non versionnée**, écrite par
>   `capturePreuve()` et **jamais purgée**. C'est l'endroit prévu pour ce qu'on veut garder.
> - dans `report/revue-visuelle.md`, décrire les défauts **sans recopier** de données personnelles
>   (écrire « le champ *Nom de la société* est coupé », pas la valeur du champ).
>
> Pas de floutage automatique : il n'est **pas** implémenté, et ne doit pas être supposé.

Analyse par Claude (vision) des captures produites par la suite. **Hors** `npx playwright test`
(la suite reste sans IA). Complète `assertLayout` (déterministe) sur ce qu'une heuristique ne peut juger.

> Prérequis : un run **SANS** `--reporter` override (sinon le reporter PDF n'écrit pas les captures dans
> `report/screenshots/`). Puis `node scripts/visual/prep-review.mjs` → `.artifacts/visual-manifest.json`.
> `prep-review.mjs` **écarte les doublons de libellé** et ne garde que la **dernière** capture (état
> final) : il journalise combien de captures sont écartées et lesquelles. `VISUAL_ALL=1` conserve tout
> (nécessaire dès qu'on veut juger un **enchaînement** d'états et pas seulement l'état final).

## Ce que Claude fait

1. Lire `.artifacts/visual-manifest.json` (`[{file, label}]`).
2. Par lots de ~10 captures, **Read** chaque `file` (image) et évaluer selon la checklist.
3. **Mesurer** chaque constat candidat avant de l'écrire (section suivante — c'est obligatoire).
4. Écrire `report/revue-visuelle.md` : couverture de la revue, synthèse, findings par sévérité,
   détail par page, constats retirés.

## Mesurer avant de conclure — obligatoire

**Une lecture d'image produit une hypothèse, pas un constat.** Sur un run réel, deux constats
parfaitement plausibles étaient faux et ont dû être rétractés publiquement :

- « **deux onglets vides** encadrent les onglets réels » → mesure DOM : **5 onglets, aucun vide**,
  de x=269 à x=1171. Les blocs sombres pris pour des onglets étaient **l'espace de part et d'autre
  d'une barre centrée**, laissant voir le panneau sombre de la page ;
- titre « **Weaving \_ \_ \_ Memories** », lu comme des caractères perdus → vérification en base :
  `HEX()` donne `5F` (tiret bas). La valeur stockée est **exactement** celle-là : **pas un défaut**.

D'où la règle : **aucun finding `bug` ou `warn` n'est écrit sans une mesure**, et la mesure figure
dans le texte du constat (chiffre + méthode). Correspondance obligatoire :

| Nature du constat | Mesure exigée | Comment |
|---|---|---|
| Géométrie : superposition, débordement, élément coupé, distance, taille | `getBoundingClientRect()` sur les deux éléments en cause | `page.evaluate` → comparer `right`/`left`/`top`/`bottom` et donner les px |
| Comptage : « n onglets/colonnes/lignes vides », « bloc en double » | comptage **par le DOM** | `document.querySelectorAll(sel).length`, et pour « vide » : `el.textContent.trim() === ''` |
| Valeur affichée douteuse (caractères perdus, mojibake, clé i18n brute) | valeur **en base** | `SELECT HEX(col) FROM t WHERE …` — si la base porte déjà cette valeur, ce n'est pas un défaut de rendu |
| Contraste, « couleur pâle », « illisible » | **ratio WCAG calculé** | luminance relative des deux couleurs effectives (`getComputedStyle`) → ratio ; seuil AA = **4,5:1** (3:1 pour texte ≥ 24 px ou ≥ 19 px gras) |
| Troncature d'un libellé | comparer texte rendu et texte source | `el.scrollWidth > el.clientWidth`, ou la chaîne du bundle i18n / de la base |
| Image cassée | état de chargement | `img.naturalWidth === 0` |
| Texte non traduit / en anglais | **locale du run** (voir plus bas) puis bundle i18n | rejouer avec `Accept-Language: fr-FR` **avant** de conclure |

Le run réel a mesuré des ratios de **1,90:1 à 4,66:1** : écrire « contraste faible » sans chiffre,
c'est se priver de savoir si l'écran échoue à 4,4 ou à 1,9 — et de savoir, après correction, qu'il
passe. Corriger une couleur « à l'estime » produit une seconde passe pour rien.

Mesure type (à lancer contre le même écran, session admin réutilisée) :

```ts
// tests/_mesure.spec.ts — spec jetable, à supprimer après usage
const m = await page.evaluate(() => {
  const lum = (c: string) => {
    const [r, g, b] = c.match(/\d+(\.\d+)?/g)!.slice(0, 3).map(Number)
      .map((v) => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; });
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };
  const ratio = (a: string, b: string) => {
    const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p);
    return Number(((x + 0.05) / (y + 0.05)).toFixed(2));
  };
  return [...document.querySelectorAll('.nav-link')].map((el) => {
    const st = getComputedStyle(el as HTMLElement);
    const r = el.getBoundingClientRect();
    return {
      texte: (el.textContent || '').trim(),
      vide: (el.textContent || '').trim() === '',
      boite: { x: Math.round(r.x), w: Math.round(r.width) },
      contraste: ratio(st.color, st.backgroundColor),
    };
  });
});
```

Vérification d'une valeur en base (identifiants du projet) :

```bash
mysql -u "$DB_USER" -p"$DB_PASSWORD" -D "$DB_NAME" -e "SELECT id, HEX(titre) FROM <table> WHERE titre LIKE '%<motif>%'"
```

## Statut par capture : conforme / défaut / **non instruite**

Un statut par capture, et **jamais de conforme par défaut** :

- **conforme** — la capture a été ouverte et regardée, checklist passée ;
- **défaut** (`bug`/`warn`) — regardée **et mesurée** ;
- **non instruite** — pas ouverte, ou ouverte sans que la vérification soit allée au bout.
  Une capture non instruite **ne prouve rien** : elle n'est ni conforme, ni non conforme.

`report/revue-visuelle.md` **doit** commencer par une section « Couverture de cette revue » qui donne
`n regardées / m au manifeste` et un tableau des non instruites, motif et **risque résiduel** :

```markdown
## Couverture de cette revue — à lire d'abord

**11 captures sur 85 ont été effectivement regardées.** Ce n'est pas un échantillon aléatoire : …

| Non examiné | Nombre | Risque résiduel |
|---|---|---|
| Variantes des mêmes écrans (tri, filtre sans résultat) | ~30 | faible — même gabarit |
| Écrans du socle non touchés par le lot | 39 | faible — sondage antérieur |
| Captures des specs en échec d'environnement | 5 | nul — elles ne montrent pas le site |
```

Cette section est ce qui rend la revue honnête : 11 écrans instruits et déclarés tels valent mieux
que 85 écrans déclarés « OK » sans preuve. Sur la même logique, une capture issue d'un test
**non applicable** ou **environnement absent** (badges du rapport) ne montre pas le site : la classer
non instruite, motif « ne montre pas le produit ».

## Une capture prouve ce qui est rendu *dans les conditions du test*

Leçon du run réel : deux constats « libellés en anglais » (page de connexion, page 404) étaient dus à
la **locale `en-US` du Chromium de Playwright**, pas au site. Le bundle français existait et portait
les clés ; rejoué avec `Accept-Language: fr-FR`, l'écran rend « Code d'accès », « S'identifier »,
« Page introuvable ». Le constat était faux, et publié.

Les conditions du test font donc partie du constat. À vérifier **avant** toute conclusion sur :

| Condition | Ce qu'elle peut faire croire | Contrôle |
|---|---|---|
| **locale du navigateur** (`locale`, `Accept-Language`) | « non traduit », « en anglais » | rejouer en `fr-FR` ; ne signaler que ce qui reste (ex. un libellé figé en dur dans le gabarit) |
| viewport (largeur, `deviceScaleFactor`) | « débordement », « éléments empilés » | mesurer aussi au viewport de la config |
| thème / mode sombre | « contraste faible », « fond noir » | relever la classe/attribut de thème appliqué |
| données de la base | « champ vide », « caractères perdus » | `HEX()` en base |
| état de session / droits | « page d'erreur », « accès refusé » | vérifier l'authentification et `core_user_right` |
| fuseau/format de date | « date fausse » | comparer à la valeur en base |

Ce qui **survit** à ces contrôles est un vrai constat, et il est alors solide.

## Rétracter un constat faux, visiblement

Un constat faux publié coûte la confiance dans toute la revue. Quand la mesure démentit :

1. **ne pas supprimer** le constat de `revue-visuelle.md` — le **barrer** (`~~…~~`) et écrire en
   clair « **constat faux, retiré** » avec la mesure qui l'a démenti ;
2. le signaler dans la synthèse (encadré « constats démentis à l'instruction ») pour que le lecteur
   pressé ne reparte pas avec l'erreur ;
3. garder ce qui subsiste du constat s'il en reste une part vraie, en le disant.

Ce coût est la raison de la section « mesurer avant de conclure ». Un constat visuel plausible mais
faux est le **principal risque** de cet exercice — bien avant le risque de rater un défaut.

## Checklist par capture

| # | Vérifier | Mesure si le constat est retenu |
|---|---|---|
| 1 | **CSS/thème appliqué** — pas de page « HTML brut » non stylée | feuille(s) chargée(s), `getComputedStyle` d'un élément témoin |
| 2 | **Pas de superposition** — aucun élément ne recouvre un autre | rectangles des deux éléments (px) |
| 3 | **Texte non tronqué** — pas de libellé coupé / débordant | `scrollWidth > clientWidth` + texte source |
| 4 | **Alignement / grille** cohérents | `left`/`width` des colonnes comparés |
| 5 | **Images/icônes chargées** | `naturalWidth === 0` |
| 6 | **Rien hors écran** — pas de débordement horizontal | `scrollWidth` du document vs viewport |
| 7 | **Cohérence de skin** — FO (thème du site) / BO (Tabler) | classes/famille de boutons relevées sur les deux écrans comparés |
| 8 | **Aspect « inachevé / placeholder »** — visuel générique, zone en attente | source de l'image / clé de propriété non configurée |
| 9 | **Proportions** — élément **disproportionné** par rapport à ses voisins | tailles des voisins (px) |
| 10 | **Densité de la page** — page anormalement **vide/courte** | hauteur du contenu, nombre de blocs ; trancher : design voulu ou contenu manquant |
| 11 | **Contraste** du texte sur son fond | **ratio WCAG calculé**, seuil 4,5:1 |
| 12 | **Contenu qui ne devrait pas être là** — script en texte brut, texte promotionnel du framework, hôte interne, marque d'un autre produit | présence dans le DOM (`n` occurrences, dont `0` dans `<script>`) et gabarit fautif |

> Les points 8-10 sont **précisément** ce que la couche déterministe ne peut pas juger : une page peut
> avoir « CSS chargé + 0 image cassée + 0 erreur » et pourtant **paraître bizarre**. Les points 11-12
> viennent du terrain : le contraste parce qu'il se juge faux à l'œil, et le contenu parasite parce
> que c'est le défaut le plus grave trouvé par le run réel (du JavaScript Matomo affiché en clair, avec
> un nom d'hôte interne, sur **toutes** les pages publiques).

## Format de finding

`{ severite: info | warn | bug, page: <label>, constat: <description courte, actionnable, AVEC la mesure> }`

- **bug** : rendu cassé ou contenu indu (CSS absent, superposition mesurée, contraste < 4,5:1, texte
  parasite) ;
- **warn** : imperfection (désalignement mesuré, troncature mineure) ;
- **info** : remarque sans anomalie.

Le schéma du workflow n'accepte que ces trois champs : la mesure va **dans `constat`**
(« onglets désactivés #51616f sur #898c95 → **1,90:1** (< 4,5:1) »), pas dans un champ à part.
Un constat sans mesure reste un **candidat** : à instruire dans la boucle principale, ou à publier
explicitement comme hypothèse non instruite — jamais comme défaut.

## À l'échelle — workflow `visual-review`

Pour **≥ 4 captures**, déléguer au workflow (fan-out d'un agent par lot) au lieu de tout lire soi-même :

```
Workflow({ scriptPath: "$SKILL/workflows/visual-review.js", args: <contenu de .artifacts/visual-manifest.json> })
```

Chaque agent Read son lot d'images, applique la checklist, renvoie ses findings (JSON validé par schéma).
Les agents n'ont **pas** de navigateur ni de base : ce qu'ils renvoient est un lot de **candidats**.
La boucle principale (a) mesure chaque candidat selon le tableau ci-dessus, (b) écarte ceux que la
mesure démentit, (c) écrit `report/revue-visuelle.md` — le workflow ne peut pas écrire de fichier, il
retourne `{count, bug, warn, findings}`. En deçà de 4 captures, faire **inline** (ci-dessus).
