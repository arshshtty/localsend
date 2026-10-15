import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/pages/tabs/send_tab.dart' show pickerOptions;
import 'package:localsend_app/provider/diagnostics_provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/bind_interfaces_action.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/security_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/subnet_validator.dart';
import 'package:localsend_app/widget/dialogs/add_file_dialog.dart';
import 'package:localsend_app/widget/dialogs/address_input_dialog.dart';
import 'package:localsend_app/widget/dialogs/qr_dialog.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/diagnostics.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// What the pairing QR code shows: own `ip:port` plus the certificate fingerprint.
class OwnPairingInfo {
  final String address; // ip:port
  final String fingerprint;

  const OwnPairingInfo({required this.address, required this.fingerprint});

  String get qrData => '$address?fingerprint=$fingerprint';
}

final ownPairingInfoProvider = ViewProvider<OwnPairingInfo?>((ref) {
  final ip = ref.watch(localIpProvider).localIps.firstOrNull;
  if (ip == null) return null;
  final port = ref.watch(settingsProvider.select((s) => s.port));
  final host = ip.contains(':') ? '[$ip]' : ip;
  return OwnPairingInfo(address: '$host:$port', fingerprint: ref.read(securityProvider).certificateHash);
});

/// Network troubleshooter: port status, interfaces, extra subnets, peer IPs, pairing.
class NetworkDiagnosticsSection extends StatefulWidget {
  final Duration timeout;

  const NetworkDiagnosticsSection({this.timeout = diagnosticsTimeout});

  @override
  State<NetworkDiagnosticsSection> createState() => _NetworkDiagnosticsSectionState();
}

class _NetworkDiagnosticsSectionState extends State<NetworkDiagnosticsSection> with Refena {
  Future<Diagnostics>? _future;

  @override
  void initState() {
    super.initState();
    ensureRef((ref) => _run());
  }

