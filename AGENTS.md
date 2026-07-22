# AGENTS.md — Kiwio iOS

> Briefing pour tout agent IA (Codex, Claude Code, autre) qui travaille sur ce repo.
> **À lire en entier avant la première modification.** Les règles produit et
> techniques détaillées vivent dans `CLAUDE.md` (même dossier) — ce fichier ne les
> duplique pas, il dit comment **opérer** le projet.

---

## 1. Le projet en 30 secondes

- **Kiwio** = application **iOS native SwiftUI** (iOS 17+), nutrition par IA. Créée par Arthur Vernet.
- **Ce repo est le seul produit.** Le repo web (`Healthmap/code`) est un brouillon abandonné : on n'y touche plus que `supabase/` (backend partagé).
- Bundle : `fr.healthmap.app` · Team Apple : `D87R3L7B75` · Nom App Store : **Kiwio**
- Backend : Supabase (`ftwfxdfkghkemnpwtzlu`, eu-west-1) — DB + Edge Functions, partagé avec le web.
- Auth iOS : **Supabase Auth natif uniquement**. Ne JAMAIS réintroduire Clerk côté iOS (le web reste sur Clerk).
- Abonnements : **RevenueCat + StoreKit 2** (jamais Stripe sur iOS).
- Architecture : MVVM + injection de dépendances via `ServiceContainer`.

**Sources de vérité, dans l'ordre :**
1. `CLAUDE.md` (racine) — règles produit, conventions, comptes de test, historique. **Prioritaire.**
2. `DESIGN-PAGES.md` (racine) — structure de chaque écran. À lire avant tout ajustement UI.
3. Vault Obsidian `C:\Users\stana\Desktop\Claude\Obsidian\Healthmap\` — architecture canonique (le POURQUOI). Lecture à la demande, jamais en bloc.

---

## 2. ⚠️ Contrainte majeure : on développe depuis Windows

**Il n'y a pas de Xcode sur la machine d'Arthur (Windows 11).** Personne ne compile en local.
→ **Toute vérification passe par la CI GitHub Actions (runners macOS).**

Conséquences pratiques :
- On ne peut pas « lancer l'app pour voir ». On lit le code, on raisonne, on pousse, on lit la CI.
- Un changement SwiftUI non trivial doit être relu deux fois : la CI est le seul filet.
- Le projet Xcode est **généré par XcodeGen** depuis `project.yml`. **Ne jamais éditer `HealthMap.xcodeproj` à la main** — modifier `project.yml`. Un nouveau fichier `.swift` posé dans `HealthMap/` est pris automatiquement (sources par dossier).

---

## 3. Repo, branches, CI

- Remote : `https://github.com/delicieuxvernet/healthmap-IOS` · branche par défaut : `main`
- Chemin local : `C:\Users\stana\Desktop\Claude\Healthmap-iOS`

### Workflow standard (à respecter)
```bash
git checkout main && git pull --ff-only
git checkout -b fix/sujet-court        # jamais de commit direct sur main
# ... modifications ...
git add <fichiers précis>              # JAMAIS git add -A / git add .
git commit -m "type(scope): message en français"
git push -u origin fix/sujet-court
gh pr create --title "..." --body "..."
# attendre la CI verte, puis :
gh pr merge <n> --squash --delete-branch
```

### Les 2 workflows GitHub Actions

**`Build & Deploy to TestFlight`** (`.github/workflows/build-testflight.yml`)
- Déclencheurs : push sur `main`, pull_request vers `main`, et `workflow_dispatch` (manuel).
- Job `tests` : compile + suite de tests sur simulateur, **sur tous les déclencheurs**. Bloquant.
- Job `build-and-upload` : **uniquement sur push `main`** → archive signée (fastlane match) → upload TestFlight. ~15-19 min.
- Le numéro de build s'incrémente côté fastlane. Un `workflow_dispatch` sur `main` produit un **nouveau numéro de build avec un code identique** (utile pour resoumettre, inutile fonctionnellement).
- `[skip ci]` dans le message de commit évite un build TestFlight inutile (à utiliser pour les commits qui ne touchent que `scripts/`, `.github/`, ou la doc).

**`ASC Subscriptions`** (`.github/workflows/asc-subscriptions.yml` → `scripts/asc_subscriptions.rb`)
Pilote App Store Connect via son API (l'UI web n'est pas automatisable). Lancement :
```bash
gh workflow run "ASC Subscriptions" --ref main -f mode=<MODE>
```
| Mode | Effet | Écrit ? |
|---|---|---|
| `audit` | État complet des abonnements (prix, territoires, essais, captures) | non |
| `app-audit` | État de la version App Store, builds, soumissions de review | non |
| `deep-audit` | Diagnostic de conformité des abos → liste de « points à corriger » | non |
| `fix-subs` | Corrige les notes de review + libellés des abos | **oui** |
| `apply` | Prix / localisations / disponibilité / essais | **oui** |
| `apply-app` | Infos App Review (contact, compte démo, notes) + rattache le dernier build VALID | **oui** |
| `screenshots` | Upload des captures de la fiche App Store | **oui** |
| `submit` | Soumet la version (+ tente les abos) à App Review | **oui** |
| `offers` / `fix-meta` | Codes promo / correction de métadonnées | **oui** |

