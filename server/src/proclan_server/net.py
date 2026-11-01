"""Download public images. Private addresses are refused."""

from __future__ import annotations

import hashlib
import ipaddress
import socket
from pathlib import Path
from urllib.parse import urljoin, urlparse

import httpx

MAX_IMAGE_BYTES = 8 * 1024 * 1024
_IMAGE_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/gif": ".gif",
}
_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
)


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
        literal = None
    if literal is not None:
        return _public_ip(literal)
    try:
        infos = socket.getaddrinfo(host, None)
    except socket.gaierror:
        return False
    addresses = []
    for info in infos:
        try:
            addresses.append(ipaddress.ip_address(info[4][0]))
        except ValueError:
            return False
    return bool(addresses) and all(_public_ip(ip) for ip in addresses)


# Some local proxies answer public DNS with 198.18.0.0/15. That range is not a
# LAN the server should refuse, or every real image URL fails closed.
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


def download_image(
    url: str,
    media_dir: Path,
    *,
    client: httpx.Client | None = None,
) -> tuple[str, bool] | None:
    """Save one public image. Return (filename, created) or None when it is dropped."""
    owns_client = client is None
    http = client or httpx.Client(timeout=httpx.Timeout(15.0), headers={"User-Agent": _UA})
    try:
        return _store_image(http, url, media_dir)
    finally:
        if owns_client:
            http.close()


def _store_image(client: httpx.Client, url: str, media_dir: Path) -> tuple[str, bool] | None:
    response = _request(client, url)
    if response is None or response.status_code >= 400:
        return None
    data = response.content
    if not data or len(data) > MAX_IMAGE_BYTES:
        return None
    ext = _image_ext(response.headers.get("content-type", ""), data)
    if ext is None:
        return None
    media_dir.mkdir(parents=True, exist_ok=True)
    filename = f"{hashlib.sha256(data).hexdigest()[:20]}{ext}"
    path = media_dir / filename
    created = not path.exists()
    if created:
        path.write_bytes(data)
    return filename, created


def _image_ext(content_type: str, data: bytes) -> str | None:
    ctype = content_type.split(";", 1)[0].strip().lower()
    if ctype in _IMAGE_TYPES:
        return _IMAGE_TYPES[ctype]
    if data.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if data.startswith(b"GIF87a") or data.startswith(b"GIF89a"):
        return ".gif"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return ".webp"
    return None


def _request(client: httpx.Client, url: str) -> httpx.Response | None:
    current = url
    for _ in range(3):
        if not is_public_url(current):
            return None
        try:
            response = client.get(current, follow_redirects=False)
        except httpx.HTTPError:
            return None
        if response.status_code in {301, 302, 303, 307, 308}:
            location = response.headers.get("location")
            if not location:
                return None
            current = urljoin(current, location)
            continue
        if not is_public_url(str(response.url)):
            return None
        return response
    return None
