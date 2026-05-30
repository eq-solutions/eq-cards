# EQ Cards — Architecture

**Status:** Phase 1 (mobile + web companion)
**Owner:** Royce Milmlow
**Last updated:** 2026-04-27

> This document is the binding architecture contract for EQ Cards v1. It is committed before any feature code. Every PR is reviewed against it. AI-assisted code that violates these rules is rejected, regardless of how clean it looks.
>
> Three rules govern this codebase:
> 1. **Boring beats clever.** This is a wallet, not a framework demo.
> 2. **Features are folders.** Cross-feature dependencies go through `core/`, never sideways.
> 3. **No code in widgets.** Business logic lives in repositories and notifiers. Widgets render and dispatch.

**Targets:** iOS, Android, Web (PWA via Flutter web). See §17 for the platform parity table.

---

## 1. Stack

| Layer | Choice | Locked version | Web? |
|---|---|---|---|
| Language | Dart | ≥ 3.5 | ✓ |
| UI framework | Flutter | ≥ 3.24 | ✓ |
| State management | Riverpod 2.x with `riverpod_generator` | ≥ 2.5 | ✓ |
| Models | `freezed` + `json_serializable` | ≥ 2.5 | ✓ |
| Routing | `go_router` | ≥ 14.0 | ✓ |
| Backend client | `supabase_flutter` | ≥ 2.5 | ✓ |
| HTTP (non-Supabase) | `dio` | ≥ 5.4 | ✓ |
| Local storage | `shared_preferences` (prefs + Supabase auth session) | latest stable | ✓ (uses IndexedDB on web) |
| Local DB cache | (deferred to v1.1) | — | — |
| Photo capture | `image_picker` | ^1.1.0 | ✓ (file dialog on web) |
| Image processing | `flutter_image_compress` (EXIF strip + resize + JPEG re-encode) | ^2.3.0 | ✓ |
| OCR | Google ML Kit (`google_mlkit_text_recognition`) | ^0.13.0 | ✗ — `kIsWeb` returns empty extraction (manual entry on web) |
| QR generation | `qr_flutter` | ^4.1.0 | ✓ |
| Push notifications | _(deferred to v1.1 — `firebase_*` removed 2026-05-30, never wired)_ | — | — |
| Local notifications | `flutter_local_notifications` + `timezone` | ^17.0.0 / ^0.9.0 | ✗ on web — fallback is in-app expiring badges |
| Analytics | `posthog_flutter` | ^4.7.0 | ✓ |
| Crash reporting | `sentry_flutter` | ^8.0.0 | ✓ |
| Biometric | `local_auth` | ^2.2.0 | ✗ — `BiometricGate` is a no-op on web |
| Lint | `very_good_analysis` | ^6.0.0 | ✓ |

**No other state management libraries. No BLoC, no GetX, no Provider directly.** Riverpod only.

**No other models pattern.** Every data class uses freezed. No hand-written `fromJson`/`toJson`.

**Removed Phase 1:** `image_cropper` was in the original stack but unused; the capture flow goes camera → OCR → edit form directly. Cropping is a v1.1 polish.

---

## 2. Folder structure

