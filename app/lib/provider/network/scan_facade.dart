import 'dart:async';

import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/network/scan_targets.dart';
import 'package:localsend_isolates/rust/api/diagnostics.dart' as rust_diag;
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('ScanFacade');

/// Timeout per peer probe (Tailscale CLI peers and entered peer IPs).
const peerProbeTimeoutMs = 500;

/// The Rust calls used by the smart scan; overridable in tests.
class ScanNetworkProbes {
  const ScanNetworkProbes();

  Future<rust_diag.Diagnostics> runDiagnostics({required int port}) => rust_diag.runDiagnostics(port: port);

  Future<List<rust_diag.PeerProbeResult>> probePeers({required List<String> peerIps, required int port, required int timeoutMs}) =>
      rust_diag.probePeers(peerIps: peerIps, port: port, timeoutMs: timeoutMs);
}

final scanNetworkProbesProvider = Provider<ScanNetworkProbes>((ref) => const ScanNetworkProbes());

/// Discovers devices in stages, cheapest first: multicast announcement and
/// favorite probes right away, http-based discovery on the subnets only when
/// nothing was confirmed within 1 second.
class StartSmartScan extends AsyncGlobalAction {
  /// Maximum number of interfaces to scan.
  /// If there are more interfaces, the first ones will be used or the user needs to select one.
  static const maxInterfaces = 3;

  @override
  Future<void> reduce() async {
    final favorites = ref.read(favoritesProvider);
    final settings = ref.read(settingsProvider);
    final networkInterfaces = ref.read(localIpProvider).localIps.take(maxInterfaces).toList();

    await Future.wait<void>([
      ref
          .redux(nearbyDevicesProvider)
          .dispatchAsync(
            StartStagedScan(
              favorites: favorites,
              interfaces: networkInterfaces,
              port: settings.port,
              https: settings.https,
              grace: const Duration(seconds: 1),
            ),
          ),
      _scanExtras(networkInterfaces),
    ]);
  }

  /// Scans what multicast cannot reach: the `extraSubnets`, the subnets of
  /// interfaces that cannot carry multicast, and peers (Tailscale CLI on
  /// desktop, entered `peerIps`) for /32 or tailnet links.
  Future<void> _scanExtras(List<String> localIps) async {
    final settings = ref.read(settingsProvider);
    final probes = ref.read(scanNetworkProbesProvider);

    rust_diag.Diagnostics? diagnostics;
    try {
      diagnostics = await probes.runDiagnostics(port: settings.port);
    } catch (e) {
      _logger.warning('Network diagnostics failed', e);
    }

    final plan = buildExtraScanPlan(
      localIps: localIps,
      extraSubnets: settings.extraSubnets,
      peerIps: settings.peerIps,
      diagnostics: diagnostics,
    );
    if (plan.invalidSubnets.isNotEmpty) {
      _logger.warning('Ignoring invalid extra subnets: ${plan.invalidSubnets}');
    }

    await Future.wait<void>([
      for (final seed in plan.subnetSeeds)
        ref.redux(nearbyDevicesProvider).dispatchAsync(StartLegacyScan(port: settings.port, localIp: seed, https: settings.https)),
      _probePeers(probes, plan.peerIps, settings.port, settings.https),
    ]);
  }

  Future<void> _probePeers(ScanNetworkProbes probes, List<String> peerIps, int port, bool https) async {
    final List<rust_diag.PeerProbeResult> results;
    try {
      results = await probes.probePeers(peerIps: peerIps, port: port, timeoutMs: peerProbeTimeoutMs);
    } catch (e) {
      _logger.warning('Peer probe failed', e);
      return;
    }
    final reachable = [
      for (final r in results)
        if (r.reachable) (r.ip, r.port),
    ];
    if (reachable.isEmpty) {
      return;
    }
    // Register the reachable peers through the regular channel probe so they
    // show up like any other nearby device.
    await ref
        .redux(nearbyDevicesProvider)
        .dispatchAsync(
          StartStagedScan(
            favorites: const [],
            peers: reachable,
            interfaces: const [],
            port: port,
            https: https,
            grace: Duration.zero,
          ),
        );
  }
}

/// HTTP based discovery on a fixed set of subnets.
class StartLegacySubnetScan extends AsyncGlobalAction {
  final List<String> subnets;

  StartLegacySubnetScan({
    required this.subnets,
  });

  @override
  Future<void> reduce() async {
    final settings = ref.read(settingsProvider);
    final port = settings.port;
    final https = settings.https;

    // send announcement in parallel
    ref.redux(nearbyDevicesProvider).dispatch(StartMulticastScan());

    await Future.wait<void>([
      for (final subnet in subnets) ref.redux(nearbyDevicesProvider).dispatchAsync(StartLegacyScan(port: port, localIp: subnet, https: https)),
    ]);
  }
}
