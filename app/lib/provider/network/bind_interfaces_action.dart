import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Saves the `bindInterfaces` setting (interface names, empty = all) and
/// applies it without touching the HTTP server, which always listens on all
/// interfaces (0.0.0.0 / [::]):
/// - discovery (multicast joins and announces) restarts through the settings
///   sync, debounced by [bindInterfacesDebounce];
/// - the advertised addresses (receive tab, QR ip:port, scanned subnets) are
///   refreshed right away.
///
/// Safe to call on every checkbox toggle: it never stops a transfer.
class SetBindInterfacesAction extends AsyncGlobalAction {
  final List<String> interfaces;

  SetBindInterfacesAction(this.interfaces);

  @override
  Future<void> reduce() async {
    await ref.notifier(settingsProvider).setBindInterfaces(interfaces);
    await ref.redux(localIpProvider).dispatchAsync(FetchLocalIpAction());
  }
}
