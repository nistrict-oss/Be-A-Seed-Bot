import time
from datetime import datetime, timezone, timedelta
from event_schedule import get_cycle_info

# Current time in MDT (UTC-6)
# 2026-06-18 00:38:00 MDT
dt = datetime(2026, 6, 18, 0, 38, 0, tzinfo=timezone(timedelta(hours=-6)))
now = int(dt.timestamp())

cycle_index, event, phase, sec_left = get_cycle_info(now)
print(f"Cycle: {cycle_index}")
print(f"Event: {event}")
print(f"Phase: {phase}")
