import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/model/send_mode.dart';
import 'package:localsend_app/model/state/network_state.dart';
import 'package:localsend_app/model/state/settings_state.dart';
import 'package:localsend_app/pages/troubleshoot_page.dart';
import 'package:localsend_app/provider/diagnostics_provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/widget/dialogs/address_input_dialog.dart';
import 'package:localsend_app/widget/dialogs/qr_dialog.dart';
import 'package:localsend_app/widget/troubleshoot/network_diagnostics_section.dart';
import 'package:localsend_isolates/rust/api/diagnostics.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';

import '../mocks.mocks.dart';

const _state = SettingsState(
  showToken: '',
  alias: 'Test',
  theme: ThemeMode.light,
  colorMode: ColorMode.system,
  customColor: Colors.blue,
  locale: null,
  port: 53317,
  networkWhitelist: null,
  networkBlacklist: null,
  multicastGroup: '224.0.0.167',
  destination: null,
  saveToGallery: false,
  saveToHistory: false,
  quickSave: false,
  quickSaveFromFavorites: false,
  receivePin: null,
  autoFinish: false,
  minimizeToTray: false,
  https: true,
  sendMode: SendMode.single,
  saveWindowPlacement: false,
  alwaysOnTop: false,
  enableAnimations: false,
  deviceType: null,
  deviceModel: null,
  shareViaLinkAutoAccept: false,
  receiveViaLinkAutoAccept: false,
  createChecksums: false,
  verifyChecksums: false,
  discoveryTimeout: 500,
  advancedSettings: false,
  bindInterfaces: [],
  extraSubnets: [],
  peerIps: [],
);

class _FakeSettings extends SettingsService {
  _FakeSettings(super.persistence);

  @override
  SettingsState init() => _state;
}

class _FakeLocalIp extends LocalIpService {
  _FakeLocalIp(super.settings);

  @override
  NetworkState init() => const NetworkState(localIps: ['192.168.1.20'], initialized: true);

  @override
  get initialAction => null;
}

late MockPersistenceService persistence;

Diagnostics _real(Diagnostics d) => Diagnostics(interfaces: d.interfaces, tcpPort: d.tcpPort, udpPort: d.udpPort, isStub: false);

