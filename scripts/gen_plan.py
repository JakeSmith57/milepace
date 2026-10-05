"""Generates MilePace/Resources/plan.json. Edit W and rerun: python3 scripts/gen_plan.py"""
import re, json, datetime as dt

START = dt.date(2026, 10, 12)      # Monday, week 1
RACE = dt.date(2027, 6, 21)        # Monday after week 36
VERSION = 2
TT_TARGET = {14: ("6:35", 1), 24: ("6:05", 2), 33: ("5:45", 3)}
PHASE_END = [14, 24, 33, 36]       # phases: build legs / aerobic power / mile-specific / sharpen

def tt(n): return ("4×200 @ R, otherwise easy", "TT", None, "tt")
# (week, miles, workout1 (Tue), workout2 (Thu wks 1-12, Fri from 13), Sat long, flag)
W = [
 (1, 5, "1.5 E", "1.5 E", 2, ""),
 (2, 6, "2 E", "2 E", 2, ""),
 (3, 7, "2 E + 4×15s strides", "2 E", 3, ""),
 (4, 5, "1.5 E", "1.5 E", 2, "down"),
 (5, 8, "2.5 E + 4 strides", "2.5 E", 3, ""),
 (6, 9, "3 E + 4 strides", "3 E", 3, ""),
 (7, 10, "3 E + 6 strides", "3 E", 4, ""),
 (8, 8, "2.5 E + 4 strides", "2.5 E", 3, "down"),
 (9, 11, "3 E + 6 strides", "3 E + 4×8s hill sprints", 3, ""),
 (10, 12, "3 E + 6 strides", "3 E + 6 hill sprints", 4, ""),
 (11, 13, "3 E + 6 strides", "3 E + 6 hill sprints", 4, ""),
 (12, 11, "2.5 E + 4 strides", "2.5 E + 4 hill sprints", 3, "down"),
 (13, 15, "3×5 min @ T (2 min jog)", "6×200 @ R (200 jog)", 5, ""),
 (14, 13, None, None, None, "tt"),
 (15, 17, "4×6 min @ T (2 min jog)", "6×200 @ R (200 jog)", 5, ""),
 (16, 19, "5×800 @ I (2 min jog)", "3×8 min @ T (2 min jog)", 6, ""),
 (17, 21, "5×1000 @ I (2–3 min jog)", "8×200 @ R (200 jog)", 6, ""),
 (18, 16, "3×1 mi @ T (1 min jog)", "6×200 @ R", 5, "down"),
 (19, 22, "6×800 @ I (2 min jog)", "20 min tempo @ T", 7, ""),
 (20, 24, "5×1000 @ I", "6×400 @ R (400 jog)", 7, ""),
 (21, 25, "4×1200 @ I (3 min jog)", "3×1.5 mi @ T (2 min jog)", 7, ""),
 (22, 20, "5×800 @ I", "6×200 @ R", 6, "down"),
 (23, 26, "5×1200 @ I (3 min jog)", "2×15 min @ T (3 min jog)", 8, ""),
 (24, 21, None, None, None, "tt"),
 (25, 25, "6×400 @ R (400 jog)", "20 min @ T + 4×200 fast", 8, ""),
 (26, 26, "5×1000 @ I", "10×200 @ goal pace, 41s (200 jog)", 8, ""),
 (27, 27, "8×400 @ R (300 jog)", "2×12 min @ T (2 min jog)", 8, ""),
 (28, 21, "3 sets of 3×300 @ R (100 walk; 4 min between sets)", "15 min tempo @ T", 6, "down"),
 (29, 28, "4 sets of 2×400 @ 84s (60s rest; 4 min between sets)", "5×1000 @ I", 8, ""),
 (30, 28, "2 sets of 4×400 @ 83s (60s rest; 5 min between sets)", "3×800 @ I + 4×200 @ 39–40s", 8, ""),
 (31, 27, "3×600 @ 2:05 (5 min rest) + 4×200 @ 39s", "2×10 min @ T", 7, ""),
 (32, 22, "12×200 @ goal pace, 41s", "3×1 mi @ T", 6, "down"),
 (33, 21, None, None, None, "tt"),
 (34, 24, "1200 @ 4:12 (84s/400), 5 min rest, 4×200 @ 38–39s", "2×10 min @ T", 7, ""),
 (35, 22, "4×400 @ 81–82s (3 min full rest)", "4×1000 @ I", 6, ""),
 (36, 15, None, None, None, "raceweek"),
]
road = {r"^3×5 min @ T":"3 × 5 min threshold", r"^4×5 min @ T \(2":"4 × 5 min threshold",
 r"^4×6 min @ T":"4 × 6 min threshold", r"^3×8 min @ T":"3 × 8 min threshold", r"^3×1 mi @ T":"3 × 1 mi threshold",
 r"^3×1\.5 mi @ T":"3 × 1.5 mi threshold", r"^20 min tempo":"20 min tempo", r"^20 min @ T":"20 min tempo",
 r"^2×15 min @ T":"2 × 15 min threshold", r"^2×12 min @ T":"2 × 12 min threshold", r"^15 min tempo":"15 min tempo",
 r"^15 min @ T":"15 min tempo", r"^2×10 min @ T":"2 × 10 min threshold"}
