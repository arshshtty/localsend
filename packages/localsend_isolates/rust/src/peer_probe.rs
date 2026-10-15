//! Peer probing for the troubleshooter (`api::diagnostics::probe_peers`).
//!
//! Peers come from two sources:
//! - desktop with the `tailscale` CLI: online peers from `tailscale status --json`;
//! - IPs the user entered (`peerIps` setting), on every platform.
//!
//! The CLI is only used when the caller asks for it (the app does so only
//! when the user picked a `tailscale*` interface).
//!
//! Each peer is probed concurrently (at most 16 at a time, one shared client) via `GET /api/localsend/v2/info` (HTTPS and
//! HTTP in parallel) with a per-peer timeout. A missing or failing CLI is not
//! an error: it just contributes no peers.

use crate::api::diagnostics::{PeerProbeResult, PeerSource};
use localsend::http::client::LsHttpClientV2;
use localsend::model::discovery::ProtocolType;
use std::future::Future;
use std::net::IpAddr;
use std::pin::Pin;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Semaphore;

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

/// At most this many probes run at the same time.
pub(crate) const MAX_CONCURRENT_PROBES: usize = 16;

/// At most this many Tailscale CLI peers are probed per scan.
pub(crate) const MAX_TAILNET_PEERS: usize = 64;

/// At most this many explicit targets (entered peer IPs plus small extra
/// subnets, capped further on the Dart side) are probed per call.
pub(crate) const MAX_PROBE_TARGETS: usize = 4096 + 32;

/// Probes one peer: reachable when a LocalSend `info` endpoint answers.
async fn probe_one(
    client: Arc<LsHttpClientV2>,
    ip: String,
    port: u16,
    source: PeerSource,
    timeout: Duration,
) -> PeerProbeResult {
    let result = tokio::time::timeout(timeout, async {
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
                    match r { Ok(info) => return Ok((info.alias, info.fingerprint)), Err(e) => last_err = Some(format!("{e:?}")) }
                }
                r = &mut http, if !http_done => {
                    http_done = true;
                    match r { Ok(info) => return Ok((info.alias, info.fingerprint)), Err(e) => last_err = Some(format!("{e:?}")) }
                }
            }
        }
        Err(last_err.unwrap_or_default())
    })
    .await;
    let (reachable, alias, fingerprint, error) = match result {
        Ok(Ok((alias, fingerprint))) => (true, Some(alias), Some(fingerprint), None),
        Ok(Err(e)) => (false, None, None, Some(e)),
        Err(_) => (
            false,
            None,
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
        fingerprint,
        error,
    }
}

/// Runs `f` for every target with at most `max_concurrent` in flight,
/// returning the results in target order.
pub(crate) async fn run_bounded<T, R, F, Fut>(
    targets: Vec<T>,
    max_concurrent: usize,
    f: F,
) -> Vec<R>
where
    T: Send + 'static,
    R: Send + 'static,
    F: Fn(T) -> Fut,
    Fut: Future<Output = R> + Send + 'static,
{
    let semaphore = Arc::new(Semaphore::new(max_concurrent.max(1)));
    let mut handles = Vec::with_capacity(targets.len());
    for target in targets {
        let fut = f(target);
        let semaphore = semaphore.clone();
        handles.push(tokio::spawn(async move {
            let _permit = semaphore.acquire_owned().await.ok()?;
            Some(fut.await)
        }));
    }
    let mut results = Vec::with_capacity(handles.len());
    for handle in handles {
        if let Ok(Some(result)) = handle.await {
            results.push(result);
        }
    }
    results
}

/// Probes `targets` with one shared HTTP client and bounded concurrency.
async fn probe_targets(
    targets: Vec<(String, PeerSource)>,
    port: u16,
    timeout_ms: u32,
) -> Vec<PeerProbeResult> {
    if targets.is_empty() {
        return Vec::new();
    }
    let timeout = Duration::from_millis(u64::from(timeout_ms.max(1)));
    let client = match LsHttpClientV2::try_new_without_cert() {
        Ok(client) => Arc::new(client),
        Err(e) => {
            tracing::warn!("Could not create the probe HTTP client: {e:?}");
            return Vec::new();
        }
    };
    run_bounded(targets, MAX_CONCURRENT_PROBES, move |(ip, source)| {
        probe_one(client.clone(), ip, port, source, timeout)
    })
    .await
}

/// Probes explicit IPs (entered peer IPs, small extra subnets) with source
/// `UserEntered`. Never runs the Tailscale CLI. Invalid IPs are skipped,
/// duplicates probed once, and at most [MAX_PROBE_TARGETS] are probed.
pub(crate) async fn probe_ips(
    peer_ips: Vec<String>,
    port: u16,
    timeout_ms: u32,
) -> Vec<PeerProbeResult> {
    let mut targets: Vec<(String, PeerSource)> = Vec::new();
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
    targets.truncate(MAX_PROBE_TARGETS);
    probe_targets(targets, port, timeout_ms).await
}

