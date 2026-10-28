#!/usr/bin/env python3
"""
FocusCorner v6.5 CLI Sync & Backup Tool (fc_sync.py)
Supports: status, rpa, sync-today, backup, restore, doctor
"""
import datetime
import json
import shutil
import sys
import uuid
from pathlib import Path

BASE_DIR = Path.home() / ".focus_corner"
BACKUPS_DIR = BASE_DIR / "backups"
TASKS_FILE = BASE_DIR / "tasks.json"
SAT_FILE = BASE_DIR / "sat_tracker.json"
EXACC_FILE = BASE_DIR / "exacc.json"
RULES_FILE = BASE_DIR / "rules.json"
RPA_ARCHIVE_FILE = BASE_DIR / "rpa_archive.json"
RPA_HISTORY_FILE = BASE_DIR / "rpa_history.md"
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
    for fname in [
        "tasks.json",
        "sat_tracker.json",
        "exacc.json",
        "rules.json",
        "rpa_archive.json",
        "rpa_history.md",
        "settings.json",
        "history.md",
    ]:
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
    rules = load_json(RULES_FILE, [])
    topics = sat.get("topics", [])
    base_m = sat.get("baseMathScore", 208)
    base_rw = sat.get("baseRWScore", 233.5)
    math_score = base_m + sum(t.get("currentScore", 0) for t in topics if "Math" in t.get("section", ""))
    rw_score = base_rw + sum(t.get("currentScore", 0) for t in topics if "Reading" in t.get("section", ""))
    total_sat = int(round(min(800, math_score) + min(800, rw_score)))
    charge = exacc.get("totalStandardCharge", 230)
    pending = [t for t in tasks if not t.get("isCompleted", False)]

    today_str = datetime.date.today().isoformat()
    x_today = sum(1 for r in rules if isinstance(r, dict) and today_str in r.get("xMarkedDates", []))
    total_r = max(1, len(rules))
    no_err = int(round(20.0 * max(0, total_r - x_today) / total_r))

    print("=== FocusCorner v6.5 Synergy, RPA & Backup Status ===")
    print(f"SAT Score      : {total_sat} / 1600 (Math: {int(round(math_score))} | R&W: {int(round(rw_score))})")
    print(f"ExAcc Charge   : {charge} ball")
    print(f"Gu No-Error    : {no_err} / 20% (Bugun: {x_today} ta X)")
    print(f"Pending Tasks  : {len(pending)} ta")
    for t in pending[:10]:
        print(f"  - [{t.get('sourceSystem', 'GENERAL')}] {t.get('title')} (Due: {t.get('scheduledDate', '')})")


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else "status"
    if arg in ("backup", "--backup"):
        snap = create_cli_backup("Manual CLI")
        print(f"✅ Backup saved to: {snap}")
    else:
        cmd_status()
