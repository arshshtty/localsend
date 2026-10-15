import 'package:localsend_isolates/rust/api/diagnostics.dart';
import 'package:refena_flutter/refena_flutter.dart';

typedef RunDiagnostics = Future<Diagnostics> Function(int port);

/// Runs network diagnostics through the Rust bridge. Errors are passed to the UI.
/// Widget tests override this provider with [fakeRunDiagnostics].
final runDiagnosticsProvider = Provider<RunDiagnostics>((ref) {
  return (port) => runDiagnostics(port: port);
});

/// Overall time limit for one diagnostics run.
const diagnosticsTimeout = Duration(seconds: 5);

class DiagnosticsTimeoutException implements Exception {
  @override
  String toString() => 'The network check took longer than ${diagnosticsTimeout.inSeconds} seconds and was stopped.';
}

/// Runs [run] with [diagnosticsTimeout]. No fallback to sample data.
Future<Diagnostics> runDiagnosticsWithTimeout(RunDiagnostics run, int port, {Duration timeout = diagnosticsTimeout}) {
  return run(port).timeout(timeout, onTimeout: () => throw DiagnosticsTimeoutException());
}

bool isHeldByThisApp(PortStatus s) => s is PortStatus_HeldByThisApp;

/// Fixed sample data in the bridge's types (marked as stub). For tests only.
Future<Diagnostics> fakeRunDiagnostics(int port) async {
  return const Diagnostics(
    interfaces: [
      InterfaceDiag(
        name: 'en0',
        index: 1,
        addresses: ['192.168.1.20'],
        up: true,
        loopback: false,
        multicastCapable: true,
        joinV4: JoinResult.ok(),
        joinV6: JoinResult.notAttempted(),
      ),
      InterfaceDiag(
        name: 'tailscale0',
        index: 2,
        addresses: ['100.101.102.103'],
        up: true,
        loopback: false,
        multicastCapable: false,
        joinV4: JoinResult.failed('VPN interface does not carry multicast'),
        joinV6: JoinResult.notAttempted(),
      ),
    ],
    tcpPort: PortStatus.free(),
    udpPort: PortStatus.free(),
    isStub: true,
  );
}

extension InterfaceDiagX on InterfaceDiag {
  bool get multicastWorks => up && multicastCapable && (joinV4 is JoinResult_Ok || joinV6 is JoinResult_Ok);

  /// Plain reason why multicast does not work, or null if it does.
  String? get noMulticastReason {
    if (!up) return 'Interface is down';
    if (joinV4 case JoinResult_Failed(:final field0)) return field0;
    if (joinV6 case JoinResult_Failed(:final field0)) return field0;
    if (!multicastCapable) return 'Interface does not support multicast';
    if (!multicastWorks) return 'Multicast was not tested';
    return null;
  }
}

extension DiagnosticsX on Diagnostics {
  /// Another app holds the port (conflict).
  bool get portInUse => tcpPort is PortStatus_InUse || udpPort is PortStatus_InUse;

  /// LocalSend itself holds the port (not a conflict).
  bool get portHeldByThisApp => isHeldByThisApp(tcpPort) || isHeldByThisApp(udpPort);

  /// Process id of the other app, e.g. "1234". The process name the backend
  /// may append ("1234 (name)") is stripped so it never shows up in the UI.
  String? get portPidHint => switch ((tcpPort, udpPort)) {
    (PortStatus_InUse(:final pidHint?), _) => stripProcessName(pidHint),
    (_, PortStatus_InUse(:final pidHint?)) => stripProcessName(pidHint),
    _ => null,
  };

  String? get portDeniedMessage => switch ((tcpPort, udpPort)) {
    (PortStatus_Denied(:final field0), _) => field0,
    (_, PortStatus_Denied(:final field0)) => field0,
    _ => null,
  };
}

/// "1234 (name)" -> "1234". Returns null if no pid is left.
String? stripProcessName(String pidHint) {
  final pid = RegExp(r'^\s*(\d+)').firstMatch(pidHint)?.group(1);
  return pid;
}

/// Appends [ip] to [peerIps] if not present (keeps order).
List<String> addPeerIp(List<String> peerIps, String ip) => peerIps.contains(ip) ? peerIps : [...peerIps, ip];
