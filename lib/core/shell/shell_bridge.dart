// Conditional export: web implementation on dart.library.html, stub elsewhere.
// Exports requestAndReceiveShellToken() — sends REQUEST_SHELL_TOKEN to the
// Shell parent frame and waits for SHELL_TOKEN_RESPONSE { token_hash }.
export 'shell_bridge_stub.dart' if (dart.library.html) 'shell_bridge_web.dart';
