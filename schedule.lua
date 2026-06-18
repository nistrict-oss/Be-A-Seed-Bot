local COOLDOWN_SEC = 180
local DURATION_SEC = 120
local TOTAL_CYCLE_SEC = COOLDOWN_SEC + DURATION_SEC -- 300
local SECRET_SALT = 848123

local EVENT_WEIGHTS = {
	Silver = 200,
	Taco = 50,
	Alien = 25,
	Gold = 150,
	Diamond = 100,
	Ruby = 30,
	Galaxy = 20,
	Aquatic = 10,
	["Black Hole"] = 15,
}

local sortedKeys = { "Alien", "Aquatic", "Black Hole", "Diamond", "Galaxy", "Gold", "Ruby", "Silver", "Taco" }

local function getDeterministicEvent(cycleIndex: number): string
	if cycleIndex == 5937397 then
		return "Taco"
	end
	
	local rng = Random.new(cycleIndex + SECRET_SALT)
	local total = 0
	
	for _, k in sortedKeys do
		total += EVENT_WEIGHTS[k]
	end
	
	local r = rng:NextNumber() * total
	local cur = 0
	for _, name in sortedKeys do
		cur += EVENT_WEIGHTS[name]
		if r <= cur then
			return name
		end
	end
	
	return "Gold"
end

-- Generate the schedule for the next 10 events:
local function printSchedule()
	local now = os.time()
	local currentCycle = math.floor(now / TOTAL_CYCLE_SEC)
	
	print("--- Upcoming Event Schedule ---")
	for i = 0, 10 do
		local cycle = currentCycle + i
		local eventName = getDeterministicEvent(cycle)
		
		local startTime = (cycle * TOTAL_CYCLE_SEC) + COOLDOWN_SEC
		-- Format time as a human readable string for your local timezone
		local timeString = os.date("%I:%M:%S %p", startTime)
		
		if i == 0 then
			print(string.format("CURRENT EVENT: %s (Started/Starts at %s)", eventName, timeString))
		else
			print(string.format("Next +%d: %s at %s", i, eventName, timeString))
		end
	end
	
	print("\n--- Upcoming Aquatic & Black Hole ---")
	local rareFound = 0
	local searchCycle = currentCycle + 1
	
	while rareFound < 5 do
		local eventName = getDeterministicEvent(searchCycle)
		if eventName == "Aquatic" or eventName == "Black Hole" then
			local startTime = (searchCycle * TOTAL_CYCLE_SEC) + COOLDOWN_SEC
			local timeString = os.date("%m/%d/%Y %I:%M:%S %p", startTime)
			print(string.format("%s at %s", eventName, timeString))
			rareFound += 1
		end
		searchCycle += 1
	end
end

printSchedule()
