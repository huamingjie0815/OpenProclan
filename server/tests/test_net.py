from proclan_server.net import _image_ext, is_public_url


def test_private_urls_are_refused():
    assert not is_public_url("http://127.0.0.1/secret")
    assert not is_public_url("http://10.1.2.3/a")
    assert not is_public_url("http://169.254.1.1/a")
    assert not is_public_url("http://localhost/a")
    assert not is_public_url("file:///etc/passwd")
    assert is_public_url("https://1.1.1.1/story")
    assert is_public_url("https://198.18.0.8/story")


def test_image_sniff():
    assert _image_ext("text/plain", b"\xff\xd8\xff" + b"x" * 10) == ".jpg"
    assert _image_ext("image/svg+xml", b"<svg></svg>") is None
