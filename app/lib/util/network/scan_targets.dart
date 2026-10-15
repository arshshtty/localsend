import 'dart:io' show InternetAddress, InternetAddressType;

import 'package:localsend_isolates/rust/api/diagnostics.dart';

/// Largest subnet (smallest prefix length) accepted per `extraSubnets` entry.
/// The design note caps an entry at a /24 for the MVP.
const minExtraSubnetPrefix = 24;

/// At most this many `extraSubnets` entries are used per scan.
const maxExtraSubnetEntries = 16;

/// At most this many hosts (a /24 counts as 256) are scanned from
/// `extraSubnets` per scan.
const maxExtraSubnetHosts = 4096;

/// At most this many entered `peerIps` are probed per scan.
const maxPeerIpsPerScan = 32;

/// Maximum IPs sent to `probePeers` in one scan (entered peer IPs plus hosts
/// of /25-/32 extra subnets). Matches `MAX_PROBE_TARGETS` in Rust.
const maxDirectProbeTargets = 96;

/// A validated `extraSubnets` entry.
class ExtraSubnet {
  /// An address inside each /24 to scan (the scan covers the whole /24).
  final List<String> subnetSeeds;

  /// Single hosts to probe directly (prefixes longer than /24).
  final List<String> hosts;

  const ExtraSubnet({required this.subnetSeeds, required this.hosts});
}

/// Parses an `extraSubnets` entry: IPv4 CIDR (`10.0.5.0/24`, `10.0.5.7/32`),
/// `a.b.c.*`, or a bare IPv4 address (= /32).
/// Returns `null` for invalid entries and for anything larger than a /24.
ExtraSubnet? parseExtraSubnet(String input) {
  final entry = input.trim();
  if (entry.isEmpty) {
    return null;
  }
  if (entry.endsWith('.*')) {
    final base = _parseIpv4('${entry.substring(0, entry.length - 2)}.0');
    return base == null ? null : ExtraSubnet(subnetSeeds: [_fmt(base)], hosts: const []);
  }

  final parts = entry.split('/');
  if (parts.length > 2) {
    return null;
  }
  final ip = _parseIpv4(parts[0]);
  if (ip == null) {
    return null;
  }
  final prefix = parts.length == 2 ? int.tryParse(parts[1]) : 32;
  if (prefix == null || prefix < minExtraSubnetPrefix || prefix > 32) {
    return null;
  }
  if (prefix == 24) {
    return ExtraSubnet(subnetSeeds: [_fmt(ip & 0xFFFFFF00)], hosts: const []);
  }
  final mask = prefix == 32 ? 0xFFFFFFFF : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  final network = ip & mask;
  final size = 1 << (32 - prefix);
  if (size <= 2) {
    // /31 and /32: every address is a host.
    return ExtraSubnet(subnetSeeds: const [], hosts: [for (var i = 0; i < size; i++) _fmt(network + i)]);
  }
  // Skip network and broadcast addresses.
  return ExtraSubnet(subnetSeeds: const [], hosts: [for (var i = 1; i < size - 1; i++) _fmt(network + i)]);
}

/// Whether [ip] is a Tailscale (CGNAT 100.64.0.0/10 or `fd7a:115c:a1e0::/48`) address.
bool isTailnetAddress(String ip) {
  final v4 = _parseIpv4(ip);
  if (v4 != null) {
    return (v4 & 0xFFC00000) == 0x64400000;
  }
  return ip.toLowerCase().startsWith('fd7a:115c:a1e0:');
}

/// Whether [bindInterfaces] contains a Tailscale interface (`tailscale*`).
/// Only then may the scan run the Tailscale CLI and probe tailnet peers.
bool wantsTailnet(List<String> bindInterfaces) => bindInterfaces.any((name) => name.startsWith('tailscale'));