`submit` accepte `-f stage_only=true` : **prépare** la soumission sans l'envoyer à Apple.

Lire le résultat d'un run :
```bash
gh run watch <run-id> --exit-status
gh run view <run-id> --log | grep -E "asc\s+Run \(" | sed 's/^asc\tRun ([a-z-]*)\t[0-9T:.Z-]* //'
```

---

## 4. 🔐 Secrets — règle absolue

**Ne jamais afficher, copier, commiter ou transmettre la valeur d'un secret.** On s'y réfère par son nom.

- **Secrets GitHub Actions** (déjà configurés, invisibles depuis le code) : `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY_BASE64`, `MATCH_GIT_URL`, `MATCH_PASSWORD`, `FASTLANE_TEAM_ID`, `CONFIG_XCCONFIG_BASE64`, `DEMO_ACCOUNT_PASSWORD`, `REVIEW_CONTACT_PHONE`.
- **`HealthMap/Resources/Config.xcconfig`** : clés client (Supabase URL + anon key, RevenueCat `appl_…`, Sentry, PostHog). **Gitignoré — ne jamais le commiter.** En CI il est injecté depuis `CONFIG_XCCONFIG_BASE64`. Le modèle public est `Config.xcconfig.example`.
  - Piège de syntaxe xcconfig : `//` démarre un commentaire, donc les URL s'écrivent `https:/$()/exemple.com`. En lisant ce fichier, reconstruire l'URL avant de s'en servir.
- Ne jamais écrire de clé en dur dans le Swift : tout passe par `AppConfig.swift`.

---

## 5. Règles de code non négociables

Détail complet dans `CLAUDE.md` §2. Les pièges qui ont déjà causé des régressions :

1. **Vocabulaire interdit** — `HealthMapTests/VoiceComplianceTests.swift` fait échouer la CI si un fichier Swift contient `carence`, `diagnostic`, `patient` ou `maladie` — **commentaires compris**. Conformité ANSES/EU 1924/2006. Dire « apport insuffisant ». `grep -ri "carence\|diagnostic\|patient\|maladie" HealthMap/` avant de pousser.
2. **Calculs = miroir exact du web** (`Core/HealthCalculator.swift`, `RedFlagDetector.swift`, `NutrientData.swift` ↔ `health.js`). Exception assumée : `NutrientEngine` quand `profile.groceries` n'est pas vide (iOS-only, documenté).
3. **Écritures `profiles` = UPDATE uniquement.** La ligne est créée par le trigger DB `handle_new_user` ; un upsert client est rejeté en 403 par la RLS.
4. **Tout écran scrollable doit poser `.containerRelativeFrame(.horizontal)`** sur le contenu du `ScrollView`, sinon dérive horizontale (« l'écran glisse sur le côté »). Ce bug est déjà revenu 3 fois (Suivi #134, Scan #120, Bilan #158).
5. **Tout onglet doit poser `.kiwiTabBarBottomInset()`** sur son contenu racine **à l'intérieur** de son `NavigationStack` — posé ailleurs, l'inset ne se propage pas et le contenu passe sous la barre flottante.
6. **Tokens de design obligatoires** : `Theme.*` (`ThemeConstants.swift`) et `Color.kiwi*` (`Color+Theme.swift`). Pas de valeur ad hoc. `whileTap` = scale 0.97 via `.healthMapPressed`.
7. **Accessibilité** : cibles tactiles ≥ 44×44 pt, Dynamic Type clampé, `accessibilityLabel` sur toute icône porteuse de sens, animations infinies gardées par `accessibilityReduceMotion`.
8. **Périmètre strict** : ne modifier que ce qui est demandé. Pas de refactor opportuniste. Jamais `git add -A`.

---

## 6. ⚠️ Deux agents sur le même repo — règles de coexistence

Codex **et** Claude Code interviennent sur ce projet, parfois le même jour. Le working tree local est partagé et peut changer de branche entre deux sessions.

- **Toujours `git fetch` + `git pull --ff-only` sur `main` avant de commencer.** Ne jamais supposer que l'état local est à jour.
- **Vérifier qu'il n'y a pas de travail d'un autre agent en cours** : `git status` et `git log origin/main --oneline -10`. Si des fichiers modifiés non commités ne relèvent pas de ta tâche, **ne pas les commiter, ne pas les jeter** — les laisser tels quels (ou `git stash push` ciblé, jamais global) et le signaler dans le compte-rendu.
- **Une branche par tâche, nommée explicitement**, pour éviter les collisions.
- **Ne jamais forcer** (`push --force`) sur `main`, ni réécrire un commit qu'on n'a pas écrit.
- Terminer chaque session par un compte-rendu : ce qui a changé, la ou les PR, l'état de la CI, ce qui reste à faire.

---

## 7. Vérification avant de pousser

Aucun build local possible (§2). Le minimum :
1. Relire le diff en entier (`git diff`).
2. `grep` du vocabulaire interdit (§5.1).
3. Vérifier que tout nouveau fichier Swift est bien sous `HealthMap/` (sinon XcodeGen ne le voit pas).
4. Pousser sur une branche → **attendre le job `tests` vert** (~10-15 min) avant de merger.
5. Après merge sur `main` : vérifier que le job `build-and-upload` finit vert et que le build monte sur TestFlight.

**Ne jamais annoncer qu'une chose fonctionne sans preuve.** Si la CI est rouge ou une étape a été sautée, le dire avec les faits.

---

## 8. Comptes de test

| Email | Mot de passe | Profil | Auth |
|---|---|---|---|
| `audit-b@test.com` | `AuditB123!` | Léa, 35 ans, végétarienne | ✅ **Supabase Auth OK — le seul utilisable sur iOS** |
| `audit-a@test.com` | `AuditA123!` | Thomas, 28 ans, sportif | ❌ pas de ligne `auth.users` → login impossible sur iOS |
| `audit-c@test.com` | `AuditC123!` | René, 67 ans, polymédiqué | ❌ idem |

**`audit-b` est le compte démo fourni à Apple.** Vérifier son login avant toute soumission :
```bash
curl -s -X POST "https://ftwfxdfkghkemnpwtzlu.supabase.co/auth/v1/token?grant_type=password" \
  -H "apikey: <SUPABASE_ANON_KEY>" -H "Content-Type: application/json" \
  -d '{"email":"audit-b@test.com","password":"AuditB123!"}'
```

---

## 9. État App Store au 22 juillet 2026 — à jour avant d'agir

- Version **1.0**, actuellement **REJECTED** — 2 refus consécutifs en **Guideline 2.1(b)** (« we cannot locate the In-App Purchases »).
- **Refus n°1 (20 juil.)** : le compte démo fourni (`audit-a`) ne pouvait pas se connecter, et les notes de review pointaient un onglet « Profil » qui n'existe plus. Corrigé (compte `audit-b`, notes réécrites, carte « Kiwio Premium » ajoutée sur l'écran Bilan).
- **Refus n°2 (21 juil.)** : la soumission envoyée ne contenait **que la version, sans les 3 abonnements**. Un garde-fou dans `asc_subscriptions.rb` empêche désormais ce cas.
- **Config des abonnements auditée et corrigée le 22 juil.** (`deep-audit` → `fix-subs`) : notes de review par abonnement (elles étaient vides) et libellés nettoyés. `deep-audit` renvoie maintenant 0 défaut.

