-- Seed Farm (manual)

print("[SeedFarm] v10.110 starting...")

local Rayfield = nil

-- Embedded Rayfield fallback (v10.108): a pinned copy of the official
-- sirius.menu build (fetched + compile-verified Oct 23 2026), used
-- only if the live download fails, so a broken HttpGet can no longer
-- kill the farm. The same leak patch is applied to either copy.
local EMBEDDED_RAYFIELD = [=======[--[[

	Rayfield Interface Suite
	by Sirius

	shlex  | Designing + Programming
	iRay   | Programming
	Max    | Programming
	Damian | Programming

]]

-- Read first, so secure mode covers Rayfield's output from its first line.
local secureMode = false
if getgenv then
	local ok, result = pcall(function() return getgenv().RAYFIELD_SECURE end)
	if ok and result then secureMode = true end
end

-- Rayfield's own console output goes through these locals. Under secure mode they are silent.
-- They are never assigned as globals: in an executor those are shared with every other script.
local warn, print, error, assert = warn, print, error, assert
if secureMode then
	local rawError = error
	local rawAssert = assert
	warn = function(...) end
	print = function(...) end
	error = function(_, level) rawError("", level) end
	assert = function(v, ...) return rawAssert(v) end
end

if debugX then
	warn('Initialising Rayfield')
end



local function getService(name)
	local service = game:GetService(name)
	return if cloneref then cloneref(service) else service
end

-- Remote modules are fetched from a fixed commit rather than a branch, so what runs is exactly what
-- was reviewed and a push to a branch can't change it under every running script. Bump this to
-- ship a new reporter or icon set. sirius-gate pins its reporter to the same commit.
local RAYFIELD_COMMIT = "3ef72398fb4c8ba6fd1801e98704991d3cc9cbc2" -- SiriusSoftwareLtd/Rayfield: reporter.lua, icons.lua
local RAYFIELD_RAW = "https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/" .. RAYFIELD_COMMIT .. "/"

-- Services
local UserInputService = getService("UserInputService")
local TweenService = getService("TweenService")
local Players = getService("Players")
local CoreGui = getService("CoreGui")

-- Some executors have no task.cancel. Without it the thread is left to finish on its own.
local function cancelThread(thread: thread)
	if task.cancel then
		pcall(task.cancel, thread)
	end
end

-- Loads and executes a function hosted on a remote URL. Cancels the request if the requested URL takes too long to respond.
-- Errors with the function are caught and logged to the output
local function loadWithTimeout(url: string, timeout: number?): ...any
	assert(type(url) == "string", "Expected string, got " .. type(url))
	timeout = timeout or 5
	local requestCompleted = false
	local success, result = false, nil

	local requestThread = task.spawn(function()
		local fetchSuccess, fetchResult = pcall(game.HttpGet, game, url) -- game:HttpGet(url)
		-- If the request fails the content can be empty, even if fetchSuccess is true
		if not fetchSuccess or #fetchResult == 0 then
			if #fetchResult == 0 then
				fetchResult = "Empty response" -- Set the error message
			end
			success, result = false, fetchResult
			requestCompleted = true
			return
		end
		local content = fetchResult -- Fetched content
		local execSuccess, execResult = pcall(function()
			return loadstring(content)()
		end)
		success, result = execSuccess, execResult
		requestCompleted = true
	end)

	local timeoutThread = task.delay(timeout, function()
		if not requestCompleted then
			warn("Request for " .. url .. " timed out after " .. tostring(timeout) .. " seconds")
			cancelThread(requestThread)
			result = "Request timed out"
			requestCompleted = true
		end
	end)

	-- Wait for completion or timeout
	while not requestCompleted do
		task.wait()
	end
	-- Cancel timeout thread if still running when request completes
	if coroutine.status(timeoutThread) ~= "dead" then
		cancelThread(timeoutThread)
	end
	if not success then
		warn("Failed to process " .. tostring(url) .. ": " .. tostring(result))
	end
	return if success then result else nil
end

local requestsDisabled = false
local analyticsOptOut = false -- the player set getgenv().RAYFIELD_ANALYTICS = false
local customAssetId = nil
if getgenv then
	local ok, result = pcall(function() return getgenv().DISABLE_RAYFIELD_REQUESTS end)
	if ok and result then requestsDisabled = true end
	local ok2, result2 = pcall(function() return getgenv().RAYFIELD_ASSET_ID end)
	if ok2 and type(result2) == "number" then customAssetId = result2 end
	local ok3, result3 = pcall(function() return getgenv().RAYFIELD_ANALYTICS end)
	if ok3 and result3 == false then analyticsOptOut = true end
end

local secureWarnings = {}
local customAssets = {}

local function secureNotify(wType, title, content)
	if secureWarnings[wType] then return end
	secureWarnings[wType] = true
	task.spawn(function()
		while not RayfieldLibrary or not RayfieldLibrary.Notify do task.wait(0.5) end
		RayfieldLibrary:Notify({
			Title = title,
			Content = content,
			Duration = 8,
		})
	end)
end
local InterfaceBuild = 'UU2NX'
local Release = "Build 1.753"
local RayfieldFolder = "Rayfield"
local ConfigurationFolder = RayfieldFolder.."/Configurations"
local ConfigurationExtension = ".rfld"
local settingsTable = {
	General = {
		-- if needs be in order just make getSetting(name)
		rayfieldOpen = {Type = 'bind', Value = 'K', Name = 'Rayfield Keybind'},
		-- buildwarnings
		-- rayfieldprompts

	},
	System = {
		usageAnalytics = {
			Type = 'toggle',
			Value = true,
			Name = 'Usage Analytics (pseudonymous)',
			Description = 'Sends a hashed user ID, executor, game, locale and script details when a window opens, plus kick error codes. Nothing you type. sirius.menu/privacy',
		},
	}
}

-- Settings that have been overridden by the developer. These will not be saved to the user's configuration file
-- Overridden settings always take precedence over settings in the configuration file, and are cleared if the user changes the setting in the UI
local overriddenSettings: { [string]: any } = {} -- For example, overriddenSettings["System.rayfieldOpen"] = "J"
local function overrideSetting(category: string, name: string, value: any)
	overriddenSettings[category .. "." .. name] = value
end

local function getSetting(category: string, name: string): any
	if overriddenSettings[category .. "." .. name] ~= nil then
		return overriddenSettings[category .. "." .. name]
	elseif settingsTable[category][name] ~= nil then
		return settingsTable[category][name].Value
	end
end

-- If requests/analytics have been disabled by the developer or the player, set the user-facing
-- setting to false as well
if requestsDisabled or analyticsOptOut then
	overrideSetting("System", "usageAnalytics", false)
end

local HttpService = getService('HttpService')
local RunService = getService('RunService')

-- Environment Check
local useStudio = RunService:IsStudio() or false

local settingsCreated = false
local settingsInitialized = false -- Whether the UI elements in the settings page have been set to the proper values
local requestFunc = (syn and syn.request) or (fluxus and fluxus.request) or (http and http.request) or http_request or request


-- The function below provides a safe alternative for calling error-prone functions
-- Especially useful for filesystem function (writefile, makefolder, etc.)
local function callSafely(func, ...)
	if func then
		local success, result = pcall(func, ...)
		if not success then
			warn("Rayfield | Function failed with error: ", result)
			return false
		else
			return result
		end
	end
end

-- Ensures a folder exists by creating it if needed
local function ensureFolder(folderPath)
	if isfolder and not callSafely(isfolder, folderPath) then
		callSafely(makefolder, folderPath)
	end
end

-- Folder and file names a hub supplies go into paths under the executor's workspace, so they can't
-- be allowed to climb out of it. Removing a character can expose a new "..", so ".:./" is cleaned
-- of the character first and the dots after, repeating until nothing changes.
local function stripTraversal(text: string): string
	local previous
	repeat
		previous = text
		text = string.gsub(text, "%.%.", "")
	until text == previous
	return text
end

-- Keeps "/" so a hub can still nest its folder, but never a leading one, a drive letter or "..".
local function sanitizeFolderName(value: any): string
	local text = string.gsub(string.gsub(tostring(value), "\\", "/"), "[:%c]", "")
	text = string.gsub(stripTraversal(text), "/+", "/")
	return (string.gsub(text, "^/+", ""))
end

-- A single file name: no slashes of either kind, control characters or "..".
local function sanitizeFileName(value: any): string
	local text = string.gsub(tostring(value), "[/\\%c]", "")
	return stripTraversal(text)
end

local function loadSettings()
	local file = nil

	local success, result =	pcall(function()
		if callSafely(isfolder, RayfieldFolder) then
			if callSafely(isfile, RayfieldFolder..'/settings'..ConfigurationExtension) then
				file = callSafely(readfile, RayfieldFolder..'/settings'..ConfigurationExtension)
			end
		end

		-- for debug in studio
		if useStudio then
			file = [[
	{"General":{"rayfieldOpen":{"Value":"K","Type":"bind","Name":"Rayfield Keybind","Element":{"HoldToInteract":false,"Ext":true,"Name":"Rayfield Keybind","Set":null,"CallOnChange":true,"Callback":null,"CurrentKeybind":"K"}}},"System":{"usageAnalytics":{"Value":false,"Type":"toggle","Name":"Usage Analytics (pseudonymous)","Element":{"Ext":true,"Name":"Usage Analytics (pseudonymous)","Set":null,"CurrentValue":false,"Callback":null}}}}
]]
		end

		if file then
			local decodeSuccess, decodedFile = pcall(function() return HttpService:JSONDecode(file) end)
			if decodeSuccess then
				file = decodedFile
			else
				file = {}
			end
		else
			file = {}
		end


		if not settingsCreated then
			return
		end

		-- Check if settings file has any entries
		if next(file) ~= nil then
			-- If it does, apply them
			for categoryName, categoryTable in file do
				for settingName, setting in categoryTable do
					local default = settingsTable[categoryName] and settingsTable[categoryName][settingName]
					if not default then continue end -- ignore keys not in settingsTable (old/renamed settings)
					local settingType = typeof(default.Value)
					-- Make sure setting has the correct type
					if not (settingType == typeof(setting.Value)) then
						warn("Rayfield | Error parsing settings file. '"..settingName.."' must be a "..settingType)
						continue
					end
					default.Value = setting.Value
				end
			end
		end
		-- Apply the actual setting value to UI elements
		for categoryName, categoryTable in settingsTable do
			for settingName, setting in categoryTable do
				if setting.Element then
					setting.Element:Set(getSetting(categoryName, settingName))
				end
			end
		end
		settingsInitialized = true
	end)

	if not success then 
		if writefile then
			warn('Rayfield had an issue accessing configuration saving capability.')
		end
	end
end

if debugX then
	warn('Now Loading Settings Configuration')
end

loadSettings()

if debugX then
	warn('Settings Loaded')
end

local ANALYTICS_TOKEN = "05de7f9fd320d3b8428cd1c77014a337b85b6c8efee2c5914f5ab5700c354b9a"

-- The reporter is fetched only at the moment it is about to be used, and only if the user hasn't
-- opted out and the developer hasn't set DISABLE_RAYFIELD_REQUESTS. Opting out means no request to
-- GitHub for it either, not just no event sent.
local reporter = nil
local reporterLoaded = false
local function loadReporter()
	if reporterLoaded then return reporter end
	reporterLoaded = true
	if requestsDisabled or useStudio then return nil end

	local fetchSuccess, fetchResult = pcall((game :: any).HttpGet, game, RAYFIELD_RAW .. "reporter.lua")
	if fetchSuccess and #fetchResult > 0 then
		local execSuccess, Analytics = pcall(function()
			return (loadstring(fetchResult) :: any)()
		end)
		if execSuccess and Analytics then
			pcall(function()
				reporter = Analytics.new({
					url          = "https://rayfield-collect.sirius-software-ltd.workers.dev",
					token        = ANALYTICS_TOKEN,
					product_name = "Rayfield",
					category     = "UILibrary",
				})
			end)
		end
	end
	return reporter
end

-- Whether analytics may be sent right now. A saved opt-out is only known once the settings file has
-- been applied, so until then the answer is no; an executor that can't read files has nothing saved
-- to respect, so the default applies there, and getgenv().RAYFIELD_ANALYTICS = false is the
-- player's way to opt out.
local function analyticsAllowed(): boolean
	if requestsDisabled or analyticsOptOut or useStudio then return false end
	if not getSetting("System", "usageAnalytics") then return false end
	return settingsInitialized or not (isfile and readfile)
end

-- Whether analyticsAllowed() has a final answer yet, rather than waiting on the settings file.
local function analyticsDecided(): boolean
	if requestsDisabled or analyticsOptOut or useStudio then return true end
	if not getSetting("System", "usageAnalytics") then return true end
	return settingsInitialized or not (isfile and readfile)
end

-- Sentivel heartbeats. A heartbeat monitor is a dead-man's switch: it stays green while pings keep
-- arriving and alarms once they stop. Rayfield pings its own below, and a window made with
-- Settings.Heartbeat pings the developer's own for as long as it's up. Best-effort throughout: a
-- ping never throws or blocks. Only a bad link, or a token Sentivel doesn't know, warns, since
-- either would otherwise look exactly like an outage. Secure mode silences those like any warn.
local HEARTBEAT_BASE = "https://www.sentivel.com/api/heartbeat/"

-- Seconds between a window's pings. A monitor expecting a ping every 5 minutes, with a little
-- grace, stays green for as long as anyone has the script open.
local HEARTBEAT_PERIOD = 300

-- Consecutive 404s before a loop gives up. Sentivel answers 404 for a token it doesn't know, which
-- never recovers, but one stray 404 from a bad deploy shouldn't silence every session.
local HEARTBEAT_GIVE_UP = 3

-- the loop that currently owns each ping URL. a newer window on the same link takes it over and
-- the older loop retires when it next wakes, so the link is never pinged twice over, and a window
-- rebuilt straight after Destroy isn't turned away by a loop that's still asleep
local heartbeatOwners = {}

-- A full ping URL or its bare token, to the canonical URL. nil and a reason when it isn't one.
local function resolveHeartbeat(target: any): (string?, string?)
	if type(target) ~= "string" then
		return nil, "Heartbeat takes your Sentivel ping URL or token as a string, got " .. typeof(target)
	end
	-- a real link is under 100 characters; this keeps the trim below cheap on anything absurd
	if #target > 512 then
		return nil, "Heartbeat is far too long to be a Sentivel ping URL. Copy the ping URL and try again"
	end

	-- a copy out of Discord or a browser can drag along no-break and zero-width spaces, which %s
	-- doesn't cover
	local cleaned = string.gsub(string.gsub(target, "\194\160", " "), "\226\128\139", "")
	cleaned = string.gsub(cleaned, "\239\187\191", "")
	local trimmed = string.match(cleaned, "^%s*(.-)%s*$") :: string
	if trimmed == "" then
		return nil, "Heartbeat is empty. Paste the ping URL from your Sentivel heartbeat monitor"
	end

	-- a link pasted without its scheme is still a link
	if not string.find(trimmed, "://", 1, true) and string.find(trimmed, "/", 1, true) then
		trimmed = "https://" .. trimmed
	end

	local token = trimmed
	if string.find(trimmed, "://", 1, true) then
		-- host first, on its own, so a Sentivel link that's just the wrong page is told that. the
		-- default port and a fully qualified trailing dot name the same host
		local host, rest = string.match(trimmed, "^[Hh][Tt][Tt][Pp][Ss]?://([^/?#]+)(.*)$")
		local bare = if host then string.gsub(string.gsub(string.lower(host), ":443$", ""), "%.$", "") else nil
		if bare ~= "sentivel.com" and bare ~= "www.sentivel.com" then
			return nil, "Heartbeat only pings Sentivel. Use the ping URL from your heartbeat monitor"
		end
		local found = string.match(rest or "", "^/api/heartbeat/([^/?#]+)/?$")
		if not found then
			return nil, "That Sentivel link isn't a heartbeat ping URL. It should look like " .. HEARTBEAT_BASE .. "<token>"
		end
		token = found
	end

	-- tokens are hex. the bounds are loose so a future token format still passes; a monitor id (a
	-- UUID, so it has dashes) falls outside them and is told why
	if #token < 32 or #token > 128 or not string.match(token, "^%x+$") then
		if string.match(token, "^%x+%-%x+%-%x+%-%x+%-%x+$") then
			return nil, "That looks like a monitor ID. Heartbeat needs the monitor's ping URL, not its ID"
		end
		return nil, "That doesn't look like a Sentivel heartbeat token. Copy the whole ping URL and try again"
	end

	-- always www: the bare domain answers with a redirect, one more round trip per ping. and
	-- lowercase: Sentivel issues lowercase tokens and matches them exactly
	return HEARTBEAT_BASE .. string.lower(token), nil
end

-- One ping. The HTTP status when it can be seen, otherwise nil. HttpGet goes first: the executor's
-- request function adds headers that identify the executor and the player's machine, and those
-- have no business reaching a third party. HttpGet throws on a failed request, so a 404 is read
-- out of its error. The request function is only used when HttpGet is missing or fails for
-- another reason. Yields, so call it from its own thread.
local function sendHeartbeat(url: string): number?
	local ok, err = pcall(function()
		return (game :: any):HttpGet(url)
	end)
	if ok then
		return 200
	end
	if string.find(tostring(err), "404", 1, true) then
		return 404
	end
	if requestFunc then
		local sent, response = pcall(requestFunc, { Url = url, Method = "GET" })
		-- some executors hand the status back as a string
		return if sent and type(response) == "table" then tonumber(response.StatusCode) else nil
	end
	return nil
end

-- Heartbeats count as analytics. Waits until analyticsAllowed() says yes, for up to
-- HEARTBEAT_PERIOD, while `wanted` holds. false once the answer is no, or it never came.
local function awaitAnalyticsConsent(wanted: () -> boolean): boolean
	local waited = 0
	while not analyticsAllowed() do
		if analyticsDecided() or waited >= HEARTBEAT_PERIOD or not wanted() then
			return false
		end
		task.wait(1)
		waited += 1
	end
	return true
end

-- Ping `target` every HEARTBEAT_PERIOD for as long as `alive` says so and the player's analytics
-- choice allows it. false when the link is bad (which warns), or when running in Studio, where
-- playtests aren't real runs.
local function startHeartbeat(target: any, alive: () -> boolean): boolean
	local url, reason = resolveHeartbeat(target)
	if not url then
		warn("Rayfield | " .. tostring(reason) .. ".")
		return false
	end
	if useStudio then
		return false
	end

	local resolved = url :: string
	local owner = {}
	heartbeatOwners[resolved] = owner
	-- deferred rather than spawned: spawning runs the first ping right away, and a request that
	-- blocks without yielding would hold CreateWindow up for a whole round trip
	task.defer(function()
		local function owned()
			return heartbeatOwners[resolved] == owner and alive()
		end
		-- nothing is sent until the player's analytics choice is known, and an opt-out, then or
		-- mid-session, ends the loop
		if not awaitAnalyticsConsent(owned) then
			if heartbeatOwners[resolved] == owner then
				heartbeatOwners[resolved] = nil
			end
			return
		end
		local notFound = 0
		while owned() and analyticsAllowed() do
			-- a 404 is Sentivel saying the token names no heartbeat (deleted, regenerated, or
			-- mistyped into another valid-looking one). once it keeps saying so, stop asking
			notFound = if sendHeartbeat(resolved) == 404 then notFound + 1 else 0
			if notFound >= HEARTBEAT_GIVE_UP then
				warn("Rayfield | Sentivel doesn't recognise this heartbeat, so pings have stopped. Check the ping URL.")
				break
			end
			task.wait(HEARTBEAT_PERIOD)
		end
		if heartbeatOwners[resolved] == owner then
			heartbeatOwners[resolved] = nil
		end
	end)
	return true
end

if debugX then
	warn('Moving on to continue initialisation')
end

local RayfieldLibrary = {
	Flags = {},
	Theme = {
		Default = {
			TextColor = Color3.fromRGB(240, 240, 240),

			Background = Color3.fromRGB(25, 25, 25),
			Topbar = Color3.fromRGB(34, 34, 34),
			Shadow = Color3.fromRGB(20, 20, 20),

			NotificationBackground = Color3.fromRGB(20, 20, 20),
			NotificationActionsBackground = Color3.fromRGB(230, 230, 230),

			TabBackground = Color3.fromRGB(80, 80, 80),
			TabStroke = Color3.fromRGB(85, 85, 85),
			TabBackgroundSelected = Color3.fromRGB(210, 210, 210),
			TabTextColor = Color3.fromRGB(240, 240, 240),
			SelectedTabTextColor = Color3.fromRGB(50, 50, 50),

			ElementBackground = Color3.fromRGB(35, 35, 35),
			ElementBackgroundHover = Color3.fromRGB(40, 40, 40),
			SecondaryElementBackground = Color3.fromRGB(25, 25, 25),
			ElementStroke = Color3.fromRGB(50, 50, 50),
			SecondaryElementStroke = Color3.fromRGB(40, 40, 40),

			SliderBackground = Color3.fromRGB(50, 138, 220),
			SliderProgress = Color3.fromRGB(50, 138, 220),
			SliderStroke = Color3.fromRGB(58, 163, 255),

			ToggleBackground = Color3.fromRGB(30, 30, 30),
			ToggleEnabled = Color3.fromRGB(0, 146, 214),
			ToggleDisabled = Color3.fromRGB(100, 100, 100),
			ToggleEnabledStroke = Color3.fromRGB(0, 170, 255),
			ToggleDisabledStroke = Color3.fromRGB(125, 125, 125),
			ToggleEnabledOuterStroke = Color3.fromRGB(100, 100, 100),
			ToggleDisabledOuterStroke = Color3.fromRGB(65, 65, 65),

			DropdownSelected = Color3.fromRGB(40, 40, 40),
			DropdownUnselected = Color3.fromRGB(30, 30, 30),

			InputBackground = Color3.fromRGB(30, 30, 30),
			InputStroke = Color3.fromRGB(65, 65, 65),
			PlaceholderColor = Color3.fromRGB(178, 178, 178)
		},

		Ocean = {
			TextColor = Color3.fromRGB(230, 240, 240),

			Background = Color3.fromRGB(20, 30, 30),
			Topbar = Color3.fromRGB(25, 40, 40),
			Shadow = Color3.fromRGB(15, 20, 20),

			NotificationBackground = Color3.fromRGB(25, 35, 35),
			NotificationActionsBackground = Color3.fromRGB(230, 240, 240),

			TabBackground = Color3.fromRGB(40, 60, 60),
			TabStroke = Color3.fromRGB(50, 70, 70),
			TabBackgroundSelected = Color3.fromRGB(100, 180, 180),
			TabTextColor = Color3.fromRGB(210, 230, 230),
			SelectedTabTextColor = Color3.fromRGB(20, 50, 50),

			ElementBackground = Color3.fromRGB(30, 50, 50),
			ElementBackgroundHover = Color3.fromRGB(40, 60, 60),
			SecondaryElementBackground = Color3.fromRGB(30, 45, 45),
			ElementStroke = Color3.fromRGB(45, 70, 70),
			SecondaryElementStroke = Color3.fromRGB(40, 65, 65),

			SliderBackground = Color3.fromRGB(0, 110, 110),
			SliderProgress = Color3.fromRGB(0, 140, 140),
			SliderStroke = Color3.fromRGB(0, 160, 160),

			ToggleBackground = Color3.fromRGB(30, 50, 50),
			ToggleEnabled = Color3.fromRGB(0, 130, 130),
			ToggleDisabled = Color3.fromRGB(70, 90, 90),
			ToggleEnabledStroke = Color3.fromRGB(0, 160, 160),
			ToggleDisabledStroke = Color3.fromRGB(85, 105, 105),
			ToggleEnabledOuterStroke = Color3.fromRGB(50, 100, 100),
			ToggleDisabledOuterStroke = Color3.fromRGB(45, 65, 65),

			DropdownSelected = Color3.fromRGB(30, 60, 60),
			DropdownUnselected = Color3.fromRGB(25, 40, 40),

			InputBackground = Color3.fromRGB(30, 50, 50),
			InputStroke = Color3.fromRGB(50, 70, 70),
			PlaceholderColor = Color3.fromRGB(140, 160, 160)
		},

		AmberGlow = {
			TextColor = Color3.fromRGB(255, 245, 230),

			Background = Color3.fromRGB(45, 30, 20),
			Topbar = Color3.fromRGB(55, 40, 25),
			Shadow = Color3.fromRGB(35, 25, 15),

			NotificationBackground = Color3.fromRGB(50, 35, 25),
			NotificationActionsBackground = Color3.fromRGB(245, 230, 215),

			TabBackground = Color3.fromRGB(75, 50, 35),
			TabStroke = Color3.fromRGB(90, 60, 45),
			TabBackgroundSelected = Color3.fromRGB(230, 180, 100),
			TabTextColor = Color3.fromRGB(250, 220, 200),
			SelectedTabTextColor = Color3.fromRGB(50, 30, 10),

			ElementBackground = Color3.fromRGB(60, 45, 35),
			ElementBackgroundHover = Color3.fromRGB(70, 50, 40),
			SecondaryElementBackground = Color3.fromRGB(55, 40, 30),
			ElementStroke = Color3.fromRGB(85, 60, 45),
			SecondaryElementStroke = Color3.fromRGB(75, 50, 35),

			SliderBackground = Color3.fromRGB(220, 130, 60),
			SliderProgress = Color3.fromRGB(250, 150, 75),
			SliderStroke = Color3.fromRGB(255, 170, 85),

			ToggleBackground = Color3.fromRGB(55, 40, 30),
			ToggleEnabled = Color3.fromRGB(240, 130, 30),
			ToggleDisabled = Color3.fromRGB(90, 70, 60),
			ToggleEnabledStroke = Color3.fromRGB(255, 160, 50),
			ToggleDisabledStroke = Color3.fromRGB(110, 85, 75),
			ToggleEnabledOuterStroke = Color3.fromRGB(200, 100, 50),
			ToggleDisabledOuterStroke = Color3.fromRGB(75, 60, 55),

			DropdownSelected = Color3.fromRGB(70, 50, 40),
			DropdownUnselected = Color3.fromRGB(55, 40, 30),

			InputBackground = Color3.fromRGB(60, 45, 35),
			InputStroke = Color3.fromRGB(90, 65, 50),
			PlaceholderColor = Color3.fromRGB(190, 150, 130)
		},

		Light = {
			TextColor = Color3.fromRGB(40, 40, 40),

			Background = Color3.fromRGB(245, 245, 245),
			Topbar = Color3.fromRGB(230, 230, 230),
			Shadow = Color3.fromRGB(200, 200, 200),

			NotificationBackground = Color3.fromRGB(250, 250, 250),
			NotificationActionsBackground = Color3.fromRGB(240, 240, 240),

			TabBackground = Color3.fromRGB(235, 235, 235),
			TabStroke = Color3.fromRGB(215, 215, 215),
			TabBackgroundSelected = Color3.fromRGB(255, 255, 255),
			TabTextColor = Color3.fromRGB(80, 80, 80),
			SelectedTabTextColor = Color3.fromRGB(0, 0, 0),

			ElementBackground = Color3.fromRGB(240, 240, 240),
			ElementBackgroundHover = Color3.fromRGB(225, 225, 225),
			SecondaryElementBackground = Color3.fromRGB(235, 235, 235),
			ElementStroke = Color3.fromRGB(210, 210, 210),
			SecondaryElementStroke = Color3.fromRGB(210, 210, 210),

			SliderBackground = Color3.fromRGB(150, 180, 220),
			SliderProgress = Color3.fromRGB(100, 150, 200), 
			SliderStroke = Color3.fromRGB(120, 170, 220),

			ToggleBackground = Color3.fromRGB(220, 220, 220),
			ToggleEnabled = Color3.fromRGB(0, 146, 214),
			ToggleDisabled = Color3.fromRGB(150, 150, 150),
			ToggleEnabledStroke = Color3.fromRGB(0, 170, 255),
			ToggleDisabledStroke = Color3.fromRGB(170, 170, 170),
			ToggleEnabledOuterStroke = Color3.fromRGB(100, 100, 100),
			ToggleDisabledOuterStroke = Color3.fromRGB(180, 180, 180),

			DropdownSelected = Color3.fromRGB(230, 230, 230),
			DropdownUnselected = Color3.fromRGB(220, 220, 220),

			InputBackground = Color3.fromRGB(240, 240, 240),
			InputStroke = Color3.fromRGB(180, 180, 180),
			PlaceholderColor = Color3.fromRGB(140, 140, 140)
		},

		Amethyst = {
			TextColor = Color3.fromRGB(240, 240, 240),

			Background = Color3.fromRGB(30, 20, 40),
			Topbar = Color3.fromRGB(40, 25, 50),
			Shadow = Color3.fromRGB(20, 15, 30),

			NotificationBackground = Color3.fromRGB(35, 20, 40),
			NotificationActionsBackground = Color3.fromRGB(240, 240, 250),

			TabBackground = Color3.fromRGB(60, 40, 80),
			TabStroke = Color3.fromRGB(70, 45, 90),
			TabBackgroundSelected = Color3.fromRGB(180, 140, 200),
			TabTextColor = Color3.fromRGB(230, 230, 240),
			SelectedTabTextColor = Color3.fromRGB(50, 20, 50),

			ElementBackground = Color3.fromRGB(45, 30, 60),
			ElementBackgroundHover = Color3.fromRGB(50, 35, 70),
			SecondaryElementBackground = Color3.fromRGB(40, 30, 55),
			ElementStroke = Color3.fromRGB(70, 50, 85),
			SecondaryElementStroke = Color3.fromRGB(65, 45, 80),

			SliderBackground = Color3.fromRGB(100, 60, 150),
			SliderProgress = Color3.fromRGB(130, 80, 180),
			SliderStroke = Color3.fromRGB(150, 100, 200),

			ToggleBackground = Color3.fromRGB(45, 30, 55),
			ToggleEnabled = Color3.fromRGB(120, 60, 150),
			ToggleDisabled = Color3.fromRGB(94, 47, 117),
			ToggleEnabledStroke = Color3.fromRGB(140, 80, 170),
			ToggleDisabledStroke = Color3.fromRGB(124, 71, 150),
			ToggleEnabledOuterStroke = Color3.fromRGB(90, 40, 120),
			ToggleDisabledOuterStroke = Color3.fromRGB(80, 50, 110),

			DropdownSelected = Color3.fromRGB(50, 35, 70),
			DropdownUnselected = Color3.fromRGB(35, 25, 50),

			InputBackground = Color3.fromRGB(45, 30, 60),
			InputStroke = Color3.fromRGB(80, 50, 110),
			PlaceholderColor = Color3.fromRGB(178, 150, 200)
		},

		Green = {
			TextColor = Color3.fromRGB(30, 60, 30),

			Background = Color3.fromRGB(235, 245, 235),
			Topbar = Color3.fromRGB(210, 230, 210),
			Shadow = Color3.fromRGB(200, 220, 200),

			NotificationBackground = Color3.fromRGB(240, 250, 240),
			NotificationActionsBackground = Color3.fromRGB(220, 235, 220),

			TabBackground = Color3.fromRGB(215, 235, 215),
			TabStroke = Color3.fromRGB(190, 210, 190),
			TabBackgroundSelected = Color3.fromRGB(245, 255, 245),
			TabTextColor = Color3.fromRGB(50, 80, 50),
			SelectedTabTextColor = Color3.fromRGB(20, 60, 20),

			ElementBackground = Color3.fromRGB(225, 240, 225),
			ElementBackgroundHover = Color3.fromRGB(210, 225, 210),
			SecondaryElementBackground = Color3.fromRGB(235, 245, 235), 
			ElementStroke = Color3.fromRGB(180, 200, 180),
			SecondaryElementStroke = Color3.fromRGB(180, 200, 180),

			SliderBackground = Color3.fromRGB(90, 160, 90),
			SliderProgress = Color3.fromRGB(70, 130, 70),
			SliderStroke = Color3.fromRGB(100, 180, 100),

			ToggleBackground = Color3.fromRGB(215, 235, 215),
			ToggleEnabled = Color3.fromRGB(60, 130, 60),
			ToggleDisabled = Color3.fromRGB(150, 175, 150),
			ToggleEnabledStroke = Color3.fromRGB(80, 150, 80),
			ToggleDisabledStroke = Color3.fromRGB(130, 150, 130),
			ToggleEnabledOuterStroke = Color3.fromRGB(100, 160, 100),
			ToggleDisabledOuterStroke = Color3.fromRGB(160, 180, 160),

			DropdownSelected = Color3.fromRGB(225, 240, 225),
			DropdownUnselected = Color3.fromRGB(210, 225, 210),

			InputBackground = Color3.fromRGB(235, 245, 235),
			InputStroke = Color3.fromRGB(180, 200, 180),
			PlaceholderColor = Color3.fromRGB(120, 140, 120)
		},

		Bloom = {
			TextColor = Color3.fromRGB(60, 40, 50),

			Background = Color3.fromRGB(255, 240, 245),
			Topbar = Color3.fromRGB(250, 220, 225),
			Shadow = Color3.fromRGB(230, 190, 195),

			NotificationBackground = Color3.fromRGB(255, 235, 240),
			NotificationActionsBackground = Color3.fromRGB(245, 215, 225),

			TabBackground = Color3.fromRGB(240, 210, 220),
			TabStroke = Color3.fromRGB(230, 200, 210),
			TabBackgroundSelected = Color3.fromRGB(255, 225, 235),
			TabTextColor = Color3.fromRGB(80, 40, 60),
			SelectedTabTextColor = Color3.fromRGB(50, 30, 50),

			ElementBackground = Color3.fromRGB(255, 235, 240),
			ElementBackgroundHover = Color3.fromRGB(245, 220, 230),
			SecondaryElementBackground = Color3.fromRGB(255, 235, 240), 
			ElementStroke = Color3.fromRGB(230, 200, 210),
			SecondaryElementStroke = Color3.fromRGB(230, 200, 210),

			SliderBackground = Color3.fromRGB(240, 130, 160),
			SliderProgress = Color3.fromRGB(250, 160, 180),
			SliderStroke = Color3.fromRGB(255, 180, 200),

			ToggleBackground = Color3.fromRGB(240, 210, 220),
			ToggleEnabled = Color3.fromRGB(255, 140, 170),
			ToggleDisabled = Color3.fromRGB(200, 180, 185),
			ToggleEnabledStroke = Color3.fromRGB(250, 160, 190),
			ToggleDisabledStroke = Color3.fromRGB(210, 180, 190),
			ToggleEnabledOuterStroke = Color3.fromRGB(220, 160, 180),
			ToggleDisabledOuterStroke = Color3.fromRGB(190, 170, 180),

			DropdownSelected = Color3.fromRGB(250, 220, 225),
			DropdownUnselected = Color3.fromRGB(240, 210, 220),

			InputBackground = Color3.fromRGB(255, 235, 240),
			InputStroke = Color3.fromRGB(220, 190, 200),
			PlaceholderColor = Color3.fromRGB(170, 130, 140)
		},

		DarkBlue = {
			TextColor = Color3.fromRGB(230, 230, 230),

			Background = Color3.fromRGB(20, 25, 30),
			Topbar = Color3.fromRGB(30, 35, 40),
			Shadow = Color3.fromRGB(15, 20, 25),

			NotificationBackground = Color3.fromRGB(25, 30, 35),
			NotificationActionsBackground = Color3.fromRGB(45, 50, 55),

			TabBackground = Color3.fromRGB(35, 40, 45),
			TabStroke = Color3.fromRGB(45, 50, 60),
			TabBackgroundSelected = Color3.fromRGB(40, 70, 100),
			TabTextColor = Color3.fromRGB(200, 200, 200),
			SelectedTabTextColor = Color3.fromRGB(255, 255, 255),

			ElementBackground = Color3.fromRGB(30, 35, 40),
			ElementBackgroundHover = Color3.fromRGB(40, 45, 50),
			SecondaryElementBackground = Color3.fromRGB(35, 40, 45), 
			ElementStroke = Color3.fromRGB(45, 50, 60),
			SecondaryElementStroke = Color3.fromRGB(40, 45, 55),

			SliderBackground = Color3.fromRGB(0, 90, 180),
			SliderProgress = Color3.fromRGB(0, 120, 210),
			SliderStroke = Color3.fromRGB(0, 150, 240),

			ToggleBackground = Color3.fromRGB(35, 40, 45),
			ToggleEnabled = Color3.fromRGB(0, 120, 210),
			ToggleDisabled = Color3.fromRGB(70, 70, 80),
			ToggleEnabledStroke = Color3.fromRGB(0, 150, 240),
			ToggleDisabledStroke = Color3.fromRGB(75, 75, 85),
			ToggleEnabledOuterStroke = Color3.fromRGB(20, 100, 180), 
			ToggleDisabledOuterStroke = Color3.fromRGB(55, 55, 65),

			DropdownSelected = Color3.fromRGB(30, 70, 90),
			DropdownUnselected = Color3.fromRGB(25, 30, 35),

			InputBackground = Color3.fromRGB(25, 30, 35),
			InputStroke = Color3.fromRGB(45, 50, 60), 
			PlaceholderColor = Color3.fromRGB(150, 150, 160)
		},

		Serenity = {
			TextColor = Color3.fromRGB(50, 55, 60),
			Background = Color3.fromRGB(240, 245, 250),
			Topbar = Color3.fromRGB(215, 225, 235),
			Shadow = Color3.fromRGB(200, 210, 220),

			NotificationBackground = Color3.fromRGB(210, 220, 230),
			NotificationActionsBackground = Color3.fromRGB(225, 230, 240),

			TabBackground = Color3.fromRGB(200, 210, 220),
			TabStroke = Color3.fromRGB(180, 190, 200),
			TabBackgroundSelected = Color3.fromRGB(175, 185, 200),
			TabTextColor = Color3.fromRGB(50, 55, 60),
			SelectedTabTextColor = Color3.fromRGB(30, 35, 40),

			ElementBackground = Color3.fromRGB(210, 220, 230),
			ElementBackgroundHover = Color3.fromRGB(220, 230, 240),
			SecondaryElementBackground = Color3.fromRGB(200, 210, 220),
			ElementStroke = Color3.fromRGB(190, 200, 210),
			SecondaryElementStroke = Color3.fromRGB(180, 190, 200),

			SliderBackground = Color3.fromRGB(200, 220, 235),  -- Lighter shade
			SliderProgress = Color3.fromRGB(70, 130, 180),
			SliderStroke = Color3.fromRGB(150, 180, 220),

			ToggleBackground = Color3.fromRGB(210, 220, 230),
			ToggleEnabled = Color3.fromRGB(70, 160, 210),
			ToggleDisabled = Color3.fromRGB(180, 180, 180),
			ToggleEnabledStroke = Color3.fromRGB(60, 150, 200),
			ToggleDisabledStroke = Color3.fromRGB(140, 140, 140),
			ToggleEnabledOuterStroke = Color3.fromRGB(100, 120, 140),
			ToggleDisabledOuterStroke = Color3.fromRGB(120, 120, 130),

			DropdownSelected = Color3.fromRGB(220, 230, 240),
			DropdownUnselected = Color3.fromRGB(200, 210, 220),

			InputBackground = Color3.fromRGB(220, 230, 240),
			InputStroke = Color3.fromRGB(180, 190, 200),
			PlaceholderColor = Color3.fromRGB(150, 150, 150)
		},
	}
}




-- Interface Management

local RayfieldAssetId = customAssetId or 10804731440
local Rayfield = useStudio and script.Parent:FindFirstChild('Rayfield') or game:GetObjects("rbxassetid://"..RayfieldAssetId)[1]
local buildAttempts = 0
local correctBuild = false
local warned
local globalLoaded
local rayfieldDestroyed = false -- True when RayfieldLibrary:Destroy() is called

-- Rayfield's own heartbeat. About 1 in 200 sessions take part, and each one that does pings every
-- HEARTBEAT_PERIOD for as long as Rayfield stays loaded. One ping per sampled load left gaps of
-- several minutes at quiet hours, which the monitor read as an outage; a sampled session that
-- keeps pinging covers those gaps without sampling more people. Like the reporter it waits for the
-- player's analytics choice, and sends nothing when they or the developer have turned it off.
if not requestsDisabled and not analyticsOptOut and not useStudio and math.random(200) == 1 then
	task.defer(function()
		local url = HEARTBEAT_BASE .. "81074364b461f8da81bad6fdc363c3b927f884d6fc28d806a15ee50ca1e68c78"
		if not awaitAnalyticsConsent(function() return not rayfieldDestroyed end) then
			return
		end
		-- the first ping skips the interface check: a script that hasn't opened a window on an
		-- executor without files gets here before the interface is parented
		sendHeartbeat(url)
		while true do
			task.wait(HEARTBEAT_PERIOD)
			if rayfieldDestroyed or not Rayfield or Rayfield.Parent == nil or Rayfield.Name == "Rayfield-Old" then
				break
			end
			if not analyticsAllowed() then
				break
			end
			sendHeartbeat(url)
		end
	end)
end

repeat
	if Rayfield:FindFirstChild('Build') and Rayfield.Build.Value == InterfaceBuild then
		correctBuild = true
		break
	end

	correctBuild = false

	if not warned then
		warn('Rayfield | Build Mismatch')
		print('Rayfield may encounter issues as you are running an incompatible interface version ('.. ((Rayfield:FindFirstChild('Build') and Rayfield.Build.Value) or 'No Build') ..').\n\nThis version of Rayfield is intended for interface build '..InterfaceBuild..'.')
		warned = true
	end

	local toDestroy
	toDestroy, Rayfield = Rayfield, useStudio and script.Parent:FindFirstChild('Rayfield') or game:GetObjects("rbxassetid://"..RayfieldAssetId)[1]
	if toDestroy and not useStudio then toDestroy:Destroy() end

	buildAttempts = buildAttempts + 1
until buildAttempts >= 2

Rayfield.Enabled = false

if gethui then
	Rayfield.Parent = gethui()
elseif syn and syn.protect_gui then 
	syn.protect_gui(Rayfield)
	Rayfield.Parent = CoreGui
elseif not useStudio and CoreGui:FindFirstChild("RobloxGui") then
	Rayfield.Parent = CoreGui:FindFirstChild("RobloxGui")
elseif not useStudio then
	Rayfield.Parent = CoreGui
end

-- Running a script again loads a second copy of Rayfield. The copy it replaces is torn down through
-- this event, which calls its Destroy: that removes its interface and disconnects its input
-- listeners, which would otherwise keep answering hotkeys for a window nobody can see. Builds
-- before 1.753 have no event, so those are only hidden and renamed, as before.
local TEARDOWN_EVENT = "RayfieldTeardown"

local function retireInterface(Interface: any)
	Interface.Enabled = false
	Interface.Name = "Rayfield-Old"
	local teardown = Interface:FindFirstChild(TEARDOWN_EVENT)
	if teardown and teardown:IsA("BindableEvent") then
		pcall(function()
			teardown:Fire()
		end)
	end
end

if gethui then
	for _, Interface in ipairs(gethui():GetChildren()) do
		if Interface.Name == Rayfield.Name and Interface ~= Rayfield then
			retireInterface(Interface)
		end
	end
elseif not useStudio then
	for _, Interface in ipairs(CoreGui:GetChildren()) do
		if Interface.Name == Rayfield.Name and Interface ~= Rayfield then
			retireInterface(Interface)
		end
	end
end

do
	local teardown = Instance.new("BindableEvent")
	teardown.Name = TEARDOWN_EVENT
	teardown.Event:Connect(function()
		if not rayfieldDestroyed and type(RayfieldLibrary.Destroy) == "function" then
			RayfieldLibrary:Destroy()
		end
	end)
	teardown.Parent = Rayfield
end

if secureMode and not customAssetId then
	secureNotify("default_asset", "Secure Mode", "You are using the default Rayfield asset ID. Set RAYFIELD_ASSET_ID to a custom upload to avoid detection.")
end

do
	local AssetPath = RayfieldFolder.."/Assets"
	local AssetBaseURL = "https://github.com/SiriusSoftwareLtd/Rayfield/blob/main/assets/"

	local assetFiles = {
		["111263549366178"] = AssetBaseURL.."111263549366178.png?raw=true",
		["77891951053543"] = AssetBaseURL.."77891951053543.png?raw=true",
		["78137979054938"] = AssetBaseURL.."78137979054938.png?raw=true",
		["80503127983237"] = AssetBaseURL.."80503127983237.png?raw=true",
		["10137832201"] = AssetBaseURL.."10137832201.png?raw=true",
		["10137941941"] = AssetBaseURL.."10137941941.png?raw=true",
		["11036884234"] = AssetBaseURL.."11036884234.png?raw=true",
		["11413591840"] = AssetBaseURL.."11413591840.png?raw=true",
		["11745872910"] = AssetBaseURL.."11745872910.png?raw=true",
		["12577727209"] = AssetBaseURL.."12577727209.png?raw=true",
		["18458939117"] = AssetBaseURL.."18458939117.png?raw=true",
		["3259050989"] = AssetBaseURL.."3259050989.png?raw=true",
		["3523728077"] = AssetBaseURL.."3523728077.png?raw=true",
		["3602733521"] = AssetBaseURL.."3602733521.png?raw=true",
		["IconChevronTopMedium"] = AssetBaseURL.."IconChevronTopMedium.png?raw=true",
		["4483362458"] = AssetBaseURL.."4483362458.png?raw=true",
		["5587865193"] = AssetBaseURL.."5587865193.png?raw=true",
		["IconMagnifyingGlass2"] = AssetBaseURL.."IconMagnifyingGlass2.png?raw=true",
	}

	for id, _ in assetFiles do
		customAssets[tostring(id)] = ""
	end

	local hasCustomAsset = type(getcustomasset) == "function"
	local hasFilesystem = type(writefile) == "function" and type(makefolder) == "function" and type(isfile) == "function" and type(isfolder) == "function"

	if hasCustomAsset and hasFilesystem then
		local ok, err = pcall(function()
			ensureFolder(RayfieldFolder)
			ensureFolder(AssetPath)

			-- skip ids we've already tried so a dead asset can't loop the loader forever
			local attempted = {}
			local function nextToFetch()
				for id, _ in assetFiles do
					if not attempted[id] and not isfile(AssetPath.."/"..tostring(id)..".png") then
						return id
					end
				end
				return nil
			end

			if nextToFetch() then
				task.spawn(function()
					while true do
						local id = nextToFetch()
						if not id then break end
						-- a failed request can hand back a nil/empty Body — never pass that to writefile
						local ok, res = pcall(requestFunc, {Url = assetFiles[id], Method = "GET"})
						if ok and type(res) == "table" and type(res.Body) == "string" and #res.Body > 0 then
							pcall(writefile, AssetPath.."/"..tostring(id)..".png", res.Body)
						end
						-- mark after the attempt so the poll waits for real downloads but still skips a dead asset
						attempted[id] = true
						task.wait()
					end
				end)

				while nextToFetch() do
					task.wait(0.1)
				end
			end

			for id, _ in assetFiles do
				local success, asset = pcall(getcustomasset, AssetPath.."/"..tostring(id)..".png")
				if success then
					customAssets[tostring(id)] = asset
				else
					warn("Rayfield | Failed to load custom asset: "..tostring(id).." - "..tostring(asset))
				end
			end
		end)

		if not ok then
			warn("Rayfield | Failed to load custom assets: "..tostring(err))
			secureNotify("asset_load_fail", "Rayfield", "Failed to load custom assets. UI images may not display correctly.")
		end
	else
		secureNotify("no_getcustomasset", "Rayfield", "Your executor does not support getcustomasset. Some UI images may not render correctly.")
	end


	Rayfield.Main.Shadow.Image.Image = customAssets[tostring(5587865193)]
	Rayfield.Main.Topbar.Hide.Image = customAssets[tostring(10137832201)]
	Rayfield.Main.Topbar.ChangeSize.Image = customAssets[tostring(10137941941)]
	Rayfield.Main.Topbar.Settings.Image = customAssets[tostring(80503127983237)]
	Rayfield.Main.Topbar.Icon.Image = customAssets[tostring(78137979054938)]
	Rayfield.Main.Topbar.Search.Image = customAssets["IconMagnifyingGlass2"]
	Rayfield.Main.Topbar.Search.ImageRectOffset = Vector2.new(0, 0)
	Rayfield.Main.Topbar.Search.ImageRectSize = Vector2.new(0, 0)
	Rayfield.Main.Elements.Template.Toggle.Switch.Shadow.Image = customAssets[tostring(3602733521)]
	Rayfield.Main.Elements.Template.Slider.Main.Shadow.Image = customAssets[tostring(3602733521)]
	Rayfield.Main.Elements.Template.Dropdown.Toggle.Image = customAssets["IconChevronTopMedium"]
	Rayfield.Main.Elements.Template.Dropdown.Toggle.ImageRectOffset = Vector2.new(0, 0)
	Rayfield.Main.Elements.Template.Dropdown.Toggle.ImageRectSize = Vector2.new(0, 0)
	Rayfield.Main.Elements.Template.Label.Icon.Image = customAssets[tostring(11745872910)]
	Rayfield.Main.Elements.Template.ColorPicker.CPBackground.MainCP.Image = customAssets[tostring(11413591840)]
	Rayfield.Main.Elements.Template.ColorPicker.CPBackground.MainCP.MainPoint.Image = customAssets[tostring(3259050989)]
	Rayfield.Main.Elements.Template.ColorPicker.ColorSlider.SliderPoint.Image = customAssets[tostring(3259050989)]
	Rayfield.Main.TabList.Template.Image.Image = customAssets[tostring(4483362458)]
	Rayfield.Main.Search.Search.Image = customAssets[tostring(18458939117)]
	Rayfield.Main.Search.Shadow.Image = customAssets[tostring(5587865193)]
	Rayfield.Notifications.Template.Icon.Image = customAssets[tostring(77891951053543)]
	Rayfield.Notifications.Template.Shadow.Image = customAssets[tostring(3523728077)]
	Rayfield.Loading.Banner.Image = customAssets[tostring(111263549366178)]

end -- custom asset block

local minSize = Vector2.new(1024, 768)
local useMobileSizing

if Rayfield.AbsoluteSize.X < minSize.X and Rayfield.AbsoluteSize.Y < minSize.Y then
	useMobileSizing = true
end

local useMobilePrompt = false
if UserInputService.TouchEnabled then
	useMobilePrompt = true
end


-- Object Variables

local Main = Rayfield.Main
local MPrompt = Rayfield:FindFirstChild('Prompt')
local Topbar = Main.Topbar
local Elements = Main.Elements
local LoadingFrame = Main.LoadingFrame
local TabList = Main.TabList
local dragBar = Rayfield:FindFirstChild('Drag')
local dragInteract = dragBar and dragBar.Interact or nil
local dragBarCosmetic = dragBar and dragBar.Drag or nil

local dragOffset = 255
local dragOffsetMobile = 150

Rayfield.DisplayOrder = 100
LoadingFrame.Version.Text = Release

-- Thanks to Latte Softworks for the Lucide integration for Roblox
local Icons = useStudio and require(script.Parent.icons) or loadWithTimeout(RAYFIELD_RAW .. 'icons.lua')
-- Variables

local CFileName = nil
local CLegacyFileName = nil -- the place-only file name configs had before Build 1.753, read as a fallback
local CEnabled = false
local Minimised = false
local Hidden = false
local Debounce = false
local searchOpen = false
local Notifications = Rayfield.Notifications
local keybindConnections = {} -- For storing keybind connections to disconnect when Rayfield is destroyed

local SelectedTheme = RayfieldLibrary.Theme.Default

local function ChangeTheme(Theme)
	if typeof(Theme) == 'string' then
		SelectedTheme = RayfieldLibrary.Theme[Theme]
	elseif typeof(Theme) == 'table' then
		SelectedTheme = Theme
	end

	Rayfield.Main.BackgroundColor3 = SelectedTheme.Background
	Rayfield.Main.Topbar.BackgroundColor3 = SelectedTheme.Topbar
	Rayfield.Main.Topbar.CornerRepair.BackgroundColor3 = SelectedTheme.Topbar
	Rayfield.Main.Shadow.Image.ImageColor3 = SelectedTheme.Shadow

	Rayfield.Main.Topbar.ChangeSize.ImageColor3 = SelectedTheme.TextColor
	Rayfield.Main.Topbar.Hide.ImageColor3 = SelectedTheme.TextColor
	Rayfield.Main.Topbar.Search.ImageColor3 = SelectedTheme.TextColor
	if Topbar:FindFirstChild('Settings') then
		Rayfield.Main.Topbar.Settings.ImageColor3 = SelectedTheme.TextColor
		Rayfield.Main.Topbar.Divider.BackgroundColor3 = SelectedTheme.ElementStroke
	end

	Main.Search.BackgroundColor3 = SelectedTheme.TextColor
	Main.Search.Shadow.ImageColor3 = SelectedTheme.TextColor
	Main.Search.Search.ImageColor3 = SelectedTheme.TextColor
	Main.Search.Input.PlaceholderColor3 = SelectedTheme.TextColor
	Main.Search.UIStroke.Color = SelectedTheme.SecondaryElementStroke

	if Main:FindFirstChild('Notice') then
		Main.Notice.BackgroundColor3 = SelectedTheme.Background
	end

	for _, text in ipairs(Rayfield:GetDescendants()) do
		if text.Parent.Parent ~= Notifications then
			if text:IsA('TextLabel') or text:IsA('TextBox') then text.TextColor3 = SelectedTheme.TextColor end
		end
	end

	for _, TabPage in ipairs(Elements:GetChildren()) do
		for _, Element in ipairs(TabPage:GetChildren()) do
			if Element.ClassName == "Frame" and Element.Name ~= "Placeholder" and Element.Name ~= "SectionSpacing" and Element.Name ~= "Divider" and Element.Name ~= "SectionTitle" and Element.Name ~= "SearchTitle-fsefsefesfsefesfesfThanks" then
				Element.BackgroundColor3 = SelectedTheme.ElementBackground
				Element.UIStroke.Color = SelectedTheme.ElementStroke
			end
		end
	end
end

local function getIcon(name : string): {id: number, imageRectSize: Vector2, imageRectOffset: Vector2}
	if not Icons then
		warn("Lucide Icons: Cannot use icons as icons library is not loaded")
		return
	end
	name = string.match(string.lower(name), "^%s*(.*)%s*$") :: string
	local sizedicons = Icons['48px']
	local r = sizedicons[name]
	if not r then
		error("Lucide Icons: Failed to find icon by the name of \"" .. name .. "\"", 2)
	end

	local rirs = r[2]
	local riro = r[3]

	if type(r[1]) ~= "number" or type(rirs) ~= "table" or type(riro) ~= "table" then
		error("Lucide Icons: Internal error: Invalid auto-generated asset entry")
	end

	local irs = Vector2.new(rirs[1], rirs[2])
	local iro = Vector2.new(riro[1], riro[2])

	local asset = {
		id = r[1],
		imageRectSize = irs,
		imageRectOffset = iro,
	}

	return asset
end
local function getAssetUri(id: any): string
	local assetUri = ""
	if type(id) == "number" then
		assetUri = "rbxassetid://" .. id
	elseif type(id) == "string" and not Icons then
		warn("Rayfield | Cannot use Lucide icons as icons library is not loaded")
	else
		warn("Rayfield | The icon argument must either be an icon ID (number) or a Lucide icon name (string)")
	end
	return assetUri
end

local function isCustomAsset(value)
	return type(value) == "string" and (string.find(value, "rbxasset://") == 1 or string.find(value, "rbxthumb://") == 1)
end

local function resolveIcon(icon)
	if not icon or icon == 0 then
		return "", nil, nil
	end

	if isCustomAsset(icon) then
		return icon, nil, nil
	end

	if secureMode then
		secureNotify("icon_blocked", "Secure Mode", "Element icons using asset IDs or Lucide names are blocked. Use getcustomasset() for icons to stay undetected.")
		return "", nil, nil
	end

	if typeof(icon) == "string" and Icons then
		local asset = getIcon(icon)
		return "rbxassetid://" .. asset.id, asset.imageRectOffset, asset.imageRectSize
	else
		return getAssetUri(icon), nil, nil
	end
end

local function makeDraggable(object, dragObject, enableTaptic, tapticOffset)
	local dragging = false
	local relative = nil

	local offset = Vector2.zero
	local screenGui = object:FindFirstAncestorWhichIsA("ScreenGui")
	if screenGui and screenGui.IgnoreGuiInset then
		offset += getService('GuiService'):GetGuiInset()
	end

	local function connectFunctions()
		if dragBar and enableTaptic then
			dragBar.MouseEnter:Connect(function()
				if not dragging and not Hidden then
					TweenService:Create(dragBarCosmetic, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {BackgroundTransparency = 0.5, Size = UDim2.new(0, 120, 0, 4)}):Play()
				end
			end)

			dragBar.MouseLeave:Connect(function()
				if not dragging and not Hidden then
					TweenService:Create(dragBarCosmetic, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {BackgroundTransparency = 0.7, Size = UDim2.new(0, 100, 0, 4)}):Play()
				end
			end)
		end
	end

	connectFunctions()

	dragObject.InputBegan:Connect(function(input, processed)
		if processed then return end

		local inputType = input.UserInputType.Name
		if inputType == "MouseButton1" or inputType == "Touch" then
			dragging = true

			relative = object.AbsolutePosition + object.AbsoluteSize * object.AnchorPoint - UserInputService:GetMouseLocation()
			if enableTaptic and not Hidden then
				TweenService:Create(dragBarCosmetic, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 110, 0, 4), BackgroundTransparency = 0}):Play()
			end
		end
	end)

	local inputEnded = UserInputService.InputEnded:Connect(function(input)
		if not dragging then return end

		local inputType = input.UserInputType.Name
		if inputType == "MouseButton1" or inputType == "Touch" then
			dragging = false

			if enableTaptic and not Hidden then
				TweenService:Create(dragBarCosmetic, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 100, 0, 4), BackgroundTransparency = 0.7}):Play()
			end
		end
	end)

	local renderStepped = RunService.RenderStepped:Connect(function()
		if dragging and not Hidden then
			local position = UserInputService:GetMouseLocation() + relative + offset
			if enableTaptic and tapticOffset then
				TweenService:Create(object, TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Position = UDim2.fromOffset(position.X, position.Y)}):Play()
				TweenService:Create(dragObject.Parent, TweenInfo.new(0.05, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Position = UDim2.fromOffset(position.X, position.Y + ((useMobileSizing and tapticOffset[2]) or tapticOffset[1]))}):Play()
			else
				if dragBar and tapticOffset then
					dragBar.Position = UDim2.fromOffset(position.X, position.Y + ((useMobileSizing and tapticOffset[2]) or tapticOffset[1]))
				end
				object.Position = UDim2.fromOffset(position.X, position.Y)
			end
		end
	end)

	object.Destroying:Connect(function()
		if inputEnded then inputEnded:Disconnect() end
		if renderStepped then renderStepped:Disconnect() end
	end)
end


local function PackColor(Color)
	return {R = Color.R * 255, G = Color.G * 255, B = Color.B * 255}
end    

local function UnpackColor(Color)
	return Color3.fromRGB(Color.R, Color.G, Color.B)
end

local function LoadConfiguration(Configuration)
	local success, Data = pcall(function() return HttpService:JSONDecode(Configuration) end)
	local changed

	if not success then warn('Rayfield had an issue decoding the configuration file, please try delete the file and reopen Rayfield.') return end

	-- Iterate through current UI elements' flags
	for FlagName, Flag in pairs(RayfieldLibrary.Flags) do
		local FlagValue = Data[FlagName]

		if (typeof(FlagValue) == 'boolean' and FlagValue == false) or FlagValue then
			task.spawn(function()
				if Flag.Type == "ColorPicker" then
					changed = true
					Flag:Set(UnpackColor(FlagValue))
				else
					if (Flag.CurrentValue or Flag.CurrentKeybind or Flag.CurrentOption or Flag.Color) ~= FlagValue then 
						changed = true
						Flag:Set(FlagValue) 	
					end
				end
			end)
		else
			warn("Rayfield | Unable to find '"..FlagName.. "' in the save file.")
			print("The error above may not be an issue if new elements have been added or not been set values.")
			--RayfieldLibrary:Notify({Title = "Rayfield Flags", Content = "Rayfield was unable to find '"..FlagName.. "' in the save file. Check sirius.menu/discord for help.", Image = 3944688398})
		end
	end

	return changed
end

local function SaveConfiguration()
	if not CEnabled or not globalLoaded then return end

	if debugX then
		print('Saving')
	end

	local Data = {}
	for i, v in pairs(RayfieldLibrary.Flags) do
		if v.Type == "ColorPicker" then
			Data[i] = PackColor(v.Color)
		else
			if typeof(v.CurrentValue) == 'boolean' then
				if v.CurrentValue == false then
					Data[i] = false
				else
					Data[i] = v.CurrentValue or v.CurrentKeybind or v.CurrentOption or v.Color
				end
			else
				Data[i] = v.CurrentValue or v.CurrentKeybind or v.CurrentOption or v.Color
			end
		end
	end

	if useStudio then
		if script.Parent:FindFirstChild('configuration') then script.Parent.configuration:Destroy() end

		local ScreenGui = Instance.new("ScreenGui")
		ScreenGui.Parent = script.Parent
		ScreenGui.Name = 'configuration'

		local TextBox = Instance.new("TextBox")
		TextBox.Parent = ScreenGui
		TextBox.Size = UDim2.new(0, 800, 0, 50)
		TextBox.AnchorPoint = Vector2.new(0.5, 0)
		TextBox.Position = UDim2.new(0.5, 0, 0, 30)
		TextBox.Text = HttpService:JSONEncode(Data)
		TextBox.ClearTextOnFocus = false
	end

	if debugX then
		warn(HttpService:JSONEncode(Data))
	end


	callSafely(writefile, ConfigurationFolder .. "/" .. CFileName .. ConfigurationExtension, tostring(HttpService:JSONEncode(Data)))
end

function RayfieldLibrary:Notify(data) -- action e.g open messages
	-- a destroyed interface has no template left to clone
	if rayfieldDestroyed then return end
	task.spawn(function()

		-- Notification Object Creation
		local newNotification = Notifications.Template:Clone()
		newNotification.Name = data.Title or 'No Title Provided'
		newNotification.Parent = Notifications
		newNotification.LayoutOrder = #Notifications:GetChildren()
		newNotification.Visible = false

		-- Set Data
		newNotification.Title.Text = data.Title or "Unknown Title"
		newNotification.Description.Text = data.Content or "Unknown Content"

		if data.Image then
			local img, rectOffset, rectSize = resolveIcon(data.Image)
			newNotification.Icon.Image = img
			if rectOffset then newNotification.Icon.ImageRectOffset = rectOffset end
			if rectSize then newNotification.Icon.ImageRectSize = rectSize end
		else
			newNotification.Icon.Image = ""
		end

		-- Set initial transparency values

		newNotification.Title.TextColor3 = SelectedTheme.TextColor
		newNotification.Description.TextColor3 = SelectedTheme.TextColor
		newNotification.BackgroundColor3 = SelectedTheme.Background
		newNotification.UIStroke.Color = SelectedTheme.TextColor
		newNotification.Icon.ImageColor3 = SelectedTheme.TextColor

		newNotification.BackgroundTransparency = 1
		newNotification.Title.TextTransparency = 1
		newNotification.Description.TextTransparency = 1
		newNotification.UIStroke.Transparency = 1
		newNotification.Shadow.ImageTransparency = 1
		newNotification.Size = UDim2.new(1, 0, 0, 800)
		newNotification.Icon.ImageTransparency = 1
		newNotification.Icon.BackgroundTransparency = 1

		task.wait()

		newNotification.Visible = true

		if data.Actions then
			warn('Rayfield | Not seeing your actions in notifications?')
			print("Notification Actions are being sunset for now, keep up to date on when they're back in the discord. (sirius.menu/discord)")
		end

		-- Calculate textbounds and set initial values
		local bounds = {newNotification.Title.TextBounds.Y, newNotification.Description.TextBounds.Y}
		newNotification.Size = UDim2.new(1, -60, 0, -Notifications:FindFirstChild("UIListLayout").Padding.Offset)

		newNotification.Icon.Size = UDim2.new(0, 32, 0, 32)
		newNotification.Icon.Position = UDim2.new(0, 20, 0.5, 0)

		TweenService:Create(newNotification, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, 0, 0, math.max(bounds[1] + bounds[2] + 31, 60))}):Play()

		task.wait(0.15)
		TweenService:Create(newNotification, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.45}):Play()
		TweenService:Create(newNotification.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()

		task.wait(0.05)

		TweenService:Create(newNotification.Icon, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 0}):Play()

		task.wait(0.05)
		TweenService:Create(newNotification.Description, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0.35}):Play()
		TweenService:Create(newNotification.UIStroke, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {Transparency = 0.95}):Play()
		TweenService:Create(newNotification.Shadow, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 0.82}):Play()

		local waitDuration = math.min(math.max((#newNotification.Description.Text * 0.1) + 2.5, 3), 10)
		task.wait(data.Duration or waitDuration)

		newNotification.Icon.Visible = false
		TweenService:Create(newNotification, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
		TweenService:Create(newNotification.UIStroke, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
		TweenService:Create(newNotification.Shadow, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
		TweenService:Create(newNotification.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
		TweenService:Create(newNotification.Description, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()

		TweenService:Create(newNotification, TweenInfo.new(1, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, -90, 0, 0)}):Play()

		task.wait(1)

		TweenService:Create(newNotification, TweenInfo.new(1, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, -90, 0, -Notifications:FindFirstChild("UIListLayout").Padding.Offset)}):Play()

		newNotification.Visible = false
		newNotification:Destroy()
	end)
end

local function openSearch()
	searchOpen = true

	Main.Search.BackgroundTransparency = 1
	Main.Search.Shadow.ImageTransparency = 1
	Main.Search.Input.TextTransparency = 1
	Main.Search.Search.ImageTransparency = 1
	Main.Search.UIStroke.Transparency = 1
	Main.Search.Size = UDim2.new(1, 0, 0, 80)
	Main.Search.Position = UDim2.new(0.5, 0, 0, 70)

	Main.Search.Input.Interactable = true

	Main.Search.Visible = true

	for _, tabbtn in ipairs(TabList:GetChildren()) do
		if tabbtn.ClassName == "Frame" and tabbtn.Name ~= "Placeholder" then
			tabbtn.Interact.Visible = false
			TweenService:Create(tabbtn, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
			TweenService:Create(tabbtn.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
			TweenService:Create(tabbtn.Image, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
			TweenService:Create(tabbtn.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
		end
	end

	Main.Search.Input:CaptureFocus()
	TweenService:Create(Main.Search.Shadow, TweenInfo.new(0.05, Enum.EasingStyle.Quint), {ImageTransparency = 0.95}):Play()
	TweenService:Create(Main.Search, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Position = UDim2.new(0.5, 0, 0, 57), BackgroundTransparency = 0.9}):Play()
	TweenService:Create(Main.Search.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 0.8}):Play()
	TweenService:Create(Main.Search.Input, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0.2}):Play()
	TweenService:Create(Main.Search.Search, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 0.5}):Play()
	TweenService:Create(Main.Search, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, -35, 0, 35)}):Play()
end

local function closeSearch()
	searchOpen = false

	TweenService:Create(Main.Search, TweenInfo.new(0.35, Enum.EasingStyle.Quint), {BackgroundTransparency = 1, Size = UDim2.new(1, -55, 0, 30)}):Play()
	TweenService:Create(Main.Search.Search, TweenInfo.new(0.15, Enum.EasingStyle.Quint), {ImageTransparency = 1}):Play()
	TweenService:Create(Main.Search.Shadow, TweenInfo.new(0.15, Enum.EasingStyle.Quint), {ImageTransparency = 1}):Play()
	TweenService:Create(Main.Search.UIStroke, TweenInfo.new(0.15, Enum.EasingStyle.Quint), {Transparency = 1}):Play()
	TweenService:Create(Main.Search.Input, TweenInfo.new(0.15, Enum.EasingStyle.Quint), {TextTransparency = 1}):Play()

	for _, tabbtn in ipairs(TabList:GetChildren()) do
		if tabbtn.ClassName == "Frame" and tabbtn.Name ~= "Placeholder" then
			tabbtn.Interact.Visible = true
			if tostring(Elements.UIPageLayout.CurrentPage) == tabbtn.Title.Text then
				TweenService:Create(tabbtn, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
				TweenService:Create(tabbtn.Image, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 0}):Play()
				TweenService:Create(tabbtn.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
				TweenService:Create(tabbtn.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
			else
				TweenService:Create(tabbtn, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.7}):Play()
				TweenService:Create(tabbtn.Image, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 0.2}):Play()
				TweenService:Create(tabbtn.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0.2}):Play()
				TweenService:Create(tabbtn.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
			end
		end
	end

	Main.Search.Input.Text = ''
	Main.Search.Input.Interactable = false
end

-- Sets element visibility across all tab pages (used by Hide, Unhide, Maximise, Minimise)
local function setElementsVisible(show)
	for _, tab in ipairs(Elements:GetChildren()) do
		if tab.Name ~= "Template" and tab.ClassName == "ScrollingFrame" and tab.Name ~= "Placeholder" then
			for _, element in ipairs(tab:GetChildren()) do
				if element.ClassName == "Frame" then
					if element.Name ~= "SectionSpacing" and element.Name ~= "Placeholder" then
						if element.Name == "SectionTitle" or element.Name == 'SearchTitle-fsefsefesfsefesfesfThanks' then
							TweenService:Create(element.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = show and 0.4 or 1}):Play()
						elseif element.Name == 'Divider' then
							TweenService:Create(element.Divider, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = show and 0.85 or 1}):Play()
						else
							local bgTarget = element:GetAttribute("BackgroundTransparencyTarget") or 0
							local strokeTarget = element:GetAttribute("UIStrokeTransparencyTarget") or 0
							local titleTarget = element:GetAttribute("TitleTextTransparencyTarget") or 0
							TweenService:Create(element, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = show and bgTarget or 1}):Play()
							TweenService:Create(element.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = show and strokeTarget or 1}):Play()
							TweenService:Create(element.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = show and titleTarget or 1}):Play()
						end
						for _, child in ipairs(element:GetChildren()) do
							if child.ClassName == "Frame" or child.ClassName == "TextLabel" or child.ClassName == "TextBox" or child.ClassName == "ImageButton" or child.ClassName == "ImageLabel" then
								child.Visible = show
							end
						end
					end
				end
			end
		end
	end
end

-- Sets tab button visibility (used by Hide, Unhide, Maximise, Minimise)
local function setTabButtonsVisible(show)
	for _, tabbtn in ipairs(TabList:GetChildren()) do
		if tabbtn.ClassName == "Frame" and tabbtn.Name ~= "Placeholder" then
			if show then
				if tostring(Elements.UIPageLayout.CurrentPage) == tabbtn.Title.Text then
					TweenService:Create(tabbtn, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
					TweenService:Create(tabbtn.Image, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 0}):Play()
					TweenService:Create(tabbtn.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
					TweenService:Create(tabbtn.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
				else
					TweenService:Create(tabbtn, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.7}):Play()
					TweenService:Create(tabbtn.Image, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 0.2}):Play()
					TweenService:Create(tabbtn.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0.2}):Play()
					TweenService:Create(tabbtn.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
				end
			else
				TweenService:Create(tabbtn, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
				TweenService:Create(tabbtn.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
				TweenService:Create(tabbtn.Image, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
				TweenService:Create(tabbtn.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
			end
		end
	end
end

local function Hide(notify: boolean?)
	if MPrompt then
		MPrompt.Title.TextColor3 = Color3.fromRGB(255, 255, 255)
		MPrompt.Position = UDim2.new(0.5, 0, 0, -50)
		MPrompt.Size = UDim2.new(0, 40, 0, 10)
		MPrompt.BackgroundTransparency = 1
		MPrompt.Title.TextTransparency = 1
		MPrompt.Visible = true
	end

	task.spawn(closeSearch)

	Debounce = true
	if notify then
		if useMobilePrompt then 
			RayfieldLibrary:Notify({Title = "Interface Hidden", Content = "The interface has been hidden, you can unhide the interface by tapping 'Show'.", Duration = 7, Image = 4400697855})
		else
			RayfieldLibrary:Notify({Title = "Interface Hidden", Content = "The interface has been hidden, you can unhide the interface by tapping " .. tostring(getSetting("General", "rayfieldOpen")) .. ".", Duration = 7, Image = 4400697855})
		end
	end

	TweenService:Create(Main, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 470, 0, 0)}):Play()
	TweenService:Create(Main.Topbar, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 470, 0, 45)}):Play()
	TweenService:Create(Main, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
	TweenService:Create(Main.Topbar, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
	TweenService:Create(Main.Topbar.Divider, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
	TweenService:Create(Main.Topbar.CornerRepair, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
	TweenService:Create(Main.Topbar.Title, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
	TweenService:Create(Main.Shadow.Image, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
	TweenService:Create(Topbar.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
	if dragBarCosmetic then
		TweenService:Create(dragBarCosmetic, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
	end

	if useMobilePrompt and MPrompt then
		TweenService:Create(MPrompt, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 120, 0, 30), Position = UDim2.new(0.5, 0, 0, 20), BackgroundTransparency = 0.3}):Play()
		TweenService:Create(MPrompt.Title, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {TextTransparency = 0.3}):Play()
	end

	for _, TopbarButton in ipairs(Topbar:GetChildren()) do
		if TopbarButton.ClassName == "ImageButton" then
			TweenService:Create(TopbarButton, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
		end
	end

	setTabButtonsVisible(false)

	if dragInteract then dragInteract.Visible = false end

	setElementsVisible(false)

	task.wait(0.5)
	Main.Visible = false
	Debounce = false
end

local function Maximise()
	Debounce = true
	Topbar.ChangeSize.Image = customAssets[tostring(10137941941)]

	TweenService:Create(Topbar.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
	TweenService:Create(Main.Shadow.Image, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {ImageTransparency = 0.6}):Play()
	TweenService:Create(Topbar.CornerRepair, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
	TweenService:Create(Topbar.Divider, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
	TweenService:Create(dragBarCosmetic, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {BackgroundTransparency = 0.7}):Play()
	TweenService:Create(Main, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = useMobileSizing and UDim2.new(0, 500, 0, 275) or UDim2.new(0, 500, 0, 475)}):Play()
	TweenService:Create(Topbar, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 500, 0, 45)}):Play()
	TabList.Visible = true
	task.wait(0.2)

	Elements.Visible = true

	setElementsVisible(true)

	task.wait(0.1)

	setTabButtonsVisible(true)

	task.wait(0.5)
	Debounce = false
end


local function Unhide()
	Debounce = true
	Main.Position = UDim2.new(0.5, 0, 0.5, 0)
	Main.Visible = true
	TweenService:Create(Main, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = useMobileSizing and UDim2.new(0, 500, 0, 275) or UDim2.new(0, 500, 0, 475)}):Play()
	TweenService:Create(Main.Topbar, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 500, 0, 45)}):Play()
	TweenService:Create(Main.Shadow.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0.6}):Play()
	TweenService:Create(Main, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
	TweenService:Create(Main.Topbar, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
	TweenService:Create(Main.Topbar.Divider, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
	TweenService:Create(Main.Topbar.CornerRepair, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
	TweenService:Create(Main.Topbar.Title, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()

	if MPrompt then
		TweenService:Create(MPrompt, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 40, 0, 10), Position = UDim2.new(0.5, 0, 0, -50), BackgroundTransparency = 1}):Play()
		TweenService:Create(MPrompt.Title, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()

		task.spawn(function()
			task.wait(0.5)
			MPrompt.Visible = false
		end)
	end

	if Minimised then
		task.spawn(Maximise)
	end

	dragBar.Position = useMobileSizing and UDim2.new(0.5, 0, 0.5, dragOffsetMobile) or UDim2.new(0.5, 0, 0.5, dragOffset)

	dragInteract.Visible = true

	for _, TopbarButton in ipairs(Topbar:GetChildren()) do
		if TopbarButton.ClassName == "ImageButton" then
			if TopbarButton.Name == 'Icon' then
				TweenService:Create(TopbarButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0}):Play()
			else
				TweenService:Create(TopbarButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0.8}):Play()
			end

		end
	end

	setTabButtonsVisible(true)

	setElementsVisible(true)

	TweenService:Create(dragBarCosmetic, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {BackgroundTransparency = 0.5}):Play()

	task.wait(0.5)
	Minimised = false
	Debounce = false
end

local function Minimise()
	Debounce = true
	Topbar.ChangeSize.Image = customAssets[tostring(11036884234)]

	Topbar.UIStroke.Color = SelectedTheme.ElementStroke

	task.spawn(closeSearch)

	setTabButtonsVisible(false)

	setElementsVisible(false)

	TweenService:Create(dragBarCosmetic, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
	TweenService:Create(Topbar.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
	TweenService:Create(Main.Shadow.Image, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
	TweenService:Create(Topbar.CornerRepair, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
	TweenService:Create(Topbar.Divider, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
	TweenService:Create(Main, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 495, 0, 45)}):Play()
	TweenService:Create(Topbar, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 495, 0, 45)}):Play()

	task.wait(0.3)

	Elements.Visible = false
	TabList.Visible = false

	task.wait(0.2)
	Debounce = false
end

local function saveSettings() -- Save settings to config file
	local encoded
	local success, err = pcall(function()
		encoded = HttpService:JSONEncode(settingsTable)
	end)

	if success then
		if useStudio then
			if script.Parent['get.val'] then
				script.Parent['get.val'].Value = encoded
			end
		end
		callSafely(writefile, RayfieldFolder..'/settings'..ConfigurationExtension, encoded)
	end
end

local function updateSetting(category: string, setting: string, value: any)
	if not settingsInitialized then
		return
	end
	settingsTable[category][setting].Value = value
	overriddenSettings[category .. "." .. setting] = nil -- If user changes an overriden setting, remove the override
	saveSettings()

	-- Turning analytics off mid-session also stops anything already armed, like the kick watcher.
	if category == "System" and setting == "usageAnalytics" and not value and reporter and reporter.disable then
		pcall(reporter.disable, reporter)
	end
end

local function createSettings(window)
	if not (writefile and isfile and readfile and isfolder and makefolder) and not useStudio then
		if Topbar['Settings'] then Topbar.Settings.Visible = false end
		Topbar['Search'].Position = UDim2.new(1, -75, 0.5, 0)
		warn('Can\'t create settings as no file-saving functionality is available.')
		return
	end

	local newTab = window:CreateTab('Rayfield Settings', 0, true)

	if TabList['Rayfield Settings'] then
		TabList['Rayfield Settings'].LayoutOrder = 1000
	end

	if Elements['Rayfield Settings'] then
		Elements['Rayfield Settings'].LayoutOrder = 1000
	end

	-- Create sections and elements
	for categoryName, settingCategory in pairs(settingsTable) do
		newTab:CreateSection(categoryName)

		for settingName, setting in pairs(settingCategory) do
			if setting.Type == 'input' then
				setting.Element = newTab:CreateInput({
					Name = setting.Name,
					CurrentValue = setting.Value,
					PlaceholderText = setting.Placeholder,
					Ext = true,
					RemoveTextAfterFocusLost = setting.ClearOnFocus,
					Callback = function(Value)
						updateSetting(categoryName, settingName, Value)
					end,
				})
			elseif setting.Type == 'toggle' then
				setting.Element = newTab:CreateToggle({
					Name = setting.Name,
					CurrentValue = setting.Value,
					Ext = true,
					Callback = function(Value)
						updateSetting(categoryName, settingName, Value)
					end,
				})
				if setting.Description then
					newTab:CreateLabel(setting.Description)
				end
			elseif setting.Type == 'bind' then
				setting.Element = newTab:CreateKeybind({
					Name = setting.Name,
					CurrentKeybind = setting.Value,
					HoldToInteract = false,
					Ext = true,
					CallOnChange = true,
					Callback = function(Value)
						updateSetting(categoryName, settingName, Value)
					end,
				})
			end
		end
	end

	settingsCreated = true
	loadSettings()
	saveSettings()
end

local function fadeOutKeyUI(KeyMain)
	TweenService:Create(KeyMain, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
	TweenService:Create(KeyMain, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 467, 0, 175)}):Play()
	TweenService:Create(KeyMain.Shadow.Image, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
	TweenService:Create(KeyMain.Title, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
	TweenService:Create(KeyMain.Subtitle, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
	TweenService:Create(KeyMain.KeyNote, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
	TweenService:Create(KeyMain.Input, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
	TweenService:Create(KeyMain.Input.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
	TweenService:Create(KeyMain.Input.InputBox, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
	TweenService:Create(KeyMain.NoteTitle, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
	TweenService:Create(KeyMain.NoteMessage, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
	TweenService:Create(KeyMain.Hide, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
end

function RayfieldLibrary:CreateWindow(Settings)
	if Rayfield:FindFirstChild('Loading') then
		if getgenv and not getgenv().rayfieldCached then
			Rayfield.Enabled = true
			Rayfield.Loading.Visible = true

			task.wait(1.4)
			Rayfield.Loading.Visible = false
		end
	end

	if getgenv then getgenv().rayfieldCached = true end

	if not correctBuild and not Settings.DisableBuildWarnings then
		task.delay(3, 
			function() 
				RayfieldLibrary:Notify({Title = 'Build Mismatch', Content = 'Rayfield may encounter issues as you are running an incompatible interface version ('.. ((Rayfield:FindFirstChild('Build') and Rayfield.Build.Value) or 'No Build') ..').\n\nThis version of Rayfield is intended for interface build '..InterfaceBuild..'.\n\nTry rejoining and then run the script twice.', Image = 4335487866, Duration = 15})		
			end)
	end

	if Settings.ToggleUIKeybind then -- Can either be a string or an Enum.KeyCode
		local keybind = Settings.ToggleUIKeybind
		if type(keybind) == "string" then
			keybind = string.upper(keybind)
			assert(pcall(function()
				return Enum.KeyCode[keybind]
			end), "ToggleUIKeybind must be a valid KeyCode")
			overrideSetting("General", "rayfieldOpen", keybind)
		elseif typeof(keybind) == "EnumItem" then
			assert(keybind.EnumType == Enum.KeyCode, "ToggleUIKeybind must be a KeyCode enum")
			overrideSetting("General", "rayfieldOpen", keybind.Name)
		else
			error("ToggleUIKeybind must be a string or KeyCode enum")
		end
	end

	ensureFolder(RayfieldFolder)

	local Passthrough = false
	Topbar.Title.Text = Settings.Name

	Main.Size = UDim2.new(0, 420, 0, 100)
	Main.Visible = true
	Main.BackgroundTransparency = 1
	if Main:FindFirstChild('Notice') then Main.Notice.Visible = false end
	Main.Shadow.Image.ImageTransparency = 1

	LoadingFrame.Title.TextTransparency = 1
	LoadingFrame.Subtitle.TextTransparency = 1

	if Settings.ShowText then
		MPrompt.Title.Text = 'Show '..Settings.ShowText
	end

	LoadingFrame.Version.TextTransparency = 1
	LoadingFrame.Title.Text = Settings.LoadingTitle or "Rayfield"
	LoadingFrame.Subtitle.Text = Settings.LoadingSubtitle or "Interface Suite"

	if Settings.LoadingTitle ~= "Rayfield Interface Suite" then
		LoadingFrame.Version.Text = "Rayfield UI"
	end

	if Settings.Icon and Settings.Icon ~= 0 and Topbar:FindFirstChild('Icon') then
		Topbar.Icon.Visible = true
		Topbar.Title.Position = UDim2.new(0, 47, 0.5, 0)

		if Settings.Icon then
			local img, rectOffset, rectSize = resolveIcon(Settings.Icon)
			Topbar.Icon.Image = img
			if rectOffset then Topbar.Icon.ImageRectOffset = rectOffset end
			if rectSize then Topbar.Icon.ImageRectSize = rectSize end
		else
			Topbar.Icon.Image = ""
		end
	end

	if dragBar then
		dragBar.Visible = false
		dragBarCosmetic.BackgroundTransparency = 1
		dragBar.Visible = true
	end

	if Settings.Theme then
		local success, result = pcall(ChangeTheme, Settings.Theme)
		if not success then
			local success, result2 = pcall(ChangeTheme, 'Default')
			if not success then
				warn('CRITICAL ERROR - NO DEFAULT THEME')
				print(result2)
			end
			warn('issue rendering theme. no theme on file')
			print(result)
		end
	end

	Topbar.Visible = false
	Elements.Visible = false
	LoadingFrame.Visible = true

	if not Settings.DisableRayfieldPrompts then
		task.spawn(function()
			while not rayfieldDestroyed do
				task.wait(math.random(180, 600))
				if rayfieldDestroyed then break end
				RayfieldLibrary:Notify({
					Title = "Rayfield Interface",
					Content = "Enjoying this UI library? Find it at sirius.menu/discord",
					Duration = 7,
					Image = 4370033185,
				})
			end
		end)
	end

	pcall(function()
		-- Without a FileName the config used to be named after the place alone, so every hub in the
		-- same game wrote over the others'. It's now the hub's name and the place. That older file is
		-- still read when the new one doesn't exist yet, so nobody's saved settings go missing.
		CLegacyFileName = nil
		if not Settings.ConfigurationSaving.FileName then
			local placeName = tostring(game.PlaceId)
			-- window names often carry characters Windows refuses in a file name, like "|" or ":",
			-- and a trailing dot or space that it drops
			local hubName = string.gsub(sanitizeFileName(Settings.Name or ""), '[:<>"|?*]', "")
			hubName = string.match(hubName, "^%s*(.-)[%s%.]*$") or ""
			if hubName ~= "" then
				Settings.ConfigurationSaving.FileName = hubName .. "-" .. placeName
				CLegacyFileName = placeName
			else
				Settings.ConfigurationSaving.FileName = placeName
			end
		end

		if Settings.ConfigurationSaving.Enabled == nil then
			Settings.ConfigurationSaving.Enabled = false
		end

		CFileName = sanitizeFileName(Settings.ConfigurationSaving.FileName)
		if CFileName == "" then
			CFileName = tostring(game.PlaceId)
		end
		if Settings.ConfigurationSaving.FolderName then
			local folderName = sanitizeFolderName(Settings.ConfigurationSaving.FolderName)
			if folderName ~= "" then
				ConfigurationFolder = folderName
			end
		end
		CEnabled = Settings.ConfigurationSaving.Enabled

		if Settings.ConfigurationSaving.Enabled then
			ensureFolder(ConfigurationFolder)
		end
	end)


	makeDraggable(Main, Topbar, false, {dragOffset, dragOffsetMobile})
	if dragBar then dragBar.Position = useMobileSizing and UDim2.new(0.5, 0, 0.5, dragOffsetMobile) or UDim2.new(0.5, 0, 0.5, dragOffset) makeDraggable(Main, dragInteract, true, {dragOffset, dragOffsetMobile}) end

	for _, TabButton in ipairs(TabList:GetChildren()) do
		if TabButton.ClassName == "Frame" and TabButton.Name ~= "Placeholder" then
			TabButton.BackgroundTransparency = 1
			TabButton.Title.TextTransparency = 1
			TabButton.Image.ImageTransparency = 1
			TabButton.UIStroke.Transparency = 1
		end
	end

	if Settings.Discord and Settings.Discord.Enabled and not useStudio and not secureMode then
		ensureFolder(RayfieldFolder.."/Discord Invites")
		local inviteFile = RayfieldFolder.."/Discord Invites".."/"..sanitizeFileName(Settings.Discord.Invite)..ConfigurationExtension

		if not callSafely(isfile, inviteFile) then
			if requestFunc then
				pcall(function()
					requestFunc({
						Url = 'http://127.0.0.1:6463/rpc?v=1',
						Method = 'POST',
						Headers = {
							['Content-Type'] = 'application/json',
							Origin = 'https://discord.com'
						},
						Body = HttpService:JSONEncode({
							cmd = 'INVITE_BROWSER',
							nonce = HttpService:GenerateGUID(false),
							args = {code = Settings.Discord.Invite}
						})
					})
				end)
			end

			if Settings.Discord.RememberJoins then -- We do logic this way so if the developer changes this setting, the user still won't be prompted, only new users
				callSafely(writefile, inviteFile,"Rayfield RememberJoins is true for this invite, this invite will not ask you to join again")
			end
		end
	end

	if (Settings.KeySystem) then
		if not Settings.KeySettings then
			Passthrough = true
			return
		end

		ensureFolder(RayfieldFolder.."/Key System")

		if typeof(Settings.KeySettings.Key) == "string" then Settings.KeySettings.Key = {Settings.KeySettings.Key} end

		if Settings.KeySettings.GrabKeyFromSite then
			for i, Key in ipairs(Settings.KeySettings.Key) do
				local Success, Response = pcall(function()
					Settings.KeySettings.Key[i] = tostring(game:HttpGet(Key):gsub("[\n\r]", " "))
					Settings.KeySettings.Key[i] = string.gsub(Settings.KeySettings.Key[i], " ", "")
				end)
				if not Success then
					print("Rayfield | "..Key.." Error " ..tostring(Response))
					warn('Check docs.sirius.menu for help with Rayfield specific development.')
				end
			end
		end

		if not Settings.KeySettings.FileName then
			Settings.KeySettings.FileName = "No file name specified"
		end
		local keyFileName = sanitizeFileName(Settings.KeySettings.FileName)
		if keyFileName == "" then
			keyFileName = "No file name specified"
		end
		local keyFile = RayfieldFolder.."/Key System".."/"..keyFileName..ConfigurationExtension

		if callSafely(isfile, keyFile) then
			for _, MKey in ipairs(Settings.KeySettings.Key) do
				local savedKeys = callSafely(readfile, keyFile)
				if savedKeys and string.find(savedKeys, tostring(MKey), 1, true) then
					Passthrough = true
				end
			end
		end

		if not Passthrough and secureMode then
			warn("Rayfield | Secure Mode: Key system requires a valid saved key. The key UI cannot be shown as it requires loading detectable assets.")
			Rayfield.Enabled = false
			return RayfieldLibrary
		end

		if not Passthrough then
			local AttemptsRemaining = Settings.KeySettings.MaxAttempts or 5
			Rayfield.Enabled = false
			local KeyUI = useStudio and script.Parent:FindFirstChild('Key') or game:GetObjects("rbxassetid://11380036235")[1]

			KeyUI.Enabled = true

			if gethui then
				KeyUI.Parent = gethui()
			elseif syn and syn.protect_gui then 
				syn.protect_gui(KeyUI)
				KeyUI.Parent = CoreGui
			elseif not useStudio and CoreGui:FindFirstChild("RobloxGui") then
				KeyUI.Parent = CoreGui:FindFirstChild("RobloxGui")
			elseif not useStudio then
				KeyUI.Parent = CoreGui
			end

			if gethui then
				for _, Interface in ipairs(gethui():GetChildren()) do
					if Interface.Name == KeyUI.Name and Interface ~= KeyUI then
						Interface.Enabled = false
						Interface.Name = "KeyUI-Old"
					end
				end
			elseif not useStudio then
				for _, Interface in ipairs(CoreGui:GetChildren()) do
					if Interface.Name == KeyUI.Name and Interface ~= KeyUI then
						Interface.Enabled = false
						Interface.Name = "KeyUI-Old"
					end
				end
			end

			local KeyMain = KeyUI.Main
			KeyMain.Title.Text = Settings.KeySettings.Title or Settings.Name
			KeyMain.Subtitle.Text = Settings.KeySettings.Subtitle or "Key System"
			KeyMain.NoteMessage.Text = Settings.KeySettings.Note or "No instructions"

			KeyMain.Size = UDim2.new(0, 467, 0, 175)
			KeyMain.BackgroundTransparency = 1
			KeyMain.Shadow.Image.ImageTransparency = 1
			KeyMain.Title.TextTransparency = 1
			KeyMain.Subtitle.TextTransparency = 1
			KeyMain.KeyNote.TextTransparency = 1
			KeyMain.Input.BackgroundTransparency = 1
			KeyMain.Input.UIStroke.Transparency = 1
			KeyMain.Input.InputBox.TextTransparency = 1
			KeyMain.NoteTitle.TextTransparency = 1
			KeyMain.NoteMessage.TextTransparency = 1
			KeyMain.Hide.ImageTransparency = 1

			TweenService:Create(KeyMain, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(KeyMain, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 500, 0, 187)}):Play()
			TweenService:Create(KeyMain.Shadow.Image, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {ImageTransparency = 0.5}):Play()
			task.wait(0.05)
			TweenService:Create(KeyMain.Title, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
			TweenService:Create(KeyMain.Subtitle, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
			task.wait(0.05)
			TweenService:Create(KeyMain.KeyNote, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
			TweenService:Create(KeyMain.Input, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(KeyMain.Input.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
			TweenService:Create(KeyMain.Input.InputBox, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
			task.wait(0.05)
			TweenService:Create(KeyMain.NoteTitle, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
			TweenService:Create(KeyMain.NoteMessage, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
			task.wait(0.15)
			TweenService:Create(KeyMain.Hide, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {ImageTransparency = 0.3}):Play()


			KeyUI.Main.Input.InputBox.FocusLost:Connect(function()
				if #KeyUI.Main.Input.InputBox.Text == 0 then return end
				local KeyFound = false
				local FoundKey = ''
				for _, MKey in ipairs(Settings.KeySettings.Key) do
					--if string.find(KeyMain.Input.InputBox.Text, MKey) then
					--	KeyFound = true
					--	FoundKey = MKey
					--end


					-- stricter key check
					if KeyMain.Input.InputBox.Text == MKey then
						KeyFound = true
						FoundKey = MKey
					end
				end
				if KeyFound then
					fadeOutKeyUI(KeyMain)
					task.wait(0.51)
					Passthrough = true
					KeyMain.Visible = false
					if Settings.KeySettings.SaveKey then
						callSafely(writefile, keyFile, FoundKey)
						RayfieldLibrary:Notify({Title = "Key System", Content = "The key for this script has been saved successfully.", Image = 3605522284})
					end
				else
					if AttemptsRemaining == 0 then
						fadeOutKeyUI(KeyMain)
						task.wait(0.45)
						Players.LocalPlayer:Kick("No Attempts Remaining")
						game:Shutdown()
					end
					KeyMain.Input.InputBox.Text = ""
					AttemptsRemaining = AttemptsRemaining - 1
					TweenService:Create(KeyMain, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 467, 0, 175)}):Play()
					TweenService:Create(KeyMain, TweenInfo.new(0.4, Enum.EasingStyle.Elastic), {Position = UDim2.new(0.495,0,0.5,0)}):Play()
					task.wait(0.1)
					TweenService:Create(KeyMain, TweenInfo.new(0.4, Enum.EasingStyle.Elastic), {Position = UDim2.new(0.505,0,0.5,0)}):Play()
					task.wait(0.1)
					TweenService:Create(KeyMain, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {Position = UDim2.new(0.5,0,0.5,0)}):Play()
					TweenService:Create(KeyMain, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 500, 0, 187)}):Play()
				end
			end)

			KeyMain.Hide.MouseButton1Click:Connect(function()
				fadeOutKeyUI(KeyMain)
				task.wait(0.51)
				Passthrough = true
				RayfieldLibrary:Destroy()
				KeyUI:Destroy()
			end)
		else
			Passthrough = true
		end
	end
	if Settings.KeySystem then
		repeat task.wait() until Passthrough
		if rayfieldDestroyed then return end
	end

	-- the developer's own Sentivel heartbeat, pinged for as long as this interface is up. Started
	-- only once the key system has let the player through, so a player sat at the key prompt isn't
	-- counted as running the script. A re-executed script renames this interface "Rayfield-Old"
	-- rather than destroying it, so that ends the loop too.
	if Settings.Heartbeat ~= nil then
		startHeartbeat(Settings.Heartbeat, function()
			return not rayfieldDestroyed and Rayfield.Parent ~= nil and Rayfield.Name ~= "Rayfield-Old"
		end)
	end

	Notifications.Template.Visible = false
	Notifications.Visible = true
	Rayfield.Enabled = true

	task.wait(0.5)
	TweenService:Create(Main, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
	TweenService:Create(Main.Shadow.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0.6}):Play()
	task.wait(0.1)
	TweenService:Create(LoadingFrame.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
	task.wait(0.05)
	TweenService:Create(LoadingFrame.Subtitle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
	task.wait(0.05)
	TweenService:Create(LoadingFrame.Version, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()


	Elements.Template.LayoutOrder = 100000
	Elements.Template.Visible = false

	Elements.UIPageLayout.FillDirection = Enum.FillDirection.Horizontal
	Elements.UIPageLayout.ScrollWheelInputEnabled = false
	Elements.UIPageLayout.GamepadInputEnabled = false
	Elements.UIPageLayout.TouchInputEnabled = false
	TabList.Template.Visible = false

	-- Tab
	local FirstTab = false
	local Window = {}
	function Window:CreateTab(Name, Image, Ext)
		local SDone = false
		local TabButton = TabList.Template:Clone()
		TabButton.Name = Name
		TabButton.Title.Text = Name
		TabButton.Parent = TabList
		TabButton.Title.TextWrapped = false
		TabButton.Size = UDim2.new(0, TabButton.Title.TextBounds.X + 30, 0, 30)

		if Image and Image ~= 0 then
			local img, rectOffset, rectSize = resolveIcon(Image)
			TabButton.Image.Image = img
			if rectOffset then TabButton.Image.ImageRectOffset = rectOffset end
			if rectSize then TabButton.Image.ImageRectSize = rectSize end

			TabButton.Title.AnchorPoint = Vector2.new(0, 0.5)
			TabButton.Title.Position = UDim2.new(0, 37, 0.5, 0)
			TabButton.Image.Visible = true
			TabButton.Title.TextXAlignment = Enum.TextXAlignment.Left
			TabButton.Size = UDim2.new(0, TabButton.Title.TextBounds.X + 52, 0, 30)
		end



		TabButton.BackgroundTransparency = 1
		TabButton.Title.TextTransparency = 1
		TabButton.Image.ImageTransparency = 1
		TabButton.UIStroke.Transparency = 1

		TabButton.Visible = not Ext or false

		-- Create Elements Page
		local TabPage = Elements.Template:Clone()
		TabPage.Name = Name
		TabPage.Visible = true

		TabPage.LayoutOrder = Ext and 10000 or #Elements:GetChildren()

		for _, TemplateElement in ipairs(TabPage:GetChildren()) do
			if TemplateElement.ClassName == "Frame" and TemplateElement.Name ~= "Placeholder" then
				TemplateElement:Destroy()
			end
		end

		TabPage.Parent = Elements
		if not FirstTab and not Ext then
			Elements.UIPageLayout.Animated = false
			Elements.UIPageLayout:JumpTo(TabPage)
			Elements.UIPageLayout.Animated = true
		end

		TabButton.UIStroke.Color = SelectedTheme.TabStroke

		if Elements.UIPageLayout.CurrentPage == TabPage then
			TabButton.BackgroundColor3 = SelectedTheme.TabBackgroundSelected
			TabButton.Image.ImageColor3 = SelectedTheme.SelectedTabTextColor
			TabButton.Title.TextColor3 = SelectedTheme.SelectedTabTextColor
		else
			TabButton.BackgroundColor3 = SelectedTheme.TabBackground
			TabButton.Image.ImageColor3 = SelectedTheme.TabTextColor
			TabButton.Title.TextColor3 = SelectedTheme.TabTextColor
		end


		-- Animate
		task.wait(0.1)
		if FirstTab or Ext then
			TabButton.BackgroundColor3 = SelectedTheme.TabBackground
			TabButton.Image.ImageColor3 = SelectedTheme.TabTextColor
			TabButton.Title.TextColor3 = SelectedTheme.TabTextColor
			TweenService:Create(TabButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.7}):Play()
			TweenService:Create(TabButton.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0.2}):Play()
			TweenService:Create(TabButton.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0.2}):Play()
			TweenService:Create(TabButton.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
		elseif not Ext then
			FirstTab = Name
			TabButton.BackgroundColor3 = SelectedTheme.TabBackgroundSelected
			TabButton.Image.ImageColor3 = SelectedTheme.SelectedTabTextColor
			TabButton.Title.TextColor3 = SelectedTheme.SelectedTabTextColor
			TweenService:Create(TabButton.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0}):Play()
			TweenService:Create(TabButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(TabButton.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
		end


		TabButton.Interact.MouseButton1Click:Connect(function()
			if Minimised then return end
			TweenService:Create(TabButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(TabButton.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
			TweenService:Create(TabButton.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
			TweenService:Create(TabButton.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0}):Play()
			TweenService:Create(TabButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.TabBackgroundSelected}):Play()
			TweenService:Create(TabButton.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextColor3 = SelectedTheme.SelectedTabTextColor}):Play()
			TweenService:Create(TabButton.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageColor3 = SelectedTheme.SelectedTabTextColor}):Play()

			for _, OtherTabButton in ipairs(TabList:GetChildren()) do
				if OtherTabButton.Name ~= "Template" and OtherTabButton.ClassName == "Frame" and OtherTabButton ~= TabButton and OtherTabButton.Name ~= "Placeholder" then
					TweenService:Create(OtherTabButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.TabBackground}):Play()
					TweenService:Create(OtherTabButton.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextColor3 = SelectedTheme.TabTextColor}):Play()
					TweenService:Create(OtherTabButton.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageColor3 = SelectedTheme.TabTextColor}):Play()
					TweenService:Create(OtherTabButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.7}):Play()
					TweenService:Create(OtherTabButton.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0.2}):Play()
					TweenService:Create(OtherTabButton.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0.2}):Play()
					TweenService:Create(OtherTabButton.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
				end
			end

			if Elements.UIPageLayout.CurrentPage ~= TabPage then
				Elements.UIPageLayout:JumpTo(TabPage)
			end
		end)

		local Tab = {}

		-- Button
		function Tab:CreateButton(ButtonSettings)
			local ButtonValue = {}

			local Button = Elements.Template.Button:Clone()
			Button.Name = ButtonSettings.Name
			Button.Title.Text = ButtonSettings.Name
			Button.Visible = true
			Button.Parent = TabPage

			Button.BackgroundTransparency = 1
			Button.UIStroke.Transparency = 1
			Button.Title.TextTransparency = 1

			TweenService:Create(Button, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(Button.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
			TweenService:Create(Button.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	


			Button.Interact.MouseButton1Click:Connect(function()
				local Success, Response = pcall(ButtonSettings.Callback)
				-- Prevents animation from trying to play if the button's callback called RayfieldLibrary:Destroy()
				if rayfieldDestroyed then
					return
				end
				if not Success then
					TweenService:Create(Button, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
					TweenService:Create(Button.ElementIndicator, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
					TweenService:Create(Button.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					Button.Title.Text = "Callback Error"
					print("Rayfield | "..ButtonSettings.Name.." Callback Error " ..tostring(Response))
					warn('Check docs.sirius.menu for help with Rayfield specific development.')
					task.wait(0.5)
					Button.Title.Text = ButtonSettings.Name
					TweenService:Create(Button, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Button.ElementIndicator, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {TextTransparency = 0.9}):Play()
					TweenService:Create(Button.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
				else
					if not ButtonSettings.Ext then
						SaveConfiguration(ButtonSettings.Name..'\n')
					end
					TweenService:Create(Button, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
					TweenService:Create(Button.ElementIndicator, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
					TweenService:Create(Button.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					task.wait(0.2)
					TweenService:Create(Button, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Button.ElementIndicator, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {TextTransparency = 0.9}):Play()
					TweenService:Create(Button.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
				end
			end)

			Button.MouseEnter:Connect(function()
				TweenService:Create(Button, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
				TweenService:Create(Button.ElementIndicator, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {TextTransparency = 0.7}):Play()
			end)

			Button.MouseLeave:Connect(function()
				TweenService:Create(Button, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
				TweenService:Create(Button.ElementIndicator, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {TextTransparency = 0.9}):Play()
			end)

			function ButtonValue:Set(NewButton)
				Button.Title.Text = NewButton
				Button.Name = NewButton
			end

			return ButtonValue
		end

		-- ColorPicker
		function Tab:CreateColorPicker(ColorPickerSettings) -- by Throit
			ColorPickerSettings.Type = "ColorPicker"
			local ColorPicker = Elements.Template.ColorPicker:Clone()
			local Background = ColorPicker.CPBackground
			local Display = Background.Display
			local Main = Background.MainCP
			local Slider = ColorPicker.ColorSlider
			ColorPicker.ClipsDescendants = true
			ColorPicker.Name = ColorPickerSettings.Name
			ColorPicker.Title.Text = ColorPickerSettings.Name
			ColorPicker.Visible = true
			ColorPicker.Parent = TabPage
			ColorPicker.Size = UDim2.new(1, -10, 0, 45)
			Background.Size = UDim2.new(0, 39, 0, 22)
			Display.BackgroundTransparency = 0
			Main.MainPoint.ImageTransparency = 1
			ColorPicker.Interact.Size = UDim2.new(1, 0, 1, 0)
			ColorPicker.Interact.Position = UDim2.new(0.5, 0, 0.5, 0)
			ColorPicker.RGB.Position = UDim2.new(0, 17, 0, 70)
			ColorPicker.HexInput.Position = UDim2.new(0, 17, 0, 90)
			Main.ImageTransparency = 1
			Background.BackgroundTransparency = 1

			for _, rgbinput in ipairs(ColorPicker.RGB:GetChildren()) do
				if rgbinput:IsA("Frame") then
					rgbinput.BackgroundColor3 = SelectedTheme.InputBackground
					rgbinput.UIStroke.Color = SelectedTheme.InputStroke
				end
			end

			ColorPicker.HexInput.BackgroundColor3 = SelectedTheme.InputBackground
			ColorPicker.HexInput.UIStroke.Color = SelectedTheme.InputStroke

			local opened = false 
			local mouse = Players.LocalPlayer:GetMouse()
			local mainDragging = false 
			local sliderDragging = false 
			ColorPicker.Interact.MouseButton1Down:Connect(function()
				task.spawn(function()
					TweenService:Create(ColorPicker, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
					TweenService:Create(ColorPicker.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					task.wait(0.2)
					TweenService:Create(ColorPicker, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(ColorPicker.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
				end)

				if not opened then
					opened = true 
					TweenService:Create(Background, TweenInfo.new(0.45, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 18, 0, 15)}):Play()
					task.wait(0.1)
					TweenService:Create(ColorPicker, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, -10, 0, 120)}):Play()
					TweenService:Create(Background, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 173, 0, 86)}):Play()
					TweenService:Create(Display, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
					TweenService:Create(ColorPicker.Interact, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Position = UDim2.new(0.289, 0, 0.5, 0)}):Play()
					TweenService:Create(ColorPicker.RGB, TweenInfo.new(0.8, Enum.EasingStyle.Exponential), {Position = UDim2.new(0, 17, 0, 40)}):Play()
					TweenService:Create(ColorPicker.HexInput, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Position = UDim2.new(0, 17, 0, 73)}):Play()
					TweenService:Create(ColorPicker.Interact, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Size = UDim2.new(0.574, 0, 1, 0)}):Play()
					TweenService:Create(Main.MainPoint, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), {ImageTransparency = 0}):Play()
					TweenService:Create(Main, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), {ImageTransparency = SelectedTheme ~= RayfieldLibrary.Theme.Default and 0.25 or 0.1}):Play()
					TweenService:Create(Background, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
				else
					opened = false
					TweenService:Create(ColorPicker, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, -10, 0, 45)}):Play()
					TweenService:Create(Background, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 39, 0, 22)}):Play()
					TweenService:Create(ColorPicker.Interact, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, 0, 1, 0)}):Play()
					TweenService:Create(ColorPicker.Interact, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Position = UDim2.new(0.5, 0, 0.5, 0)}):Play()
					TweenService:Create(ColorPicker.RGB, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Position = UDim2.new(0, 17, 0, 70)}):Play()
					TweenService:Create(ColorPicker.HexInput, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Position = UDim2.new(0, 17, 0, 90)}):Play()
					TweenService:Create(Display, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
					TweenService:Create(Main.MainPoint, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
					TweenService:Create(Main, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
					TweenService:Create(Background, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
				end

			end)

			local colorPickerInputConnection = UserInputService.InputEnded:Connect(function(input, gameProcessed) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					mainDragging = false
					sliderDragging = false
				end end)
			Main.MouseButton1Down:Connect(function()
				if opened then
					mainDragging = true 
				end
			end)
			Main.MainPoint.MouseButton1Down:Connect(function()
				if opened then
					mainDragging = true 
				end
			end)
			Slider.MouseButton1Down:Connect(function()
				sliderDragging = true 
			end)
			Slider.SliderPoint.MouseButton1Down:Connect(function()
				sliderDragging = true 
			end)
			local h,s,v = ColorPickerSettings.Color:ToHSV()
			local color = Color3.fromHSV(h,s,v) 
			local hex = string.format("#%02X%02X%02X",color.R*0xFF,color.G*0xFF,color.B*0xFF)
			ColorPicker.HexInput.InputBox.Text = hex
			local function setDisplay()
				--Main
				Main.MainPoint.Position = UDim2.new(s,-Main.MainPoint.AbsoluteSize.X/2,1-v,-Main.MainPoint.AbsoluteSize.Y/2)
				Main.MainPoint.ImageColor3 = Color3.fromHSV(h,s,v)
				Background.BackgroundColor3 = Color3.fromHSV(h,1,1)
				Display.BackgroundColor3 = Color3.fromHSV(h,s,v)
				--Slider 
				local x = h * Slider.AbsoluteSize.X
				Slider.SliderPoint.Position = UDim2.new(0,x-Slider.SliderPoint.AbsoluteSize.X/2,0.5,0)
				Slider.SliderPoint.ImageColor3 = Color3.fromHSV(h,1,1)
				local color = Color3.fromHSV(h,s,v) 
				local r,g,b = math.floor((color.R*255)+0.5),math.floor((color.G*255)+0.5),math.floor((color.B*255)+0.5)
				ColorPicker.RGB.RInput.InputBox.Text = tostring(r)
				ColorPicker.RGB.GInput.InputBox.Text = tostring(g)
				ColorPicker.RGB.BInput.InputBox.Text = tostring(b)
				hex = string.format("#%02X%02X%02X",color.R*0xFF,color.G*0xFF,color.B*0xFF)
				ColorPicker.HexInput.InputBox.Text = hex
			end
			setDisplay()
			ColorPicker.HexInput.InputBox.FocusLost:Connect(function()
				if not pcall(function()
						local r, g, b = string.match(ColorPicker.HexInput.InputBox.Text, "^#?(%w%w)(%w%w)(%w%w)$")
						local rgbColor = Color3.fromRGB(tonumber(r, 16),tonumber(g, 16), tonumber(b, 16))
						h,s,v = rgbColor:ToHSV()
						hex = ColorPicker.HexInput.InputBox.Text
						setDisplay()
						ColorPickerSettings.Color = rgbColor
					end) 
				then 
					ColorPicker.HexInput.InputBox.Text = hex 
				end
				pcall(function()ColorPickerSettings.Callback(Color3.fromHSV(h,s,v))end)
				local r,g,b = math.floor((h*255)+0.5),math.floor((s*255)+0.5),math.floor((v*255)+0.5)
				ColorPickerSettings.Color = Color3.fromRGB(r,g,b)
				if not ColorPickerSettings.Ext then
					SaveConfiguration()
				end
			end)
			--RGB
			local function rgbBoxes(box,toChange)
				local value = tonumber(box.Text) 
				local color = Color3.fromHSV(h,s,v) 
				local oldR,oldG,oldB = math.floor((color.R*255)+0.5),math.floor((color.G*255)+0.5),math.floor((color.B*255)+0.5)
				local save 
				if toChange == "R" then save = oldR;oldR = value elseif toChange == "G" then save = oldG;oldG = value else save = oldB;oldB = value end
				if value then 
					value = math.clamp(value,0,255)
					h,s,v = Color3.fromRGB(oldR,oldG,oldB):ToHSV()

					setDisplay()
				else 
					box.Text = tostring(save)
				end
				local r,g,b = math.floor((h*255)+0.5),math.floor((s*255)+0.5),math.floor((v*255)+0.5)
				ColorPickerSettings.Color = Color3.fromRGB(r,g,b)
				if not ColorPickerSettings.Ext then
					SaveConfiguration(ColorPickerSettings.Flag..'\n'..tostring(ColorPickerSettings.Color))
				end
			end
			ColorPicker.RGB.RInput.InputBox.FocusLost:connect(function()
				rgbBoxes(ColorPicker.RGB.RInput.InputBox,"R")
				pcall(function()ColorPickerSettings.Callback(Color3.fromHSV(h,s,v))end)
			end)
			ColorPicker.RGB.GInput.InputBox.FocusLost:connect(function()
				rgbBoxes(ColorPicker.RGB.GInput.InputBox,"G")
				pcall(function()ColorPickerSettings.Callback(Color3.fromHSV(h,s,v))end)
			end)
			ColorPicker.RGB.BInput.InputBox.FocusLost:connect(function()
				rgbBoxes(ColorPicker.RGB.BInput.InputBox,"B")
				pcall(function()ColorPickerSettings.Callback(Color3.fromHSV(h,s,v))end)
			end)

			local colorPickerRenderConnection = RunService.RenderStepped:connect(function()
				if mainDragging then
					local localX = math.clamp(mouse.X-Main.AbsolutePosition.X,0,Main.AbsoluteSize.X)
					local localY = math.clamp(mouse.Y-Main.AbsolutePosition.Y,0,Main.AbsoluteSize.Y)
					Main.MainPoint.Position = UDim2.new(0,localX-Main.MainPoint.AbsoluteSize.X/2,0,localY-Main.MainPoint.AbsoluteSize.Y/2)
					s = localX / Main.AbsoluteSize.X
					v = 1 - (localY / Main.AbsoluteSize.Y)
					Display.BackgroundColor3 = Color3.fromHSV(h,s,v)
					Main.MainPoint.ImageColor3 = Color3.fromHSV(h,s,v)
					Background.BackgroundColor3 = Color3.fromHSV(h,1,1)
					local color = Color3.fromHSV(h,s,v) 
					local r,g,b = math.floor((color.R*255)+0.5),math.floor((color.G*255)+0.5),math.floor((color.B*255)+0.5)
					ColorPicker.RGB.RInput.InputBox.Text = tostring(r)
					ColorPicker.RGB.GInput.InputBox.Text = tostring(g)
					ColorPicker.RGB.BInput.InputBox.Text = tostring(b)
					ColorPicker.HexInput.InputBox.Text = string.format("#%02X%02X%02X",color.R*0xFF,color.G*0xFF,color.B*0xFF)
					pcall(function()ColorPickerSettings.Callback(Color3.fromHSV(h,s,v))end)
					ColorPickerSettings.Color = Color3.fromRGB(r,g,b)
					if not ColorPickerSettings.Ext then
						SaveConfiguration()
					end
				end
				if sliderDragging then 
					local localX = math.clamp(mouse.X-Slider.AbsolutePosition.X,0,Slider.AbsoluteSize.X)
					h = localX / Slider.AbsoluteSize.X
					Display.BackgroundColor3 = Color3.fromHSV(h,s,v)
					Slider.SliderPoint.Position = UDim2.new(0,localX-Slider.SliderPoint.AbsoluteSize.X/2,0.5,0)
					Slider.SliderPoint.ImageColor3 = Color3.fromHSV(h,1,1)
					Background.BackgroundColor3 = Color3.fromHSV(h,1,1)
					Main.MainPoint.ImageColor3 = Color3.fromHSV(h,s,v)
					local color = Color3.fromHSV(h,s,v) 
					local r,g,b = math.floor((color.R*255)+0.5),math.floor((color.G*255)+0.5),math.floor((color.B*255)+0.5)
					ColorPicker.RGB.RInput.InputBox.Text = tostring(r)
					ColorPicker.RGB.GInput.InputBox.Text = tostring(g)
					ColorPicker.RGB.BInput.InputBox.Text = tostring(b)
					ColorPicker.HexInput.InputBox.Text = string.format("#%02X%02X%02X",color.R*0xFF,color.G*0xFF,color.B*0xFF)
					pcall(function()ColorPickerSettings.Callback(Color3.fromHSV(h,s,v))end)
					ColorPickerSettings.Color = Color3.fromRGB(r,g,b)
					if not ColorPickerSettings.Ext then
						SaveConfiguration()
					end
				end
			end)

			ColorPicker.Destroying:Connect(function()
				if colorPickerRenderConnection then
					colorPickerRenderConnection:Disconnect()
				end
				if colorPickerInputConnection then
					colorPickerInputConnection:Disconnect()
				end
			end)

			if Settings.ConfigurationSaving then
				if Settings.ConfigurationSaving.Enabled and ColorPickerSettings.Flag then
					RayfieldLibrary.Flags[ColorPickerSettings.Flag] = ColorPickerSettings
				end
			end

			function ColorPickerSettings:Set(RGBColor)
				ColorPickerSettings.Color = RGBColor
				h,s,v = ColorPickerSettings.Color:ToHSV()
				color = Color3.fromHSV(h,s,v)
				setDisplay()
			end

			ColorPicker.MouseEnter:Connect(function()
				TweenService:Create(ColorPicker, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
			end)

			ColorPicker.MouseLeave:Connect(function()
				TweenService:Create(ColorPicker, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
			end)

			Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
				for _, rgbinput in ipairs(ColorPicker.RGB:GetChildren()) do
					if rgbinput:IsA("Frame") then
						rgbinput.BackgroundColor3 = SelectedTheme.InputBackground
						rgbinput.UIStroke.Color = SelectedTheme.InputStroke
					end
				end

				ColorPicker.HexInput.BackgroundColor3 = SelectedTheme.InputBackground
				ColorPicker.HexInput.UIStroke.Color = SelectedTheme.InputStroke
			end)

			return ColorPickerSettings
		end

		-- Section
		function Tab:CreateSection(SectionName)

			local SectionValue = {}

			if SDone then
				local SectionSpace = Elements.Template.SectionSpacing:Clone()
				SectionSpace.Visible = true
				SectionSpace.Parent = TabPage
			end

			local Section = Elements.Template.SectionTitle:Clone()
			Section.Title.Text = SectionName
			Section.Visible = true
			Section.Parent = TabPage

			Section.Title.TextTransparency = 1
			TweenService:Create(Section.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0.4}):Play()

			function SectionValue:Set(NewSection)
				Section.Title.Text = NewSection
			end

			SDone = true

			return SectionValue
		end

		-- Divider
		function Tab:CreateDivider()
			local DividerValue = {}

			local Divider = Elements.Template.Divider:Clone()
			Divider.Visible = true
			Divider.Parent = TabPage

			Divider.Divider.BackgroundTransparency = 1
			TweenService:Create(Divider.Divider, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.85}):Play()

			function DividerValue:Set(Value)
				Divider.Visible = Value
			end

			return DividerValue
		end

		-- Label
		function Tab:CreateLabel(LabelText : string, Icon: number, Color : Color3, IgnoreTheme : boolean)
			local LabelValue = {}

			local Label = Elements.Template.Label:Clone()
			Label.Title.Text = LabelText
			Label.Visible = true
			Label.Parent = TabPage

			Label.BackgroundColor3 = Color or SelectedTheme.SecondaryElementBackground
			Label.UIStroke.Color = Color or SelectedTheme.SecondaryElementStroke

			if Icon then
				local img, rectOffset, rectSize = resolveIcon(Icon)
				Label.Icon.Image = img
				if rectOffset then Label.Icon.ImageRectOffset = rectOffset end
				if rectSize then Label.Icon.ImageRectSize = rectSize end
			else
				Label.Icon.Image = ""
			end

			if Icon and Label:FindFirstChild('Icon') then
				Label.Title.Position = UDim2.new(0, 45, 0.5, 0)
				Label.Title.Size = UDim2.new(1, -100, 0, 14)
				Label.Icon.Visible = true
			end

			Label.Icon.ImageTransparency = 1
			Label.BackgroundTransparency = 1
			Label.UIStroke.Transparency = 1
			Label.Title.TextTransparency = 1

			Label:SetAttribute("BackgroundTransparencyTarget", Color and 0.8 or 0)
			Label:SetAttribute("UIStrokeTransparencyTarget", Color and 0.7 or 0)
			Label:SetAttribute("TitleTextTransparencyTarget", Color and 0.2 or 0)

			TweenService:Create(Label, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = Color and 0.8 or 0}):Play()
			TweenService:Create(Label.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = Color and 0.7 or 0}):Play()
			TweenService:Create(Label.Icon, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0.2}):Play()
			TweenService:Create(Label.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = Color and 0.2 or 0}):Play()

			function LabelValue:Set(NewLabel, Icon, Color)
				Label.Title.Text = NewLabel

				if Color then
					Label.BackgroundColor3 = Color or SelectedTheme.SecondaryElementBackground
					Label.UIStroke.Color = Color or SelectedTheme.SecondaryElementStroke
				end

				if Icon and Label:FindFirstChild('Icon') then
					Label.Title.Position = UDim2.new(0, 45, 0.5, 0)
					Label.Title.Size = UDim2.new(1, -100, 0, 14)

					local img, rectOffset, rectSize = resolveIcon(Icon)
					Label.Icon.Image = img
					if rectOffset then Label.Icon.ImageRectOffset = rectOffset end
					if rectSize then Label.Icon.ImageRectSize = rectSize end

					Label.Icon.Visible = true
				end
			end

			Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
				Label.BackgroundColor3 = IgnoreTheme and (Color or Label.BackgroundColor3) or SelectedTheme.SecondaryElementBackground
				Label.UIStroke.Color = IgnoreTheme and (Color or Label.BackgroundColor3) or SelectedTheme.SecondaryElementStroke
			end)

			return LabelValue
		end

		-- Paragraph
		function Tab:CreateParagraph(ParagraphSettings)
			local ParagraphValue = {}

			local Paragraph = Elements.Template.Paragraph:Clone()
			Paragraph.Title.Text = ParagraphSettings.Title
			Paragraph.Content.Text = ParagraphSettings.Content
			Paragraph.Visible = true
			Paragraph.Parent = TabPage

			Paragraph.BackgroundTransparency = 1
			Paragraph.UIStroke.Transparency = 1
			Paragraph.Title.TextTransparency = 1
			Paragraph.Content.TextTransparency = 1

			Paragraph.BackgroundColor3 = SelectedTheme.SecondaryElementBackground
			Paragraph.UIStroke.Color = SelectedTheme.SecondaryElementStroke

			TweenService:Create(Paragraph, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(Paragraph.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
			TweenService:Create(Paragraph.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	
			TweenService:Create(Paragraph.Content, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	

			function ParagraphValue:Set(NewParagraphSettings)
				Paragraph.Title.Text = NewParagraphSettings.Title
				Paragraph.Content.Text = NewParagraphSettings.Content
			end

			Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
				Paragraph.BackgroundColor3 = SelectedTheme.SecondaryElementBackground
				Paragraph.UIStroke.Color = SelectedTheme.SecondaryElementStroke
			end)

			return ParagraphValue
		end

		-- Input
		function Tab:CreateInput(InputSettings)
			local Input = Elements.Template.Input:Clone()
			Input.Name = InputSettings.Name
			Input.Title.Text = InputSettings.Name
			Input.Visible = true
			Input.Parent = TabPage

			Input.BackgroundTransparency = 1
			Input.UIStroke.Transparency = 1
			Input.Title.TextTransparency = 1

			Input.InputFrame.InputBox.Text = InputSettings.CurrentValue or ''

			Input.InputFrame.BackgroundColor3 = SelectedTheme.InputBackground
			Input.InputFrame.UIStroke.Color = SelectedTheme.InputStroke

			TweenService:Create(Input, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(Input.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
			TweenService:Create(Input.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	

			Input.InputFrame.InputBox.PlaceholderText = InputSettings.PlaceholderText
			Input.InputFrame.Size = UDim2.new(0, Input.InputFrame.InputBox.TextBounds.X + 24, 0, 30)

			Input.InputFrame.InputBox.FocusLost:Connect(function()
				local Success, Response = pcall(function()
					InputSettings.Callback(Input.InputFrame.InputBox.Text)
					InputSettings.CurrentValue = Input.InputFrame.InputBox.Text
				end)

				if not Success then
					TweenService:Create(Input, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
					TweenService:Create(Input.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					Input.Title.Text = "Callback Error"
					print("Rayfield | "..InputSettings.Name.." Callback Error " ..tostring(Response))
					warn('Check docs.sirius.menu for help with Rayfield specific development.')
					task.wait(0.5)
					Input.Title.Text = InputSettings.Name
					TweenService:Create(Input, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Input.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
				end

				if InputSettings.RemoveTextAfterFocusLost then
					Input.InputFrame.InputBox.Text = ""
				end

				if not InputSettings.Ext then
					SaveConfiguration()
				end
			end)

			Input.MouseEnter:Connect(function()
				TweenService:Create(Input, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
			end)

			Input.MouseLeave:Connect(function()
				TweenService:Create(Input, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
			end)

			Input.InputFrame.InputBox:GetPropertyChangedSignal("Text"):Connect(function()
				TweenService:Create(Input.InputFrame, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Size = UDim2.new(0, Input.InputFrame.InputBox.TextBounds.X + 24, 0, 30)}):Play()
			end)

			function InputSettings:Set(text)
				Input.InputFrame.InputBox.Text = text
				InputSettings.CurrentValue = text

				local Success, Response = pcall(function()
					InputSettings.Callback(text)
				end)

				if not InputSettings.Ext then
					SaveConfiguration()
				end
			end

			if Settings.ConfigurationSaving then
				if Settings.ConfigurationSaving.Enabled and InputSettings.Flag then
					RayfieldLibrary.Flags[InputSettings.Flag] = InputSettings
				end
			end

			Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
				Input.InputFrame.BackgroundColor3 = SelectedTheme.InputBackground
				Input.InputFrame.UIStroke.Color = SelectedTheme.InputStroke
			end)

			return InputSettings
		end

		-- Dropdown
		function Tab:CreateDropdown(DropdownSettings)
			local Dropdown = Elements.Template.Dropdown:Clone()
			if string.find(DropdownSettings.Name,"closed") then
				Dropdown.Name = "Dropdown"
			else
				Dropdown.Name = DropdownSettings.Name
			end
			Dropdown.Title.Text = DropdownSettings.Name
			Dropdown.Visible = true
			Dropdown.Parent = TabPage

			Dropdown.List.Visible = false
			if DropdownSettings.CurrentOption then
				if type(DropdownSettings.CurrentOption) == "string" then
					DropdownSettings.CurrentOption = {DropdownSettings.CurrentOption}
				end
				if not DropdownSettings.MultipleOptions and type(DropdownSettings.CurrentOption) == "table" then
					DropdownSettings.CurrentOption = {DropdownSettings.CurrentOption[1]}
				end
			else
				DropdownSettings.CurrentOption = {}
			end

			if DropdownSettings.MultipleOptions then
				if DropdownSettings.CurrentOption and type(DropdownSettings.CurrentOption) == "table" then
					if #DropdownSettings.CurrentOption == 1 then
						Dropdown.Selected.Text = DropdownSettings.CurrentOption[1]
					elseif #DropdownSettings.CurrentOption == 0 then
						Dropdown.Selected.Text = "None"
					else
						Dropdown.Selected.Text = "Various"
					end
				else
					DropdownSettings.CurrentOption = {}
					Dropdown.Selected.Text = "None"
				end
			else
				Dropdown.Selected.Text = DropdownSettings.CurrentOption[1] or "None"
			end

			Dropdown.Toggle.ImageColor3 = SelectedTheme.TextColor
			TweenService:Create(Dropdown, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()

			Dropdown.BackgroundTransparency = 1
			Dropdown.UIStroke.Transparency = 1
			Dropdown.Title.TextTransparency = 1

			Dropdown.Size = UDim2.new(1, -10, 0, 45)

			TweenService:Create(Dropdown, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(Dropdown.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
			TweenService:Create(Dropdown.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	

			for _, ununusedoption in ipairs(Dropdown.List:GetChildren()) do
				if ununusedoption.ClassName == "Frame" and ununusedoption.Name ~= "Placeholder" then
					ununusedoption:Destroy()
				end
			end

			Dropdown.Toggle.Rotation = 180

			Dropdown.Interact.MouseButton1Click:Connect(function()
				TweenService:Create(Dropdown, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
				TweenService:Create(Dropdown.UIStroke, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
				task.wait(0.1)
				TweenService:Create(Dropdown, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
				TweenService:Create(Dropdown.UIStroke, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
				if Debounce then return end
				if Dropdown.List.Visible then
					Debounce = true
					TweenService:Create(Dropdown, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, -10, 0, 45)}):Play()
					for _, DropdownOpt in ipairs(Dropdown.List:GetChildren()) do
						if DropdownOpt.ClassName == "Frame" and DropdownOpt.Name ~= "Placeholder" then
							TweenService:Create(DropdownOpt, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
							TweenService:Create(DropdownOpt.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
							TweenService:Create(DropdownOpt.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
						end
					end
					TweenService:Create(Dropdown.List, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ScrollBarImageTransparency = 1}):Play()
					TweenService:Create(Dropdown.Toggle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Rotation = 180}):Play()	
					task.wait(0.35)
					Dropdown.List.Visible = false
					Debounce = false
				else
					TweenService:Create(Dropdown, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, -10, 0, 180)}):Play()
					Dropdown.List.Visible = true
					TweenService:Create(Dropdown.List, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ScrollBarImageTransparency = 0.7}):Play()
					TweenService:Create(Dropdown.Toggle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Rotation = 0}):Play()	
					for _, DropdownOpt in ipairs(Dropdown.List:GetChildren()) do
						if DropdownOpt.ClassName == "Frame" and DropdownOpt.Name ~= "Placeholder" then
							if DropdownOpt.Name ~= Dropdown.Selected.Text then
								TweenService:Create(DropdownOpt.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
							end
							TweenService:Create(DropdownOpt, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
							TweenService:Create(DropdownOpt.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
						end
					end
				end
			end)

			Dropdown.MouseEnter:Connect(function()
				if not Dropdown.List.Visible then
					TweenService:Create(Dropdown, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
				end
			end)

			Dropdown.MouseLeave:Connect(function()
				TweenService:Create(Dropdown, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
			end)

			local function SetDropdownOptions()
				for _, Option in ipairs(DropdownSettings.Options) do
					local DropdownOption = Elements.Template.Dropdown.List.Template:Clone()
					DropdownOption.Name = Option
					DropdownOption.Title.Text = Option
					DropdownOption.Parent = Dropdown.List
					DropdownOption.Visible = true

					DropdownOption.BackgroundTransparency = 1
					DropdownOption.UIStroke.Transparency = 1
					DropdownOption.Title.TextTransparency = 1

					--local Dropdown = Tab:CreateDropdown({
					--	Name = "Dropdown Example",
					--	Options = {"Option 1","Option 2"},
					--	CurrentOption = {"Option 1"},
					--  MultipleOptions = true,
					--	Flag = "Dropdown1",
					--	Callback = function(TableOfOptions)

					--	end,
					--})


					DropdownOption.Interact.ZIndex = 50
					DropdownOption.Interact.MouseButton1Click:Connect(function()
						if not DropdownSettings.MultipleOptions and table.find(DropdownSettings.CurrentOption, Option) then 
							return
						end

						if table.find(DropdownSettings.CurrentOption, Option) then
							table.remove(DropdownSettings.CurrentOption, table.find(DropdownSettings.CurrentOption, Option))
							if DropdownSettings.MultipleOptions then
								if #DropdownSettings.CurrentOption == 1 then
									Dropdown.Selected.Text = DropdownSettings.CurrentOption[1]
								elseif #DropdownSettings.CurrentOption == 0 then
									Dropdown.Selected.Text = "None"
								else
									Dropdown.Selected.Text = "Various"
								end
							else
								Dropdown.Selected.Text = DropdownSettings.CurrentOption[1]
							end
						else
							if not DropdownSettings.MultipleOptions then
								table.clear(DropdownSettings.CurrentOption)
							end
							table.insert(DropdownSettings.CurrentOption, Option)
							if DropdownSettings.MultipleOptions then
								if #DropdownSettings.CurrentOption == 1 then
									Dropdown.Selected.Text = DropdownSettings.CurrentOption[1]
								elseif #DropdownSettings.CurrentOption == 0 then
									Dropdown.Selected.Text = "None"
								else
									Dropdown.Selected.Text = "Various"
								end
							else
								Dropdown.Selected.Text = DropdownSettings.CurrentOption[1]
							end
							TweenService:Create(DropdownOption.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
							TweenService:Create(DropdownOption, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.DropdownSelected}):Play()
							Debounce = true
						end


						local Success, Response = pcall(function()
							DropdownSettings.Callback(DropdownSettings.CurrentOption)
						end)

						if not Success then
							TweenService:Create(Dropdown, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
							TweenService:Create(Dropdown.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
							Dropdown.Title.Text = "Callback Error"
							print("Rayfield | "..DropdownSettings.Name.." Callback Error " ..tostring(Response))
							warn('Check docs.sirius.menu for help with Rayfield specific development.')
							task.wait(0.5)
							Dropdown.Title.Text = DropdownSettings.Name
							TweenService:Create(Dropdown, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
							TweenService:Create(Dropdown.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
						end

						for _, droption in ipairs(Dropdown.List:GetChildren()) do
							if droption.ClassName == "Frame" and droption.Name ~= "Placeholder" and not table.find(DropdownSettings.CurrentOption, droption.Name) then
								TweenService:Create(droption, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.DropdownUnselected}):Play()
							end
						end
						if not DropdownSettings.MultipleOptions then
							task.wait(0.1)
							TweenService:Create(Dropdown, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, -10, 0, 45)}):Play()
							for _, DropdownOpt in ipairs(Dropdown.List:GetChildren()) do
								if DropdownOpt.ClassName == "Frame" and DropdownOpt.Name ~= "Placeholder" then
									TweenService:Create(DropdownOpt, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
									TweenService:Create(DropdownOpt.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
									TweenService:Create(DropdownOpt.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
								end
							end
							TweenService:Create(Dropdown.List, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ScrollBarImageTransparency = 1}):Play()
							TweenService:Create(Dropdown.Toggle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Rotation = 180}):Play()	
							task.wait(0.35)
							Dropdown.List.Visible = false
						end
						Debounce = false
						if not DropdownSettings.Ext then
							SaveConfiguration()
						end
					end)

					Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
						DropdownOption.UIStroke.Color = SelectedTheme.ElementStroke
					end)
				end
			end
			SetDropdownOptions()

			for _, droption in ipairs(Dropdown.List:GetChildren()) do
				if droption.ClassName == "Frame" and droption.Name ~= "Placeholder" then
					if not table.find(DropdownSettings.CurrentOption, droption.Name) then
						droption.BackgroundColor3 = SelectedTheme.DropdownUnselected
					else
						droption.BackgroundColor3 = SelectedTheme.DropdownSelected
					end

					Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
						if not table.find(DropdownSettings.CurrentOption, droption.Name) then
							droption.BackgroundColor3 = SelectedTheme.DropdownUnselected
						else
							droption.BackgroundColor3 = SelectedTheme.DropdownSelected
						end
					end)
				end
			end

			function DropdownSettings:Set(NewOption)
				DropdownSettings.CurrentOption = NewOption

				if typeof(DropdownSettings.CurrentOption) == "string" then
					DropdownSettings.CurrentOption = {DropdownSettings.CurrentOption}
				end

				if not DropdownSettings.MultipleOptions then
					DropdownSettings.CurrentOption = {DropdownSettings.CurrentOption[1]}
				end

				if DropdownSettings.MultipleOptions then
					if #DropdownSettings.CurrentOption == 1 then
						Dropdown.Selected.Text = DropdownSettings.CurrentOption[1]
					elseif #DropdownSettings.CurrentOption == 0 then
						Dropdown.Selected.Text = "None"
					else
						Dropdown.Selected.Text = "Various"
					end
				else
					Dropdown.Selected.Text = DropdownSettings.CurrentOption[1]
				end


				local Success, Response = pcall(function()
					DropdownSettings.Callback(NewOption)
				end)
				if not Success then
					TweenService:Create(Dropdown, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
					TweenService:Create(Dropdown.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					Dropdown.Title.Text = "Callback Error"
					print("Rayfield | "..DropdownSettings.Name.." Callback Error " ..tostring(Response))
					warn('Check docs.sirius.menu for help with Rayfield specific development.')
					task.wait(0.5)
					Dropdown.Title.Text = DropdownSettings.Name
					TweenService:Create(Dropdown, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Dropdown.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
				end

				for _, droption in ipairs(Dropdown.List:GetChildren()) do
					if droption.ClassName == "Frame" and droption.Name ~= "Placeholder" then
						if not table.find(DropdownSettings.CurrentOption, droption.Name) then
							droption.BackgroundColor3 = SelectedTheme.DropdownUnselected
						else
							droption.BackgroundColor3 = SelectedTheme.DropdownSelected
						end
					end
				end
				--SaveConfiguration()
			end

			function DropdownSettings:Refresh(optionsTable: table) -- updates a dropdown with new options from optionsTable
				DropdownSettings.Options = optionsTable
				for _, option in Dropdown.List:GetChildren() do
					if option.ClassName == "Frame" and option.Name ~= "Placeholder" then
						option:Destroy()
					end
				end
				SetDropdownOptions()

				-- Apply selected/unselected background colors to new options
				for _, droption in ipairs(Dropdown.List:GetChildren()) do
					if droption.ClassName == "Frame" and droption.Name ~= "Placeholder" then
						if not table.find(DropdownSettings.CurrentOption, droption.Name) then
							droption.BackgroundColor3 = SelectedTheme.DropdownUnselected
						else
							droption.BackgroundColor3 = SelectedTheme.DropdownSelected
						end
					end
				end

				-- If the dropdown is currently open, make new options visible immediately
				if Dropdown.List.Visible then
					for _, DropdownOpt in ipairs(Dropdown.List:GetChildren()) do
						if DropdownOpt.ClassName == "Frame" and DropdownOpt.Name ~= "Placeholder" then
							DropdownOpt.BackgroundTransparency = 0
							DropdownOpt.Title.TextTransparency = 0
							if not table.find(DropdownSettings.CurrentOption, DropdownOpt.Name) then
								DropdownOpt.UIStroke.Transparency = 0
							end
						end
					end
				end
			end

			if Settings.ConfigurationSaving then
				if Settings.ConfigurationSaving.Enabled and DropdownSettings.Flag then
					RayfieldLibrary.Flags[DropdownSettings.Flag] = DropdownSettings
				end
			end

			Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
				Dropdown.Toggle.ImageColor3 = SelectedTheme.TextColor
				TweenService:Create(Dropdown, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
			end)

			return DropdownSettings
		end

		-- Keybind
		function Tab:CreateKeybind(KeybindSettings)
			local CheckingForKey = false
			local Keybind = Elements.Template.Keybind:Clone()
			Keybind.Name = KeybindSettings.Name
			Keybind.Title.Text = KeybindSettings.Name
			Keybind.Visible = true
			Keybind.Parent = TabPage

			Keybind.BackgroundTransparency = 1
			Keybind.UIStroke.Transparency = 1
			Keybind.Title.TextTransparency = 1

			Keybind.KeybindFrame.BackgroundColor3 = SelectedTheme.InputBackground
			Keybind.KeybindFrame.UIStroke.Color = SelectedTheme.InputStroke

			TweenService:Create(Keybind, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(Keybind.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
			TweenService:Create(Keybind.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	

			Keybind.KeybindFrame.KeybindBox.Text = KeybindSettings.CurrentKeybind
			Keybind.KeybindFrame.Size = UDim2.new(0, Keybind.KeybindFrame.KeybindBox.TextBounds.X + 24, 0, 30)

			Keybind.KeybindFrame.KeybindBox.Focused:Connect(function()
				CheckingForKey = true
				Keybind.KeybindFrame.KeybindBox.Text = ""
			end)
			Keybind.KeybindFrame.KeybindBox.FocusLost:Connect(function()
				CheckingForKey = false
				if Keybind.KeybindFrame.KeybindBox.Text == nil or Keybind.KeybindFrame.KeybindBox.Text == "" then
					Keybind.KeybindFrame.KeybindBox.Text = KeybindSettings.CurrentKeybind
					if not KeybindSettings.Ext then
						SaveConfiguration()
					end
				end
			end)

			Keybind.MouseEnter:Connect(function()
				TweenService:Create(Keybind, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
			end)

			Keybind.MouseLeave:Connect(function()
				TweenService:Create(Keybind, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
			end)

			local connection = UserInputService.InputBegan:Connect(function(input, processed)
				if rayfieldDestroyed then return end
				if CheckingForKey then
					if input.KeyCode ~= Enum.KeyCode.Unknown then
						local SplitMessage = string.split(tostring(input.KeyCode), ".")
						local NewKeyNoEnum = SplitMessage[3]
						Keybind.KeybindFrame.KeybindBox.Text = tostring(NewKeyNoEnum)
						KeybindSettings.CurrentKeybind = tostring(NewKeyNoEnum)
						Keybind.KeybindFrame.KeybindBox:ReleaseFocus()
						if not KeybindSettings.Ext then
							SaveConfiguration()
						end

						if KeybindSettings.CallOnChange then
							KeybindSettings.Callback(tostring(NewKeyNoEnum))
						end
					end
				elseif not KeybindSettings.CallOnChange and KeybindSettings.CurrentKeybind ~= nil and (input.KeyCode == Enum.KeyCode[KeybindSettings.CurrentKeybind] and not processed) then -- Test
					local Held = true
					local Connection
					Connection = input.Changed:Connect(function(prop)
						if prop == "UserInputState" then
							Connection:Disconnect()
							Held = false
						end
					end)

					if not KeybindSettings.HoldToInteract then
						local Success, Response = pcall(KeybindSettings.Callback)
						if not Success then
							TweenService:Create(Keybind, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
							TweenService:Create(Keybind.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
							Keybind.Title.Text = "Callback Error"
							print("Rayfield | "..KeybindSettings.Name.." Callback Error " ..tostring(Response))
							warn('Check docs.sirius.menu for help with Rayfield specific development.')
							task.wait(0.5)
							Keybind.Title.Text = KeybindSettings.Name
							TweenService:Create(Keybind, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
							TweenService:Create(Keybind.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
						end
					else
						task.wait(0.25)
						if Held then
							local Loop; Loop = RunService.Stepped:Connect(function()
								if not Held then
									KeybindSettings.Callback(false) -- maybe pcall this
									Loop:Disconnect()
								else
									KeybindSettings.Callback(true) -- maybe pcall this
								end
							end)
						end
					end
				end
			end)
			table.insert(keybindConnections, connection)

			Keybind.KeybindFrame.KeybindBox:GetPropertyChangedSignal("Text"):Connect(function()
				TweenService:Create(Keybind.KeybindFrame, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Size = UDim2.new(0, Keybind.KeybindFrame.KeybindBox.TextBounds.X + 24, 0, 30)}):Play()
			end)

			function KeybindSettings:Set(NewKeybind)
				Keybind.KeybindFrame.KeybindBox.Text = tostring(NewKeybind)
				KeybindSettings.CurrentKeybind = tostring(NewKeybind)
				Keybind.KeybindFrame.KeybindBox:ReleaseFocus()
				if not KeybindSettings.Ext then
					SaveConfiguration()
				end

				if KeybindSettings.CallOnChange then
					KeybindSettings.Callback(tostring(NewKeybind))
				end
			end

			if Settings.ConfigurationSaving then
				if Settings.ConfigurationSaving.Enabled and KeybindSettings.Flag then
					RayfieldLibrary.Flags[KeybindSettings.Flag] = KeybindSettings
				end
			end

			Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
				Keybind.KeybindFrame.BackgroundColor3 = SelectedTheme.InputBackground
				Keybind.KeybindFrame.UIStroke.Color = SelectedTheme.InputStroke
			end)

			return KeybindSettings
		end

		-- Toggle
		function Tab:CreateToggle(ToggleSettings)
			local ToggleValue = {}

			local Toggle = Elements.Template.Toggle:Clone()
			Toggle.Name = ToggleSettings.Name
			Toggle.Title.Text = ToggleSettings.Name
			Toggle.Visible = true
			Toggle.Parent = TabPage

			Toggle.BackgroundTransparency = 1
			Toggle.UIStroke.Transparency = 1
			Toggle.Title.TextTransparency = 1
			Toggle.Switch.BackgroundColor3 = SelectedTheme.ToggleBackground

			if SelectedTheme ~= RayfieldLibrary.Theme.Default then
				Toggle.Switch.Shadow.Visible = false
			end

			TweenService:Create(Toggle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
			TweenService:Create(Toggle.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	

			if ToggleSettings.CurrentValue == true then
				Toggle.Switch.Indicator.Position = UDim2.new(1, -20, 0.5, 0)
				Toggle.Switch.Indicator.UIStroke.Color = SelectedTheme.ToggleEnabledStroke
				Toggle.Switch.Indicator.BackgroundColor3 = SelectedTheme.ToggleEnabled
				Toggle.Switch.UIStroke.Color = SelectedTheme.ToggleEnabledOuterStroke
			else
				Toggle.Switch.Indicator.Position = UDim2.new(1, -40, 0.5, 0)
				Toggle.Switch.Indicator.UIStroke.Color = SelectedTheme.ToggleDisabledStroke
				Toggle.Switch.Indicator.BackgroundColor3 = SelectedTheme.ToggleDisabled
				Toggle.Switch.UIStroke.Color = SelectedTheme.ToggleDisabledOuterStroke
			end

			Toggle.MouseEnter:Connect(function()
				TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
			end)

			Toggle.MouseLeave:Connect(function()
				TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
			end)

			Toggle.Interact.MouseButton1Click:Connect(function()
				if ToggleSettings.CurrentValue == true then
					ToggleSettings.CurrentValue = false
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Position = UDim2.new(1, -40, 0.5, 0)}):Play()
					TweenService:Create(Toggle.Switch.Indicator.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Color = SelectedTheme.ToggleDisabledStroke}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.8, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {BackgroundColor3 = SelectedTheme.ToggleDisabled}):Play()
					TweenService:Create(Toggle.Switch.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Color = SelectedTheme.ToggleDisabledOuterStroke}):Play()
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()	
				else
					ToggleSettings.CurrentValue = true
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Position = UDim2.new(1, -20, 0.5, 0)}):Play()
					TweenService:Create(Toggle.Switch.Indicator.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Color = SelectedTheme.ToggleEnabledStroke}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.8, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {BackgroundColor3 = SelectedTheme.ToggleEnabled}):Play()
					TweenService:Create(Toggle.Switch.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Color = SelectedTheme.ToggleEnabledOuterStroke}):Play()
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()		
				end

				local Success, Response = pcall(function()
					if debugX then warn('Running toggle \''..ToggleSettings.Name..'\' (Interact)') end

					ToggleSettings.Callback(ToggleSettings.CurrentValue)
				end)

				if not Success then
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					Toggle.Title.Text = "Callback Error"
					print("Rayfield | "..ToggleSettings.Name.." Callback Error " ..tostring(Response))
					warn('Check docs.sirius.menu for help with Rayfield specific development.')
					task.wait(0.5)
					Toggle.Title.Text = ToggleSettings.Name
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
				end

				if not ToggleSettings.Ext then
					SaveConfiguration()
				end
			end)

			function ToggleSettings:Set(NewToggleValue)
				if NewToggleValue == true then
					ToggleSettings.CurrentValue = true
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Position = UDim2.new(1, -20, 0.5, 0)}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(0,12,0,12)}):Play()
					TweenService:Create(Toggle.Switch.Indicator.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Color = SelectedTheme.ToggleEnabledStroke}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.8, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {BackgroundColor3 = SelectedTheme.ToggleEnabled}):Play()
					TweenService:Create(Toggle.Switch.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Color = SelectedTheme.ToggleEnabledOuterStroke}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(0,17,0,17)}):Play()	
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()	
				else
					ToggleSettings.CurrentValue = false
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Position = UDim2.new(1, -40, 0.5, 0)}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(0,12,0,12)}):Play()
					TweenService:Create(Toggle.Switch.Indicator.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Color = SelectedTheme.ToggleDisabledStroke}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.8, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {BackgroundColor3 = SelectedTheme.ToggleDisabled}):Play()
					TweenService:Create(Toggle.Switch.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Color = SelectedTheme.ToggleDisabledOuterStroke}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(0,17,0,17)}):Play()
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()	
				end

				local Success, Response = pcall(function()
					if debugX then warn('Running toggle \''..ToggleSettings.Name..'\' (:Set)') end

					ToggleSettings.Callback(ToggleSettings.CurrentValue)
				end)

				if not Success then
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					Toggle.Title.Text = "Callback Error"
					print("Rayfield | "..ToggleSettings.Name.." Callback Error " ..tostring(Response))
					warn('Check docs.sirius.menu for help with Rayfield specific development.')
					task.wait(0.5)
					Toggle.Title.Text = ToggleSettings.Name
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
				end

				if not ToggleSettings.Ext then
					SaveConfiguration()
				end
			end

			if not ToggleSettings.Ext then
				if Settings.ConfigurationSaving then
					if Settings.ConfigurationSaving.Enabled and ToggleSettings.Flag then
						RayfieldLibrary.Flags[ToggleSettings.Flag] = ToggleSettings
					end
				end
			end


			Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
				Toggle.Switch.BackgroundColor3 = SelectedTheme.ToggleBackground

				if SelectedTheme ~= RayfieldLibrary.Theme.Default then
					Toggle.Switch.Shadow.Visible = false
				end

				task.wait()

				if not ToggleSettings.CurrentValue then
					Toggle.Switch.Indicator.UIStroke.Color = SelectedTheme.ToggleDisabledStroke
					Toggle.Switch.Indicator.BackgroundColor3 = SelectedTheme.ToggleDisabled
					Toggle.Switch.UIStroke.Color = SelectedTheme.ToggleDisabledOuterStroke
				else
					Toggle.Switch.Indicator.UIStroke.Color = SelectedTheme.ToggleEnabledStroke
					Toggle.Switch.Indicator.BackgroundColor3 = SelectedTheme.ToggleEnabled
					Toggle.Switch.UIStroke.Color = SelectedTheme.ToggleEnabledOuterStroke
				end
			end)

			return ToggleSettings
		end

		-- Slider
		function Tab:CreateSlider(SliderSettings)
			local SLDragging = false
			local Slider = Elements.Template.Slider:Clone()
			Slider.Name = SliderSettings.Name
			Slider.Title.Text = SliderSettings.Name
			Slider.Visible = true
			Slider.Parent = TabPage

			Slider.BackgroundTransparency = 1
			Slider.UIStroke.Transparency = 1
			Slider.Title.TextTransparency = 1

			if SelectedTheme ~= RayfieldLibrary.Theme.Default then
				Slider.Main.Shadow.Visible = false
			end

			Slider.Main.BackgroundColor3 = SelectedTheme.SliderBackground
			Slider.Main.UIStroke.Color = SelectedTheme.SliderStroke
			Slider.Main.Progress.UIStroke.Color = SelectedTheme.SliderStroke
			Slider.Main.Progress.BackgroundColor3 = SelectedTheme.SliderProgress

			TweenService:Create(Slider, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(Slider.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
			TweenService:Create(Slider.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	

			Slider.Main.Progress.Size =	UDim2.new(0, Slider.Main.AbsoluteSize.X * ((SliderSettings.CurrentValue - SliderSettings.Range[1]) / (SliderSettings.Range[2] - SliderSettings.Range[1])) > 5 and Slider.Main.AbsoluteSize.X * ((SliderSettings.CurrentValue - SliderSettings.Range[1]) / (SliderSettings.Range[2] - SliderSettings.Range[1])) or 5, 1, 0)

			if not SliderSettings.Suffix then
				Slider.Main.Information.Text = tostring(SliderSettings.CurrentValue)
			else
				Slider.Main.Information.Text = tostring(SliderSettings.CurrentValue) .. " " .. SliderSettings.Suffix
			end

			Slider.MouseEnter:Connect(function()
				TweenService:Create(Slider, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
			end)

			Slider.MouseLeave:Connect(function()
				TweenService:Create(Slider, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
			end)

			Slider.Main.Interact.InputBegan:Connect(function(Input)
				if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then 
					TweenService:Create(Slider.Main.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					TweenService:Create(Slider.Main.Progress.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					SLDragging = true 
				end 
			end)

			Slider.Main.Interact.InputEnded:Connect(function(Input) 
				if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then 
					TweenService:Create(Slider.Main.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0.4}):Play()
					TweenService:Create(Slider.Main.Progress.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0.3}):Play()
					SLDragging = false 
				end 
			end)

			Slider.Main.Interact.MouseButton1Down:Connect(function(X)
				local Current = Slider.Main.Progress.AbsolutePosition.X + Slider.Main.Progress.AbsoluteSize.X
				local Start = Current
				local Location = X
				local Loop; Loop = RunService.Stepped:Connect(function()
					if SLDragging then
						Location = UserInputService:GetMouseLocation().X
						Current = Current + 0.025 * (Location - Start)

						if Location < Slider.Main.AbsolutePosition.X then
							Location = Slider.Main.AbsolutePosition.X
						elseif Location > Slider.Main.AbsolutePosition.X + Slider.Main.AbsoluteSize.X then
							Location = Slider.Main.AbsolutePosition.X + Slider.Main.AbsoluteSize.X
						end

						if Current < Slider.Main.AbsolutePosition.X + 5 then
							Current = Slider.Main.AbsolutePosition.X + 5
						elseif Current > Slider.Main.AbsolutePosition.X + Slider.Main.AbsoluteSize.X then
							Current = Slider.Main.AbsolutePosition.X + Slider.Main.AbsoluteSize.X
						end

						if Current <= Location and (Location - Start) < 0 then
							Start = Location
						elseif Current >= Location and (Location - Start) > 0 then
							Start = Location
						end
						TweenService:Create(Slider.Main.Progress, TweenInfo.new(0.45, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Size = UDim2.new(0, Current - Slider.Main.AbsolutePosition.X, 1, 0)}):Play()
						local NewValue = SliderSettings.Range[1] + (Location - Slider.Main.AbsolutePosition.X) / Slider.Main.AbsoluteSize.X * (SliderSettings.Range[2] - SliderSettings.Range[1])

						NewValue = math.floor(NewValue / SliderSettings.Increment + 0.5) * (SliderSettings.Increment * 10000000) / 10000000
						NewValue = math.clamp(NewValue, SliderSettings.Range[1], SliderSettings.Range[2])

						if not SliderSettings.Suffix then
							Slider.Main.Information.Text = tostring(NewValue)
						else
							Slider.Main.Information.Text = tostring(NewValue) .. " " .. SliderSettings.Suffix
						end

						if SliderSettings.CurrentValue ~= NewValue then
							local Success, Response = pcall(function()
								SliderSettings.Callback(NewValue)
							end)
							if not Success then
								TweenService:Create(Slider, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
								TweenService:Create(Slider.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
								Slider.Title.Text = "Callback Error"
								print("Rayfield | "..SliderSettings.Name.." Callback Error " ..tostring(Response))
								warn('Check docs.sirius.menu for help with Rayfield specific development.')
								task.wait(0.5)
								Slider.Title.Text = SliderSettings.Name
								TweenService:Create(Slider, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
								TweenService:Create(Slider.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
							end

							SliderSettings.CurrentValue = NewValue
							if not SliderSettings.Ext then
								SaveConfiguration()
							end
						end
					else
						TweenService:Create(Slider.Main.Progress, TweenInfo.new(0.3, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Size = UDim2.new(0, Location - Slider.Main.AbsolutePosition.X > 5 and Location - Slider.Main.AbsolutePosition.X or 5, 1, 0)}):Play()
						Loop:Disconnect()
					end
				end)
			end)

			function SliderSettings:Set(NewVal)
				local NewVal = math.clamp(NewVal, SliderSettings.Range[1], SliderSettings.Range[2])

				TweenService:Create(Slider.Main.Progress, TweenInfo.new(0.45, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Size = UDim2.new(0, Slider.Main.AbsoluteSize.X * ((NewVal - SliderSettings.Range[1]) / (SliderSettings.Range[2] - SliderSettings.Range[1])) > 5 and Slider.Main.AbsoluteSize.X * ((NewVal - SliderSettings.Range[1]) / (SliderSettings.Range[2] - SliderSettings.Range[1])) or 5, 1, 0)}):Play()
				Slider.Main.Information.Text = tostring(NewVal) .. " " .. (SliderSettings.Suffix or "")

				local Success, Response = pcall(function()
					SliderSettings.Callback(NewVal)
				end)

				if not Success then
					TweenService:Create(Slider, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
					TweenService:Create(Slider.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					Slider.Title.Text = "Callback Error"
					print("Rayfield | "..SliderSettings.Name.." Callback Error " ..tostring(Response))
					warn('Check docs.sirius.menu for help with Rayfield specific development.')
					task.wait(0.5)
					Slider.Title.Text = SliderSettings.Name
					TweenService:Create(Slider, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Slider.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
				end

				SliderSettings.CurrentValue = NewVal
				if not SliderSettings.Ext then
					SaveConfiguration()
				end
			end

			if Settings.ConfigurationSaving then
				if Settings.ConfigurationSaving.Enabled and SliderSettings.Flag then
					RayfieldLibrary.Flags[SliderSettings.Flag] = SliderSettings
				end
			end

			Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
				if SelectedTheme ~= RayfieldLibrary.Theme.Default then
					Slider.Main.Shadow.Visible = false
				end

				Slider.Main.BackgroundColor3 = SelectedTheme.SliderBackground
				Slider.Main.UIStroke.Color = SelectedTheme.SliderStroke
				Slider.Main.Progress.UIStroke.Color = SelectedTheme.SliderStroke
				Slider.Main.Progress.BackgroundColor3 = SelectedTheme.SliderProgress
			end)

			return SliderSettings
		end

		Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
			TabButton.UIStroke.Color = SelectedTheme.TabStroke

			if Elements.UIPageLayout.CurrentPage == TabPage then
				TabButton.BackgroundColor3 = SelectedTheme.TabBackgroundSelected
				TabButton.Image.ImageColor3 = SelectedTheme.SelectedTabTextColor
				TabButton.Title.TextColor3 = SelectedTheme.SelectedTabTextColor
			else
				TabButton.BackgroundColor3 = SelectedTheme.TabBackground
				TabButton.Image.ImageColor3 = SelectedTheme.TabTextColor
				TabButton.Title.TextColor3 = SelectedTheme.TabTextColor
			end
		end)

		return Tab
	end

	Elements.Visible = true


	task.wait(1.1)
	TweenService:Create(Main, TweenInfo.new(0.7, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut), {Size = UDim2.new(0, 390, 0, 90)}):Play()
	task.wait(0.3)
	TweenService:Create(LoadingFrame.Title, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
	TweenService:Create(LoadingFrame.Subtitle, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
	TweenService:Create(LoadingFrame.Version, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
	task.wait(0.1)
	TweenService:Create(Main, TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Size = useMobileSizing and UDim2.new(0, 500, 0, 275) or UDim2.new(0, 500, 0, 475)}):Play()
	TweenService:Create(Main.Shadow.Image, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {ImageTransparency = 0.6}):Play()

	Topbar.BackgroundTransparency = 1
	Topbar.Divider.Size = UDim2.new(0, 0, 0, 1)
	Topbar.Divider.BackgroundColor3 = SelectedTheme.ElementStroke
	Topbar.CornerRepair.BackgroundTransparency = 1
	Topbar.Title.TextTransparency = 1
	Topbar.Search.ImageTransparency = 1
	if Topbar:FindFirstChild('Settings') then
		Topbar.Settings.ImageTransparency = 1
	end
	Topbar.ChangeSize.ImageTransparency = 1
	Topbar.Hide.ImageTransparency = 1


	task.wait(0.5)
	Topbar.Visible = true
	TweenService:Create(Topbar, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
	TweenService:Create(Topbar.CornerRepair, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
	task.wait(0.1)
	TweenService:Create(Topbar.Divider, TweenInfo.new(1, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, 0, 0, 1)}):Play()
	TweenService:Create(Topbar.Title, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
	task.wait(0.05)
	TweenService:Create(Topbar.Search, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {ImageTransparency = 0.8}):Play()
	task.wait(0.05)
	if Topbar:FindFirstChild('Settings') then
		TweenService:Create(Topbar.Settings, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {ImageTransparency = 0.8}):Play()
		task.wait(0.05)
	end
	TweenService:Create(Topbar.ChangeSize, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {ImageTransparency = 0.8}):Play()
	task.wait(0.05)
	TweenService:Create(Topbar.Hide, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {ImageTransparency = 0.8}):Play()
	task.wait(0.3)

	if dragBar then
		TweenService:Create(dragBarCosmetic, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.7}):Play()
	end

	function Window.ModifyTheme(NewTheme)
		local success = pcall(ChangeTheme, NewTheme)
		if not success then
			RayfieldLibrary:Notify({Title = 'Unable to Change Theme', Content = 'We are unable find a theme on file.', Image = 4400704299})
		else
			RayfieldLibrary:Notify({Title = 'Theme Changed', Content = 'Successfully changed theme to '..(typeof(NewTheme) == 'string' and NewTheme or 'Custom Theme')..'.', Image = 4483362748})
		end
	end

	local success, result = pcall(function()
		createSettings(Window)
	end)

	if not success then warn('Rayfield had an issue creating settings.') end

	-- Report after createSettings so loadSettings() has run and usageAnalytics reflects the user's saved preference
	if analyticsAllowed() and loadReporter() then
		local themeName = "Default"
		if Settings.Theme then
			if type(Settings.Theme) == "string" then
				themeName = Settings.Theme
			elseif type(Settings.Theme) == "table" then
				themeName = "Custom"
			end
		end

		local discordInvite = nil
		if Settings.Discord and Settings.Discord.Enabled and Settings.Discord.Invite and Settings.Discord.Invite ~= "" then
			local raw = tostring(Settings.Discord.Invite)
			-- Normalize: strip URL prefixes to extract just the invite code
			discordInvite = (raw:match("discord%.gg/([%w%-]+)") or raw:match("discord%.com/invite/([%w%-]+)") or raw):sub(1, 32)
		end

		local sampleSend = false

		-- Random Sampling Test
		if not Settings.ScriptID and math.random() > 0.4 then
			sampleSend = true
		end

		--if Settings.ScriptID then
			reporter:windowCreated({
				script_name        = Settings.Name or "Unknown",
				script_version     = Release,
				interface_version  = InterfaceBuild,
				theme              = themeName,
				is_mobile          = useMobileSizing and true or false,
				has_key_system     = Settings.KeySystem and true or false,
				discord_invite     = discordInvite,
				config_saving      = (Settings.ConfigurationSaving and Settings.ConfigurationSaving.Enabled) and true or false,
				script_id          = Settings.ScriptID or sampleSend and 'sid_tzfyxawonjx9' or nil,
				verification_token = Settings.VerificationToken,
			})
		--end
	end

	return Window
end

local function setVisibility(visibility: boolean, notify: boolean?)
	if Debounce then return end
	if visibility then
		Hidden = false
		Unhide()
	else
		Hidden = true
		Hide(notify)
	end
end

function RayfieldLibrary:SetVisibility(visibility: boolean)
	setVisibility(visibility, false)
end

function RayfieldLibrary:IsVisible(): boolean
	return not Hidden
end

local hideHotkeyConnection -- Has to be initialized here since the connection is made later in the script
function RayfieldLibrary:Destroy()
	rayfieldDestroyed = true
	-- stops the kick watcher the reporter armed, so nothing is sent for a window that's gone
	if reporter and reporter.disable then
		pcall(reporter.disable, reporter)
	end
	if hideHotkeyConnection then
		hideHotkeyConnection:Disconnect()
	end
	for _, connection in keybindConnections do
		connection:Disconnect()
	end
	Rayfield:Destroy()
end

Topbar.ChangeSize.MouseButton1Click:Connect(function()
	if Debounce then return end
	if Minimised then
		Minimised = false
		Maximise()
	else
		Minimised = true
		Minimise()
	end
end)

Main.Search.Input:GetPropertyChangedSignal('Text'):Connect(function()
	if #Main.Search.Input.Text > 0 then
		if not Elements.UIPageLayout.CurrentPage:FindFirstChild('SearchTitle-fsefsefesfsefesfesfThanks') then 
			local searchTitle = Elements.Template.SectionTitle:Clone()
			searchTitle.Parent = Elements.UIPageLayout.CurrentPage
			searchTitle.Name = 'SearchTitle-fsefsefesfsefesfesfThanks'
			searchTitle.LayoutOrder = -100
			searchTitle.Title.Text = "Results from '"..Elements.UIPageLayout.CurrentPage.Name.."'"
			searchTitle.Visible = true
		end
	else
		local searchTitle = Elements.UIPageLayout.CurrentPage:FindFirstChild('SearchTitle-fsefsefesfsefesfesfThanks')

		if searchTitle then
			searchTitle:Destroy()
		end
	end

	for _, element in ipairs(Elements.UIPageLayout.CurrentPage:GetChildren()) do
		if element.ClassName ~= 'UIListLayout' and element.Name ~= 'Placeholder' and element.Name ~= 'SearchTitle-fsefsefesfsefesfesfThanks' then
			if element.Name == 'SectionTitle' then
				if #Main.Search.Input.Text == 0 then
					element.Visible = true
				else
					element.Visible = false
				end
			else
				if string.lower(element.Name):find(string.lower(Main.Search.Input.Text), 1, true) then
					element.Visible = true
				else
					element.Visible = false
				end
			end
		end
	end
end)

Main.Search.Input.FocusLost:Connect(function(enterPressed)
	if #Main.Search.Input.Text == 0 and searchOpen then
		task.wait(0.12)
		closeSearch()
	end
end)

Topbar.Search.MouseButton1Click:Connect(function()
	task.spawn(function()
		if searchOpen then
			closeSearch()
		else
			openSearch()
		end
	end)
end)

if Topbar:FindFirstChild('Settings') then
	Topbar.Settings.MouseButton1Click:Connect(function()
		task.spawn(function()
			for _, OtherTabButton in ipairs(TabList:GetChildren()) do
				if OtherTabButton.Name ~= "Template" and OtherTabButton.ClassName == "Frame" and OtherTabButton.Name ~= "Placeholder" then
					TweenService:Create(OtherTabButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.TabBackground}):Play()
					TweenService:Create(OtherTabButton.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextColor3 = SelectedTheme.TabTextColor}):Play()
					TweenService:Create(OtherTabButton.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageColor3 = SelectedTheme.TabTextColor}):Play()
					TweenService:Create(OtherTabButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.7}):Play()
					TweenService:Create(OtherTabButton.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0.2}):Play()
					TweenService:Create(OtherTabButton.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0.2}):Play()
					TweenService:Create(OtherTabButton.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
				end
			end

			Elements.UIPageLayout:JumpTo(Elements['Rayfield Settings'])
		end)
	end)

end


Topbar.Hide.MouseButton1Click:Connect(function()
	setVisibility(Hidden, not useMobileSizing)
end)

hideHotkeyConnection = UserInputService.InputBegan:Connect(function(input, processed)
	if rayfieldDestroyed then return end
	if (input.KeyCode == Enum.KeyCode[getSetting("General", "rayfieldOpen")]) and not processed then
		if Debounce then return end
		if Hidden then
			Hidden = false
			Unhide()
		else
			Hidden = true
			Hide()
		end
	end
end)

if MPrompt then
	MPrompt.Interact.MouseButton1Click:Connect(function()
		if Debounce then return end
		if Hidden then
			Hidden = false
			Unhide()
		end
	end)
end

for _, TopbarButton in ipairs(Topbar:GetChildren()) do
	if TopbarButton.ClassName == "ImageButton" and TopbarButton.Name ~= 'Icon' then
		TopbarButton.MouseEnter:Connect(function()
			TweenService:Create(TopbarButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0}):Play()
		end)

		TopbarButton.MouseLeave:Connect(function()
			TweenService:Create(TopbarButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0.8}):Play()
		end)
	end
end


function RayfieldLibrary:LoadConfiguration()
	local config

	if debugX then
		warn('Loading Configuration')
	end

	if useStudio then
		config = [[{"Toggle1adwawd":true,"ColorPicker1awd":{"B":255,"G":255,"R":255},"Slider1dawd":100,"ColorPicfsefker1":{"B":255,"G":255,"R":255},"Slidefefsr1":80,"dawdawd":"","Input1":"hh","Keybind1":"B","Dropdown1":["Ocean"]}]]
	end

	if CEnabled then
		local notified
		local loaded

		local success, result = pcall(function()
			if useStudio and config then
				loaded = LoadConfiguration(config)
				return
			end

			if isfile then 
				local configPath = ConfigurationFolder .. "/" .. CFileName .. ConfigurationExtension
				if CLegacyFileName and not callSafely(isfile, configPath) then
					local legacyPath = ConfigurationFolder .. "/" .. CLegacyFileName .. ConfigurationExtension
					if callSafely(isfile, legacyPath) then
						configPath = legacyPath
					end
				end
				if callSafely(isfile, configPath) then
					loaded = LoadConfiguration(callSafely(readfile, configPath))
				end
			else
				notified = true
				RayfieldLibrary:Notify({Title = "Rayfield Configurations", Content = "We couldn't enable Configuration Saving as you are not using software with filesystem support.", Image = 4384402990})
			end
		end)

		if success and loaded and not notified then
			RayfieldLibrary:Notify({Title = "Rayfield Configurations", Content = "The configuration file for this script has been loaded from a previous session.", Image = 4384403532})
		elseif not success and not notified then
			warn('Rayfield Configurations Error | '..tostring(result))
			RayfieldLibrary:Notify({Title = "Rayfield Configurations", Content = "We've encountered an issue loading your configuration correctly.\n\nCheck the Developer Console for more information.", Image = 4384402990})
		end
	end

	globalLoaded = true
end



if useStudio then
	-- run w/ studio
	-- Feel free to place your own script here to see how it'd work in Roblox Studio before running it on your execution software.


	--local Window = RayfieldLibrary:CreateWindow({
	--	Name = "Rayfield Example Window",
	--	LoadingTitle = "Rayfield Interface Suite",
	--	Theme = 'Default',
	--	Icon = 0,
	--	LoadingSubtitle = "by Sirius",
	--	ConfigurationSaving = {
	--		Enabled = true,
	--		FolderName = nil, -- Create a custom folder for your hub/game
	--		FileName = "Big Hub52"
	--	},
	--	Discord = {
	--		Enabled = false,
	--		Invite = "noinvitelink", -- The Discord invite code, do not include discord.gg/. E.g. discord.gg/ABCD would be ABCD
	--		RememberJoins = true -- Set this to false to make them join the discord every time they load it up
	--	},
	--	KeySystem = false, -- Set this to true to use our key system
	--	KeySettings = {
	--		Title = "Untitled",
	--		Subtitle = "Key System",
	--		Note = "No method of obtaining the key is provided",
	--		FileName = "Key", -- It is recommended to use something unique as other scripts using Rayfield may overwrite your key file
	--		SaveKey = true, -- The user's key will be saved, but if you change the key, they will be unable to use your script
	--		GrabKeyFromSite = false, -- If this is true, set Key below to the RAW site you would like Rayfield to get the key from
	--		Key = {"Hello"} -- List of keys that will be accepted by the system, can be RAW file links (pastebin, github etc) or simple strings ("hello","key22")
	--	}
	--})

	--local Tab = Window:CreateTab("Tab Example", 'key-round') -- Title, Image
	--local Tab2 = Window:CreateTab("Tab Example 2", 4483362458) -- Title, Image

	--local Section = Tab2:CreateSection("Section")


	--local ColorPicker = Tab2:CreateColorPicker({
	--	Name = "Color Picker",
	--	Color = Color3.fromRGB(255,255,255),
	--	Flag = "ColorPicfsefker1", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
	--	Callback = function(Value)
	--		-- The function that takes place every time the color picker is moved/changed
	--		-- The variable (Value) is a Color3fromRGB value based on which color is selected
	--	end
	--})

	--local Slider = Tab2:CreateSlider({
	--	Name = "Slider Example",
	--	Range = {0, 100},
	--	Increment = 10,
	--	Suffix = "Bananas",
	--	CurrentValue = 40,
	--	Flag = "Slidefefsr1", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
	--	Callback = function(Value)
	--		-- The function that takes place when the slider changes
	--		-- The variable (Value) is a number which correlates to the value the slider is currently at
	--	end,
	--})

	--local Input = Tab2:CreateInput({
	--	Name = "Input Example",
	--	CurrentValue = '',
	--	PlaceholderText = "Input Placeholder",
	--	Flag = 'dawdawd',
	--	RemoveTextAfterFocusLost = false,
	--	Callback = function(Text)
	--		-- The function that takes place when the input is changed
	--		-- The variable (Text) is a string for the value in the text box
	--	end,
	--})


	----RayfieldLibrary:Notify({Title = "Rayfield Interface", Content = "Welcome to Rayfield. These - are the brand new notification design for Rayfield, with custom sizing and Rayfield calculated wait times.", Image = 4483362458})

	--local Section = Tab:CreateSection("Section Example")

	--local Button = Tab:CreateButton({
	--	Name = "Change Theme",
	--	Callback = function()
	--		-- The function that takes place when the button is pressed
	--		Window.ModifyTheme('DarkBlue')
	--	end,
	--})

	--local Toggle = Tab:CreateToggle({
	--	Name = "Toggle Example",
	--	CurrentValue = false,
	--	Flag = "Toggle1adwawd", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
	--	Callback = function(Value)
	--		-- The function that takes place when the toggle is pressed
	--		-- The variable (Value) is a boolean on whether the toggle is true or false
	--	end,
	--})

	--local ColorPicker = Tab:CreateColorPicker({
	--	Name = "Color Picker",
	--	Color = Color3.fromRGB(255,255,255),
	--	Flag = "ColorPicker1awd", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
	--	Callback = function(Value)
	--		-- The function that takes place every time the color picker is moved/changed
	--		-- The variable (Value) is a Color3fromRGB value based on which color is selected
	--	end
	--})

	--local Slider = Tab:CreateSlider({
	--	Name = "Slider Example",
	--	Range = {0, 100},
	--	Increment = 10,
	--	Suffix = "Bananas",
	--	CurrentValue = 40,
	--	Flag = "Slider1dawd", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
	--	Callback = function(Value)
	--		-- The function that takes place when the slider changes
	--		-- The variable (Value) is a number which correlates to the value the slider is currently at
	--	end,
	--})

	--local Input = Tab:CreateInput({
	--	Name = "Input Example",
	--	CurrentValue = "Helo",
	--	PlaceholderText = "Adaptive Input",
	--	RemoveTextAfterFocusLost = false,
	--	Flag = 'Input1',
	--	Callback = function(Text)
	--		-- The function that takes place when the input is changed
	--		-- The variable (Text) is a string for the value in the text box
	--	end,
	--})

	--local thoptions = {}
	--for themename, theme in pairs(RayfieldLibrary.Theme) do
	--	table.insert(thoptions, themename)
	--end

	--local Dropdown = Tab:CreateDropdown({
	--	Name = "Theme",
	--	Options = thoptions,
	--	CurrentOption = {"Default"},
	--	MultipleOptions = false,
	--	Flag = "Dropdown1", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
	--	Callback = function(Options)
	--		--Window.ModifyTheme(Options[1])
	--		-- The function that takes place when the selected option is changed
	--		-- The variable (Options) is a table of strings for the current selected options
	--	end,
	--})


	--Window.ModifyTheme({
	--	TextColor = Color3.fromRGB(50, 55, 60),
	--	Background = Color3.fromRGB(240, 245, 250),
	--	Topbar = Color3.fromRGB(215, 225, 235),
	--	Shadow = Color3.fromRGB(200, 210, 220),

	--	NotificationBackground = Color3.fromRGB(210, 220, 230),
	--	NotificationActionsBackground = Color3.fromRGB(225, 230, 240),

	--	TabBackground = Color3.fromRGB(200, 210, 220),
	--	TabStroke = Color3.fromRGB(180, 190, 200),
	--	TabBackgroundSelected = Color3.fromRGB(175, 185, 200),
	--	TabTextColor = Color3.fromRGB(50, 55, 60),
	--	SelectedTabTextColor = Color3.fromRGB(30, 35, 40),

	--	ElementBackground = Color3.fromRGB(210, 220, 230),
	--	ElementBackgroundHover = Color3.fromRGB(220, 230, 240),
	--	SecondaryElementBackground = Color3.fromRGB(200, 210, 220),
	--	ElementStroke = Color3.fromRGB(190, 200, 210),
	--	SecondaryElementStroke = Color3.fromRGB(180, 190, 200),

	--	SliderBackground = Color3.fromRGB(200, 220, 235),  -- Lighter shade
	--	SliderProgress = Color3.fromRGB(70, 130, 180),
	--	SliderStroke = Color3.fromRGB(150, 180, 220),

	--	ToggleBackground = Color3.fromRGB(210, 220, 230),
	--	ToggleEnabled = Color3.fromRGB(70, 160, 210),
	--	ToggleDisabled = Color3.fromRGB(180, 180, 180),
	--	ToggleEnabledStroke = Color3.fromRGB(60, 150, 200),
	--	ToggleDisabledStroke = Color3.fromRGB(140, 140, 140),
	--	ToggleEnabledOuterStroke = Color3.fromRGB(100, 120, 140),
	--	ToggleDisabledOuterStroke = Color3.fromRGB(120, 120, 130),

	--	DropdownSelected = Color3.fromRGB(220, 230, 240),
	--	DropdownUnselected = Color3.fromRGB(200, 210, 220),

	--	InputBackground = Color3.fromRGB(220, 230, 240),
	--	InputStroke = Color3.fromRGB(180, 190, 200),
	--	PlaceholderColor = Color3.fromRGB(150, 150, 150)
	--})

	--local Keybind = Tab:CreateKeybind({
	--	Name = "Keybind Example",
	--	CurrentKeybind = "Q",
	--	HoldToInteract = false,
	--	Flag = "Keybind1", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
	--	Callback = function(Keybind)
	--		-- The function that takes place when the keybind is pressed
	--		-- The variable (Keybind) is a boolean for whether the keybind is being held or not (HoldToInteract needs to be true)
	--	end,
	--})

	--local Label = Tab:CreateLabel("Label Example")

	--local Label2 = Tab:CreateLabel("Warning", 4483362458, Color3.fromRGB(255, 159, 49),  true)

	--local Paragraph = Tab:CreateParagraph({Title = "Paragraph Example", Content = "Paragraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph Example"})
end

if CEnabled and Main:FindFirstChild('Notice') then
	Main.Notice.BackgroundTransparency = 1
	Main.Notice.Title.TextTransparency = 1
	Main.Notice.Size = UDim2.new(0, 0, 0, 0)
	Main.Notice.Position = UDim2.new(0.5, 0, 0, -100)
	Main.Notice.Visible = true


	TweenService:Create(Main.Notice, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut), {Size = UDim2.new(0, 280, 0, 35), Position = UDim2.new(0.5, 0, 0, -50), BackgroundTransparency = 0.5}):Play()
	TweenService:Create(Main.Notice.Title, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {TextTransparency = 0.1}):Play()
end
-- AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA why :(
--if not useStudio then
--	task.spawn(loadWithTimeout, "https://raw.githubusercontent.com/SiriusSoftwareLtd/Sirius/refs/heads/request/boost.lua")
--end

task.delay(4, function()
	RayfieldLibrary.LoadConfiguration()
	if Main:FindFirstChild('Notice') and Main.Notice.Visible then
		TweenService:Create(Main.Notice, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut), {Size = UDim2.new(0, 100, 0, 25), Position = UDim2.new(0.5, 0, 0, -100), BackgroundTransparency = 1}):Play()
		TweenService:Create(Main.Notice.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()

		task.wait(0.5)
		Main.Notice.Visible = false
	end
end)

return RayfieldLibrary

]=======]

local function patchRayfield(src)
    -- Rayfield leak patch (v10.95): SetDropdownOptions connects a theme
    -- handler for EVERY dropdown option that keeps indexing the option
    -- frame forever. Refresh destroys old option frames, so any later
    -- theme change errors "UIStroke is not a valid member of Frame"
    -- once per stale option. Guard both leaked handlers. Fail-open: if
    -- an anchor ever changes upstream, the unpatched library loads.
    local patched = false
    local a1 = "DropdownOption.UIStroke.Color = SelectedTheme.ElementStroke"
    if src:find(a1, 1, true) then
        src = src:gsub(
            "DropdownOption%.UIStroke%.Color = SelectedTheme%.ElementStroke",
            'local __s = DropdownOption:FindFirstChild("UIStroke"); '
                .. 'if __s then __s.Color = SelectedTheme.ElementStroke end',
            1)
        patched = true
    end
    local TAB = string.char(9)
    local a2 = "GetPropertyChangedSignal('BackgroundColor3')"
        .. ":Connect(function()\n" .. TAB:rep(6)
        .. "if not table.find(DropdownSettings.CurrentOption, droption.Name) then"
    local p2 = src:find(a2, 1, true)
    if p2 then
        local r2 = "GetPropertyChangedSignal('BackgroundColor3')"
            .. ":Connect(function()\n" .. TAB:rep(6)
            .. "if not droption.Parent then return end\n" .. TAB:rep(6)
            .. "if not table.find(DropdownSettings.CurrentOption, droption.Name) then"
        src = src:sub(1, p2 - 1) .. r2 .. src:sub(p2 + #a2)
        patched = true
    end
    return src, patched
end

local function loadFromSource(src, label)
    local patchedSrc, patched = patchRayfield(src)
    local chunk, cerr = loadstring(patchedSrc)
    if not chunk and patched then
        chunk, cerr = loadstring(src) -- pristine fallback
    end
    if not chunk then
        print("[SeedFarm] rayfield (" .. label .. ") compile failed: "
            .. tostring(cerr))
        return nil
    end
    print("[SeedFarm] rayfield leak patch: "
        .. (patched and "applied" or "anchor missed - unpatched")
        .. " (" .. label .. ")")
    local ok, result = pcall(chunk)
    if not ok or not result then
        print("[SeedFarm] rayfield (" .. label .. ") execute failed: "
            .. tostring(result))
        return nil
    end
    return result
end

-- stage A: live download (2 attempts, exact error printed)
for attempt = 1, 2 do
    local okHttp, srcOrErr = pcall(function()
        return game:HttpGet("https://sirius.menu/rayfield")
    end)
    if okHttp and type(srcOrErr) == "string" and #srcOrErr > 1000 then
        Rayfield = loadFromSource(srcOrErr, "download")
        if Rayfield then break end
    else
        print("[SeedFarm] rayfield download attempt " .. attempt
            .. " failed: " .. tostring(srcOrErr))
    end
    if attempt < 2 then task.wait(2) end
end
-- stage B: embedded copy
if not Rayfield then
    print("[SeedFarm] using embedded rayfield copy")
    Rayfield = loadFromSource(EMBEDDED_RAYFIELD, "embedded")
end

if not Rayfield then
    print("[SeedFarm] ERROR: Rayfield failed to load (internet/executor?) - old copy left running")
    return
end
print("[SeedFarm] Rayfield loaded")

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local LocalPlayer = Players.LocalPlayer

getgenv().__SeedFarmGen = (getgenv().__SeedFarmGen or 0) + 1
local MY_GEN = getgenv().__SeedFarmGen
local function stillAlive() return getgenv().__SeedFarmGen == MY_GEN end
pcall(function()
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local old = pg and pg:FindFirstChild("SeedFarmGui")
    if old then old:Destroy() end
    local oldPin = workspace:FindFirstChild("SeedFarmPin")
    if oldPin then oldPin:Destroy() end
    -- NOTE: do NOT destroy anything named "Rayfield" here - that GUI is the
    -- library's own core (created by the loadstring above, this run), and
    -- deleting it breaks CreateWindow ("Title is not a valid member of
    -- Frame Topbar"). Rayfield replaces its previous window on load, and
    -- the generation counter stops any old loops.
end)

-- AFK toggle state (defined early so the Idled handler can capture it)
local afkEnabled = false

-- Anti-AFK (toggleable): stays armed only when afkEnabled is true
pcall(function()
    local VirtualUser = game:GetService("VirtualUser")
    LocalPlayer.Idled:Connect(function()
        if afkEnabled then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
            print("[SeedFarm] anti-AFK kicked")
        end
    end)
end)

-- widen streaming radius so distant seeds replicate without walking to them
pcall(function()
    if Workspace.StreamingEnabled then
        Workspace.StreamingMinRadius = 100000
        print("[SeedFarm] streaming radius widened to 100000")
    else
        print("[SeedFarm] streaming not enabled")
    end
end)

local SAFE_ZONE = Vector3.new(0, 0.5, -28)
-- teleport pin: user-placed run destination (nil = use safe zone)
local pinPos = nil
local pinMarker = Instance.new("Part")
pinMarker.Name = "SeedFarmPin"
pinMarker.Size = Vector3.new(2, 2, 2)
pinMarker.Shape = Enum.PartType.Ball
pinMarker.Color = Color3.fromRGB(255, 200, 50)
pinMarker.Material = Enum.Material.Neon
pinMarker.Anchored = true
pinMarker.CanCollide = false
pinMarker.CanQuery = false
pinMarker.CanTouch = false
pinMarker.Transparency = 1
pinMarker.Parent = workspace
local RUN_SPEED = 250 -- adjustable via speed slider (0-500)
local ARRIVE_DIST = 10
local lastTeleportAt = 0

local selectedSeed = nil -- {model, prompt, name, tierStr, weight, pos}

-- Noclip: Stepped loop forces CanCollide off while enabled
local noclipEnabled = false
-- Auto Run: when ON, instantly runs back after a confirmed seed pickup
local autoRunEnabled = false
-- forward declaration: defined after runBtn, used by tpSeedBtn handler
local triggerRunback
local noclipParts = {}
local noclipChar = nil
pcall(function()
    game:GetService("RunService").Stepped:Connect(function()
        if noclipEnabled then
            local char = LocalPlayer.Character
            if char then
                if char ~= noclipChar then
                    noclipChar = char
                    noclipParts = {}
                    for _, p in ipairs(char:GetDescendants()) do
                        if p:IsA("BasePart") then
                            table.insert(noclipParts, p)
                        end
                    end
                end
                for _, p in ipairs(noclipParts) do
                    pcall(function() p.CanCollide = false end)
                end
            end
        end
    end)
end)

local function getRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end
local function getHumanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

-- Inf Jump state + handler (toggle lives in the GUI section)
local infJumpEnabled = false
game:GetService("UserInputService").JumpRequest:Connect(function()
    if infJumpEnabled then
        local humanoid = getHumanoid()
        if humanoid then
            pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end)
        end
    end
end)

-- Known Halloween seed IDs (from ReplicatedStorage.Assets.Seeds dump)
local HALLOWEEN_SEED_IDS = {
    ["HW_BLOODSTONE"] = true,
    ["HW_WITCHBLOOM"] = true,
    ["Seed_NightmareSoul"] = true,
    ["HW_PUMPKIN"] = true,
    ["HW_GOURD"] = true,
    ["HW_HEX"] = true,
    ["HW_MARSH"] = true,
    ["HW_MURKBOG"] = true,
    ["HW_RITUAL"] = true,
    ["HW_CHASM"] = true,
    ["HW_CROWN"] = true,
    ["HW_DREAD"] = true,
    ["HW_GRAVE"] = true,
    ["HW_ECLIPSE"] = true,
    ["HW_CROWN_HAUNTED"] = true,
    ["HW_DREAD_HAUNTED"] = true,
    ["HW_GRAVE_HAUNTED"] = true,
    ["HW_MARSH_HAUNTED"] = true,
    ["HW_RITUAL_HAUNTED"] = true,
    -- completed from the game's halloween.catalog (v10.110 dump):
    -- Sanguine, Nightmare, Black Pumpkin, all six werewolf seeds,
    -- and the remaining Ghostly variants were missing entirely
    ["HW_SANGUINE"] = true,
    ["HW_NIGHTMARE"] = true,
    ["HW_BLACK_PUMPKIN"] = true,
    ["HW_MOONFANG"] = true,
    ["HW_FERAL"] = true,
    ["HW_HOWLING"] = true,
    ["HW_BLOODFANG"] = true,
    ["HW_ALPHA"] = true,
    ["HW_LUNAR_ECLIPSE"] = true,
    ["HW_PUMPKIN_HAUNTED"] = true,
    ["HW_GOURD_HAUNTED"] = true,
    ["HW_HEX_HAUNTED"] = true,
    ["HW_WITCHBLOOM_HAUNTED"] = true,
    ["HW_MURKBOG_HAUNTED"] = true,
    ["HW_BLOODSTONE_HAUNTED"] = true,
    ["HW_CHASM_HAUNTED"] = true,
    ["HW_ECLIPSE_HAUNTED"] = true,
    ["HW_SANGUINE_HAUNTED"] = true,
    ["HW_MOONFANG_HAUNTED"] = true,
    ["HW_FERAL_HAUNTED"] = true,
    ["HW_HOWLING_HAUNTED"] = true,
    ["HW_BLOODFANG_HAUNTED"] = true,
    ["HW_ALPHA_HAUNTED"] = true,
    ["HW_LUNAR_ECLIPSE_HAUNTED"] = true,
}

-- halloween area folder names (leaf names from the HALLOWEEN_AREAS
-- paths further down; Castle nests under Abyss). Location is the
-- primary halloween signal (v10.109): a seed sitting inside one of
-- these folders IS a halloween seed even if its ID is brand new and
-- missing from the table above - the ID table and the biome
-- attribute are backups. (Fixes new halloween seeds leaking into
-- the Main tab, whose first scan pass tags everything "wild".)
local HALLOWEEN_AREA_NAMES = {
    HalloweenWitchwood = true, HalloweenMarsh = true,
    HalloweenHollow = true, HalloweenGraveyard = true,
    HalloweenCrypt = true, HalloweenAbyss = true,
    HalloweenCastle = true,
}
local function isHalloweenSeed(model, seedId)
    if seedId and HALLOWEEN_SEED_IDS[seedId] then return true end
    if not model then return false end
    if HALLOWEEN_SEED_IDS[model.Name] then return true end
    local anc = model.Parent
    while anc do
        if HALLOWEEN_AREA_NAMES[anc.Name] then return true end
        anc = anc.Parent
    end
    local bid = nil
    pcall(function() bid = model:GetAttribute("BiomeId") end)
    if type(bid) == "string"
        and bid:lower():find("halloween", 1, true) then
        return true
    end
    return false
end

-- SeedId database from wild-seed dump (Oct 10, 2026), synced with the
-- game's own seed-config (Oct 22, 2026 dump): all 53 config seeds.
-- Used as fallback when a seed's live SeedName/SeedTier attributes are missing.
local SEED_DB = {
    ["B01_T1"] = { name = "Sprout Seed", tier = "T1" },
    ["B01_T2"] = { name = "Overgrown Seed", tier = "T2" },
    ["B02_T1"] = { name = "Bog Seed", tier = "T1" },
    ["B02_T2"] = { name = "Mutagen Seed", tier = "T2" },
    ["B02_T3"] = { name = "Ancient Mire Seed", tier = "T3" },
    ["B03_T1"] = { name = "Frost Seed", tier = "T1" },
    ["B03_T2"] = { name = "Glacial Seed", tier = "T2" },
    ["B04_T1"] = { name = "Spore Seed", tier = "T1" },
    ["B04_T2"] = { name = "Mycelium Seed", tier = "T2" },
    ["B05_T1"] = { name = "Ember Seed", tier = "T1" },
    ["B05_T2"] = { name = "Magma Seed", tier = "T2" },
    ["B06_T1"] = { name = "Fossil Seed", tier = "T1" },
    ["B07_T1"] = { name = "Sample Seed", tier = "T1" },
    ["B07_T2"] = { name = "Prototype Seed", tier = "T2" },
    ["B07_T4"] = { name = "Colossus Seed", tier = "T4Guardian" },
    ["B08_T1"] = { name = "Xeno Seed", tier = "T1" },
    ["B08_T2"] = { name = "Cosmic Seed", tier = "T2" },
    ["HW_CHASM"] = { name = "Chasm Seed", tier = "T3" },
    ["HW_CROWN"] = { name = "Crown Seed", tier = "T3" },
    ["HW_CROWN_HAUNTED"] = { name = "👻 Ghostly Crown Seed", tier = "T3" },
    ["HW_DREAD"] = { name = "Dread Seed", tier = "T3" },
    ["HW_DREAD_HAUNTED"] = { name = "👻 Ghostly Dread Seed", tier = "T3" },
    ["HW_ECLIPSE"] = { name = "Eclipse Seed", tier = "T4Guardian" },
    ["HW_GOURD"] = { name = "Gourd Seed", tier = "T1" },
    ["HW_GRAVE"] = { name = "Grave Seed", tier = "T3" },
    ["HW_GRAVE_HAUNTED"] = { name = "👻 Ghostly Grave Seed", tier = "T3" },
    ["HW_HEX"] = { name = "Hex Seed", tier = "T2" },
    ["HW_MARSH"] = { name = "Spirit Seed", tier = "T2" },
    ["HW_MARSH_HAUNTED"] = { name = "👻 Ghostly Spirit Seed", tier = "T2" },
    ["HW_MURKBOG"] = { name = "Murkbog Seed", tier = "T2" },
    ["HW_PUMPKIN"] = { name = "Pumpkin Seed", tier = "T1" },
    ["HW_RITUAL"] = { name = "Ritual Seed", tier = "T3" },
    ["HW_RITUAL_HAUNTED"] = { name = "👻 Ghostly Ritual Seed", tier = "T3" },
    ["HW_BLOODSTONE"] = { name = "Bloodstone Seed", tier = "T3" },
    ["HW_BLOODSTONE_HAUNTED"] = { name = "👻 Ghostly Bloodstone Seed", tier = "T3" },
    ["HW_WITCHBLOOM"] = { name = "Witchbloom Seed", tier = "T2" },
    ["HW_WITCHBLOOM_HAUNTED"] = { name = "👻 Ghostly Witchbloom Seed", tier = "T2" },
    ["HW_PUMPKIN_HAUNTED"] = { name = "👻 Ghostly Pumpkin Seed", tier = "T1" },
    ["HW_GOURD_HAUNTED"] = { name = "👻 Ghostly Gourd Seed", tier = "T1" },
    ["HW_HEX_HAUNTED"] = { name = "👻 Ghostly Hex Seed", tier = "T2" },
    ["HW_MURKBOG_HAUNTED"] = { name = "👻 Ghostly Murkbog Seed", tier = "T2" },
    ["HW_CHASM_HAUNTED"] = { name = "👻 Ghostly Chasm Seed", tier = "T3" },
    ["HW_ECLIPSE_HAUNTED"] = { name = "👻 Ghostly Eclipse Seed", tier = "T4Guardian" },
    ["HW_SANGUINE"] = { name = "Sanguine Seed", tier = "T4Guardian" },
    ["HW_SANGUINE_HAUNTED"] = { name = "👻 Ghostly Sanguine Seed", tier = "T4Guardian" },
    ["HW_NIGHTMARE"] = { name = "Nightmare Seed", tier = "T4Guardian" },
    ["HW_BLACK_PUMPKIN"] = { name = "Black Pumpkin Seed", tier = "T1" },
    ["SW1_EXTRA"] = { name = "Prime Velocity Seed", tier = "T2" },
    ["SW1_FAILED"] = { name = "Failed Velocity Seed", tier = "T2" }, -- INF: inferred
    ["SW1_PERFECT"] = { name = "Perfect Velocity Seed", tier = "T4Guardian" }, -- seed-config
    ["SW1_REGULAR"] = { name = "Velocity Seed", tier = "T1" },
    ["SW2_EXTRA"] = { name = "Prime Overdrive Seed", tier = "T2" }, -- INF: inferred
    ["SW2_FAILED"] = { name = "Failed Overdrive Seed", tier = "T2" }, -- INF: inferred
    ["SW2_PERFECT"] = { name = "Perfect Overdrive Seed", tier = "T4Guardian" }, -- seed-config
    ["SW2_REGULAR"] = { name = "Overdrive Seed", tier = "T1" },
    ["SW3_EXTRA"] = { name = "Prime Hyper Seed", tier = "T2" },
    ["SW3_FAILED"] = { name = "Failed Hyper Seed", tier = "T2" }, -- INF: inferred
    ["SW3_PERFECT"] = { name = "Perfect Hyper Seed", tier = "T4Guardian" }, -- seed-config
    ["SW3_REGULAR"] = { name = "Hyper Seed", tier = "T1" },
    ["SW4_EXTRA"] = { name = "Prime Glitched Seed", tier = "T2" }, -- INF: inferred
    ["SW4_FAILED"] = { name = "Failed Glitched Seed", tier = "T2" },
    ["SW4_PERFECT"] = { name = "Perfect Glitched Seed", tier = "T4Guardian" }, -- seed-config -- INF: inferred
    ["SW4_REGULAR"] = { name = "Glitched Seed", tier = "T1" },
    ["SW5_EXTRA"] = { name = "Prime Hacked Seed", tier = "T2" }, -- INF: inferred
    ["SW5_FAILED"] = { name = "Failed Hacked Seed", tier = "T2" },
    ["SW5_PERFECT"] = { name = "Perfect Hacked Seed", tier = "T4Guardian" }, -- seed-config
    ["SW5_REGULAR"] = { name = "Hacked Seed", tier = "T1" },
    -- seed-config sync (Oct 22, 2026): the T3/T4 wild seeds, the six
    -- Specials, and the Arena seeds were missing from this DB - without an
    -- entry a seed whose live SeedTier attribute is absent falls back to
    -- T1, so T3+/T4+ target filters and TP TO BEST misjudged them.
    ["B01_T3"] = { name = "Ancient Wildroot Seed", tier = "T3" },
    ["B01_T4"] = { name = "Seedwarden Seed", tier = "T4Guardian" },
    ["B02_T4"] = { name = "Marshlord Seed", tier = "T4Guardian" },
    ["B03_T3"] = { name = "Ancient Permafrost Seed", tier = "T3" },
    ["B03_T4"] = { name = "Frostwarden Seed", tier = "T4Guardian" },
    ["B04_T3"] = { name = "Ancient Mycelium Seed", tier = "T3" },
    ["B04_T4"] = { name = "Mycelord Seed", tier = "T4Guardian" },
    ["B05_T3"] = { name = "Ancient Caldera Seed", tier = "T3" },
    ["B05_T4"] = { name = "Embermane Seed", tier = "T4Guardian" },
    ["B06_T2"] = { name = "Primal Seed", tier = "T2" },
    ["B06_T3"] = { name = "Ancient Amber Seed", tier = "T3" },
    ["B06_T4"] = { name = "Bonecrusher Seed", tier = "T4Guardian" },
    ["B07_T3"] = { name = "Ancient Genome Seed", tier = "T3" },
    ["B08_T3"] = { name = "Ancient Void Seed", tier = "T3" },
    ["B08_T4"] = { name = "Voidwarden Seed", tier = "T4Guardian" },
    ["ANCIENT_SEED"] = { name = "Primordial Seed", tier = "T4Guardian" },
    ["ABYSSAL_LEVIATHAN_SEED"] = { name = "Abyssal Seed", tier = "T4Guardian" },
    ["NIGHTMARE_SOUL_SEED"] = { name = "Nightmare Soul Seed", tier = "T4Guardian" },
    ["BLOODMOON_CURSE_SEED"] = { name = "Bloodmoon Curse Seed", tier = "T4Guardian" },
    ["BLACK_HOLE_SEED"] = { name = "Black Hole Seed", tier = "T4Guardian" },
    ["PUMPKIN_IMP_SEED"] = { name = "Pumpkin Imp Seed", tier = "T4Guardian" },
    ["ARENA_SEED"] = { name = "Legionary Seed", tier = "T1" },
    ["ARENA_IMPERIAL_SEED"] = { name = "Legatus Seed", tier = "T1" },
    ["ARENA_FROSTGUARD_SEED"] = { name = "Centurion Seed", tier = "T1" },
    ["ARENA_LEGION_SEED"] = { name = "Imperator Seed", tier = "T1" },
}

-- startup self-report (v10.90): subsystems record their status here as
-- they resolve; one console block prints it all ~12s after load
local selfReport = {}

-- Self-checking seed catalog (v10.87): compare SEED_DB against the game's
-- OWN seed-config at runtime and auto-register anything missing (with the
-- game's displayName + tier), so a game update that adds seeds no longer
-- needs a manual DB sync. One console line reports the result.
task.spawn(function()
    task.wait(8)
    pcall(function()
        local cfg = nil
        pcall(function()
            local rs = game:GetService("ReplicatedStorage")
            local common = rs:FindFirstChild("Common")
            local cfgFolder = common and common:FindFirstChild("config")
            local m = cfgFolder and cfgFolder:FindFirstChild("seed-config")
            if m then cfg = require(m) end
        end)
        local gameSeeds = nil
        if type(cfg) == "table" then
            for _, key in ipairs({ "SEEDS", "Seeds", "seeds" }) do
                if type(cfg[key]) == "table" then gameSeeds = cfg[key] break end
            end
            if not gameSeeds then
                local function looksLikeSeeds(t)
                    local n = 0
                    for k, v in pairs(t) do
                        if type(k) == "string" and type(v) == "table"
                            and v.displayName then
                            n += 1
                        end
                    end
                    return n > 10
                end
                if looksLikeSeeds(cfg) then
                    gameSeeds = cfg
                else
                    for _, v in pairs(cfg) do
                        if type(v) == "table" and looksLikeSeeds(v) then
                            gameSeeds = v
                            break
                        end
                    end
                end
            end
        end
        if not gameSeeds then
            print("[SeedFarm] catalog check: seed-config not resolved - skipped")
            selfReport.catalog = "seed-config not resolved - skipped"
            return
        end
        local total, added = 0, {}
        for id, entry in pairs(gameSeeds) do
            if type(id) == "string" and type(entry) == "table"
                and entry.displayName then
                total += 1
                if not SEED_DB[id] then
                    SEED_DB[id] = {
                        name = entry.displayName,
                        tier = entry.tier or "T1",
                    }
                    added[#added + 1] = id .. " (" .. entry.displayName
                        .. ", " .. (entry.tier or "T1") .. ")"
                end
            end
        end
        if #added > 0 then
            print("[SeedFarm] catalog check: game has " .. total
                .. " seeds - ADDED " .. #added .. " missing to DB: "
                .. table.concat(added, "; "))
            selfReport.catalog = "game has " .. total .. " seeds, added "
                .. #added .. " missing to DB"
        else
            print("[SeedFarm] catalog check: game has " .. total
                .. " seeds - farm DB covers all of them")
            selfReport.catalog = "game has " .. total
                .. " seeds, DB covers all"
        end
    end)
end)

-- Find all wild seeds (same logic as v7.2 which worked)
-- Now scans multiple roots: WildSeeds, BlackHoleArena spawn points, MutantCore shells
-- Also accepts "Collect" prompts (fragments etc.) which lack SeedUid.
local function getSeedData(prompt, source)
    -- walk up looking for SeedUid
    local p = prompt.Parent
    local uidHolder = nil
    local foundUid = nil
    while p do
        local ok, uid = pcall(function() return p:GetAttribute("SeedUid") end)
        if ok and uid and uid ~= "" then
            foundUid = uid
            uidHolder = p
            break
        end
        if p.Name == "WildSeeds" or p.Name == "BlackHoleSeedSpawnPoints" or p.Name == "MutantCoreSeedShells" then break end
        p = p.Parent
    end
    -- fallback for collectibles without SeedUid
    if not foundUid then
        if prompt.ActionText ~= "Collect" then return nil end
        uidHolder = prompt.Parent
        foundUid = "collect_" .. uidHolder:GetFullName()
    end
    p = uidHolder
    local _sid = p:GetAttribute("SeedId") or ""
    local _db = SEED_DB[_sid]
    local tierStr = p:GetAttribute("SeedTier") or (_db and _db.tier) or "T1"
    local tierNum = tonumber(tierStr:match("T(%d+)")) or 1
    local pos = nil
    pcall(function()
        local mesh = p:FindFirstChild("mesh", true)
        if mesh and mesh:IsA("BasePart") then
            pos = mesh.Position
        else
            pos = p:GetPivot().Position
        end
    end)
    -- mutation detection: any "mutat" attribute set, or WeatherMutations non-empty
    local mutated = false
    pcall(function()
        for k, v in pairs(p:GetAttributes()) do
            local kl = k:lower()
            if kl:find("mutat") and v ~= "" and v ~= false and v ~= nil then
                mutated = true
                break
            end
        end
        if not mutated then
            local wm = p:GetAttribute("WeatherMutations")
            if wm and wm ~= "" then mutated = true end
        end
    end)
    -- halloween detection: source tag or known seed ID
    local seedId = _sid
    local isHalloween = source == "halloween" or isHalloweenSeed(p, seedId)
    return {
        model = p,
        prompt = prompt,
        uid = foundUid,
        seedId = seedId,
        biomeId = p:GetAttribute("BiomeId") or "",
        tierStr = tierStr,
        tier = tierNum,
        weight = tonumber(p:GetAttribute("SeedWeightKg")) or 0,
        name = (source == "abyssal") and "Abyssal Seed" or (p:GetAttribute("SeedName") or (_db and _db.name) or "?"),
        pos = pos,
        source = isHalloween and "halloween" or (source or "wild"), -- "wild" | "blackhole" | "mutant" | "halloween"
        mutated = mutated,
    }
end

-- Event folders accept ANY prompt ActionText (not just Steal/Collect),
-- since event items get prompts added dynamically.
local function scanRoot(root, source, seeds, anyPrompt, skipSeen)
    if not root then return 0 end
    local count = 0
    for _, prompt in ipairs(root:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and (not skipSeen or not skipSeen[prompt])
            and (anyPrompt or prompt.ActionText == "Steal" or prompt.ActionText == "Collect") then
            local data = getSeedData(prompt, source)
            if data and data.pos then
                -- tag collectibles (fragments etc.)
                if prompt.ActionText == "Collect" then
                    data.isCollectible = true
                    if data.name == "?" then
                        data.name = prompt.Parent and prompt.Parent.Name or "Collectible"
                    end
                end
                table.insert(seeds, data)
                count += 1
            end
        end
    end
    return count
end

-- Name-based fallback: list event items by model name even without prompts
-- (teleport to them; touch or manual collect).
local function scanByName(root, source, seeds, label)
    if not root then return 0 end
    local count = 0
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("Model") or d:IsA("MeshPart") or d:IsA("Part") then
            local n = d.Name:lower()
            local isTarget = false
            if source == "abyssal" and n:find("abyssal") and n:find("fragment") then isTarget = true end
            if source == "core" and n:find("core") and n:find("seed") and not n:find("vault") and not n:find("pass") and not n:find("shell") then isTarget = true end
            if isTarget then
                -- skip if already listed via prompt scan
                local already = false
                for _, s in ipairs(seeds) do
                    if s.model == d then already = true break end
                end
                if not already then
                    local pos = nil
                    pcall(function() pos = d:GetPivot().Position end)
                    if pos then
                        table.insert(seeds, {
                            model = d, prompt = nil, uid = "name_" .. d:GetFullName(),
                            seedId = "", biomeId = "", tierStr = "EVT", tier = 99,
                            weight = 0, name = label or d.Name, pos = pos,
                            source = source, mutated = false, isEventItem = true,
                        })
                        count += 1
                    end
                end
            end
        end
    end
    return count
end

-- Lenient seed data for workspace-wide sweep: accepts any prompt whose
-- ancestor has seed-like attributes (doesn't require SeedUid).
local function getSweepData(prompt)
    local p = prompt.Parent
    local best = nil
    local depth = 0
    while p and p ~= Workspace and depth < 8 do
        local ok, attrs = pcall(function() return p:GetAttributes() end)
        if ok and attrs then
            local hasSeedAttr = attrs.SeedUid or attrs.SeedTier or attrs.SeedName or attrs.SeedId
            if hasSeedAttr then
                best = p
                break
            end
        end
        -- also accept models named like seeds or special types
        -- (but reject NPCs, shops, portals, halls)
        local n = p.Name:lower()
        local fullLower = p:GetFullName():lower()
        local isJunkContext = fullLower:find("npc") or fullLower:find("shop")
            or fullLower:find("portal") or fullLower:find("hall") or n:find("talk")
            or n:find("gravekeeper") or n:find("pumpkin merchant") or n:find("merchant")
        local isSeedLike = n:find("seed") or n:find("fragment")
        local isSpecialLike = (n:find("hyper") or n:find("glitch") or n:find("hacker") or n:find("hack")
            or n:find("overdrive") or n:find("velocity") or n:find("blackhole"))
            and not isJunkContext
        -- "abyssal"/"mutant"/"core" only count when paired with seed/fragment
        -- (or when the full path contains "blackholeseed")
        local isEventLike = ((n:find("abyssal") or n:find("mutant") or n:find("core"))
            and (n:find("seed") or n:find("fragment") or fullLower:find("blackholeseed")))
            and not isJunkContext
        if (p:IsA("Model") or p:IsA("MeshPart") or p:IsA("Part")) and (isSeedLike or isSpecialLike or isEventLike) then
            if not n:find("vault") and not n:find("pad") and not n:find("shell") and not n:find("pass") then
                best = p
                break
            end
        end
        p = p.Parent
        depth += 1
    end
    if not best then return nil end
    p = best
    -- detect blackhole egg by full path (e.g. Map.Runtime.BlackHoleSeed.Core)
    local fullPath = p:GetFullName():lower()
    local isBlackHole = fullPath:find("blackhole")
    local _sid = p:GetAttribute("SeedId") or ""
    local _db = SEED_DB[_sid]
    local tierStr = p:GetAttribute("SeedTier") or (_db and _db.tier) or "T1"
    local tierNum = tonumber(tierStr:match("T(%d+)")) or 1
    local pos = nil
    pcall(function()
        local mesh = p:FindFirstChild("mesh", true)
        if mesh and mesh:IsA("BasePart") then
            pos = mesh.Position
        else
            pos = p:GetPivot().Position
        end
    end)
    if not pos then return nil end
    -- also try prompt parent position as fallback
    if not pos then
        pcall(function() pos = prompt.Parent:GetPivot().Position end)
    end
    if not pos then return nil end
    local dispName = p:GetAttribute("SeedName") or (_db and _db.name) or p.Name
    if isBlackHole and dispName:lower() == "core" then
        dispName = "BlackHole Egg"
    end
    return {
        model = p,
        prompt = prompt,
        uid = "sweep_" .. p:GetFullName(),
        seedId = _sid,
        biomeId = p:GetAttribute("BiomeId") or "",
        tierStr = tierStr,
        tier = tierNum,
        weight = tonumber(p:GetAttribute("SeedWeightKg")) or 0,
        name = dispName,
        pos = pos,
        source = isBlackHole and "blackhole"
            or (isHalloweenSeed(p, _sid) and "halloween" or "sweep"),
        mutated = false,
    }
end

-- Area paths as nested lookups: HalloweenCastle lives under HalloweenAbyss,
-- not directly under WildSeeds.
local HALLOWEEN_AREAS = {
    {"HalloweenWitchwood"}, {"HalloweenMarsh"}, {"HalloweenHollow"},
    {"HalloweenGraveyard"}, {"HalloweenCrypt"},
    {"HalloweenAbyss"}, {"HalloweenAbyss", "HalloweenCastle"},
}

-- console-quiet state (v10.91): scan diagnostics print on change only
local lastScanPrintSig = nil
local sweepPrinted = {} -- prompt instance -> already announced

local function findWildSeeds()
    local seeds = {}
    pcall(function()
        local map = Workspace:FindFirstChild("Map")
        -- 1. normal wild seeds (all biomes, incl. SpeedwayT4/T5 subfolders)
        local ws = map and map:FindFirstChild("WildSeeds")
        local n1 = scanRoot(ws, "wild", seeds, false)
        -- 2. black hole arena seeds (any prompt type)
        local bha = map and map:FindFirstChild("Biomes")
        bha = bha and bha:FindFirstChild("BlackHoleArena")
        local bhsp = bha and bha:FindFirstChild("BlackHoleSeedSpawnPoints")
        local n2 = scanRoot(bhsp, "blackhole", seeds, true)
        -- 2c. LIVE Black Hole event seed (black-hole-seed-config, Oct 23
        -- 2026): the event seed is a CollectionService-tagged model carrying
        -- its own state attributes - not a spawn-point prompt - so list it
        -- directly. Dedupe by model against the scans above.
        pcall(function()
            for _, inst in ipairs(CollectionService:GetTagged("BlackHoleSeed")) do
                local already = false
                for _, s in ipairs(seeds) do
                    if s.model == inst then already = true break end
                end
                if not already then
                    local pos = nil
                    pcall(function() pos = inst:GetPivot().Position end)
                    if pos then
                        local prompt = inst:FindFirstChildOfClass("ProximityPrompt", true)
                        local sid = inst:GetAttribute("SeedId") or "BLACK_HOLE_SEED"
                        local db = SEED_DB[sid]
                        local tStr = inst:GetAttribute("SeedTier") or (db and db.tier) or "T4Guardian"
                        table.insert(seeds, {
                            model = inst, prompt = prompt,
                            uid = inst:GetAttribute("SeedUid") or "blackhole_event",
                            seedId = sid,
                            biomeId = inst:GetAttribute("BiomeId") or "",
                            tierStr = tStr,
                            tier = tonumber(tStr:match("T(%d+)")) or 4,
                            weight = tonumber(inst:GetAttribute("SeedWeightKg")) or 0,
                            name = inst:GetAttribute("SeedName") or (db and db.name) or "Black Hole Seed",
                            pos = pos, source = "blackhole", mutated = false,
                            isEventItem = true,
                        })
                    end
                end
            end
        end)
        -- 3. mutant core seed shells (any prompt type)
        local mcss = Workspace:FindFirstChild("MutantCoreSeedShells")
        local n3 = scanRoot(mcss, "mutant", seeds, true)
        -- 4. mutant core vault under WildSeeds (any prompt type) + name fallback
        local mcv = ws and ws:FindFirstChild("MutantCoreVault")
        local n4 = scanRoot(mcv, "core", seeds, true)
        local n4b = scanByName(mcv, "core", seeds, "Core Seed")
        -- 5. abyssal seeds under Map.Runtime (any prompt type)
        -- (fragment name fallback removed - only real collectible seeds)
        local rt = map and map:FindFirstChild("Runtime")
        local af = rt and rt:FindFirstChild("AbyssalFragments")
        local n5 = scanRoot(af, "abyssal", seeds, true)
        -- 6. speedway codex seed pads (Tier1-5 SeedPad under LaboratoryPresentation)
        local codex = Workspace:FindFirstChild("Speedway_V3_Codex")
        local n6 = scanRoot(codex, "codex", seeds, true)
        -- 6b. Halloween WildSeeds areas (any prompt type, dedicated source tag)
        local n6b = 0
        -- skip prompts already listed by earlier scans: the recursive wild sweep
        -- above already covers Halloween descendants, so re-scanning them would
        -- duplicate dropdown entries
        local seen6b = {}
        for _, s in ipairs(seeds) do
            if s.prompt then seen6b[s.prompt] = true end
        end
        for _, areaPath in ipairs(HALLOWEEN_AREAS) do
            local area = ws
            for _, part in ipairs(areaPath) do
                area = area and area:FindFirstChild(part)
            end
            local before = #seeds
            n6b += scanRoot(area, "halloween", seeds, true, seen6b)
            for i = before + 1, #seeds do
                if seeds[i].prompt then seen6b[seeds[i].prompt] = true end
            end
        end
        -- 7. WORKSPACE-WIDE SWEEP: catch seeds in any location we haven't mapped.
        --    Accepts ANY prompt ActionText (special seeds may not use Steal/Collect).
        --    Only adds prompts not already found (dedupe by prompt instance).
        local n7 = 0
        local seenPrompts = {}
        for _, s in ipairs(seeds) do
            if s.prompt then seenPrompts[s.prompt] = true end
        end
        for _, prompt in ipairs(Workspace:GetDescendants()) do
            if prompt:IsA("ProximityPrompt") and not seenPrompts[prompt] then
                -- skip player GUI, plots/pens (planted seeds), player scripts,
                -- NPCs/shops/portals (talk/lobby prompts, not seeds)
                -- + NightmareRealm NPCs (Gravekeeper, Pumpkin Merchant)
                local full = prompt:GetFullName()
                local flower = full:lower()
                local at = prompt.ActionText:lower()
                if not full:find("PlayerGui") and not full:find("Backpack") and not full:find("PlayerScripts")
                    and not flower:find("pens") and not flower:find("planted_")
                    and not flower:find("plot") and not flower:find("base")
                    and not flower:find("npc") and not flower:find("shop")
                    and not flower:find("portal") and not flower:find("mutanthall")
                    and not flower:find("gravekeeper") and not flower:find("pumpkin merchant")
                    and at ~= "talk" and at ~= "return to lobby" then
                    local data = getSeedData(prompt, "sweep")
                    if not data then
                        data = getSweepData(prompt)
                    end
                    if data and data.pos then
                        -- tag with the actual prompt text for debugging
                        data.sweepPromptText = prompt.ActionText
                        table.insert(seeds, data)
                        n7 += 1
                        if not sweepPrinted[prompt] then
                            sweepPrinted[prompt] = true
                            print(string.format("[SeedFarm] sweep found: '%s' prompt='%s' at %s",
                                data.name, prompt.ActionText, prompt:GetFullName()))
                        end
                    end
                end
            end
        end
        -- tier breakdown for debugging - printed only when the tally
        -- changes (v10.91): findWildSeeds runs every 1.5s from the
        -- background refresh plus ESP/vacuum/farm scans, and printing
        -- every call flooded the console with identical blocks
        local tiers = {}
        for _, s in ipairs(seeds) do
            tiers[s.tierStr] = (tiers[s.tierStr] or 0) + 1
        end
        local tstr = {}
        for t, n in pairs(tiers) do table.insert(tstr, t .. "=" .. n) end
        table.sort(tstr) -- stable order: pairs() shuffling must not fake a change
        local scanSig = string.format("%d,%d,%d,%d,%d,%d,%d,%d,%d,%d|%s",
            n1, n2, n3, n4, n4b, n5, n6, n6b, n7, #seeds,
            table.concat(tstr, " "))
        if scanSig ~= lastScanPrintSig then
            lastScanPrintSig = scanSig
            print(string.format("[SeedFarm] scan: wild=%d bh=%d mutant=%d core=%d+%d abyssal=%d codex=%d halloween=%d sweep=%d total=%d",
                n1, n2, n3, n4, n4b, n5, n6, n6b, n7, #seeds))
            print("[SeedFarm] tiers: " .. table.concat(tstr, " "))
        end
    end)
    -- no filters: show every spawned seed
    -- (special types still get isSpecial flag for styling)
    local SPECIAL_TYPES = { "hyper", "overdrive", "hacker", "glitched", "velocity" }
    for _, s in ipairs(seeds) do
        local nameId = (s.name .. " " .. s.seedId):lower()
        for _, t in ipairs(SPECIAL_TYPES) do
            if nameId:find(t, 1, true) then s.isSpecial = true break end
        end
    end
    -- crown the single rarest/most valuable seed: value = tier first, then weight,
    -- with bonuses for mutated / special / event sources
    local function valueScore(s)
        local score = s.tier * 1e12 + math.min(s.weight, 1e12)
        if s.mutated or s.source == "mutant" then score += 5e11 end
        if s.source == "abyssal" or s.source == "core" then score += 4e11 end
        if s.source == "halloween" then score += 3.5e11 end
        if s.source == "blackhole" then score += 3e11 end
        if s.isSpecial then score += 2e11 end
        if s.isCollectible then score += 1e11 end
        return score
    end
    local topSeed, topScore = nil, -1
    for _, s in ipairs(seeds) do
        local sc = valueScore(s)
        if sc > topScore then topScore, topSeed = sc, s end
    end
    if topSeed then topSeed.isTopSeed = true end
    -- filter: hide T1 seeds that aren't prime (top) or mutated and weigh under 25k
    local kept = {}
    for _, s in ipairs(seeds) do
        if not (s.tierStr == "T1" and not s.isTopSeed and not s.mutated and s.weight < 25000) then
            table.insert(kept, s)
        end
    end
    seeds = kept
    -- sort: tier descending (T4, T3, T2, T1), then weight descending
    table.sort(seeds, function(a, b)
        if a.tier ~= b.tier then return a.tier > b.tier end
        return a.weight > b.weight
    end)
    return seeds
end

-- Black Hole event watcher (black-hole-seed-config, Oct 23 2026): announce
-- the event seed when it appears and report carrier changes from its
-- BlackHoleState / BlackHoleCarrierUserId attributes. The carrier runs at
-- HALF speed (CarrierSpeedMultiplier 0.5), so warn Daniel if it's him.
local bhWatched = {}
local bhTrailPos = nil
local function bhPlayerName(userId)
    if not userId or userId == 0 then return nil end
    local plr = Players:GetPlayerByUserId(userId)
    if plr then return plr.DisplayName .. " (@" .. plr.Name .. ")" end
    return "user " .. tostring(userId)
end
task.spawn(function()
    task.wait(3)
    while true do
        pcall(function()
            for _, inst in ipairs(CollectionService:GetTagged("BlackHoleSeed")) do
                if not bhWatched[inst] then
                    bhWatched[inst] = true
                    local pos = nil
                    pcall(function() pos = inst:GetPivot().Position end)
                    print("[SeedFarm] BLACK HOLE SEED LIVE"
                        .. (pos and (" at " .. tostring(pos)) or ""))
                    local function reportState()
                        if not inst.Parent then return end
                        local state = inst:GetAttribute("BlackHoleState")
                        local carrier = inst:GetAttribute("BlackHoleCarrierUserId")
                        local who = bhPlayerName(carrier)
                        if who then
                            print("[SeedFarm] Black Hole seed carried by " .. who
                                .. " (state=" .. tostring(state) .. ")")
                            if carrier == LocalPlayer.UserId then
                                print("[SeedFarm] Black Hole carrier is YOU - "
                                    .. "your speed is HALF (0.5x) while you "
                                    .. "hold it! Delivery: your standard "
                                    .. "safe zone.")
                            end
                        else
                            print("[SeedFarm] Black Hole seed state=" .. tostring(state))
                        end
                    end
                    reportState()
                    inst:GetAttributeChangedSignal("BlackHoleCarrierUserId"):Connect(reportState)
                    inst:GetAttributeChangedSignal("BlackHoleState"):Connect(reportState)
                end
            end
        end)
        -- delivery probe (v10.88): while DANIEL carries the event seed,
        -- log a position trail - where the trail ends is the bank point
        pcall(function()
            local inst = nil
            for _, t in ipairs(CollectionService:GetTagged("BlackHoleSeed")) do
                inst = t
                break
            end
            if inst and inst:GetAttribute("BlackHoleCarrierUserId")
                == LocalPlayer.UserId then
                local root = getRoot()
                if root then
                    local p = root.Position
                    if not bhTrailPos
                        or (p - bhTrailPos).Magnitude > 10 then
                        bhTrailPos = p
                        print("[SeedFarm] 🕳️ BH trail: " .. tostring(p)
                            .. " state="
                            .. tostring(inst:GetAttribute("BlackHoleState")))
                    end
                end
            elseif bhTrailPos then
                print("[SeedFarm] 🕳️ BH trail END - you no longer carry "
                    .. "it (banked, dropped, or taken)")
                bhTrailPos = nil
            end
        end)
        task.wait(2)
    end
end)

-- Guardian detection
local guardians = {}
local lastGuardianScan = 0
local function getModelPos(model)
    local ok, pos = pcall(function()
        if model.PrimaryPart then return model.PrimaryPart.Position end
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp then return hrp.Position end
        for _, p in ipairs(model:GetDescendants()) do
            if p:IsA("BasePart") then return p.Position end
        end
        return nil
    end)
    if ok then return pos end
    return nil
end
local function scanGuardians()
    if os.clock() - lastGuardianScan < 10 then return guardians end
    lastGuardianScan = os.clock()
    guardians = {}
    pcall(function()
        local map = Workspace:FindFirstChild("Map")
        local gfolder = map and map:FindFirstChild("Guardians")
        if gfolder then
            for _, g in ipairs(gfolder:GetChildren()) do
                if g.Name:find("Guardian_Biome") then
                    local pos = getModelPos(g)
                    if pos then table.insert(guardians, {model = g, pos = pos}) end
                end
            end
        end
    end)
    return guardians
end
local function nearestGuardian(fromPos)
    local list = scanGuardians()
    local best, bestDist = nil, math.huge
    for _, g in ipairs(list) do
        local pos = getModelPos(g.model)
        if pos then g.pos = pos end
        local d = (g.pos - fromPos).Magnitude
        if d < bestDist then best, bestDist = g, d end
    end
    return best, bestDist
end

-- Teleport to seed + instant pickup
local lastCarryData = nil
local lastCarrySeq = 0
local lastDeliverySeq = 0
local lastDeliveryUid = nil
local lastCarriedUid = nil
local manualTpPending = false

local approachByRun = false -- halloween farm run-in flag (set by the
-- farm cycle below; declared here because teleportToSelected is
-- defined before the areaFarm table exists - v10.105 crash fix)
local function teleportToSelected()
    if not selectedSeed then
        return "Pick a seed first!"
    end
    local root = getRoot()
    if not root then return "No character!" end
    -- re-check seed still exists
    if not selectedSeed.model.Parent then
        return "Seed is gone!"
    end
    local function carryCount(quick)
        local total = 0
        local sid = selectedSeed.seedId
        local uid = selectedSeed.uid
        local nm = selectedSeed.name
        local roots = {}
        local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
        if bp then table.insert(roots, bp) end
        if LocalPlayer.Character then table.insert(roots, LocalPlayer.Character) end
        if not quick then
            local pgui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if pgui then table.insert(roots, pgui) end
        end
        for _, r in ipairs(roots) do
            for _, d in ipairs(r:GetDescendants()) do
                local match = false
                if uid and uid ~= "" and uid:sub(1, 5) ~= "name_" then
                    local okA, v = pcall(function() return d:GetAttribute("SeedUid") end)
                    if okA and v == uid then match = true end
                end
                if not match and sid and sid ~= "" then
                    local okA, v = pcall(function() return d:GetAttribute("SeedId") end)
                    if okA and v == sid then match = true end
                end
                if not match and nm and (d:IsA("Tool") or d:IsA("Model")) and d.Name == nm then
                    match = true
                end
                if match then
                    local q = 1
                    for _, an in ipairs({ "Count", "Amount", "Quantity" }) do
                        local okA, v = pcall(function() return d:GetAttribute(an) end)
                        if okA and type(v) == "number" then q = v break end
                    end
                    total += q
                end
            end
        end
        return total
    end
    local carryBefore = carryCount(false)
    local carrySeqBefore = lastCarrySeq
    local carryQuickBefore = carryCount(true)
    print(string.format("[SeedFarm] carry snapshot before pickup: full=%d quick=%d", carryBefore, carryQuickBefore))
    local pos = selectedSeed.pos
    print(string.format("[SeedFarm] teleporting to %s (%s)", selectedSeed.name, selectedSeed.tierStr))
    pcall(function()
        pos = selectedSeed.model:GetPivot().Position
    end)
    if approachByRun then
        -- Halloween farm run-in (v10.103, Daniel's ask): walk to the
        -- seed on foot instead of teleporting, then fall through to
        -- the same prompt + confirm flow below.
        local hum = getHumanoid()
        local savedSpd = hum and hum.WalkSpeed
        print("[SeedFarm] halloween farm: running to " .. selectedSeed.name)
        local t0 = os.clock()
        local lastP = root.Position
        while true do
            task.wait(0.25)
            if not stillAlive() then return "Died en route!" end
            if not (selectedSeed.model and selectedSeed.model.Parent) then
                if savedSpd then
                    pcall(function() hum.WalkSpeed = savedSpd end)
                end
                return "Seed is gone!"
            end
            root = getRoot()
            hum = getHumanoid()
            if root and hum then
                pcall(function()
                    pos = selectedSeed.model:GetPivot().Position
                end)
                local d = (root.Position - pos).Magnitude
                if d <= 7 then break end
                if os.clock() - t0 > 120 then
                    if savedSpd then
                        pcall(function() hum.WalkSpeed = savedSpd end)
                    end
                    return "Run to seed timed out!"
                end
                pcall(function() hum.WalkSpeed = RUN_SPEED end)
                if (root.Position - lastP).Magnitude < 0.5 then
                    pcall(function() hum.Jump = true end)
                end
                lastP = root.Position
                hum:MoveTo(pos)
            else
                task.wait(0.5)
            end
        end
        if savedSpd then pcall(function() hum.WalkSpeed = savedSpd end) end
        print("[SeedFarm] halloween farm: at the seed")
    else
        root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
    end
    lastTeleportAt = os.clock()
    task.wait(0.2)
    -- instant prompt pickup (skip if no prompt: touch/manual item)
    local prompt = selectedSeed.prompt
    local promptValid = false
    pcall(function() promptValid = prompt ~= nil and prompt.Parent ~= nil end)
    if not promptValid then
        -- seed model may have recreated its prompt since the scan:
        -- re-find fresh, preferring the same ActionText
        pcall(function()
            if selectedSeed.model and selectedSeed.model.Parent then
                local wantText = prompt and prompt.ActionText or nil
                local fallback = nil
                for _, d in ipairs(selectedSeed.model:GetDescendants()) do
                    if d:IsA("ProximityPrompt") then
                        if wantText and d.ActionText == wantText then
                            prompt = d
                            break
                        elseif not fallback then
                            fallback = d
                        end
                    end
                end
                if not promptValid then prompt = prompt or fallback end
            end
        end)
        pcall(function() promptValid = prompt ~= nil and prompt.Parent ~= nil end)
        if promptValid then
            selectedSeed.prompt = prompt
            print("[SeedFarm] re-found prompt '" .. tostring(prompt.ActionText) .. "'")
        end
    end
    if promptValid then
        pcall(function()
            print(string.format("[SeedFarm] prompt '%s' enabled=%s hold=%s los=%s maxDist=%s",
                tostring(prompt.ActionText), tostring(prompt.Enabled),
                tostring(prompt.HoldDuration), tostring(prompt.RequiresLineOfSight),
                tostring(prompt.MaxActivationDistance)))
        end)
        pcall(function()
            -- get within activation range
            local maxDist = 10
            pcall(function() maxDist = prompt.MaxActivationDistance end)
            local promptPos = pos
            pcall(function()
                local pp = prompt.Parent
                if pp:IsA("BasePart") then promptPos = pp.Position
                elseif pp:IsA("Model") then promptPos = pp:GetPivot().Position end
            end)
            local dist = (root.Position - promptPos).Magnitude
            if dist > maxDist then
                -- move closer: teleport to within range
                local dir = (promptPos - root.Position).Unit
                root.CFrame = CFrame.new(promptPos - dir * math.max(maxDist - 1, 2) + Vector3.new(0, 3, 0))
                task.wait(0.2)
                root = getRoot()
            end
            -- force fireable state: event prompts are sometimes disabled.
            local holdTime = 0
            pcall(function() holdTime = prompt.HoldDuration or 0 end)
            pcall(function() prompt.Enabled = true end)
            pcall(function() prompt.RequiresLineOfSight = false end)
            pcall(function()
                if prompt.MaxActivationDistance < 12 then
                    prompt.MaxActivationDistance = 12
                end
            end)
            local PPS = game:GetService("ProximityPromptService")
            local function isGone()
                local g = false
                pcall(function() g = prompt.Parent == nil end)
                return g
            end
            if fireproximityprompt then
                if not firesignal then
                    print("[SeedFarm] WARNING: firesignal NOT available - hold-sim SKIPPED, Halloween/event seeds will likely IGNORE this pickup!")
                end
                print("[SeedFarm] landed - waiting 0.2s before pickup")
                task.wait(0.2)
                local function modelGone()
                    local g = false
                    pcall(function() g = selectedSeed.model == nil or selectedSeed.model.Parent == nil end)
                    return g
                end
                for attempt = 1, 10 do
                    if modelGone() or isGone() then break end
                    if carryCount(true) > carryQuickBefore then
                        print("[SeedFarm] carry confirmed while firing - stopping")
                        break
                    end
                    print("[SeedFarm] pickup '" .. prompt.ActionText .. "' attempt " .. attempt .. "/10 (hold=" .. holdTime .. "s)")
                    if firesignal then
                        pcall(function() firesignal(PPS.PromptButtonHoldBegan, prompt, LocalPlayer) end)
                        task.wait(holdTime > 0 and (holdTime + 0.4) or 0.1)
                        pcall(function() firesignal(PPS.PromptButtonHoldEnded, prompt, LocalPlayer) end)
                        task.wait(0.1)
                    end
                    if not isGone() and not modelGone() then
                        fireproximityprompt(prompt)
                        print("[SeedFarm] fired prompt '" .. prompt.ActionText .. "'")
                    end
                    task.wait(0.3)
                end
            else
                pcall(function() prompt.HoldDuration = 0 end)
            end
        end)
    elseif selectedSeed.isEventItem then
        print("[SeedFarm] event item has no prompt - touch it to collect")
        return "Teleported! Touch it to collect."
    end
    local modelGone = false
    local carried = false
    for i = 1, 16 do
        pcall(function()
            modelGone = selectedSeed.model == nil or selectedSeed.model.Parent == nil
        end)
        local now = carryCount(false)
        if now > carryBefore then carried = true end
        if lastCarrySeq > carrySeqBefore and lastCarryData then
            local uidOk = (not selectedSeed.uid) or (not lastCarryData.uid) or (lastCarryData.uid == selectedSeed.uid)
            local idOk = (not selectedSeed.seedId) or (not lastCarryData.seedId) or (lastCarryData.seedId == selectedSeed.seedId)
            if uidOk and idOk then
                carried = true
                print("[SeedFarm] carry confirmed by event (uid=" .. tostring(lastCarryData.uid) .. ")")
            end
        end
        print(string.format("[SeedFarm] confirm %d/16: carry %d->%d modelGone=%s", i, carryBefore, now, tostring(modelGone)))
        if carried then break end
        task.wait(0.25)
    end
    if carried then
        print("[SeedFarm] picked up " .. selectedSeed.name .. " (carry confirmed)")
        lastPickupHalloween = (selectedSeed.source == "halloween")
        lastPickupHalloweenAt = os.clock()
        if lastPickupHalloween then
            print("[SeedFarm] halloween pickup - delivery will fly")
        end
        return "Got " .. selectedSeed.name .. "!"
    elseif modelGone then
        -- model gone but no carry = the handler never granted it; do NOT
        -- run back (Auto Run only fires on "Got ...")
        print("[SeedFarm] WARNING: model gone but carry NOT confirmed - not collected")
        return "Gone, but not carried!"
    else
        return "Pickup failed, try again"
    end
end

-- Manual run back (uninterruptible unless STOP pressed: arrival or 90s timeout)
-- Starts moving IMMEDIATELY on button press. Wrapped in pcall so a mid-loop
-- error can never leave runningBack stuck true.
local runningBack = false
local stopRunback = false
local vacuumOn = true -- runback vacuum (v10.88): collect drops while passing
-- set by teleportToSelected when the confirmed pickup was a Halloween seed:
-- the runback for it teleports to the return point instead of walking
local lastPickupHalloween = false
local lastPickupHalloweenAt = 0

-- Safe zones are CollectionService-tagged "SafeZone" (game's world module
-- TAGS table, Oct 23 2026 dump) - main map, Halloween areas, anywhere.
-- Discovered live, never hardcoded. Nested tagged children are skipped so
-- a zone model counts once, at its pivot.
local function findSafeZones()
    local zones = {}
    local tagged = {}
    pcall(function() tagged = CollectionService:GetTagged("SafeZone") end)
    local taggedSet = {}
    for _, inst in ipairs(tagged) do taggedSet[inst] = true end
    for _, inst in ipairs(tagged) do
        local nested = false
        local anc = inst.Parent
        while anc do
            if taggedSet[anc] then nested = true break end
            anc = anc.Parent
        end
        if not nested then
            local pos = nil
            pcall(function()
                if inst:IsA("BasePart") then pos = inst.Position
                else pos = inst:GetPivot().Position end
            end)
            if pos then
                table.insert(zones, { inst = inst, name = inst.Name, pos = pos })
            end
        end
    end
    return zones
end

-- Halloween sanctuaries each carry a Part named "SanctuaryBeacon" -
-- the light column Daniel calls the light beacon (his explorer saves,
-- Oct 23 2026: a HalloweenSanctuaries model with one beacon per
-- sanctuary area, Beams named SanctuaryColumn / SanctuaryColumnCore).
-- Found live by name; cached only once a scan actually finds some, so
-- an early scan before the area streams in never poisons the cache.
local beaconCache = nil
local function findBeacons(deep)
    if beaconCache then return beaconCache end
    local out = {}
    local scope = nil
    pcall(function()
        scope = Workspace:FindFirstChild("HalloweenSanctuaries", true)
    end)
    -- without the model, only a caller that knows halloween content
    -- is streamed (a halloween delivery) pays for a workspace scan
    local searchIn = scope or (deep and Workspace or nil)
    if not searchIn then return out end
    pcall(function()
        for _, d in ipairs(searchIn:GetDescendants()) do
            if d.Name == "SanctuaryBeacon" and d:IsA("BasePart") then
                local area = "sanctuary"
                local anc = d.Parent
                while anc and anc ~= searchIn do
                    if anc:IsA("Model") then area = anc.Name end
                    anc = anc.Parent
                end
                out[#out + 1] = { inst = d, pos = d.Position, area = area }
            end
        end
    end)
    if #out > 0 then beaconCache = out end
    return out
end

-- one console listing shortly after load, so the found zones (Halloween
-- included) are visible without needing a delivery first
task.spawn(function()
    task.wait(6)
    local zones = findSafeZones()
    selfReport.safeZones = #zones
    print("[SeedFarm] safe zones found: " .. #zones)
    for i, z in ipairs(zones) do
        if i > 12 then print("[SeedFarm]   ... and " .. (#zones - 12) .. " more") break end
        print("[SeedFarm]   safe zone '" .. z.name .. "' at " .. tostring(z.pos))
    end
    local beacons = findBeacons()
    print("[SeedFarm] sanctuary beacons found: " .. #beacons)
    for _, b in ipairs(beacons) do
        print("[SeedFarm]   beacon at " .. b.area .. " - " .. tostring(b.pos))
    end
end)
local runbackLoopActive = false
local function runToSafeZone()
    if runningBack then return false end
    runningBack = true
    stopRunback = false
    local savedSpeed = nil -- WalkSpeed before the run (restored at the end)
    local ok, result = pcall(function()
        local humanoid = getHumanoid()
        local root = getRoot()
        if not (humanoid and root) then
            return false
        end
        savedSpeed = humanoid.WalkSpeed
        local deliverySeqAtStart = lastDeliverySeq
        local flyMode = false -- halloween delivery flies (v10.103)
        local cruiseY = nil
        local flyPhase = "rise"
        local lastVacuum = 0
        local vacuumFired = {}
        -- run target: pin if set, otherwise the default safe zone
        local target = pinPos or SAFE_ZONE
        local dist = (root.Position - target).Magnitude
        print(string.format("[SeedFarm] runback start: dist=%.0f", dist))
        -- Halloween delivery (v10.89 - REPLACES the v10.84 teleport
        -- delivery: Daniel verified Oct 23 2026 that teleporting to a safe
        -- zone does NOT bank the seed; delivery needs walking in). For a
        -- halloween-sourced carry with no pin set, the walk targets the
        -- NEAREST safe zone first; if standing in it does not bank within
        -- 3s, the arrival branch below retargets to the main safe zone
        -- and keeps walking. Pin set = pin stays the only target.
        local hwTargets = nil
        -- snapshot, do NOT consume the flag here (v10.106): if this
        -- attempt fails, the triggerRunback retry must still know the
        -- carry was a halloween one. The flag clears on delivery (tail).
        local hwPickup = lastPickupHalloween
            and (os.clock() - lastPickupHalloweenAt < 30)
        if hwPickup then
            if not pinPos then
                hwTargets = {}
                -- stage 1: the nearest sanctuary's light beacon
                -- (v10.104, Daniel's spec: fly to a beacon and drop
                -- into its safe zone). A beacon paired with the
                -- nearest non-main safe zone wins; beacons also cover
                -- the case where no zone is tagged nearby. Stage 2 is
                -- always the main safe zone.
                local zones = findSafeZones()
                table.sort(zones, function(a, b)
                    return (a.pos - root.Position).Magnitude
                        < (b.pos - root.Position).Magnitude
                end)
                local zoneTarget = nil
                for _, z in ipairs(zones) do
                    if (z.pos - SAFE_ZONE).Magnitude >= 15 then
                        zoneTarget = z
                        break -- nearest non-main zone only
                    end
                end
                local beacons = findBeacons(true)
                table.sort(beacons, function(a, b)
                    return (a.pos - root.Position).Magnitude
                        < (b.pos - root.Position).Magnitude
                end)
                local stage1 = nil
                if beacons[1] and (not zoneTarget
                    or (beacons[1].pos - zoneTarget.pos).Magnitude < 60) then
                    stage1 = {
                        pos = beacons[1].pos,
                        label = "beacon at " .. beacons[1].area,
                    }
                elseif zoneTarget then
                    stage1 = {
                        pos = zoneTarget.pos,
                        label = "safe zone '" .. zoneTarget.name .. "'",
                    }
                elseif beacons[1] then
                    stage1 = {
                        pos = beacons[1].pos,
                        label = "beacon at " .. beacons[1].area,
                    }
                end
                if stage1 then hwTargets[#hwTargets + 1] = stage1 end
                hwTargets[#hwTargets + 1] = {
                    pos = SAFE_ZONE, label = "main safe zone",
                }
                target = hwTargets[1].pos
                dist = (root.Position - target).Magnitude
                flyMode = true
                print("[SeedFarm] halloween delivery: flying to "
                    .. hwTargets[1].label .. " (teleport does not bank)")
            end
        end

        print(string.format("[SeedFarm] runback plan: mode=%s target=%s",
            flyMode and "FLY" or "walk",
            hwTargets and hwTargets[1].label
                or (pinPos and "pin" or "main safe zone")))
        if hwTargets then
            print(string.format(
                "[SeedFarm] runback plan detail: zones=%d beacons=%d",
                #findSafeZones(), #findBeacons()))
        end

        -- move on the very first frame: speed up, hop to unstick, go
        pcall(function() humanoid.WalkSpeed = RUN_SPEED end)
        pcall(function() humanoid.Jump = true end)
        if not flyMode then humanoid:MoveTo(target) end
        local lastPos = root.Position
        local startTime = os.clock()
        local lastLog = 0
        local TIMEOUT = hwTargets and 240 or 90
        local arriveTime = 0
        while true do
            task.wait(0.1)
            if not stillAlive() then return false end
            if stopRunback then
                print("[SeedFarm] runback STOPPED by user")
                return false
            end
            root = getRoot()
            humanoid = getHumanoid()
            if root and humanoid then
                pcall(function() humanoid.WalkSpeed = RUN_SPEED end)
                dist = (root.Position - target).Magnitude
                local elapsed = os.clock() - startTime
                if elapsed - lastLog >= 2 then
                    lastLog = elapsed
                    print(string.format("[SeedFarm] runback: dist=%.0f t=%ds", dist, math.floor(elapsed)))
                end
                -- guardian detour (graded, v10.87 - radii from the
                -- guardian-tuning dump: patrol 26-90, response up to 90,
                -- chase at least 1.07x your speed, so the old 8-stud dodge
                -- was already caught. Veer starts at 30, hardens inside 15.)
                -- flight (v10.103, halloween delivery): rise above
                -- guardian reach, cruise to above the safe zone (the
                -- light beacon), then drop in. The root's CFrame steps
                -- toward the waypoint each tick at RUN_SPEED.
                if flyMode then
                    if not cruiseY then
                        cruiseY = math.max(root.Position.Y, target.Y) + 70
                    end
                    local horiz = Vector3.new(target.X - root.Position.X,
                        0, target.Z - root.Position.Z).Magnitude
                    local wp
                    if flyPhase == "rise" then
                        wp = Vector3.new(root.Position.X, cruiseY,
                            root.Position.Z)
                        if cruiseY - root.Position.Y < 2 then
                            flyPhase = "cruise"
                        end
                    elseif flyPhase == "cruise" then
                        wp = Vector3.new(target.X, cruiseY, target.Z)
                        if horiz < 3 then flyPhase = "descend" end
                    else
                        wp = Vector3.new(target.X, target.Y + 2, target.Z)
                    end
                    local delta = wp - root.Position
                    local step = math.max(30, RUN_SPEED) * 0.1
                    local newPos = wp
                    if delta.Magnitude > step then
                        newPos = root.Position + delta.Unit * step
                    end
                    pcall(function()
                        root.CFrame = CFrame.new(newPos)
                            * (root.CFrame - root.CFrame.Position)
                        root.AssemblyLinearVelocity = Vector3.zero
                    end)
                end
                local moveTarget = target
                if not flyMode then
                local g, gDist = nearestGuardian(root.Position)
                if g and gDist < 30 then
                    local awayDir = Vector3.new(root.Position.X - g.pos.X, 0, root.Position.Z - g.pos.Z)
                    if awayDir.Magnitude < 0.1 then awayDir = Vector3.new(1, 0, 0) end
                    awayDir = awayDir.Unit
                    local toSafe = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
                    if toSafe.Magnitude > 0.1 then toSafe = toSafe.Unit else toSafe = Vector3.new(0,0,0) end
                    local awayW = gDist < 15 and 0.85 or 0.5
                    local detourDir = (awayDir * awayW + toSafe * (1 - awayW))
                    if detourDir.Magnitude < 0.1 then detourDir = awayDir end
                    moveTarget = root.Position + detourDir.Unit * 40
                    moveTarget = Vector3.new(moveTarget.X, root.Position.Y, moveTarget.Z)
                end
                end -- not flyMode: guardian detour is ground-only
                -- runback vacuum (v10.88): auto-collect collectible drops
                -- within reach while passing - no detour, no teleport.
                -- findWildSeeds is throttled to 1.5s and each prompt fires
                -- at most once per run.
                if not flyMode and vacuumOn and fireproximityprompt
                    and os.clock() - lastVacuum > 1.5 then
                    lastVacuum = os.clock()
                    pcall(function()
                        for _, s in ipairs(findWildSeeds()) do
                            if s.isCollectible and s.prompt
                                and s.prompt.Parent
                                and not vacuumFired[s.prompt] then
                                local pp = nil
                                pcall(function()
                                    local par = s.prompt.Parent
                                    if par:IsA("BasePart") then
                                        pp = par.Position
                                    else
                                        pp = par:GetPivot().Position
                                    end
                                end)
                                if pp and (pp - root.Position).Magnitude <= 10 then
                                    vacuumFired[s.prompt] = true
                                    pcall(function()
                                        fireproximityprompt(s.prompt)
                                    end)
                                    print("[SeedFarm] vacuum collected "
                                        .. (s.name or "collectible"))
                                end
                            end
                        end
                    end)
                end
                if lastDeliverySeq > deliverySeqAtStart then
                    print("[SeedFarm] DELIVERY confirmed by server - seed banked, stopping run")
                    return true
                end
                if dist <= ARRIVE_DIST then
                    if hwTargets and #hwTargets > 1 then
                        -- dwell in this zone up to 3s: does it bank?
                        local dwellT = 0
                        local banked = false
                        while dwellT < 3 do
                            task.wait(0.25)
                            dwellT += 0.25
                            if stopRunback then return false end
                            if not stillAlive() then return false end
                            if lastDeliverySeq > deliverySeqAtStart then
                                banked = true
                                break
                            end
                        end
                        if banked then
                            print("[SeedFarm] halloween delivery CONFIRMED at "
                                .. hwTargets[1].label)
                            return true
                        end
                        print("[SeedFarm] " .. hwTargets[1].label
                            .. " did not bank - walking on to "
                            .. hwTargets[2].label)
                        table.remove(hwTargets, 1)
                        target = hwTargets[1].pos
                        flyPhase = "cruise"
                        -- fall through: the loop keeps walking to the
                        -- new target (dist is recomputed at the loop top)
                    else
                        print("[SeedFarm] ARRIVED (within " .. ARRIVE_DIST .. "m) in " .. math.floor(elapsed) .. "s")
                        return true
                    end
                end
                if elapsed > TIMEOUT then
                    print("[SeedFarm] runback timeout")
                    return false
                end
                if not flyMode then
                    if (root.Position - lastPos).Magnitude < 1 then
                        humanoid.Jump = true
                    end
                    humanoid:MoveTo(moveTarget)
                end
                lastPos = root.Position
            else
                task.wait(0.5) -- wait for respawn
            end
        end
    end)
    -- restore the WalkSpeed you had before the run
    if savedSpeed then
        pcall(function()
            local h = getHumanoid()
            if h then h.WalkSpeed = savedSpeed end
        end)
    end
    if result == true then lastPickupHalloween = false end
    runningBack = false
    if not ok then
        print("[SeedFarm] runback error: " .. tostring(result))
        return false
    end
    return result
end

-- All farm logic above is unchanged; only the interface is Rayfield now.
-- NOTE: Rayfield dropdown rows can't be colored per-seed like the old GUI -
-- tier/source still show as text (👑/🧬/🎃 prefix + tier + name + weight).
local statusLabel, eggStatusLabel
local runBackBtn -- assigned at creation below; TP callback references it
local runbackArmed = false
local espEnabled = false
local updateSeedESP
local autoSelectBest = false
local espTierSet = {}
local syncWorldESP
local autoFarmOn = false
local treadmillIdleOn = false
local treadmillExitFn = nil
local autoFarmMinTier = "Any"

-- area split (v10.94, Daniel's ask): every seed belongs to exactly one
-- farm area - main (biomes 1-8 + events), speedway (SW* ids + codex
-- pads, mirroring isSpeedwaySeed), or halloween. Each area gets its own
-- tab, dropdown and scoped Full Auto Farm; only one area farms at a
-- time (turning one on switches the others off).
local function seedArea(s)
    if s.source == "halloween" then return "halloween" end
    if (s.seedId and s.seedId:match("^SW")) or s.source == "codex" then
        return "speedway"
    end
    return "main"
end
local areaFarm = {
    area = "main", -- active Auto Farm scope (last area switched on)
    auto = { main = false, speedway = false, halloween = false },
    sel = {},      -- area -> that tab's selected seed
    toggles = {},  -- area -> Rayfield toggle handle
}
local function setStatus(t)
    print("[SeedFarm] " .. tostring(t))
    if statusLabel then pcall(function() statusLabel:Set(t) end) end
end

local function setAreaAutoFarm(area, v)
    if v then
        for a, t in pairs(areaFarm.toggles) do
            if a ~= area and areaFarm.auto[a] then
                areaFarm.auto[a] = false
                if t then pcall(function() t:Set(false) end) end
            end
        end
        areaFarm.area = area
    end
    areaFarm.auto[area] = v
    autoFarmOn = (areaFarm.auto.main or areaFarm.auto.speedway
        or areaFarm.auto.halloween) and true or false
    print("[SeedFarm] auto farm [" .. area .. "] " .. (v and "ON" or "OFF")
        .. " (scope: " .. areaFarm.area .. ")")
    if v then
        setStatus("Auto Farm ON (" .. area .. ") - hunting "
            .. autoFarmMinTier)
    end
end
local function setEggStatus(t)
    print("[SeedFarm][Egg] " .. tostring(t))
    if eggStatusLabel then pcall(function() eggStatusLabel:Set(t) end) end
end

-- Grow & Pet toggle states (the automation loops at the bottom read these)
local equipOn = false

-- drop a stale saved theme name that this Rayfield build doesn't have
-- themes that actually exist in this Rayfield build
local VALID_THEMES = { Default = true, Green = true, DarkBlue = true, Amethyst = true, Bloom = true, Ocean = true, Serenity = true, AmberGlow = true, Light = true }
if getgenv().__SeedFarmTheme and not VALID_THEMES[getgenv().__SeedFarmTheme] then getgenv().__SeedFarmTheme = nil end

local Window = Rayfield:CreateWindow({
    Name = "🌱 Seed Farm v10.110",
    LoadingTitle = "Seed Farm v10.110",
    LoadingSubtitle = "Rayfield GUI",
    Theme = getgenv().__SeedFarmTheme or "Green",
    ToggleUIKeybind = Enum.KeyCode.RightControl,
    ConfigurationSaving = { Enabled = true, FolderName = "SeedFarm", FileName = "SeedFarmConfig" },
    DisableRayfieldPrompts = true,
    Discord = { Enabled = false },
    KeySystem = false,
})

local FarmTab = Window:CreateTab("🌱 Main", 4483362458)

FarmTab:CreateSection("Seeds")
local seedByText = {}
local function seedDisplayText(s)
    local prefix = ""
    if s.isTopSeed then
        prefix = "👑 TOP "
    end
    if s.mutated or s.source == "mutant" then
        prefix = prefix .. "🧬 "
    elseif s.source == "abyssal" then
        prefix = prefix .. "💜 "
    elseif s.source == "core" then
        prefix = prefix .. "🟣 "
    elseif s.source == "halloween" then
        prefix = prefix .. "🎃 "
    elseif s.source == "codex" then
        prefix = prefix .. "🔬 "
    elseif s.isSpecial then
        prefix = prefix .. "⚡ "
    elseif s.isCollectible then
        prefix = prefix .. "💎 "
    elseif s.source == "blackhole" then
        prefix = prefix .. "🕳️ "
    elseif s.source == "sweep" then
        prefix = prefix .. "🔍 "
    end
    if prefix ~= "" then
        return string.format("%s %s · %s (%dkg)", prefix, s.tierStr, s.name, math.floor(s.weight))
    end
    return string.format("%s · %s (%dkg)", s.tierStr, s.name, math.floor(s.weight))
end

local seedDropdown = FarmTab:CreateDropdown({
    Name = "Select Seed",
    Options = { "— press Refresh Seeds —" },
    CurrentOption = { "— press Refresh Seeds —" },
    MultipleOptions = false,
    Callback = function(Options)
        local sel = type(Options) == "table" and Options[1] or Options
        local s = sel and seedByText[sel]
        if s then
            local changed = (not selectedSeed)
                or selectedSeed.model ~= s.model
                or selectedSeed.uid ~= s.uid
                or selectedSeed.name ~= s.name
            selectedSeed = s
            areaFarm.sel.main = s
            if changed then
                setStatus("Selected: " .. s.name)
                print("[SeedFarm] selected " .. s.name .. " (" .. s.source .. (s.mutated and ", mutated" or "") .. ")")
            end
            if updateSeedESP then pcall(updateSeedESP) end
        end
    end,
})

local lastSeedSig = ""
local dropRebuilding = false
local prevUids = {}
local firstScan = true
local lastAutoUid = nil
local function bestSeed(seeds)
    local best = nil
    for _, s in ipairs(seeds) do
        if s.isTopSeed then return s end
        if not best or s.tier > best.tier or (s.tier == best.tier and (s.weight or 0) > (best.weight or 0)) then
            best = s
        end
    end
    return best
end
local function refreshSeedList(force)
    if dropRebuilding then return end
    dropRebuilding = true
    local allSeeds = findWildSeeds()
    local seeds = {}
    for _, s in ipairs(allSeeds) do
        if seedArea(s) == "main" then seeds[#seeds + 1] = s end
    end
    if force then print("[SeedFarm] found " .. #seeds .. " main seeds") end
    local opts, map = {}, {}
    for _, s in ipairs(seeds) do
        local t = seedDisplayText(s)
        table.insert(opts, t)
        map[t] = s
    end
    if #opts == 0 then
        opts = { "— no seeds found —" }
    end
    local sig = table.concat(opts, "|")
    if force or sig ~= lastSeedSig then
        lastSeedSig = sig
        seedByText = map
        pcall(function() seedDropdown:Refresh(opts) end)
        if #seeds == 0 then setStatus("No seeds found!") end
    end
    local curUids = {}
    for _, s in ipairs(allSeeds) do
        if s.uid then curUids[s.uid] = true end
        local isRare = s.isTopSeed or s.mutated or s.tier >= 4 or s.source == "halloween"
        if not firstScan and isRare and s.uid and not prevUids[s.uid] then
            print("[SeedFarm] RARE SPAWN: " .. seedDisplayText(s))
        end
    end
    prevUids = curUids
    firstScan = false
    if autoSelectBest then
        local best = bestSeed(seeds)
        if best then
            selectedSeed = best
            if best.uid ~= lastAutoUid then
                lastAutoUid = best.uid
                print("[SeedFarm] auto-selected best: " .. best.name)
            end
            pcall(function() seedDropdown:Set({ seedDisplayText(best) }) end)
            if updateSeedESP then pcall(updateSeedESP) end
        end
    end
    if syncWorldESP then pcall(syncWorldESP, allSeeds) end
    dropRebuilding = false
end

FarmTab:CreateButton({
    Name = "🔄 Refresh Seeds",
    Callback = function() refreshSeedList(true) end,
})

-- background refresh: only pushes to the dropdown when the list changed,
-- so it won't yank the list around while you're scrolling it
task.spawn(function()
    while stillAlive() do
        task.wait(1.5)
        pcall(function() refreshSeedList(false) end)
        pcall(function() refreshSpeedwayList(false) end)
        pcall(function() refreshImpList(false) end)
        pcall(function() refreshHalloweenList(false) end)
    end
end)

statusLabel = FarmTab:CreateLabel("Pick a seed to start")
local guardianWarnLabel = FarmTab:CreateLabel("")

-- session stats (v10.88): deliveries counted in the
-- InventorySeedCarryStateChanged handler; label shows banked total,
-- per-tier split, and the game's own LightningBest attribute
local sessionStats = { total = 0, byTier = {} }
sessionStats.label = FarmTab:CreateLabel("🏆 Banked: 0")
sessionStats.update = function()
    local parts = { "🏆 Banked: " .. sessionStats.total }
    for _, t in ipairs({ "T4Guardian", "T4", "T3", "T2", "T1" }) do
        local n = sessionStats.byTier[t]
        if n and n > 0 then
            parts[#parts + 1] = t .. " ×" .. n
        end
    end
    local best = nil
    pcall(function()
        best = Players.LocalPlayer:GetAttribute("LightningBest")
    end)
    if type(best) == "number" and best > 0 then
        parts[#parts + 1] = "⚡ Best combo " .. best
    end
    pcall(function()
        sessionStats.label:Set(table.concat(parts, " · "))
    end)
end

-- carry guardian warning (v10.87): while a carry is outstanding (carry
-- event seen, delivery not yet), surface the nearest guardian's distance
-- on its own label - far band <60m, danger band <25m (response radius in
-- guardian-tuning runs to 90m). Prints only on band changes.
task.spawn(function()
    local lastBand = ""
    while true do
        task.wait(0.5)
        local band = ""
        pcall(function()
            if lastCarrySeq > lastDeliverySeq then
                local root = getRoot()
                if root then
                    local g, gDist = nearestGuardian(root.Position)
                    if g and gDist < 25 then
                        band = "🔴 GUARDIAN ON YOU - " .. math.floor(gDist) .. "m"
                    elseif g and gDist < 60 then
                        band = "⚠️ Guardian near - " .. math.floor(gDist) .. "m"
                    end
                end
            end
        end)
        if band ~= lastBand then
            lastBand = band
            pcall(function() guardianWarnLabel:Set(band) end)
            if band ~= "" then print("[SeedFarm] " .. band) end
        end
    end
end)

local collectedCount = 0
local collectedLabel = FarmTab:CreateLabel("Seeds collected: 0")
local function noteCollected()
    collectedCount += 1
    pcall(function() collectedLabel:Set("Seeds collected: " .. collectedCount) end)
    print("[SeedFarm] session collected: " .. collectedCount)
end

FarmTab:CreateSection("Actions")
-- shared teleport flow (TP TO SEED and TP TO BEST both end here)
local function doTeleport()
    runbackArmed = false -- a fresh TP cancels any pending arm
    manualTpPending = true -- this teleport's carry event triggers the runback
    setStatus("Teleporting...")
    local msg = teleportToSelected()
    manualTpPending = false
    setStatus(msg)
    if msg and msg:sub(1, 3) == "Got" then
        noteCollected()
        if autoRunEnabled and not runningBack and not runbackLoopActive then
            runbackArmed = true
            setStatus("Carried! Press RUN BACK when you're ready.")
            pcall(function() runBackBtn:Set("🏃 RUN BACK (READY!)") end)
            print("[SeedFarm] auto-run ARMED - waiting for RUN BACK press")
        end
    end
end

FarmTab:CreateButton({
    Name = "📍 TP TO SEED",
    Callback = function()
        if areaFarm.sel.main then selectedSeed = areaFarm.sel.main end
        doTeleport()
    end,
})

FarmTab:CreateButton({
    Name = "👑 TP TO BEST",
    Callback = function()
        local seeds = findWildSeeds()
        local best = bestSeed(seeds)
        if not best then
            setStatus("No seeds found!")
            return
        end
        selectedSeed = best
        print("[SeedFarm] TP TO BEST -> " .. seedDisplayText(best))
        if updateSeedESP then pcall(updateSeedESP) end
        doTeleport()
    end,
})

--------------------------------------------------------------------------------
-- SPEEDWAY TAB (speedway seeds as they spawn: SW* IDs + codex seed pads)
--------------------------------------------------------------------------------
local SpeedwayTab = Window:CreateTab("🏁 Speedway", 4483362458)

do -- Halloween tab (v10.94): halloween-only seeds + scoped auto farm
    local HalloweenTab = Window:CreateTab("👻 Halloween", 4483362458)
    areaFarm.halloweenTab = HalloweenTab -- imp controls attach below the halloween seeds
    HalloweenTab:CreateSection("Halloween Seeds")
    local halloweenByText = {}
    local halloweenDropdown = HalloweenTab:CreateDropdown({
        Name = "Select Halloween Seed",
        Options = { "— press Refresh —" },
        CurrentOption = { "— press Refresh —" },
        MultipleOptions = false,
        Callback = function(Options)
            local sel = type(Options) == "table" and Options[1] or Options
            local s = sel and halloweenByText[sel]
            if s then
                selectedSeed = s
                areaFarm.sel.halloween = s
                setStatus("Selected: " .. s.name)
                print("[SeedFarm] selected halloween seed " .. s.name)
                if updateSeedESP then pcall(updateSeedESP) end
            end
        end,
    })
    local lastHalloweenSig = ""
    local halloweenRebuilding = false
    function refreshHalloweenList(force)
        if halloweenRebuilding then return end
        halloweenRebuilding = true
        local seeds = {}
        for _, s in ipairs(findWildSeeds()) do
            if seedArea(s) == "halloween" then
                seeds[#seeds + 1] = s
            end
        end
        if force then
            print("[SeedFarm] found " .. #seeds .. " halloween seeds")
        end
        local opts, map = {}, {}
        for _, s in ipairs(seeds) do
            local t = seedDisplayText(s)
            table.insert(opts, t)
            map[t] = s
        end
        if #opts == 0 then opts = { "— no halloween seeds —" } end
        local sig = table.concat(opts, "|")
        if force or sig ~= lastHalloweenSig then
            lastHalloweenSig = sig
            halloweenByText = map
            pcall(function() halloweenDropdown:Refresh(opts) end)
        end
        halloweenRebuilding = false
    end
    HalloweenTab:CreateButton({
        Name = "🔄 Refresh Halloween Seeds",
        Callback = function() refreshHalloweenList(true) end,
    })
    HalloweenTab:CreateButton({
        Name = "📍 TP TO SEED",
        Callback = function()
            if areaFarm.sel.halloween then
                selectedSeed = areaFarm.sel.halloween
            end
            doTeleport()
        end,
    })
    HalloweenTab:CreateButton({
        Name = "👑 TP TO BEST",
        Callback = function()
            local hw = {}
            for _, s in ipairs(findWildSeeds()) do
                if seedArea(s) == "halloween" then hw[#hw + 1] = s end
            end
            local best = bestSeed(hw)
            if not best then
                setStatus("No halloween seeds found!")
                return
            end
            selectedSeed = best
            areaFarm.sel.halloween = best
            print("[SeedFarm] TP TO BEST HALLOWEEN -> "
                .. seedDisplayText(best))
            if updateSeedESP then pcall(updateSeedESP) end
            doTeleport()
        end,
    })
    HalloweenTab:CreateButton({
        Name = "🏃 RUN BACK",
        Callback = function() triggerRunback() end,
    })
    HalloweenTab:CreateButton({
        Name = "⏹ STOP",
        Callback = function()
            if runningBack or runbackLoopActive then
                stopRunback = true
                setStatus("Stopping...")
            end
        end,
    })
    HalloweenTab:CreateLabel("Halloween seeds appear here as they spawn. Delivery walks to the nearest safe zone.")
    HalloweenTab:CreateSection("Auto Farm")
    areaFarm.toggles.halloween = HalloweenTab:CreateToggle({
        Name = "Full Auto Farm",
        CurrentValue = false,
        Callback = function(v) setAreaAutoFarm("halloween", v) end,
    })
end
SpeedwayTab:CreateSection("Speedway Seeds")

local function isSpeedwaySeed(s)
    return (s.seedId and s.seedId:match("^SW")) or s.source == "codex"
end

local function speedwaySeeds()
    local out = {}
    for _, s in ipairs(findWildSeeds()) do
        if isSpeedwaySeed(s) then
            table.insert(out, s)
        end
    end
    return out
end

local speedwayByText = {}
local speedwayDropdown = SpeedwayTab:CreateDropdown({
    Name = "Select Speedway Seed",
    Options = { "— press Refresh —" },
    CurrentOption = { "— press Refresh —" },
    MultipleOptions = false,
    Callback = function(Options)
        local sel = type(Options) == "table" and Options[1] or Options
        local s = sel and speedwayByText[sel]
        if s then
            local changed = (not selectedSeed)
                or selectedSeed.model ~= s.model
                or selectedSeed.uid ~= s.uid
                or selectedSeed.name ~= s.name
            selectedSeed = s
            areaFarm.sel.speedway = s
            if changed then
                setStatus("Selected: " .. s.name)
                print("[SeedFarm] selected speedway seed " .. s.name .. " (" .. s.source .. ")")
            end
            if updateSeedESP then pcall(updateSeedESP) end
        end
    end,
})

local lastSpeedwaySig = ""
local speedwayRebuilding = false
-- global: the background refresh loop calls this (defined before it textually)
function refreshSpeedwayList(force)
    if speedwayRebuilding then return end
    speedwayRebuilding = true
    local seeds = speedwaySeeds()
    if force then
        print("[SeedFarm] found " .. #seeds .. " speedway seeds")
    end
    local opts, map = {}, {}
    for _, s in ipairs(seeds) do
        local t = seedDisplayText(s)
        table.insert(opts, t)
        map[t] = s
    end
    if #opts == 0 then
        opts = { "— no speedway seeds —" }
    end
    local sig = table.concat(opts, "|")
    if force or sig ~= lastSpeedwaySig then
        lastSpeedwaySig = sig
        speedwayByText = map
        pcall(function() speedwayDropdown:Refresh(opts) end)
    end
    speedwayRebuilding = false
end

SpeedwayTab:CreateButton({
    Name = "🔄 Refresh Speedway Seeds",
    Callback = function() refreshSpeedwayList(true) end,
})

SpeedwayTab:CreateButton({
    Name = "📍 TP TO SPEEDWAY SEED",
    Callback = function()
        if areaFarm.sel.speedway then
            selectedSeed = areaFarm.sel.speedway
        end
        doTeleport()
    end,
})

SpeedwayTab:CreateButton({
    Name = "👑 TP TO BEST SPEEDWAY",
    Callback = function()
        local seeds = speedwaySeeds()
        local best = bestSeed(seeds)
        if not best then
            setStatus("No speedway seeds found!")
            return
        end
        selectedSeed = best
        print("[SeedFarm] TP TO BEST SPEEDWAY -> " .. seedDisplayText(best))
        if updateSeedESP then pcall(updateSeedESP) end
        doTeleport()
    end,
})

SpeedwayTab:CreateLabel("Speedway seeds appear here as they spawn.")

SpeedwayTab:CreateSection("Auto Farm")
areaFarm.toggles.speedway = SpeedwayTab:CreateToggle({
    Name = "Full Auto Farm",
    CurrentValue = false,
    Callback = function(v) setAreaAutoFarm("speedway", v) end,
})




SpeedwayTab:CreateSection("⚡ Lightning Chamber")

-- Lightning chamber (from the game's lightning-chamber-config, Oct 22 2026):
-- a 3x3 pad grid in its own room. Pad 5 IS the chamber center, and the
-- module's own lightningPadPosition(i) gives exact world positions, so no
-- coordinates are hardcoded here. Grid (viewed from the south door):
--   7 8 9   (north / board wall)
--   4 5 6
--   1 2 3   (south / door side)
local lightningCfgCache = false -- false = not tried yet
local lightningCfgSource = "unresolved"
local function getLightningCfg()
    if lightningCfgCache ~= false then return lightningCfgCache end
    local ok, mod = pcall(function()
        local rs = game:GetService("ReplicatedStorage")
        local common = rs:FindFirstChild("Common")
        local cfgFolder = common and common:FindFirstChild("config")
        local m = cfgFolder and cfgFolder:FindFirstChild("lightning-chamber-config")
        if not m then return nil end
        return require(m)
    end)
    lightningCfgCache = (ok and mod) or nil
    if lightningCfgCache then lightningCfgSource = "game config" end
    if not lightningCfgCache then
        -- fallback from the map-config dump (Oct 23 2026): chamber center
        -- (186, 0, 47) = CenterX 186, SAFE_ZONE_MAX_Z 0 + WallThickness 10
        -- + HalfSize 36 + 1; pads on the same 3x3 grid, 13-stud spacing
        local center = Vector3.new(186, 0, 47)
        lightningCfgCache = {
            lightningPadPosition = function(i)
                local n = math.clamp(math.floor(i), 1, 9) - 1
                return center + Vector3.new((n % 3 - 1) * 13, 0,
                    (math.floor(n / 3) - 1) * 13)
            end,
            lightningChamberEnabled = function() return true end,
        }
        print("[SeedFarm] lightning-chamber-config not resolved - "
            .. "using map-config fallback positions")
        lightningCfgSource = "map-config fallback positions"
    end
    selfReport.lightning = lightningCfgSource
    return lightningCfgCache
end

local function teleportToLightningPad(pad)
    local cfg = getLightningCfg()
    if not cfg or not cfg.lightningPadPosition then
        setStatus("Lightning config not found!")
        print("[SeedFarm] lightning teleport: lightning-chamber-config not resolved")
        return
    end
    if cfg.lightningChamberEnabled then
        local okE, enabled = pcall(function() return cfg.lightningChamberEnabled() end)
        if okE and enabled == false then
            setStatus("Lightning Chamber is disabled here!")
            print("[SeedFarm] lightning teleport: chamber disabled on this server")
            return
        end
    end
    local ok, pos = pcall(function() return cfg.lightningPadPosition(pad) end)
    if not ok or typeof(pos) ~= "Vector3" then
        setStatus("Lightning position failed!")
        print("[SeedFarm] lightning teleport: pad position failed for pad " .. pad)
        return
    end
    local root = getRoot()
    if not root then setStatus("No character!") return end
    root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
    if pad == 5 then
        setStatus("⚡ Lightning Chamber")
    else
        setStatus("⚡ Lightning Pad " .. pad)
    end
    print(string.format("[SeedFarm] teleported to lightning pad %d at %s", pad, tostring(pos)))
end

-- AUTO LIGHTNING: the game broadcasts every strike on an instance named
-- "LightningChamberState" (attributes per lightning-chamber-config):
-- StrikeId, Pad (target), Pad2, WarnAt, StrikeAt, Golden, Surge. The bot
-- teleports to the announced pad the moment a new StrikeId appears (the
-- warning window is ~2.5s) and stays for the strike. Pad hops are 13
-- studs, which also clears the game's 4-stud activity check; a repeated
-- pad gets a quick out-and-back shuffle instead. The per-strike console
-- line logs Pad/Pad2/Golden and the combo before->after, so one run
-- proves which pad is real if Pad2 turns out to matter.
local lightningAuto = false
local lightningGen = 0

local function findLightningState()
    for _, rootInst in ipairs({ workspace, game:GetService("ReplicatedStorage") }) do
        local hit = rootInst:FindFirstChild("LightningChamberState", true)
        if hit then return hit end
    end
    return nil
end

local function playerCombo()
    local ok, v = pcall(function()
        return Players.LocalPlayer:GetAttribute("LightningCombo")
    end)
    if ok and type(v) == "number" then return v end
    return nil
end

local function autoLightningLoop(gen)
    local cfg = getLightningCfg()
    if not cfg or not cfg.lightningPadPosition then
        setStatus("Lightning config not found!")
        print("[SeedFarm] auto lightning: config not resolved")
        lightningAuto = false
        return
    end
    teleportToLightningPad(5) -- enter at center so the chamber starts
    local state = findLightningState()
    local lastSid = nil
    local lastPad = nil
    while lightningAuto and gen == lightningGen do
        if not state or not state.Parent then
            state = findLightningState()
            if state then
                print("[SeedFarm] auto lightning: state instance found ("
                    .. state:GetFullName() .. ")")
            end
        end
        if state then
            local sid = state:GetAttribute("StrikeId")
            local pad = state:GetAttribute("Pad")
            if sid ~= nil and sid ~= lastSid
                and type(pad) == "number" and pad >= 1 and pad <= 9 then
                lastSid = sid
                local pad2 = state:GetAttribute("Pad2")
                local golden = state:GetAttribute("Golden")
                local surge = state:GetAttribute("Surge")
                local strikeAt = state:GetAttribute("StrikeAt")
                local comboBefore = playerCombo()
                local ok, pos = pcall(function()
                    return cfg.lightningPadPosition(pad)
                end)
                if ok and typeof(pos) == "Vector3" then
                    local root = getRoot()
                    if root then
                        if pad == lastPad then
                            -- same pad twice: shuffle out and back so
                            -- the activity check still sees real movement
                            root.CFrame = CFrame.new(pos
                                + Vector3.new(5.5, 3, 0))
                            task.wait(0.35)
                            if not (lightningAuto and gen == lightningGen) then
                                return
                            end
                            root = getRoot()
                            if root then
                                root.CFrame = CFrame.new(pos
                                    + Vector3.new(0, 3, 0))
                            end
                        else
                            root.CFrame = CFrame.new(pos
                                + Vector3.new(0, 3, 0))
                        end
                    end
                    lastPad = pad
                    setStatus("⚡ Pad " .. pad
                        .. (golden and " 🌟 GOLDEN" or "")
                        .. " - strike #" .. tostring(sid))
                    local delayS = 1
                    if type(strikeAt) == "number" then
                        local okT, now = pcall(function()
                            return workspace:GetServerTimeNow()
                        end)
                        if okT and type(now) == "number" then
                            delayS = math.clamp(strikeAt - now + 0.6,
                                0.3, 5)
                        end
                    end
                    local mySid = sid
                    task.delay(delayS, function()
                        print(string.format(
                            "[SeedFarm] ⚡ strike #%s pad %s (pad2=%s "
                            .. "golden=%s surge=%s) combo %s -> %s",
                            tostring(mySid), tostring(pad),
                            tostring(pad2), tostring(golden),
                            tostring(surge), tostring(comboBefore),
                            tostring(playerCombo())))
                    end)
                end
            end
        end
        task.wait(0.15)
    end
end

local autoLightningToggle = nil
local function applyAutoLightning(v)
    lightningAuto = v
    lightningGen = lightningGen + 1
    if v then
        print("[SeedFarm] auto lightning ON - watching "
            .. "LightningChamberState")
        task.spawn(function() autoLightningLoop(lightningGen) end)
    else
        print("[SeedFarm] auto lightning OFF")
    end
end

autoLightningToggle = SpeedwayTab:CreateToggle({
    Name = "⚡ AUTO LIGHTNING",
    CurrentValue = false,
    Flag = "AutoLightning",
    Callback = function(value) applyAutoLightning(value) end,
})


--------------------------------------------------------------------------------
-- IMP FARM TAB (pumpkin imp farmer v1.1, merged in)
-- Imp = Configuration "Imp" in ReplicatedStorage.HalloweenPumpkinImp.
-- Position P + V*dt, hits via shovel Activate() (server cooldown 1.25s).
--------------------------------------------------------------------------------
areaFarm.halloweenTab:CreateSection("🎃 Imp Farm")

local ImpConfig = {
    ImpFolderName = "HalloweenPumpkinImp",
    ImpConfigName = "Imp",
    SwingDelay = 1.3,       -- server shovel cooldown is 1.25
    TeleportOffset = 6,
    MaxDistance = 2000,
    BagGrabDelay = 1.0,
}

local impLoopActive = false
local impAutoEnabled = false
local impDefeated = 0
local impBags = 0
local selectedImp = nil

local impFolder = nil
local function resolveImpFolder()
    if impFolder and impFolder.Parent then return impFolder end
    local rs = game:GetService("ReplicatedStorage")
    impFolder = rs:FindFirstChild(ImpConfig.ImpFolderName)
        or Workspace:FindFirstChild(ImpConfig.ImpFolderName)
    return impFolder
end

local function getImps()
    local out = {}
    local folder = resolveImpFolder()
    if not folder then return out end
    for _, ch in ipairs(folder:GetChildren()) do
        if ch.Name == ImpConfig.ImpConfigName and ch:IsA("Configuration") then
            if ch:GetAttribute("State") ~= "Despawned" then
                table.insert(out, ch)
            end
        end
    end
    return out
end

local function impState(cfg) return cfg:GetAttribute("State") or "Idle" end

local function impHealth(cfg)
    local h = cfg:GetAttribute("Health")
    local m = cfg:GetAttribute("MaxHealth")
    if type(h) == "number" and type(m) == "number" and m > 0 then return h, m end
    return nil, nil
end

local function impPosition(cfg)
    local p = cfg:GetAttribute("P")
    if typeof(p) ~= "Vector3" then return nil end
    local v = cfg:GetAttribute("V")
    local t = cfg:GetAttribute("T")
    local now = Workspace:GetServerTimeNow()
    if typeof(v) == "Vector3" and type(t) == "number" and type(now) == "number" then
        return p + v * math.clamp(now - t, 0, 0.25)
    end
    return p
end

local ImpHittable = { Aggro = true, Running = true, PortalCasting = true, PortalCancelled = true }

local function getNearestImp()
    local root = getRoot()
    if not root then return nil end
    local rootPos = root.Position
    local best, bestDist = nil, ImpConfig.MaxDistance
    for _, cfg in ipairs(getImps()) do
        local pos = impPosition(cfg)
        if pos then
            local d = (rootPos - pos).Magnitude
            if d < bestDist then best, bestDist = cfg, d end
        end
    end
    return best
end

local function getImpShovel()
    local character = LocalPlayer.Character
    if character then
        for _, tool in ipairs(character:GetChildren()) do
            if tool:IsA("Tool") and string.find(string.lower(tool.Name), "shovel", 1, true) then
                return tool
            end
        end
    end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack and character then
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") and string.find(string.lower(tool.Name), "shovel", 1, true) then
                tool.Parent = character
                return tool
            end
        end
    end
    return nil
end

local function getDroppedBags()
    local out = {}
    local ok, tagged = pcall(function() return CollectionService:GetTagged("GoldenCandyBag") end)
    if not ok or not tagged then return out end
    for _, m in ipairs(tagged) do
        if m:IsA("Model") and m.Parent then
            local state = m:GetAttribute("GoldenBagState") or "Dropped"
            local carrier = m:GetAttribute("GoldenBagCarrierUserId") or 0
            if state == "Dropped" and carrier == 0 then table.insert(out, m) end
        end
    end
    return out
end

local function grabImpBag(bag)
    local root = getRoot()
    if not root then return false end
    local ok, pivot = pcall(function() return bag:GetPivot() end)
    if not ok or not pivot then return false end
    root.CFrame = CFrame.new(pivot.Position + Vector3.new(0, 3, 0))
    task.wait(0.3)
    for _, d in ipairs(bag:GetDescendants()) do
        if d:IsA("ProximityPrompt") then pcall(function() fireproximityprompt(d) end) end
    end
    task.wait(0.5)
    local state = bag:GetAttribute("GoldenBagState")
    local carrier = bag:GetAttribute("GoldenBagCarrierUserId") or 0
    return (not bag.Parent) or state == "Carried" or carrier ~= 0
end

local impStatusLabel = areaFarm.halloweenTab:CreateLabel("Idle")
local impCountLabel = areaFarm.halloweenTab:CreateLabel("🎃 0   🍬 0")
local function setImpStatus(text)
    pcall(function()
        impStatusLabel:Set(text)
        impCountLabel:Set(string.format("🎃 %d   🍬 %d", impDefeated, impBags))
    end)
    print("[SeedFarm][Imp] " .. text)
end

local function impDisplayText(cfg)
    local root = getRoot()
    local rootPos = root and root.Position
    local pos = impPosition(cfg)
    local dist = (rootPos and pos) and (rootPos - pos).Magnitude or nil
    local state = impState(cfg)
    local h, m = impHealth(cfg)
    local txt = "🎃 " .. state
    if h and m then txt = txt .. string.format(" %d/%d", math.floor(h), math.floor(m)) end
    if state == "PortalCasting" then
        local now = Workspace:GetServerTimeNow()
        local endsAt = cfg:GetAttribute("CastEndsAt")
        if type(now) == "number" and type(endsAt) == "number" then
            txt = txt .. string.format(" ⏳%ds", math.max(0, math.floor(endsAt - now)))
        end
    end
    if dist then txt = txt .. string.format(" [%dm]", math.floor(dist)) end
    return txt
end

local impByText = {}
local impDropdown = areaFarm.halloweenTab:CreateDropdown({
    Name = "Select Imp",
    Options = { "— press Refresh —" },
    CurrentOption = { "— press Refresh —" },
    MultipleOptions = false,
    Callback = function(Options)
        local sel = type(Options) == "table" and Options[1] or Options
        selectedImp = sel and impByText[sel]
        if selectedImp then setImpStatus("Selected: " .. impState(selectedImp)) end
    end,
})

local lastImpSig = ""
local impRebuilding = false
-- global: the background refresh loop calls this
function refreshImpList(force)
    if impRebuilding then return end
    impRebuilding = true
    local imps = getImps()
    local opts, map = {}, {}
    for _, cfg in ipairs(imps) do
        local t = impDisplayText(cfg)
        table.insert(opts, t)
        map[t] = cfg
    end
    if #opts == 0 then opts = { "— no imps —" } end
    local sig = table.concat(opts, "|")
    if force or sig ~= lastImpSig then
        lastImpSig = sig
        impByText = map
        pcall(function() impDropdown:Refresh(opts) end)
    end
    -- bag count on the grab button
    local bags = getDroppedBags()
    pcall(function()
        impBagBtn:Set(#bags > 0 and ("🍬 GRAB BAG (" .. #bags .. ")") or "🍬 GRAB BAG")
    end)
    impRebuilding = false
end

areaFarm.halloweenTab:CreateButton({
    Name = "🔄 Refresh Imps",
    Callback = function() refreshImpList(true) end,
})

areaFarm.halloweenTab:CreateSection("Actions")

local function farmImpBody(cfg)
    local shovel = getImpShovel()
    if not shovel then
        setImpStatus("No shovel found!")
        warn("[SeedFarm][Imp] no shovel tool in backpack/character")
        return
    end
    print("[SeedFarm][Imp] using shovel: " .. shovel.Name)
    setImpStatus("Fighting imp...")
    local startTime = os.clock()
    local lastSwing = 0
    local lastHitSeq = cfg:GetAttribute("HitSeq") or 0
    while cfg and cfg.Parent do
        local state = impState(cfg)
        if state == "Defeated" then
            impDefeated = impDefeated + 1
            setImpStatus("Imp defeated!")
            print("[SeedFarm][Imp] imp defeated")
            break
        end
        if state == "Escaping" or state == "Despawned" then
            setImpStatus("Imp " .. state)
            break
        end
        local character = LocalPlayer.Character
        local root = getRoot()
        if not root then break end
        if shovel.Parent ~= character and character then
            shovel.Parent = character
        end
        local pos = impPosition(cfg)
        if pos then
            root.CFrame = CFrame.lookAt(pos + Vector3.new(0, 0, ImpConfig.TeleportOffset), pos)
        end
        if ImpHittable[state] and (os.clock() - lastSwing) >= ImpConfig.SwingDelay then
            lastSwing = os.clock()
            pcall(function() shovel:Activate() end)
        end
        local seq = cfg:GetAttribute("HitSeq") or 0
        if seq > lastHitSeq then
            lastHitSeq = seq
            local h, m = impHealth(cfg)
            print(string.format("[SeedFarm][Imp] hit %d confirmed%s",
                seq, (h and m) and string.format(" (%d/%d HP)", math.floor(h), math.floor(m)) or ""))
        end
        if os.clock() - startTime > 300 then
            warn("[SeedFarm][Imp] cycle timed out")
            break
        end
        task.wait(0.1)
    end
    task.wait(ImpConfig.BagGrabDelay)
    local bagGrabbed = false
    local bags = getDroppedBags()
    if #bags > 0 then
        setImpStatus("Grabbing bag...")
        if grabImpBag(bags[1]) then
            impBags = impBags + 1
            bagGrabbed = true
            setImpStatus("Bag grabbed!")
            print("[SeedFarm][Imp] golden bag secured")
            -- back to the safe zone with the loot
            setImpStatus("Running back...")
            pcall(function() triggerRunback() end)
        end
    end
    return bagGrabbed
end

local impWaitingForNext = false
local lastFoughtImp = nil
local suppressImpToggleCb = false
local impAutoToggle = nil
local function setImpAutoUI(v)
    suppressImpToggleCb = true
    pcall(function() impAutoToggle:Set(v) end)
    suppressImpToggleCb = false
end

function runImpCycle(cfg, fromAuto)
    if impLoopActive then return end
    if not cfg or not cfg.Parent then return end
    print("[SeedFarm][Imp] cycle start: " .. impState(cfg))
    impLoopActive = true
    local bagGrabbed = false
    local ok, err = xpcall(function() bagGrabbed = farmImpBody(cfg) end,
        function(e) return debug.traceback(tostring(e)) end)
    if not ok then warn("[SeedFarm][Imp] cycle error: " .. tostring(err)) end
    impLoopActive = false
    if fromAuto then
        -- one imp per engagement: toggle off until a NEW imp shows up
        impAutoEnabled = false
        impWaitingForNext = true
        lastFoughtImp = cfg
        setImpAutoUI(false)
        setImpStatus(bagGrabbed and "Bag secured - waiting for next imp"
            or "Cycle done - waiting for next imp")
        print("[SeedFarm][Imp] standing down until a new imp spawns")
    elseif not impAutoEnabled then
        setImpStatus("Idle")
    end
    pcall(function() refreshImpList(true) end)
end

areaFarm.halloweenTab:CreateButton({
    Name = "🎯 FIGHT SELECTED",
    Callback = function()
        if selectedImp and selectedImp.Parent then
            task.spawn(function() runImpCycle(selectedImp, false) end)
        else
            setImpStatus("Select an imp first!")
        end
    end,
})

impAutoToggle = areaFarm.halloweenTab:CreateToggle({
    Name = "🔁 Imp Auto-Farm",
    CurrentValue = false,
    Callback = function(v)
        if suppressImpToggleCb then return end
        impAutoEnabled = v
        impWaitingForNext = false -- user took over; cancel any wait
        setImpStatus(v and "Auto-farm ON" or "Auto-farm OFF")
        print("[SeedFarm][Imp] auto-farm " .. (v and "enabled" or "disabled"))
    end,
})

impBagBtn = areaFarm.halloweenTab:CreateButton({
    Name = "🍬 GRAB BAG",
    Callback = function()
        if impLoopActive then return end
        task.spawn(function()
            local bags = getDroppedBags()
            if #bags == 0 then setImpStatus("No bags to grab") return end
            setImpStatus("Grabbing bag...")
            if grabImpBag(bags[1]) then
                impBags = impBags + 1
                setImpStatus("Bag grabbed!")
            else
                setImpStatus("Bag grab failed")
            end
        end)
    end,
})

-- imp auto-farm loop
task.spawn(function()
    while stillAlive() do
        task.wait(2)
        if impWaitingForNext then
            -- a new imp (different instance than the one just fought) re-arms auto
            local fresh = false
            for _, c in ipairs(getImps()) do
                if c ~= lastFoughtImp then fresh = true break end
            end
            if fresh then
                impWaitingForNext = false
                lastFoughtImp = nil
                impAutoEnabled = true
                setImpAutoUI(true)
                setImpStatus("New imp! Auto-farm ON")
                print("[SeedFarm][Imp] new imp detected - re-engaging")
            end
        elseif impAutoEnabled and not impLoopActive then
            local imp = getNearestImp()
            if imp then
                setImpStatus("Auto: " .. impState(imp))
                runImpCycle(imp, true)
            else
                setImpStatus("Auto: waiting for imp")
            end
        end
        pcall(function() refreshImpList(false) end)
    end
end)

-- refresh on imp/bag add/remove
task.spawn(function()
    local folder = resolveImpFolder()
    if folder then
        folder.ChildAdded:Connect(function() pcall(function() refreshImpList(true) end) end)
        folder.ChildRemoved:Connect(function() pcall(function() refreshImpList(true) end) end)
    end
    pcall(function()
        CollectionService:GetInstanceAddedSignal("GoldenCandyBag"):Connect(function() pcall(function() refreshImpList(true) end) end)
        CollectionService:GetInstanceRemovedSignal("GoldenCandyBag"):Connect(function() pcall(function() refreshImpList(true) end) end)
    end)
end)
pcall(function() refreshImpList(true) end)

runBackBtn = FarmTab:CreateButton({
    Name = "🏃 RUN BACK",
    Callback = function()
        if runbackArmed then
            runbackArmed = false
            print("[SeedFarm] auto-run released by RUN BACK press")
        end
        triggerRunback()
    end,
})

-- separate STOP button (does not repurpose RUN BACK)
FarmTab:CreateButton({
    Name = "⏹ STOP",
    Callback = function()
        if runningBack or runbackLoopActive then
            stopRunback = true
            setStatus("Stopping...")
        end
    end,
})

-- Black Hole event runner (v10.101, was the TP button): walk to the
-- live event seed on foot, re-aiming at its position every 0.4s; on
-- arrival, fire its pickup prompt (no E key needed). STOP cancels.
FarmTab:CreateButton({
    Name = "🕳️ RUN TO BLACK HOLE",
    Callback = function()
        if areaFarm.bhRunning then return end
        local inst = nil
        pcall(function()
            for _, t in ipairs(CollectionService:GetTagged("BlackHoleSeed")) do
                inst = t
                break
            end
        end)
        if not inst then
            setStatus("No Black Hole seed live right now")
            print("[SeedFarm] black hole run: no live event seed")
            return
        end
        local carrier = inst:GetAttribute("BlackHoleCarrierUserId")
        if carrier == LocalPlayer.UserId then
            setStatus("🕳️ You're carrying it - deliver to your safe zone!")
            return
        end
        local who = bhPlayerName(carrier)
        print("[SeedFarm] black hole run: seed is "
            .. (who and ("carried by " .. who) or "FREE"))
        areaFarm.bhRunning = true
        stopRunback = false
        setStatus("🕳️ Running to Black Hole seed... (STOP cancels)")
        task.spawn(function()
            local started = os.clock()
            while areaFarm.bhRunning do
                if stopRunback then
                    setStatus("🕳️ Black Hole run stopped")
                    break
                end
                if os.clock() - started > 180 then
                    setStatus("🕳️ Black Hole run timed out")
                    break
                end
                if not inst.Parent then
                    setStatus("🕳️ Black Hole seed gone")
                    break
                end
                if inst:GetAttribute("BlackHoleCarrierUserId")
                    == LocalPlayer.UserId then
                    setStatus("🕳️ You have the Black Hole seed - "
                        .. "deliver it to your safe zone!")
                    print("[SeedFarm] black hole run: you picked it up")
                    break
                end
                local root = getRoot()
                local pos = nil
                pcall(function() pos = inst:GetPivot().Position end)
                if root and pos then
                    local d = (root.Position - pos).Magnitude
                    if d <= 8 then
                        pcall(function()
                            local prompt = inst:FindFirstChildWhichIsA(
                                "ProximityPrompt", true)
                            if prompt then fireproximityprompt(prompt) end
                        end)
                        setStatus("🕳️ At the Black Hole seed - grab it!")
                        print("[SeedFarm] black hole run: arrived")
                        break
                    end
                    local hum = root.Parent
                        and root.Parent:FindFirstChildOfClass("Humanoid")
                    if hum then hum:MoveTo(pos) end
                end
                task.wait(0.4)
            end
            areaFarm.bhRunning = false
        end)
    end,
})

FarmTab:CreateToggle({
    Name = "🧲 Runback Vacuum",
    CurrentValue = true,
    Flag = "RunbackVacuum",
    Callback = function(v)
        vacuumOn = v
        print("[SeedFarm] runback vacuum " .. (v and "ON" or "OFF"))
    end,
})

-- extracted run-back trigger (called by RUN BACK button AND auto-run)
triggerRunback = function()
    if runningBack or runbackLoopActive then return end
    setStatus("Running back...")
    task.spawn(function()
        runbackLoopActive = true
        stopRunback = false -- clear any previous STOP press
        -- live distance readout on the RUN BACK button while running
        local distConn
        distConn = game:GetService("RunService").Heartbeat:Connect(function()
            if not runbackLoopActive then
                if distConn then distConn:Disconnect() end
                return
            end
            local root = getRoot()
            if root then
                local rt = pinPos or SAFE_ZONE
                local d = math.floor((root.Position - rt).Magnitude)
                pcall(function() runBackBtn:Set("🏃 RUNNING (" .. d .. "m)") end)
            end
        end)
        -- retry loop: if a run breaks/times out, wait 0.2s and go again until
        -- delivered or STOP pressed
        local ok = false
        while not stopRunback and not ok do
            ok = runToSafeZone()
            if not ok and not stopRunback then
                setStatus("Broke — retrying in 0.2s...")
                print("[SeedFarm] runback attempt failed, retrying in 0.2s")
                task.wait(0.2)
            end
        end
        runbackLoopActive = false
        if distConn then distConn:Disconnect() end
        setStatus(ok and "Delivered! Pick next seed." or "Runback ended.")
        pcall(function() runBackBtn:Set(pinPos and "🏃 RUN TO PIN" or "🏃 RUN BACK") end)
    end)
end

-- pin button: tap to set a custom run destination, tap again to clear it
-- (run-back falls back to the safe zone when no pin is set)
local pinBtn = FarmTab:CreateButton({
    Name = "📌 SET PIN",
    Callback = function()
        if pinPos then
            pinPos = nil
            pinMarker.Transparency = 1
            pcall(function() pinBtn:Set("📌 SET PIN") end)
            if not runningBack and not runbackLoopActive then
                pcall(function() runBackBtn:Set("🏃 RUN BACK") end)
            end
            setStatus("Pin cleared — run-back goes to safe zone")
            print("[SeedFarm] pin cleared")
            return
        end
        local root = getRoot()
        if not root then
            setStatus("No character!")
            return
        end
        pinPos = root.Position
        pinMarker.Position = pinPos + Vector3.new(0, 3, 0)
        pinMarker.Transparency = 0.3
        pcall(function() pinBtn:Set("📌 PIN: ON (tap to clear)") end)
        if not runningBack and not runbackLoopActive then
            pcall(function() runBackBtn:Set("🏃 RUN TO PIN") end)
        end
        setStatus(string.format("Pin set! (%d, %d, %d)", math.floor(pinPos.X), math.floor(pinPos.Y), math.floor(pinPos.Z)))
        print("[SeedFarm] pin set at " .. tostring(pinPos))
    end,
})

FarmTab:CreateSection("Toggles")
FarmTab:CreateToggle({
    Name = "Auto Run",
    Flag = "AutoRun",
    CurrentValue = false,
    Callback = function(v)
        autoRunEnabled = v
        if not v and runbackArmed then
            -- toggling Auto Run off cancels a pending arm
            runbackArmed = false
            pcall(function() runBackBtn:Set(pinPos and "🏃 RUN TO PIN" or "🏃 RUN BACK") end)
            print("[SeedFarm] auto-run disarmed (toggle off)")
        end
        print("[SeedFarm] auto run " .. (v and "ON" or "OFF"))
    end,
})
FarmTab:CreateToggle({
    Name = "Auto-Select Best",
    Flag = "AutoSelectBest",
    CurrentValue = false,
    Callback = function(v)
        autoSelectBest = v
        print("[SeedFarm] auto-select best " .. (v and "ON" or "OFF"))
        if v then pcall(function() refreshSeedList(true) end) end
    end,
})
FarmTab:CreateToggle({
    Name = "Seed ESP",
    Flag = "SeedESP",
    CurrentValue = false,
    Callback = function(v)
        espEnabled = v
        print("[SeedFarm] seed ESP " .. (v and "ON" or "OFF"))
        if updateSeedESP then pcall(updateSeedESP) end
    end,
})

FarmTab:CreateSection("Auto Farm")
areaFarm.toggles.main = FarmTab:CreateToggle({
    Name = "Full Auto Farm",
    CurrentValue = false,
    Callback = function(v) setAreaAutoFarm("main", v) end,
})
FarmTab:CreateToggle({
    Name = "🏃 Treadmill When Idle",
    CurrentValue = false,
    Callback = function(v)
        treadmillIdleOn = v
        print("[SeedFarm] treadmill idle " .. (v and "ON" or "OFF"))
        if v then
            setStatus("Treadmill idle ON - trains, grabs " .. autoFarmMinTier .. " seeds")
        elseif treadmillExitFn then
            treadmillExitFn()
        end
    end,
})
FarmTab:CreateDropdown({
    Name = "Auto Farm Targets",
    Flag = "AutoFarmMinTier",
    Options = { "Any", "T2+", "T3+", "T4+", "Events only" },
    CurrentOption = { "Any" },
    MultipleOptions = false,
    Callback = function(Options)
        autoFarmMinTier = type(Options) == "table" and Options[1] or Options or "Any"
        print("[SeedFarm] auto farm targets: " .. autoFarmMinTier)
    end,
})

FarmTab:CreateSection("World ESP")
FarmTab:CreateDropdown({
    Name = "Show Tiers (multi)",
    Flag = "WorldESPTiers",
    Options = { "T1", "T2", "T3", "T4", "Event" },
    CurrentOption = {},
    MultipleOptions = true,
    Callback = function(Options)
        espTierSet = {}
        for _, t in ipairs(Options or {}) do espTierSet[t] = true end
        print("[SeedFarm] world ESP tiers: " .. table.concat(Options or {}, ", "))
        if syncWorldESP then pcall(function() syncWorldESP(findWildSeeds()) end) end
    end,
})

local espHL, espBB, espLbl
local function clearSeedESP()
    if espHL then pcall(function() espHL:Destroy() end) espHL = nil end
    if espBB then pcall(function() espBB:Destroy() end) espBB = nil espLbl = nil end
end
updateSeedESP = function()
    clearSeedESP()
    if not espEnabled then return end
    local m = selectedSeed and selectedSeed.model
    if not (m and m.Parent) then return end
    pcall(function()
        espHL = Instance.new("Highlight")
        espHL.FillColor = Color3.fromRGB(255, 200, 0)
        espHL.OutlineColor = Color3.fromRGB(255, 255, 255)
        espHL.FillTransparency = 0.5
        espHL.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        espHL.Parent = m
    end)
    pcall(function()
        espBB = Instance.new("BillboardGui")
        espBB.Size = UDim2.new(0, 180, 0, 44)
        espBB.AlwaysOnTop = true
        espBB.StudsOffset = Vector3.new(0, 4, 0)
        espBB.Adornee = m
        espLbl = Instance.new("TextLabel")
        espLbl.Size = UDim2.new(1, 0, 1, 0)
        espLbl.BackgroundTransparency = 1
        espLbl.TextColor3 = Color3.fromRGB(255, 230, 120)
        espLbl.Font = Enum.Font.SourceSansBold
        espLbl.TextSize = 14
        espLbl.Text = selectedSeed.name
        espLbl.Parent = espBB
        espBB.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    end)
end
task.spawn(function()
    while stillAlive() do
        task.wait(0.25)
        if espEnabled and espBB and espLbl then
            local m = selectedSeed and selectedSeed.model
            local root = getRoot()
            if not (m and m.Parent and root) then
                clearSeedESP()
            else
                pcall(function()
                    local d = math.floor((root.Position - m:GetPivot().Position).Magnitude)
                    espLbl.Text = selectedSeed.name .. " · " .. d .. "m"
                end)
            end
        end
    end
end)

local worldEspMarkers = {}
local function tierBucket(s)
    if s.tier == 99 or s.isEventItem or s.isCollectible then return "Event" end
    if s.tier >= 4 then return "T4" end
    if s.tier == 3 then return "T3" end
    if s.tier == 2 then return "T2" end
    return "T1"
end
local TIER_COLORS = {
    T1 = Color3.fromRGB(60, 220, 80),
    T2 = Color3.fromRGB(255, 220, 40),
    T3 = Color3.fromRGB(255, 140, 20),
    T4 = Color3.fromRGB(255, 50, 50),
    Event = Color3.fromRGB(200, 80, 255),
}
local function removeWorldMarker(m)
    local mk = worldEspMarkers[m]
    if mk then
        if mk.hl then pcall(function() mk.hl:Destroy() end) end
        if mk.bb then pcall(function() mk.bb:Destroy() end) end
        worldEspMarkers[m] = nil
    end
end
syncWorldESP = function(seeds)
    local want = {}
    for _, s in ipairs(seeds) do
        if espTierSet[tierBucket(s)] and s.model and s.model.Parent
            and s.model ~= (selectedSeed and selectedSeed.model) then
            want[s.model] = s
        end
    end
    for m in pairs(worldEspMarkers) do
        if not want[m] or not m.Parent then removeWorldMarker(m) end
    end
    local count = 0
    for _ in pairs(worldEspMarkers) do count += 1 end
    for m, s in pairs(want) do
        if not worldEspMarkers[m] and count < 60 then
            count += 1
            local col = TIER_COLORS[tierBucket(s)] or Color3.new(1, 1, 1)
            local hl, bb, lbl
            pcall(function()
                hl = Instance.new("Highlight")
                hl.FillColor = col
                hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                hl.FillTransparency = 0.6
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.Parent = m
            end)
            pcall(function()
                bb = Instance.new("BillboardGui")
                bb.Size = UDim2.new(0, 150, 0, 36)
                bb.AlwaysOnTop = true
                bb.StudsOffset = Vector3.new(0, 3.5, 0)
                bb.Adornee = m
                lbl = Instance.new("TextLabel")
                lbl.Size = UDim2.new(1, 0, 1, 0)
                lbl.BackgroundTransparency = 1
                lbl.TextColor3 = col
                lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                lbl.TextStrokeTransparency = 0.4
                lbl.Font = Enum.Font.SourceSansBold
                lbl.TextSize = 13
                lbl.Text = s.name
                lbl.Parent = bb
                bb.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            end)
            worldEspMarkers[m] = { hl = hl, bb = bb, lbl = lbl, seed = s }
        end
    end
end
task.spawn(function()
    while stillAlive() do
        task.wait(0.3)
        local root = getRoot()
        for m, mk in pairs(worldEspMarkers) do
            if not m.Parent then
                removeWorldMarker(m)
            elseif mk.lbl and root then
                pcall(function()
                    local d = math.floor((root.Position - m:GetPivot().Position).Magnitude)
                    mk.lbl.Text = mk.seed.name .. " · " .. d .. "m"
                end)
            end
        end
    end
end)

-- treadmill idle: board your own treadmill (found via the plot finder's
-- OwnerUserId marker in Workspace.Map.Pens) and train while no target seed
-- matching the Auto Farm Targets filter is up
local tmBoardRemote, tmExitRemote, tmTapRemote = nil, nil, nil
for _, d in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
    if d:IsA("RemoteEvent") then
        if d.Name == "RequestBoardTreadmill" then tmBoardRemote = d
        elseif d.Name == "RequestExitTreadmill" then tmExitRemote = d
        elseif d.Name == "ReportTreadmillTap" then tmTapRemote = d end
    end
end
print("[SeedFarm] treadmill remotes: board=" .. tostring(tmBoardRemote ~= nil) .. " exit=" .. tostring(tmExitRemote ~= nil) .. " tap=" .. tostring(tmTapRemote ~= nil))
local treadmillState = { boarded = false, model = nil, pos = nil }
local penAttrLogged = false
local function getAssignedPen()
    -- pen-guidance-config: player attributes AssignedPenCenter / AssignedPenSize
    for _, holder in ipairs({ LocalPlayer, LocalPlayer.Character }) do
        if holder then
            local okC, center = pcall(function() return holder:GetAttribute("AssignedPenCenter") end)
            local okS, size = pcall(function() return holder:GetAttribute("AssignedPenSize") end)
            if okC and okS and typeof(center) == "Vector3" and typeof(size) == "Vector3" then
                return center, size
            end
        end
    end
    return nil, nil
end
local function findMyTreadmill()
    local map = workspace:FindFirstChild("Map")
    local pens = map and map:FindFirstChild("Pens")
    if not pens then return nil end
    -- 1. own pen via AssignedPenCenter/AssignedPenSize attributes (fast, exact)
    local center, size = getAssignedPen()
    if not penAttrLogged then
        penAttrLogged = true
        print("[SeedFarm] AssignedPenCenter=" .. tostring(center) .. " AssignedPenSize=" .. tostring(size))
    end
    if center and size then
        for _, d in ipairs(pens:GetDescendants()) do
            if d:IsA("Model") and d.Name:lower():find("treadmill") then
                local pos = nil
                pcall(function() pos = d:GetPivot().Position end)
                if pos
                    and math.abs(pos.X - center.X) <= size.X / 2
                    and math.abs(pos.Z - center.Z) <= size.Z / 2
                    and math.abs(pos.Y - center.Y) <= size.Y / 2 + 8 then
                    return d
                end
            end
        end
    end
    -- 2. fallback: OwnerUserId marker scan
    for _, d in ipairs(pens:GetDescendants()) do
        if d:IsA("Model") and d.Name:lower():find("treadmill") and d:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
            return d
        end
    end
    for _, d in ipairs(pens:GetDescendants()) do
        if d:IsA("Model") and d.Name:lower():find("treadmill") then return d end
    end
    return nil
end
local function boardTreadmill()
    local m = findMyTreadmill()
    if not m then print("[SeedFarm] treadmill: none found in your pen") return false end
    local pos = nil
    pcall(function() pos = m:GetPivot().Position end)
    local root = getRoot()
    if not pos or not root then return false end
    root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
    task.wait(0.3)
    local prompt = m:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt and fireproximityprompt then
        pcall(function() fireproximityprompt(prompt) end)
    end
    if tmBoardRemote then pcall(function() tmBoardRemote:FireServer(m) end) end
    treadmillState.boarded = true
    treadmillState.model = m
    treadmillState.pos = pos
    setStatus("Training on " .. m.Name)
    print("[SeedFarm] boarded treadmill " .. m.Name)
    return true
end
treadmillExitFn = function()
    if tmExitRemote then pcall(function() tmExitRemote:FireServer() end) end
    treadmillState.boarded = false
end

local farmBlacklist = {} -- uid -> unblock time (after 3 failed attempts)
local farmFailCount = {}
local function farmTarget()
    local best = nil
    for _, s in ipairs(findWildSeeds()) do
        local blocked = s.uid and farmBlacklist[s.uid] and os.clock() < farmBlacklist[s.uid]
        if not blocked and seedArea(s) == areaFarm.area then
            local ok = false
            if autoFarmMinTier == "Any" then ok = true
            elseif autoFarmMinTier == "T2+" then ok = s.tier >= 2
            elseif autoFarmMinTier == "T3+" then ok = s.tier >= 3
            elseif autoFarmMinTier == "T4+" then ok = s.tier >= 4
            elseif autoFarmMinTier == "Events only" then ok = (s.tier == 99 or s.isEventItem or s.isCollectible or s.source == "halloween")
            end
            if ok and (not best or s.tier > best.tier or (s.tier == best.tier and (s.weight or 0) > (best.weight or 0))) then
                best = s
            end
        end
    end
    return best
end
local autoFarmBusy = false
task.spawn(function()
    while stillAlive() do
        task.wait(0.5)
        if (autoFarmOn or treadmillIdleOn) and not autoFarmBusy then
            autoFarmBusy = true
            local okCycle, errCycle = pcall(function()
                local target = farmTarget()
                if not target then
                    if treadmillIdleOn then
                        if treadmillState.boarded and treadmillState.pos then
                            local r = getRoot()
                            if r and (r.Position - treadmillState.pos).Magnitude > 15 then
                                treadmillState.boarded = false
                            end
                        end
                        if not treadmillState.boarded then
                            setStatus("No " .. autoFarmMinTier .. " seeds - heading to treadmill")
                            boardTreadmill()
                        end
                        if treadmillState.boarded and tmTapRemote then
                            pcall(function() tmTapRemote:FireServer(treadmillState.model) end)
                        end
                        task.wait(0.4)
                    else
                        setStatus("Auto Farm: no targets, waiting...")
                        task.wait(2)
                    end
                    return
                end
                if treadmillState.boarded then
                    print("[SeedFarm] target seed up - leaving treadmill")
                    treadmillExitFn()
                end
                selectedSeed = target
                if updateSeedESP then pcall(updateSeedESP) end
                setStatus("Auto Farm: going for " .. target.name)
                print("[SeedFarm] auto farm target: " .. seedDisplayText(target))
                approachByRun = (areaFarm.area == "halloween")
                local msg = teleportToSelected()
                approachByRun = false
                setStatus(msg)
                if msg and msg:sub(1, 3) == "Got" then
                    noteCollected()
                    farmFailCount[target.uid] = nil
                    print("[SeedFarm] auto farm: carried, running back")
                    if not runbackLoopActive and not runningBack then
                        triggerRunback()
                    end
                    local waited = 0
                    while (autoFarmOn or treadmillIdleOn) and (runbackLoopActive or runningBack) and waited < 120 do
                        task.wait(0.25)
                        waited += 0.25
                    end
                else
                    -- failed pickup: 3 strikes on the same seed = skip it 60s
                    if target.uid then
                        farmFailCount[target.uid] = (farmFailCount[target.uid] or 0) + 1
                        if farmFailCount[target.uid] >= 3 then
                            farmBlacklist[target.uid] = os.clock() + 60
                            farmFailCount[target.uid] = nil
                            print("[SeedFarm] auto farm: blacklisted " .. target.name .. " for 60s (3 failed pickups)")
                        end
                    end
                    task.wait(1)
                end
            end)
            if not okCycle then print("[SeedFarm] auto farm cycle error: " .. tostring(errCycle)) end
            autoFarmBusy = false
        end
    end
end)

-- scrub a stale theme name out of the saved config BEFORE it loads: restoring
-- an unknown theme empties Rayfield's theme state, which the tab buttons
-- read before switching pages - so the tabs silently stop working
pcall(function()
    if readfile and writefile and isfile and isfile("SeedFarm/SeedFarmConfig.rfld") then
        local HttpService = game:GetService("HttpService")
        local data = HttpService:JSONDecode(readfile("SeedFarm/SeedFarmConfig.rfld"))
        local saved = type(data.Theme) == "table" and data.Theme[1] or data.Theme
        if saved and not VALID_THEMES[saved] then
            data.Theme = { getgenv().__SeedFarmTheme or "Green" }
            writefile("SeedFarm/SeedFarmConfig.rfld", HttpService:JSONEncode(data))
            print("[SeedFarm] cleaned stale theme '" .. tostring(saved) .. "' from saved config")
        end
    end
end)
-- LoadConfiguration moved to the very end of the file
-- (v10.98) so elements created inside plantSeedInit
-- (the Plant tab) exist before saved values are applied

refreshSeedList(true)
pcall(function() refreshSpeedwayList(true) end)
pcall(function() refreshHalloweenList(true) end)
local hookOk, hookErr = pcall(function()
    local RS = game:GetService("ReplicatedStorage")
    local remote = nil
    for _, d in ipairs(RS:GetDescendants()) do
        if d.Name == "CarryStateChanged" and d:IsA("RemoteEvent") then
            remote = d
            break
        end
    end
    if remote then
        remote.OnClientEvent:Connect(function(data)
            if not stillAlive() then return end
            if type(data) == "table" then
                lastCarryData = data
                lastCarrySeq += 1
                lastCarriedUid = data.uid
                if (data.seedId and HALLOWEEN_SEED_IDS[data.seedId])
                    or (type(data.biomeId) == "string"
                        and data.biomeId:lower()
                            :find("halloween", 1, true)) then
                    lastPickupHalloween = true
                    lastPickupHalloweenAt = os.clock()
                    print("[SeedFarm] carry is a halloween seed ("
                        .. tostring(data.seedId)
                        .. ") - fly delivery armed")
                end
                if (autoRunEnabled or autoFarmOn or manualTpPending) and not runningBack and not runbackLoopActive then
                    manualTpPending = false
                    runbackArmed = false
                    print("[SeedFarm] carry started - auto run starting now")
                    task.spawn(triggerRunback)
                end
            else
                lastCarryData = nil
            end
        end)
        print("[SeedFarm] CarryStateChanged hooked - instant pickup confirmation on")
        selfReport.carryHook = "hooked"
    else
        print("[SeedFarm] CarryStateChanged not found - inventory polling only")
        selfReport.carryHook = "NOT FOUND"
    end
    local invRemote = nil
    for _, d in ipairs(RS:GetDescendants()) do
        if d.Name == "InventorySeedCarryStateChanged" and d:IsA("RemoteEvent") then
            invRemote = d
            break
        end
    end
    if invRemote then
        invRemote.OnClientEvent:Connect(function(data)
            if not stillAlive() then return end
            if type(data) == "table" then
                lastDeliveryUid = data.uid
                lastDeliverySeq += 1
                sessionStats.total += 1
                local dbE = data.seedId and SEED_DB[data.seedId]
                local tStr = (dbE and dbE.tier) or "T?"
                sessionStats.byTier[tStr] =
                    (sessionStats.byTier[tStr] or 0) + 1
                sessionStats.update()
            end
        end)
        print("[SeedFarm] InventorySeedCarryStateChanged hooked - delivery confirmation on")
        selfReport.deliveryHook = "hooked"
    end
    local bhRemote = nil
    for _, d in ipairs(RS:GetDescendants()) do
        if d.Name == "BlackHoleSeedSecured" and d:IsA("RemoteEvent") then
            bhRemote = d
            break
        end
    end
    if bhRemote then
        bhRemote.OnClientEvent:Connect(function()
            if not stillAlive() then return end
            -- count it as Daniel's bank only if he was the carrier: the
            -- delivery trail is live, or the seed still names him
            local mine = bhTrailPos ~= nil
            if not mine then
                pcall(function()
                    for _, t in ipairs(game:GetService("CollectionService")
                        :GetTagged("BlackHoleSeed")) do
                        if t:GetAttribute("BlackHoleCarrierUserId")
                            == LocalPlayer.UserId then
                            mine = true
                        end
                    end
                end)
            end
            if mine then
                lastDeliverySeq += 1
                sessionStats.total += 1
                sessionStats.byTier["T4Guardian"] =
                    (sessionStats.byTier["T4Guardian"] or 0) + 1
                sessionStats.update()
                print("[SeedFarm] 🕳️ Black Hole seed SECURED - banked "
                    .. "at your safe zone")
            end
        end)
        print("[SeedFarm] BlackHoleSeedSecured hooked - BH delivery confirmation on")
        selfReport.bhHook = "hooked"
    else
        selfReport.bhHook = "not found"
    end
end)
if not hookOk then
    selfReport.carryHook = "ERROR"
    print("[SeedFarm] carry hook ERROR: " .. tostring(hookErr))
end

print("[SeedFarm] v10.110 loaded - pick a seed!")

-- startup self-report printer (v10.90): ~12s after load (catalog check
-- reports at 8s, safe zones at 6s), print every subsystem's status in
-- one block - the single screenshot that shows what is broken
task.delay(12, function()
    pcall(getLightningCfg) -- force-resolve so the report is real
    local bh = "no event seed present"
    pcall(function()
        local tagged = game:GetService("CollectionService")
            :GetTagged("BlackHoleSeed")
        if tagged[1] then
            bh = "state=" .. tostring(tagged[1]
                :GetAttribute("BlackHoleState")) .. " carrier="
                .. tostring(tagged[1]
                    :GetAttribute("BlackHoleCarrierUserId"))
        end
    end)
    print("[SeedFarm] ===== startup self-report =====")
    print("[SeedFarm] carry hook: " .. (selfReport.carryHook or "not hooked"))
    print("[SeedFarm] delivery hook: "
        .. (selfReport.deliveryHook or "not hooked"))
    print("[SeedFarm] placement: " .. (selfReport.placement or "unknown"))
    print("[SeedFarm] growth config: " .. (selfReport.growth or "unknown"))
    print("[SeedFarm] safe zones: " .. tostring(selfReport.safeZones or "?")
        .. " found")
    print("[SeedFarm] lightning: " .. (selfReport.lightning or "unresolved"))
    print("[SeedFarm] catalog: " .. (selfReport.catalog or "not run yet"))
    print("[SeedFarm] black hole: " .. bh)
    print("[SeedFarm] black hole secured hook: "
        .. (selfReport.bhHook or "not hooked"))
    print("[SeedFarm] ===== end self-report =====")
end)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- get GlobalEvents folder
local globalEvents = nil
pcall(function()
    globalEvents = ReplicatedStorage:FindFirstChild("shared/network@GlobalEvents")
end)

-- Equip Best Pet loop (uses RequestFillBest)
task.spawn(function()
    while stillAlive() do
        task.wait(5)
        if equipOn and globalEvents then
            local ok = pcall(function()
                globalEvents.RequestFillBest:FireServer()
            end)
            if ok then
                setEggStatus("Fired RequestFillBest")
            else
                setEggStatus("RequestFillBest failed")
            end
        end
    end
end)


--------------------------------------------------------------------------------
-- PLANT SEED TAB (plant-seed v3.6 merged in, Oct 23 2026)
-- The whole planter lives inside its own function (fresh local-register
-- budget - the farm's main chunk is at Luau's 200-local limit) with its own
-- locals, so it cannot collide with the farm's globals (its selectedSeed /
-- getRoot are its own). The old standalone window is replaced by a Rayfield
-- tab; console prints keep the [PlantSeed] prefix. Includes the v3.6
-- game-module placement validation (seed-placement / seed-placement-config).
--------------------------------------------------------------------------------
local function plantSeedInit()
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local equipRemote, plantRemote = nil, nil
local growSeedRemote, growAllRemote = nil, nil
for _, d in ipairs(RS:GetDescendants()) do
    if d:IsA("RemoteEvent") then
        if d.Name == "RequestEquipSeed" then equipRemote = d
        elseif d.Name == "RequestPlantSeed" then plantRemote = d
        elseif d.Name == "RequestGrowSeed" then growSeedRemote = d
        elseif d.Name == "RequestGrowAllSeeds" then growAllRemote = d end
    end
end
print("[PlantSeed] equip remote: " .. (equipRemote and "found" or "NOT FOUND"))
print("[PlantSeed] plant remote: " .. (plantRemote and "found" or "NOT FOUND"))
print("[PlantSeed] grow remotes: RequestGrowSeed="
    .. (growSeedRemote and "found" or "NOT FOUND")
    .. " RequestGrowAllSeeds="
    .. (growAllRemote and "found" or "NOT FOUND"))

local function getRoot()
    local c = player.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function findGuid(str)
    if type(str) ~= "string" then return nil end
    return str:match("(%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x)")
end

local function itemLabels(item)
    local texts = {}
    for _, d in ipairs(item:GetDescendants()) do
        if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text and d.Text ~= "" then
            texts[#texts + 1] = d.Text
        end
    end
    return texts
end

-- read the seed inventory grid (panel must be open so the grid exists)
local function readGrid()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return {} end
    local grid = nil
    pcall(function() grid = pg.ClientAppRoot.InventoryPanel.Window.Body.Content.Grid end)
    if not grid then
        print("[PlantSeed] grid not found - open the seed inventory first")
        return {}
    end
    local items = {}
    for _, item in ipairs(grid:GetChildren()) do
        if item:IsA("GuiObject") and item.Name:find("|") then
            local texts = itemLabels(item)
            local name = item.Name
            for _, t in ipairs(texts) do
                if t:find("Seed") and not t:find("KG") and #t < 40 then name = t break end
            end
            items[#items + 1] = { stackKey = item.Name, name = name, uid = nil }
        end
    end
    return items
end

local function gridSeedCount()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return 0 end
    local grid = nil
    pcall(function() grid = pg.ClientAppRoot.InventoryPanel.Window.Body.Content.Grid end)
    if not grid then return 0 end
    local c = 0
    for _, ch in ipairs(grid:GetChildren()) do
        if ch:IsA("GuiObject") and ch.Name:find("|") then c += 1 end
    end
    return c
end

local function inventoryPanelOpen()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return false end
    local panel = nil
    pcall(function() panel = pg.ClientAppRoot.InventoryPanel end)
    if not panel then return false end
    local okv, vis = pcall(function() return panel.Visible end)
    return okv and vis == true
end

-- right-side toolbar candidates (any class - the icons aren't ImageButtons),
-- top to bottom. Must belong to a toolbar-like group (3+ similar siblings).
local function findToolbarButtons(isOurs)
    local pg = player:FindFirstChild("PlayerGui")
    local out = {}
    if not pg then return out end
    local cam = workspace.CurrentCamera
    local vs = cam and cam.ViewportSize or Vector2.new(1000, 1000)
    local groups = {}
    local function insideInvPanel(d)
        local a = d
        while a do
            if a.Name == "InventoryPanel" then return true end
            a = a.Parent
        end
        return false
    end
    pcall(function()
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("GuiObject") and not isOurs(d) and not insideInvPanel(d)
                and not d.Name:find("|") then
                local okv, res = pcall(function()
                    if not d.Visible then return nil end
                    local pos = d.AbsolutePosition
                    local size = d.AbsoluteSize
                    if size.X < 24 or size.Y < 24 then return nil end
                    if size.X > 160 or size.Y > 160 then return nil end
                    if pos.X < vs.X * 0.55 then return nil end -- right side only
                    if pos.Y < vs.Y * 0.08 then return nil end -- skip top bar
                    if pos.Y > vs.Y * 0.78 then return nil end -- skip bottom hotbar
                    local par = d.Parent
                    return { b = d, y = pos.Y + size.Y / 2, par = par }
                end)
                if okv and res then
                    out[#out + 1] = res
                    if res.par then
                        groups[res.par] = (groups[res.par] or 0) + 1
                    end
                end
            end
        end
    end)
    -- keep only members of toolbar-like groups
    local kept = {}
    for _, r in ipairs(out) do
        if r.par and (groups[r.par] or 0) >= 3 then
            kept[#kept + 1] = r
        end
    end
    table.sort(kept, function(a, b) return a.y < b.y end)
    -- de-dupe: max 8, prefer one per parent slot (skip nested duplicates)
    local final, seenY = {}, {}
    for _, r in ipairs(kept) do
        local dup = false
        for _, y in ipairs(seenY) do if math.abs(y - r.y) < 12 then dup = true break end end
        if not dup then
            final[#final + 1] = r
            seenY[#seenY + 1] = r.y
        end
        if #final >= 8 then break end
    end
    return final
end

local _vim = nil
pcall(function() _vim = game:GetService("VirtualInputManager") end)

-- synthetic tap at a screen position (works on any GuiObject class)
local function tapAt(x, y)
    if not _vim then return false end
    local ok = pcall(function()
        _vim:SendMouseButtonEvent(x, y, 0, true, game, 1)
        task.wait(0.06)
        _vim:SendMouseButtonEvent(x, y, 0, false, game, 1)
    end)
    return ok
end

-- call the game's own InputBegan/InputEnded handlers with a fake touch input
local function fireGameInput(g)
    local ran = false
    pcall(function()
        local gc = getconnections or debug.getconnections
        if not gc then return end
        for _, sig in ipairs({ g.InputBegan, g.InputEnded }) do
            local okc, conns = pcall(gc, sig)
            if okc and conns then
                for _, c in ipairs(conns) do
                    local okf = pcall(function()
                        c.Function({
                            UserInputType = Enum.UserInputType.Touch,
                            UserInputState = Enum.UserInputState.Begin,
                            Position = Vector3.new(0, 0, 0),
                        }, false)
                    end)
                    if okf then ran = true end
                end
            end
        end
    end)
    return ran
end

local function pressGui(g)
    -- firesignal for real buttons, VIM tap for anything else.
    -- success = the panel opened or the grid gained items (not just "no error")
    local wasPanel = inventoryPanelOpen()
    local wasGrid = gridSeedCount()
    local function changed()
        return (inventoryPanelOpen() and not wasPanel) or gridSeedCount() > wasGrid
    end
    if g:IsA("GuiButton") then
        pcall(function() firesignal(g.Activated) end)
        task.wait(0.8)
        if changed() then return true end
        pcall(function() firesignal(g.MouseButton1Click) end)
        task.wait(0.8)
        if changed() then return true end
    end
    local okp, pos, size = pcall(function() return g.AbsolutePosition, g.AbsoluteSize end)
    if okp and pos and size.X > 0 then
        local cx, cy = pos.X + size.X / 2, pos.Y + size.Y / 2
        print(string.format("[PlantSeed] VIM tap at (%d,%d) on %s", cx, cy, g.Name))
        if tapAt(cx, cy) then
            task.wait(1)
            if changed() then return true end
        end
    end
    return false
end

local function pressButton(b)
    local fired = false
    pcall(function() firesignal(b.Activated) fired = true end)
    task.wait(0.9)
    if gridSeedCount() > 0 then return true end
    pcall(function() firesignal(b.MouseButton1Click) fired = true end)
    task.wait(0.9)
    return gridSeedCount() > 0
end

local function openSeedInventory()
    if gridSeedCount() > 0 then return true end
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return false end
    print("[PlantSeed] opening the seed inventory...")
    local function isOurs(d)
        local a = d
        while a do
            if a.Name == "PlantSeed" then return true end
            a = a.Parent
        end
        return false
    end
    local function insideInvPanel(d)
        local a = d
        while a do
            if a.Name == "InventoryPanel" then return true end
            a = a.Parent
        end
        return false
    end
    -- 0) the Seeds toolbar icon: may open the seed grid directly
    local function pressToolbarIcon(iconName)
        local btn = nil
        pcall(function()
            for _, d in ipairs(pg:GetDescendants()) do
                if d:IsA("GuiButton") and not isOurs(d) and d.Name == "Button"
                    and d.Parent and d.Parent.Name == iconName
                    and d.Parent.Parent and d.Parent.Parent.Name == "Buttons" then
                    local okv, vis = pcall(function() return d.Visible end)
                    if okv and vis then btn = d break end
                end
            end
        end)
        if not btn then return false end
        print("[PlantSeed] pressing toolbar icon: " .. iconName)
        for attempt = 1, 2 do
            if gridSeedCount() > 0 then break end
            pcall(function() pressGui(btn) end)
            task.wait(0.7)
        end
        return gridSeedCount() > 0
    end
    if gridSeedCount() == 0 then
        if pressToolbarIcon("Seeds") then
            print("[PlantSeed] seed grid opened via Seeds icon")
        end
    end
    -- 1) the backpack: Buttons > Inventory > Button (the real clickable)
    if gridSeedCount() == 0 and not inventoryPanelOpen() then
        local btn, frame = nil, nil
        pcall(function()
            for _, d in ipairs(pg:GetDescendants()) do
                if not isOurs(d) and d.Parent and d.Parent.Name == "Buttons"
                    and d.Name == "Inventory" and d:IsA("GuiObject") then
                    local okv, vis = pcall(function() return d.Visible end)
                    if okv and vis then frame = d end
                end
                if d:IsA("GuiButton") and not isOurs(d) and d.Name == "Button"
                    and d.Parent and d.Parent.Name == "Inventory"
                    and d.Parent.Parent and d.Parent.Parent.Name == "Buttons" then
                    local okv, vis = pcall(function() return d.Visible end)
                    if okv and vis then btn = d end
                end
                if btn and frame then break end
            end
        end)
        if btn then
            print("[PlantSeed] pressing backpack button")
            for attempt = 1, 2 do
                if inventoryPanelOpen() then break end
                pcall(function()
                    if pressGui(btn) then
                        print("[PlantSeed] inventory opened via backpack")
                    end
                end)
                task.wait(0.5)
            end
        end
        if not inventoryPanelOpen() and frame then
            print("[PlantSeed] trying game input handlers on Inventory frame")
            pcall(function()
                local was = inventoryPanelOpen()
                if fireGameInput(frame) then
                    task.wait(1)
                    if inventoryPanelOpen() and not was then
                        print("[PlantSeed] inventory opened via game input")
                    end
                end
            end)
        end
        if not inventoryPanelOpen() and frame then
            print("[PlantSeed] VIM tap fallback on Inventory frame")
            pcall(function()
                if pressGui(frame) then
                    print("[PlantSeed] inventory opened via VIM tap")
                end
            end)
        end
        if not btn and not frame then
            print("[PlantSeed] backpack not found on toolbar")
        end
    end
    -- 2) make sure the SEEDS tab is selected (class-agnostic)
    if gridSeedCount() == 0 and inventoryPanelOpen() then
        local cands = {}
        pcall(function()
            local panel = pg.ClientAppRoot.InventoryPanel
            for _, d in ipairs(panel:GetDescendants()) do
                if d:IsA("GuiObject") and not isOurs(d) then
                    local txt = ""
                    pcall(function() txt = d.Text or "" end)
                    if txt == "" then
                        pcall(function()
                            for _, ch in ipairs(d:GetChildren()) do
                                if ch:IsA("TextLabel") and (ch.Text or "") ~= "" then
                                    txt = ch.Text
                                    break
                                end
                            end
                        end)
                    end
                    if txt:lower():find("^seeds") then
                        -- prefer: Button child > GuiButton > Frame
                        local inner = nil
                        pcall(function()
                            for _, ch in ipairs(d:GetChildren()) do
                                if ch:IsA("GuiButton") and ch.Name == "Button" then
                                    inner = ch
                                    break
                                end
                            end
                        end)
                        local target = inner or d
                        local prio = 2
                        if inner then prio = 0
                        elseif d:IsA("GuiButton") then prio = 1 end
                        cands[#cands + 1] = { t = target, frame = d, prio = prio,
                            desc = d.ClassName .. " '" .. d.Name .. "'" }
                    end
                end
            end
        end)
        table.sort(cands, function(a, b) return a.prio < b.prio end)
        print("[PlantSeed] found " .. #cands .. " seeds-tab candidates")
        local tried = 0
        for _, c in ipairs(cands) do
            if gridSeedCount() > 0 or tried >= 3 then break end
            tried += 1
            print("[PlantSeed] tapping seeds tab: " .. c.desc)
            pcall(function() pressGui(c.t) end)
            task.wait(0.7)
            if gridSeedCount() == 0 and c.frame ~= c.t then
                -- game-input fallback on the frame itself
                pcall(function()
                    if fireGameInput(c.frame) then
                        task.wait(0.8)
                    end
                end)
            end
        end
        if gridSeedCount() == 0 then
            print("[PlantSeed] seeds tab did not switch")
        else
            print("[PlantSeed] seeds tab open")
        end
    end
    local c = gridSeedCount()
    print("[PlantSeed] inventory grid has " .. c .. " seed items")
    if c == 0 then
        -- diagnostic: dump every visible button so the real toggle can be pinned
        print("[PlantSeed] --- visible buttons in PlayerGui ---")
        pcall(function()
            for _, d in ipairs(pg:GetDescendants()) do
                if d:IsA("GuiButton") and not isOurs(d) then
                    local okv, vis = pcall(function() return d.Visible and d.AbsoluteSize.X > 20 end)
                    if okv and vis then
                        local par = d.Parent and d.Parent.Name or "?"
                        print("[PlantSeed] btn: " .. d.Name .. " (in " .. par .. ")")
                    end
                end
            end
            -- topbar icon detail: parent chain + icon image per ClickRegion
            for _, d in ipairs(pg:GetDescendants()) do
                if d:IsA("GuiButton") and d.Name == "ClickRegion" and not isOurs(d) then
                    local spot = d.Parent
                    local holder = spot and spot.Parent
                    local img = ""
                    pcall(function()
                        for _, ch in ipairs(spot:GetChildren()) do
                            if ch:IsA("ImageLabel") or ch:IsA("ImageButton") then
                                img = tostring(ch.Image)
                                break
                            end
                        end
                    end)
                    print("[PlantSeed] topbar: holder=" .. (holder and holder.Name or "?") ..
                        " image=" .. img)
                end
            end
        end)
        print("[PlantSeed] --- end button dump ---")
    end
    return c > 0
end

local UID_KEYS = { "uid", "Uid", "UUID", "uuid", "seedUid", "SeedUid", "itemUid", "ItemUid", "id", "Id" }
local function takeUid(t)
    for _, k in ipairs(UID_KEYS) do
        local v = rawget(t, k)
        local g = findGuid(v)
        if g then return g end
    end
    return nil
end

-- hunt the client's inventory state in GC for stackKey -> uid
local function huntUids(items)
    if #items == 0 then return end
    local want = {}
    for _, it in ipairs(items) do want[it.stackKey] = it end
    local found = 0
    local ok, gc = pcall(function() return getgc(true) end)
    if not ok or not gc then print("[PlantSeed] getgc unavailable") return end
    print("[PlantSeed] hunting uids in client memory for " .. #items .. " stacks...")
    for _, obj in ipairs(gc) do
        if found >= #items then break end
        if type(obj) == "table" then
            pcall(function()
                -- shape 1: entry has a stackKey field; uid must be under a uid key
                local sk = rawget(obj, "stackKey") or rawget(obj, "StackKey")
                if type(sk) == "string" and want[sk] and not want[sk].uid then
                    local g = takeUid(obj)
                    if g then want[sk].uid = g found += 1 end
                end
                -- shape 2: table keyed BY stackKey; prefer uid keys, else any GUID inside
                for sk2, it in pairs(want) do
                    if not it.uid then
                        local sub = rawget(obj, sk2)
                        if type(sub) == "table" then
                            local g = takeUid(sub)
                            if not g then
                                for _, v in pairs(sub) do
                                    g = findGuid(v)
                                    if g then break end
                                end
                            end
                            if g then it.uid = g found += 1 end
                        elseif type(sub) == "string" then
                            local g = findGuid(sub)
                            if g then it.uid = g found += 1 end
                        end
                    end
                end
                -- shape 4: co-occurrence - a GUID and a known stackKey living
                -- in the same small table get paired (loose, runs last)
                local needCo = false
                for _, it in pairs(want) do if not it.uid then needCo = true break end end
                if needCo then
                    local sz = 0
                    for _ in pairs(obj) do sz += 1 if sz > 25 then break end end
                    if sz <= 25 then
                        local g4, k4 = nil, nil
                        for k, v in pairs(obj) do
                            if type(v) == "string" then
                                if not g4 and findGuid(v) then g4 = v end
                                if not k4 and want[v] and not want[v].uid then k4 = v end
                            end
                            if type(k) == "string" then
                                if not g4 and findGuid(k) then g4 = k end
                                if not k4 and want[k] and not want[k].uid then k4 = k end
                            end
                            if g4 and k4 then break end
                        end
                        if g4 and k4 then
                            want[k4].uid = g4
                            found += 1
                            print("[PlantSeed] uid paired (co-occur): " .. want[k4].name .. " -> " .. g4:sub(1, 8))
                        end
                    end
                end
                -- shape 3: entry has uid + seedId parts; compose its stackKey
                local uid = rawget(obj, "uid") or rawget(obj, "Uid") or rawget(obj, "seedUid") or rawget(obj, "SeedUid")
                local sid = rawget(obj, "seedId") or rawget(obj, "SeedId")
                if type(uid) == "string" and findGuid(uid) and type(sid) == "string" then
                    local biome = rawget(obj, "biomeId") or rawget(obj, "BiomeId") or ""
                    local rar = rawget(obj, "rarity") or rawget(obj, "Rarity") or rawget(obj, "tier") or rawget(obj, "Tier") or ""
                    local size = rawget(obj, "size") or rawget(obj, "Size") or ""
                    local w = rawget(obj, "weightKg") or rawget(obj, "WeightKg") or rawget(obj, "weight") or 0
                    local composed = string.format("%s|%s|%s|%s||%.6f", sid, tostring(biome), tostring(rar), tostring(size), tonumber(w) or 0)
                    if want[composed] and not want[composed].uid then
                        want[composed].uid = uid
                        found += 1
                    end
                end
            end)
        end
    end
    for _, it in ipairs(items) do
        if it.uid then
            print("[PlantSeed] uid found: " .. it.name .. " -> " .. it.uid)
        else
            print("[PlantSeed] no uid yet for: " .. it.name .. " (" .. it.stackKey .. ")")
        end
    end
end

-- declared early: scanSeeds (below) and the learn hook both use it
local learnedUids = {} -- [stackKey] = uid, filled by the learn hook, applied on SCAN

local function applyLearned(items)
    local applied = 0
    for _, it in ipairs(items) do
        if not it.uid and learnedUids[it.stackKey] then
            it.uid = learnedUids[it.stackKey]
            applied += 1
        end
    end
    if applied > 0 then print("[PlantSeed] applied " .. applied .. " learned uids") end
end

local function scanSeeds()
    local items = readGrid()
    huntUids(items)
    applyLearned(items)
    -- the game's inventory state populates async after the panel opens;
    -- re-hunt while most uids are still missing
    local tries = 0
    while #items > 0 and tries < 2 do
        local missing = 0
        for _, it in ipairs(items) do if not it.uid then missing += 1 end end
        if missing <= #items / 2 then break end
        tries += 1
        task.wait(2)
        print("[PlantSeed] re-hunting uids (attempt " .. (tries + 1) .. ")...")
        huntUids(items)
        applyLearned(items)
    end
    return items
end

--------------------------------------------------------------------------------
-- v1.5: the server's REAL placement validator, ported from
-- Common/config/seed-placement-config + Common/world/seed-placement.
-- Spots are pre-validated client-side so the only remaining failure mode
-- is a bad uid (which the SNIFF toggle resolves).
--------------------------------------------------------------------------------
local EDGE_MARGIN = 0.5
local MIN_R = 0.9
local MAX_R = 6.6
local NEW_SEED_R = 2.5

-- v3.6: the game's OWN placement modules (from the seed-placement /
-- seed-placement-config dumps, Oct 23 2026). When they resolve, the
-- validator and the per-seed footprint radii come from the game itself;
-- otherwise the v3.5 port below runs unchanged.
--   seedFootprintRadius({seedId, size, weightKg, tier}): the game's radius
--     for a seed - seed-config placementRadius if it defines one, else
--     computed from size/weight/growth - clamped [0.9, 6.6]. v3.5 used a
--     fixed 2.5 for every seed, so big seeds got server Overlap rejects
--     and small seeds wasted soil.
--   reservedSeedFootprintRadius(seed, current): what the server reserves
--     for an already-planted seed (its grown footprint, not today's box).
--   seed-placement.validatePlacement(area, spot, existing): the real
--     verdict function ("Ok"/"OutsideSoil"/"BlocksDoorway"/"Overlap").
local placementMod, placementCfg = nil, nil
pcall(function()
    local rs = game:GetService("ReplicatedStorage")
    local common = rs:FindFirstChild("Common")
    local cfgFolder = common and common:FindFirstChild("config")
    local m1 = cfgFolder and cfgFolder:FindFirstChild("seed-placement-config")
    if m1 then placementCfg = require(m1) end
    local m2 = cfgFolder and cfgFolder:FindFirstChild("seed-placement")
    if not m2 and common then
        m2 = common:FindFirstChild("seed-placement", true)
    end
    if m2 then placementMod = require(m2) end
end)
print("[PlantSeed] placement modules: validator=" .. tostring(placementMod ~= nil)
    .. " config=" .. tostring(placementCfg ~= nil))
selfReport.placement = (placementMod ~= nil and "validator LIVE"
    or "validator fallback") .. ", " .. (placementCfg ~= nil
    and "config LIVE" or "config fallback")

-- growth durations (v10.90): seed-config entries carry a growthProfile
-- table built by the game's seed-weight-growth-config; scan each profile
-- for a duration-looking number so crop timers can be computed from a
-- planted-at timestamp when a crop carries one. Heuristic field scan -
-- the HARVEST PROBE output pins the real field names.
local psGrowthSecs = {} -- seedId -> grow seconds
pcall(function()
    local rsG = game:GetService("ReplicatedStorage")
    local commonG = rsG:FindFirstChild("Common")
    local cfgG = commonG and commonG:FindFirstChild("config")
    local mCfg = cfgG and cfgG:FindFirstChild("seed-config")
    local mGrow = cfgG and cfgG:FindFirstChild("seed-weight-growth-config")
    local growMod = nil
    if mGrow then pcall(function() growMod = require(mGrow) end) end
    if not mCfg then return end
    local cfg = require(mCfg)
    local seeds = nil
    if type(cfg) == "table" then
        if type(cfg.SEEDS) == "table" then
            seeds = cfg.SEEDS
        else
            for _, v in pairs(cfg) do
                if type(v) == "table" and v.displayName then
                    seeds = cfg
                    break
                end
            end
            if not seeds then seeds = cfg end
        end
    end
    if type(seeds) ~= "table" then return end
    for id, e in pairs(seeds) do
        if type(e) == "table" and e.growthProfile ~= nil then
            local gp = e.growthProfile
            if type(gp) == "string" and growMod
                and type(growMod.growthProfile) == "function" then
                pcall(function() gp = growMod.growthProfile(gp) end)
            end
            if type(gp) == "table" then
                local dur = gp.totalSeconds or gp.growSeconds
                    or gp.durationSeconds or gp.duration or gp.growTime
                    or gp.totalTime or gp.seconds or gp.time
                if type(dur) ~= "number" then
                    for k, v in pairs(gp) do
                        local kl = tostring(k):lower()
                        if type(v) == "number" and v >= 5 and v <= 604800
                            and (kl:find("time") or kl:find("second")
                                or kl:find("dur")) then
                            dur = v
                            break
                        end
                    end
                end
                if type(dur) == "number" and dur > 0 then
                    psGrowthSecs[id] = dur
                end
            end
        end
    end
end)
local psGrowthCount = 0
for _ in pairs(psGrowthSecs) do psGrowthCount += 1 end
print("[PlantSeed] growth config: " .. psGrowthCount
    .. " seed durations resolved")
selfReport.growth = psGrowthCount .. " seed durations"

-- stackKey = seedId|biomeId|rarity|size||weightKg
local function seedInfoFor(seed)
    local parts = string.split(seed.stackKey or "", "|")
    return {
        seedId = parts[1] ~= "" and parts[1] or nil,
        tier = parts[3] ~= "" and parts[3] or nil,
        size = parts[4] ~= "" and parts[4] or nil,
        weightKg = tonumber(parts[6]),
    }
end

local function newSeedRadius(seed)
    if placementCfg and placementCfg.seedFootprintRadius then
        local ok, r = pcall(function()
            return placementCfg.seedFootprintRadius(seedInfoFor(seed))
        end)
        if ok and type(r) == "number" and r > 0 then return r end
    end
    return NEW_SEED_R
end
local MAX_PLANTS = 10 -- server plot cap (LimitReached) -- conservative footprint for the seed being planted

local function getSoil()
    local map = workspace:FindFirstChild("Map")
    local pens = map and map:FindFirstChild("Pens")
    if not pens then return nil end
    local pen = nil
    -- 1. own pen via AssignedPenCenter attribute
    local okC, c = pcall(function()
        return player:GetAttribute("AssignedPenCenter")
            or (player.Character and player.Character:GetAttribute("AssignedPenCenter"))
    end)
    if okC and typeof(c) == "Vector3" then
        for _, p in ipairs(pens:GetChildren()) do
            if p:IsA("Model") then
                local pp = nil
                pcall(function() pp = p:GetPivot().Position end)
                if pp and (pp - c).Magnitude < 15 then pen = p break end
            end
        end
    end
    -- 2. fallback: OwnerUserId / PenOwnerName markers
    if not pen then
        for _, p in ipairs(pens:GetChildren()) do
            if p:IsA("Model") and (p:GetAttribute("OwnerUserId") == player.UserId
                or p:GetAttribute("PenOwnerName") == player.DisplayName) then
                pen = p
                break
            end
        end
    end
    -- 3. fallback: the pen the character is standing in
    if not pen and player.Character then
        local root = player.Character:FindFirstChild("HumanoidRootPart")
        if root then
            local pos = root.Position
            for _, p in ipairs(pens:GetChildren()) do
                if p:IsA("Model") then
                    local pp = nil
                    pcall(function() pp = p:GetPivot().Position end)
                    if pp and math.abs(pos.X - pp.X) < 26 and math.abs(pos.Z - pp.Z) < 46 then
                        pen = p
                        print("[PlantSeed] soil: using pen under character: " .. p.Name)
                        break
                    end
                end
            end
        end
    end
    if not pen then
        print("[PlantSeed] soil FAIL: AssignedPenCenter=" .. tostring(c) ..
            " displayName=" .. tostring(player.DisplayName))
        for _, p in ipairs(pens:GetChildren()) do
            if p:IsA("Model") then
                local al = {}
                pcall(function()
                    for k, v in pairs(p:GetAttributes()) do
                        al[#al + 1] = k .. "=" .. tostring(v):sub(1, 24)
                    end
                end)
                print("[PlantSeed] pen " .. p.Name .. " attrs: " .. table.concat(al, ", "))
            end
        end
        return nil
    end
    local soil = pen:FindFirstChild("PlantableSoil", true)
    if not (soil and soil:IsA("BasePart")) then return nil end
    local sz = soil.Size
    local s = {
        part = soil, pen = pen,
        center = soil.Position,
        halfWidth = sz.X / 2, halfLength = sz.Z / 2,
        surfaceY = soil.Position.Y + sz.Y / 2,
    }
    -- doorway: 12-wide door; assume centered on the +Z (corridor-facing) edge
    -- unless a door part is found in the pen model
    local doorPart = nil
    for _, d in ipairs(pen:GetDescendants()) do
        if d:IsA("BasePart") and d.Name:lower():find("door") then doorPart = d break end
    end
    if doorPart then
        local lp = doorPart.Position - s.center
        s.doorway = { halfWidth = doorPart.Size.X / 2, depth = 8, edgeZ = lp.Z, found = true }
        print(string.format("[PlantSeed] door part found at localZ=%.1f", lp.Z))
    else
        s.doorway = { halfWidth = 6, depth = 8, edgeZ = s.halfLength, found = false }
        print("[PlantSeed] no door part found - assuming 12-wide door on +Z edge")
    end
    print(string.format("[PlantSeed] soil: %s halfW=%.1f halfL=%.1f", pen.Name, s.halfWidth, s.halfLength))
    -- teleport to plot center before planting (Daniel's ask, v2.9)
    pcall(function()
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            hrp.CFrame = CFrame.new(s.center.X, s.center.Y + 6, s.center.Z)
            print("[PlantSeed] teleported to plot center")
        end
    end)
    task.wait(0.5)
    return s
end

local function getExistingPlants(soil)
    local out = {}
    local map = workspace:FindFirstChild("Map")
    local pens = map and map:FindFirstChild("Pens")
    if not pens then return out end
    for _, m in ipairs(pens:GetChildren()) do
        if m.Name:sub(1, 8) == "Planted_" and m:IsA("Model") then
            local p = nil
            pcall(function() p = m:GetPivot().Position end)
            if p then
                local lx = p.X - soil.center.X
                local lz = p.Z - soil.center.Z
                -- only plants inside MY soil (not the whole server's)
                if math.abs(lx) <= soil.halfWidth and math.abs(lz) <= soil.halfLength then
                    local bb = nil
                    pcall(function() local _, sz = m:GetBoundingBox() bb = sz end)
                    local r = 2
                    if bb then r = math.clamp(math.max(bb.X, bb.Z) / 2, MIN_R, MAX_R) end
                    -- the server reserves the plant's GROWN footprint, not
                    -- today's bounding box - ask the game when we know the
                    -- plant's seed id
                    if placementCfg and placementCfg.reservedSeedFootprintRadius then
                        local sid = nil
                        pcall(function() sid = m:GetAttribute("SeedId") end)
                        if sid and sid ~= "" then
                            local okR, rr = pcall(function()
                                return placementCfg.reservedSeedFootprintRadius(
                                    { seedId = sid }, r)
                            end)
                            if okR and type(rr) == "number" and rr > 0 then
                                r = rr
                            end
                        end
                    end
                    table.insert(out, { lx = lx, lz = lz, radius = r })
                end
            end
        end
    end
    print("[PlantSeed] existing plants: " .. #out)
    return out
end

-- port of validatePlacement: "Ok" | "OutsideSoil" | "BlocksDoorway" | "Overlap" | "InvalidPosition"
local function validateSpot(lx, lz, radius, plants, soil)
    if placementMod and placementMod.validatePlacement then
        local dw = soil.doorway
        local doorPlusZ = (not dw) or (not dw.found) or ((dw.edgeZ or 0) >= 0)
        if doorPlusZ then
            local ok, verdict = pcall(function()
                local area = {
                    halfWidth = soil.halfWidth,
                    halfLength = soil.halfLength,
                }
                if dw and dw.depth and dw.halfWidth then
                    area.doorway = { depth = dw.depth, halfWidth = dw.halfWidth }
                end
                local existing = {}
                for _, pl in ipairs(plants) do
                    table.insert(existing, {
                        localX = pl.lx, localZ = pl.lz, radius = pl.radius,
                    })
                end
                return placementMod.validatePlacement(area,
                    { localX = lx, localZ = lz, radius = radius }, existing, nil)
            end)
            if ok and type(verdict) == "string" then return verdict end
        end
    end
    if type(lx) ~= "number" or type(lz) ~= "number" or lx ~= lx or lz ~= lz then
        return "InvalidPosition"
    end
    if type(radius) ~= "number" or radius <= 0 then return "InvalidPosition" end
    local maxX = soil.halfWidth - (radius + EDGE_MARGIN)
    local maxZ = soil.halfLength - (radius + EDGE_MARGIN)
    if maxX <= 0 or maxZ <= 0 then return "OutsideSoil" end
    if math.abs(lx) > maxX or math.abs(lz) > maxZ then return "OutsideSoil" end
    local dw = soil.doorway
    if dw then
        local edge = dw.found and dw.edgeZ or soil.halfLength
        local cx = math.clamp(lx, -dw.halfWidth, dw.halfWidth)
        local cz = math.clamp(lz, edge - dw.depth, edge)
        local dx, dz = lx - cx, lz - cz
        if dx * dx + dz * dz < radius * radius then return "BlocksDoorway" end
    end
    for _, pl in ipairs(plants) do
        local rr = (pl.radius and pl.radius > 0) and pl.radius or MIN_R
        local need = radius + rr
        local dx, dz = lx - pl.lx, lz - pl.lz
        if dx * dx + dz * dz < need * need then return "Overlap" end
    end
    return "Ok"
end

local function findPlantSpots(soil, plants, maxN, radius)
    radius = radius or NEW_SEED_R
    local spots = {}
    local step, inset = 4, 4
    local lx = -soil.halfWidth + inset
    while lx <= soil.halfWidth - inset do
        local lz = -soil.halfLength + inset
        while lz <= soil.halfLength - inset do
            if validateSpot(lx, lz, radius, plants, soil) == "Ok" then
                table.insert(spots, { x = soil.center.X + lx, z = soil.center.Z + lz, lx = lx, lz = lz })
                if #spots >= (maxN or 40) then return spots end
            end
            lz += step
        end
        lx += step
    end
    return spots
end

-- the server rejects plants from outside your own plot ("TooFarAway")
local function ensureInPlot(soil)
    local root = getRoot()
    if not root then return false end
    local p = root.Position
    if math.abs(p.X - soil.center.X) <= soil.halfWidth
        and math.abs(p.Z - soil.center.Z) <= soil.halfLength then
        return true
    end
    root.CFrame = CFrame.new(soil.center + Vector3.new(0, 3, 0))
    task.wait(0.5)
    return true
end

-- the confirmed flow: equip, wait, plant - then VERIFY a Planted_ model
-- really appeared near the spot (planted crops live under Map.Pens)
local lastPlantFire = 0
local function plantOne(seed, soil, plants)
    if not seed.uid then return false end
    if not equipRemote or not plantRemote then return false end
    if not ensureInPlot(soil) then return false end
    local seedR = newSeedRadius(seed)
    local spots = findPlantSpots(soil, plants, 12, seedR)
    if #spots == 0 then
        print("[PlantSeed] no valid spot - soil full or blocked")
        return false
    end
    print("[PlantSeed] " .. #spots .. " valid spots for " .. seed.name
        .. " (footprint r=" .. string.format("%.2f", seedR) .. ")")
    local pens = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Pens")
    for _, spot in ipairs(spots) do
        local before = {}
        if pens then for _, m in ipairs(pens:GetChildren()) do before[m.Name] = true end end
        -- rate limit: RequestPlantSeed allows 4/sec
        local dt = os.clock() - lastPlantFire
        if dt < 0.3 then task.wait(0.3 - dt) end
        local ok1 = pcall(function() equipRemote:FireServer(seed.uid) end)
        if not ok1 then print("[PlantSeed] equip fire failed for " .. seed.name) return false end
        task.wait(0.5)
        lastPlantFire = os.clock()
        -- SOIL-LOCAL coords (sniff-confirmed): validator reads localX/localZ
        local ok2 = pcall(function() plantRemote:FireServer(seed.uid, spot.lx, spot.lz) end)
        if not ok2 then print("[PlantSeed] plant fire failed for " .. seed.name) return false end
        local verified = false
        local deadline = os.clock() + 3
        while os.clock() < deadline do
            if pens then
                for _, m in ipairs(pens:GetChildren()) do
                    if m.Name:sub(1, 8) == "Planted_" and not before[m.Name] then
                        local p = nil
                        pcall(function() p = m:GetPivot().Position end)
                        local hasSoil = m:FindFirstChild("Soil", true) ~= nil
                        if p and math.abs(p.X - spot.x) < 10 and math.abs(p.Z - spot.z) < 10 and hasSoil then
                            print("[PlantSeed] VERIFIED planted: " .. seed.name .. " (" .. m.Name .. ")")
                            verified = true
                            break
                        end
                    end
                end
            end
            if verified then break end
            task.wait(0.3)
        end
        if verified then
            table.insert(plants, { lx = spot.lx, lz = spot.lz, radius = seedR })
            return true
        end
        print(string.format("[PlantSeed] spot (%d,%d) rejected - trying next",
            math.floor(spot.x), math.floor(spot.z)))
    end
    print("[PlantSeed] NOT VERIFIED: " .. seed.name .. " - spots were valid, uid is likely wrong (use SNIFF)")
    return false
end

-- LEARN mode: click each seed in the inventory grid once; the hook below
-- pairs the game's own RequestEquipSeed uid to that stackKey.
local learnOn = false
local lastClickedKey = nil
local function hookGridClicks()
    local pg = player:FindFirstChild("PlayerGui")
    local grid = nil
    pcall(function() grid = pg.ClientAppRoot.InventoryPanel.Window.Body.Content.Grid end)
    if not grid then return end
    for _, item in ipairs(grid:GetChildren()) do
        if item:IsA("GuiObject") and item.Name:find("|") then
            local hooked = false
            pcall(function() hooked = item:GetAttribute("PSLearnHooked") end)
            if not hooked then
                pcall(function() item:SetAttribute("PSLearnHooked", true) end)
                pcall(function()
                    item.InputBegan:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1
                            or input.UserInputType == Enum.UserInputType.Touch then
                            lastClickedKey = item.Name
                            if learnOn then
                                print("[PlantSeed] LEARN clicked: " .. item.Name:sub(1, 32) .. "...")
                            end
                        end
                    end)
                end)
            end
        end
    end
end

-- ground-truth sniffer: shows the game's OWN equip/plant calls
local sniffOn = false
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    if (sniffOn or learnOn) and getnamecallmethod() == "FireServer" and (self == equipRemote or self == plantRemote or self == growSeedRemote or self == growAllRemote) then
        if learnOn and self == equipRemote then
            local uid = ...
            if type(uid) == "string" and findGuid(uid) then
                local key = lastClickedKey
                lastClickedKey = nil
                if key then
                    learnedUids[key] = uid
                    print("[PlantSeed] LEARN paired: " .. key:sub(1, 28) .. "... -> " .. uid:sub(1, 8) .. " (hit SCAN to apply)")
                else
                    print("[PlantSeed] LEARN saw a uid but no grid click - click the seed first")
                end
            end
        end
        local parts = {}
        for i, a in ipairs({ ... }) do parts[i] = tostring(a) end
        print("[PlantSeed] SNIFF " .. self.Name .. "(" .. table.concat(parts, ", ") .. ")")
    end
    return oldNamecall(self, ...)
end))

    -- ---- merged GUI plumbing (Rayfield tab replaces the v3.6 window) ----
    local mySeeds = {}
    local psSelectedSeed = nil
    local psSeedByText = {}
    local psDropdown = nil
    local psStatus = nil
    local psCropsLabel = nil
    local psSoilCache = nil

    local function psSetStatus(s)
        print("[PlantSeed] " .. tostring(s))
        if psStatus then pcall(function() psStatus:Set(tostring(s)) end) end
    end

    local function refreshList()
        local opts = {}
        psSeedByText = {}
        for _, s in ipairs(mySeeds) do
            local t = s.uid and s.name or (s.name .. " (no uid)")
            if psSeedByText[t] then
                t = t .. " · " .. (s.stackKey or ""):sub(1, 12)
            end
            opts[#opts + 1] = t
            psSeedByText[t] = s
        end
        if #opts == 0 then opts = { "— no seeds scanned —" } end
        if psDropdown then
            pcall(function() psDropdown:Refresh(opts) end)
        end
    end

    local function plantAllSeeds()
        local soil = getSoil()
        if not soil then psSetStatus("Own pen/soil not found!") return end
        psSoilCache = soil
        local seeds = scanSeeds()
        if #seeds == 0 then psSetStatus("Open the seed inventory first") return end
        local plants = getExistingPlants(soil)
        local free = MAX_PLANTS - #plants
        if free <= 0 then
            psSetStatus("Plot full (" .. #plants .. "/" .. MAX_PLANTS
                .. ") - harvest, then AUTO again")
            print("[PlantSeed] plot full (" .. #plants .. "/" .. MAX_PLANTS
                .. ") - stopping")
            return
        end
        local plantable = {}
        for _, s in ipairs(seeds) do
            if s.uid then plantable[#plantable + 1] = s end
        end
        if #plantable == 0 then
            psSetStatus("No plantable seeds - try LEARN")
            return
        end
        while #plantable > free do table.remove(plantable) end
        psSetStatus("Planting " .. #plantable .. " seeds (" .. #plants
            .. "/" .. MAX_PLANTS .. " used)...")
        local planted = 0
        for _, s in ipairs(plantable) do
            if plantOne(s, soil, plants) then planted += 1 end
            task.wait(0.3)
        end
        psSetStatus("Done: planted " .. planted .. "/" .. #plantable
            .. " (plot " .. (#plants + planted) .. "/" .. MAX_PLANTS .. ")")
        mySeeds = scanSeeds()
        refreshList()
    end

    -- HARVEST PROBE (v10.87): dumps his planted crops' attributes + grow
    -- prompt shape, then watches attribute changes for 30s - the ground
    -- truth a future auto-harvest/replant gets built from, captured first.
    local function harvestProbe()
        local soil = getSoil()
        if not soil then psSetStatus("Own pen/soil not found!") return end
        psSoilCache = soil
        local map = workspace:FindFirstChild("Map")
        local pens = map and map:FindFirstChild("Pens")
        if not pens then psSetStatus("Pens not found") return end
        local mine = {}
        for _, m in ipairs(pens:GetChildren()) do
            if m.Name:sub(1, 8) == "Planted_" and m:IsA("Model") then
                local p = nil
                pcall(function() p = m:GetPivot().Position end)
                if p and math.abs(p.X - soil.center.X) <= soil.halfWidth
                    and math.abs(p.Z - soil.center.Z) <= soil.halfLength then
                    mine[#mine + 1] = m
                end
            end
        end
        print("[PlantSeed] HARVEST PROBE: " .. #mine
            .. " planted crops in your plot")
        for _, m in ipairs(mine) do
            local attrs = {}
            pcall(function()
                for k, v in pairs(m:GetAttributes()) do
                    attrs[#attrs + 1] = k .. "=" .. tostring(v):sub(1, 30)
                end
            end)
            print("[PlantSeed]  " .. m.Name .. " attrs: "
                .. table.concat(attrs, ", "))
            local prompt = m:FindFirstChild("GrowPrompt", true)
            if prompt and prompt:IsA("ProximityPrompt") then
                print("[PlantSeed]  " .. m.Name .. " GrowPrompt: action='"
                    .. tostring(prompt.ActionText) .. "' object='"
                    .. tostring(prompt.ObjectText) .. "' hold="
                    .. tostring(prompt.HoldDuration) .. " enabled="
                    .. tostring(prompt.Enabled) .. " maxDist="
                    .. tostring(prompt.MaxActivationDistance))
            else
                print("[PlantSeed]  " .. m.Name .. " GrowPrompt: none found")
            end
        end
        psSetStatus("Probe: " .. #mine
            .. " crops dumped - watching changes 30s")
        task.spawn(function()
            local conns = {}
            for _, m in ipairs(mine) do
                conns[#conns + 1] = m.AttributeChanged:Connect(function(attr)
                    local v = nil
                    pcall(function() v = m:GetAttribute(attr) end)
                    print("[PlantSeed] probe change: " .. m.Name .. " "
                        .. attr .. " -> " .. tostring(v))
                end)
            end
            task.wait(30)
            for _, c in ipairs(conns) do
                pcall(function() c:Disconnect() end)
            end
            print("[PlantSeed] HARVEST PROBE done")
        end)
    end

    -- crop timers (v10.88): a Plant-tab label listing his planted crops.
    -- Any ReadyAt-style epoch attribute the game puts on a crop model
    -- becomes a live countdown; until the HARVEST PROBE shows which
    -- attributes exist, the list is names/count only. Uses the CACHED
    -- soil (getSoil teleports on every call - never call it on a timer).
    local function psMyCropModels(soil)
        local out = {}
        local map = workspace:FindFirstChild("Map")
        local pens = map and map:FindFirstChild("Pens")
        if not pens then return out end
        for _, m in ipairs(pens:GetChildren()) do
            if m.Name:sub(1, 8) == "Planted_" and m:IsA("Model") then
                local p = nil
                pcall(function() p = m:GetPivot().Position end)
                if p and math.abs(p.X - soil.center.X) <= soil.halfWidth
                    and math.abs(p.Z - soil.center.Z) <= soil.halfLength then
                    out[#out + 1] = m
                end
            end
        end
        return out
    end

    task.spawn(function()
        task.wait(12)
        while true do
            pcall(function()
                if psCropsLabel and psSoilCache then
                    local crops = psMyCropModels(psSoilCache)
                    if #crops == 0 then
                        psCropsLabel:Set("🌾 Crops: none planted")
                    else
                        local now = workspace:GetServerTimeNow()
                        local lines = { "🌾 Crops: " .. #crops }
                        for i, m in ipairs(crops) do
                            if i > 6 then
                                lines[#lines + 1] = "· +"
                                    .. (#crops - 6) .. " more"
                                break
                            end
                            local nm = nil
                            pcall(function()
                                nm = m:GetAttribute("SeedName")
                                    or m:GetAttribute("SeedId")
                            end)
                            local extra = ""
                            pcall(function()
                                for k, v in pairs(m:GetAttributes()) do
                                    local kl = k:lower()
                                    if type(v) == "number" and v > 1e9
                                        and (kl:find("ready")
                                            or kl:find("matur")
                                            or kl:find("harvest")
                                            or kl:find("grow")) then
                                        local left = v - now
                                        if left > 0 then
                                            extra = string.format(
                                                " · ready in %d:%02d",
                                                math.floor(left / 60),
                                                math.floor(left % 60))
                                        else
                                            extra = " · READY"
                                        end
                                    end
                                end
                            end)
                            if extra == "" then
                                pcall(function()
                                    local sid = m:GetAttribute("SeedId")
                                    local plantedAt = nil
                                    for k, v in pairs(m:GetAttributes()) do
                                        local kl = k:lower()
                                        if type(v) == "number" and v > 1e9
                                            and (kl:find("planted")
                                                or kl:find("start")
                                                or kl:find("since")) then
                                            plantedAt = v
                                        end
                                    end
                                    local dur = sid and psGrowthSecs[sid]
                                    if plantedAt and dur then
                                        local left = plantedAt + dur - now
                                        if left > 0 then
                                            extra = string.format(
                                                " · ready in %d:%02d (est)",
                                                math.floor(left / 60),
                                                math.floor(left % 60))
                                        else
                                            extra = " · READY (est)"
                                        end
                                    end
                                end)
                            end
                            lines[#lines + 1] = "· "
                                .. tostring(nm or m.Name) .. extra
                        end
                        psCropsLabel:Set(table.concat(lines, "\n"))
                    end
                end
            end)
            task.wait(10)
        end
    end)

    local PlantTab = Window:CreateTab("🌱 Plant", 4483362458)
    PlantTab:CreateSection("Plant Seeds")
    psStatus = PlantTab:CreateLabel("Open seed inventory, then SCAN.")
    psCropsLabel = PlantTab:CreateLabel(
        "🌾 Crops: plant or probe once to locate your plot")

    PlantTab:CreateButton({
        Name = "🔍 SCAN SEEDS",
        Callback = function()
            hookGridClicks()
            mySeeds = scanSeeds()
            refreshList()
            local plantable = 0
            for _, s in ipairs(mySeeds) do
                if s.uid then plantable += 1 end
            end
            psSetStatus(#mySeeds .. " seeds, " .. plantable .. " plantable")
        end,
    })

    psDropdown = PlantTab:CreateDropdown({
        Name = "Seed",
        Options = { "— no seeds scanned —" },
        CurrentOption = { "— no seeds scanned —" },
        MultipleOptions = false,
        Callback = function(Options)
            local t = type(Options) == "table" and Options[1] or Options
            psSelectedSeed = t and psSeedByText[t] or nil
            if psSelectedSeed then
                psSetStatus("Selected: " .. psSelectedSeed.name)
            end
        end,
    })

    PlantTab:CreateButton({
        Name = "🌱 PLANT SELECTED",
        Callback = function()
            if not psSelectedSeed then
                psSetStatus("Pick a seed from the list first")
                return
            end
            local soil = getSoil()
            if not soil then psSetStatus("Own pen/soil not found!") return end
            psSoilCache = soil
            local plants = getExistingPlants(soil)
            if #plants >= MAX_PLANTS then
                psSetStatus("Plot full (" .. MAX_PLANTS .. "/" .. MAX_PLANTS .. ")")
                return
            end
            if plantOne(psSelectedSeed, soil, plants) then
                psSetStatus("Planted " .. psSelectedSeed.name)
                task.wait(0.3)
                mySeeds = scanSeeds()
                refreshList()
            else
                psSetStatus("Plant failed - see console")
            end
        end,
    })

    PlantTab:CreateButton({
        Name = "🚀 AUTO: SCAN + PLANT ALL",
        Callback = function()
            psSetStatus("Opening inventory...")
            if not openSeedInventory() then
                psSetStatus("Tap the backpack icon yourself, then hit AUTO")
                return
            end
            hookGridClicks()
            task.wait(1.5) -- inventory state populates for the uid hunt
            plantAllSeeds()
        end,
    })

    PlantTab:CreateButton({
        Name = "🌱 PLANT ALL",
        Callback = function() plantAllSeeds() end,
    })


    -- AUTO-GROW (v10.93): RequestGrowAllSeeds() takes NO arguments -
    -- SNIFF capture Oct 23 2026 (Daniel fired Grow All by hand and the
    -- hook logged an empty call). While ON, fires it every 30s whenever
    -- he has crops in the ground. Whether the game charges anything per
    -- grow is unknown, so: starts OFF, first fire prints once, the
    -- 30s loop stays silent after that.
    local psAutoGrow = false
    local psGrowFiredOnce = false
    PlantTab:CreateToggle({
        Name = "🌱 AUTO-GROW",
        CurrentValue = false,
        Callback = function(v)
            psAutoGrow = v
            psSetStatus(v and "Auto-grow ON (Grow All every 30s)"
                or "Auto-grow off")
        end,
    })
    task.spawn(function()
        while true do
            task.wait(30)
            if psAutoGrow then
                pcall(function()
                    local soil = psSoilCache
                    if not soil then
                        soil = getSoil()
                        if soil then psSoilCache = soil end
                    end
                    if not soil then return end
                    local crops = psMyCropModels(soil)
                    if #crops > 0 and growAllRemote then
                        growAllRemote:FireServer()
                        if not psGrowFiredOnce then
                            psGrowFiredOnce = true
                            print("[PlantSeed] auto-grow: fired "
                                .. "RequestGrowAllSeeds() for " .. #crops
                                .. " crops (repeats silently every 30s "
                                .. "while ON)")
                        end
                    end
                end)
            end
        end
    end)

    -- Equip Best Pet (moved here from the removed Grow & Pet tab,
    -- v10.98): same Flag, so its saved on/off state carries over; the
    -- engine loop lives in the main chunk (fires RequestFillBest)
    PlantTab:CreateSection("Pet")
    PlantTab:CreateToggle({
        Name = "Equip Best Pet",
        Flag = "EquipBest",
        CurrentValue = false,
        Callback = function(v)
            equipOn = v
            print("[SeedFarm] equip best pet " .. (v and "ON" or "OFF"))
        end,
    })

    print("[PlantSeed] merged into Seed Farm - Plant tab ready")
end

plantSeedInit()

local SettingsTab = Window:CreateTab("⚙️ Settings", 4483362458)
SettingsTab:CreateSection("Session")
-- Anti-AFK lives here now (moved from the Farm tab)
SettingsTab:CreateToggle({
    Name = "AFK (Anti-AFK)",
    Flag = "AntiAFK",
    CurrentValue = false,
    Callback = function(v)
        afkEnabled = v
        print("[SeedFarm] anti-AFK " .. (v and "ON" or "OFF"))
    end,
})
SettingsTab:CreateToggle({
    Name = "Noclip",
    Flag = "Noclip",
    CurrentValue = false,
    Callback = function(v)
        noclipEnabled = v
        print("[SeedFarm] noclip " .. (v and "ON" or "OFF"))
    end,
})
SettingsTab:CreateToggle({
    Name = "Inf Jump",
    Flag = "InfJump",
    CurrentValue = false,
    Callback = function(v)
        infJumpEnabled = v
        print("[SeedFarm] inf jump " .. (v and "ON" or "OFF"))
    end,
})
-- Auto Rejoin: when ON, a disconnect/kick error prompt triggers an
-- instant rejoin into the SAME server (toggle, so it can be turned off)
local autoRejoinOn = false
SettingsTab:CreateToggle({
    Name = "Auto Rejoin",
    Flag = "AutoRejoin",
    CurrentValue = false,
    Callback = function(v)
        autoRejoinOn = v
        print("[SeedFarm] auto rejoin " .. (v and "ON" or "OFF"))
    end,
})
task.spawn(function()
    local pgui = game:GetService("CoreGui"):WaitForChild("RobloxPromptGui", 30)
    local overlay = pgui and pgui:WaitForChild("promptOverlay", 30)
    if overlay then
        overlay.ChildAdded:Connect(function(child)
            if autoRejoinOn and stillAlive() and child.Name == "ErrorPrompt" then
                print("[SeedFarm] disconnect detected - auto rejoining same server")
                pcall(function()
                    game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
                end)
            end
        end)
        print("[SeedFarm] auto rejoin watcher ready")
    end
end)

SettingsTab:CreateSection("Server")
-- Hop Server: pick a random non-full public server (emptiest first page)
-- that isn't this one and teleport to it
SettingsTab:CreateButton({
    Name = "🔀 Hop Server",
    Callback = function()
        setStatus("Hopping server...")
        local ok, err = pcall(function()
            local HttpService = game:GetService("HttpService")
            local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
            local data = HttpService:JSONDecode(game:HttpGet(url))
            local candidates = {}
            for _, s in ipairs(data.data or {}) do
                if s.id and s.id ~= game.JobId and (s.maxPlayers or 0) - (s.playing or 0) > 0 then
                    table.insert(candidates, s.id)
                end
            end
            if #candidates == 0 then error("no other server available") end
            local target = candidates[math.random(1, #candidates)]
            print("[SeedFarm] hopping to server " .. target)
            game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, target, LocalPlayer)
        end)
        if not ok then
            setStatus("Hop failed - tap again")
            print("[SeedFarm] hop failed: " .. tostring(err))
        end
    end,
})

SettingsTab:CreateSection("Appearance")
SettingsTab:CreateDropdown({
    Name = "Theme",
    Flag = "Theme",
    Options = { "Default", "Green", "DarkBlue", "Amethyst", "Bloom", "Ocean", "Serenity", "AmberGlow", "Light" },
    CurrentOption = { getgenv().__SeedFarmTheme or "Green" },
    MultipleOptions = false,
    Callback = function(Options)
        local name = type(Options) == "table" and Options[1] or Options
        if name and not VALID_THEMES[name] then
            print("[SeedFarm] ignoring unknown theme: " .. tostring(name))
            name = nil
        end
        if name then
            local ok, err = pcall(function() Window.ModifyTheme(name) end)
            if ok then
                getgenv().__SeedFarmTheme = name -- remembered on re-execute
                print("[SeedFarm] theme -> " .. name)
            else
                print("[SeedFarm] theme '" .. name .. "' failed: " .. tostring(err))
            end
        end
    end,
})

SettingsTab:CreateSection("Movement")
SettingsTab:CreateSlider({
    Name = "Run Speed",
    Flag = "RunSpeed",
    Range = { 0, 500 },
    Increment = 10,
    CurrentValue = 250,
    Callback = function(v)
        RUN_SPEED = math.clamp(math.floor(v), 0, 500)
        print("[SeedFarm] run speed set to " .. RUN_SPEED)
    end,
})

local cfgOk, cfgErr = pcall(function() Rayfield:LoadConfiguration() end)
print("[SeedFarm] LoadConfiguration: " .. tostring(cfgOk) .. (cfgOk and "" or (" - " .. tostring(cfgErr))))

