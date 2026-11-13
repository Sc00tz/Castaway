// SSRF guard for server-side fetches of attacker-controlled URLs (e.g. podcast
// RSS enclosure URLs). Restricts the scheme to http/https and rejects any URL
// whose host resolves to a loopback, link-local, private, unique-local,
// unspecified or otherwise reserved address. IPv4-mapped IPv6 (::ffff:a.b.c.d)
// and NAT64 (64:ff9b::/96) forms are unwrapped before classification so they
// cannot be used to smuggle an internal IPv4 address past the check.

use std::net::{IpAddr, Ipv4Addr, ToSocketAddrs};

/// Integration tests serve fixture feeds/audio from a loopback HTTP server, which this guard
/// would otherwise (correctly) refuse. Only the `test-support` feature can open that hole, and
/// only for loopback — private/link-local/metadata ranges stay blocked. Never enabled in
/// release builds.
#[cfg(feature = "test-support")]
static ALLOW_LOOPBACK: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

#[cfg(feature = "test-support")]
pub fn allow_loopback_for_tests() {
    ALLOW_LOOPBACK.store(true, std::sync::atomic::Ordering::SeqCst);
}

#[inline]
fn loopback_allowed() -> bool {
    #[cfg(feature = "test-support")]
    {
        ALLOW_LOOPBACK.load(std::sync::atomic::Ordering::SeqCst)
    }
    #[cfg(not(feature = "test-support"))]
    {
        false
    }
}

/// Environment variable listing private networks an admin allows server-side fetches to reach,
/// e.g. a NAS or Audiobookshelf instance on the LAN that hosts feeds. Comma-separated IPs or
/// CIDR blocks: `ALLOWED_PRIVATE_NETWORKS=192.168.1.20,10.0.0.0/24,100.64.0.0/10`.
///
/// If outbound traffic goes through an HTTP proxy (HTTP_PROXY / HTTPS_PROXY) on a private
/// address, list the proxy's address here too: guarded clients resolve the proxy's name, not
/// the destination's, and would otherwise refuse to connect to it.
pub const ALLOWED_PRIVATE_NETWORKS_ENV: &str = "ALLOWED_PRIVATE_NETWORKS";

/// An IP network (address + prefix length).
#[derive(Debug, Clone, Copy, PartialEq)]
struct Network {
    addr: IpAddr,
    prefix: u8,
}

impl Network {
    /// Parse `a.b.c.d`, `a.b.c.d/n`, `v6` or `v6/n`. A bare address is a single host.
    fn parse(s: &str) -> Option<Network> {
        let s = s.trim();
        let (addr, prefix) = match s.split_once('/') {
            Some((a, p)) => (a.trim().parse::<IpAddr>().ok()?, Some(p.trim().parse::<u8>().ok()?)),
            None => (s.parse::<IpAddr>().ok()?, None),
        };
        let max = if addr.is_ipv4() { 32 } else { 128 };
        let prefix = prefix.unwrap_or(max);
        (prefix <= max).then_some(Network { addr, prefix })
    }

    fn contains(&self, ip: IpAddr) -> bool {
        match (self.addr, ip) {
            (IpAddr::V4(net), IpAddr::V4(ip)) => {
                let mask = if self.prefix == 0 { 0 } else { u32::MAX << (32 - self.prefix) };
                u32::from(net) & mask == u32::from(ip) & mask
            }
            (IpAddr::V6(net), IpAddr::V6(ip)) => {
                let mask = if self.prefix == 0 { 0 } else { u128::MAX << (128 - self.prefix) };
                u128::from(net) & mask == u128::from(ip) & mask
            }
            _ => false,
        }
    }
}

fn parse_networks(raw: &str) -> Vec<Network> {
    raw.split(',')
        .filter(|s| !s.trim().is_empty())
        .filter_map(|s| {
            let net = Network::parse(s);
            if net.is_none() {
                tracing::warn!("{}: ignoring invalid entry {:?}", ALLOWED_PRIVATE_NETWORKS_ENV, s.trim());
            }
            net
        })
        .collect()
}