```
lib/
├── main.dart                      # Bootstraps Supabase, Sentry, PostHog
├── app.dart                       # Root MaterialApp.router + BiometricGate wrapper
│
├── core/                          # Cross-feature shared concerns. Nothing app-specific lives here.
│   ├── theme/
│   │   ├── eq_theme.dart          # ThemeData with EQ brand tokens
│   │   ├── eq_colours.dart        # Sky, Deep, Ice, Ink, Grey constants
│   │   ├── eq_typography.dart     # Plus Jakarta Sans text styles
│   │   └── eq_spacing.dart        # 8px grid: xs, sm, md, lg, xl
│   │
│   ├── router/
│   │   ├── app_router.dart        # go_router StatefulShellRoute, redirect, listen-bridge
│   │   └── routes.dart            # Type-safe route names
│   │
│   ├── shell/                     # Composition layer. Allowed to import feature barrels.
│   │   ├── home_shell_screen.dart # 3-tab Material 3 NavigationBar; wires alerts on licence-list change
│   │   ├── complete_profile_banner.dart  # Shown on /licences when profile incomplete
│   │   └── biometric_gate.dart    # Cold-launch + 5-min-background biometric prompt (kIsWeb no-op)
│   │
│   ├── widgets/                   # Truly shared primitives. <10 widgets max.
│   │   ├── eq_button.dart
│   │   ├── eq_card.dart
│   │   ├── eq_text_field.dart
│   │   └── eq_app_bar.dart
│   │
│   ├── supabase/
│   │   ├── supabase_client_provider.dart    # Single Supabase client instance
│   │   └── supabase_error_handler.dart
│   │
│   ├── error/
│   │   └── failure.dart           # Sealed Failure types (implements Exception)
│   │
│   ├── analytics/
│   │   └── analytics_service.dart # PostHog wrapper. Track named events only.
│   │
│   └── utils/
│       ├── date_utils.dart
│       ├── clipboard_utils.dart   # Single source of truth for copy + haptic + toast
│       └── photo_upload.dart      # EXIF-stripped uploader; Uint8List + File overloads
│
├── features/                      # All app features. Each is self-contained.
│   ├── auth/
│   │   ├── data/
│   │   │   ├── auth_repository.dart
│   │   │   └── aus_phone.dart     # E.164 normaliser + AUS-mobile validator (profile mobile field only — auth uses email since 2026-05-20)
│   │   ├── domain/
│   │   │   ├── auth_state.dart
│   │   │   └── auth_flow_state.dart  # sealed UI flow state
│   │   ├── presentation/
│   │   │   ├── notifiers/
│   │   │   │   ├── auth_state_provider.dart   # Stream<AuthState>
│   │   │   │   └── auth_flow_notifier.dart    # send/verify/clearError
│   │   │   └── screens/
│   │   │       ├── email_entry_screen.dart
│   │   │       └── otp_screen.dart
│   │   └── auth.dart              # Barrel export
│   │
│   ├── profile/
│   │   ├── data/
│   │   │   ├── profile_repository.dart
│   │   │   └── models/profile.dart                # freezed; nullable timestamps
│   │   ├── presentation/
│   │   │   ├── notifiers/profile_notifier.dart
│   │   │   ├── screens/
│   │   │   │   ├── profile_screen.dart
│   │   │   │   └── profile_edit_screen.dart
│   │   │   └── widgets/
│   │   │       ├── profile_field_row.dart         # Tap to copy field
│   │   │       └── copy_induction_block.dart      # The one big copy button
│   │   └── profile.dart
│   │
│   ├── licences/
│   │   ├── data/
│   │   │   ├── licence_repository.dart
│   │   │   ├── licence_types_repository.dart
│   │   │   ├── ocr_service.dart                   # Google ML Kit wrapper, kIsWeb no-op
│   │   │   └── models/
│   │   │       ├── licence.dart                   # freezed; metadata jsonb; transient signed URLs
│   │   │       └── licence_type.dart              # freezed
│   │   ├── presentation/
│   │   │   ├── notifiers/
│   │   │   │   ├── licences_list_notifier.dart
│   │   │   │   └── licence_types_provider.dart
│   │   │   ├── screens/
│   │   │   │   ├── licences_list_screen.dart      # List + add bottom sheet (camera vs manual)
│   │   │   │   ├── licence_detail_screen.dart     # Tap-to-copy on every field
│   │   │   │   └── licence_edit_screen.dart       # Manual + OCR-prefilled, both modes
│   │   │   └── widgets/
│   │   │       ├── licence_card.dart
│   │   │       └── expiry_badge.dart
│   │   └── licences.dart
│   │
│   ├── alerts/                    # Local expiry notifications
│   │   ├── data/alerts_scheduler.dart # Schedules at 90/30/7 days; mobile only
│   │   └── alerts.dart
│   │
│   └── settings/
│       ├── presentation/
│       │   ├── notifiers/biometric_settings_notifier.dart
│       │   └── screens/settings_screen.dart       # Sign out, biometric toggle, version
│       └── settings.dart
│
└── gen/                           # Generated *.g.dart and *.freezed.dart. Gitignored.
```

### Rules for the structure

- **Features cannot import from each other.** `features/profile/` cannot import from `features/licences/`. If two features need shared code, it goes in `core/`.
- **Composition exception:** `core/router/` and `core/shell/` are the *only* layers allowed to import multiple feature barrels. They are the composition root. Spirit of the rule: features stay loosely coupled, but something has to wire them together — that's `router` and `shell`.
- **Widgets do not import from `data/`.** Widgets read state via Riverpod providers exposed in `presentation/notifiers/`. Notifiers talk to repositories. Repositories talk to Supabase.
- **No `utils/` dumping ground inside features.** Feature-specific utils live next to the file that uses them. Reusable utils go in `core/utils/`.
- **One screen per file.** Always.
- **Barrel files (`feature_name.dart`) export only the public API.** Internals (notifiers, repositories) are not exported, except where another core layer (router, shell) needs them — currently `authRepositoryProvider`, `authStateChangesProvider`, `licencesListNotifierProvider`, `profileNotifierProvider`, `biometricSettingsNotifierProvider`, `alertsSchedulerProvider`.

---

## 3. State management — Riverpod patterns

### 3.1 Provider types — pick the right one

| Need | Provider type | Example |
|---|---|---|
| One-shot computed value | `@riverpod` function | `currentUserId(ref)` |
| Mutable state machine | `@riverpod class` extending `_$Notifier` | `LicencesListNotifier` |
| Async load + auto-cache | `@riverpod` async function | `licenceTypes(ref)` |
| Stream subscription | `@riverpod Stream` | `authStateChanges(ref)` |

### 3.2 Naming conventions

- Notifiers: `{Feature}Notifier` (e.g. `LicencesListNotifier`).
- Provider variables (auto-generated): camelCase of class.
- One notifier per screen-level state. Don't combine two screens into one notifier.

### 3.3 The notifier contract

Every notifier exposes:
- A `build()` returning the initial state (sync or async).
- Public methods that mutate state via `state = ...`.
- No widget logic. No `BuildContext`. Notifiers are pure Dart.

