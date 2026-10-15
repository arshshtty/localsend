//! Enumeration and filtering of the local network interfaces.

use std::net::{IpAddr, Ipv4Addr};

/// Restricts the network interfaces that are used.
///
/// Filters are matched against every address of an interface. A `*` matches one
/// or more characters that are not a `.`, so `192.168.1.*` matches
/// `192.168.1.42` but not `192.168.10.1`.
#[derive(Clone, Debug, Default)]
pub struct InterfaceFilter {
    /// When set, only interfaces with a matching address are used.
    pub whitelist: Option<Vec<String>>,

    /// When set, interfaces with a matching address are skipped.
    pub blacklist: Option<Vec<String>>,

    /// When set and non-empty, only interfaces with one of these names
    /// (e.g. `["tailscale0"]`) are used. `None` or empty = all interfaces.
    pub interface_names: Option<Vec<String>>,
}

impl InterfaceFilter {
    /// Returns `true` when the interface `name` with the given addresses must not be used.
    pub fn is_ignored(&self, name: &str, addresses: &[IpAddr]) -> bool {
        if let Some(names) = &self.interface_names {
            if !names.is_empty() && !names.iter().any(|n| n == name) {
                return true;
            }
        }

        if let Some(whitelist) = &self.whitelist {
            if !any_address_matches(addresses, whitelist) {
                return true;
            }
        }

        if let Some(blacklist) = &self.blacklist {
            if any_address_matches(addresses, blacklist) {
                return true;
            }
        }

        false
    }
}

/// Returns `true` when at least one of `addresses` matches at least one of `patterns`.
fn any_address_matches(addresses: &[IpAddr], patterns: &[String]) -> bool {
    addresses.iter().any(|address| {
        let address = address.to_string();
        patterns
            .iter()
            .any(|pattern| matches_ip_filter(pattern, &address))
    })
}

/// Matches the whole address against a filter pattern.
fn matches_ip_filter(pattern: &str, address: &str) -> bool {
    match pattern.split_once('*') {
        None => pattern == address,
        Some((prefix, rest)) => {
            let Some(remainder) = address.strip_prefix(prefix) else {
                return false;
            };

            // `*` must consume at least one character and may not cross a `.`.
            let max_len = remainder
                .find('.')
                .unwrap_or(remainder.len())
                .min(remainder.len());

            (1..=max_len).any(|len| matches_ip_filter(rest, &remainder[len..]))
        }
    }
}

/// A local IPv4 address that a multicast socket can be bound to.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct LocalInterfaceV4 {
    /// The name of the interface, only used for logging.
    pub(crate) name: String,

    /// The IPv4 address of the interface, used to join the multicast group.
    pub(crate) address: Ipv4Addr,
}

/// A local interface that an IPv6 multicast socket can be bound to.
///
/// IPv6 group membership is joined per interface rather than per address, so a
/// single socket per interface covers all of its IPv6 addresses.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct LocalInterfaceV6 {
    /// The name of the interface, only used for logging.
    pub(crate) name: String,

    /// The index of the interface, used to join the multicast group.
    pub(crate) index: u32,
}

/// The local network interfaces that multicast sockets can be bound to.
pub(crate) struct LocalInterfaces {
    /// One entry per IPv4 address of an interface.
    pub(crate) v4: Vec<LocalInterfaceV4>,

    /// One entry per interface that has at least one IPv6 address.
    pub(crate) v6: Vec<LocalInterfaceV6>,
}

/// Returns the addresses of all non-loopback interfaces that pass `filter`.
pub(crate) fn local_interfaces(filter: &InterfaceFilter) -> std::io::Result<LocalInterfaces> {
    struct Entry {
        name: String,
        index: Option<u32>,
        addresses: Vec<IpAddr>,
    }

    // Filters apply to an interface as a whole, so all of its addresses have to
    // be known before any of them can be accepted.
    let mut by_name: Vec<Entry> = Vec::new();
    for interface in if_addrs::get_if_addrs()? {
        if interface.is_loopback() {
            continue;
        }

        match by_name
            .iter_mut()
            .find(|entry| entry.name == interface.name)
        {
            Some(entry) => {
                entry.index = entry.index.or(interface.index);
                entry.addresses.push(interface.ip());
            }
            None => by_name.push(Entry {
                name: interface.name.clone(),
                index: interface.index,
                addresses: vec![interface.ip()],
            }),
        }
    }

    let mut result = LocalInterfaces {
        v4: Vec::new(),
        v6: Vec::new(),
    };
    for entry in by_name {
        if filter.is_ignored(&entry.name, &entry.addresses) {
            tracing::debug!(
                "Ignoring network interface {} ({:?})",
                entry.name,
                entry.addresses
            );
            continue;
        }

        let mut has_v6 = false;
        for address in &entry.addresses {
            match address {
                // IPv4 group membership is joined per address.
                IpAddr::V4(address) => result.v4.push(LocalInterfaceV4 {
                    name: entry.name.clone(),
                    address: *address,
                }),
                IpAddr::V6(_) => has_v6 = true,
            }
        }

        if has_v6 {
            match entry.index {
                Some(index) => result.v6.push(LocalInterfaceV6 {
                    name: entry.name,
                    index,
                }),
                // Joining an IPv6 group requires the interface index.
                None => tracing::debug!(
                    "Interface {} has no index, not using it for IPv6 multicast",
                    entry.name
                ),
            }
        }
    }

    Ok(result)
}

