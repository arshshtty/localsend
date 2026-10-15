import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Saves the `bindInterfaces` setting (interface names, empty = all) and
/// applies it: discovery restarts through the settings sync, and a running
/// server is restarted so it listens only on the chosen interfaces.
///
/// Use this instead of calling `SettingsService.setBindInterfaces` directly,
/// which would leave a running server on the old interfaces.
class SetBindInterfacesAction extends AsyncGlobalAction {
  final List<String> interfaces;

  SetBindInterfacesAction(this.interfaces);

  @override
  Future<void> reduce() async {
    await ref.notifier(settingsProvider).setBindInterfaces(interfaces);
    if (ref.read(serverProvider) != null) {
      await ref.notifier(serverProvider).restartServerFromSettings();
    }
  }
}
