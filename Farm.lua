-- Seed Farm (manual)

print("[SeedFarm] v10.72 starting...")

local Rayfield = nil
pcall(function()
    Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)
if not Rayfield then
    print("[SeedFarm] ERROR: Rayfield failed to load (internet/executor?) - old copy left running")
    return
end
print("[SeedFarm] Rayfield loaded")

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
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
}

-- Complete SeedId database from wild-seed dump (Oct 10, 2026).
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
    ["SW1_EXTRA"] = { name = "Prime Velocity Seed", tier = "T2" },
    ["SW1_FAILED"] = { name = "Failed Velocity Seed", tier = "T2" }, -- INF: inferred
    ["SW1_PERFECT"] = { name = "Perfect Velocity Seed", tier = "T2" }, -- INF: inferred
    ["SW1_REGULAR"] = { name = "Velocity Seed", tier = "T1" },
    ["SW2_EXTRA"] = { name = "Prime Overdrive Seed", tier = "T2" }, -- INF: inferred
    ["SW2_FAILED"] = { name = "Failed Overdrive Seed", tier = "T2" }, -- INF: inferred
    ["SW2_PERFECT"] = { name = "Perfect Overdrive Seed", tier = "T2" }, -- INF: inferred
    ["SW2_REGULAR"] = { name = "Overdrive Seed", tier = "T1" },
    ["SW3_EXTRA"] = { name = "Prime Hyper Seed", tier = "T2" },
    ["SW3_FAILED"] = { name = "Failed Hyper Seed", tier = "T2" }, -- INF: inferred
    ["SW3_PERFECT"] = { name = "Perfect Hyper Seed", tier = "T2" }, -- INF: inferred
    ["SW3_REGULAR"] = { name = "Hyper Seed", tier = "T1" },
    ["SW4_EXTRA"] = { name = "Prime Glitched Seed", tier = "T2" }, -- INF: inferred
    ["SW4_FAILED"] = { name = "Failed Glitched Seed", tier = "T2" },
    ["SW4_PERFECT"] = { name = "Perfect Glitched Seed", tier = "T2" }, -- INF: inferred
    ["SW4_REGULAR"] = { name = "Glitched Seed", tier = "T1" },
    ["SW5_EXTRA"] = { name = "Prime Hacked Seed", tier = "T2" }, -- INF: inferred
    ["SW5_FAILED"] = { name = "Failed Hacked Seed", tier = "T2" },
    ["SW5_PERFECT"] = { name = "Perfect Hacked Seed", tier = "T2" }, -- INF: inferred
    ["SW5_REGULAR"] = { name = "Hacked Seed", tier = "T1" },
}

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
    local isHalloween = source == "halloween" or HALLOWEEN_SEED_IDS[seedId] or HALLOWEEN_SEED_IDS[p.Name]
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
        source = isBlackHole and "blackhole" or "sweep",
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
                        if n7 <= 10 then
                            print(string.format("[SeedFarm] sweep found: '%s' prompt='%s' at %s",
                                data.name, prompt.ActionText, prompt:GetFullName()))
                        end
                    end
                end
            end
        end
        print(string.format("[SeedFarm] scan: wild=%d bh=%d mutant=%d core=%d+%d abyssal=%d codex=%d halloween=%d sweep=%d total=%d",
            n1, n2, n3, n4, n4b, n5, n6, n6b, n7, #seeds))
        -- tier breakdown for debugging
        local tiers = {}
        for _, s in ipairs(seeds) do
            tiers[s.tierStr] = (tiers[s.tierStr] or 0) + 1
        end
        local tstr = {}
        for t, n in pairs(tiers) do table.insert(tstr, t .. "=" .. n) end
        print("[SeedFarm] tiers: " .. table.concat(tstr, " "))
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
    root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
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
        -- run target: pin if set, otherwise the default safe zone
        local target = pinPos or SAFE_ZONE
        local dist = (root.Position - target).Magnitude
        print(string.format("[SeedFarm] runback start: dist=%.0f", dist))
        -- move on the very first frame: speed up, hop to unstick, go
        pcall(function() humanoid.WalkSpeed = RUN_SPEED end)
        pcall(function() humanoid.Jump = true end)
        humanoid:MoveTo(target)
        local lastPos = root.Position
        local startTime = os.clock()
        local lastLog = 0
        local TIMEOUT = 90
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
                -- guardian detour
                local moveTarget = target
                local g, gDist = nearestGuardian(root.Position)
                if g and gDist < 8 then
                    local awayDir = Vector3.new(root.Position.X - g.pos.X, 0, root.Position.Z - g.pos.Z)
                    if awayDir.Magnitude < 0.1 then awayDir = Vector3.new(1, 0, 0) end
                    awayDir = awayDir.Unit
                    local toSafe = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
                    if toSafe.Magnitude > 0.1 then toSafe = toSafe.Unit else toSafe = Vector3.new(0,0,0) end
                    local detourDir = (awayDir * 0.7 + toSafe * 0.3)
                    if detourDir.Magnitude < 0.1 then detourDir = awayDir end
                    moveTarget = root.Position + detourDir.Unit * 40
                    moveTarget = Vector3.new(moveTarget.X, root.Position.Y, root.Position.Z)
                end
                if lastDeliverySeq > deliverySeqAtStart then
                    print("[SeedFarm] DELIVERY confirmed by server - seed banked, stopping run")
                    return true
                end
                if dist <= ARRIVE_DIST then
                    print("[SeedFarm] ARRIVED (within " .. ARRIVE_DIST .. "m) in " .. math.floor(elapsed) .. "s")
                    return true
                end
                if elapsed > TIMEOUT then
                    print("[SeedFarm] runback timeout")
                    return false
                end
                if (root.Position - lastPos).Magnitude < 1 then
                    humanoid.Jump = true
                end
                lastPos = root.Position
                humanoid:MoveTo(moveTarget)
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
local autoFarmMinTier = "Any"
local function setStatus(t)
    print("[SeedFarm] " .. tostring(t))
    if statusLabel then pcall(function() statusLabel:Set(t) end) end
end
local function setEggStatus(t)
    print("[SeedFarm][Egg] " .. tostring(t))
    if eggStatusLabel then pcall(function() eggStatusLabel:Set(t) end) end
end

-- Grow & Pet toggle states (the automation loops at the bottom read these)
local hatchOn = false
local equipOn = false

-- drop a stale saved theme name that this Rayfield build doesn't have
-- themes that actually exist in this Rayfield build
local VALID_THEMES = { Default = true, Green = true, DarkBlue = true, Amethyst = true, Bloom = true, Ocean = true, Serenity = true, AmberGlow = true, Light = true }
if getgenv().__SeedFarmTheme and not VALID_THEMES[getgenv().__SeedFarmTheme] then getgenv().__SeedFarmTheme = nil end

local Window = Rayfield:CreateWindow({
    Name = "🌱 Seed Farm v10.72",
    LoadingTitle = "Seed Farm v10.72",
    LoadingSubtitle = "Rayfield GUI",
    Theme = getgenv().__SeedFarmTheme or "Green",
    ToggleUIKeybind = Enum.KeyCode.RightControl,
    ConfigurationSaving = { Enabled = true, FolderName = "SeedFarm", FileName = "SeedFarmConfig" },
    DisableRayfieldPrompts = true,
    Discord = { Enabled = false },
    KeySystem = false,
})

local FarmTab = Window:CreateTab("🌱 Farm", 4483362458)
local PetTab = Window:CreateTab("🥚 Grow & Pet", 4483362458)

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
            selectedSeed = s
            setStatus("Selected: " .. s.name)
            print("[SeedFarm] selected " .. s.name .. " (" .. s.source .. (s.mutated and ", mutated" or "") .. ")")
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
    local seeds = findWildSeeds()
    print("[SeedFarm] found " .. #seeds .. " seeds")
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
    for _, s in ipairs(seeds) do
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
    if syncWorldESP then pcall(syncWorldESP, seeds) end
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
    end
end)

statusLabel = FarmTab:CreateLabel("Pick a seed to start")

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
    Callback = doTeleport,
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
FarmTab:CreateToggle({
    Name = "Full Auto Farm",
    CurrentValue = false,
    Callback = function(v)
        autoFarmOn = v
        print("[SeedFarm] full auto farm " .. (v and "ON" or "OFF"))
        if v then setStatus("Auto Farm ON - hunting " .. autoFarmMinTier) end
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

FarmTab:CreateSection("Speed")
FarmTab:CreateSlider({
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

local farmBlacklist = {} -- uid -> unblock time (after 3 failed attempts)
local farmFailCount = {}
local function farmTarget()
    local best = nil
    for _, s in ipairs(findWildSeeds()) do
        local blocked = s.uid and farmBlacklist[s.uid] and os.clock() < farmBlacklist[s.uid]
        if not blocked then
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
        if autoFarmOn and not autoFarmBusy then
            autoFarmBusy = true
            local okCycle, errCycle = pcall(function()
                local target = farmTarget()
                if not target then
                    setStatus("Auto Farm: no targets, waiting...")
                    task.wait(2)
                    return
                end
                selectedSeed = target
                if updateSeedESP then pcall(updateSeedESP) end
                setStatus("Auto Farm: going for " .. target.name)
                print("[SeedFarm] auto farm target: " .. seedDisplayText(target))
                local msg = teleportToSelected()
                setStatus(msg)
                if msg and msg:sub(1, 3) == "Got" then
                    noteCollected()
                    farmFailCount[target.uid] = nil
                    print("[SeedFarm] auto farm: carried, running back")
                    if not runbackLoopActive and not runningBack then
                        triggerRunback()
                    end
                    local waited = 0
                    while autoFarmOn and (runbackLoopActive or runningBack) and waited < 120 do
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

PetTab:CreateSection("Grow & Pet")
PetTab:CreateToggle({
    Name = "Auto Hatch (Grow All)",
    Flag = "AutoHatch",
    CurrentValue = false,
    Callback = function(v)
        hatchOn = v
        print("[SeedFarm] auto hatch " .. (v and "ON" or "OFF"))
    end,
})
PetTab:CreateToggle({
    Name = "Equip Best Pet",
    Flag = "EquipBest",
    CurrentValue = false,
    Callback = function(v)
        equipOn = v
        print("[SeedFarm] equip best pet " .. (v and "ON" or "OFF"))
    end,
})
eggStatusLabel = PetTab:CreateLabel("")

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
local cfgOk, cfgErr = pcall(function() Rayfield:LoadConfiguration() end)
print("[SeedFarm] LoadConfiguration: " .. tostring(cfgOk) .. (cfgOk and "" or (" - " .. tostring(cfgErr))))

refreshSeedList(true)
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
    else
        print("[SeedFarm] CarryStateChanged not found - inventory polling only")
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
            end
        end)
        print("[SeedFarm] InventorySeedCarryStateChanged hooked - delivery confirmation on")
    end
end)
if not hookOk then print("[SeedFarm] carry hook ERROR: " .. tostring(hookErr)) end

print("[SeedFarm] v10.72 loaded - pick a seed!")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- find remotes by name pattern
local function findRemotes(patterns)
    local found = {}
    pcall(function()
        for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
            if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                local n = obj.Name:lower()
                for _, pat in ipairs(patterns) do
                    if n:find(pat) then
                        table.insert(found, obj)
                        break
                    end
                end
            end
        end
    end)
    return found
end

-- log discovered seed/pet remotes on load (helps wire up correct args)
task.spawn(function()
    task.wait(2)
    local seedR = findRemotes({"seed"})
    local hatchR = findRemotes({"hatch", "grow"})
    local petR = findRemotes({"pet"})
    print("[SeedFarm][Egg] seed remotes (" .. #seedR .. "):")
    for _, r in ipairs(seedR) do print("  - " .. r:GetFullName()) end
    print("[SeedFarm][Egg] hatch/grow remotes (" .. #hatchR .. "):")
    for _, r in ipairs(hatchR) do print("  - " .. r:GetFullName()) end
    print("[SeedFarm][Egg] pet remotes (" .. #petR .. "):")
    for _, r in ipairs(petR) do print("  - " .. r:GetFullName()) end
    -- also look for Grow All button
    pcall(function()
        for _, obj in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
            if obj:IsA("TextButton") and obj.Text:lower():find("grow all") then
                print("[SeedFarm][Egg] Grow All button: " .. obj:GetFullName())
            end
        end
    end)
end)

-- get GlobalEvents folder
local globalEvents = nil
pcall(function()
    globalEvents = ReplicatedStorage:FindFirstChild("shared/network@GlobalEvents")
end)

local hatchFails = 0
task.spawn(function()
    while stillAlive() do
        task.wait(3)
        if hatchOn and globalEvents then
            if hatchFails >= 5 then
                setEggStatus("GrowAll paused (5 fails) - toggle off/on")
            else
                local ok = pcall(function()
                    globalEvents.RequestGrowAllSeeds:FireServer()
                end)
                if ok then
                    hatchFails = 0
                    setEggStatus("Fired RequestGrowAllSeeds")
                else
                    hatchFails += 1
                    setEggStatus("GrowAll failed (" .. hatchFails .. "/5)")
                end
            end
        else
            hatchFails = 0
        end
    end
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
