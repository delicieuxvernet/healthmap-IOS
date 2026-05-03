# CLAUDE.md — HealthMap iOS (SwiftUI)

> **Ce fichier est la mémoire long terme du projet iOS.**
> À lire intégralement au début de CHAQUE session avant d'écrire la moindre ligne de code.
> Dernière mise à jour : 20 avril 2026 (migration Clerk)

---

## 🚨 LIRE EN PREMIER : sources de vérité

L'architecture canonique de HealthMap (web + iOS) vit dans le **vault Obsidian** :

📂 **`C:\Users\stana\Desktop\Claude\Obsidian\Healthmap\`**

- Point d'entrée : **`00 — README.md`** (MOC qui indexe tout)
- Lecture **à la demande** selon la tâche (jamais tout charger d'un coup)
- Heuristique pour iOS :
  - Question architecture iOS → `02 — Architecture/Frontend iOS (SwiftUI).md`
  - Question backend partagé / Edge Functions → `02 — Architecture/Edge Functions.md` + `Backend Supabase.md`
  - Question DB / schéma → `03 — Base de données/Schéma relationnel.md`
  - Question scoring / red flags → `05 — IA & Algorithmes/Calcul des scores (health.js).md` + `Red flags détection.md` (mirror exact à respecter)
  - Question décision archi → `07 — Décisions (ADR)/`

**Pour les règles de code partagées** (déterminisme scores, RGPD, conventions), voir aussi :
- `C:\Users\stana\Desktop\Claude\Healthmap\code\CLAUDE.md` (CLAUDE.md du repo web)

**Setup local Xcode** : voir `README-SETUP.md` à côté de ce fichier.

---

## 1. Projet en bref

**HealthMap iOS** — app native SwiftUI (iOS 17+), miroir mobile de https://www.healthmap.fr.

- **Auth** : **Clerk** (`pk_live_Y2xlcmsuaGVhbHRobWFwLmZyJA`, domaine `clerk.healthmap.fr`) —
  mêmes utilisateurs que le web depuis le 20 avril 2026. **Plus de Supabase Auth.**
- Backend DB + Edge Functions : **partagé avec le web** (Supabase `eu-west-1`,
  project `ftwfxdfkghkemnpwtzlu`). JWT Clerk (template `supabase`) injecté dans le
  `SupabaseClient` via closure `accessToken` — RLS conservée telle quelle.
- Subscriptions : **RevenueCat** (StoreKit 2 — pas Stripe sur iOS)
- Architecture : **MVVM + DI** via `ServiceContainer`
- Bundle : `fr.healthmap.app`

### Règle d'or unique

> **Les calculs (BMI, BMR, TDEE, scores nutriments, red flags) doivent rester un MIRROR EXACT de `health.js` côté web.**
>
> Toute évolution d'une formule côté web doit être répercutée immédiatement dans `Core/HealthCalculator.swift`, `Core/RedFlagDetector.swift`, `Core/NutrientData.swift`. Sinon, divergence iOS/web → bugs invisibles.

---

## 2. ⚠️ Règles absolues immuables

### 2.1 — Code & calculs
1. **`HealthCalculator.swift` = miroir de `health.js`**. Pas de logique calcul propre à iOS.
2. **`NutrientData.swift` = source canonique** des labels/emojis nutriments (jamais l'IA).
3. **`AIAnalysisService` doit utiliser `temperature=0`** côté Edge Function (déjà géré server-side, mais ne pas paramétrer autrement).
4. **Circuit breaker actif** sur `AIAnalysisService` (3 fails → open 5 min). Ne pas le désactiver.

### 2.2 — Sécurité
5. **Aucune clé API hardcodée**. Tout via `Config.xcconfig` (gitignored) lu par `AppConfig.swift`.
   Les clés critiques : `CLERK_PUBLISHABLE_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
   `REVENUECAT_API_KEY`, `SENTRY_DSN`.
6. **SSL pinning placeholders** dans `SSLPinningService.swift` → **À remplacer par les vrais hashes SPKI SHA-256 avant prod**.
7. **PII strippée** par Sentry `beforeSend` callback. Ne jamais logger email/UUID en clair.
8. **Clerk = single source of truth pour l'auth**. Ne JAMAIS re-introduire `SupabaseAuth.signIn/signUp`
   — le `SupabaseClient` est configuré avec `autoRefreshToken: false` et `InMemoryLocalStorage`
   exprès pour que son système d'auth soit désactivé. Tout passe par `AuthService` (Clerk-backed).

### 2.3 — UX / branding
8. **Palette : voir `Color+Theme.swift` comme source canonique.** Pas de règle d'absolu inventée — consommer ce qui existe dans le fichier de tokens, demander au user avant de proposer une nouvelle teinte.
9. **Touch targets ≥ 44×44 pt** (HIG Apple).
10. **`whileTap` scale 0.97** via `.healthMapPressed` button style. Standardisé partout.
11. **Dynamic Type clamped** `.large ... .accessibility3` (ne pas exploser le layout).
12. **Reduce-motion respecté** sur toute animation (`@Environment(\.accessibilityReduceMotion)`).

### 2.4 — RGPD & App Store
13. **Edge Functions `delete-user` (Art. 17) + `export-user-data` (Art. 20)** déjà déployées côté Supabase. Boutons UI à câbler dans `ProfileView.swift`.
14. **Sign in with Apple** : capability à activer dans Xcode + entitlements (App Store guideline 4.8).
15. **NSCameraUsageDescription + NSPhotoLibraryUsageDescription** déjà dans Info.plist (meal scan).

