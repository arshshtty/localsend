//! Implementation of the network diagnostics exposed by `api::diagnostics`.
//!
//! Kept outside `crate::api` so flutter_rust_bridge does not scan it; the
//! Dart-facing types live in `api::diagnostics`.

use crate::api::diagnostics::{Diagnostics, InterfaceDiag, JoinResult, PortStatus, StartError};
use localsend::multicast::{DEFAULT_MULTICAST_GROUP, DEFAULT_MULTICAST_GROUP_V6};
use socket2::{Domain, Protocol, Socket, Type};
use std::collections::BTreeMap;
use std::io;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr, SocketAddrV4, SocketAddrV6};

/// One interface as reported by the OS, before any multicast probing.
#[derive(Debug, Clone)]
pub(crate) struct RawInterface {
    pub name: String,
    pub index: u32,
    pub addresses: Vec<IpAddr>,
    pub up: bool,
    pub loopback: bool,
    pub multicast_capable: bool,
}

/// Source of interfaces and multicast joins. Injectable for tests.
pub(crate) trait InterfaceSource {
    fn interfaces(&self) -> io::Result<Vec<RawInterface>>;
    fn join_v4(&self, iface: &RawInterface, addr: Ipv4Addr) -> io::Result<()>;
    fn join_v6(&self, iface: &RawInterface) -> io::Result<()>;
}

/// The real OS-backed source.
pub(crate) struct SystemInterfaceSource;

impl InterfaceSource for SystemInterfaceSource {
    fn interfaces(&self) -> io::Result<Vec<RawInterface>> {
        let flags = os_flags();
        let mut by_name: BTreeMap<String, RawInterface> = BTreeMap::new();
        for iface in if_addrs::get_if_addrs()? {
            let loopback = iface.is_loopback();
            let entry = by_name.entry(iface.name.clone()).or_insert_with(|| {
                let (up, multicast) = match flags.get(&iface.name) {
                    Some(f) => (f.up, f.multicast),
                    // No flag info (Windows). APPROXIMATE: Windows exposes no
                    // multicast flag here, so "not loopback and not
                    // point-to-point" is assumed. This wrongly reports
                    // Wintun adapters (e.g. Tailscale, WireGuard) as
                    // multicast-capable; the join result is authoritative.
                    None => (iface.is_oper_up(), !loopback && !iface.is_p2p()),
                };
                RawInterface {
                    name: iface.name.clone(),
                    index: iface.index.unwrap_or(0),
                    addresses: Vec::new(),
                    up,
                    loopback,
                    multicast_capable: multicast,
                }
            });
            entry.addresses.push(iface.ip());
        }
        // Interfaces without addresses (e.g. down or unconfigured) are still reported on unix.
        for (name, f) in flags {
            by_name.entry(name.clone()).or_insert(RawInterface {
                name,
                index: f.index,
                addresses: Vec::new(),
                up: f.up,
                loopback: f.loopback,
                multicast_capable: f.multicast,
            });
        }
        Ok(by_name.into_values().collect())
    }

    fn join_v4(&self, _iface: &RawInterface, addr: Ipv4Addr) -> io::Result<()> {
        let socket = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
        socket.bind(&SocketAddr::from(SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, 0)).into())?;
        socket.join_multicast_v4(&DEFAULT_MULTICAST_GROUP, &addr)?;
        // Dropping the throwaway socket leaves the group.
        Ok(())
    }

    fn join_v6(&self, iface: &RawInterface) -> io::Result<()> {
        let socket = Socket::new(Domain::IPV6, Type::DGRAM, Some(Protocol::UDP))?;
        socket.set_only_v6(true)?;
        socket.bind(&SocketAddr::from(SocketAddrV6::new(Ipv6Addr::UNSPECIFIED, 0, 0, 0)).into())?;
        socket.join_multicast_v6(&DEFAULT_MULTICAST_GROUP_V6, iface.index)?;
        Ok(())
    }
}

#[derive(Debug, Clone, Copy)]
struct OsFlags {
    index: u32,
    up: bool,
    loopback: bool,
    multicast: bool,
}

