# 🎯 BRIEF MAC CLAUDE — HealthMap iOS Setup & Deploy

> **À LIRE EN PREMIER.** Tu es Claude Code sur un Mac (MacInCloud), nouvelle session.
> Ton job : finaliser le projet Xcode HealthMap iOS, builder, tester et préparer la soumission App Store.

---

## 1. Contexte projet (résumé)

**HealthMap** est une app de bilan nutritionnel par IA. URL prod web : https://www.healthmap.fr.
L'app iOS est un mirror natif SwiftUI de la web app. Backend partagé Supabase + auth Clerk PROD.

- **Owner** : Arthur Vernet (`audit-a@test.com` est le profil de test)
- **Bundle ID prévu** : `fr.healthmap.app`
- **Min iOS** : 17.0
- **Stack iOS** : SwiftUI, MVVM + DI via `ServiceContainer.swift`
- **Auth** : Clerk PROD (`pk_live_Y2xlcmsuaGVhbHRobWFwLmZyJA`, domaine `clerk.healthmap.fr`)
- **Backend** : Supabase project `ftwfxdfkghkemnpwtzlu` (eu-west-1)
- **IAP** : RevenueCat + StoreKit 2 (PAS Stripe sur iOS — refusé par Apple)

**Sources de vérité** :
- `CLAUDE.md` (à la racine de ce repo) — règles du projet iOS
- `README-SETUP.md` — setup détaillé
- Fichier web miroir : voir le repo `Healthmap` (pas sur cette machine — l'utilisateur a le miroir sur PC Windows)

---

## 2. État au 3 mai 2026 (avant ton arrivée)

Audit complet réalisé. Voici ce qui est **DÉJÀ fait** :
- ✅ Code Swift complet (~95 fichiers .swift), bien structuré
- ✅ Tests unitaires (14 fichiers `HealthMapTests/`)
- ✅ `Info.plist`, `PrivacyInfo.xcprivacy`, `Config.xcconfig.example` prêts
- ✅ Red flag `digestive_bleeding` ajouté (urgency immediate)
- ✅ Palette nutriments unifiée web/iOS (variée, type FoodVisor — pas tout bleu)
- ✅ `verify-receipt` Edge Function patchée (JWT Clerk validation, CORS strict)
- ✅ Wording "carence" → "apport insuffisant" (conformité ANSES + EU 1924/2006)
- ✅ Edge Functions Supabase critiques déployées : `delete-user`, `export-user-data`, `generate-analysis` (v33), `validate-hypotheses`, `create-checkout`, `stripe-webhook`
- ✅ Repo iOS sous Git (commit baseline + audit fix)

---

## 3. Ce qu'il TE reste à faire (par phase)

### 🔴 PHASE 1 — Créer le projet Xcode (ESSENTIEL, blocker absolu)

**Problème** : aucun `.xcodeproj` n'existe. Sans ça, rien ne builde.

**Solution recommandée** : utiliser **XcodeGen** (CLI) pour générer le projet depuis un fichier YAML versionnable. C'est plus propre que de cliquer dans Xcode.

**Tâches** :
1. Vérifier que XcodeGen est installé : `which xcodegen` (sinon `brew install xcodegen`)
2. Créer un fichier `project.yml` à la racine décrivant :
   - Target `HealthMap` (iOS 17+, Swift 5.9+, bundle `fr.healthmap.app`)
   - Target `HealthMapTests`
   - Inclure tous les dossiers `App/`, `Core/`, `Models/`, `Services/`, `ViewModels/`, `Views/`, `Utilities/`, `Resources/`
   - Capabilities : Sign in with Apple, Push Notifications, Background Modes (remote-notification), Associated Domains (`applinks:healthmap.fr`)
   - Settings de signing (à laisser en automatic au début, ou Manual avec teamID si user fournit)
   - SPM dependencies :
     - Clerk iOS SDK : `https://github.com/clerk/clerk-ios` (latest)
     - Supabase Swift : `https://github.com/supabase/supabase-swift` (latest)
     - RevenueCat : `https://github.com/RevenueCat/purchases-ios` (latest)
     - Sentry : `https://github.com/getsentry/sentry-cocoa` (latest, optional)
3. Générer : `xcodegen generate`
4. Vérifier : `xcodebuild -list -project HealthMap.xcodeproj`

### 🔴 PHASE 2 — App Icon

**Problème** : `Assets.xcassets/AppIcon.appiconset/` ne contient que `Contents.json`, pas d'image.

**Tâche** : générer un AppIcon 1024×1024 minimaliste si pas de design fourni.
- Si l'utilisateur n'a pas de design → propose-lui de créer un AppIcon temporaire (gradient bleu + initiale "H" ou logo simple) via ImageMagick (`brew install imagemagick`) ou demande-lui de fournir une image.
- Si fourni → place-la dans `HealthMap/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

### 🔴 PHASE 3 — Config secrets

**Tâche** : créer `HealthMap/Resources/Config.xcconfig` à partir de `Config.xcconfig.example`.

```bash
cp HealthMap/Resources/Config.xcconfig.example HealthMap/Resources/Config.xcconfig
```

Puis remplir avec les vraies valeurs (l'utilisateur doit te les fournir) :
- `CLERK_PUBLISHABLE_KEY=pk_live_Y2xlcmsuaGVhbHRobWFwLmZyJA`
- `SUPABASE_URL=https://ftwfxdfkghkemnpwtzlu.supabase.co`
- `SUPABASE_ANON_KEY=...` (à demander)
- `REVENUECAT_API_KEY=...` (à demander)
- `SENTRY_DSN=...` (optionnel)

⚠️ Le fichier `Config.xcconfig` est dans `.gitignore` — ne JAMAIS le commiter.

### 🟠 PHASE 4 — SSL Pinning

**Tâche** : remplacer les 4 placeholders dans `HealthMap/Services/SSLPinningService.swift:47-55` par les vrais hashes SPKI SHA-256 des certs Supabase et Clerk.

Commande documentée dans le fichier (lignes 36-40) :
```bash
echo | openssl s_client -servername ftwfxdfkghkemnpwtzlu.supabase.co \
  -connect ftwfxdfkghkemnpwtzlu.supabase.co:443 2>/dev/null | \
  openssl x509 -pubkey -noout | \
  openssl pkey -pubin -outform der | \
  openssl dgst -sha256 -binary | \
  base64
```

À faire pour : Supabase primary, Supabase backup, Clerk primary, Clerk backup.

### 🟠 PHASE 5 — Build & Test

```bash
# Build
xcodebuild build -project HealthMap.xcodeproj -scheme HealthMap -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.5' | xcpretty

# Tests
xcodebuild test -project HealthMap.xcodeproj -scheme HealthMap -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.5' | xcpretty

# Lance le simulateur pour tester l'app visuellement
open -a Simulator
xcrun simctl boot "iPhone 15 Pro"
```

Si erreurs de build → corrige les warnings/erreurs Swift (probablement des imports manquants après ajout des SPM).

### 🟠 PHASE 6 — Smoke test 3 profils

Une fois l'app qui se lance dans le simulateur, l'utilisateur teste avec :
- `audit-a@test.com / AuditA123!` → score attendu ~9/10
- `audit-b@test.com / AuditB123!` → score attendu ~3/10
- `audit-c@test.com / AuditC123!` → score attendu ~3/10

Tu peux automatiser ça avec **XCUITest** plus tard, mais pour la 1re itération l'utilisateur teste manuellement.

### 🟢 PHASE 7 — Fastlane setup (deploy auto)

Une fois que ça build et que ça marche en simulateur :

```bash
brew install fastlane
cd /chemin/vers/Healthmap-iOS
fastlane init
```

Configurer un `Fastfile` avec :
- Lane `beta` : build + archive + upload TestFlight
- Lane `screenshots` : génère les screenshots App Store auto
- Lane `match` : gestion certificats (nécessite repo git privé séparé)

⚠️ Avant fastlane → l'utilisateur doit avoir :
- Compte Apple Developer ($99/an) actif
- Apple ID + 2FA fonctionnel
- App créée sur App Store Connect (peut être fait par fastlane `produce`)

### 🟢 PHASE 8 — Soumission App Store

Une fois Fastlane qui fonctionne :
```bash
fastlane beta  # → upload TestFlight, attendre validation Apple ~30 min
```

Tester via TestFlight sur device réel. Si OK :
```bash
fastlane release  # → submit for App Store review
```

---

## 4. Comptes test (mêmes que web)

| Email | Password | Profil | Score attendu |
|-------|----------|--------|---------------|
| audit-a@test.com | AuditA123! | Thomas, 28 ans, sportif omnivore | ~9/10 |
| audit-b@test.com | AuditB123! | Léa, 35 ans, végétarienne règles abondantes | ~3/10 |
| audit-c@test.com | AuditC123! | René, 67 ans, fumeur PPI+metformin | ~3/10 |

---

## 5. Règles ABSOLUES (depuis CLAUDE.md)

1. **Calculs = mirror exact de `health.js` web**. Pas de logique calcul propre à iOS.
2. **`NutrientData.swift` = canon** des labels/emojis nutriments.
3. **Aucune clé API hardcodée** — tout via `Config.xcconfig` (gitignored).
4. **Clerk = unique source d'auth**. Pas de `SupabaseAuth.signIn/signUp`.
5. **Touch targets ≥ 44×44 pt**. Reduce-motion respecté partout.
6. **Tests avec audit-a/b/c obligatoires** après tout changement fonctionnel.
7. **Git commit après chaque phase qui marche** (pour rollback facile).

---

## 6. Comment travailler avec moi (l'utilisateur)

- L'utilisateur (Arthur) parle français.
- Style de rapport préféré : TL;DR 1 ligne, statut visuel ✅❌⏳, action claire à la fin.
- Toujours demander avant de modifier un truc non explicitement demandé.
- Si tu galères, dis-le. Si une décision produit doit être prise, demande.

---

## 7. Premier message à m'envoyer (Arthur)

Quand tu démarres ta session sur le Mac, Arthur te dira probablement juste :
> "Lance la Phase 1"

Tu sais quoi faire. Bon courage. 🚀
