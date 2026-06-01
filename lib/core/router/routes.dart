abstract class Routes {
  static const splash = '/';

  // Handoff — reads #sh=<jwt> from the URL hash and calls setSession.
  // Used by the Shell to inject a session token into the Cards iframe.
  static const handoff = '/auth/handoff';

  // Email OTP — direct sign-in for users accessing Cards outside the Shell.
  static const email = '/auth/email';
  static const otp = '/auth/otp';

  // Shown when a user has a valid Supabase session but no tenant provisioning.
  static const notProvisioned = '/auth/not-provisioned';

  // PIN auth — gate shown after a valid session is restored.
  static const pinSetup = '/auth/pin/setup';
  static const pinEntry = '/auth/pin/enter';

  static const home = '/home';
  static const profile = '/profile';
  static const profileEdit = '/profile/edit';
  static const licencesList = '/licences';
  static const licenceCreate = '/licences/new';
  static const licenceCapture = '/licences/capture';
  // Profile fill from driver licence scan — shown between OCR and licence save
  static const profileFillFromLicence = '/licences/fill-profile';
  static const licenceDetail = '/licences/:id';
  static const licenceEdit = '/licences/:id/edit';
  static const certificatesList = '/certificates';
  static const certificateCreate = '/certificates/new';
  static const certificateDetail = '/certificates/:id';
  static const certificateEdit = '/certificates/:id/edit';

  static const settings = '/settings';
  static const privacyPolicy = '/legal/privacy';
  static const termsOfUse = '/legal/terms';

  // Onboarding wizard — shown on first sign-in when profile is incomplete.
  static const onboarding = '/onboarding';
  static const onboardingProfile = '/onboarding/profile';
  static const onboardingDone = '/onboarding/done';

  // D2: public licence-verification page — no auth required.
  static const share = '/share';

  /// URL builders for path-parameter routes. Use these instead of hand-rolled
  /// string interpolation so the route shapes stay in one place.
  static String licenceDetailFor(String id) => '/licences/$id';
  static String licenceEditFor(String id) => '/licences/$id/edit';

  static String certificateDetailFor(String id) => '/certificates/$id';
  static String certificateEditFor(String id) => '/certificates/$id/edit';
}
