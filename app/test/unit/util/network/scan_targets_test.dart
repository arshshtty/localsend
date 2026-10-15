import 'package:localsend_app/util/network/scan_targets.dart';
import 'package:localsend_isolates/rust/api/diagnostics.dart';
import 'package:test/test.dart';

InterfaceDiag _iface(String name, List<String> addresses, {bool up = true, bool multicast = true, bool loopback = false}) => InterfaceDiag(
  name: name,
  index: 1,
  addresses: addresses,
  up: up,
  loopback: loopback,
  multicastCapable: multicast,
  joinV4: const JoinResult.notAttempted(),
  joinV6: const JoinResult.notAttempted(),
);

Diagnostics _diag(List<InterfaceDiag> interfaces) => Diagnostics(
  interfaces: interfaces,
  tcpPort: const PortStatus.free(),
  udpPort: const PortStatus.free(),
  isStub: false,
);

void main() {
  group('parseExtraSubnet', () {
    test('accepts /24 CIDR and a.b.c.*', () {
      expect(parseExtraSubnet('10.0.5.0/24')!.subnetSeeds, ['10.0.5.0']);
      expect(parseExtraSubnet('10.0.5.77/24')!.subnetSeeds, ['10.0.5.0']);
      expect(parseExtraSubnet(' 192.168.8.* ')!.subnetSeeds, ['192.168.8.0']);
    });

    test('small prefixes become host probes', () {
      expect(parseExtraSubnet('10.0.0.7/32')!.hosts, ['10.0.0.7']);
      expect(parseExtraSubnet('10.0.0.7')!.hosts, ['10.0.0.7']);
      expect(parseExtraSubnet('10.0.0.4/30')!.hosts, ['10.0.0.5', '10.0.0.6']);
      expect(parseExtraSubnet('10.0.0.128/25')!.hosts, hasLength(126));
    });

    test('rejects invalid and too large (> /24) entries', () {
      for (final bad in ['', 'abc', '10.0.0.0/23', '10.0.0.0/16', '10.0.0.0/33', '10.0.0.0/x', '10.0.0/24', '::1/128', '1.2.3.4/24/1', '10.*']) {
        expect(parseExtraSubnet(bad), isNull, reason: bad);
      }
    });
  });

  test('isTailnetAddress', () {
    expect(isTailnetAddress('100.64.0.5'), isTrue);
    expect(isTailnetAddress('100.127.255.1'), isTrue);
    expect(isTailnetAddress('100.128.0.1'), isFalse);
    expect(isTailnetAddress('fd7a:115c:a1e0::1'), isTrue);
    expect(isTailnetAddress('192.168.1.2'), isFalse);
  });

  test('non-multicast interfaces are scanned, tailnet ones are left to peer probes', () {
    final seeds = nonMulticastSubnetSeeds(
      _diag([
        _iface('eth0', ['192.168.1.2']),
        _iface('wg0', ['10.9.0.2', 'fe80::1'], multicast: false),
        _iface('tailscale0', ['100.64.0.5'], multicast: false),
        _iface('down0', ['10.8.0.2'], multicast: false, up: false),
        _iface('lo', ['127.0.0.1'], multicast: false, loopback: true),
      ]),
    );
    expect(seeds, ['10.9.0.2']);
  });

  group('buildExtraScanPlan', () {
    test('defaults add nothing', () {
      final plan = buildExtraScanPlan(localIps: ['192.168.1.2'], extraSubnets: [], peerIps: []);
      expect(plan.subnetSeeds, isEmpty);
      expect(plan.peerIps, isEmpty);
      expect(plan.invalidSubnets, isEmpty);
    });

    test('combines extra subnets, non-multicast subnets and peer IPs without duplicates', () {
      final plan = buildExtraScanPlan(
        localIps: ['192.168.1.2'],
        extraSubnets: ['192.168.1.0/24', '10.0.5.0/24', '10.0.5.*', '10.1.0.9/32', '10.0.0.0/16'],
        peerIps: ['100.64.0.9', 'not-an-ip', '10.1.0.9'],
        diagnostics: _diag([
          _iface('wg0', ['10.9.0.2'], multicast: false),
          _iface('tailscale0', ['100.64.0.5'], multicast: false),
        ]),
      );
      expect(plan.subnetSeeds, ['10.0.5.0', '10.9.0.2']);
      expect(plan.peerIps.toSet(), {'100.64.0.9', '10.1.0.9'});
      expect(plan.invalidSubnets, ['10.0.0.0/16']);
    });

    test('acceptance (no CLI): an IP entered once is probed on every later scan', () {
      for (var scan = 0; scan < 3; scan++) {
        final plan = buildExtraScanPlan(localIps: ['192.168.1.2'], extraSubnets: [], peerIps: ['100.64.0.9']);
        expect(plan.peerIps, ['100.64.0.9']);
      }
    });
  });
}