```dart
@riverpod
class LicencesListNotifier extends _$LicencesListNotifier {
  @override
  Future<List<Licence>> build() async {
    final repo = ref.read(licenceRepositoryProvider);
    return repo.getAllForCurrentUser();
  }

  Future<void> deleteLicence(String id) async {
    final repo = ref.read(licenceRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await repo.softDelete(id);
      return repo.getAllForCurrentUser();
    });
  }
}
```

### 3.4 Forbidden / required patterns

- ❌ `setState` outside trivial pure-UI widgets (animations, simple toggles).
- ❌ `StatefulWidget` for anything backed by Supabase data. Use `ConsumerWidget` + Riverpod.
- ❌ Reading providers inside `build` of a `StatelessWidget`. Use `ConsumerWidget`.
- ❌ `ref.read` inside **widget** `build` methods. Always `ref.watch` in widget builds.
- ❌ `ref.read` for **state-bearing** providers inside notifier `build()`. Use `ref.watch` so the notifier rebuilds when its dependencies change.
- ✅ `ref.read` IS acceptable inside notifier `build()` for **stable services** — repositories, the Supabase client, anything whose identity doesn't change for the lifetime of the notifier.
- ✅ `ref.listen` in a `@riverpod` function's body (e.g. the router) is acceptable when you want to react to events without rebuilding the producer. Use sparingly; document why.
- ❌ Singletons or global variables. Everything is a provider.

---

## 4. Data layer — repository pattern

### 4.1 The repository contract

Every feature with persistent data has a repository. Repositories are the **only place** Supabase is touched.

```dart
class LicenceRepository {
  LicenceRepository(this._client);
  final SupabaseClient _client;

  Future<List<Licence>> getAllForCurrentUser() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const NotAuthenticatedFailure();
    final rows = await _client
        .from('licences')
        .select()
        .eq('user_id', userId)
        .filter('deleted_at', 'is', null)
        .order('expiry_date');
    return (rows as List).cast<Map<String, dynamic>>().map(Licence.fromJson).toList();
  }

  Future<Licence> upsert(Licence licence) async { /* ... */ }
  Future<void> softDelete(String id) async { /* ... */ }
}

@riverpod
LicenceRepository licenceRepository(LicenceRepositoryRef ref) {
  return LicenceRepository(ref.watch(supabaseClientProvider));
}
```

### 4.2 Rules

- Repositories return domain models (freezed classes), never raw Supabase rows.
- Repositories throw typed `Failure` exceptions, never rethrow Supabase errors directly.
- Repositories never know about widgets, BuildContext, or routing.
- One repository per logical entity. `LicenceRepository`, not `DataRepository`.
- **Photo paths vs signed URLs:** repositories store the storage path in the DB, then post-fetch enrich the model with transient signed URLs (`photoFrontSignedUrl`, etc.) that aren't persisted. Signed URLs expire 1h.

### 4.3 Local cache (deferred to v1.1)

**v1 ships without a local DB cache.** Supabase + good loading states are sufficient. Adding Drift now buys cold-open speed only — and adds a real class of staleness/sync bugs we don't need yet.

v1 read path: skeleton screens while Supabase loads; HTTP image cache handles photo thumbnails. v1 write path: requires network — "you need network to add a licence" is an accepted UX trade for v1.

Drift returns in **v1.1**, paired with offline writes.

---

## 5. Models — freezed always

### 5.1 Pattern

```dart
@freezed
class Licence with _$Licence {
  const Licence._();

  const factory Licence({
    String? id,                                 // null for unsaved drafts; populated by Postgres on insert
    required String userId,
    required String licenceType,
    required String licenceNumber,
    required DateTime issueDate,
    required DateTime expiryDate,
    String? issuingAuthority,
    String? state,
    @JsonKey(name: 'photo_front_url') String? photoFrontPath,
    @JsonKey(name: 'photo_back_url') String? photoBackPath,
    String? notes,
    @Default(<String, dynamic>{}) Map<String, dynamic> metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    @JsonKey(includeFromJson: false, includeToJson: false) String? photoFrontSignedUrl,
    @JsonKey(includeFromJson: false, includeToJson: false) String? photoBackSignedUrl,
  }) = _Licence;

  factory Licence.fromJson(Map<String, dynamic> json) => _$LicenceFromJson(json);

  bool get isExpired => DateTime.now().isAfter(expiryDate);
}
```

### 5.2 Rules

- Every model is immutable (freezed enforces this).
- Every model has `fromJson` / `toJson` via `json_serializable`.
- Snake-case JSON ↔ camelCase Dart handled by `json_serializable` config (`field_rename: snake`). Override per-field via `@JsonKey(name: ...)` when needed (e.g. when DB column name differs from natural Dart camelCase).
- **Server-managed timestamps (`created_at`, `updated_at`) are nullable on freezed classes** so client-constructed drafts don't need placeholder values. The server populates them on read; repositories don't send them on upsert.
- **Transient computed fields** (e.g. signed URLs) use `@JsonKey(includeFromJson: false, includeToJson: false)` so they're set programmatically post-fetch and never serialised back.
- No business logic in models. Computed properties OK if pure (e.g. `bool get isExpired => DateTime.now().isAfter(expiryDate);`). Anything else lives in a notifier or service.

---

## 6. Routing — go_router

