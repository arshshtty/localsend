import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/diagnostics_provider.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_app/provider/last_devices.provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/subnet_validator.dart';
import 'package:localsend_app/widget/dialogs/error_dialog.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/model.dart';
import 'package:localsend_isolates/util/rust.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

enum _InputMode {
  hashtag,
  ip
  ;

  String get label {
    return switch (this) {
      _InputMode.hashtag => t.dialogs.addressInput.hashtag,
      _InputMode.ip => t.dialogs.addressInput.ip,
    };
  }
}

/// A dialog to input an hash or address.
/// Pops the dialog with the device if found.
/// In IP mode, the input may include a port (`192.168.1.5:53317`, `[fe80::1]:53317`).
class AddressInputDialog extends StatefulWidget {
  /// Opens directly in IP mode (used by the troubleshooter).
  final bool startWithIp;

  const AddressInputDialog({this.startWithIp = false});

  @override
  State<AddressInputDialog> createState() => _AddressInputDialogState();
}

class _AddressInputDialogState extends State<AddressInputDialog> with Refena {
  late final _selected = List.generate(_InputMode.values.length, (index) => index == (widget.startWithIp ? 1 : 0));
  late _InputMode _mode = widget.startWithIp ? _InputMode.ip : _InputMode.hashtag;
  String _input = '';
  bool _fetching = false;
  String? _error;

