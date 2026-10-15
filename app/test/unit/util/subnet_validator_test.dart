import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/subnet_validator.dart';

void main() {
  test('validateSubnet', () {
    expect(validateSubnet('192.168.5.0/26'), isNull);
    expect(validateSubnet('192.168.5.7/32'), isNull);
    expect(validateSubnet('192.168.5.192/26'), isNull);
    // Over /26 (more than 64 addresses) is rejected to match the 96-target scan cap.
    expect(validateSubnet('192.168.5.0/24'), contains('/26'));
    expect(validateSubnet('192.168.5.128/25'), contains('192.168.5.128/26'));
    expect(validateSubnet('192.168.5.*'), contains('192.168.5.0/26'));
    expect(validateSubnet('10.0.0.0/8'), contains('too large'));
    expect(validateSubnet('192.168.5.7/26'), contains('192.168.5.0/26'));
    expect(validateSubnet('192.168.05.0/24'), isNotNull);
    expect(validateSubnet('010.1.1.*'), isNotNull);
    expect(validateSubnet('192.168.*.*'), isNotNull);
    expect(validateSubnet('300.1.1.0/24'), isNotNull);
    expect(validateSubnet('hello'), isNotNull);
  });

  test('normalizeSubnet', () {
    expect(normalizeSubnet('10.0.6.*'), normalizeSubnet('10.0.6.0/24'));
  });

  test('isValidIp', () {
    expect(isValidIp('100.64.0.2'), isTrue);
    expect(isValidIp('fd7a:115c:a1e0::1'), isTrue);
    expect(isValidIp('fe80::1%eth0'), isTrue);
    expect(isValidIp('1.2.3'), isFalse);
    expect(isValidIp('01.2.3.4'), isFalse);
    expect(isValidIp('256.1.1.1'), isFalse);
    expect(isValidIp('nope'), isFalse);
    expect(isValidIp(':::'), isFalse);
  });

  test('parseHostPort', () {
    HostPort p(String s) => parseHostPort(s);
    expect((p('192.168.1.5').host, p('192.168.1.5').port), ('192.168.1.5', null));
    expect((p('192.168.1.5:5000').host, p('192.168.1.5:5000').port), ('192.168.1.5', 5000));
    expect((p('[fe80::1]:53317').host, p('[fe80::1]:53317').port), ('fe80::1', 53317));
    expect((p('[fe80::1]').host, p('[fe80::1]').port), ('fe80::1', null));
    expect((p('fe80::1').host, p('fe80::1').port), ('fe80::1', null));
    expect(p('192.168.1.5:99999').error, isNotNull);
    expect(p('1.2.3.4:abc').error, isNotNull);
    expect(p('1.2.3.4:').error, isNotNull);
    expect(p('[fe80::1]:0').error, isNotNull);
    expect(p(':53317').error, isNotNull);
  });
}