static ALLOWED_NETWORKS: std::sync::LazyLock<Vec<Network>> = std::sync::LazyLock::new(|| {
    let nets = parse_networks(&std::env::var(ALLOWED_PRIVATE_NETWORKS_ENV).unwrap_or_default());
    if !nets.is_empty() {
        tracing::info!("Server-side fetches may reach these private networks: {:?}", nets);
    }
    nets
});

/// Unwrap IPv4-mapped (::ffff:a.b.c.d) and NAT64 (64:ff9b::/96) addresses to the IPv4 address
/// they carry, so an internal IPv4 target can't be smuggled in IPv6 form. Uses
/// `to_ipv4_mapped()` rather than `to_ipv4()`, which would also turn `::1` into `0.0.0.1`.
fn canonical(ip: IpAddr) -> IpAddr {
    if let IpAddr::V6(v6) = ip {
        if let Some(v4) = v6.to_ipv4_mapped() {
            return IpAddr::V4(v4);
        }
        let seg = v6.segments();
        if seg[0] == 0x0064 && seg[1] == 0xff9b && seg[2..6] == [0, 0, 0, 0] {
            let o = v6.octets();
            return IpAddr::V4(Ipv4Addr::new(o[12], o[13], o[14], o[15]));
        }
    }
    ip
}

/// Addresses no setting can open up: loopback (this container's own services), link-local
/// (incl. cloud metadata at 169.254.169.254), multicast, and unspecified/reserved ranges.
fn is_never_allowed(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => {
            let o = v4.octets();
            (v4.is_loopback() && !loopback_allowed())
                || v4.is_link_local()
                || v4.is_unspecified()
                || v4.is_broadcast()
                || v4.is_documentation()
                || v4.is_multicast()                       // 224.0.0.0/4
                || o[0] == 0                                // 0.0.0.0/8
                || (o[0] == 192 && o[1] == 0 && o[2] == 0)  // 192.0.0.0/24 IETF protocol assignments
                || (o[0] == 198 && (o[1] & 0xfe) == 18)     // 198.18.0.0/15 benchmarking
                || o[0] >= 240                              // 240.0.0.0/4 reserved
        }
        IpAddr::V6(v6) => {
            let s0 = v6.segments()[0];
            (v6.is_loopback() && !loopback_allowed())
                || v6.is_unspecified()
                || (s0 & 0xffc0) == 0xfe80 // fe80::/10 link-local
                || (s0 & 0xff00) == 0xff00 // ff00::/8 multicast
        }
    }
}

/// Private-network addresses: blocked unless listed in [`ALLOWED_PRIVATE_NETWORKS_ENV`].
fn is_private(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => {
            let o = v4.octets();
            v4.is_private()                              // 10/8, 172.16/12, 192.168/16
                || (o[0] == 100 && (o[1] & 0xc0) == 64) // 100.64.0.0/10 CGNAT (incl. Tailscale)
        }
        IpAddr::V6(v6) => (v6.segments()[0] & 0xfe00) == 0xfc00, // fc00::/7 unique-local
    }
}

fn is_blocked_with(ip: IpAddr, allowed: &[Network]) -> bool {
    let ip = canonical(ip);
    if is_never_allowed(ip) {
        return true;
    }
    is_private(ip) && !allowed.iter().any(|n| n.contains(ip))
}

/// Returns true if `ip` must not be the target of a server-side fetch.
pub fn is_blocked_ip(ip: IpAddr) -> bool {
    is_blocked_with(ip, &ALLOWED_NETWORKS)
}

