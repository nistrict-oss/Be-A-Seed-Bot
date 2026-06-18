from datetime import datetime, timezone, timedelta
from event_schedule import get_cycle_info, get_deterministic_event, RobloxRandom, TOTAL_WEIGHT

dt = datetime(2026, 6, 18, 0, 38, 0, tzinfo=timezone(timedelta(hours=-6)))
now = int(dt.timestamp())
cycle = now // 300

rng = RobloxRandom(cycle + 848123)
val = rng.next_number()
r = val * TOTAL_WEIGHT

print(f"Timestamp: {now}")
print(f"Cycle: {cycle}")
print(f"RNG value: {val}")
print(f"R: {r}")
print(f"Event: {get_deterministic_event(cycle)}")
