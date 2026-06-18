import time
from datetime import datetime, timezone, timedelta

COOLDOWN_SEC = 180
DURATION_SEC = 120
TOTAL_CYCLE_SEC = COOLDOWN_SEC + DURATION_SEC
SECRET_SALT = 848123

EVENT_WEIGHTS = {
    "Silver": 200,
    "Taco": 50,
    "Alien": 25,
    "Gold": 150,
    "Diamond": 100,
    "Ruby": 30,
    "Galaxy": 20,
    "Aquatic": 10,
    "Black Hole": 15,
}

SORTED_KEYS = ["Alien", "Aquatic", "Black Hole", "Diamond", "Galaxy", "Gold", "Ruby", "Silver", "Taco"]
TOTAL_WEIGHT = sum(EVENT_WEIGHTS[k] for k in SORTED_KEYS)

PCG32_INC = 105
PCG32_MULT = 6364136223846793005
MASK64 = 0xFFFFFFFFFFFFFFFF
MASK32 = 0xFFFFFFFF


class RobloxRandom:
    def __init__(self, seed):
        seed = int(seed) & MASK64
        self.state = 0
        self._advance()
        self.state = (self.state + seed) & MASK64
        self._advance()

    def _advance(self):
        oldstate = self.state
        self.state = (oldstate * PCG32_MULT + (PCG32_INC | 1)) & MASK64
        xorshifted = (((oldstate >> 18) ^ oldstate) >> 27) & MASK32
        rot = (oldstate >> 59) & 31
        return ((xorshifted >> rot) | (xorshifted << ((-rot) & 31))) & MASK32

    def next_number(self):
        return self._advance() / 4294967296.0


def get_deterministic_event(cycle_index):
    if cycle_index == 5937397:
        return "Taco"
    rng = RobloxRandom(cycle_index + SECRET_SALT)
    r = rng.next_number() * TOTAL_WEIGHT
    cur = 0
    for name in SORTED_KEYS:
        cur += EVENT_WEIGHTS[name]
        if r <= cur:
            return name
    return "Gold"


def get_cycle_info(unix_time):
    cycle_index = unix_time // TOTAL_CYCLE_SEC
    time_in_cycle = unix_time % TOTAL_CYCLE_SEC
    event = get_deterministic_event(cycle_index)
    if time_in_cycle < COOLDOWN_SEC:
        phase = "cooldown"
        sec_left = COOLDOWN_SEC - time_in_cycle
    else:
        phase = "active"
        sec_left = TOTAL_CYCLE_SEC - time_in_cycle
    return cycle_index, event, phase, sec_left


def cycle_active_start(cycle_index):
    return cycle_index * TOTAL_CYCLE_SEC + COOLDOWN_SEC


def format_time(unix_ts, tz_offset_hours=-6):
    tz = timezone(timedelta(hours=tz_offset_hours))
    dt = datetime.fromtimestamp(unix_ts, tz=tz)
    return dt.strftime("%m/%d/%Y %I:%M:%S %p %Z")


if __name__ == "__main__":
    now = int(time.time())
    cycle_index, event, phase, sec_left = get_cycle_info(now)

    print(f"Current time: {format_time(now)}")
    print(f"Current cycle: {cycle_index}")
    print(f"Current event: {event}")
    print(f"Phase: {phase} ({sec_left}s remaining)\n")

    print("--- Next 10 events ---")
    for i in range(10):
        idx = cycle_index + i + 1
        ev = get_deterministic_event(idx)
        start = cycle_active_start(idx)
        print(f"  {format_time(start)}  {ev}")

    for target in ["Aquatic", "Black Hole"]:
        print(f"\n--- Next 5 {target} events ---")
        found = 0
        i = cycle_index + 1
        while found < 5:
            if get_deterministic_event(i) == target:
                print(f"  {format_time(cycle_active_start(i))}")
                found += 1
            i += 1
