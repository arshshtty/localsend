//! Network troubleshooter contract.
//!
//! The types in this module are the Dart-facing contract for the network
//! troubleshooter screen. `run_diagnostics` is real (Troubleshooter 2/4);
//! `probe_peers` is still a stub until 3/4.

/// Result of trying to join the LocalSend multicast group on one interface.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum JoinResult {
    Ok,
    NotAttempted,
    Failed(String),
}

/// Whether the LocalSend port can be bound.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PortStatus {
    Free,
    /// Bound by another process. `pid_hint` (e.g. `"1234 (name)"`) is
    /// best-effort; treat the process name as sensitive in any export.
    InUse {
        pid_hint: Option<String>,
    },
    Denied(String),
    /// Held by this app's own running server or discovery (not a conflict).
    HeldByThisApp,
}

/// Diagnostics for one network interface.
///
/// Interfaces that cannot carry multicast are still reported
/// (`multicast_capable == false`); discovery scans their subnet instead.
#[derive(Debug, Clone)]
pub struct InterfaceDiag {
    pub name: String,
    pub index: u32,
    /// IP addresses as strings (IPv4 dotted or IPv6, no scope suffix).
    pub addresses: Vec<String>,
    pub up: bool,
    pub loopback: bool,
    pub multicast_capable: bool,
    pub join_v4: JoinResult,
    pub join_v6: JoinResult,
}

/// Full diagnostics report.
#[derive(Debug, Clone)]
pub struct Diagnostics {
    pub interfaces: Vec<InterfaceDiag>,
    pub tcp_port: PortStatus,
    pub udp_port: PortStatus,
    /// Permanent field: `true` only when the data comes from a stub
    /// (fixed fake data, e.g. this placeholder or test fakes); real
    /// diagnostics always set `false`. The UI may show a "sample data" hint.
    pub is_stub: bool,
}

/// Typed server/multicast start error.
///
/// Returned (thrown in Dart) by `start_server` when the server cannot start.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StartError {
    PortInUse { port: u16 },
    PermissionDenied,
    NoInterface,
    Other(String),
}

impl std::fmt::Display for StartError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&describe_start_error(self.clone()))
    }
}

impl std::error::Error for StartError {}

/// Where a probed peer IP came from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PeerSource {
    /// `tailscale status --json` (desktop, CLI present).
    TailscaleCli,
    /// IP entered by the user (`peerIps` setting).
    UserEntered,
}

/// Result of probing one peer IP on the LocalSend port.
#[derive(Debug, Clone)]
pub struct PeerProbeResult {
    pub ip: String,
    pub port: u16,
    pub source: PeerSource,
    pub reachable: bool,
    /// Device alias if a LocalSend device answered.
    pub alias: Option<String>,
    /// Device fingerprint if a LocalSend device answered.
    pub fingerprint: Option<String>,
    pub error: Option<String>,
}

/// Runs network diagnostics for `port`.
///
/// Lists every interface (including ones that cannot carry multicast),
/// tries joining the LocalSend multicast group (v4/v6) on a throwaway socket
/// per interface, and probes whether the TCP/UDP `port` can be bound.
///
/// While this app's server (TCP) or discovery (UDP) runs on `port`, the
/// bind probe is skipped and the status is `HeldByThisApp`.
pub async fn run_diagnostics(port: u16) -> Diagnostics {
    let own = crate::diagnostics_impl::OwnPorts {
        tcp: crate::api::server::running_server_port().await == Some(port),
        udp: crate::api::discovery::running_discovery_port().await == Some(port),
    };
    tokio::task::spawn_blocking(move || {
        crate::diagnostics_impl::run(port, &crate::diagnostics_impl::SystemInterfaceSource, own)
    })
    .await
    .unwrap_or_else(|e| Diagnostics {
        interfaces: Vec::new(),
        tcp_port: PortStatus::Denied(format!("diagnostics failed: {e}")),
        udp_port: PortStatus::Denied(format!("diagnostics failed: {e}")),
        is_stub: false,
    })
}

/// Probes peers (Tailscale CLI peers on desktop, plus `peer_ips`) on `port`.
///
/// STUB: returns an empty list. Implemented in a later PR.
pub async fn probe_peers(
    peer_ips: Vec<String>,
    port: u16,
    timeout_ms: u32,
) -> Vec<PeerProbeResult> {
    let _ = (peer_ips, port, timeout_ms);
    Vec::new()
}

/// Human-readable message for a [StartError] (English fallback for logs/UI).
///
#[flutter_rust_bridge::frb(sync)]
pub fn describe_start_error(error: StartError) -> String {
    match error {
        StartError::PortInUse { port } => format!("Port {port} is already in use"),
        StartError::PermissionDenied => "Permission denied".to_string(),
        StartError::NoInterface => "No network interface available".to_string(),
        StartError::Other(msg) => msg,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn real_diagnostics_are_not_stub() {
        let d = run_diagnostics(0).await;
        assert!(!d.is_stub);
        assert!(probe_peers(vec![], 53317, 500).await.is_empty());
        assert_eq!(
            describe_start_error(StartError::PortInUse { port: 53317 }),
            "Port 53317 is already in use"
        );
    }

    /// Our own running server must not be reported as a port conflict.
    #[tokio::test]
    async fn own_running_server_is_held_by_this_app() {
        use crate::api::server::{WebMode, WebParams, start_server};
        let server = start_server(
            0,
            None,
            "diag".into(),
            "2.1".into(),
            None,
            None,
            "fingerprint".into(),
            None,
            false,
            WebParams {
                mode: WebMode::Disabled,
                i18n: Default::default(),
                pages: Default::default(),
            },
            None,
        )
        .await
        .expect("server starts");
        let port = crate::api::server::running_server_port()
            .await
            .expect("running");
        let d = run_diagnostics(port).await;
        assert_eq!(d.tcp_port, PortStatus::HeldByThisApp);
        server.stop().await;
    }
}
