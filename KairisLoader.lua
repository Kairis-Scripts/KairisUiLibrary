-- ══════════════════════════════════════════════════════════════════════════════
-- KAIRIS HUB — Universal ScriptLoader (free)
-- Only 4 games: MM2, Steal an Egg, Rivals, Grow a Chicken Fighter
-- Fully open source: everything is plain Lua on GitHub, no encryption.
--
-- FAST + STALE-PROOF:
--  * Downloads are cached for 5 minutes per session.
--  * Stale CDN copies are rejected via marker ("KairisFree").
-- ══════════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════════
-- CONFIG
-- ══════════════════════════════════════════════════════════════════════════════
local CACHE_BUST = "?cb=" .. tostring(os.time()) .. tostring(math.random(100000, 999999))

local CFG = {
    LIB_URL      = "https://raw.githubusercontent.com/Kairis-Scripts/KairisUiLibrary/refs/heads/main/KairisLib.lua" .. CACHE_BUST,
    SCRIPTS_BASE = "https://raw.githubusercontent.com/Kairis-Scripts/KairisUiLibrary/refs/heads/main/scripts/",
    FALLBACK     = "Universal.lua",
    TRACK_URL    = nil,
}

-- ══════════════════════════════════════════════════════════════════════════════
-- PLACE-ID → SCRIPT MAPPING (ONLY 4 GAMES)
-- ══════════════════════════════════════════════════════════════════════════════
local GAME_MAP = {
    [94640181989498]  = "KairisGrowAChickenFighter.lua",  -- Grow a Chicken Fighter 🐔
    [107778070777162] = "KairisStealAnEgg.lua",           -- Steal an Egg 🥚
    [142823291]       = "KairisMM2.lua",                  -- MM2 🔪
    [17625359962]     = "KairisRivals.lua",               -- RIVALS 🔫
}

-- Universe (GameId) → script (catches all places under a game)
local GAME_MAP_BY_GAMEID = {
    [6035872082] = "KairisRivals.lua",  -- RIVALS Universe
}

local function ResolveScript(pid, gid)
    return GAME_MAP[pid] or GAME_MAP_BY_GAMEID[gid] or CFG.FALLBACK
end

-- ══════════════════════════════════════════════════════════════════════════════
-- CACHE + STALE-PROTECTION
-- ══════════════════════════════════════════════════════════════════════════════
local LIB_MARKER  = "KairisFree"
local CACHE_TTL   = 300

local KAIRIS_CACHE = _G.KairisLoaderCache or {}
_G.KairisLoaderCache = KAIRIS_CACHE

local function cacheGet(key)
    local entry = KAIRIS_CACHE[key]
    if entry and os.clock() - entry.at <= CACHE_TTL then
        return entry.value
    end
    return nil
end

local function cacheSet(key, value)
    KAIRIS_CACHE[key] = { at = os.clock(), value = value }
end

-- ══════════════════════════════════════════════════════════════════════════════
-- FETCH: downloads a text file from a URL
-- ══════════════════════════════════════════════════════════════════════════════
local function FetchRaw(url)
    if type(request) == "function" then
        local ok, req = pcall(request, { Url = url, Method = "GET" })
        if ok and type(req) == "table" and req.StatusCode == 200
            and type(req.Body) == "string" and #req.Body >= 100 then
            return true, req.Body
        end
    end
    local ok, src = pcall(game.HttpGet, game, url)
    if ok and type(src) == "string" and #src >= 100 then
        return true, src
    end
    return false, nil
end

local function CacheBust(url)
    local sep = string.find(url, "?", 1, true) and "&" or "?"
    return url .. sep .. "cb=" .. tostring(os.time()) .. tostring(math.random(100000, 999999))
end

local function FetchApiRaw(apiPath)
    if type(request) ~= "function" then return false, nil end
    local ok, req = pcall(request, {
        Url = "https://api.github.com/repos/YOUR_USERNAME/YOUR_REPO/contents/" .. apiPath,
        Method = "GET",
        Headers = {
            ["Accept"]     = "application/vnd.github.raw+json",
            ["User-Agent"] = "kairis-hub",
        },
    })
    if ok and type(req) == "table" and req.StatusCode == 200
        and type(req.Body) == "string" and #req.Body >= 100 then
        return true, req.Body
    end
    return false, nil
end

local function FetchFresh(url, marker, minBytes, apiPath)
    minBytes = minBytes or 100
    for attempt = 1, 3 do
        local target = attempt == 1 and url or CacheBust(url)
        local ok, body = FetchRaw(target)
        if ok and #body >= minBytes and (marker == nil or string.find(body, marker, 1, true)) then
            return true, body, attempt
        end
        if attempt < 3 then task.wait(1) end
    end
    if apiPath then
        local ok, body = FetchApiRaw(apiPath)
        if ok and #body >= minBytes and (marker == nil or string.find(body, marker, 1, true)) then
            return true, body, 4
        end
    end
    return false, nil, 4
