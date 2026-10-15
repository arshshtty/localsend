# Network troubleshooter

Open it from the Send tab ("Troubleshoot"). It works on Windows, macOS, Linux, Android and iOS.

## What it shows
- **Port warning**: if another app already uses LocalSend's port (53317 by default) or LocalSend could not start because of it, a banner says so, with the other program's process id when known. Change the port in Settings or quit the other app.
- **Network interfaces**: every network on this device with its addresses and whether multicast works. Networks without multicast (VPNs like Tailscale, some guest Wi-Fi) are labelled "No multicast" with the reason; automatic discovery may not work there, so use "Send by IP:port". If the check itself fails, the error is shown.
- **Interface picker**: tick the networks LocalSend should use, for example `tailscale0`. With none ticked, all are used. The choice is saved; making LocalSend use only those networks is not applied yet.
- **Extra subnets (not used yet)**: address ranges like `192.168.5.0/24` or `192.168.5.*`, at most 256 addresses each. They are saved now; scanning them comes in a later update.
- **Known peer IPs (not used yet)**: addresses of other devices, for example Tailscale IPs (`100.x.y.z`). They are saved now; checking them comes in a later update. After "Send by IP:port" reaches a device, LocalSend asks whether to remember its address; nothing is added unless you choose "Remember".
- **Send by IP:port**: type an address such as `192.168.1.20` or `192.168.1.20:53317` and send files directly.
- **Pairing code**: shows a QR code with this device's address and certificate fingerprint. It is display-only: the other device reads the address and types it into "Send by IP:port". There is no camera scanner.

The existing firewall help on the same screen is unchanged.

## Notes
- If the app was built with the placeholder network check, the screen shows sample data, says so, and does not let you select those sample networks.
- Screen text is English only for now.
- This feature lives in the arshshtty/localsend fork only and is not being proposed to the upstream LocalSend project.
