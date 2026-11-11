-- exertions: skater exertions on pops and landings

-- cg_ = client game

local cvars = {}	-- every cvar, in the order registered

-- name alone prints the value, name and a number sets it
local function Cvar_Register(name, value, min, max, help, why)
	local cv = {value = value}
	table.insert(cvars, {name = name, cv = cv, default = value, min = min, max = max, help = help, why = why})
	reskate.console.command(name, help, function(args)
		if args[1] == nil then
			reskate.console.print(string.format("%s is %g (%g to %g)", name, cv.value, min, max))
			return
		end
		local v = tonumber(args[1])
		if v == nil then
			reskate.console.print(name .. ": " .. args[1] .. " is not a number")
			return
		end
		cv.value = math.clamp(v, min, max)
		reskate.console.print(string.format("%s set to %g", name, cv.value))
	end)
	return cv
end

-- tunable cvars, defaults are most optimal, but tunable anyway because yolo
local cg_exert_voice = Cvar_Register("cg_exert_voice", -1, -1, 2,
	"Voice: -1 the skater's, 0 none, 1 style A, 2 style B",
	"Leave at -1 to follow the creator's voice. Force 1 or 2 to hear that voice's takes without changing your skater, or 0 to mute.")

local cg_exert_range = Cvar_Register("cg_exert_range", 4.5, 1, 500,
	"Metres from the camera to silence",
	"Raise it if exertions turn faint with a far camera. Lower it if they sound like they come from your speakers instead of the skater.")

local cg_exert_land_min = Cvar_Register("cg_exert_land_min", 2.0, 0, 50,
	"Down speed below this gets no landing exertion",
	"Raise it if small drops and grind exits grunt too often. Lower it to hear more of them.")

local cg_exert_land_heavy = Cvar_Register("cg_exert_land_heavy", 5.0, 0, 50,
	"Down speed for heavy landing exertions",
	"Where light takes give way to heavy ones. Lower it to hear effort on smaller drops.")

local cg_exert_land_very_heavy = Cvar_Register("cg_exert_land_very_heavy", 8.0, 0, 50,
	"Down speed for very heavy landing exertions",
	"Where the biggest takes start, and where landings reach full volume. Set it just under your biggest drops.")

local cg_exert_setup_volume = Cvar_Register("cg_exert_setup_volume", 0.8, 0, 1,
	"Volume of pop exertions",
	"Lower it if pops compete with landings, or if a grunt on every ollie gets tiring.")

local cg_exert_pitch_spread = Cvar_Register("cg_exert_pitch_spread", 0.05, 0, 0.5,
	"Random pitch change either way",
	"Makes repeated takes sound different. 0 plays takes exactly as exported. Past about 0.08 the voice starts to sound like someone else.")

local cg_exert_debug = Cvar_Register("cg_exert_debug", 0, 0, 1,
    "Print each pop and landing to the console",
    "Turn it on to see down speeds and which takes are played. It can be useful for tuning the other cvars.")

local function Exert_DPrint(text)
    if cg_exert_debug.value >= 1 then
        reskate.console.print(text)
    end
end

-- a take's bucket is the start of its file name
local BUCKETS = {"land_light", "land_heavy", "land_very_heavy", "trick_setup"}

