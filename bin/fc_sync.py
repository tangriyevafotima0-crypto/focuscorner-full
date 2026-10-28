#!/usr/bin/env python3
"""
fc_sync.py — CLI Synergy & Backup Bridge for FocusCorner v5.2
Allows external terminal or internal scripts to inspect status, append tasks,
create backups, or sync today's Oct 18 tasks while FocusCorner live-reloads.
"""
import argparse
import datetime
import json
import os
import shutil
import uuid
from pathlib import Path

BASE_DIR = Path.home() / ".focus_corner"
BACKUPS_DIR = BASE_DIR / "backups"
TASKS_FILE = BASE_DIR / "tasks.json"
SAT_FILE = BASE_DIR / "sat_tracker.json"
EXACC_FILE = BASE_DIR / "exacc.json"
HISTORY_FILE = BASE_DIR / "history.md"


def load_json(path: Path, default):
    if path.exists():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if path == TASKS_FILE and isinstance(data, dict) and "tasks" in data:
                return data["tasks"]
            return data
        except Exception:
            return default
    return default


def atomic_save_json(path: Path, data):
    BASE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    tmp.replace(path)


def create_cli_backup(reason="CLI Sync"):
    BACKUPS_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    snap_dir = BACKUPS_DIR / f"snapshot_{stamp}"
    snap_dir.mkdir(parents=True, exist_ok=True)
    for fname in ["tasks.json", "sat_tracker.json", "exacc.json", "rules.json", "settings.json", "history.md"]:
        src = BASE_DIR / fname
        if src.exists():
            shutil.copy2(src, snap_dir / fname)
    nb_src = BASE_DIR / "notebook"
    if nb_src.exists():
        shutil.copytree(nb_src, snap_dir / "notebook", dirs_exist_ok=True)
    return snap_dir


def cmd_status():
    sat = load_json(SAT_FILE, {})
    exacc = load_json(EXACC_FILE, {})
    tasks = load_json(TASKS_FILE, [])
    topics = sat.get("topics", [])
    base_m = sat.get("baseMathScore", 200)
    base_rw = sat.get("baseRWScore", 200)
    math_score = base_m + sum(t.get("currentScore", 0) for t in topics if "Math" in t.get("section", ""))
    rw_score = base_rw + sum(t.get("currentScore", 0) for t in topics if "Reading" in t.get("section", ""))
    total_sat = int(round(min(800, math_score) + min(800, rw_score)))
    charge = exacc.get("totalStandardCharge", 170)
    pending = [t for t in tasks if not t.get("isCompleted", False)]

    print("=== FocusCorner v5.2 Synergy & Backup Status ===")
    print(f"SAT Score      : {total_sat} / 1600 (Math: {int(round(math_score))} | R&W: {int(round(rw_score))})")
    print(f"ExAcc Charge   : {charge} ball")
    print(f"Pending Tasks  : {len(pending)} ta")
    for t in pending[:10]:
        print(f"  - [{t.get('sourceSystem', t.get('category', 'GENERAL'))}] {t.get('title')} (Due: {t.get('scheduledDate', t.get('deadline', ''))})")


