import 'dart:io';

final _octet = r'(0|[1-9]\d{0,2})';

List<int>? _parseOctets(List<String?> parts) {
  final values = parts.map((p) => int.parse(p!)).toList();
  return values.every((v) => v <= 255) ? values : null;
}

/// Validates an extra subnet entry: CIDR network address (`10.0.5.0/26`, prefix 26..32). `a.b.c.*` (256 addresses) is rejected: scans are capped at
/// 96 direct-probe targets, so the largest accepted range is /26 (64 addresses).
/// Returns a plain error message, or null if valid.
String? validateSubnet(String input) {
  final s = input.trim();
  if (s.isEmpty) return 'Enter a subnet, for example 192.168.5.0/26';
  final wildcard = RegExp('^$_octet\\.$_octet\\.$_octet\\.\\*\$').firstMatch(s);
  if (wildcard != null) {
    if (_parseOctets([wildcard.group(1), wildcard.group(2), wildcard.group(3)]) == null) return 'Each number must be between 0 and 255';
    return 'Range too large: use /26 or smaller, for example ${wildcard.group(1)}.${wildcard.group(2)}.${wildcard.group(3)}.0/26';
  }
  if (s.contains('*')) return 'Use a range like 192.168.5.0/26 (no *)';
  final cidr = RegExp('^$_octet\\.$_octet\\.$_octet\\.$_octet/(\\d{1,2})\$').firstMatch(s);
  if (cidr == null) return 'Use a range like 192.168.5.0/26 (no leading zeros)';
  final octets = _parseOctets([for (var i = 1; i <= 4; i++) cidr.group(i)]);
  if (octets == null) return 'Each number must be between 0 and 255';
  final prefix = int.parse(cidr.group(5)!);
  if (prefix > 32) return 'The number after / must be 32 or less';
  if (prefix < 26) {
    final net26 = octets[3] & 0xc0;
    return 'Range too large: use /26 or smaller (at most 64 addresses), for example ${octets[0]}.${octets[1]}.${octets[2]}.$net26/26';
  }
  final hostBits = 32 - prefix;
  final mask = hostBits == 0 ? 0 : (1 << hostBits) - 1;
  if (octets[3] & mask != 0) {
    final network = octets[3] & ~mask & 0xff;
    return 'Use the start of the range: ${octets[0]}.${octets[1]}.${octets[2]}.$network/$prefix';
  }
  return null;
}

/// Normalises a valid subnet for duplicate checks (`a.b.c.*` is never valid).
String normalizeSubnet(String input) => input.trim();

/// Validates a single IPv4/IPv6 address (IPv6 zone ids like `%eth0` allowed).
bool isValidIp(String input) {
  var s = input.trim();
  final zone = s.indexOf('%');
  if (zone > 0 && s.contains(':')) s = s.substring(0, zone);
  if (!s.contains(':') && !RegExp('^$_octet\\.$_octet\\.$_octet\\.$_octet\$').hasMatch(s)) return false;
  return InternetAddress.tryParse(s) != null;
}

/// Result of [parseHostPort]: either host (+ optional port) or an error.
class HostPort {
  final String host; // IPv6 without brackets
  final int? port;
  final String? error;

  const HostPort(this.host, this.port) : error = null;
  const HostPort.error(String this.error) : host = '', port = null;
}

/// Parses `host`, `host:port`, `[v6]` or `[v6]:port`. A bare IPv6 address has no port.
HostPort parseHostPort(String input) {
  final s = input.trim();
  final v6 = RegExp(r'^\[([^\]]+)\](?::(.*))?$').firstMatch(s);
  if (v6 != null) return _withPort(v6.group(1)!, v6.group(2));
  final colons = ':'.allMatches(s).length;
  if (colons == 1) {
    final i = s.indexOf(':');
    return _withPort(s.substring(0, i), s.substring(i + 1));
  }
  return HostPort(s, null);
}

HostPort _withPort(String host, String? port) {
  if (host.isEmpty) return const HostPort.error('Enter an address');
  if (port == null) return HostPort(host, null);
  final p = RegExp(r'^\d{1,5}$').hasMatch(port) ? int.parse(port) : null;
  if (p == null || p < 1 || p > 65535) return const HostPort.error('Port must be a number from 1 to 65535');
  return HostPort(host, p);
}