Single source of truth in `core/router/app_router.dart`. Routes defined as constants in `core/router/routes.dart`.

```dart
abstract class Routes {
  static const splash = '/';
  static const emailEntry = '/auth/email';
  static const otp = '/auth/otp';
  static const home = '/home';                       // legacy alias; redirects to licencesList
  static const profile = '/profile';
  static const profileEdit = '/profile/edit';
  static const licencesList = '/licences';
  static const licenceCreate = '/licences/new';
  static const licenceCapture = '/licences/capture'; // deprecated v1; capture is invoked inline
  static const licenceDetail = '/licences/:id';
  static const licenceEdit = '/licences/:id/edit';
  static const settings = '/settings';
}
```

The shell has 3 tabs implemented via `StatefulShellRoute.indexedStack`:
- **Branch 0 (Licences):** `/licences` with nested `/licences/new`, `/licences/:id`, `/licences/:id/edit`. Static `'new'` listed before wildcard `':id'` so go_router prefers the exact match.
- **Branch 1 (Profile):** `/profile` with nested `/profile/edit`.
- **Branch 2 (Settings):** `/settings`.

### 6.1 Auth guard

A `redirect` function checks `Supabase.instance.client.auth.currentSession` (sync). A `_AuthRouterNotifier` (`ChangeNotifier`) is bumped via `ref.listen(authStateChangesProvider, ...)` to re-evaluate the redirect when the auth stream fires. Unauthenticated users are bounced to `emailEntry`. Authenticated users on auth routes are bounced to `licencesList`.

### 6.2 Rules

- Routes inside the home shell preserve per-tab nav stacks (StatefulShellRoute behaviour).
- No imperative `Navigator.push` outside `go_router`. Always `context.go(...)` or `context.push(...)`.
- Cross-tab navigation uses `context.go(...)` (e.g. the "Finish" button on `CompleteProfileBanner` → `/profile/edit`).
- Deep links resolve through go_router config — `cards.eq.solutions/q/<id>` opens licence detail (Phase 2).

---

## 7. Theming — EQ brand tokens

### 7.1 Colours

```dart
abstract class EqColours {
  static const sky  = Color(0xFF3DA8D8);
  static const deep = Color(0xFF2986B4);
  static const ice  = Color(0xFFEAF5FB);
  static const ink  = Color(0xFF1A1A2E);
  static const grey = Color(0xFF666666);
  static const white = Color(0xFFFFFFFF);

  // Functional
  static const error = Color(0xFFD32F2F);
  static const warning = Color(0xFFF57C00);  // Used for expiring-soon licences
  static const success = Color(0xFF388E3C);
}
```

### 7.2 Spacing — 8px grid

```dart
abstract class EqSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}
```

### 7.3 Typography — Plus Jakarta Sans

Plus Jakarta Sans bundled as a font asset for mobile. On web, the same .ttf assets ship via the standard Flutter web font pipeline. Fallback to system font on any platform that can't load it.

### 7.4 Component primitives

`core/widgets/` contains the small set of EQ-branded primitives. **Every screen composes these.**

- `EqButton` — primary, secondary, destructive variants. 6px corner radius. 48dp min height.
- `EqCard` — Ice background, 8px corner radius.
- `EqTextField` — branded text input with consistent error styling.
- `EqAppBar` — Sky fill, white text.

---

## 8. The copy-paste utility — single source of truth

This is the wedge. Every copy action goes through one function (`core/utils/clipboard_utils.dart`):

```dart
Future<void> copyWithFeedback({
  required BuildContext context,
  required String value,
  required String label,
}) async {
  await Clipboard.setData(ClipboardData(text: value));
  await HapticFeedback.lightImpact();
  unawaited(AnalyticsService.track('copy_field', {'label': label}));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('$label copied'),
      duration: const Duration(milliseconds: 1200),
      behavior: SnackBarBehavior.floating,
      backgroundColor: EqColours.ink,
    ),
  );
}
```