end

-- ══════════════════════════════════════════════════════════════════════════════
-- LOAD LIBRARY
-- ══════════════════════════════════════════════════════════════════════════════
local function LibraryUsable(lib)
    return type(lib) == "table"
        and type(lib.CreateWindow) == "function"
        and lib.ChatFree == true
end

local function LoadLibrary()
    local cached = cacheGet("lib")
    if LibraryUsable(cached) then
        print("[Loader] Library reused from cache (v" .. tostring(cached.Version or "?") .. ")")
        return cached
    end

    local ok, source, attempt = FetchFresh(CFG.LIB_URL, LIB_MARKER, 50000, "KairisLib.lua")
    if not ok then
        error("[Loader] Could not fetch the CURRENT UI library — GitHub's CDN is still serving the old build. Re-run the script in a few seconds.", 0)
    end

    local chunk, compileErr = loadstring(source)
    if not chunk then
        error("[Loader] Library compile error: " .. tostring(compileErr), 0)
    end
    local ok2, lib = pcall(chunk)
    if not ok2 then
        error("[Loader] Library execution error: " .. tostring(lib), 0)
    end
    if not LibraryUsable(lib) then
        error("[Loader] Library loaded but it is NOT the current chat-free build (stale copy). Refusing to run it — re-run the script.", 0)
    end

    cacheSet("lib", lib)
    if attempt >= 4 then
        print("[Loader] CDN served a stale copy — fetched the current library from the fresh API fallback.")
    elseif attempt > 1 then
        print("[Loader] CDN served a stale copy — refetched the current library (attempt " .. attempt .. ").")
    end
    print("[Loader] Library v" .. tostring(lib.Version or "?") .. " ready.")
    return lib
end

-- ══════════════════════════════════════════════════════════════════════════════
-- LOAD GAME SCRIPT
-- ══════════════════════════════════════════════════════════════════════════════
local function LoadGameScript(lib, scriptName)
    local content = cacheGet("script:" .. scriptName)
    local fromCache = content ~= nil
    if not fromCache then
        local url = CFG.SCRIPTS_BASE .. scriptName
        local ok, body = FetchFresh(url, nil, 2000, "scripts/" .. scriptName)
        if not ok then
            error("[Loader] Failed to download game script: " .. scriptName, 0)
        end
        content = body
        cacheSet("script:" .. scriptName, content)
    end

    local fullSource = "Library = _G.KairisLib;\n" .. content

    local chunk, compileErr = loadstring(fullSource)
    if not chunk then
        error("[Loader] Game script compile error (" .. scriptName .. "): " .. tostring(compileErr), 0)
    end

    local ok2, err = pcall(chunk)
    if not ok2 then
        error("[Loader] Game script runtime error (" .. scriptName .. "): " .. tostring(err), 0)
    end
    return fromCache
end

-- ══════════════════════════════════════════════════════════════════════════════
-- MAIN
-- ══════════════════════════════════════════════════════════════════════════════
local placeId = game.PlaceId
local gameId = game.GameId
local scriptName = ResolveScript(placeId, gameId)

print("[Loader] PlaceId:", placeId, " GameId:", gameId, "→", scriptName)

local t0 = os.clock()
local Library = LoadLibrary()

_G.KairisLib = Library

local scriptCached = LoadGameScript(Library, scriptName)
print(string.format("[Loader] %s is now running (script %s, total %.2fs).",
    scriptName, scriptCached and "from cache" or "downloaded", os.clock() - t0))

-- Track launch (if TRACK_URL is set)
if CFG.TRACK_URL then
    local function urlencode(s)
        return (string.gsub(tostring(s), "[^%w%-%_%.%~]", function(c)
            return string.format("%%%02X", string.byte(c))
        end))
    end
    local function Track(kind)
        local params = {
            kind = kind,
            place_id = tostring(placeId),
            game_id = tostring(gameId),
        }
        local parts = {}
        for k, v in pairs(params) do
            parts[#parts + 1] = k .. "=" .. urlencode(v)
        end
        local url = CFG.TRACK_URL .. "?" .. table.concat(parts, "&")
        pcall(function()
            if type(request) == "function" then
                request({ Url = url, Method = "GET" })
            else
                game:HttpGet(url)
            end
        end)
    end
    Track("launch")
    pcall(task.spawn, function()
        while true do
            task.wait(25)
            Track("heartbeat")
        end
    end)
end