/// Validate a URL before any server-side fetch.
///
/// Returns Ok(()) only if the scheme is http/https and *every* address the host
/// resolves to is a public, routable address. Resolution failure or any blocked
/// address yields Err with a short reason.
pub fn ensure_safe_public_url(raw_url: &str) -> Result<(), String> {
    let parsed = url::Url::parse(raw_url).map_err(|e| format!("invalid URL: {}", e))?;

    match parsed.scheme() {
        "http" | "https" => {}
        other => return Err(format!("scheme '{}' not allowed (only http/https)", other)),
    }

    let host_raw = parsed
        .host_str()
        .ok_or_else(|| "URL has no host".to_string())?
        .to_string();

    // url::Url::host_str() returns IPv6 literals wrapped in brackets
    // (e.g. "[::1]"); strip them before attempting a literal-IP parse.
    let host = host_raw
        .strip_prefix('[')
        .and_then(|h| h.strip_suffix(']'))
        .map(|h| h.to_string())
        .unwrap_or(host_raw);

    // If the host is already a literal IP, classify it directly.
    if let Ok(ip) = host.parse::<IpAddr>() {
        return if is_blocked_ip(ip) {
            Err(format!("destination IP {} is private/reserved", ip))
        } else {
            Ok(())
        };
    }

    let port = parsed.port_or_known_default().unwrap_or(80);
    let addrs: Vec<IpAddr> = (host.as_str(), port)
        .to_socket_addrs()
        .map_err(|e| format!("could not resolve host '{}': {}", host, e))?
        .map(|sa| sa.ip())
        .collect();

    if addrs.is_empty() {
        return Err(format!("host '{}' resolved to no addresses", host));
    }
    for ip in &addrs {
        if is_blocked_ip(*ip) {
            return Err(format!(
                "host '{}' resolves to private/reserved address {}",
                host, ip
            ));
        }
    }
    Ok(())
}

/// Async wrapper: DNS resolution is blocking, so run the check off the async
/// executor.
pub async fn ensure_safe_public_url_async(raw_url: &str) -> Result<(), String> {
    let owned = raw_url.to_string();
    tokio::task::spawn_blocking(move || ensure_safe_public_url(&owned))
        .await
        .map_err(|e| format!("URL guard task failed: {}", e))?
}

/// DNS resolver for clients that fetch feed-supplied URLs. It fails any lookup whose answer
/// includes a blocked address, so the connection itself can never reach one. Because the check
/// happens at connect time, it also covers every redirect hop and DNS rebinding (a name that
/// resolved to a public address during an up-front check and to an internal one a moment later).
#[derive(Debug, Default, Clone, Copy)]
pub struct GuardedResolver;

impl reqwest::dns::Resolve for GuardedResolver {
    fn resolve(&self, name: reqwest::dns::Name) -> reqwest::dns::Resolving {
        let host = name.as_str().to_string();
        Box::pin(async move {
            let addrs: Vec<std::net::SocketAddr> = tokio::net::lookup_host((host.as_str(), 0)).await?.collect();
            if addrs.is_empty() {
                return Err(format!("host '{}' resolved to no addresses", host).into());
            }
            if let Some(blocked) = addrs.iter().find(|a| is_blocked_ip(a.ip())) {
                return Err(format!("host '{}' resolves to private/reserved address {}", host, blocked.ip()).into());
            }
            Ok(Box::new(addrs.into_iter()) as reqwest::dns::Addrs)
        })
    }
}

/// True if `url` isn't http(s), or names a blocked IP address directly. Hostnames are left to
/// [`GuardedResolver`], which reqwest never consults for IP literals; that's why this exists.
fn literal_target_blocked(url: &url::Url) -> bool {
    if !matches!(url.scheme(), "http" | "https") {
        return true;
    }
    match url.host() {
        Some(url::Host::Ipv4(ip)) => is_blocked_ip(IpAddr::V4(ip)),
        Some(url::Host::Ipv6(ip)) => is_blocked_ip(IpAddr::V6(ip)),
        _ => false,
    }
}

/// Redirect check for guarded clients: at most 10 hops, none to a non-http(s) URL or a blocked
/// IP literal. Needs no DNS lookup (the old policy blocked an executor thread on one per hop).
fn guarded_redirect_policy() -> reqwest::redirect::Policy {
    reqwest::redirect::Policy::custom(|attempt| {
        if attempt.previous().len() >= 10 {
            return attempt.error("too many redirects");
        }
        if literal_target_blocked(attempt.url()) {
            return attempt.error("redirect to a private/reserved address");
        }
        attempt.follow()
    })
}

