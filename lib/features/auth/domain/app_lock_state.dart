/// Phase of the PIN lock gate.
///
/// - [checking]          — async has_pin() call in flight; router holds at splash.
/// - [pinSetupRequired]  — session valid, no PIN set; user must choose one.
/// - [pinEntryRequired]  — session valid, PIN set; user must enter it.
/// - [unlocked]          — either no session (OTP will gate) or PIN verified.
enum AppLockPhase {
  checking,
  pinSetupRequired,
  pinEntryRequired,
  unlocked,
}
