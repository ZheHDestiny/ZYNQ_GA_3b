"""Small SQLite result store used by the local GA3B demonstration service."""

from __future__ import annotations

import json
import sqlite3
import threading
from datetime import datetime, timezone
from pathlib import Path


class ResultRepository:
    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        self._initialize()

    def _connect(self):
        connection = sqlite3.connect(self.path, timeout=10)
        connection.row_factory = sqlite3.Row
        return connection

    def _initialize(self) -> None:
        with self._connect() as connection:
            connection.execute(
                """CREATE TABLE IF NOT EXISTS results (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    created_at TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    category TEXT,
                    profile TEXT,
                    payload_json TEXT NOT NULL
                )"""
            )

    def save(self, kind: str, payload: dict) -> int:
        classification = payload.get("classification", {})
        profile = payload.get("fitness_profile", {})
        if isinstance(profile, dict):
            profile = profile.get("id")
        with self._lock, self._connect() as connection:
            cursor = connection.execute(
                "INSERT INTO results(created_at,kind,category,profile,payload_json) VALUES(?,?,?,?,?)",
                (datetime.now(timezone.utc).isoformat(), kind,
                 classification.get("id"), profile,
                 json.dumps(payload, ensure_ascii=False, separators=(",", ":"))),
            )
            return int(cursor.lastrowid)

    def list(self, limit: int = 20) -> list[dict]:
        limit = max(1, min(200, int(limit)))
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT id,created_at,kind,category,profile,payload_json FROM results "
                "WHERE kind <> 'automated_test' ORDER BY id DESC LIMIT ?", (limit,)
            ).fetchall()
        summaries = []
        for row in rows:
            payload = json.loads(row["payload_json"])
            result = payload.get("result", payload)
            summaries.append({
                "id": row["id"], "created_at": row["created_at"],
                "kind": row["kind"], "category": row["category"],
                "profile": row["profile"], "elapsed_ms": payload.get("elapsed_ms"),
                "survived_steps": result.get("steps", result.get("trajectory", {}).get("survived_steps")),
            })
        return summaries

    def get(self, result_id: int) -> dict | None:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT id,created_at,payload_json FROM results WHERE id=?", (int(result_id),)
            ).fetchone()
        if row is None:
            return None
        payload = json.loads(row["payload_json"])
        payload["record_id"] = row["id"]
        payload["recorded_at"] = row["created_at"]
        return payload
