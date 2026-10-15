import 'dart:async';
import 'dart:io';

import 'package:localsend_app/util/network/local_ips.dart';
import 'package:test/test.dart';

/// QA r1 F1: Linux without a system D-Bus. network_info_plus throws, hangs or
/// leaks a SocketException; the advertised IPs must still come from getifaddrs.
void main() {
  Future<List<NamedAddresses>> lan() async => [
    (name: 'enp0s4', addresses: ['172.30.0.2', 'fe80::1']),
    (name: 'docker0', addresses: ['172.17.0.1']),
    (name: 'tailscale0', addresses: ['100.64.9.7']),
  ];
  Future<List<NamedAddresses>> empty() async => [];
  Future<List<NamedAddresses>> failing() async => throw const SocketException('no getifaddrs');

  Future<List<String>> resolve({
    List<InterfaceSource>? sources,
    WifiIpSource? wifiIp,
    List<String> bind = const [],
    List<String>? blacklist,
  }) => resolveLocalIps(
    interfaceSources: sources ?? [lan],
    wifiIp: wifiIp,
    whitelist: null,
    blacklist: blacklist,
    bindInterfaces: bind,
    timeout: const Duration(milliseconds: 100),
  );

  test('no wifi source (Linux): native IPv4 list, .1 last', () async {
    expect(await resolve(), ['172.30.0.2', '100.64.9.7', '172.17.0.1']);
  });

  test('wifi source throws a D-Bus SocketException: native list', () async {
    final ips = await resolve(
      wifiIp: () async => throw const SocketException('Connection failed', address: null, osError: OSError('No such file or directory', 2)),
    );
    expect(ips, ['172.30.0.2', '100.64.9.7', '172.17.0.1']);
  });

  test('wifi source leaks an error outside its future and never completes: native list', () async {
    final ips = await resolve(
      wifiIp: () {
        // Like the D-Bus signal stream: the error escapes to the zone.
        // ignore: discarded_futures
        Future<void>.error(const SocketException('/var/run/dbus/system_bus_socket'));
        return Completer<String?>().future;
      },
    );
    expect(ips, ['172.30.0.2', '100.64.9.7', '172.17.0.1']);
  });

  test('wifi source hangs: times out, native list', () async {
    final ips = await resolve(wifiIp: () => Completer<String?>().future);
    expect(ips, hasLength(3));
  });

  test('working wifi source is ranked first', () async {
    expect((await resolve(wifiIp: () async => '100.64.9.7')).first, '100.64.9.7');
  });

  test('failing or empty first source falls back to the next (Rust core list)', () async {
    expect(await resolve(sources: [failing, empty, lan]), hasLength(3));
  });

  test('bindInterfaces scoping is kept, and drops a wifi IP outside the pick', () async {
    expect(await resolve(bind: ['tailscale0'], wifiIp: () async => '172.30.0.2'), ['100.64.9.7']);
    expect(await resolve(bind: ['gone0']), hasLength(3));
  });

  test('blacklist still applies', () async {
    expect(await resolve(blacklist: ['172.17.0.1']), ['172.30.0.2', '100.64.9.7']);
  });

  test('real getifaddrs with no system D-Bus', () async {
    // Run with DBUS_SYSTEM_BUS_ADDRESS=unix:path=/nonexistent (see PR): the
    // dart:io source must not touch D-Bus.
    final ips = await resolveLocalIps(
      interfaceSources: [dartIoInterfaces],
      wifiIp: null,
      whitelist: null,
      blacklist: null,
      bindInterfaces: const [],
    );
    final hasNonLoopback = (await NetworkInterface.list()).any((i) => i.addresses.any((a) => a.type == InternetAddressType.IPv4));
    if (hasNonLoopback) {
      expect(ips, isNotEmpty);
    }
  }, testOn: 'linux');

  test('dart:io empty, fallback only loopback/link-local: no address (QR disabled)', () async {
    Future<List<NamedAddresses>> onlyLo() async => [
      (name: 'lo', addresses: ['127.0.0.1', '::1']),
      (name: 'eth0', addresses: ['169.254.10.20']),
    ];
    expect(await resolve(sources: [empty, onlyLo]), isEmpty);
  });

  test('veth/docker/br- interfaces rank last', () async {
    Future<List<NamedAddresses>> withBridges() async => [
      (name: 'veth1a2b', addresses: ['10.200.0.5']),
      (name: 'br-0f1e', addresses: ['172.18.0.1']),
      (name: 'docker0', addresses: ['172.17.0.2']),
      (name: 'wlan0', addresses: ['192.168.1.1']),
      (name: 'eth0', addresses: ['192.168.1.20']),
    ];
    final ips = await resolve(sources: [withBridges]);
    expect(ips.take(2), ['192.168.1.20', '192.168.1.1']);
    expect(ips.skip(2).toSet(), {'10.200.0.5', '172.18.0.1', '172.17.0.2'});
  });
}
