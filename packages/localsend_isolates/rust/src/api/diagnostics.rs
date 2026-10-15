//! Network troubleshooter contract (Troubleshooter PR 1/4: contract stub).
//!
//! The types in this module are the Dart-facing contract for the network
//! troubleshooter screen. The functions currently return fixed placeholder
//! data so the UI can be built in parallel; real implementations land in
//! later PRs (real `run_diagnostics` + `StartError::PortInUse` in 2/4,
//! interface binding / extra subnets / peer probing in 3/4).


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
    InUse { pid_hint: Option<String> },
    Denied(String),
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
    /// `true` while this is the PR 1 placeholder (fixed fake data).
    pub is_stub: bool,
}

/// Typed server/multicast start error.
///
/// Not yet returned by `start_server` (wired in Troubleshooter PR 2/4).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StartError {
    PortInUse { port: u16 },
    PermissionDenied,
    NoInterface,
    Other(String),
}

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
    pub error: Option<String>,
}

/// Runs network diagnostics for `port`.
///
/// STUB: returns fixed fake data with `is_stub = true`.
pub async fn run_diagnostics(port: u16) -> Diagnostics {
    let _ = port;
    Diagnostics {
        interfaces: vec![
            InterfaceDiag {
                name: "stub0".to_string(),
                index: 1,
                addresses: vec!["192.168.1.23".to_string()],
                up: true,
                loopback: false,
                multicast_capable: true,
                join_v4: JoinResult::Ok,
                join_v6: JoinResult::NotAttempted,
            },
            InterfaceDiag {
                name: "tailscale0".to_string(),
                index: 2,
                addresses: vec!["100.64.0.5".to_string()],
                up: true,
                loopback: false,
                multicast_capable: false,
                join_v4: JoinResult::Failed("stub: interface does not support multicast".to_string()),
                join_v6: JoinResult::NotAttempted,
            },
        ],
        tcp_port: PortStatus::Free,
        udp_port: PortStatus::Free,
        is_stub: true,
    }
}

/// Probes peers (Tailscale CLI peers on desktop, plus `peer_ips`) on `port`.
///
/// STUB: returns an empty list. Implemented in a later PR.
pub async fn probe_peers(peer_ips: Vec<String>, port: u16, timeout_ms: u32) -> Vec<PeerProbeResult> {
    let _ = (peer_ips, port, timeout_ms);
    Vec::new()
}

/// Human-readable message for a [StartError] (English fallback for logs/UI).
///
/// Also makes `StartError` part of the generated Dart contract ahead of
/// Troubleshooter PR 2/4, where `start_server` starts returning it.
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
    async fn stub_reports_non_multicast_interface() {
        let d = run_diagnostics(53317).await;
        assert!(d.is_stub);
        assert!(d.interfaces.iter().any(|i| !i.multicast_capable));
        assert!(probe_peers(vec![], 53317, 500).await.is_empty());
        assert_eq!(describe_start_error(StartError::PortInUse { port: 53317 }), "Port 53317 is already in use");
    }
}
