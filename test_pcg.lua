local ffi = require("ffi")
local bit = require("bit")

local function RobloxRandom(seed)
    local self = {}
    self.state = ffi.new("uint64_t[1]")
    self.state[0] = 0ULL
    
    local MASK64 = ffi.cast("uint64_t", 0xFFFFFFFFFFFFFFFFULL)
    local MULT = ffi.cast("uint64_t", 6364136223846793005ULL)
    local INC = ffi.cast("uint64_t", 105ULL)
    
    local function advance()
        local oldstate = self.state[0]
        self.state[0] = oldstate * MULT + INC
        
        -- get hi and lo parts (little endian)
        local old_arr = ffi.new("uint64_t[1]", oldstate)
        local ptr = ffi.cast("uint32_t*", old_arr)
        local old_lo = ptr[0]
        local old_hi = ptr[1]
        
        -- oldstate >> 18
        local shifted18_hi = bit.rshift(old_hi, 18)
        local shifted18_lo = bit.bor(bit.rshift(old_lo, 18), bit.lshift(old_hi, 32 - 18))
        
        local xor_hi = bit.bxor(shifted18_hi, old_hi)
        local xor_lo = bit.bxor(shifted18_lo, old_lo)
        
        -- >> 27 of XOR
        local xorshifted = bit.bor(bit.rshift(xor_lo, 27), bit.lshift(xor_hi, 32 - 27))
        
        -- rot = oldstate >> 59
        local rot = bit.rshift(old_hi, 59 - 32)
        
        -- return
        local neg_rot = bit.band(-rot, 31)
        local res = bit.bor(bit.rshift(xorshifted, rot), bit.lshift(xorshifted, neg_rot))
        
        return ffi.cast("uint32_t", res)
    end
    
    self.advance = advance
    
    local seed_u64 = ffi.cast("uint64_t", seed)
    self.advance()
    self.state[0] = self.state[0] + seed_u64
    self.advance()
    
    function self.next_number()
        local n = tonumber(self.advance())
        if n < 0 then n = n + 4294967296 end
        return n / 4294967296.0
    end
    
    return self
end

local rng = RobloxRandom(5937398 + 848123)
print("1st:", rng.next_number())
print("2nd:", rng.next_number())
