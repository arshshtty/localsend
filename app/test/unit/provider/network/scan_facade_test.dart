import 'package:localsend_app/provider/network/scan_facade.dart';
import 'package:localsend_isolates/rust/api/diagnostics.dart';
import 'package:test/test.dart';

class FakeProbes extends ScanNetworkProbes {
  int listCalls = 0;
  int tailscaleCalls = 0;
  final List<List<String>> probeCalls = [];
  final List<InterfaceDiag> interfaces;
  final List<PeerProbeResult> tailnet;

  FakeProbes({this.interfaces = const [], this.tailnet = const []});

  @override
  Future<List<InterfaceDiag>> listInterfaces() async {
    listCalls++;
    return interfaces;
  }

  @override
  Future<List<PeerProbeResult>> probePeers({required List<String> peerIps, required int port, required int timeoutMs}) async {
    probeCalls.add(peerIps);
    return [
      for (final ip in peerIps)
        PeerProbeResult(ip: ip, port: port, source: PeerSource.userEntered, reachable: true, alias: 'a', fingerprint: 'f', error: null),
    ];
  }

  @override
  Future<List<PeerProbeResult>> probeTailscalePeers({required int port, required int timeoutMs}) async {
    tailscaleCalls++;
    return tailnet;
  }
}

class Recorder {
  final seeds = <String>[];
  final registered = <List<(String, int)>>[];
}

Future<Recorder> run(
  FakeProbes probes, {
  List<String> bindInterfaces = const [],
  List<String> extraSubnets = const [],
  List<String> peerIps = const [],
}) async {
  final r = Recorder();
  await runSmartScanExtras(
    probes: probes,
    localIps: ['192.168.1.2'],
    bindInterfaces: bindInterfaces,
    extraSubnets: extraSubnets,
    peerIps: peerIps,
    port: 53317,
    scanSubnet: (seed) async => r.seeds.add(seed),
    registerPeers: (peers) async => r.registered.add(peers),
  );
  return r;
}

void main() {
  test('default settings: the smart scan does nothing extra (same as main)', () async {
    final probes = FakeProbes();
    final r = await run(probes);
    expect(probes.listCalls, 0);
    expect(probes.tailscaleCalls, 0);
    expect(probes.probeCalls, isEmpty);
    expect(r.seeds, isEmpty);
    expect(r.registered, isEmpty);
  });

  test('the Tailscale CLI is not invoked without a tailscale interface, even with peer IPs', () async {
    final probes = FakeProbes();
    final r = await run(probes, bindInterfaces: ['eth0'], peerIps: ['100.64.0.9']);
    expect(probes.tailscaleCalls, 0);
    expect(probes.probeCalls, [
      ['100.64.0.9'],
    ]);
    expect(r.registered, [
      [('100.64.0.9', 53317)],
    ]);
  });

  test('acceptance (CLI): picking tailscale0 finds the tailnet peer without an entered IP', () async {
    final probes = FakeProbes(
      tailnet: [
        const PeerProbeResult(
          ip: '100.64.0.7',
          port: 53317,
          source: PeerSource.tailscaleCli,
          reachable: true,
          alias: 'Desktop',
          fingerprint: 'f',
          error: null,
        ),
        const PeerProbeResult(
          ip: '100.64.0.8',
          port: 53317,
          source: PeerSource.tailscaleCli,
          reachable: false,
          alias: null,
          fingerprint: null,
          error: 'timeout',
        ),
      ],
    );
    final r = await run(probes, bindInterfaces: ['tailscale0']);
    expect(probes.tailscaleCalls, 1);
    expect(probes.probeCalls, isEmpty);
    expect(r.registered, [
      [('100.64.0.7', 53317)],
    ]);
  });

  test('extra subnets are scanned only when set', () async {
    final probes = FakeProbes();
    final r = await run(probes, extraSubnets: ['10.0.5.0/26']);
    expect(r.seeds, isEmpty);
    expect(probes.probeCalls.single, hasLength(62));
    expect(probes.listCalls, 0);
    expect(probes.tailscaleCalls, 0);
  });

  test('picked non-multicast interfaces use the cheap interface list', () async {
    final probes = FakeProbes(
      interfaces: [
        const InterfaceDiag(
          name: 'wg0',
          index: 3,
          addresses: ['10.9.0.2'],
          up: true,
          loopback: false,
          multicastCapable: false,
          joinV4: JoinResult.notAttempted(),
          joinV6: JoinResult.notAttempted(),
        ),
      ],
    );
    final r = await run(probes, bindInterfaces: ['wg0']);
    expect(probes.listCalls, 1);
    expect(r.seeds, ['10.9.0.2']);
  });
}
