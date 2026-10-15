import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/rust/api/diagnostics.dart' show StartError;
import 'package:refena_flutter/refena_flutter.dart';

/// The typed reason multicast discovery could not start (e.g.
/// `StartError.portInUse` or `StartError.noInterface`), or `null` while
/// multicast runs. Updated on every discovery (re)start by
/// [StartMulticastStatusListener].
final multicastStartErrorProvider = StateProvider<StartError?>((ref) => null);

/// Mirrors the discovery isolate's multicast start error into
/// [multicastStartErrorProvider]. Runs for the lifetime of the app.
class StartMulticastStatusListener extends AsyncGlobalAction {
  @override
  Future<void> reduce() async {
    final stream = ref.redux(parentIsolateProvider).dispatchTakeResult(IsolateDiscoveryMulticastStatusAction());
    await for (final error in stream) {
      ref.notifier(multicastStartErrorProvider).setState((_) => error);
    }
  }
}
