-- ============================== CONFIG ==============================
-- LOADOUT FORMAT (edit these like JSON):
-- {
--     name    = "Heavy",                 -- what the player types in chat to pick it (NO numbers)
--     morph   = "MTF",                   -- built-in morph name (from :morphs). "" = no morph
--     shirt   = "",                      -- shirt template ID via :shirt. "" = skip
--     pants   = "",                      -- pants template ID via :pants. "" = skip
--     hats    = { },                     -- accessory IDs via :hat
--     hp      = 200,                     -- max health
--     weapons = { "M4", "L3 Keycard" },  -- tools to give (exact :tools names)
--     skin    = "",                      -- optional :skin colour, "" = none
--     scale   = "",                      -- optional :scale args e.g. "1 1 1 1.2", "" = none
-- }
--
-- Keep loadout names and team names NUMBER-FREE -- the chat filter hashes digits,
-- so a name like "L3 Squad" would show and match as garbage. Use "Level Three Squad".

-- Teams and their loadouts. Key = the EXACT team name in the game.
local TEAM_LOADOUTS = {
    ["Mobile Task Force"] = {
        { name = "Assault", morph = "MTF", hp = 150, weapons = { "M4", "L3 Keycard" } },
        { name = "Heavy",   morph = "MTF", hp = 220, weapons = { "XM250" }, scale = "1 1 1 1.15" },
    },
    ["Security Department"] = {
        { name = "Standard", morph = "Security", hp = 120, weapons = { "M9", "L1 Keycard" } },
    },
}

-- Extra loadouts only specific User IDs can pick, at their OWN team's locker.
-- If their team has no loadouts, they still get these.
local ID_LOADOUTS = {
    -- [123456789] = {
    --     { name = "Commander", morph = "MTF", hp = 300, weapons = { "Minigun" } },
    -- },
}

-- Lockers in the map: interaction part name -> { team, exclusive }.
--   exclusive = false  -> REGULAR: other teams can steal from it.
--   exclusive = true   -> EXCLUSIVE: only the owning team can use it, no stealing.
local LOCKERS = {
    ["MTFLocker"]      = { team = "MTF",      exclusive = false },
    ["SecurityLocker"] = { team = "Security", exclusive = true },
}

-- ============================== STATE ==============================
local pendingChoice = {}   -- [player] = list of loadouts waiting for a chat pick

local function cmd(str)
    local ok, err = runCommand(str)
    print("[LOCKER] " .. str .. " -> ok=" .. tostring(ok) .. " err=" .. tostring(err))
end

-- ============================== APPLY ==============================
local function applyLoadout(player, lo, notice)
    -- clear inventory first
    for _, t in ipairs(getTools(player)) do removeTool(player, t) end
    -- appearance
    if lo.morph and lo.morph ~= "" then cmd(":morph " .. player .. " " .. lo.morph) end
    if lo.shirt and lo.shirt ~= "" then cmd(":shirt " .. player .. " " .. lo.shirt) end
    if lo.pants and lo.pants ~= "" then cmd(":pants " .. player .. " " .. lo.pants) end
    if lo.skin  and lo.skin  ~= "" then cmd(":skin "  .. player .. " " .. lo.skin)  end
    if lo.scale and lo.scale ~= "" then cmd(":scale " .. player .. " " .. lo.scale) end
    -- health
    if lo.hp then setPlayerMaxHealth(player, lo.hp); setPlayerHealth(player, lo.hp) end
    -- hats (accessory IDs)
    if lo.hats then for _, id in ipairs(lo.hats) do cmd(":hat " .. player .. " " .. id) end end
    -- weapons
    if lo.weapons then for _, w in ipairs(lo.weapons) do giveTool(player, w) end end
    -- one combined announcement (two in a row would clobber each other)
    announce(player, "[LOCKER] " .. (notice or "") .. "Equipped: " .. lo.name .. ".")
end

-- ============================== EVENTS ==============================
event("interaction", function(Data)
    local player = Data.Value[1]
    local part   = Data.Value[2]
    local info = LOCKERS[part]
    if not info then return end
    local lockerTeam = info.team

    local playerTeam = getTeam(player)
    local stealing = (playerTeam ~= lockerTeam)

    -- exclusive lockers cannot be used by other teams
    if stealing and info.exclusive then
        announce(player, "[LOCKER] This locker is exclusive to " .. lockerTeam .. ".", true)
        return
    end

    -- build the list of loadouts this player can get here
    local list = {}
    for _, lo in ipairs(TEAM_LOADOUTS[lockerTeam] or {}) do list[#list + 1] = lo end
    if not stealing then
        for _, lo in ipairs(ID_LOADOUTS[getUserId(player)] or {}) do list[#list + 1] = lo end
    end
    if #list == 0 then return end   -- nothing to give here

    -- the stole notice rides on the NEXT announcement (never its own, or it gets clobbered)
    local notice = stealing and ("You stole from a " .. lockerTeam .. " locker! ") or ""

    if #list == 1 then
        applyLoadout(player, list[1], notice)      -- one option -> apply now, notice included
    else
        pendingChoice[player] = list
        local names = {}
        for _, lo in ipairs(list) do names[#names + 1] = lo.name end
        announce(player, "[LOCKER] " .. notice .. "Type one of: " .. table.concat(names, ", ") .. " in chat. Check comms for info.")
    end
end)

event("chatted", function(Data)
    local player = Data.Value[1]
    local msg    = Data.Value[2]
    if type(msg) ~= "string" then return end
    local choices = pendingChoice[player]
    if not choices then return end
    local pick = string.lower(msg)
    for _, lo in ipairs(choices) do
        if string.lower(lo.name) == pick then
            pendingChoice[player] = nil
            applyLoadout(player, lo)
            return
        end
    end
end)

event("left", function(Data)
    pendingChoice[Data.Value] = nil
end)

-- ============================== STARTUP CHECK ==============================
local missing = {}
for part, _ in pairs(LOCKERS) do
    if f(part) == nil then missing[#missing + 1] = part end
end
if #missing == 0 then
    print("[LOCKER] All lockers found. :D")
else
    print("[LOCKER] Missing: " .. table.concat(missing, ", "))
end
print("[LOCKER] locker system loaded")
