import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart';
import 'package:localsend_app/util/native/platform_check.dart';
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

  /// Cheap interface list (no joins, no port probes).
  Future<List<rust_diag.InterfaceDiag>> listInterfaces() => rust_diag.listInterfaces();

  Future<List<rust_diag.PeerProbeResult>> probePeers({required List<String> peerIps, required int port, required int timeoutMs}) =>
      rust_diag.probePeers(peerIps: peerIps, port: port, timeoutMs: timeoutMs);

  Future<List<rust_diag.PeerProbeResult>> probeTailscalePeers({required int port, required int timeoutMs}) =>
      rust_diag.probeTailscalePeers(port: port, timeoutMs: timeoutMs);
}

final scanNetworkProbesProvider = Provider<ScanNetworkProbes>((ref) => const ScanNetworkProbes());

/// Scans what multicast cannot reach, on top of the regular staged scan:
/// - the valid `extraSubnets` (only when the list is non-empty);
/// - the subnets of picked `bindInterfaces` that cannot carry multicast;
/// - the entered `peerIps` (max 32) and hosts of small extra subnets;
/// - Tailscale CLI peers, only when a `tailscale*` interface is picked.
///
/// With default settings (all three lists empty) nothing is called, so the
/// smart scan behaves exactly like before.
Future<ExtraScanPlan> runSmartScanExtras({
  required ScanNetworkProbes probes,
  required List<String> localIps,
  required List<String> bindInterfaces,
  required List<String> extraSubnets,
  required List<String> peerIps,
  required int port,
  required Future<void> Function(String seed) scanSubnet,
  required Future<void> Function(List<(String, int)> peers) registerPeers,
}) async {
  var plan = buildExtraScanPlan(localIps: localIps, bindInterfaces: bindInterfaces, extraSubnets: extraSubnets, peerIps: peerIps);
  if (plan.isEmpty) {
    return plan;
  }
  if (plan.invalidSubnets.isNotEmpty) {
    _logger.warning('Ignoring invalid or over-cap extra subnets: ${plan.invalidSubnets}');
  }
  if (plan.needsInterfaces) {
    try {
      final interfaces = await probes.listInterfaces();
      plan = buildExtraScanPlan(
        localIps: localIps,
        bindInterfaces: bindInterfaces,
        extraSubnets: extraSubnets,
        peerIps: peerIps,
        interfaces: interfaces,
      );
    } catch (e) {
      _logger.warning('Listing network interfaces failed', e);
    }
  }

  Future<void> probe(Future<List<rust_diag.PeerProbeResult>> Function() run) async {
    final List<rust_diag.PeerProbeResult> results;
    try {
      results = await run();
    } catch (e) {
      _logger.warning('Peer probe failed', e);
      return;
    }
    final reachable = [
      for (final r in results)
        if (r.reachable) (r.ip, r.port),
    ];
    if (reachable.isNotEmpty) {
      await registerPeers(reachable);
    }
  }

  await Future.wait<void>([
    for (final seed in plan.subnetSeeds) scanSubnet(seed),
    if (plan.peerIps.isNotEmpty) probe(() => probes.probePeers(peerIps: plan.peerIps, port: port, timeoutMs: peerProbeTimeoutMs)),
    if (plan.tailnet) probe(() => probes.probeTailscalePeers(port: port, timeoutMs: peerProbeTimeoutMs)),
  ]);
  return plan;
}

/// Discovers devices in stages, cheapest first: multicast announcement and
/// favorite probes right away, http-based discovery on the subnets only when
/// nothing was confirmed within 1 second.
class StartSmartScan extends AsyncGlobalAction {
  /// Maximum number of interfaces to scan.
  /// If there are more interfaces, the first ones will be used or the user needs to select one.
  static const maxInterfaces = 3;

  @override
  Future<void> reduce() async {
    if (checkPlatform([TargetPlatform.android])) {
      await withMulticastLockAndroid(_scan);
    } else {
      await _scan();
    }
  }

  Future<void> _scan() async {
    // Advertised addresses and scanned subnets follow `bindInterfaces`, so
    // they are recomputed on every scan instead of once at startup.
    await ref.redux(localIpProvider).dispatchAsync(FetchLocalIpAction());
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

  Future<void> _scanExtras(List<String> localIps) async {
    final settings = ref.read(settingsProvider);
    await runSmartScanExtras(
      probes: ref.read(scanNetworkProbesProvider),
      localIps: localIps,
      bindInterfaces: settings.bindInterfaces,
      extraSubnets: settings.extraSubnets,
      peerIps: settings.peerIps,
      port: settings.port,
      scanSubnet: (seed) =>
          ref.redux(nearbyDevicesProvider).dispatchAsync(StartLegacyScan(port: settings.port, localIp: seed, https: settings.https)),
      // Register the reachable peers through the regular channel probe so
      // they show up like any other nearby device.
      registerPeers: (peers) => ref
          .redux(nearbyDevicesProvider)
          .dispatchAsync(
            StartStagedScan(
              favorites: const [],
              peers: peers,
              interfaces: const [],
              port: settings.port,
              https: settings.https,
              grace: Duration.zero,
            ),
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
