//! Peer probing for the troubleshooter (`api::diagnostics::probe_peers`).
//!
//! Peers come from two sources:
//! - desktop with the `tailscale` CLI: online peers from `tailscale status --json`;
//! - IPs the user entered (`peerIps` setting), on every platform.
//!
//! Each peer is probed concurrently via `GET /api/localsend/v2/info` (HTTPS and
//! HTTP in parallel) with a per-peer timeout. A missing or failing CLI is not
//! an error: it just contributes no peers.

use crate::api::diagnostics::{PeerProbeResult, PeerSource};
use localsend::http::client::LsHttpClientV2;
use localsend::model::discovery::ProtocolType;
use std::future::Future;
use std::net::IpAddr;
use std::pin::Pin;
use std::time::Duration;

/// How long the `tailscale status --json` call may take.
const CLI_TIMEOUT: Duration = Duration::from_secs(2);

/// Source of `tailscale status --json` output. Injectable for tests.
pub(crate) trait TailscaleStatus: Send + Sync {
    /// The raw JSON, or `None` when the CLI is missing or failed.
    fn status_json(&self) -> Pin<Box<dyn Future<Output = Option<String>> + Send + '_>>;
}

/// Runs the real `tailscale` CLI (desktop only).
pub(crate) struct SystemTailscale;

impl TailscaleStatus for SystemTailscale {
    fn status_json(&self) -> Pin<Box<dyn Future<Output = Option<String>> + Send + '_>> {
        Box::pin(async {
            if !cfg!(any(
                target_os = "linux",
                target_os = "macos",
                target_os = "windows"
            )) {
                return None;
            }
            let candidates: &[&str] = if cfg!(target_os = "macos") {
                &[
                    "tailscale",
                    "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
                ]
            } else {
                &["tailscale"]
            };
            for cli in candidates {
                let mut cmd = tokio::process::Command::new(cli);
                cmd.args(["status", "--json"]).kill_on_drop(true);
                match tokio::time::timeout(CLI_TIMEOUT, cmd.output()).await {
                    Ok(Ok(out)) if out.status.success() => {
                        return Some(String::from_utf8_lossy(&out.stdout).into_owned());
                    }
                    Ok(Ok(out)) => {
                        tracing::debug!(
                            "tailscale status failed: {}",
                            String::from_utf8_lossy(&out.stderr)
                        );
                    }
                    Ok(Err(e)) => tracing::debug!("tailscale CLI {cli} not usable: {e}"),
                    Err(_) => tracing::debug!("tailscale status timed out"),
                }
            }
            None
        })
    }
}

/// Extracts the Tailscale IPs (IPv4 first) of all online peers.
/// Malformed JSON yields no peers.
pub(crate) fn parse_tailscale_peers(json: &str) -> Vec<String> {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(json) else {
        return Vec::new();
    };
    let Some(peers) = value.get("Peer").and_then(|p| p.as_object()) else {
        return Vec::new();
    };
    let mut ips = Vec::new();
    for peer in peers.values() {
        if peer.get("Online").and_then(|o| o.as_bool()) != Some(true) {
            continue;
        }
        let mut peer_ips: Vec<IpAddr> = peer
            .get("TailscaleIPs")
            .and_then(|v| v.as_array())
            .map(|a| {
                a.iter()
                    .filter_map(|ip| ip.as_str()?.parse().ok())
                    .collect()
            })
            .unwrap_or_default();
        peer_ips.sort_by_key(|ip| ip.is_ipv6());
        // One address per peer is enough; prefer IPv4.
        if let Some(ip) = peer_ips.first() {
            ips.push(ip.to_string());
        }
    }
    ips.sort();
    ips
}

/// Probes one peer: reachable when a LocalSend `info` endpoint answers.
async fn probe_one(
    ip: String,
    port: u16,
    source: PeerSource,
    timeout: Duration,
) -> PeerProbeResult {
    let result = tokio::time::timeout(timeout, async {
        let client = LsHttpClientV2::try_new_without_cert().map_err(|e| format!("{e:?}"))?;
        let https = client.info(ProtocolType::Https, &ip, port);
        let http = client.info(ProtocolType::Http, &ip, port);
        tokio::pin!(https, http);
        // First success wins; fail only when both failed.
        let mut last_err = None;
        let mut https_done = false;
        let mut http_done = false;
        while !(https_done && http_done) {
            tokio::select! {
                r = &mut https, if !https_done => {
                    https_done = true;
                    match r { Ok(info) => return Ok(info.alias), Err(e) => last_err = Some(format!("{e:?}")) }
                }
                r = &mut http, if !http_done => {
                    http_done = true;
                    match r { Ok(info) => return Ok(info.alias), Err(e) => last_err = Some(format!("{e:?}")) }
                }
            }
        }
        Err(last_err.unwrap_or_default())
    })
    .await;
    let (reachable, alias, error) = match result {
        Ok(Ok(alias)) => (true, Some(alias), None),
        Ok(Err(e)) => (false, None, Some(e)),
        Err(_) => (
            false,
            None,
            Some(format!("timeout after {} ms", timeout.as_millis())),
        ),
    };
    PeerProbeResult {
        ip,
        port,
        source,
        reachable,
        alias,
        error,
    }
}