Future<RefenaContainer> _pump(
  WidgetTester tester, {
  Diagnostics? diag,
  Object? error,
  StartError? startError,
  RunDiagnostics? run,
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  persistence = MockPersistenceService();
  final container = RefenaContainer(
    overrides: [
      settingsProvider.overrideWithNotifier((ref) => _FakeSettings(persistence)),
      localIpProvider.overrideWithNotifier((ref) => _FakeLocalIp(ref.notifier(settingsProvider))),
      runDiagnosticsProvider.overrideWithValue(run ?? (port) async => error != null ? throw error : diag ?? _real(await fakeRunDiagnostics(port))),
      ownPairingInfoProvider.overrideWithBuilder((ref) => const OwnPairingInfo(address: '192.168.1.20:53317', fingerprint: 'ABC123')),
      serverStartErrorProvider.overrideWithInitialState((ref) => startError),
    ],
  );
  await tester.pumpWidget(
    RefenaScope.withContainer(
      container: container,
      child: TranslationProvider(child: const MaterialApp(home: TroubleshootPage())),
    ),
  );
  if (run == null) await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('renders interfaces and labels ones without multicast', (tester) async {
    await _pump(tester);
    expect(find.text('en0'), findsOneWidget);
    expect(find.text('tailscale0'), findsOneWidget);
    expect(find.text('192.168.1.20'), findsWidgets);
    expect(find.text('Multicast ✓'), findsOneWidget);
    expect(find.byKey(const ValueKey('no-multicast-tailscale0')), findsOneWidget);
    expect(find.textContaining('VPN interface does not carry multicast'), findsOneWidget);
    expect(find.byKey(const ValueKey('port-in-use-banner')), findsNothing);
    expect(find.byKey(const ValueKey('sample-data-note')), findsNothing);
    expect(find.text('Tailscale'), findsOneWidget);
    // existing help stays
    expect(find.text(t.troubleshootPage.noDiscovery.symptom), findsOneWidget);
  });

  testWidgets('picking an interface dispatches SetBindInterfacesAction', (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('iface-tailscale0')));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).bindInterfaces, ['tailscale0']);
    verify(persistence.setBindInterfaces(['tailscale0'])).called(1);
    await tester.tap(find.byKey(const ValueKey('iface-tailscale0')));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).bindInterfaces, isEmpty);
  });

  testWidgets('stub data is labelled and cannot be selected', (tester) async {
    final c = await _pump(tester, diag: await fakeRunDiagnostics(53317));
    expect(find.byKey(const ValueKey('sample-data-note')), findsOneWidget);
    expect(find.byKey(const ValueKey('table-sample-note')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('iface-tailscale0')));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).bindInterfaces, isEmpty);
    verifyNever(persistence.setBindInterfaces(any));
  });

  testWidgets('bridge error is shown, not replaced by sample data', (tester) async {
    await _pump(tester, error: Exception('bridge down'));
    expect(find.byKey(const ValueKey('diagnostics-error')), findsOneWidget);
    expect(find.textContaining('bridge down'), findsOneWidget);
    expect(find.text('tailscale0'), findsNothing);
  });

  testWidgets('no banner when port is free', (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('port-in-use-banner')), findsNothing);
    expect(find.byKey(const ValueKey('port-held-by-this-app')), findsNothing);
  });

  testWidgets('diagnostics timeout shows error with Try again, no sample data', (tester) async {
    await _pump(tester, run: (port) => Completer<Diagnostics>().future);
    await tester.pump(diagnosticsTimeout + const Duration(seconds: 1));
    await tester.pump();
    expect(find.byKey(const ValueKey('diagnostics-error')), findsOneWidget);
    expect(find.textContaining('took longer than'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('tailscale0'), findsNothing);
  });

  testWidgets('heldByThisApp is not a conflict', (tester) async {
    await _pump(
      tester,
      diag: const Diagnostics(interfaces: [], tcpPort: PortStatus.heldByThisApp(), udpPort: PortStatus.heldByThisApp(), isStub: false),
    );
    expect(find.byKey(const ValueKey('port-in-use-banner')), findsNothing);
    expect(find.byKey(const ValueKey('port-held-by-this-app')), findsOneWidget);
  });

  testWidgets('banner shows pid only, never the process name', (tester) async {
    await _pump(
      tester,
      diag: const Diagnostics(
        interfaces: [],
        tcpPort: PortStatus.inUse(pidHint: '1234 (secret-app)'),
        udpPort: PortStatus.free(),
        isStub: false,
      ),
    );
    expect(find.byKey(const ValueKey('port-in-use-banner')), findsOneWidget);
    expect(find.textContaining('1234'), findsOneWidget);
    expect(find.textContaining('secret-app'), findsNothing);
  });

  test('stripProcessName and addPeerIp', () {
    expect(stripProcessName('1234 (name)'), '1234');
    expect(stripProcessName('(name)'), isNull);
    expect(addPeerIp(['a'], 'b'), ['a', 'b']);
    expect(addPeerIp(['a', 'b'], 'a'), ['a', 'b']);
  });

  testWidgets('banner shows for server start error PortInUse', (tester) async {
    await _pump(tester, startError: const StartError.portInUse(port: 53318));
    expect(find.text('Port 53318 in use — change port or quit the other app'), findsOneWidget);
  });

  testWidgets('subnet editor accepts /26 and rejects larger ranges', (tester) async {
    final c = await _pump(tester);
    final field = find.descendant(of: find.byKey(const ValueKey('extra-subnets')), matching: find.byType(TextField));
    final add = find.descendant(of: find.byKey(const ValueKey('extra-subnets')), matching: find.text('Add'));
    for (final tooLarge in ['10.0.0.0/16', '10.0.5.0/24', '10.0.5.0/25', '10.0.6.*']) {
      await tester.enterText(field, tooLarge);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.textContaining('Range too large'), findsOneWidget, reason: tooLarge);
      expect(c.read(settingsProvider).extraSubnets, isEmpty);
    }
    await tester.enterText(field, '10.0.5.0/26');
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).extraSubnets, ['10.0.5.0/26']);
    await tester.enterText(field, '10.0.5.0/26');
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).extraSubnets, ['10.0.5.0/26']);
  });

  testWidgets('peer IPs field saves', (tester) async {
    final c = await _pump(tester);
    final field = find.descendant(of: find.byKey(const ValueKey('peer-ips')), matching: find.byType(TextField));
    await tester.enterText(field, 'nope');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).peerIps, isEmpty);
    await tester.enterText(field, '100.64.0.2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).peerIps, ['100.64.0.2']);
    verify(persistence.setPeerIps(['100.64.0.2'])).called(1);
    await tester.enterText(field, 'fd7a:115c:a1e0::1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).peerIps, ['100.64.0.2', 'fd7a:115c:a1e0::1']);
  });

  testWidgets('shows banner when port is in use', (tester) async {
    await _pump(
      tester,
      diag: const Diagnostics(interfaces: [], tcpPort: PortStatus.inUse(), udpPort: PortStatus.free(), isStub: false),
    );
    expect(find.byKey(const ValueKey('port-in-use-banner')), findsOneWidget);
    expect(find.text('Port 53317 in use — change port or quit the other app'), findsOneWidget);
    expect(find.byKey(const ValueKey('sample-data-note')), findsNothing);
  });

  testWidgets('Send by IP:port opens the address dialog in IP mode', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Send by IP:port'));
    await tester.pumpAndSettle();
    expect(find.byType(AddressInputDialog), findsOneWidget);
    expect(find.text('IP: '), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '1.2.3.4:abc');
    await tester.tap(find.text(t.general.confirm));
    await tester.pumpAndSettle();
    expect(find.text('Port must be a number from 1 to 65535'), findsNothing); // shown via error icon
    expect(find.text(t.general.error), findsOneWidget);
  });

  testWidgets('pairing code opens the QR dialog with address and fingerprint', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Show pairing code'));
    await tester.pumpAndSettle();
    final qr = tester.widget<QrDialog>(find.byType(QrDialog));
    expect(qr.data, '192.168.1.20:53317?fingerprint=ABC123');
    expect(find.textContaining('Show this code to the other device'), findsOneWidget);
  });

  testWidgets('remember-address prompt is opt-in', (tester) async {
    expect(await _openRemember(tester, 'Not now'), isFalse);
    expect(await _openRemember(tester, 'Remember'), isTrue);
  });
}

Future<bool?> _openRemember(WidgetTester tester, String button) async {
  bool? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showDialog<bool>(
            context: context,
            builder: (_) => const RememberPeerDialog(ip: '100.64.0.9'),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.textContaining('100.64.0.9'), findsOneWidget);
  await tester.tap(find.text(button));
  await tester.pumpAndSettle();
  return result;
}