track = {r"^6×200 @ R":"6x200-r", r"^8×200 @ R":"8x200-r", r"^10×200 @ R":"10x200-r", r"^10×200 @ goal":"10x200-goal",
 r"^12×200 @ goal":"12x200-goal", r"^6×400 @ R":"6x400-r", r"^8×400 @ R":"8x400-r", r"^5×800 @ I":"5x800-i",
 r"^6×800 @ I":"6x800-i", r"^5×1000 @ I":"5x1000-i", r"^6×1000 @ I":"6x1000-i", r"^4×1000 @ I":"4x1000-i",
 r"^4×1200 @ I":"4x1200-i", r"^5×1200 @ I":"5x1200-i", r"^3 sets of 3×300":"3s-3x300-r",
 r"^4 sets of 2×400":"4s-2x400-84", r"^2 sets of 4×400":"2s-4x400-83", r"^3×600 @ 2:05":"3x600-125",
 r"^3×800 @ I":"3x800-i", r"^6×400 @ 82":"6x400-82", r"^4×400 @ 81":"4x400-82", r"^1200 @ 4:12":"1x1200-412",
 r"^600 @ 2:02":"sharpener", r"^3×400 @ goal":"3x400-goal"}

def phase_of(n):
    for i, end in enumerate(PHASE_END):
        if n <= end: return i + 1
    return 4

def classify(t):
    m = re.match(r"^([\d.]+) E(.*)", t)
    if m:
        note = m.group(2).strip(" +") or None
        return dict(kind="easy", miles=float(m.group(1)), title=f"{m.group(1)} mi easy", note=note)
    for k, v in road.items():
        if re.match(k, t): return dict(kind="road", preset=v, title=v, note=t)
    for k, v in track.items():
        if re.match(k, t): return dict(kind="track", preset=v, title=t.split(" (")[0], note=t)
    raise SystemExit(f"unmatched workout: {t}")

def easy(mi, note=None): return dict(kind="easy", miles=mi, title=f"{mi:g} mi easy", note=note)
def long(mi): return dict(kind="long", miles=float(mi), title=f"{mi:g} mi long, easy")

days = []
def add(week, wd, d):
    d = {k: v for k, v in d.items() if v is not None}
    d.update(week=week, weekday=wd, phase=phase_of(week)); days.append(d)

for (n, mi, t1, t2, lr, flag) in W:
    if flag == "tt":
        target, k = TT_TARGET[n]
        add(n, 1, easy(3.0 if n > 13 else 2.0)); add(n, 2, easy(3.0, "with 4 × 200 @ R"))
        add(n, 4, easy(2.5, "+ 4 strides")); add(n, 5, easy(2.0, "easy + 4 strides, keep it short"))
        m, ss = target.split(":")
        add(n, 6, dict(kind="timeTrial", preset="mile-tt", title=f"mile time trial #{k}", note=f"target ≤ {target}",
                       targetSeconds=int(m) * 60 + int(ss)))
        continue
    if flag == "raceweek":
        add(n, 1, easy(3.0, "+ 4 strides"))
        add(n, 2, classify("600 @ 2:02, 400 @ 80s, 2×200 @ 38s (full rest)"))
        add(n, 4, easy(2.5, "+ 4 strides"))
        add(n, 5, classify("3×400 @ goal pace + 3×200 relaxed-fast"))
        add(n, 6, easy(2.0, "shakeout. no tennis or hard riding until after the race"))
        continue
    a, b = classify(t1), classify(t2)
    if n <= 8:
        add(n, 2, a); add(n, 4, b); add(n, 6, long(lr))
    elif n <= 12:
        fill = max(1.5, mi - a.get("miles", 3) - b.get("miles", 3) - lr)
        add(n, 1, easy(fill)); add(n, 2, a); add(n, 4, b); add(n, 6, long(lr))
    else:
        wk = 3.5 if n < 17 else 4.0
        fill = round(max(2.0, (mi - lr - 2 * wk) / 2) * 2) / 2
        add(n, 1, easy(fill)); add(n, 2, a); add(n, 4, easy(fill, "+ 4–6 strides")); add(n, 5, b); add(n, 6, long(lr))

race_week = (RACE - START).days // 7 + 1
race_wd = RACE.weekday() + 1
add(race_week, race_wd, dict(kind="race", preset="mile-tt", title="goal race: 5:30 mile", note="race day. full warm-up, even laps.", targetSeconds=330))
weeks = [dict(week=n, miles=mi, phase=phase_of(n), recovery=(flag == "down"), timeTrial=(flag == "tt"), race=False)
         for (n, mi, *_rest, flag) in W]
weeks.append(dict(week=race_week, miles=2.5, phase=4, recovery=False, timeTrial=False, race=True))
plan = dict(name="5:30 mile plan", version=VERSION, startDate=START.isoformat(), raceDate=RACE.isoformat(),
            weeks=weeks, sessions=days)
json.dump(plan, open("MilePace/Resources/plan.json", "w"), ensure_ascii=False, indent=1)
print(len(weeks), "weeks,", len(days), "sessions; race week", race_week, "weekday", race_wd)