  void _run() {
    final port = ref.read(settingsProvider).port;
    final future = runDiagnosticsWithTimeout(ref.read(runDiagnosticsProvider), port, timeout: widget.timeout);
    // Mark errors as handled; FutureBuilder still receives and shows them.
    future.then((_) {}, onError: (_) {}).ignore();
    setState(() {
      _future = future;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final startError = ref.watch(serverStartErrorProvider);
    return FutureBuilder<Diagnostics>(
      future: _future,
      builder: (context, snapshot) {
        final diag = snapshot.data;
        // Our own running server holds the port, so a diagnostics "in use" is
        // only meaningful while the server is stopped.
        final int? bannerPort = switch (startError) {
          StartError_PortInUse(:final port) => port,
          _ => (diag != null && diag.portInUse) ? settings.port : null,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (bannerPort != null)
              Padding(
                padding: const EdgeInsets.only(top: 15),
                child: MaterialBanner(
                  key: const ValueKey('port-in-use-banner'),
                  leading: const Icon(Icons.warning),
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                  content: Text(
                    'Port $bannerPort in use — change port or quit the other app'
                    '${bannerPort == settings.port && diag?.portPidHint != null ? '\nUsed by process ${diag!.portPidHint}' : ''}',
                  ),
                  actions: [TextButton(onPressed: _run, child: const Text('Check again'))],
                ),
              ),
            if (bannerPort == null && diag != null && diag.portHeldByThisApp)
              Padding(
                key: const ValueKey('port-held-by-this-app'),
                padding: const EdgeInsets.only(top: 15),
                child: Text('LocalSend is using port ${settings.port}.', textAlign: TextAlign.center),
              ),
            if (snapshot.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 15),
                child: MaterialBanner(
                  key: const ValueKey('diagnostics-error'),
                  leading: const Icon(Icons.error),
                  content: Text('The network check failed: ${snapshot.error}'),
                  actions: [TextButton(onPressed: _run, child: const Text('Try again'))],
                ),
              ),
            if (diag != null && diag.isStub)
              const Padding(
                key: ValueKey('sample-data-note'),
                padding: EdgeInsets.only(top: 15),
                child: Text('Showing sample data: the full network check is not available in this build yet.', textAlign: TextAlign.center),
              ),
            if (diag?.portDeniedMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 15),
                child: Text(
                  'Not allowed to use port ${settings.port}: ${diag!.portDeniedMessage}',
                  style: TextStyle(color: Theme.of(context).colorScheme.warning),
                ),
              ),
            _Card(
              title: 'Network interfaces',
              trailing: IconButton(tooltip: 'Check again', icon: const Icon(Icons.refresh), onPressed: _run),
              children: [
                const Text('Choose the networks LocalSend uses for discovery, scans and the addresses it shows. With none selected, all are used.'),
                const SizedBox(height: 10),
                if (snapshot.connectionState != ConnectionState.done)
                  const Center(child: CircularProgressIndicator())
                else if (diag == null)
                  const Text('No interface information available.')
                else ...[
                  if (diag.isStub)
                    const Padding(
                      key: ValueKey('table-sample-note'),
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('Showing sample data. These are not your real networks and cannot be selected.'),
                    ),
                  _InterfaceTable(diag: diag, selected: settings.bindInterfaces),
                ],
              ],
            ),
            _ListEditor(
              key: const ValueKey('extra-subnets'),
              title: 'Extra subnets to scan',
              description:
                  'Ranges to scan for devices, like 192.168.5.0/26 (up to 64 addresses each, 96 addresses in total across scans).',
              hint: '192.168.5.0/26',
              values: settings.extraSubnets,
              validate: validateSubnet,
              normalize: normalizeSubnet,
              onChanged: (v) => ref.notifier(settingsProvider).setExtraSubnets(v),
            ),
            _ListEditor(
              key: const ValueKey('peer-ips'),
              title: 'Known peer IPs',
              description:
                  'Addresses of other devices, for example Tailscale IPs (100.x.y.z). LocalSend checks them directly during scans. After you type an address in "Send by IP:port" and it reaches a device, you can choose to remember it here.',
              hint: '100.64.0.2',
              values: settings.peerIps,
              validate: (s) => isValidIp(s) ? null : 'Enter an IP address, for example 100.64.0.2',
              normalize: (s) => s.trim(),
              onChanged: (v) => ref.notifier(settingsProvider).setPeerIps(v),
            ),
            const _PairingCard(),
          ],
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final List<Widget> children;

  const _Card({required this.title, required this.children, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 15),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _InterfaceTable extends StatelessWidget {
  final Diagnostics diag;
  final List<String> selected;

  const _InterfaceTable({required this.diag, required this.selected});

  @override
  Widget build(BuildContext context) {
    final interfaces = diag.interfaces.where((i) => !i.loopback).toList();
    if (interfaces.isEmpty) {
      return const Text('No network interfaces found. Connect to Wi-Fi or a network cable.');
    }
    return Column(
      children: [
        for (final iface in interfaces)
          CheckboxListTile(
            key: ValueKey('iface-${iface.name}'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: !diag.isStub && selected.contains(iface.name),
            onChanged: diag.isStub
                ? null
                : (checked) async {
                    // Keep only names that exist on this device.
                    final known = diag.interfaces.map((i) => i.name).toSet();
                    final current = selected.where(known.contains).toList();
                    if (checked == true) {
                      current.add(iface.name);
                    } else {
                      current.remove(iface.name);
                    }
                    await context.ref.global.dispatchAsync(SetBindInterfacesAction(current));
                  },
            title: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(iface.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                if (iface.name.startsWith('tailscale'))
                  const Chip(label: Text('Tailscale'), visualDensity: VisualDensity.compact)
                else if (RegExp(r'^(utun|wg|tun|ppp)').hasMatch(iface.name))
                  const Chip(label: Text('Possible VPN'), visualDensity: VisualDensity.compact),
                if (!iface.up) const Chip(label: Text('Down'), visualDensity: VisualDensity.compact),
                if (iface.multicastWorks)
                  const Chip(
                    avatar: Icon(Icons.check, color: Colors.green),
                    label: Text('Multicast ✓'),
                    visualDensity: VisualDensity.compact,
                  )
                else
                  Chip(
                    key: ValueKey('no-multicast-${iface.name}'),
                    avatar: Icon(Icons.close, color: Theme.of(context).colorScheme.error),
                    label: const Text('No multicast ✗'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(iface.addresses.isEmpty ? 'No address' : iface.addresses.join(', ')),
                if (!iface.multicastWorks)
                  Text(
                    '${iface.noMulticastReason}. Automatic discovery may not work on this network; use "Send by IP:port" instead.',
                    style: TextStyle(color: Theme.of(context).colorScheme.warning),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ListEditor extends StatefulWidget {
  final String title;
  final String description;
  final String hint;
  final List<String> values;
  final String? Function(String) validate;
  final String Function(String) normalize;
  final Future<void> Function(List<String>) onChanged;

  const _ListEditor({
    super.key,
    required this.title,
    required this.description,
    required this.hint,
    required this.values,
    required this.validate,
    required this.normalize,
    required this.onChanged,
  });

  @override
  State<_ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends State<_ListEditor> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final value = _controller.text.trim();
    final error = widget.validate(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _error = null);
    _controller.clear();
    final key = widget.normalize(value);
    if (!widget.values.any((v) => widget.normalize(v) == key)) {
      await widget.onChanged([...widget.values, value]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: widget.title,
      children: [
        Text(widget.description),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in widget.values)
              InputChip(
                label: Text(v),
                onDeleted: () => widget.onChanged(widget.values.where((e) => e != v).toList()),
              ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(hintText: widget.hint, errorText: _error, errorMaxLines: 3),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 10),
            TextButton(onPressed: _add, child: const Text('Add')),
          ],
        ),
      ],
    );
  }
}

class _PairingCard extends StatelessWidget {
  const _PairingCard();

  @override
  Widget build(BuildContext context) {
    final own = context.ref.watch(ownPairingInfoProvider);
    return _Card(
      title: 'Connect by address',
      children: [
        Text(own == null ? 'This device has no network address yet.' : 'This device: ${own.address}'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Send by IP:port'),
              onPressed: () async {
                final device = await showDialog<Device?>(
                  context: context,
                  builder: (_) => const AddressInputDialog(startWithIp: true),
                );
                if (device == null || !context.mounted) return;
                final ref = context.ref;
                if (ref.read(selectedSendingFilesProvider).isEmpty) {
                  await AddFileDialog.open(context: context, options: pickerOptions);
                }
                final files = ref.read(selectedSendingFilesProvider);
                if (files.isEmpty || !context.mounted) return;
                await ref.notifier(sendProvider).startSession(target: device, files: files, background: false);
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.qr_code),
              label: const Text('Show pairing code'),
              onPressed: own == null
                  ? null
                  : () => showDialog(
                      context: context,
                      builder: (_) => QrDialog(
                        data: own.qrData,
                        label: 'Show this code to the other device.\nOn the other device, choose "Send by IP:port" and type ${own.address}.',
                      ),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}
