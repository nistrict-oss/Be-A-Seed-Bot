local discordia = require("discordia")
local timer = require("timer")
local ffi = require("ffi")
local bit = require("bit")

-- FFI PCG32 implementation mimicking Roblox's Random.new (53-bit precision)
local function RobloxRandom(seed)
    local self = {}
    self.state = ffi.new("uint64_t[1]", 0ULL)
    
    local MULT = ffi.cast("uint64_t", 6364136223846793005ULL)
    local INC = ffi.cast("uint64_t", 105ULL)
    
    local function advance()
        -- Advance state FIRST, then compute output from new state
        self.state[0] = self.state[0] * MULT + INC
        local cur_state = self.state[0]
        
        local cur_arr = ffi.new("uint64_t[1]", cur_state)
        local ptr = ffi.cast("uint32_t*", cur_arr)
        local cur_lo = ptr[0]
        local cur_hi = ptr[1]
        
        local shifted18_hi = bit.rshift(cur_hi, 18)
        local shifted18_lo = bit.bor(bit.rshift(cur_lo, 18), bit.lshift(cur_hi, 32 - 18))
        
        local xor_hi = bit.bxor(shifted18_hi, cur_hi)
        local xor_lo = bit.bxor(shifted18_lo, cur_lo)
        
        local xorshifted = bit.bor(bit.rshift(xor_lo, 27), bit.lshift(xor_hi, 32 - 27))
        
        local rot = bit.rshift(cur_hi, 59 - 32)
        local neg_rot = bit.band(-rot, 31)
        local res = bit.bor(bit.rshift(xorshifted, rot), bit.lshift(xorshifted, neg_rot))
        
        return ffi.cast("uint32_t", res)
    end
    
    -- Initialization
    advance()
    self.state[0] = self.state[0] + ffi.cast("uint64_t", seed)
    advance()
    
    function self.next_number()
        -- Roblox NextNumber generates a 53-bit float using two 32-bit advances
        local out1 = tonumber(advance())
        if out1 < 0 then out1 = out1 + 4294967296 end
        
        local out2 = tonumber(advance())
        if out2 < 0 then out2 = out2 + 4294967296 end
        
        return (out1 * 4294967296.0 + out2) / 18446744073709551616.0
    end
    
    return self
end

-- Event Schedule Math
local COOLDOWN_SEC = 180
local DURATION_SEC = 120
local TOTAL_CYCLE_SEC = COOLDOWN_SEC + DURATION_SEC
local SECRET_SALT = 848123

local EVENT_WEIGHTS = {
    Silver = 200, Taco = 50, Alien = 25, Gold = 150,
    Diamond = 100, Ruby = 30, Galaxy = 20, Aquatic = 10, ["Black Hole"] = 15, Petalune = 10,
}
local sortedKeys = { "Alien", "Aquatic", "Black Hole", "Diamond", "Galaxy", "Gold", "Petalune", "Ruby", "Silver", "Taco" }
local TOTAL_WEIGHT = 0
for _, k in ipairs(sortedKeys) do TOTAL_WEIGHT = TOTAL_WEIGHT + EVENT_WEIGHTS[k] end

local function getDeterministicEvent(cycleIndex)
    if cycleIndex == 5937397 then return "Taco" end
    
    local rng = RobloxRandom(cycleIndex + SECRET_SALT)
    local r = rng.next_number() * TOTAL_WEIGHT
    local cur = 0
    for _, name in ipairs(sortedKeys) do
        cur = cur + EVENT_WEIGHTS[name]
        if r <= cur then return name end
    end
    return "Gold"
end

local function getCycleInfo(unixTime)
    local cycleIndex = math.floor(unixTime / TOTAL_CYCLE_SEC)
    local timeInCycle = unixTime % TOTAL_CYCLE_SEC
    local event = getDeterministicEvent(cycleIndex)
    local phase, secLeft
    if timeInCycle < COOLDOWN_SEC then
        phase = "cooldown"
        secLeft = COOLDOWN_SEC - timeInCycle
    else
        phase = "active"
        secLeft = TOTAL_CYCLE_SEC - timeInCycle
    end
    return cycleIndex, event, phase, secLeft
end

-- Read Config (.env)
local env = {}
local file = io.open('.env', 'r')
if file then
    for line in file:lines() do
        local k, v = line:match("^([^#=%s]+)=([^#\r\n]+)")
        if k and v then env[k] = v end
    end
    file:close()
end

local EVENT_CHANNEL_ID = env.EVENT_CHANNEL_ID or os.getenv("EVENT_CHANNEL_ID")
local EVENT_ROLE_ID = env.EVENT_ROLE_ID or os.getenv("EVENT_ROLE_ID")
local TOKEN = env.DISCORD_TOKEN or os.getenv("DISCORD_TOKEN")

local EVENT_COLORS = {
    Silver = 0xC0C0C0, Taco = 0xF4A460, Alien = 0x7CFC00, Gold = 0xFFD700,
    Diamond = 0x00BFFF, Ruby = 0xDC143C, Galaxy = 0x8A2BE2, Aquatic = 0x00CED1,
    ["Black Hole"] = 0x1C1C1C, Petalune = 0xFF69B4,
}

local client = discordia.Client()
local lastStartingSoonCycle = -1
local lastActiveCycle = -1

client:on('ready', function()
    print('Logged in as ' .. client.user.username)
    print('Event loop running! (Powered by Luvit & Discordia)')
    
    timer.setInterval(5000, function()
        coroutine.wrap(function()
            local now = os.time()
            local cycleIndex, event, phase, secLeft = getCycleInfo(now)
            local channel = client:getChannel(EVENT_CHANNEL_ID)
            
            if not channel then return end
            
            local color = EVENT_COLORS[event] or 0x808080
            local roleMention = "<@&" .. EVENT_ROLE_ID .. ">"
            
            if phase == "cooldown" and cycleIndex ~= lastStartingSoonCycle then
                lastStartingSoonCycle = cycleIndex
                local content = nil
                if event == "Aquatic" or event == "Black Hole" or event == "Petalune" then
                    content = roleMention
                end
                
                channel:send {
                    content = content,
                    embed = {
                        title = event .. " Event is starting soon!",
                        description = "The **" .. event .. "** event will begin in a few moments. Get ready!",
                        color = color,
                        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
                    }
                }
            end
            
            if phase == "active" and cycleIndex ~= lastActiveCycle then
                lastActiveCycle = cycleIndex
                channel:send {
                    embed = {
                        title = event .. " Event is ACTIVE!",
                        description = "The **" .. event .. "** event has started! Jump in now to participate.",
                        color = color,
                        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
                    }
                }
            end
        end)()
    end)
end)

client:run("Bot " .. TOKEN)
