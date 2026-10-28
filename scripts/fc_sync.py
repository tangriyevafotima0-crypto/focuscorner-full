#!/usr/bin/env python3
"""
fc_sync.py — CLI Synergy Bridge for FocusCorner v2.0
Allows terminal or AI scripts to inspect status, append tasks, or export reports
directly from ~/.focus_corner/ while FocusCorner live-reloads via FSEvents.
"""
import argparse
import datetime
import json
import os
import uuid
from pathlib import Path

BASE_DIR = Path.home() / ".focus_corner"
TASKS_FILE = BASE_DIR / "tasks.json"
SAT_FILE = BASE_DIR / "sat_tracker.json"
EXACC_FILE = BASE_DIR / "exacc.json"
HISTORY_FILE = BASE_DIR / "history.md"


def load_json(path: Path, default):
    if path.exists():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return default
    return default


def atomic_save_json(path: Path, data):
    BASE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    tmp.replace(path)


def cmd_status():
    sat = load_json(SAT_FILE, {})
    exacc = load_json(EXACC_FILE, {})
    tasks = load_json(TASKS_FILE, [])
    topics = sat.get("topics", [])
    math_score = 200 + sum(t.get("currentScore", 0) for t in topics if "Math" in t.get("section", ""))
    rw_score = 200 + sum(t.get("currentScore", 0) for t in topics if "Reading" in t.get("section", ""))
    total_sat = int(round(min(800, math_score) + min(800, rw_score)))
    charge = exacc.get("totalStandardCharge", 0)
    pending = [t for t in tasks if not t.get("isCompleted", False)]

    print(f"=== FocusCorner v2.0 Synergy Status ===")
    print(f"SAT Score      : {total_sat} / 1600 (Math: {int(round(math_score))} | R&W: {int(round(rw_score))})")
    print(f"ExAcc Charge   : {charge} ball")
    print(f"Pending Tasks  : {len(pending)} ta")
    for t in pending[:10]:
        print(f"  - [{t.get('sourceSystem', 'GENERAL')}] {t.get('title')} (Due: {t.get('scheduledDate', '')})")


def cmd_add_task(title: str, source: str, acc: str, sat_stage: str, points: float, date_str: str):
    tasks = load_json(TASKS_FILE, [])
    now_iso = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    today_str = date_str or datetime.date.today().isoformat()
    new_item = {
        "id": str(uuid.uuid4()).upper(),
        "title": title,
        "isCompleted": False,
        "createdAt": now_iso,
        "sourceSystem": source.upper(),
        "accumulatorSize": acc.upper(),
        "satStage": sat_stage.upper(),
        "scheduledDate": today_str,
        "pointsValue": points,
        "notes": ""
    }
    tasks.insert(0, new_item)
    atomic_save_json(TASKS_FILE, tasks)
    print(f"✅ Task qo'shildi va FocusCorner oynasiga jonli uzatildi: {title}")


def main():
    parser = argparse.ArgumentParser(description="FocusCorner v2.0 CLI Synergy Bridge")
    sub = parser.add_subparsers(dest="cmd")

    sub.add_parser("status", help="Show current SAT, ExAcc, and Task status")

    add_p = sub.add_parser("add-task", help="Add a task to FocusCorner live HUD")
    add_p.add_argument("title", help="Task title")
    add_p.add_argument("--source", default="GENERAL", choices=["GENERAL", "EXACC", "SAT"])
    add_p.add_argument("--acc", default="NONE", choices=["NONE", "SMALL", "MEDIUM", "BIG"])
    add_p.add_argument("--sat-stage", default="NONE", choices=["NONE", "INGEST", "DAY_1", "DAY_3", "DAY_7", "DAY_14", "DAY_30"])
    add_p.add_argument("--points", type=float, default=0.0)
    add_p.add_argument("--date", default="")

    args = parser.parse_args()
    if args.cmd == "add-task":
        cmd_add_task(args.title, args.source, args.acc, args.sat_stage, args.points, args.date)
    else:
        cmd_status()


if __name__ == "__main__":
    main()