/// Names of the local interfaces (for validating saved interface names).
pub fn interface_names() -> std::io::Result<Vec<String>> {
    let mut names: Vec<String> = if_addrs::get_if_addrs()?
        .into_iter()
        .map(|i| i.name)
        .collect();
    names.sort();
    names.dedup();
    Ok(names)
}

/// The IPv4 addresses of all usable (non-loopback, unfiltered) local
/// interfaces, e.g. the subnets to fall back-scan when multicast is silent.
pub fn local_interface_addresses(filter: &InterfaceFilter) -> std::io::Result<Vec<Ipv4Addr>> {
    Ok(local_interfaces(filter)?
        .v4
        .into_iter()
        .map(|interface| interface.address)
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ip(address: &str) -> IpAddr {
        address.parse().unwrap()
    }

    #[test]
    fn test_exact_pattern() {
        assert!(matches_ip_filter("192.168.1.42", "192.168.1.42"));
        assert!(!matches_ip_filter("192.168.1.42", "192.168.1.43"));
    }

    #[test]
    fn test_wildcard_does_not_cross_dots() {
        assert!(matches_ip_filter("192.168.1.*", "192.168.1.42"));
        assert!(!matches_ip_filter("192.168.1.*", "192.168.1.42.1"));
        assert!(!matches_ip_filter("192.168.*", "192.168.1.42"));
        assert!(matches_ip_filter("192.168.*.42", "192.168.1.42"));
    }

    #[test]
    fn test_wildcard_requires_at_least_one_character() {
        assert!(!matches_ip_filter("192.168.1.*", "192.168.1."));
    }

    #[test]
    fn test_multiple_wildcards() {
        assert!(matches_ip_filter("192.*.*.42", "192.168.1.42"));
        assert!(!matches_ip_filter("192.*.*.42", "192.168.1.43"));
    }

    #[test]
    fn test_ipv6_wildcard() {
        assert!(matches_ip_filter("1::1:*:3", "1::1:2:3"));
        assert!(!matches_ip_filter("1::1:*:3", "1::1:2:4"));
    }

    #[test]
    fn test_no_filter_accepts_everything() {
        let filter = InterfaceFilter::default();
        assert!(!filter.is_ignored("eth0", &[ip("192.168.1.42")]));
    }

    #[test]
    fn test_whitelist_skips_non_matching_interfaces() {
        let filter = InterfaceFilter {
            whitelist: Some(vec!["192.168.1.*".to_string()]),
            blacklist: None,
            interface_names: None,
        };

        assert!(!filter.is_ignored("eth0", &[ip("192.168.1.42")]));
        assert!(filter.is_ignored("eth0", &[ip("10.0.0.1")]));
        // A single matching address is enough to keep the interface.
        assert!(!filter.is_ignored("eth0", &[ip("10.0.0.1"), ip("192.168.1.42")]));
    }

    #[test]
    fn test_blacklist_skips_matching_interfaces() {
        let filter = InterfaceFilter {
            whitelist: None,
            blacklist: Some(vec!["10.0.0.*".to_string()]),
            interface_names: None,
        };

        assert!(!filter.is_ignored("eth0", &[ip("192.168.1.42")]));
        assert!(filter.is_ignored("eth0", &[ip("10.0.0.1")]));
        // A single matching address is enough to drop the interface.
        assert!(filter.is_ignored("eth0", &[ip("192.168.1.42"), ip("10.0.0.1")]));
    }

    #[test]
    fn test_blacklist_wins_over_whitelist() {
        let filter = InterfaceFilter {
            whitelist: Some(vec!["192.168.*.*".to_string()]),
            blacklist: Some(vec!["192.168.1.*".to_string()]),
            interface_names: None,
        };

        assert!(!filter.is_ignored("eth0", &[ip("192.168.2.42")]));
        assert!(filter.is_ignored("eth0", &[ip("192.168.1.42")]));
    }

    #[test]
    fn test_interface_names_restrict_by_name() {
        let filter = InterfaceFilter {
            interface_names: Some(vec!["tailscale0".to_string()]),
            ..Default::default()
        };
        assert!(!filter.is_ignored("tailscale0", &[ip("100.64.0.5")]));
        assert!(filter.is_ignored("eth0", &[ip("192.168.1.42")]));
    }

    #[test]
    fn test_empty_interface_names_keep_all() {
        let filter = InterfaceFilter {
            interface_names: Some(vec![]),
            ..Default::default()
        };
        assert!(!filter.is_ignored("eth0", &[ip("192.168.1.42")]));
    }

    #[test]
    fn test_interface_names_combine_with_blacklist() {
        let filter = InterfaceFilter {
            interface_names: Some(vec!["eth0".to_string()]),
            blacklist: Some(vec!["10.0.0.*".to_string()]),
            ..Default::default()
        };
        assert!(filter.is_ignored("eth0", &[ip("10.0.0.1")]));
        assert!(!filter.is_ignored("eth0", &[ip("192.168.1.42")]));
    }

    /// Linux only: in a fresh user + network namespace with two veth links,
    /// `interface_names` restricts the interfaces multicast binds/joins on (and
    /// the advertised interface list), while the HTTP server still listens on all.
    /// Skips (passes) when unprivileged netns/veth are unavailable.
    #[cfg(target_os = "linux")]
    #[test]
    fn test_interface_names_in_netns() {
        if std::env::var_os("LS_NETNS_INNER").is_some() {
            return;
        }
        let probe = std::process::Command::new("unshare")
            .args(["-rn", "sh", "-c", "ip link add t0 type veth peer name t1"])
            .output();
        if !matches!(probe, Ok(ref out) if out.status.success()) {
            eprintln!("skipping netns test: unprivileged netns/veth unavailable");
            return;
        }
        let exe = std::env::current_exe().unwrap();
        let script = format!(
            "set -e; ip link set lo up; ip link add v0 type veth peer name v1; \
             ip addr add 10.78.0.1/24 dev v0; ip addr add 10.78.1.1/24 dev v1; \
             ip link set v0 up; ip link set v1 up; \
             LS_NETNS_INNER=1 '{}' --exact util::interface::tests::netns_inner_interface_names --ignored",
            exe.display()
        );
        let out = std::process::Command::new("unshare")
            .args(["-rn", "sh", "-c", &script])
            .output()
            .unwrap();
        let stdout = String::from_utf8_lossy(&out.stdout);
        assert!(
            out.status.success() && stdout.contains("1 passed"),
            "inner test failed:\n{stdout}\n{}",
            String::from_utf8_lossy(&out.stderr)
        );
    }

    #[cfg(target_os = "linux")]
    #[test]
    #[ignore = "run inside a network namespace by test_interface_names_in_netns"]
    fn netns_inner_interface_names() {
        assert!(std::env::var_os("LS_NETNS_INNER").is_some());
        let all = local_interfaces(&InterfaceFilter::default()).unwrap();
        let names: Vec<_> = all.v4.iter().map(|i| i.name.as_str()).collect();
        assert!(names.contains(&"v0") && names.contains(&"v1"), "{names:?}");

        let only_v1 = InterfaceFilter {
            interface_names: Some(vec!["v1".to_string()]),
            ..Default::default()
        };
        let picked = local_interfaces(&only_v1).unwrap();
        assert_eq!(
            picked.v4,
            vec![LocalInterfaceV4 {
                name: "v1".to_string(),
                address: "10.78.1.1".parse().unwrap()
            }]
        );
        // The multicast sockets follow the same filter.
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        let sockets = rt.block_on(async {
            crate::multicast::socket::bind_multicast_sockets(
                crate::multicast::DEFAULT_MULTICAST_GROUP,
                None,
                0,
                &only_v1,
            )
        });
        let sockets = sockets.expect("bind on v1");
        assert_eq!(sockets.len(), 1);

        // The HTTP server is not scoped: it listens on 0.0.0.0/[::] and
        // accepts on every interface, including ones not in the filter.
        rt.block_on(async {
            let (_stop_tx, stop_rx) = tokio::sync::oneshot::channel::<()>();
            let handle = crate::http::server::start_with_port(
                0,
                None,
                crate::http::state::ClientInfo {
                    alias: "netns".into(),
                    version: "2.1".into(),
                    device_model: None,
                    device_type: None,
                    token: "t".into(),
                },
                None,
                None,
                Default::default(),
                stop_rx,
            )
            .await
            .expect("server starts");
            let port = handle.port();
            let connect = |ip: &'static str| async move {
                tokio::time::timeout(
                    std::time::Duration::from_secs(2),
                    tokio::net::TcpStream::connect((ip, port)),
                )
                .await
                .is_ok_and(|r| r.is_ok())
            };
            assert!(connect("10.78.1.1").await, "v1 must accept");
            assert!(
                connect("10.78.0.1").await,
                "v0 must accept too (server is not filtered)"
            );
        });
    }
}