**No screen implements its own copy logic.** Every "Copy" button calls `copyWithFeedback`. Haptic on web is a soft no-op (browsers don't expose it consistently); the toast and clipboard write still happen.

---

## 9. Error handling

### 9.1 Failure types

```dart
sealed class Failure implements Exception {
  const Failure();
}
class NetworkFailure extends Failure { const NetworkFailure(); }
class NotAuthenticatedFailure extends Failure { const NotAuthenticatedFailure(); }
class NotFoundFailure extends Failure { const NotFoundFailure(); }
class ValidationFailure extends Failure { const ValidationFailure(this.message); final String message; }
class ServerFailure extends Failure { const ServerFailure(this.code, this.message); final int code; final String message; }
class UnknownFailure extends Failure { const UnknownFailure(this.error); final Object error; }
```

`Failure implements Exception` — required so `throw mapSupabaseError(e)` doesn't trip the `only_throw_errors` lint.

### 9.2 Rules

- Repositories throw typed `Failure`. Never rethrow `PostgrestException` to UI.
- Notifiers catch `Failure` and surface user-readable messages.
- Sentry receives every uncaught exception in release builds.
- Network failures show a retry CTA. Auth failures bounce to login. Validation failures show inline.

---

## 10. Analytics — what we track

### 10.1 Principles

- Track named events, never page views.
- All events are user-action events. No passive tracking.
- No PII in event properties. User ID only via PostHog identification.
- Every event has a fixed schema. Document new events here before shipping.

### 10.2 v1 event taxonomy

| Event | Properties | Why |
|---|---|---|
| `app_opened` | `is_first_open: bool`, `platform: 'ios'\|'android'\|'web'` | Daily active baseline + platform mix |
| `signup_completed` | `method: 'email'` | Conversion funnel |
| `profile_field_filled` | `field: string` | Which fields people actually fill |
| `licence_added` | `licence_type: string`, `via_ocr: bool` | Adoption + OCR efficacy |
| `licence_deleted` | — | Churn signal |
| `copy_field` | `label: string` | **The headline metric.** ≥ 5/week per user = wedge works. |
| `copy_induction_block` | — | Power-user signal |
| `qr_generated` | `licence_id: string` | Phase 1 → 2 bridge |
| `expiry_alert_received` | `days_before: int` | Notification efficacy (mobile only) |
| `expiry_alert_tapped` | `days_before: int` | Are they useful? |

---

## 11. Security & privacy

### 11.1 Auth tokens

- Supabase persists the session via its default `shared_preferences` storage on every platform (NSUserDefaults on iOS, SharedPreferences on Android, `localStorage`/IndexedDB on web). Acceptable for the web-first v1.
- NB: this is **not** OS-encrypted storage. A dedicated secure store (Keychain / EncryptedSharedPreferences via `flutter_secure_storage`) was speced but never wired; the dep was removed 2026-05-30 as unused. Revisit for the mobile threat model if native builds ship, or if we move to HttpOnly cookie auth.
- Never written to logs, never in analytics events, never in error reports.

### 11.2 Photos

- Captured photos uploaded to Supabase Storage in a private bucket.
- Access via signed URLs only, expiry 1h.
- Photos compressed before upload — JPEG quality 80, scaled so neither side is below ~1080px.
- **EXIF must be stripped on upload** to remove GPS coordinates and device metadata. The upload helper in `core/utils/photo_upload.dart` handles this in one place via `flutter_image_compress` (`keepExif: false`).
- The helper exposes both a `Uint8List` API (used cross-platform) and a `File` API (mobile convenience). The `File` overload reads bytes and delegates.

### 11.3 RLS policies

Every table has RLS enforced. Three policies per table (`SELECT`, `INSERT`, `UPDATE`):

```sql
CREATE POLICY "users_read_own_profile"
  ON profiles FOR SELECT USING (id = auth.uid());
```

`licences` and `audit_log` follow the same shape with `user_id = auth.uid()`. Storage policies live in `0003_storage_setup.sql` and gate by the first segment of the path being `auth.uid()`.

### 11.4 Biometric gating (mobile only)

Mobile: app requires FaceID / TouchID / device passcode on cold launch when biometrics are enabled (default: on). After 5 minutes in the background, the gate re-locks. Implementation: `local_auth` package, gated in `core/shell/biometric_gate.dart`.

Web: `BiometricGate` short-circuits via `kIsWeb` and lets the child render immediately. Browser session security (HTTPS + Supabase session cookies + idle timeout) covers the equivalent for v1. WebAuthn-based reauth is a v1.1 candidate.

### 11.5 Web platform considerations

- **OCR (`google_mlkit_text_recognition`)** is mobile-only. The `OcrService` returns an empty `OcrExtraction` on web; the licence form falls back to manual entry. Cloud OCR fallback (Google Cloud Vision via Edge Function) is a v1.1 path.
- **`local_auth`** is mobile-only — `BiometricGate` is a no-op on web (see §11.4).
- **`flutter_local_notifications`** has reduced web support; v1 web does NOT schedule expiry alerts. In-app expiring badges still render (`ExpiryBadge` works everywhere).
- **Camera** on web becomes a file picker (image_picker handles this transparently). No live camera viewfinder.
- **PWA shell** (manifest + service worker) is configured by `flutter create --platforms=web` defaults; brand polish (icons, theme color, install prompt) is v1.1.

---

## 12. Testing strategy

v1 testing budget is small and intentional. Don't chase coverage; chase confidence on the things that matter.

### 12.1 What we test

- **Pure model tests** — `Profile.isComplete`, `Profile.fullAddress`, `Licence.daysUntilExpiry`, `Licence.isExpiringSoon`, `Licence.isExpired`. Done.
- **Pure utility tests** — `aus_phone.dart` normaliser + validator. Done (13 cases).
- **Widget tests for `LicenceCard`** — renders correctly for valid, expiring, expired states. *Pending.*
- **Widget tests for `copyWithFeedback`** — verifies clipboard write, haptic call, snackbar appearance. *Pending.*
- **Repository unit tests** — fake the Supabase client. Test happy path + auth failure + network failure for each repo method. *Pending.*
- **Golden tests for `EqButton`, `EqCard`, `EqTextField`** — catches accidental theme regressions. *Pending.*

### 12.2 What we don't test in v1

- Screen-level integration tests (too brittle while UI is changing weekly).
- E2E tests (Maestro/Patrol). Defer to v1.1 once flows stabilise.
- 100% coverage. Anyone chasing this is procrastinating.

---

## 13. CI/CD

### 13.1 GitHub Actions pipeline

**On every push to `main`:**
1. `flutter analyze` — must pass.
2. `flutter test` — must pass.

**On a tag matching `release/v*` OR a manual `workflow_dispatch`:**
3. iOS build → upload to TestFlight (internal testers).
4. Android build → upload to Play Internal Testing.
5. Web build (`flutter build web --release`) → deploy to Netlify (decided §16 Q5). Target domain: `cards.eq.solutions`. Each push to `main` auto-deploys via GitHub → Netlify webhook.
6. Sentry release tag created.

Rationale: every-push-to-TestFlight in a solo + AI-assisted codebase trains internal testers to ignore broken builds. Tester slots and goodwill are precious. Ship to them deliberately, on a release tag.

### 13.2 Branch strategy

- `main` is the only long-lived branch. Always green on `flutter analyze` + `flutter test`.
- Feature work in branches named `feat/<feature>-<short-desc>`, e.g. `feat/licences-ocr-prefill`.
- Squash merge to main. No merge commits.
- Releases tagged `release/v0.1.3` etc.

### 13.3 Versioning

- App version: `MAJOR.MINOR.PATCH+BUILD` (e.g. `0.1.3+47`).
- Build number auto-incremented by GitHub Actions.
- Version bumps in PRs.

---

## 14. Vibe-coding rules

This codebase is built solo with heavy AI assistance. The risk is unmaintainable sprawl. These rules contain it:

1. **Read this document first, every session.** Before asking AI to write code, paste relevant sections of this doc into the prompt context.
2. **One feature at a time.** Don't ask AI to scaffold five features at once. *Note (Phase 0/1):* this rule was deliberately relaxed for the initial Phase 0 + Phase 1 scaffold pass on a brand-new repo. Re-engage from v1.1 onwards.
3. **Name files before generating code.** Tell the AI "create `lib/features/licences/data/licence_repository.dart`" — never "create the licence repository wherever you think." Folder structure is locked.
4. **Reject sprawl.** If AI suggests a new package, util, or pattern not in this doc, the answer is no — or update this doc first, deliberately.
5. **Every PR has a clear scope.** "Implement profile edit screen" is OK. "Improve profile" is not.
6. **No silent abstractions.** If AI introduces a base class, mixin, or generic utility, review it like a stranger wrote it.
7. **Run `flutter analyze` before every commit.** CI will catch you, but local feedback is faster.

---

## 15. Out of scope for v1

The following are explicitly deferred:

- Tenants, memberships, multi-org support
- Boss-side dashboards
- Module marketplace / module activation
- Stripe / subscriptions / paywall
- Apple Wallet pass generation (v1.1)
- Apple Watch companion (v1.2+)
- Family/team profile sharing
- Dark mode (v1.1)
- Offline writes (v1.1)
- Local DB cache / Drift (v1.1, alongside offline writes)
- Cloud OCR fallback for web (v1.1; on-device ML Kit is mobile-only in v1)
- WebAuthn / passkey reauth on web (v1.1)
- Web push notifications via FCM (v1.1)
- Issuer verification API integrations (Phase 2+)
- Renewal marketplace (Phase 3)

---

## 16. Open architectural questions

1. **Push notifications: FCM-only, or APNs direct?** v1 ships local notifs only (mobile). Server push (FCM) deferred to v1.1+ when boss-side dashboards or shared expiry triggers exist.
2. ~~Drift cache or skip?~~ **Decided 2026-04-27: defer to v1.1.** v1 read path uses Supabase + skeletons + HTTP image cache. See §4.3.
3. ~~OCR: on-device only or cloud fallback?~~ **Decided 2026-04-27 (mobile), revised 2026-04-28 (web).** Mobile: on-device ML Kit (private, free, offline). Web: Anthropic Claude Vision via Supabase Edge Function `ocr-licence` (image leaves device, ~$3-5 per 1000 calls, returns structured fields directly — no regex post-processing). Both paths produce a unified `OcrExtraction` result. The Edge Function requires `ANTHROPIC_API_KEY` set via `supabase secrets set` before deploy. Image is base64-encoded client-side and EXIF-stripped via `flutter_image_compress` (mobile path) — web path passes raw bytes; add EXIF strip on web before upload if licence sensitivity becomes a concern.
4. ~~Phone OTP: Supabase native or Twilio Verify direct?~~ **Decided 2026-04-27: Supabase native with Twilio configured as the SMS sender in Supabase Auth settings.** **Superseded 2026-05-20: switched to email OTP via Supabase's built-in mailer** to remove the Twilio dependency and SMS cost for the pilot. Phone-as-identity model retired; mobile is now a profile field, not an auth identifier. Re-evaluate adding phone-OTP back as an alternative sign-in method post-pilot if user feedback demands it.
5. ~~Web hosting: Cloudflare Pages or Netlify?~~ **Decided 2026-04-28: Netlify.** Matches the existing EQ Solutions / SKS deploy pattern (eq-solves-field.netlify.app, sks-nsw-labour.netlify.app, eq-solves-service.netlify.app). Single dashboard for all sites, GitHub-push auto-deploy. Cards site target: `cards.eq.solutions` via Netlify custom domain.
6. **PWA brand polish (icons, install prompt, theme color)** — v1.1 work.

---

## 17. Platform parity table

| Feature | iOS | Android | Web |
|---|---|---|---|
| Email OTP auth | ✓ | ✓ | ✓ |
| Profile view + edit + tap-to-copy | ✓ | ✓ | ✓ |
| Licence list + detail + tap-to-copy | ✓ | ✓ | ✓ |
| Licence add (manual entry) | ✓ | ✓ | ✓ |
| Licence add (camera + OCR) | ✓ ML Kit | ✓ ML Kit | File picker + Claude Vision (Edge Function) |
| Photo upload (EXIF stripped) | ✓ | ✓ | ✓ |
| Expiry alerts (local notifs at 90/30/7d) | ✓ | ✓ | ✗ (in-app badges only) |
| Biometric gate on cold launch + 5min bg | ✓ | ✓ | ✗ (no-op) |
| Sign out | ✓ | ✓ | ✓ |
| Settings (biometric toggle, version) | ✓ | ✓ | Toggle persists but has no effect |

---

## 18. Cross-module data architecture

> **✓ RECONCILIATION RESOLVED (2026-05-21 — Units 3 + 4).**
>
> The decision is **Path A: consolidate.** Cards data moved to eq-canonical
> (`jvknxcmbtrfnxfrwfimn`) via the one-time Unit 3 migration (`scripts/migrate-to-canonical.ts`,
> removed post-migration 2026-05-30 — see CHANGELOG) and the Unit 4 canonical flip (`0d14c50`).
> The module-local cache model (Path B) was rejected.
>
> **What changed:**
> - `§18.1` below described a "no shared database" model between EQ surfaces. That model is
>   now superseded **for inter-EQ data flows**. Inside EQ, surfaces share data via RLS on
>   the canonical project — no consent flow, no token exchange.
> - `§18.2–§18.3` (share-intent URL + redeem endpoint) are preserved as the export profile
>   for **external consumers** (non-EQ surfaces: e.g. a principal contractor's compliance
>   portal pulling a tradie's licence wallet). This API is still Phase 2.
> - Auth: EQ Shell mints a JWT (`app_metadata.tenant_id`) and passes it to Cards via
>   `#sh=<jwt>` iframe URL hash. Cards calls `setSession` and proceeds. Standalone access
>   uses email-OTP directly against eq-canonical.
>
> The text below describes the original v1 architecture and the external share API contract.
> §18.1 is archaeology; §18.2–§18.7 remain forward documentation for the external API.

---

EQ Cards is the first product in a planned EQ Solutions suite (EQ Field, EQ Expenses, EQ Quotes, EQ Ops). When another module needs EQ Cards data — e.g. a tradie joining a job in EQ Field who has profile + licences in EQ Cards — data flows through an explicit consent surface, **not** direct database access.

**Project status (2026-04-28, updated 2026-05-21):** ~~the Supabase project `hshvnjzczdytfiklhojz` (originally provisioned as "EQ Assets") is now used **exclusively by EQ Cards**~~ — **this is now the legacy project**. As of Unit 4, Cards reads/writes from eq-canonical (`jvknxcmbtrfnxfrwfimn`) via `eq_cards_*` bridge RPCs. The legacy project (`hshvnjzczdytfiklhojz`) is kept live for the rollback window only.

### 18.1 Decision: independent products + share API (decided 2026-04-28; superseded 2026-05-21 for inter-EQ flows)

> **⚠ This decision has been superseded for cross-EQ-surface data flows.** As of
> Unit 4 (2026-05-21), EQ Cards data lives in the canonical project (`jvknxcmbtrfnxfrwfimn`)
> alongside every other EQ surface. Inter-EQ access is via RLS on the canonical project,
> not the share-API flow below.
>
> The share API described here is preserved as the contract for **external consumers**
> (non-EQ third-party apps wanting to read a tradie's wallet). It is still Phase 2.

~~Each EQ module is its own Supabase project, its own auth pool, its own schema. There is **no shared database**.~~ Cross-module data flows (for external consumers) via:

1. **Source** module exposes a share-intent URL.
2. **Destination** module opens the source URL with desired scopes + a callback.
3. **Source** prompts the user for explicit consent ("EQ Field wants to read your profile and 3 licences").
4. **Source** issues a short-lived, one-time token bound to `(user_id, destination, scopes)`.
5. **Destination** redeems the token server-to-server for the data, then stores its own copy.

OAuth2-shaped without the formal OIDC layer. Closest analogue: "Sign in with Apple," but for product-to-product data import.

**Why not shared Supabase:**
- **Product boundaries.** Each EQ module is sellable independently. A customer may buy EQ Cards as a personal wallet without ever touching EQ Field. Mixing data in one project couples the products commercially.
- **Blast radius.** One product's RLS bug shouldn't compromise every other product's data.

### 18.2 The share-intent URL

```
GET https://cards.eq.solutions/share
  ?to=<destination_app_id>
  &scopes=<comma_separated_scopes>
  &callback=<destination_redirect_uri>
  &state=<csrf_token>
```

**Allowed scopes (v1 EQ Cards):** `profile`, `licences`, `licences:metadata`. New scopes require an entry in this section before they go live.

**Allowed destinations** are pre-registered (`eq-field`, `eq-expenses`, `eq-quotes`, `eq-ops`) with whitelisted redirect URIs in the source's `share_destinations` table. No open redirect.

**On allow:**
```
HTTP 302
Location: <callback>?token=<one_time_token>&state=<original_state>
```
Token is one-time-use, TTL 5 minutes, bound to `(user_id, destination, scopes)`. Tokens are **not** redeemable from a browser.

### 18.3 Redeem endpoint (server-to-server)

```
POST https://cards.eq.solutions/api/v1/share/redeem
Authorization: Bearer <destination_app_secret>
Body: { "token": "..." }

200 OK { "profile": { ... }, "licences": [ ... ] }
```

Destination apps authenticate with a server-side secret hashed in the source's `share_destinations` table. The secret never reaches the client.

### 18.4 EQ Cards as system of record

When the destination receives data:
- It stores its own copy in its own schema (works offline + independently).
- It records `cards_imported_at` and the scope set so the user can re-import later.
- **No automatic sync.** If the user updates their profile in EQ Cards, EQ Field doesn't see the change until the user re-imports. Push / webhook sync is a v2.x consideration; v1 of this contract is pull-only.

### 18.5 Reserved schema (NOT v1)

When this is implemented (Phase 2+), EQ Cards adds:

| Table | Purpose |
|---|---|
| `share_destinations` | Pre-registered destination apps: id, name, redirect URIs, secret hash, allowed scopes |
| `share_grants` | User → destination → scopes → granted_at / revoked_at. User-visible in Settings → Connected apps |
| `share_tokens` | Short-lived one-time tokens (TTL ~5 min), bound to (user, destination, scopes) |

User-facing surface (Phase 2+): **Settings → Connected apps** lists active grants with a revoke button per app.

### 18.6 What v1 commits to

**v1 builds:** nothing. §18 is forward documentation only.

**v1 preserves:** the schema decisions in §5 and SCHEMA.md are compatible with the share contract — `profiles` and `licences` (with `metadata jsonb`) serialise to JSON cleanly without restructure.

**v1 explicitly does NOT:**
- Build the `/share` endpoint
- Build the `/api/v1/share/redeem` endpoint
- Build the consent UI
- Build deep linking for `cards.eq.solutions/share`
- Register any destination apps

Implementation is a Phase 2 ticket, scheduled when EQ Cards has ≥ 10 active users **and** another EQ module has a feature that would consume the data. Until then, the wedge (tap-to-copy onto induction forms) is the de facto cross-module integration.

### 18.7 Implications for other EQ modules

When EQ Field, Expenses, Quotes or Ops are built:
- Each gets its own Supabase project + auth pool.
- Each registers as a destination in EQ Cards' `share_destinations` (when the share infrastructure ships).
- Each stores its own profile/licence copy locally.
- Each implements its own "Connect EQ Cards" flow per §18.2.
- The user signs into each product separately (no shared session).

Single sign-on across the suite is **not** in scope. If we later decide we want it, it's a separate identity service (likely after Phase 3 multi-tenant work), not retrofitted into this share contract.

---

**Revisions:**
- 2026-04-27 (Phase 0) — Initial commit. Three baseline tightenings: §3.4 `ref.read` rule clarified; §4.3 Drift deferred to v1.1; §13.1 TestFlight gated behind release tags / manual dispatch.
- 2026-04-27 (Phase 0.5) — Schema doc committed alongside; `metadata jsonb` added to `licences` so Medicare cards live in the same table.
- 2026-04-27 (Phase 1) — Auth, profile, licences, alerts, settings, home shell shipped. §14.2 deliberately relaxed for the brand-new scaffold pass. New `core/shell/` composition layer documented (§2). `Failure implements Exception` added (§9.1). Photo `metadata jsonb` and signed URL pattern committed (§4.2, §5.1). Routes table includes `licenceCreate`; `licenceCapture` deprecated. `flutter_image_compress` and `timezone` added to stack; `image_cropper` removed as unused.
- 2026-04-27 (Phase 1 — web) — Web companion target added. `kIsWeb` guards on OCR, biometric, local notifications. Photo upload helper exposes `Uint8List` API for cross-platform photos. New §11.5 web considerations + §17 platform parity table.
- 2026-04-28 (Phase 1 — modules) — §18 added: cross-module data architecture committed to Option B (independent products + share API + explicit consent). Forward documentation only; no code in v1. Settings → Connected apps surface reserved for Phase 2+.
- 2026-05-21 (Units 3 + 4) — §18 reconciliation resolved. Path A (consolidate to canonical) taken. Cards data moved to eq-canonical (`jvknxcmbtrfnxfrwfimn`) via Unit 3 migration + Unit 4 canonical flip. §18.1 "no shared database" superseded for inter-EQ flows; §18.2–§18.3 share API preserved as the external-consumer contract (Phase 2). §18 RECONCILIATION PENDING block replaced with RESOLVED. Auth model updated: Shell JWT handoff (primary) + email-OTP (standalone).

**End of document.** Update this file when architectural decisions change. Date and signature every revision.
