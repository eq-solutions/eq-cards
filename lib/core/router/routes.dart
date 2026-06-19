abstract class Routes {
  static const splash = '/';

  // Shell iframe entry point — loaded by CardsIframe.tsx with ?shell=1.
  // If already signed in, the router redirects to licencesList.
  // If not signed in, redirected to email sign-in.
  static const handoff = '/auth/handoff';

  // Email OTP — direct sign-in for users accessing Cards outside the Shell.
  static const email = '/auth/email';
  static const otp = '/auth/otp';

  // Shown when a user has a valid Supabase session but no tenant provisioning.
  static const notProvisioned = '/auth/not-provisioned';

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

  // D2: public licence-verification page — no auth required.
  static const share = '/share';

  /// URL builders for path-parameter routes. Use these instead of hand-rolled
  /// string interpolation so the route shapes stay in one place.
  static String licenceDetailFor(String id) => '/licences/$id';
  static String licenceEditFor(String id) => '/licences/$id/edit';

  static String certificateDetailFor(String id) => '/certificates/$id';
  static String certificateEditFor(String id) => '/certificates/$id/edit';

  // Admin — org admin only; entered from Settings, outside the shell.
  static const adminMembers = '/admin/members';
  static const adminMemberNew = '/admin/members/new';
  static const adminMemberDetail = '/admin/members/:workerId';
  static const adminMemberEdit = '/admin/members/:workerId/edit';

  static String adminMemberDetailFor(String id) => '/admin/members/$id';
  static String adminMemberEditFor(String id) => '/admin/members/$id/edit';

  // Claim — deep-link target for workers claiming an invite.
  static const claim = '/claim';

  // Join — worker scans QR or enters a join code to onboard into a tenant.
  // Public route — no auth required.
  static const join = '/join';

  // Provision — org admin self-provisions a new workspace via a one-time link.
  // ?token=<uuid>&name=<orgName>  (name is optional display hint)
  // Public route — no auth required.
  static const provision = '/provision';

  // Worker self-service — APP 12 access to own employment record.
  static const workerHrRecord = '/settings/hr-record';
}
