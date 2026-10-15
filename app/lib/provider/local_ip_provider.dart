import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:localsend_app/model/state/network_state.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/network/local_ips.dart';
import 'package:localsend_isolates/rust/api/diagnostics.dart' as rust_diag;
import 'package:logging/logging.dart';
import 'package:network_info_plus/network_info_plus.dart' as plugin;
import 'package:refena_flutter/refena_flutter.dart';

export 'package:localsend_app/util/network/local_ips.dart' show filterBindInterfaces, rankIpAddresses;

final _logger = Logger('NetworkInfo');

final localIpProvider = ReduxProvider<LocalIpService, NetworkState>((ref) {
  return LocalIpService(
    ref.notifier(settingsProvider),
  );
});

StreamSubscription? _subscription;

class LocalIpService extends ReduxNotifier<NetworkState> {
  final SettingsService _settingsService;

  LocalIpService(this._settingsService);

  @override
  NetworkState init() {
    return const NetworkState(
      localIps: [],
      initialized: false,
    );
  }

  @override
  get initialAction => InitLocalIpAction();
}

/// Fetches the local IP address and registers a listener to update the IP address
class InitLocalIpAction extends ReduxAction<LocalIpService, NetworkState> {
  @override
  NetworkState reduce() {
    if (!kIsWeb) {
      // ignore: discarded_futures
      _subscription?.cancel();

      if (checkPlatform([TargetPlatform.windows])) {
        // https://github.com/localsend/localsend/issues/12
        // https://github.com/localsend/localsend/issues/78
      } else {
        // connectivity_plus uses NetworkManager over D-Bus on Linux; without a
        // system bus it fails when listening. Keep that from crashing into the
        // zone: addresses are still refreshed on every scan.
        runZonedGuarded(
          () {
            _subscription = Connectivity().onConnectivityChanged.listen(
              (_) async {
                await dispatchAsync(FetchLocalIpAction());
              },
              onError: (Object e) => _logger.warning('Connectivity listener failed', e),
            );
          },
          (e, _) => _logger.warning('Connectivity listener failed', e),
        );
      }
    }

    return state;
  }

  @override
  void after() {
    // ignore: discarded_futures
    dispatchAsync(FetchLocalIpAction());
  }
}

class FetchLocalIpAction extends AsyncReduxAction<LocalIpService, NetworkState> {
  @override
  Future<NetworkState> reduce() async {
    return NetworkState(
      localIps: await _getIp(
        whitelist: notifier._settingsService.state.networkWhitelist,
        blacklist: notifier._settingsService.state.networkBlacklist,
        bindInterfaces: notifier._settingsService.state.bindInterfaces,
      ),
      initialized: true,
    );
  }
}

Future<List<String>> _getIp({
  required List<String>? whitelist,
  required List<String>? blacklist,
  List<String> bindInterfaces = const [],
}) async {
  final addresses = await resolveLocalIps(
    interfaceSources: [dartIoInterfaces, _rustInterfaces],
    // On Linux network_info_plus needs NetworkManager over the system D-Bus,
    // which is missing on many setups (containers, minimal desktops) and then
    // throws or hangs. getifaddrs already has every address, so skip it.
    wifiIp: checkPlatform([TargetPlatform.linux]) ? null : () => plugin.NetworkInfo().getWifiIP(),
    whitelist: whitelist,
    blacklist: blacklist,
    bindInterfaces: bindInterfaces,
  );
  _logger.info('Network state: $addresses');
  return addresses;
}

/// The Rust core's getifaddrs list (no multicast joins), used if `dart:io`
/// returns nothing.
Future<List<NamedAddresses>> _rustInterfaces() async {
  return [
    for (final i in await rust_diag.listInterfaces())
      if (!i.loopback) (name: i.name, addresses: i.addresses),
  ];
}
