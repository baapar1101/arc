"""
JWS/JWE helpers for Moadian API v2 (compatible with moadian2 / Authlib 1.3.x).
"""
from __future__ import annotations

from datetime import datetime, timezone

from authlib.jose import JsonWebEncryption, JsonWebSignature


def sign_jws(payload: str, private_key, cert_x5c_base64: str) -> str:
    """Create compact JWS with x5c certificate chain (moadian2 format)."""
    sig_time = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    headers = {
        "alg": "RS256",
        "x5c": [cert_x5c_base64],
        "sigT": sig_time,
        "typ": "jose",
        "crit": ["sigT"],
        "cty": "text/plain",
    }
    jws = JsonWebSignature()
    signed = jws.serialize_compact(headers, payload.encode("utf-8"), private_key)
    return signed.decode("utf-8")


def encrypt_jwe(payload: str, server_public_key_pem: str) -> str:
    """Encrypt signed payload with tax authority RSA public key."""
    jwe = JsonWebEncryption()
    protected = {
        "alg": "RSA-OAEP-256",
        "enc": "A256GCM",
    }
    return jwe.serialize_compact(protected, payload, server_public_key_pem)


def build_v2_packet(encrypted_payload: str, fiscal_id: str) -> dict:
    import uuid

    return {
        "payload": encrypted_payload,
        "header": {
            "requestTraceId": str(uuid.uuid4()),
            "fiscalId": fiscal_id,
        },
    }
