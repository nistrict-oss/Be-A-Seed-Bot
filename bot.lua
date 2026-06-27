local discordia = require("discordia")
local timer = require("timer")
local ffi = require("ffi")
local bit = require("bit")

-- Discordia 2.13.1 has no native slash-command support. Unknown gateway events
-- fall through EventHandler's metatable, so we hook INTERACTION_CREATE and surface
-- it as a normal client event ('interactionCreate'). The required module resolves
-- to the same cached table the internal Shard uses, so this patch is shared.
do
    local ok, EventHandler = pcall(require, 'discordia/libs/client/EventHandler')
    if not ok then
        ok, EventHandler = pcall(require, './deps/discordia/libs/client/EventHandler.lua')
    end
    if ok and EventHandler then
        EventHandler.INTERACTION_CREATE = function(d, client)
            client:emit('interactionCreate', d)
        end
    else
        print('WARNING: could not hook INTERACTION_CREATE; slash commands will not respond.')
    end
end

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
    Hell = 5, Crystal = 2,
}
local sortedKeys = { "Alien", "Aquatic", "Black Hole", "Crystal", "Diamond", "Galaxy", "Gold", "Hell", "Petalune", "Ruby", "Silver", "Taco" }
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

-- Searches forward from a cycle index for the next cycle whose event matches.
local MAX_SEARCH = 500000
local function findNextOccurrence(targetEvent, fromCycle)
    for i = 0, MAX_SEARCH do
        local ci = fromCycle + i
        if getDeterministicEvent(ci) == targetEvent then
            return ci
        end
    end
    return nil
end

-- Active phase start/end (unix) for a given cycle index.
local function cycleTimes(cycleIndex)
    local cycleStart = cycleIndex * TOTAL_CYCLE_SEC
    return cycleStart, cycleStart + COOLDOWN_SEC, cycleStart + TOTAL_CYCLE_SEC
end

-- Discord dynamic timestamp markdown (localizes per viewer). style: F, f, R, T, etc.
local function ts(unix, style)
    return "<t:" .. math.floor(unix) .. ":" .. (style or "F") .. ">"
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
    Hell = 0xCC2200, Crystal = 0xB8E0FF,
}

local client = discordia.Client()
local lastStartingSoonCycle = -1
local lastActiveCycle = -1

-- Slash command definitions ------------------------------------------------
local eventChoices = {}
for _, name in ipairs(sortedKeys) do
    table.insert(eventChoices, { name = name, value = name })
end

local SLASH_COMMANDS = {
    {
        name = "nextevent",
        description = "Show the next upcoming event (optionally for a specific event)",
        options = {
            {
                type = 3, -- STRING
                name = "event",
                description = "Filter to a specific event",
                required = false,
                choices = eventChoices,
            },
        },
    },
    {
        name = "currentevent",
        description = "Show the event happening right now and time remaining",
    },
    {
        name = "upcoming",
        description = "List the next several upcoming events",
        options = {
            {
                type = 4, -- INTEGER
                name = "count",
                description = "How many events to list (1-15, default 5)",
                required = false,
            },
        },
    },
}

-- Bulk-overwrites guild commands for every guild the bot is in (instant update).
local function registerCommands()
    local appId = client.user.id
    for guild in client.guilds:iter() do
        local _, err = client._api:request('PUT',
            '/applications/' .. appId .. '/guilds/' .. guild.id .. '/commands',
            SLASH_COMMANDS)
        if err then
            print('Failed to register commands in ' .. guild.name .. ': ' .. tostring(err))
        else
            print('Registered slash commands in ' .. guild.name)
        end
    end
end

local function getOption(d, name)
    if not (d.data and d.data.options) then return nil end
    for _, opt in ipairs(d.data.options) do
        if opt.name == name then return opt.value end
    end
    return nil
end

local function respondInteraction(d, embed)
    embed.timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local _, err = client._api:request('POST',
        '/interactions/' .. d.id .. '/' .. d.token .. '/callback',
        { type = 4, data = { embeds = { embed } } })
    if err then
        print('Failed to respond to interaction: ' .. tostring(err))
    end
end

client:on('interactionCreate', function(d)
    if d.type ~= 2 then return end -- 2 = APPLICATION_COMMAND
    local name = d.data and d.data.name
    local now = os.time()
    local cycleIndex = math.floor(now / TOTAL_CYCLE_SEC)
    local timeInCycle = now % TOTAL_CYCLE_SEC
    -- The next cycle whose event has not yet started.
    local startCycle = (timeInCycle < COOLDOWN_SEC) and cycleIndex or (cycleIndex + 1)

    if name == "currentevent" then
        local _, event, phase = getCycleInfo(now)
        local _, activeStart, activeEnd = cycleTimes(cycleIndex)
        local color = EVENT_COLORS[event] or 0x808080
        if phase == "active" then
            respondInteraction(d, {
                title = event .. " Event is ACTIVE",
                description = "**" .. event .. "** is happening right now!\nEnds " ..
                    ts(activeEnd, "R") .. " (" .. ts(activeEnd, "T") .. ").",
                color = color,
            })
        else
            respondInteraction(d, {
                title = event .. " Event is in cooldown",
                description = "**" .. event .. "** begins " ..
                    ts(activeStart, "R") .. " (" .. ts(activeStart, "F") .. ").",
                color = color,
            })
        end

    elseif name == "nextevent" then
        local filter = getOption(d, "event")
        if filter then
            local found = findNextOccurrence(filter, cycleIndex)
            if not found then
                respondInteraction(d, {
                    title = "No upcoming " .. filter .. " event found",
                    color = 0x808080,
                })
                return
            end
            local _, activeStart, activeEnd = cycleTimes(found)
            local color = EVENT_COLORS[filter] or 0x808080
            local desc
            if now >= activeStart and now < activeEnd then
                desc = "**" .. filter .. "** is active right now! Ends " .. ts(activeEnd, "R") .. "."
            else
                desc = "Starts " .. ts(activeStart, "R") .. " (" .. ts(activeStart, "F") .. ")\n" ..
                       "Ends " .. ts(activeEnd, "T") .. "."
            end
            respondInteraction(d, {
                title = "Next " .. filter .. " Event",
                description = desc,
                color = color,
            })
        else
            local event = getDeterministicEvent(startCycle)
            local _, activeStart, activeEnd = cycleTimes(startCycle)
            respondInteraction(d, {
                title = "Next Event: " .. event,
                description = "**" .. event .. "** begins " .. ts(activeStart, "R") ..
                    " (" .. ts(activeStart, "F") .. ")\nEnds " .. ts(activeEnd, "T") .. ".",
                color = EVENT_COLORS[event] or 0x808080,
            })
        end

    elseif name == "upcoming" then
        local count = getOption(d, "count") or 5
        if count < 1 then count = 1 end
        if count > 15 then count = 15 end
        local lines = {}
        for i = 0, count - 1 do
            local ci = startCycle + i
            local event = getDeterministicEvent(ci)
            local _, activeStart = cycleTimes(ci)
            table.insert(lines, "**" .. event .. "** - " .. ts(activeStart, "R") ..
                " (" .. ts(activeStart, "f") .. ")")
        end
        respondInteraction(d, {
            title = "Upcoming Events",
            description = table.concat(lines, "\n"),
            color = 0x5865F2,
        })
    end
end)

client:on('ready', function()
    print('Logged in as ' .. client.user.username)
    print('Event loop running! (Powered by Luvit & Discordia)')

    registerCommands()
    
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
                if event == "Aquatic" or event == "Petalune" or event == "Hell" or event == "Crystal" then
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