### 2.5 — Lifecycle
16. **Session refresh 10 min** (matche le web) via `AuthViewModel`.
17. **Offline queue** (`OfflineQueueService`) doit drainer au reconnect. Ne pas court-circuiter.
18. **Draft questionnaire** persisté `UserDefaults['healthmap_questionnaire_draft']` schema v2 (userId-scoped). Cleared au sign out via `clearLocalCaches()`.

---

## 3. Architecture (résumé)

```
HealthMap/
├── App/                  → @main (Clerk.configure + SupabaseService), ContentView, AppDelegate (APNs)
├── Core/                 → AppConfig, ServiceContainer, HealthCalculator, NutrientData,
│                          RedFlagDetector, AuthTypes (HMSession/HMUser/HMAuthChangeEvent shims)
├── Models/               → UserProfile, AIAnalysis (v7), Nutrient, RedFlag, Supplements
├── Services/ (29)        → Clerk-backed AuthService, ClerkProfileResolver, Supabase (DB only),
│                          Database, AIAnalysis, Subscription (RevenueCat),
│                          Network, Offline, SSL pinning, Toast, Haptic, Analytics, Push
├── ViewModels/           → @MainActor, AuthVM, DashboardVM, QuestionnaireVM, etc.
├── Views/ (35)           → Auth, Onboarding, Questionnaire, Dashboard, Checkin, MealScan,
│                          Recommendations, Supplements, Profile, Paywall, Shared
├── Utilities/            → Color+Theme, ThemeConstants, Accessibility, AppleSignInNonce, AppLogger
└── Resources/            → Info.plist, Config.xcconfig.example, Assets.xcassets
```

### 3.1 — Architecture auth (depuis 20 avril 2026)

```
SwiftUI (AuthView, ProfileView...)
    ↓
AuthViewModel (@MainActor, publishes HMUser?/HMSession?)
    ↓
AuthService (Clerk-backed, singleton)
    ├─ Clerk.shared.auth.*                    ← signup/signin/oauth
    ├─ Clerk.shared.session?.getToken(...)    ← JWT template "supabase"
    └─ ClerkProfileResolver
           ├─ SELECT profiles WHERE clerk_id=? (lookup UUID)
           └─ INSERT profiles(clerk_id, email, first_name) si fresh signup

SupabaseClient (DB + Edge Functions uniquement)
    └─ accessToken closure → Clerk JWT ("supabase" template)
           └─ RLS `auth.uid() = profiles.id` continue de matcher
```

**Règle invariante** : `HMUser.id` est un `UUID` = `profiles.id`, PAS `clerk.user.id`
(qui serait `"user_xxx..."`). Les call-sites qui font `.eq("id", value: userId)` continuent
de fonctionner tel quel — c'est pour ça qu'on a `ClerkProfileResolver`.

→ Détail complet dans `Obsidian/Healthmap/02 — Architecture/Frontend iOS (SwiftUI).md`.

---

## 4. Mismatchs connus à résoudre

(Identifiés lors de l'audit du 18 avril 2026, documentés dans le vault)

1. **`verify-receipt` Edge Function attendue par iOS mais inexistante côté Supabase**.
   - Code iOS : `ReceiptValidationService.swift` invoque `client.functions.invoke("verify-receipt", ...)`.
   - Action : soit déployer cette Edge Function, soit retirer l'appel.

2. **`analytics_events` schéma divergent**.
   - iOS écrit : `event`, `properties`, `app_version`, `environment`, `created_at`.
   - DB Supabase actuelle : `event_name`, `properties`, `occurred_at`.
   - Action : aligner — soit ajouter colonnes manquantes, soit adapter `AnalyticsService.swift`.

3. **Colonnes `questionnaire_data_encrypted` / `ai_analysis_encrypted`** attendues par `SecureStorageService.decryptFromTransit()` mais inexistantes dans le schéma actuel.
   - Pas bloquant (fallback plaintext en place).
   - Action : soit ajouter ces colonnes (avec pgcrypto), soit retirer le code de décryption.

---

## 5. Règle de mise à jour de la doc

À la fin d'une session de modifs structurelles iOS, **mettre à jour le vault Obsidian** :
- Nouveau service / view majeure → MAJ `02 — Architecture/Frontend iOS (SwiftUI).md`
- Nouvelle décision archi iOS → nouvelle ADR dans `07 — Décisions (ADR)/`
- Changement qui invalide une affirmation existante → patcher la note + bumper `updated:` dans le frontmatter

PAS de MAJ pour bug fix trivial / refactor cosmétique.

À la fin de la session, indiquer dans le résumé : *"J'ai mis à jour N notes du vault : X, Y."*

---

## 6. Comptes test (mêmes que le web)

| Email | Password | Persona |
|---|---|---|
| `audit-a@test.com` | `AuditA123!` | Thomas, 28 ans, sportif omnivore |
| `audit-b@test.com` | `AuditB123!` | Léa, 35 ans, végétarienne, règles abondantes |
| `audit-c@test.com` | `AuditC123!` | René, 67 ans, fumeur PPI+metformin |

Tester avec ces 3 profils après tout changement fonctionnel.

---

## 7. Documents annexes

- **`README-SETUP.md`** (à côté de ce fichier) — Setup Xcode + RevenueCat + Sign in with Apple
- **Vault Obsidian** `C:\Users\stana\Desktop\Claude\Obsidian\Healthmap\` — Architecture canonique
- **`Healthmap/code/CLAUDE.md`** — Règles partagées (web)