#[cfg(unix)]
fn os_flags() -> BTreeMap<String, OsFlags> {
    let mut map = BTreeMap::new();
    // SAFETY: standard getifaddrs/freeifaddrs usage; pointers are only read
    // while the list is alive.
    unsafe {
        let mut head: *mut libc::ifaddrs = std::ptr::null_mut();
        if libc::getifaddrs(&mut head) != 0 {
            return map;
        }
        let mut cur = head;
        while !cur.is_null() {
            let ifa = &*cur;
            if !ifa.ifa_name.is_null() {
                let name = std::ffi::CStr::from_ptr(ifa.ifa_name)
                    .to_string_lossy()
                    .into_owned();
                let f = ifa.ifa_flags as libc::c_uint;
                let index = libc::if_nametoindex(ifa.ifa_name);
                map.entry(name).or_insert(OsFlags {
                    index,
                    up: f & (libc::IFF_UP as libc::c_uint) != 0,
                    loopback: f & (libc::IFF_LOOPBACK as libc::c_uint) != 0,
                    multicast: f & (libc::IFF_MULTICAST as libc::c_uint) != 0,
                });
            }
            cur = ifa.ifa_next;
        }
        libc::freeifaddrs(head);
    }
    map
}

#[cfg(not(unix))]
fn os_flags() -> BTreeMap<String, OsFlags> {
    BTreeMap::new()
}

fn join_result(r: io::Result<()>) -> JoinResult {
    match r {
        Ok(()) => JoinResult::Ok,
        Err(e) => JoinResult::Failed(e.to_string()),
    }
}

/// Builds the per-interface diagnostics. Interfaces that cannot carry
/// multicast are still reported, with joins marked `NotAttempted`.
pub(crate) fn collect_interfaces(source: &dyn InterfaceSource) -> Vec<InterfaceDiag> {
    let raw = match source.interfaces() {
        Ok(raw) => raw,
        Err(e) => {
            tracing::warn!("Listing network interfaces failed: {e}");
            return Vec::new();
        }
    };
    raw.into_iter()
        .map(|iface| {
            let can_join = iface.up && iface.multicast_capable;
            let v4 = iface.addresses.iter().find_map(|a| match a {
                IpAddr::V4(v4) => Some(*v4),
                IpAddr::V6(_) => None,
            });
            let has_v6 = iface.addresses.iter().any(IpAddr::is_ipv6);
            let join_v4 = match (can_join, v4) {
                (true, Some(addr)) => join_result(source.join_v4(&iface, addr)),
                _ => JoinResult::NotAttempted,
            };
            let join_v6 = if can_join && has_v6 && iface.index != 0 {
                join_result(source.join_v6(&iface))
            } else {
                JoinResult::NotAttempted
            };
            InterfaceDiag {
                name: iface.name,
                index: iface.index,
                addresses: iface.addresses.iter().map(IpAddr::to_string).collect(),
                up: iface.up,
                loopback: iface.loopback,
                multicast_capable: iface.multicast_capable,
                join_v4,
                join_v6,
            }
        })
        .collect()
}

/// TCP bind probe on the wildcard address, like the HTTP server does.
pub(crate) fn probe_tcp(port: u16) -> PortStatus {
    match std::net::TcpListener::bind(SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, port)) {
        Ok(listener) => {
            drop(listener);
            PortStatus::Free
        }
        Err(e) => port_status_from_err(&e, port, true),
    }
}

/// UDP bind probe with the same reuse options as the multicast socket, so a
/// running LocalSend discovery socket does not count as "in use"; only an
/// exclusive bind by another process does.
///
/// Caveat: because of `SO_REUSEADDR`/`SO_REUSEPORT`, another process that
/// also binds the port with reuse (e.g. a second LocalSend instance) is NOT
/// detected and the result is `Free`, although both sockets then share the
/// incoming datagrams.
pub(crate) fn probe_udp(port: u16) -> PortStatus {
    let result = (|| -> io::Result<()> {
        let socket = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
        socket.set_reuse_address(true)?;
        #[cfg(all(
            unix,
            not(any(target_os = "solaris", target_os = "illumos", target_os = "cygwin"))
        ))]
        socket.set_reuse_port(true)?;
        socket.bind(&SocketAddr::from(SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, port)).into())?;
        Ok(())
    })();
    match result {
        Ok(()) => PortStatus::Free,
        Err(e) => port_status_from_err(&e, port, false),
    }
}

fn port_status_from_err(e: &io::Error, port: u16, tcp: bool) -> PortStatus {
    match e.kind() {
        io::ErrorKind::AddrInUse => PortStatus::InUse {
            pid_hint: pid_hint(port, tcp),
        },
        io::ErrorKind::PermissionDenied => PortStatus::Denied(e.to_string()),
        _ => PortStatus::Denied(e.to_string()),
    }
}