-- sorts a folder's wavs into buckets
local function Voice_Load(folder)
	local voice = {}
	for _, bucket in BUCKETS do
		voice[bucket] = {}
	end
	for _, name in reskate.package.list(folder) do
		if name:lower():sub(-4) == ".wav" then
			for _, bucket in BUCKETS do
				local prefix = bucket .. "_"
				if name:sub(1, #prefix) == prefix then
					table.insert(voice[bucket], folder .. "/" .. name)
					break
				end
			end
		end
	end
	return voice
end

local voices = {
	[1] = Voice_Load("sounds/m"),	-- style A
	[2] = Voice_Load("sounds/f"),	-- style B
}

for index, voice in voices do
	local counts = {}
	for _, bucket in BUCKETS do
		table.insert(counts, string.format("%s %d", bucket, #voice[bucket]))
	end
	reskate.console.print(string.format("exertions: voice %d: %s", index, table.concat(counts, ", ")))
end

-- the creator's voice items, by voice index
local VOICE_ITEMS = {
	own_voicetype01 = 1,	-- style A
	own_voicetype02 = 2,	-- style B
}

-- the voice the skater was made with, 0 when it has none
local function Voice_Skater()
	for _, s in reskate.outfit.slots() do
		if s.slot:lower() == "cust_voicetypes" then
			return VOICE_ITEMS[s.item:lower()] or 0
		end
	end
	return 0
end

-- nil means no voice, so stay silent
local function Voice_Current()
	local index = math.floor(cg_exert_voice.value)
	if index < 0 then
		index = Voice_Skater()
	end
	return voices[index]
end

local lastPick = {}
local setupId = nil	-- the setup exertion now playing, if any

-- random choice of vo, don't play same one twice in a row
local function PickTake(set)
	local n = #set
	if n == 0 then
		return nil
	end
	local i = math.random(n)
	if n > 1 and i == lastPick[set] then
		i = i % n + 1
	end
	lastPick[set] = i
	return set[i]
end

local function RandomPitch()
	local s = cg_exert_pitch_spread.value
	return 1 - s + 2 * s * math.random()
end

reskate.on("launch", function(e)
	if e.from == "other" then
		return
	end

	local voice = Voice_Current()
	if not voice then
		return
	end

	local take = PickTake(voice.trick_setup)
	if not take then
		return
	end

	setupId = reskate.audio.play(take, {volume = cg_exert_setup_volume.value, pitch = RandomPitch(), range = cg_exert_range.value})
	Exert_DPrint("launch from " .. e.from .. ", " .. take)
end)

reskate.on("board_landed", function(e)
	local voice = Voice_Current()
	if not voice then
		return
	end

	local landMin = cg_exert_land_min.value
	local veryHeavy = cg_exert_land_very_heavy.value

	if e.down_speed < landMin then
		Exert_DPrint(string.format("board down %.2f m/s, no exertion", e.down_speed))
		return
	end

	if setupId then
		reskate.audio.stop(setupId)
		setupId = nil
	end

	local set = voice.land_light
	if e.down_speed >= veryHeavy then
		set = voice.land_very_heavy
	elseif e.down_speed >= cg_exert_land_heavy.value then
		set = voice.land_heavy
	end

	local take = PickTake(set)
	if not take then
		Exert_DPrint(string.format("board down %.2f m/s, no takes for it", e.down_speed))
		return
	end

	local t = math.clamp((e.down_speed - landMin) / math.max(veryHeavy - landMin, 0.01), 0, 1)
	local id, why = reskate.audio.play(take, {volume = 0.6 + 0.4 * t, pitch = RandomPitch(), range = cg_exert_range.value})

	Exert_DPrint(string.format("board down %.2f m/s onto %s, %s", e.down_speed, e.onto, take))
	if not id then
		reskate.console.print("exertion failed: " .. why) -- should always print, debug gate irrelevant
	end
end)

-- test: cg_exert_test [range] [volume]
reskate.console.command("cg_exert_test", "Plays a test take: cg_exert_test [range] [volume]", function(args)
	local voice = Voice_Current()
	local take = voice and PickTake(voice.land_heavy)
	if not take then
		reskate.console.print("cg_exert_test: no heavy takes for this voice")
		return
	end

	local range = math.clamp(tonumber(args[1]) or cg_exert_range.value, 1, 500)
	local volume = math.clamp(tonumber(args[2]) or 1, 0, 1)
	local id, why = reskate.audio.play(take, {range = range, volume = volume})
	if id then
		reskate.console.print(string.format("cg_exert_test: %s, range %.0f, volume %.2f", take, range, volume))
	else
		reskate.console.print("cg_exert_test failed: " .. why)
	end
end)

-- every cvar with its value, default, range and what it is for
reskate.console.command("cg_exert_help", "Lists every exertions cvar and why you would tune it", function(args)
	for _, c in cvars do
		reskate.console.print(string.format("%s %g (default %g, %g to %g)", c.name, c.cv.value, c.default, c.min, c.max))
		reskate.console.print("    " .. c.help)
		reskate.console.print("    " .. c.why)
	end
	reskate.console.print("cg_exert_test [range] [volume]: plays a heavy landing take")
end)