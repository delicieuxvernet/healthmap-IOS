# Kiwio iOS — Guide de configuration

> ## ⛔ CE DOCUMENT EST PARTIELLEMENT PÉRIMÉ (constaté le 1er août 2026)
>
> Il décrit **Clerk** comme fournisseur d'authentification iOS. **C'est faux depuis le
> 7 juin 2026** : iOS est passé à **Supabase Auth natif** et Clerk en a été entièrement
> retiré (le web, lui, reste sur Clerk). La `CLERK_PUBLISHABLE_KEY` encore présente dans
> `Config.xcconfig` est un résidu inutilisé.
>
> Sont également dépassés : l'étape 1 (le projet Xcode existe, généré par **XcodeGen**
> depuis `project.yml`), le paquet SPM Clerk, et le bloc « Statut App Store » ci-dessous —
> `delete-user` est déployée et la capability Sign in with Apple est active.
>
> **Restent valables** : la configuration `Config.xcconfig`, RevenueCat, Sentry, PostHog,
> la table `analytics_events`, les secrets CI et la partie tests.
>
> **En cas de contradiction, l'ordre de confiance est :**
> `AGENTS.md` → `CLAUDE.md` → vault Obsidian `09 — Passation` → ce fichier.

> 🥝 **Kiwio = HealthMap** (marque renommée, juin 2026). Les noms **internes** restent inchangés pour stabilité : target/module Swift `HealthMap`, bundle id `fr.healthmap.app`, domaine `healthmap.fr`, repo `healthmap-IOS`.

App native SwiftUI (iOS 17+) pour Kiwio. Backend partagé avec healthmap.fr (Supabase).
Cette version inclut : gestion d'erreurs typée, logging unifié, crash reporting, retry réseau,
push notifications, et tests unitaires avec mocks.

> **Statut App Store** : suppression de compte (guideline 5.1.1 v) et Sign in with Apple
> (guideline 4.8) sont désormais câblés dans l'UI. Reste à activer la capability
> « Sign in with Apple » dans Xcode et à déployer l'Edge Function `delete-user` sur
> Supabase. Voir la section **Conformité App Store** ci-dessous.

## Pré-requis

