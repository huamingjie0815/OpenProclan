"""Accept http(s) links. Refuse a literal private address.

Names are not resolved. This machine may be unable to look up a host the
phone can open, and the server does not fetch the URL.
"""

from __future__ import annotations

import ipaddress
from urllib.parse import urlparse


def is_public_url(url: str) -> bool:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        return False
    host = parsed.hostname.strip("[]").lower()
    if host in {"localhost", "localhost.localdomain"} or host.endswith(".local"):
        return False
    try:
        literal = ipaddress.ip_address(host)
    except ValueError:
        return True
    return _public_ip(literal)


# A literal address in this range is a local proxy's stand-in for a public host.
_PROXY_FAKE_IP = ipaddress.ip_network("198.18.0.0/15")


def _public_ip(ip: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
    if isinstance(ip, ipaddress.IPv4Address) and ip in _PROXY_FAKE_IP:
        return True
    return not (
        ip.is_private
        or ip.is_loopback
        or ip.is_link_local
        or ip.is_multicast
        or ip.is_reserved
        or ip.is_unspecified
    )