  Future<void> _submit(List<String> localIps, int defaultPort, [String? candidate]) async {
    int port = defaultPort;
    final List<String> candidates;
    final String input = _input.trim();
    if (candidate != null) {
      candidates = [candidate];
    } else if (_mode == _InputMode.ip) {
      final parsed = parseHostPort(input);
      if (parsed.error != null) {
        setState(() => _error = parsed.error);
        return;
      }
      candidates = [parsed.host]; // bare host: the Rust URL builder adds IPv6 brackets
      port = parsed.port ?? port;
    } else {
      candidates = localIps.map((ip) => '${ip.ipPrefix}.$input').toList();
    }

    setState(() {
      _fetching = true;
    });

    final https = ref.read(settingsProvider).https;

    final deviceCompleter = Completer<void>();
    Device? foundDevice;
    String? error;

    final payload = ref.read(deviceFullInfoProvider).toRegisterDto();

    final List<Future<void>> futures = [
      for (final ip in candidates)
        () async {
          try {
            final response = await ref
                .read(httpProvider)
                .discovery
                .register(
                  protocol: https ? ProtocolType.https : ProtocolType.http,
                  ip: ip,
                  port: port,
                  payload: payload,
                );

            foundDevice = response.body.toDevice(ip, port, https);
            deviceCompleter.complete();
          } catch (e) {
            error = e.toString();
            rethrow;
          }
        }(),
    ];

    // Wait until,
    // - a device is found
    // - all candidates are checked
    try {
      await Future.any([
        deviceCompleter.future,
        Future.wait(futures),
      ]);
    } catch (_) {}

    if (!mounted) {
      return;
    }

    if (foundDevice != null) {
      ref.redux(lastDevicesProvider).dispatch(AddLastDeviceAction(foundDevice!));
      final foundIp = foundDevice!.ip;
      if ((_mode == _InputMode.ip || candidate != null) && foundIp != null && !ref.read(settingsProvider).peerIps.contains(foundIp)) {
        // Opt-in only: remembered addresses are checked during later scans.
        final remember = await showDialog<bool>(
          context: context,
          builder: (_) => RememberPeerDialog(ip: foundIp),
        );
        if (!mounted) return;
        if (remember == true) {
          await ref.notifier(settingsProvider).setPeerIps(addPeerIp(ref.read(settingsProvider).peerIps, foundIp));
          if (!mounted) return;
        }
      }
      context.pop(foundDevice);
    } else {
      setState(() {
        _fetching = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localIps = (ref.watch(localIpProvider.select((info) => info.localIps))).uniqueIpPrefix;
    final settings = ref.watch(settingsProvider);
    final lastDevices = ref.watch(lastDevicesProvider);

    return AlertDialog(
      title: Text(t.dialogs.addressInput.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ToggleButtons(
            isSelected: _selected,
            onPressed: (int index) {
              setState(() {
                for (int i = 0; i < _selected.length; i++) {
                  _selected[i] = i == index;
                }
                _mode = _InputMode.values[index];
              });
            },
            borderRadius: BorderRadius.circular(10),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            children: _InputMode.values.map((mode) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Text(mode.label),
              );
            }).toList(),
          ),
          const SizedBox(height: 15),
          TextFormField(
            key: ValueKey('input-$_mode'),
            autofocus: true,
            enabled: !_fetching,
            keyboardType: _mode == _InputMode.hashtag ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(
              prefixText: _mode == _InputMode.hashtag ? '# ' : 'IP: ',
            ),
            onChanged: (s) {
              setState(() => _input = s);
            },
            onFieldSubmitted: (s) async => _submit(localIps, settings.port),
          ),
          const SizedBox(height: 10),
          if (_mode == _InputMode.hashtag) ...[
            Text(
              '${t.general.example}: 123',
              style: const TextStyle(color: Colors.grey),
            ),
            if (localIps.length <= 1)
              Text(
                '${t.dialogs.addressInput.ip}: ${localIps.firstOrNull?.ipPrefix ?? '192.168.2'}.$_input',
                style: const TextStyle(color: Colors.grey),
              )
            else ...[
              Text(
                '${t.dialogs.addressInput.ip}:',
                style: const TextStyle(color: Colors.grey),
              ),
              for (final ip in localIps)
                Text(
                  '- ${ip.ipPrefix}.$_input',
                  style: const TextStyle(color: Colors.grey),
                ),
            ],
          ] else ...[
            if (lastDevices.isEmpty)
              Text(
                '${t.general.example}: ${localIps.firstOrNull?.ipPrefix ?? '192.168.2'}.123 or ${localIps.firstOrNull?.ipPrefix ?? '192.168.2'}.123:${settings.port}',
                style: const TextStyle(color: Colors.grey),
              )
            else
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: t.dialogs.addressInput.recentlyUsed),
                    ...lastDevices
                        .mapIndexed((index, device) {
                          return [
                            if (index != 0) const TextSpan(text: ', '),
                            TextSpan(
                              text: device.ip,
                              style: TextStyle(color: Theme.of(context).colorScheme.primary),
                              recognizer: TapGestureRecognizer()..onTap = () async => _submit(localIps, settings.port, device.ip),
                            ),
                          ];
                        })
                        .expand((e) => e),
                  ],
                ),
              ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Text(t.general.error, style: TextStyle(color: Theme.of(context).colorScheme.warning)),
                  if (_error != null) ...[
                    const SizedBox(width: 5),
                    InkWell(
                      onTap: () async {
                        await showDialog(
                          context: context,
                          builder: (_) => ErrorDialog(error: _error!),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Icon(Icons.info, color: Theme.of(context).colorScheme.warning, size: 20),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(),
          child: Text(t.general.cancel),
        ),
        FilledButton(
          onPressed: _fetching ? null : () async => _submit(localIps, settings.port),
          child: Text(t.general.confirm),
        ),
      ],
    );
  }
}

/// Asks whether to remember a reached address for later scans. Defaults to no.
class RememberPeerDialog extends StatelessWidget {
  final String ip;

  const RememberPeerDialog({required this.ip});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Remember this address?'),
      content: Text('Remember $ip for later scans? LocalSend will then check this address when looking for devices.'),
      actions: [
        FilledButton(onPressed: () => context.pop(false), child: const Text('Not now')),
        TextButton(onPressed: () => context.pop(true), child: const Text('Remember')),
      ],
    );
  }
}

extension on String {
  String get ipPrefix {
    return split('.').take(3).join('.');
  }
}

extension on List<String> {
  List<String> get uniqueIpPrefix {
    final seen = <String>{};
    return where((s) => seen.add(s.ipPrefix)).toList();
  }
}