- **Xcode 16+** (Mac) ou GitHub Actions macos-15
- **Compte Apple Developer** (99 $/an) — https://developer.apple.com
- **Compte RevenueCat** (gratuit) — https://www.revenuecat.com
- **Compte Sentry** (gratuit jusqu'à 5k events/mois) — https://sentry.io (optionnel mais recommandé)
- **Compte PostHog EU** (gratuit jusqu'à 1M events) — https://eu.posthog.com (optionnel)
- **iPhone physique** pour tester via TestFlight

---

## Étape 1 : Créer le projet Xcode

1. Ouvrir Xcode, File > New > Project > iOS > App
2. Product Name : `HealthMap`
3. Organization Identifier : `fr.healthmap`
4. Bundle Identifier : `fr.healthmap.app`
5. Language : Swift, Interface : SwiftUI
6. Minimum Deployment : **iOS 17.0**
7. Supprimer les fichiers générés par défaut
8. Glisser-déposer le dossier `HealthMap/` dans le projet Xcode (cocher « Copy items if needed »)
9. Glisser-déposer le dossier `HealthMapTests/` dans le target Tests

---

## Étape 2 : Dépendances Swift Package Manager

File > Add Package Dependencies, puis ajouter :

| Package | URL | Version |
|---------|-----|---------|
| **Clerk iOS** | `https://github.com/clerk/clerk-ios` | Up to Next Major from 1.0.0 |
| Supabase | `https://github.com/supabase/supabase-swift` | Up to Next Major from 2.0.0 |
| RevenueCat | `https://github.com/RevenueCat/purchases-ios` | Up to Next Major from 5.0.0 |
| Sentry *(recommandé)* | `https://github.com/getsentry/sentry-cocoa` | Up to Next Major from 8.0.0 |

Pour Clerk : sélectionner le produit `ClerkKit`. C'est **le provider d'auth principal**
depuis le 20 avril 2026 (remplacement de Supabase Auth).
Pour Supabase : sélectionner le produit `Supabase`. Il reste utilisé pour la DB et les
Edge Functions — le JWT vient de Clerk (cf. `SupabaseService.configure()` qui branche
un `accessToken` closure lisant `Clerk.shared.session?.getToken(.init(template: "supabase"))`).
Pour RevenueCat : sélectionner `RevenueCat` **et** `RevenueCatUI`.
Pour Sentry : sélectionner `Sentry`. Le code est guardé par `#if canImport(Sentry)` donc il
compile même sans la dépendance — elle active simplement le reporting.

---

## Étape 3 : Configuration des secrets via xcconfig

**Les clés ne sont jamais codées en dur dans le code.** On utilise un fichier `Config.xcconfig`
git-ignoré, lu par `Info.plist`, lui-même lu par `AppConfig.swift` au démarrage.

1. Copier le template :
   ```bash
   cp HealthMap/Resources/Config.xcconfig.example HealthMap/Resources/Config.xcconfig
   ```

2. Remplir `Config.xcconfig` avec tes vraies clés :
   ```
   APP_ENVIRONMENT = production
   CLERK_PUBLISHABLE_KEY = pk_live_Y2xlcmsuaGVhbHRobWFwLmZyJA
   SUPABASE_URL = https:$()//ftwfxdfkghkemnpwtzlu.supabase.co
   SUPABASE_ANON_KEY = eyJhbGc...ta_vraie_cle_anon
   REVENUECAT_API_KEY = appl_xxxxxxxxxxxx
   SENTRY_DSN = https:$()//xxx@sentry.io/yyy
   POSTHOG_API_KEY = phc_xxxxxxxx
   POSTHOG_HOST = https:$()//eu.i.posthog.com
   ```
   ⚠️ Le `$()` autour de `//` est obligatoire : xcconfig interprète `//` comme un commentaire.

   `CLERK_PUBLISHABLE_KEY` pointe sur l'instance PROD partagée avec le web
   (domaine custom `clerk.healthmap.fr`). C'est le même `pk_live_...` que le web —
   une seule source d'utilisateurs, peu importe la plateforme.

3. Attacher le fichier aux build settings :
   - Target HealthMap > Info > Configurations
   - Debug et Release : sélectionner `Config` pour les deux

4. Vérifier que `Config.xcconfig` est bien dans `.gitignore` (il l'est déjà).

5. **Ne jamais commit ce fichier.** Le template `.example` est la seule version versionnée.

---

## Étape 4 : Capabilities et provisioning

Dans Xcode > Target HealthMap > Signing & Capabilities, activer :

- **Push Notifications** (pour APNs / notifications de rappel du questionnaire)
- **Background Modes** → « Remote notifications »
- **Sign in with Apple** (si utilisé en complément de Google OAuth)
- **Associated Domains** → `applinks:healthmap.fr` (pour les deep links universels)

---

## Étape 5 : RevenueCat

1. Créer une app iOS dans https://app.revenuecat.com
2. App Store Connect > Apps > HealthMap > In-App Purchases : créer les produits
   - `healthmap_monthly` (abonnement mensuel)
   - `healthmap_annual` (abonnement annuel)
3. Dans RevenueCat :
   - Créer un entitlement `premium`
   - Lier les deux produits à cet entitlement
   - Créer une offering `default` qui contient les deux packages
4. Récupérer la clé API Apple Public → `REVENUECAT_API_KEY` dans `Config.xcconfig`

---

## Étape 6 : Sentry (crash reporting)

1. Créer un projet sur https://sentry.io (type Apple > iOS)
2. Copier le DSN → `SENTRY_DSN` dans `Config.xcconfig`
3. `CrashReportingService.swift` configure automatiquement Sentry :
   - PII stripping dans `beforeSend`
   - Breadcrumbs filtrées (pas de `questionnaire_data`, `ai_analysis`, etc.)
   - Tag `environment` = valeur de `APP_ENVIRONMENT`

Si `SENTRY_DSN` est vide, le service devient un no-op silencieux (utile en dev).

---

## Étape 7 : PostHog (analytics optionnel)

1. Créer un projet sur https://eu.posthog.com (hébergement EU pour RGPD)
2. Copier la clé projet → `POSTHOG_API_KEY` dans `Config.xcconfig`
3. **Aucun SDK à ajouter** : `AnalyticsService` POST directement sur
   `https://eu.i.posthog.com/capture/` via `URLSession`. Ça garde le binaire
   petit et évite la friction côté App Store review (un SDK analytics tiers
   déclenche souvent des questions du reviewer).

Si `POSTHOG_API_KEY` est vide, `postHogCapture` et `postHogIdentify` retournent
immédiatement — zéro trafic réseau. Les événements sont toujours loggés
localement (`os.Logger`) et dans la table Supabase `analytics_events`
(sans PII grâce au sanitizer, cf. `AnalyticsPIIStrippingTests`).

---

## Étape 8 : Table `analytics_events` Supabase

```sql
CREATE TABLE public.analytics_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  event text NOT NULL,
  properties jsonb DEFAULT '{}'::jsonb,
  app_version text,
  environment text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.analytics_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users insert own events" ON public.analytics_events
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
```

## Étape 9 : Edge Function `delete-user` (RGPD + Apple)

L'App Store rejette toute app avec compte utilisateur sans suppression in-app
(guideline 5.1.1 v). `AuthService.deleteAccount()` appelle une Edge Function Supabase
avec service_role :

```ts
// supabase/functions/delete-user/index.ts
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const { user_id } = await req.json();
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );
  const { error } = await admin.auth.admin.deleteUser(user_id);
  if (error) return new Response(error.message, { status: 500 });
  return new Response("ok");
});
```

Déployer : `supabase functions deploy delete-user`

---

## Étape 10 : CI/CD GitHub Actions

Secrets à configurer dans Settings > Secrets > Actions :

| Secret | Obtention |
|--------|-----------|
| `BUILD_CERTIFICATE_BASE64` | Export .p12 depuis Keychain → `base64 -i cert.p12 \| pbcopy` |
| `P12_PASSWORD` | Mot de passe choisi à l'export |
| `BUILD_PROVISION_PROFILE_BASE64` | `.mobileprovision` depuis Apple Developer Portal |
| `KEYCHAIN_PASSWORD` | N'importe quel mot de passe aléatoire |
| `ASC_KEY_ID` | App Store Connect > Users > Keys |
| `ASC_ISSUER_ID` | Idem |
| `ASC_API_KEY_BASE64` | `.p8` → base64 |
| `CONFIG_XCCONFIG_BASE64` | **Nouveau** : `base64 -i Config.xcconfig \| pbcopy` — injecté au build |

Le workflow `build-testflight.yml` tourne sur `macos-15`.

Push sur `main` → build → TestFlight.

---

## Tests

```bash
xcodebuild test \
  -scheme HealthMap \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Tests inclus :
- `HealthCalculatorTests` — calculs déterministes vs web
- `HealthMapErrorTests` — surface d'erreur typée et mapping
- `NetworkServiceRetryTests` — retry exponentiel, distinction transient/permanent
- `AnalyticsPIIStrippingTests` — RGPD : aucune donnée de santé ne sort
- `Mocks/` — `MockAuthService`, `MockDatabaseService`, `MockAnalyticsService`
  pour les ViewModel tests sans réseau

---

## Architecture

```
HealthMap/
├── App/          — HealthMapApp (init + AppDelegate), ContentView
├── Core/         — HealthMapError, AppConfig, HealthCalculator
├── Models/       — Structures Codable
├── Views/        — Écrans SwiftUI
├── ViewModels/   — @MainActor ObservableObject
├── Services/     — Supabase, Auth, Database, Subscription, Analytics,
│                   Network (retry), CrashReporting (Sentry), Push
├── Utilities/    — AppLogger (os.Logger), extensions, thème
└── Resources/    — Assets, Info.plist, Config.xcconfig(.example)

HealthMapTests/
├── Mocks/        — Mocks des protocols de service
└── *Tests.swift
```

## Flux de démarrage

1. `HealthMapApp.init()` : CrashReporting → Logger → **Clerk.configure** → Supabase
   (avec JWT injecté par closure) → RevenueCat → Connectivity → Analytics
2. `AppDelegate` : enregistrement APNs (après onboarding, pas au premier lancement)
3. `ContentView` : Splash → Onboarding → Auth → Questionnaire → Dashboard

## Flux d'authentification (Clerk, depuis 20 avril 2026)

- **Provider unique** : Clerk (`pk_live_Y2xlcmsuaGVhbHRobWFwLmZyJA`, domaine custom
  `clerk.healthmap.fr`). Mêmes utilisateurs que le web — PAS de Supabase Auth.
- **Signup email** : 2 étapes via Clerk iOS SDK
  1. `AuthService.signUpStart` → `Clerk.shared.auth.signUp(...).sendEmailCode()`
  2. `AuthService.verifySignUpCode(code)` → `signUp.verifyEmailCode(code)` →
     la session Clerk bascule en `.complete`, `authStateChanges()` émet `.signedIn`.
- **Google OAuth** : `Clerk.shared.auth.signInWithOAuth(provider: .google, prefersEphemeralWebBrowserSession: true)`.
  Clerk monte sa propre `ASWebAuthenticationSession`.
- **Apple** : `SignInWithAppleButton` SwiftUI natif (AuthView) → idToken transmis à
  `Clerk.shared.auth.signInWithIdToken(idToken, provider: .apple)`.
- **Reset password** : `AuthService.resetPassword(email:)` (prépare `resetPasswordEmailCode`)
  puis `completeResetPassword(code:newPassword:)`.
- **JWT template Supabase** : `Clerk.shared.session?.getToken(.init(template: "supabase"))`
  renvoie un JWT dont `sub` = `profiles.id` (UUID). Cet JWT est injecté dans le
  `SupabaseClientOptions.AuthOptions.accessToken` closure — les RLS policies
  Supabase continuent de fonctionner comme avant.
- **Resolve `profiles.id`** : `ClerkProfileResolver.resolveProfileUUID(for:)` fait
  un SELECT `profiles WHERE clerk_id = :clerkId`, ou INSERT si fresh signup. Miroir
  exact du `resolveProfile()` web (`src/context/AuthContext.jsx`).

### Prérequis Clerk Dashboard (à faire une seule fois, côté web)

Les étapes suivantes sont déjà faites par le web (même instance Clerk, partagée) :
- JWT template `supabase` configuré, `sub` mappé sur `user.public_metadata.profile_id`
  (= `profiles.id`)
- Provider Apple configuré (Service ID, Team ID, Key ID, clé `.p8`)
- Provider Google configuré (Client ID / Secret OAuth)
- Email code signup activé (pas de magic link)
- Domaine custom `clerk.healthmap.fr` vérifié

## Conformité App Store

- ✅ **Guideline 5.1.1(v)** — suppression de compte : bouton « Supprimer mon compte »
  dans `ProfileView` avec **double confirmation** (alerte puis feuille où l'utilisateur
  doit taper le mot « SUPPRIMER »). Appelle `AuthViewModel.deleteAccount()` →
  `AuthService.deleteAccount()` → `DatabaseService.deleteAllUserData()` → Edge Function
  `delete-user`. Événements analytics `account_deletion_requested` / `_completed` / `_failed`
  pour la télémétrie. **À faire côté infra** : déployer la fonction `delete-user` sur
  Supabase (voir Étape 9).
- ✅ **Guideline 4.8 — Sign in with Apple** : `SignInWithAppleButton` présent dans
  `AuthView`, nonce généré via `AppleSignInNonce.make()` (SHA256 côté Apple, brut conservé
  pour la trace). Le callback appelle `AuthService.signInWithApple(idToken:rawNonce:)` qui
  depuis le 20 avril 2026 forwarde le token à Clerk via
  `Clerk.shared.auth.signInWithIdToken(idToken, provider: .apple)`. **À faire côté Xcode** :
  activer la capability « Sign in with Apple » dans Signing & Capabilities (Étape 4).
- ❌ **App Tracking Transparency** — `NSUserTrackingUsageDescription` a été retiré de
  l'Info.plist car ATT n'est pas utilisé. Aucun tracking cross-app : l'analytics est
  first-party (Supabase + PostHog EU).
- ✅ Privacy nutrition labels — aucune donnée de santé n'est envoyée aux analytics
  (voir `AnalyticsPIIStrippingTests`).
- ✅ Encryption — `ITSAppUsesNonExemptEncryption = NO` (HTTPS standard uniquement).

## Conformité RGPD

- ✅ Art. 6 — consentement explicite (écran d'onboarding)
- ✅ Art. 9 — données santé chiffrées en transit, stockées en UE (Supabase EU region)
- ✅ Art. 17 — droit à l'effacement (`DatabaseService.deleteAllUserData`)
- ✅ Art. 20 — portabilité (export PDF du dashboard)
- ⚠️ **Supabase n'est pas certifié HDS** — voir l'audit de sécurité pour le plan de migration

---

## Comptes de test

| Email | Password | Profil |
|-------|----------|--------|
| audit-a@test.com | AuditA123! | Thomas, sportif omnivore (score élevé) |
| audit-b@test.com | AuditB123! | Léa, végétarienne stressée (score bas) |
| audit-c@test.com | AuditC123! | René, fumeur sous médicaments (score bas) |

## Support

Issues : https://github.com/healthmap/healthmap-ios/issues