### 🚧 Limite connue de l'API App Store Connect
Un abonnement **rejeté** ne peut pas être re-soumis par API. Trois voies testées, toutes en échec :
- `POST /v1/subscriptionSubmissions` → 409 `no pending version for submission`
- `POST /v1/reviewSubmissionItems` avec relation `subscription` → 409 `not a relationship on the resource`
- modification réelle de l'entité (note de review) pour régénérer une version pending → 409 persiste

→ **Seul le bouton « Resubmit » de l'UI App Store Connect (Monétisation → Abonnements) fonctionne.** C'est une action humaine, à ne pas re-tenter par script.

### Reste à faire (actions humaines, hors API)
1. **Resubmit** des 3 abonnements dans l'UI ASC.
2. **Accord Paid Applications** (ASC → Entreprise) à activer par l'Account Holder — non vérifiable par API (`/v1/agreements` → 404). Sans lui, StoreKit ne renvoie aucun produit et le paywall reste vide.
3. **RevenueCat** : l'offering `default` ne contient que `healthmap_monthly` et `healthmap_annual` — **`healthmap_weekly` manque**. Vérifiable :
   ```bash
   curl -s -H "Authorization: Bearer <REVENUECAT_API_KEY>" -H "X-Platform: ios" \
     https://api.revenuecat.com/v1/subscribers/diag/offerings
   ```
4. **Screen recording** d'un achat sandbox sur appareil physique, exigé par Apple à la resoumission.

Quand 1 et 2 sont faits : `gh workflow run "ASC Subscriptions" --ref main -f mode=apply-app` puis `-f mode=submit`.

---

## 10. Méthode de travail attendue par Arthur

1. **Maquette avant code** pour tout changement visuel : montrer le rendu (HTML/SVG dans le chat, ou description précise) et attendre validation. Ne jamais coder un design non validé.
2. **Décision produit** = 2 à 4 options + une recommandation. Un détail mineur tranchable : trancher et le signaler, ne pas faire arbitrer l'évident.
3. **Autonomie sur l'exécution** : branche → commit ciblé → CI → merge → déploiement, jusqu'au vert. Feu vert permanent pour merger et déployer. **Confirmer avant toute action destructive ou irréversible** (suppression de données, soumission App Store, envoi externe).
4. **Compte-rendu final** : TL;DR en une ligne, statut ✅/⏳/❌, numéro de build ou URL, où sont les fichiers.
5. **Honnêteté** : un test qui échoue, une étape sautée → le dire avec les faits.
