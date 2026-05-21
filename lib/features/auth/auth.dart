export 'data/auth_repository.dart'
    show AuthRepository, authRepositoryProvider;
export 'domain/auth_state.dart' show AuthState;
export 'presentation/notifiers/auth_state_provider.dart'
    show authStateChangesProvider;
// Cards Unit 4 (2026-05-21) — iframe handoff replaces email-OTP.
// Old EmailEntryScreen + OtpScreen are deleted in this revision.
export 'presentation/screens/iframe_handoff_screen.dart'
    show IframeHandoffScreen;