/// Best-effort "pid (name)" of the process holding `port`.
///
/// The process name is sensitive (it reveals other software on the machine):
/// keep it on-device and redact it from any exported/shared report.
#[cfg(any(target_os = "linux", target_os = "android"))]
fn pid_hint(port: u16, tcp: bool) -> Option<String> {
    use std::fs;
    let tables: &[&str] = if tcp {
        &["/proc/net/tcp", "/proc/net/tcp6"]
    } else {
        &["/proc/net/udp", "/proc/net/udp6"]
    };
    let mut inodes = Vec::new();
    for table in tables {
        let Ok(content) = fs::read_to_string(table) else {
            continue;
        };
        for line in content.lines().skip(1) {
            let cols: Vec<&str> = line.split_whitespace().collect();
            if cols.len() < 10 {
                continue;
            }
            let Some(local_port) = cols[1]
                .rsplit(':')
                .next()
                .and_then(|p| u16::from_str_radix(p, 16).ok())
            else {
                continue;
            };
            // TCP: only LISTEN (0A). UDP: any bound socket.
            if local_port == port && (!tcp || cols[3] == "0A") && cols[9] != "0" {
                inodes.push(format!("socket:[{}]", cols[9]));
            }
        }
    }
    if inodes.is_empty() {
        return None;
    }
    for proc_entry in fs::read_dir("/proc").ok()?.flatten() {
        let pid = proc_entry.file_name().to_string_lossy().into_owned();
        if !pid.chars().all(|c| c.is_ascii_digit()) {
            continue;
        }
        let Ok(fds) = fs::read_dir(proc_entry.path().join("fd")) else {
            continue;
        };
        for fd in fds.flatten() {
            if let Ok(target) = fs::read_link(fd.path())
                && inodes.iter().any(|i| target.to_string_lossy() == *i)
            {
                let name = fs::read_to_string(proc_entry.path().join("comm")).unwrap_or_default();
                return Some(format!("{pid} ({})", name.trim()));
            }
        }
    }
    None
}

#[cfg(target_os = "macos")]
fn pid_hint(port: u16, tcp: bool) -> Option<String> {
    let filter = if tcp {
        format!("-iTCP:{port}")
    } else {
        format!("-iUDP:{port}")
    };
    let mut args = vec!["-nP", "-Fpc", filter.as_str()];
    if tcp {
        args.push("-sTCP:LISTEN");
    }
    let out = std::process::Command::new("lsof")
        .args(&args)
        .output()
        .ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    let pid = text.lines().find_map(|l| l.strip_prefix('p'))?;
    let name = text.lines().find_map(|l| l.strip_prefix('c')).unwrap_or("");
    Some(format!("{pid} ({name})"))
}

#[cfg(not(any(target_os = "linux", target_os = "android", target_os = "macos")))]
fn pid_hint(_port: u16, _tcp: bool) -> Option<String> {
    None
}

/// Which of `port`'s sockets are held by this app's own server/discovery.
#[derive(Debug, Clone, Copy, Default)]
pub(crate) struct OwnPorts {
    pub tcp: bool,
    pub udp: bool,
}

/// A port held by our own process is not a conflict.
fn own_process_hint(status: PortStatus) -> PortStatus {
    match &status {
        PortStatus::InUse {
            pid_hint: Some(hint),
        } if hint.split_whitespace().next() == Some(std::process::id().to_string().as_str()) => {
            PortStatus::HeldByThisApp
        }
        _ => status,
    }
}

pub(crate) fn run(port: u16, source: &dyn InterfaceSource, own: OwnPorts) -> Diagnostics {
    Diagnostics {
        interfaces: collect_interfaces(source),
        tcp_port: if own.tcp {
            PortStatus::HeldByThisApp
        } else {
            own_process_hint(probe_tcp(port))
        },
        udp_port: if own.udp {
            PortStatus::HeldByThisApp
        } else {
            own_process_hint(probe_udp(port))
        },
        is_stub: false,
    }
}

