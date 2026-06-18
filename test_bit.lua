local ffi = require("ffi")
local bit = require("bit")

local oldstate = ffi.cast("uint64_t", 1234567890123456789ULL)
local a = bit.rshift(oldstate, 18)
local b = bit.bxor(a, oldstate)
print(tonumber(a), tonumber(b))