/// Probes the online peers listed by `tailscale status --json` (at most
/// [MAX_TAILNET_PEERS]) with source `TailscaleCli`. A missing or failing CLI
/// yields no results.
pub(crate) async fn probe_tailscale_with(
    tailscale: &dyn TailscaleStatus,
    port: u16,
    timeout_ms: u32,
) -> Vec<PeerProbeResult> {
    let Some(json) = tailscale.status_json().await else {
        return Vec::new();
    };
    let mut peers = parse_tailscale_peers(&json);
    peers.truncate(MAX_TAILNET_PEERS);
    let targets = peers
        .into_iter()
        .map(|ip| (ip, PeerSource::TailscaleCli))
        .collect();
    probe_targets(targets, port, timeout_ms).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    const FIXTURE: &str = include_str!("../tests/fixtures/tailscale_status.json");

    struct FakeTailscale {
        json: Option<String>,
        calls: AtomicUsize,
    }

    impl FakeTailscale {
        fn new(json: Option<&str>) -> Self {
            Self {
                json: json.map(str::to_string),
                calls: AtomicUsize::new(0),
            }
        }
    }

    impl TailscaleStatus for FakeTailscale {
        fn status_json(&self) -> Pin<Box<dyn Future<Output = Option<String>> + Send + '_>> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            Box::pin(async move { self.json.clone() })
        }
    }

    fn free_port() -> u16 {
        std::net::TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .port()
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

    /// Acceptance (desktop + CLI, tailscale interface picked): an online
    /// tailnet peer is found without the user typing its IP.
    #[tokio::test]
    async fn cli_peer_is_found_without_entered_ip() {
        let (server, _stop) = start_test_server("Tailnet Peer").await;
        let cli = FakeTailscale::new(Some(FIXTURE));
        let results = probe_tailscale_with(&cli, server.port(), 2000).await;
        assert_eq!(results.len(), 1, "{results:?}");
        let r = &results[0];
        assert_eq!(r.ip, "127.0.0.1");
        assert_eq!(r.source, PeerSource::TailscaleCli);
        assert!(r.reachable, "{r:?}");
        assert_eq!(r.alias.as_deref(), Some("Tailnet Peer"));
        assert_eq!(r.fingerprint.as_deref(), Some("fingerprint"));
    }

    /// Acceptance (no CLI): a missing CLI yields nothing; the entered IP is
    /// probed and found.
    #[tokio::test]
    async fn without_cli_entered_ip_is_found() {
        let (server, _stop) = start_test_server("Entered Peer").await;
        assert!(
            probe_tailscale_with(&FakeTailscale::new(None), server.port(), 2000)
                .await
                .is_empty()
        );
        let results = probe_ips(
            vec!["127.0.0.1".into(), "bogus".into(), "127.0.0.1".into()],
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
        let results = probe_ips(vec!["127.0.0.1".into()], free_port(), 500).await;
        assert_eq!(results.len(), 1);
        assert!(!results[0].reachable);
        assert!(results[0].error.is_some());
    }

    #[tokio::test]
    async fn no_targets_probe_nothing() {
        assert!(probe_ips(vec![], 53317, 500).await.is_empty());
    }

    #[tokio::test]
    async fn concurrency_is_bounded() {
        let in_flight = Arc::new(AtomicUsize::new(0));
        let peak = Arc::new(AtomicUsize::new(0));
        let results = run_bounded((0..100).collect(), MAX_CONCURRENT_PROBES, |i: u32| {
            let in_flight = in_flight.clone();
            let peak = peak.clone();
            async move {
                let now = in_flight.fetch_add(1, Ordering::SeqCst) + 1;
                peak.fetch_max(now, Ordering::SeqCst);
                tokio::time::sleep(Duration::from_millis(10)).await;
                in_flight.fetch_sub(1, Ordering::SeqCst);
                i
            }
        })
        .await;
        assert_eq!(results, (0..100).collect::<Vec<_>>());
        let peak = peak.load(Ordering::SeqCst);
        assert!(peak <= MAX_CONCURRENT_PROBES, "peak {peak}");
        assert!(peak > 1, "probes should overlap");
    }

    #[tokio::test]
    async fn tailnet_peers_are_capped() {
        let peers: Vec<String> = (0..200)
            .map(|i| {
                format!(
                    r#""n{i}": {{"Online": true, "TailscaleIPs": ["127.0.{}.{}"]}}"#,
                    i / 250,
                    i % 250 + 1
                )
            })
            .collect();
        let json = format!(r#"{{"Peer": {{{}}}}}"#, peers.join(","));
        assert_eq!(parse_tailscale_peers(&json).len(), 200);
        let results =
            probe_tailscale_with(&FakeTailscale::new(Some(&json)), free_port(), 200).await;
        assert_eq!(results.len(), MAX_TAILNET_PEERS);
    }

    #[tokio::test]
    async fn explicit_targets_are_capped() {
        let ips: Vec<String> = (0..(MAX_PROBE_TARGETS + 50))
            .map(|i| format!("127.{}.{}.{}", (i >> 16) & 0xff, (i >> 8) & 0xff, i & 0xff))
            .collect();
        let results = probe_ips(ips, free_port(), 50).await;
        assert_eq!(results.len(), MAX_PROBE_TARGETS);
    }
}