def cmd_sync_today():
    create_cli_backup("Pre-Sync Today")
    today_str = datetime.date.today().isoformat()
    tomorrow_str = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
    four_days_str = (datetime.date.today() + datetime.timedelta(days=4)).isoformat()
    now_iso = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    tasks = [
        {
            "id": str(uuid.uuid5(uuid.NAMESPACE_DNS, "oct18-sat-sr-1")).upper(),
            "title": "[SAT SR] Day 7: Transitions (+10.5) | Day 1: Exponential (+14)",
            "isCompleted": False,
            "createdAt": now_iso,
            "sourceSystem": "SAT",
            "accumulatorSize": "SMALL",
            "satStage": "DAY_7",
            "scheduledDate": today_str,
            "startDate": today_str,
            "durationDays": 1,
            "manualElapsedDaysOffset": 0,
            "pointsValue": 24.5,
            "notes": "17:00 – 18:30 Spaced Repetition bloki"
        },
        {
            "id": str(uuid.uuid5(uuid.NAMESPACE_DNS, "oct18-sat-math-quad")).upper(),
            "title": "[SAT Math] Quadratic Functions & Parabolas — Deep Focus (+24 ball)",
            "isCompleted": False,
            "createdAt": now_iso,
            "sourceSystem": "SAT",
            "accumulatorSize": "BIG",
            "satStage": "INGEST",
            "scheduledDate": today_str,
            "startDate": today_str,
            "durationDays": 1,
            "manualElapsedDaysOffset": 0,
            "pointsValue": 24.0,
            "notes": "18:45 – 19:45 Sunday Buffer mavzusi"
        },
        {
            "id": str(uuid.uuid5(uuid.NAMESPACE_DNS, "oct18-ae-checkin")).upper(),
            "title": "⚡ A&E Check-in: SAT Mani Acc (Audit & Scoring)",
            "isCompleted": False,
            "createdAt": now_iso,
            "sourceSystem": "EXACC",
            "accumulatorSize": "SMALL",
            "satStage": "NONE",
            "scheduledDate": today_str,
            "startDate": today_str,
            "durationDays": 1,
            "manualElapsedDaysOffset": 0,
            "pointsValue": 10.0,
            "notes": "20:00 – 20:30 Haftalik audit"
        },
        {
            "id": str(uuid.uuid5(uuid.NAMESPACE_DNS, "oct18-invest-buffer")).upper(),
            "title": "ExAcc: Sunday Buffer — Invest Midi Acc (Haftalik sarhisob)",
            "isCompleted": False,
            "createdAt": now_iso,
            "sourceSystem": "EXACC",
            "accumulatorSize": "SMALL",
            "satStage": "NONE",
            "scheduledDate": today_str,
            "startDate": today_str,
            "durationDays": 1,
            "manualElapsedDaysOffset": 0,
            "pointsValue": 10.0,
            "notes": "21:45 – 22:15 Investitsiya Midi Acc"
        },
        {
            "id": str(uuid.uuid5(uuid.NAMESPACE_DNS, "oct18-gu-rank1")).upper(),
            "title": "[Gu Rank 1 - Initial] Kun 1: Awakening & Tana Bilan Yarashish",
            "isCompleted": False,
            "createdAt": now_iso,
            "sourceSystem": "GENERAL",
            "accumulatorSize": "SMALL",
            "satStage": "NONE",
            "scheduledDate": today_str,
            "startDate": today_str,
            "durationDays": 1,
            "manualElapsedDaysOffset": 0,
            "pointsValue": 10.0,
            "notes": "22:30 – 23:00 Ichki kultivatsiya bloki"
        },
        {
            "id": str(uuid.uuid5(uuid.NAMESPACE_DNS, "oct19-sat-rw-punct")).upper(),
            "title": "[SAT RW] Boundaries & Punctuation — Deep Focus (Ingest 30%) (+21 ball)",
            "isCompleted": False,
            "createdAt": now_iso,
            "sourceSystem": "SAT",
            "accumulatorSize": "BIG",
            "satStage": "INGEST",
            "scheduledDate": tomorrow_str,
            "startDate": today_str,
            "durationDays": 2,
            "manualElapsedDaysOffset": 0,
            "pointsValue": 21.0,
            "notes": "Dushanba (19-Okt) kuniga ko'chirilgan"
        },
        {
            "id": str(uuid.uuid5(uuid.NAMESPACE_DNS, "oct19-sat-math-ineq")).upper(),
            "title": "[SAT Math] Linear Inequalities & Word Problems — Ingest 30% (+24 ball)",
            "isCompleted": False,
            "createdAt": now_iso,
            "sourceSystem": "SAT",
            "accumulatorSize": "BIG",
            "satStage": "INGEST",
            "scheduledDate": tomorrow_str,
            "startDate": today_str,
            "durationDays": 2,
            "manualElapsedDaysOffset": 0,
            "pointsValue": 24.0,
            "notes": "Dushanba (19-Okt) Math bloki"
        },
        {
            "id": str(uuid.uuid5(uuid.NAMESPACE_DNS, "oct22-exacc-deep")).upper(),
            "title": "[ExAcc] Haftalik Mini-Acc Deep Work Bloki (+25 ball)",
            "isCompleted": False,
            "createdAt": now_iso,
            "sourceSystem": "EXACC",
            "accumulatorSize": "MEDIUM",
            "satStage": "NONE",
            "scheduledDate": four_days_str,
            "startDate": today_str,
            "durationDays": 5,
            "manualElapsedDaysOffset": 0,
            "pointsValue": 25.0,
            "notes": "Payshanba (22-Okt)"
        },
        {
            "id": str(uuid.uuid5(uuid.NAMESPACE_DNS, "done-oct18-linear-d7")).upper(),
            "title": "[SAT] Linear Functions & Systems — Day 7 Review (+12 ball)",
            "isCompleted": True,
            "createdAt": now_iso,
            "sourceSystem": "SAT",
            "accumulatorSize": "SMALL",
            "satStage": "DAY_7",
            "scheduledDate": today_str,
            "startDate": today_str,
            "durationDays": 1,
            "manualElapsedDaysOffset": 0,
            "pointsValue": 12.0,
            "notes": "Bajarildi ✅"
        },
        {
            "id": str(uuid.uuid5(uuid.NAMESPACE_DNS, "done-oct18-words-d1")).upper(),
            "title": "[SAT] Words in Context — Day 1 Review (+8 ball)",
            "isCompleted": True,
            "createdAt": now_iso,
            "sourceSystem": "SAT",
            "accumulatorSize": "SMALL",
            "satStage": "DAY_1",
            "scheduledDate": today_str,
            "startDate": today_str,
            "durationDays": 1,
            "manualElapsedDaysOffset": 0,
            "pointsValue": 8.0,
            "notes": "Bajarildi ✅"
        },
        {
            "id": str(uuid.uuid5(uuid.NAMESPACE_DNS, "done-oct18-inv-init")).upper(),
            "title": "[GENERAL] Investment Accni yaratish va boshlash",
            "isCompleted": True,
            "createdAt": now_iso,
            "sourceSystem": "GENERAL",
            "accumulatorSize": "NONE",
            "satStage": "NONE",
            "scheduledDate": today_str,
            "startDate": today_str,
            "durationDays": 1,
            "manualElapsedDaysOffset": 0,
            "pointsValue": 0.0,
            "notes": "Bajarildi ✅"
        },
        {
            "id": str(uuid.uuid5(uuid.NAMESPACE_DNS, "done-oct18-nevroz-init")).upper(),
            "title": "[GENERAL] Nevroz Acc yaratish va boshlash",
            "isCompleted": True,
            "createdAt": now_iso,
            "sourceSystem": "GENERAL",
            "accumulatorSize": "NONE",
            "satStage": "NONE",
            "scheduledDate": today_str,
            "startDate": today_str,
            "durationDays": 1,
            "manualElapsedDaysOffset": 0,
            "pointsValue": 0.0,
            "notes": "Bajarildi ✅"
        },
        {
            "id": str(uuid.uuid5(uuid.NAMESPACE_DNS, "done-oct18-gu-init")).upper(),
            "title": "[GENERAL] GU Tizimini yaratish",
            "isCompleted": True,
            "createdAt": now_iso,
            "sourceSystem": "GENERAL",
            "accumulatorSize": "NONE",
            "satStage": "NONE",
            "scheduledDate": today_str,
            "startDate": today_str,
            "durationDays": 1,
            "manualElapsedDaysOffset": 0,
            "pointsValue": 0.0,
            "notes": "Bajarildi ✅"
        }
    ]

    atomic_save_json(TASKS_FILE, tasks)
    print(f"🚀 Bugungi ({today_str}) 5 ta faol vazifa, Dushanbalik 2 ta SAT vazifa va 5 ta bajarilgan vazifa FocusCorner oynasiga jonli uzatildi!")


def main():
    parser = argparse.ArgumentParser(description="FocusCorner v5.2 CLI Synergy Bridge")
    sub = parser.add_subparsers(dest="cmd")

    sub.add_parser("status", help="Show current SAT, ExAcc, and Task status")
    sub.add_parser("sync-today", help="Sync today's Oct 18 tasks to FocusCorner")
    sub.add_parser("backup", help="Create a full snapshot backup in ~/.focus_corner/backups")

    args = parser.parse_args()
    if args.cmd == "sync-today":
        cmd_sync_today()
    elif args.cmd == "backup":
        snap = create_cli_backup("CLI Manual Backup")
        print(f"🛡 Zahira nusxa yaratildi: {snap}")
    else:
        cmd_status()


if __name__ == "__main__":
    main()