pub(crate) async fn probe_peers_with(
    tailscale: &dyn TailscaleStatus,
    peer_ips: Vec<String>,
    port: u16,
    timeout_ms: u32,
) -> Vec<PeerProbeResult> {
    let timeout = Duration::from_millis(u64::from(timeout_ms.max(1)));
    let mut targets: Vec<(String, PeerSource)> = Vec::new();
    if let Some(json) = tailscale.status_json().await {
        for ip in parse_tailscale_peers(&json) {
            targets.push((ip, PeerSource::TailscaleCli));
        }
    }
    for ip in peer_ips {
        let ip = ip.trim().to_string();
        if ip.parse::<IpAddr>().is_err() {
            tracing::debug!("Ignoring invalid peer IP {ip:?}");
            continue;
        }
        if !targets.iter().any(|(t, _)| *t == ip) {
            targets.push((ip, PeerSource::UserEntered));
        }
    }
    let probes = targets
        .into_iter()
        .map(|(ip, source)| tokio::spawn(probe_one(ip, port, source, timeout)));
    let mut results = Vec::new();
    for probe in probes.collect::<Vec<_>>() {
        if let Ok(result) = probe.await {
            results.push(result);
        }
    }
    results
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE: &str = include_str!("../tests/fixtures/tailscale_status.json");

    struct FakeTailscale(Option<String>);

    impl TailscaleStatus for FakeTailscale {
        fn status_json(&self) -> Pin<Box<dyn Future<Output = Option<String>> + Send + '_>> {
            Box::pin(async move { self.0.clone() })
        }
    }

    #[test]
    fn parses_online_peers_only() {
        assert_eq!(
            parse_tailscale_peers(FIXTURE),
            vec!["127.0.0.1".to_string()]
        );
        assert!(parse_tailscale_peers("not json").is_empty());
        assert!(parse_tailscale_peers("{}").is_empty());
    }

    async fn start_test_server(
        alias: &str,
    ) -> (
        localsend::http::server::ServerHandle,
        tokio::sync::oneshot::Sender<()>,
    ) {
        let (stop_tx, stop_rx) = tokio::sync::oneshot::channel::<()>();
        let handle = localsend::http::server::start_with_port(
            0,
            None,
            localsend::http::state::ClientInfo {
                alias: alias.into(),
                version: "2.1".into(),
                device_model: None,
                device_type: None,
                token: "fingerprint".into(),
            },
            None,
            Some(localsend::http::server::ServerConfigV2 {
                pin: None,
                verify_checksums: false,
                event_tx: tokio::sync::mpsc::channel(16).0,
            }),
            Default::default(),
            stop_rx,
        )
        .await
        .unwrap();
        (handle, stop_tx)
    }

    /// Acceptance (desktop + CLI): an online tailnet peer is found without
    /// the user typing its IP.
    #[tokio::test]
    async fn cli_peer_is_found_without_entered_ip() {
        let (server, _stop) = start_test_server("Tailnet Peer").await;
        let results = probe_peers_with(
            &FakeTailscale(Some(FIXTURE.into())),
            vec![],
            server.port(),
            2000,
        )
        .await;
        assert_eq!(results.len(), 1, "{results:?}");
        let r = &results[0];
        assert_eq!(r.ip, "127.0.0.1");
        assert_eq!(r.source, PeerSource::TailscaleCli);
        assert!(r.reachable, "{r:?}");
        assert_eq!(r.alias.as_deref(), Some("Tailnet Peer"));
    }

    /// Acceptance (no CLI): a missing CLI falls back quietly; the entered IP
    /// is probed and found.
    #[tokio::test]
    async fn without_cli_entered_ip_is_found() {
        let (server, _stop) = start_test_server("Entered Peer").await;
        let results = probe_peers_with(
            &FakeTailscale(None),
            vec!["127.0.0.1".into(), "bogus".into()],
            server.port(),
            2000,
        )
        .await;
        assert_eq!(results.len(), 1, "{results:?}");
        assert_eq!(results[0].source, PeerSource::UserEntered);
        assert!(results[0].reachable);
        assert_eq!(results[0].alias.as_deref(), Some("Entered Peer"));
    }

    #[tokio::test]
    async fn unreachable_peer_reports_error() {
        // Grab a free port and close it again so nothing listens there.
        let port = std::net::TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .port();
        let results = probe_peers_with(
            &FakeTailscale(Some("garbage".into())),
            vec!["127.0.0.1".into()],
            port,
            500,
        )
        .await;
        assert_eq!(results.len(), 1);
        assert!(!results[0].reachable);
        assert!(results[0].error.is_some());
    }

    #[tokio::test]
    async fn duplicate_ip_is_probed_once() {
        let port = std::net::TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .port();
        let results = probe_peers_with(
            &FakeTailscale(Some(FIXTURE.into())),
            vec!["127.0.0.1".into()],
            port,
            300,
        )
        .await;
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].source, PeerSource::TailscaleCli);
    }
}
