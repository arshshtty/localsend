import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:localsend_isolates/util/network_interfaces.dart';
import 'package:logging/logging.dart';

final _logger = Logger('LocalIps');

/// An interface name with its addresses (IPv4 dotted or IPv6).
typedef NamedAddresses = ({String name, List<String> addresses});

/// Lists the local interfaces. Implementations must not need D-Bus or
/// NetworkManager (getifaddrs via `dart:io` or the Rust core).
typedef InterfaceSource = Future<List<NamedAddresses>> Function();

/// The Wi-Fi IP from a platform plugin (network_info_plus). May throw, hang
/// or leak errors into the zone (D-Bus missing on Linux).
typedef WifiIpSource = Future<String?> Function();

/// How long the Wi-Fi IP lookup may take before it is ignored.
const wifiIpTimeout = Duration(seconds: 2);

/// `dart:io` `NetworkInterface.list` (getifaddrs on Linux/macOS/Android).
Future<List<NamedAddresses>> dartIoInterfaces() async {
  return [
    for (final i in await NetworkInterface.list()) (name: i.name, addresses: i.addresses.map((a) => a.address).toList()),
  ];
}

/// The advertised local IPv4 addresses, best first.
///
/// [interfaceSources] are tried in order until one yields an address after
/// filtering, so a failing or empty source falls back to the next one.
/// [wifiIp] only ranks the result (the plugin IP is preferred); when it is
/// null, throws, leaks a zone error or times out, the native list is used
/// as is. With [bindInterfaces] set, only those interfaces are advertised
/// (all of them if none of the names exist).
Future<List<String>> resolveLocalIps({
  required List<InterfaceSource> interfaceSources,
  required WifiIpSource? wifiIp,
  required List<String>? whitelist,
  required List<String>? blacklist,
  required List<String> bindInterfaces,
  Duration timeout = wifiIpTimeout,
}) async {
  var native = <String>[];
  var narrowed = false;
  var virtualIps = <String>{};
  for (final (i, source) in interfaceSources.indexed) {
    final List<NamedAddresses> all;
    try {
      all = (await source())
          .where((e) => !isNetworkIgnoredRaw(networkWhitelist: whitelist, networkBlacklist: blacklist, interface: e.addresses))
          .toList();
    } catch (e) {
      _logger.warning('Interface source #$i failed', e);
      continue;
    }
    final chosen = filterBindInterfaces(all, bindInterfaces, (e) => e.name);
    // IPv4 only for now. Loopback and link-local never reach a peer (dart:io
    // already omits them; the Rust fallback does not).
    native = chosen.expand((e) => e.addresses).where(isAdvertisableIpv4).toSet().toList();
    virtualIps = {
      for (final e in chosen)
        if (isVirtualInterface(e.name)) ...e.addresses,
    };
    if (native.isNotEmpty) {
      narrowed = chosen.length < all.length;
      break;
    }
  }

  String? ip = wifiIp == null ? null : await guardedWifiIp(wifiIp, timeout);
  // The Wi-Fi IP is only kept if it belongs to a chosen interface.
  if (narrowed && ip != null && !native.contains(ip)) {
    ip = null;
  }
  return rankIpAddresses(native, ip, deprioritized: virtualIps);
}

/// IPv4, not loopback (127/8) and not link-local (169.254/16).
bool isAdvertisableIpv4(String ip) => !ip.contains(':') && !ip.startsWith('127.') && !ip.startsWith('169.254.');

/// Container/bridge interfaces (veth*, docker*, br-*) that are rarely the LAN.
bool isVirtualInterface(String name) => name.startsWith('veth') || name.startsWith('docker') || name.startsWith('br-');

/// Runs [source] in a guarded zone with a timeout. Returns null on any error,
/// including errors the plugin leaks outside the returned future.
Future<String?> guardedWifiIp(WifiIpSource source, Duration timeout) {
  final completer = Completer<String?>();
  // ignore: discarded_futures
  runZonedGuarded(
    () async {
      final value = await source();
      if (!completer.isCompleted) completer.complete(value);
    },
    (e, _) {
      _logger.warning('Failed to get wifi IP', e);
      if (!completer.isCompleted) completer.complete(null);
    },
  );
  return completer.future.timeout(
    timeout,
    onTimeout: () {
      _logger.warning('Wifi IP lookup timed out');
      return null;
    },
  );
}

/// Keeps the interfaces named in [bindInterfaces]. Empty [bindInterfaces]
/// means all interfaces; if none of the names exist (adapter removed), all
/// interfaces are kept as well and a warning is logged, matching Rust's
/// `resolve_bind_interfaces`.
List<T> filterBindInterfaces<T>(List<T> interfaces, List<String> bindInterfaces, String Function(T) name) {
  if (bindInterfaces.isEmpty) {
    return interfaces;
  }
  final chosen = interfaces.where((i) => bindInterfaces.contains(name(i))).toList();
  if (chosen.isEmpty) {
    _logger.warning('None of the bind interfaces $bindInterfaces exist, using all interfaces');
    return interfaces;
  }
  return chosen;
}

List<String> rankIpAddresses(List<String> nativeResult, String? thirdPartyResult, {Set<String> deprioritized = const {}}) {
  if (thirdPartyResult == null) {
    // only take the list
    return nativeResult._rankIpAddresses(null, deprioritized);
  } else if (nativeResult.isEmpty) {
    // only take the first IP from third party library
    return [thirdPartyResult];
  } else if (thirdPartyResult.endsWith('.1')) {
    // merge
    return {thirdPartyResult, ...nativeResult}.toList()._rankIpAddresses(null, deprioritized);
  } else {
    // merge but prefer result from third party library
    return {thirdPartyResult, ...nativeResult}.toList()._rankIpAddresses(thirdPartyResult, deprioritized);
  }
}

/// Sorts Ip addresses with first being the most likely primary local address
/// Currently,
/// - sorts ending with ".1" last
/// - primary is always first
/// - [deprioritized] (container/bridge interfaces) after everything else
extension ListIpExt on List<String> {
  List<String> _rankIpAddresses(String? primary, [Set<String> deprioritized = const {}]) {
    int score(String ip) => ip == primary ? 10 : (deprioritized.contains(ip) ? -1 : (ip.endsWith('.1') ? 0 : 1));
    return sorted((a, b) => score(b).compareTo(score(a)));
  }
}
