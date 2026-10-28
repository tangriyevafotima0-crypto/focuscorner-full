# FocusCorner v2.0 — Synergy Edition (macOS Native HUD)
**ExAcc (`@exacc` / `@accumulation-system`) + Score SAT (`@score-sat-system`) + RPA Engine (`Do & Don't`)**

FocusCorner v2.0 — macOS (Ventura, Sonoma, Sequoia) uchun maxsus Swift 5.9+ (SwiftUI + AppKit `NSPanel`) asosida qurilgan ultra-yengil (<25MB RAM, 0.0% idle CPU) ish stoli ustki qatlami (Always-On-Top HUD).

## 1. Asosiy Yangiliklar va Sinergiya Arxitekturasi (v2.0)

1. **Uchta Tizim Sinergiyasi:**
   - **RPA HUD (Pinned Corner — Do & Don't Tanbehlar):** Ekranning 4 burchagidan biriga mahkamlanadigan (`topRight`, `topLeft`, `bottomRight`, `bottomLeft`), o'zgarmas qoidalar (`🔒 Lock`) va **ExAcc Xavfsizlik Protokollari** (`Hard Stop 00:30`, `Launch Window 14:00`, `WIP Limit <= 2`, `Sunday Buffer`) jonli indikatori.
   - **Score SAT System (`@score-sat-system`):** Ebbinghaus oraliq takrorlash (`Ingest 30%`, `Day 1 +20%`, `Day 3 +20%`, `Day 7/14 +15%`, `Day 30 +15%`), **Qat'iy Sana va Interval Filtri** (kelajakdagi takrorlashni muddatidan oldin tasodifan yopishni bloklaydi) hamda **Mock Xato (-30% Fast-Track Recovery)** avtomatik generatori.
   - **ExAcc & Accumulation (`@exacc`):** Missiyalar (`Monumental`, `Substantial`, `Modest`), Acc (`Nano`, `Mini`, `Midi`, `Mani`), Volume (`Smooth`, `Peak`, `Upper`), kunlik akkumulyatorlar (`Small +10`, `Medium +25`, `Big +50`) va **Faction Isolation** (SAT ballarini standart ExAcc ballari bilan aralashtirmasdan Read-Only Observer rejimida kuzatish).
2. **`history.md` va Foydalanuvchi Ma'lumotlarining 100% Daxlsizligi:**
   - `~/.focus_corner/history.md` faqat **append-only** (oxiridan qo'shish) rejimida ishlaydi — hech qanday yangilanish uni o'chirmaydi.
   - Har safar `./run.sh` yoki `./scripts/update.sh` ishga tushganda `~/.focus_corner/backups/snapshot_YYYYMMDD_HHMMSS/` ichiga avtomatik zahira nusxa olinadi.
   - v1 formatdagi `rules.json`, `tasks.json` va `settings.json` fayllari avtomatik ravishda xatosiz o'qiladi.
3. **Maksimal Qulaylik (User Comfort & Window Control):**
   - **Har qanday oyna va Full-Screen ustida ko'rinish:** `.canJoinAllSpaces`, `.fullScreenAuxiliary` va `hidesOnDeactivate = false` orqali barcha virtual ish stollarida (Spaces) va to'liq ekranli ilovalar ustida yo'qolib qolmasdan turadi.
   - **Vaqtinchalik Ko'rinmas Qilish (Stealth & Snooze Timer):** `5m`, `15m`, `30m`, `60m` taymer bilan vaqtincha yashirish (vaqt tugashi bilan o'zi avtomatik qaytib chiqadi!) yoki `Cmd + Shift + H` bilan tezkor yashirish/ko'rsatish.
   - **Ghost Click-Through Rejimi (`Cmd + Shift + G`):** Oynalar shaffofligini 22% ga tushirib, myshka bosishlarini HUD ustidan to'g'ridan-to'g'ri orqadagi kod yoki brauzerga o'tkazib yuboradi.
   - **Erkin O'lchamni O'zgartirish (Resize) va Yig'ish (Mini-Pill Collapse):** Har ikkala oynaning pastki o'ng burchagidan tortib o'lchamini o'zgartirish, `S / M / L` tayyor o'lchamlar, `A- / A+` shrift masshtabi va bitta tugma bilan 44px mini-kapsula holatiga yig'ish.

## 2. O'rnatish va Smooth Yangilash (1-Click)

Terminalda loyiha papkasiga kirib quyidagi bitta buyruqni bering:

```bash
chmod +x run.sh scripts/*.sh
./run.sh
```

- **Release (Stable) kanalida yangilash va 400MB+ `.build` keshni avtomatik tozalash:**
  ```bash
  ./run.sh --release
  ```
- **Development (Tezkor dasturlash) kanalida ishga tushirish:**
  ```bash
  ./run.sh --dev
  ```
- **Terminal orqali jonli task qo'shish yoki statusni ko'rish:**
  ```bash
  python3 scripts/fc_sync.py status
  python3 scripts/fc_sync.py add-task "[SAT Math] Exponential Functions — Day 1 Review" --source SAT --sat-stage DAY_1 --points 14
  ```

## 3. Global Klaviatura Qisqartmalari (Hotkeys)

- `Cmd + Shift + F` — Tasklar & Synergy HUD oynasini yashirish / ko'rsatish
- `Cmd + Shift + R` — RPA Qoidalar HUD oynasini yashirish / ko'rsatish
- `Cmd + Shift + H` — Ikkala oynani birdaniga vaqtincha yashirish / qaytarish (Stealth Mode)
- `Cmd + Shift + G` — Ghost Click-Through rejimi (myshka HUD orqali o'tadi)
