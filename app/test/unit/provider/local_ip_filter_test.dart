import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:test/test.dart';

void main() {
  String name(String s) => s;

  test('empty bindInterfaces keeps all interfaces', () {
    expect(filterBindInterfaces(['eth0', 'wlan0'], const [], name), ['eth0', 'wlan0']);
  });

  test('keeps only the chosen interfaces', () {
    expect(filterBindInterfaces(['eth0', 'wlan0', 'tailscale0'], const ['wlan0'], name), ['wlan0']);
  });

  test('falls back to all interfaces when none of the names exist', () {
    expect(filterBindInterfaces(['eth0', 'wlan0'], const ['usb0'], name), ['eth0', 'wlan0']);
  });
}