/// The only way to build a client that fetches attacker-controlled URLs (feeds, enclosures,
/// artwork, chapters, transcripts). Every DNS answer and every redirect goes through the SSRF
/// guard. Callers add their own timeout and user agent, and must still run
/// [`ensure_safe_public_url_async`] on the initial URL, because a URL containing a raw IP
/// address skips DNS entirely.
///
/// A plain `reqwest::Client` must never be used for a URL that came from a feed.
pub fn guarded_client_builder() -> reqwest::ClientBuilder {
    reqwest::Client::builder()
        .dns_resolver(GuardedResolver)
        .redirect(guarded_redirect_policy())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blocks_loopback_and_metadata_and_private() {
        for u in [
            "http://127.0.0.1:8040/api/castaway_check",
            "http://169.254.169.254/latest/meta-data/",
            "http://[::ffff:169.254.169.254]/",
            "http://[64:ff9b::a9fe:a9fe]/",
            "http://10.0.0.5/",
            "http://192.168.1.1/",
            "http://[::1]/",
            "gopher://127.0.0.1/",
            "file:///etc/passwd",
        ] {
            assert!(ensure_safe_public_url(u).is_err(), "should block {}", u);
        }
    }

    #[test]
    fn allows_public_literal() {
        assert!(ensure_safe_public_url("http://93.184.216.34/audio.mp3").is_ok());
    }

    #[test]
    fn blocks_cgnat_multicast_and_benchmark_ranges() {
        for ip in ["100.64.0.1", "100.127.255.254", "224.0.0.1", "198.18.0.1", "192.0.0.8", "0.1.2.3"] {
            assert!(is_blocked_with(ip.parse().unwrap(), &[]), "should block {}", ip);
        }
        assert!(!is_blocked_with("100.128.0.1".parse().unwrap(), &[]), "just past CGNAT is public");
    }

    #[test]
    fn network_parsing_and_matching() {
        let nets = parse_networks(" 192.168.1.20 , 10.0.0.0/24,fd00::/8, garbage, 10.0.0.0/33");
        assert_eq!(nets.len(), 3, "invalid entries are skipped");
        assert!(nets[0].contains("192.168.1.20".parse().unwrap()));
        assert!(!nets[0].contains("192.168.1.21".parse().unwrap()));
        assert!(nets[1].contains("10.0.0.255".parse().unwrap()));
        assert!(!nets[1].contains("10.0.1.0".parse().unwrap()));
        assert!(nets[2].contains("fd12::1".parse().unwrap()));
        assert!(!nets[1].contains("fd12::1".parse().unwrap()), "v4 networks never match v6");
    }

    #[test]
    fn allowlist_opens_private_ranges_only() {
        let allowed = parse_networks("192.168.1.0/24,100.64.0.0/10,127.0.0.0/8,169.254.0.0/16");
        assert!(!is_blocked_with("192.168.1.50".parse().unwrap(), &allowed));
        assert!(!is_blocked_with("::ffff:192.168.1.50".parse().unwrap(), &allowed), "mapped form too");
        assert!(!is_blocked_with("100.100.1.1".parse().unwrap(), &allowed));
        assert!(is_blocked_with("192.168.2.1".parse().unwrap(), &allowed), "outside the listed network");
        assert!(is_blocked_with("10.0.0.1".parse().unwrap(), &allowed));
        // Listing them changes nothing: loopback and link-local/metadata stay blocked.
        assert!(is_blocked_with("127.0.0.1".parse().unwrap(), &allowed));
        assert!(is_blocked_with("169.254.169.254".parse().unwrap(), &allowed));
    }

    #[tokio::test]
    async fn resolver_refuses_internal_names() {
        use reqwest::dns::Resolve;
        use std::str::FromStr;
        let name = reqwest::dns::Name::from_str("localhost").unwrap();
        assert!(GuardedResolver.resolve(name).await.is_err(), "localhost must not resolve for a guarded client");
    }

    #[tokio::test]
    async fn guarded_client_cannot_connect_to_internal_names() {
        let client = guarded_client_builder().build().unwrap();
        let err = client.get("http://localhost:9/").send().await.unwrap_err();
        assert!(err.is_connect() || err.is_request(), "unexpected error kind: {:?}", err);
    }

    #[test]
    fn redirect_target_check() {
        let blocked = |u: &str| literal_target_blocked(&url::Url::parse(u).unwrap());
        assert!(blocked("http://127.0.0.1/"));
        assert!(blocked("http://[::ffff:10.0.0.1]/"));
        assert!(blocked("ftp://93.184.216.34/"), "non-http schemes are refused");
        assert!(!blocked("https://93.184.216.34/"));
        assert!(!blocked("https://example.com/"), "names are left to the resolver");
    }
}
