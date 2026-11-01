"""Password hashes and random tokens."""

from __future__ import annotations

import hashlib
import secrets

from argon2 import PasswordHasher
from argon2.exceptions import VerificationError, VerifyMismatchError

_passwords = PasswordHasher()


def hash_password(password: str) -> str:
    return _passwords.hash(password)


def verify_password(stored: str, password: str) -> bool:
    try:
        return _passwords.verify(stored, password)
    except (VerifyMismatchError, VerificationError):
        return False


def new_secret() -> str:
    return secrets.token_urlsafe(32)


def digest(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()
