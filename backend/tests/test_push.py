from __future__ import annotations

import uuid

from sqlalchemy import select

from app.config import get_settings
from app.models import Notification, User
from app.models.device import DeviceToken
from app.services import push_service


def _user(db, name="Sam"):
    u = User(id=uuid.uuid4(), auth_subject=f"dev|{uuid.uuid4().hex[:8]}", display_name=name)
    db.add(u)
    db.commit()
    return u


def test_register_device_is_idempotent_and_follows_latest_user(client, auth_headers, db):
    h1, h2 = auth_headers(), auth_headers()
    body = {"token": "tok-abcdefgh", "platform": "android"}
    assert client.post("/api/v1/devices", json=body, headers=h1).status_code == 204
    assert client.post("/api/v1/devices", json=body, headers=h2).status_code == 204
    assert len(db.execute(select(DeviceToken)).scalars().all()) == 1
    assert client.post("/api/v1/devices", json=body).status_code == 401


def test_queue_is_a_noop_without_credentials(db):
    u = _user(db)
    push_service.queue(db, u.id, "hi", kind="summoned")
    assert push_service._PENDING not in db.info


def test_deliver_caps_per_day_and_drops_dead_tokens(db, monkeypatch, tmp_path):
    creds = tmp_path / "k.json"
    creds.write_text('{"client_email":"a@b","project_id":"p","token_uri":"x","private_key":"k"}')
    monkeypatch.setattr(get_settings(), "firebase_credentials", str(creds))
    monkeypatch.setattr(get_settings(), "push_daily_cap", 1)
    push_service._credentials.cache_clear()

    sam, busy = _user(db), _user(db, "Busy")
    for u in (sam, busy):
        db.add(DeviceToken(id=uuid.uuid4(), user_id=u.id, token=f"live-{u.display_name}-token"))
    db.add(DeviceToken(id=uuid.uuid4(), user_id=sam.id, token="dead-token-1"))
    db.add(Notification(id=uuid.uuid4(), user_id=sam.id, kind="summoned", text="one"))
    for i in range(3):  # busy already got 3 notifications today: over the cap
        db.add(Notification(id=uuid.uuid4(), user_id=busy.id, kind="summoned", text=f"b{i}"))
    db.commit()

    calls = []

    def sender(creds, token, title, body, data):
        calls.append(token)
        return token != "dead-token-1"

    push_service.deliver(
        [(sam.id, "one", {"kind": "summoned"}), (busy.id, "b2", {"kind": "summoned"})],
        sender=sender,
    )
    assert sorted(calls) == ["dead-token-1", "live-Sam-token"], "busy user is capped"
    tokens = db.execute(select(DeviceToken.token)).scalars().all()
    assert "dead-token-1" not in tokens and "live-Sam-token" in tokens


def test_delete_only_removes_own_token(client, db, auth_headers):
    from sqlalchemy import select

    from app.models.device import DeviceToken

    a, b = auth_headers(), auth_headers()
    token = "fcm-token-abcdefghijklmnop"
    client.post("/api/v1/devices", json={"token": token}, headers=a)
    assert client.delete(f"/api/v1/devices/{token}", headers=b).status_code == 204
    assert db.execute(select(DeviceToken)).scalars().all()
    assert client.delete(f"/api/v1/devices/{token}", headers=a).status_code == 204
    db.expire_all()
    assert not db.execute(select(DeviceToken)).scalars().all()