/// IPv4 addresses of the up, non-loopback interfaces in [bindInterfaces]
/// that cannot carry multicast, whose /24 must be scanned instead. Tailnet
/// addresses are excluded: their peers come from the peer probes.
List<String> nonMulticastSubnetSeeds(List<InterfaceDiag> interfaces, List<String> bindInterfaces) {
  return [
    for (final iface in interfaces)
      if (bindInterfaces.contains(iface.name) && iface.up && !iface.loopback && !iface.multicastCapable)
        for (final address in iface.addresses)
          if (_parseIpv4(address) != null && !isTailnetAddress(address)) address,
  ];
}

/// Everything the smart scan does on top of the local-subnet staged scan.
class ExtraScanPlan {
  /// Seeds whose /24 is scanned unconditionally.
  final List<String> subnetSeeds;

  /// IPs probed directly via `probePeers`: entered peer IPs (max
  /// [maxPeerIpsPerScan]) and hosts of /25-/32 extra subnets.
  final List<String> peerIps;

  /// Whether the Tailscale CLI peers are probed (a `tailscale*` interface is picked).
  final bool tailnet;

  /// Whether the cheap interface list is needed (some interfaces are picked).
  final bool needsInterfaces;

  /// `extraSubnets` entries that were rejected or over the caps.
  final List<String> invalidSubnets;

  const ExtraScanPlan({
    required this.subnetSeeds,
    required this.peerIps,
    required this.tailnet,
    required this.needsInterfaces,
    required this.invalidSubnets,
  });

  /// Nothing to do beyond the regular scan (default settings).
  bool get isEmpty => subnetSeeds.isEmpty && peerIps.isEmpty && !tailnet && !needsInterfaces;
}

/// Combines the settings (and, when interfaces are picked, the interface
/// list) into the extra scan targets. With empty [bindInterfaces],
/// [extraSubnets] and [peerIps] the plan is empty, so the scan behaves
/// exactly like before. Subnets already covered by [localIps] are not
/// scanned twice.
ExtraScanPlan buildExtraScanPlan({
  required List<String> localIps,
  required List<String> bindInterfaces,
  required List<String> extraSubnets,
  required List<String> peerIps,
  List<InterfaceDiag>? interfaces,
}) {
  final covered = localIps.map(_subnetKey).whereType<String>().toSet();
  final seeds = <String>[];
  final hosts = <String>{
    ...peerIps.map((e) => e.trim()).where((e) => InternetAddress.tryParse(e) != null).take(maxPeerIpsPerScan),
  };
  final invalid = <String>[];

  void addSeed(String seed) {
    final key = _subnetKey(seed);
    if (key != null && covered.add(key)) {
      seeds.add(seed);
    }
  }

  var budget = maxExtraSubnetHosts;
  for (final (i, entry) in extraSubnets.indexed) {
    final parsed = i < maxExtraSubnetEntries ? parseExtraSubnet(entry) : null;
    final cost = parsed == null ? 0 : parsed.subnetSeeds.length * 256 + parsed.hosts.length;
    final newHosts = parsed?.hosts.where((h) => !hosts.contains(h)).length ?? 0;
    if (parsed == null || cost > budget || hosts.length + newHosts > maxDirectProbeTargets) {
      invalid.add(entry);
      continue;
    }
    budget -= cost;
    parsed.subnetSeeds.forEach(addSeed);
    hosts.addAll(parsed.hosts);
  }
  if (interfaces != null) {
    nonMulticastSubnetSeeds(interfaces, bindInterfaces).forEach(addSeed);
  }
  return ExtraScanPlan(
    subnetSeeds: seeds,
    peerIps: hosts.toList(),
    tailnet: wantsTailnet(bindInterfaces),
    needsInterfaces: bindInterfaces.isNotEmpty,
    invalidSubnets: invalid,
  );
}

String? _subnetKey(String ip) {
  final v4 = _parseIpv4(ip);
  return v4 == null ? null : _fmt(v4 & 0xFFFFFF00);
}

int? _parseIpv4(String s) {
  final address = InternetAddress.tryParse(s);
  if (address == null || address.type != InternetAddressType.IPv4) {
    return null;
  }
  final b = address.rawAddress;
  return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
}

String _fmt(int v) => '${(v >> 24) & 0xFF}.${(v >> 16) & 0xFF}.${(v >> 8) & 0xFF}.${v & 0xFF}';
