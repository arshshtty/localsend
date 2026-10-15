import 'package:localsend_isolates/rust/api/diagnostics.dart';

/// Thrown when the HTTP server fails to start.
///
/// Carries the typed [StartError] from Rust (e.g. [StartError_PortInUse]) and
/// a human-readable [message], which [toString] returns so existing error
/// snackbars keep showing plain text.
class ServerStartException implements Exception {
  final StartError error;
  final String message;

  const ServerStartException({
    required this.error,
    required this.message,
  });

  @override
  String toString() => message;
}
