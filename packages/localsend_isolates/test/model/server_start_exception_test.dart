import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_isolates/model/server_start_exception.dart';
import 'package:localsend_isolates/rust/api/diagnostics.dart';

void main() {
  test('carries the typed PortInUse error and keeps the plain message', () {
    const e = ServerStartException(
      error: StartError.portInUse(port: 53317),
      message: 'Port 53317 is already in use',
    );
    expect(e.error, isA<StartError_PortInUse>());
    expect((e.error as StartError_PortInUse).port, 53317);
    expect(e.toString(), 'Port 53317 is already in use');
  });

  test('other errors keep their original text', () {
    const e = ServerStartException(error: StartError.other('boom'), message: 'boom');
    expect(e.error, const StartError.other('boom'));
    expect('$e', 'boom');
  });
}
