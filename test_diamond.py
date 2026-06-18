MASK64 = 0xFFFFFFFFFFFFFFFF
MASK32 = 0xFFFFFFFF
PCG32_MULT = 6364136223846793005
PCG32_INC = 105

def pcg32_next(state, inc):
    state = (state * PCG32_MULT + inc) & MASK64
    xorshifted = (((state >> 18) ^ state) >> 27) & MASK32
    rot = (state >> 59) & 31
    out = ((xorshifted >> rot) | (xorshifted << ((-rot) & 31))) & MASK32
    return state, out

seed = 5939215 + 848123

# Standard 1 advance
st = 0
inc = PCG32_INC | 1
st, _ = pcg32_next(st, inc)
st = (st + seed) & MASK64
st, _ = pcg32_next(st, inc)

st, out = pcg32_next(st, inc)
val1 = out / 4294967296.0
print(f"1 advance: {val1}")

# 2 advances (53-bit)
st = 0
st, _ = pcg32_next(st, inc)
st = (st + seed) & MASK64
st, _ = pcg32_next(st, inc)

st, out1 = pcg32_next(st, inc)
st, out2 = pcg32_next(st, inc)
val2 = (out1 * 4294967296.0 + out2) / 18446744073709551616.0
print(f"2 advances: {val2}")

def get_event(val):
    r = val * 600
    if r <= 25: return "Alien"
    elif r <= 35: return "Aquatic"
    elif r <= 50: return "Black Hole"
    elif r <= 150: return "Diamond"
    elif r <= 170: return "Galaxy"
    elif r <= 320: return "Gold"
    elif r <= 350: return "Ruby"
    elif r <= 550: return "Silver"
    else: return "Taco"

print(f"Event (1 advance): {get_event(val1)}")
print(f"Event (2 advances): {get_event(val2)}")