/// Maps a server start error to the typed [StartError].
pub(crate) fn start_error_from_anyhow(err: &anyhow::Error, port: u16) -> StartError {
    for cause in err.chain() {
        if let Some(io_err) = cause.downcast_ref::<io::Error>() {
            match io_err.kind() {
                io::ErrorKind::AddrInUse => return StartError::PortInUse { port },
                io::ErrorKind::PermissionDenied => return StartError::PermissionDenied,
                io::ErrorKind::AddrNotAvailable => return StartError::NoInterface,
                _ => {}
            }
        }
    }
    if format!("{err:#}").contains("No network interface available") {
        return StartError::NoInterface;
    }
    // Same text the untyped error carried over the bridge before.
    StartError::Other(format!("{err:?}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;

    struct FakeSource {
        ifaces: Vec<RawInterface>,
        v4_calls: Cell<u32>,
    }

    impl InterfaceSource for FakeSource {
        fn interfaces(&self) -> io::Result<Vec<RawInterface>> {
            Ok(self.ifaces.clone())
        }
        fn join_v4(&self, iface: &RawInterface, _addr: Ipv4Addr) -> io::Result<()> {
            self.v4_calls.set(self.v4_calls.get() + 1);
            if iface.name == "broken0" {
                Err(io::Error::other("join refused"))
            } else {
                Ok(())
            }
        }
        fn join_v6(&self, _iface: &RawInterface) -> io::Result<()> {
            Ok(())
        }
    }

    fn raw(name: &str, addr: &str, up: bool, multicast: bool) -> RawInterface {
        RawInterface {
            name: name.into(),
            index: 7,
            addresses: vec![addr.parse().unwrap()],
            up,
            loopback: false,
            multicast_capable: multicast,
        }
    }

    #[test]
    fn fake_interfaces_report_join_results() {
        let source = FakeSource {
            ifaces: vec![
                raw("eth0", "192.168.1.2", true, true),
                raw("down0", "10.0.0.2", false, true),
                raw("tailscale0", "100.64.0.5", true, false),
                raw("broken0", "172.16.0.2", true, true),
                raw("v6only", "fe80::1", true, true),
            ],
            v4_calls: Cell::new(0),
        };
        let diags = collect_interfaces(&source);
        assert_eq!(diags.len(), 5);
        let by = |n: &str| diags.iter().find(|d| d.name == n).unwrap().clone();
        assert_eq!(by("eth0").join_v4, JoinResult::Ok);
        assert_eq!(by("down0").join_v4, JoinResult::NotAttempted);
        // Non-multicast interfaces are still reported.
        let ts = by("tailscale0");
        assert!(!ts.multicast_capable);
        assert_eq!(ts.join_v4, JoinResult::NotAttempted);
        assert_eq!(ts.addresses, vec!["100.64.0.5".to_string()]);
        assert_eq!(
            by("broken0").join_v4,
            JoinResult::Failed("join refused".into())
        );
        assert_eq!(by("v6only").join_v4, JoinResult::NotAttempted);
        assert_eq!(by("v6only").join_v6, JoinResult::Ok);
        assert_eq!(source.v4_calls.get(), 2);
    }

    #[test]
    fn held_tcp_port_reports_in_use() {
        let holder = std::net::TcpListener::bind("0.0.0.0:0").unwrap();
        let port = holder.local_addr().unwrap().port();
        match probe_tcp(port) {
            PortStatus::InUse { pid_hint } => {
                #[cfg(target_os = "linux")]
                assert!(
                    pid_hint
                        .unwrap()
                        .starts_with(&std::process::id().to_string())
                );
                #[cfg(not(target_os = "linux"))]
                let _ = pid_hint;
            }
            other => panic!("expected InUse, got {other:?}"),
        }
        drop(holder);
        assert_eq!(probe_tcp(port), PortStatus::Free);
    }

    #[test]
    fn held_udp_port_reports_in_use() {
        // An exclusive (no reuse) bind blocks the probe.
        let holder = std::net::UdpSocket::bind("0.0.0.0:0").unwrap();
        let port = holder.local_addr().unwrap().port();
        assert!(matches!(probe_udp(port), PortStatus::InUse { .. }));
    }

    #[test]
    fn system_source_lists_loopback() {
        let diags = collect_interfaces(&SystemInterfaceSource);
        let lo = diags.iter().find(|d| d.loopback);
        assert!(lo.is_some(), "no loopback in {diags:?}");
    }

    #[test]
    fn maps_addr_in_use_to_port_in_use() {
        let err =
            anyhow::Error::from(io::Error::from(io::ErrorKind::AddrInUse)).context("bind failed");
        assert_eq!(
            start_error_from_anyhow(&err, 53317),
            StartError::PortInUse { port: 53317 }
        );
        let err = anyhow::Error::from(io::Error::from(io::ErrorKind::PermissionDenied));
        assert_eq!(
            start_error_from_anyhow(&err, 1),
            StartError::PermissionDenied
        );
        let err = anyhow::anyhow!("boom");
        assert_eq!(
            start_error_from_anyhow(&err, 1),
            StartError::Other("boom".into())
        );
    }

    #[test]
    fn own_ports_are_held_by_this_app() {
        // Even when something holds the ports, our own sockets are reported as ours.
        let holder = std::net::TcpListener::bind("0.0.0.0:0").unwrap();
        let port = holder.local_addr().unwrap().port();
        let fake = FakeSource {
            ifaces: vec![],
            v4_calls: Cell::new(0),
        };
        let d = run(
            port,
            &fake,
            OwnPorts {
                tcp: true,
                udp: true,
            },
        );
        assert_eq!(d.tcp_port, PortStatus::HeldByThisApp);
        assert_eq!(d.udp_port, PortStatus::HeldByThisApp);
        // Without the flag, the pid hint (Linux) still identifies our process.
        #[cfg(target_os = "linux")]
        assert_eq!(
            run(port, &fake, OwnPorts::default()).tcp_port,
            PortStatus::HeldByThisApp
        );
    }

    #[tokio::test]
    async fn server_start_on_held_port_is_port_in_use() {
        let holder = std::net::TcpListener::bind("0.0.0.0:0").unwrap();
        let port = holder.local_addr().unwrap().port();
        let (_stop_tx, stop_rx) = tokio::sync::oneshot::channel::<()>();
        let result = localsend::http::server::start_with_port(
            port,
            None,
            localsend::http::state::ClientInfo {
                alias: "test".into(),
                version: "2.1".into(),
                device_model: None,
                device_type: None,
                token: "token".into(),
            },
            None,
            None,
            Default::default(),
            stop_rx,
        )
        .await;
        let err = result.err().expect("start must fail on a held port");
        assert_eq!(
            start_error_from_anyhow(&err, port),
            StartError::PortInUse { port }
        );
    }

    /// Linux only: runs `netns_inner` inside a fresh user + network namespace
    /// with a veth pair: `v0` has multicast turned off, `v1` is a normal
    /// multicast-capable interface, and `v2`/`v3` stay down.
    /// Skips (passes) when unprivileged user namespaces or veth are unavailable.
    #[cfg(target_os = "linux")]
    #[test]
    fn netns_veth_interfaces() {
        if std::env::var_os("LS_NETNS_INNER").is_some() {
            return;
        }
        let exe = std::env::current_exe().unwrap();
        let script = format!(
            "set -e; ip link set lo up; \
             ip link add v0 type veth peer name v1; \
             ip link add v2 type veth peer name v3; \
             ip addr add 10.77.0.1/24 dev v0; ip addr add 10.77.1.1/24 dev v1; \
             ip link set v0 multicast off; ip link set v0 up; ip link set v1 up; \
             LS_NETNS_INNER=1 '{}' --exact diagnostics_impl::tests::netns_inner --ignored --nocapture",
            exe.display()
        );
        let probe = std::process::Command::new("unshare")
            .args(["-rn", "sh", "-c", "ip link add t0 type veth peer name t1"])
            .output();
        match probe {
            Ok(out) if out.status.success() => {}
            _ => {
                eprintln!("skipping netns test: unprivileged netns/veth unavailable");
                return;
            }
        }
        let out = std::process::Command::new("unshare")
            .args(["-rn", "sh", "-c", &script])
            .output()
            .unwrap();
        let stdout = String::from_utf8_lossy(&out.stdout);
        assert!(
            out.status.success() && stdout.contains("1 passed"),
            "netns_inner failed:\n{stdout}\n{}",
            String::from_utf8_lossy(&out.stderr)
        );
    }

    #[cfg(target_os = "linux")]
    #[test]
    #[ignore = "run inside a network namespace by netns_veth_interfaces"]
    fn netns_inner() {
        assert!(std::env::var_os("LS_NETNS_INNER").is_some());
        let diags = collect_interfaces(&SystemInterfaceSource);
        let by = |n: &str| {
            diags
                .iter()
                .find(|d| d.name == n)
                .unwrap_or_else(|| panic!("{n} missing in {diags:?}"))
                .clone()
        };
        let v0 = by("v0");
        assert!(!v0.multicast_capable, "{v0:?}");
        assert_eq!(v0.join_v4, JoinResult::NotAttempted);
        assert_eq!(v0.addresses, vec!["10.77.0.1".to_string()]);
        let v1 = by("v1");
        assert!(v1.multicast_capable && v1.up, "{v1:?}");
        assert_eq!(v1.join_v4, JoinResult::Ok);
        // Down, address-less interfaces are still reported.
        let v2 = by("v2");
        assert!(!v2.up);
        assert!(v2.addresses.is_empty());
        assert_eq!(v2.join_v4, JoinResult::NotAttempted);
        assert!(by("lo").loopback);
    }
}
