-- theintrodb.lua - Skip intros, recaps, credits & previews using TheIntroDB
-- version: v1.0.0
--
-- Fetches segment timestamps for the currently playing movie / TV episode from
-- the TheIntroDB API (https://api.theintrodb.org/v3/media) and provides:
--   * keybindings to skip each segment type
--   * a clickable on-screen button bar (toggle with theintrodb-toggle-ui)
--   * optional auto-skip of intros & recaps (toggle with theintrodb-auto-skip)
--
-- Identification: a TMDB ID (or IMDB ID) is read from the filename
--   tmdb-12345, tmdb_12345, tmdb12345, tt0123456, or from the
--   `theintrodb-tmdb_id` / `theintrodb-imdb_id` script options
--   (mpv --script-opts=theintrodb-tmdb_id=12345 ...).
-- TV episodes need season/episode: parsed from the filename (S01E02 or 1x02),
-- or set via script options.
--
-- Config: script-opts/theintrodb.conf  (see theintrodb.conf.example)
--
-- License: MIT

local utils = require "mp.utils"

-- ---------------------------------------------------------------------------
-- defaults (overridable via script-opts/theintrodb.conf)
-- ---------------------------------------------------------------------------
local o = {
    api_url = "https://api.theintrodb.org/v3/media",
    api_key = "",            -- optional Bearer key; include to see your pending submissions
    tmdb_api_key = "eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiI1NzlkZWYyZDY5ZWFlNDk4ZjJiOTI4MTgyNDdjM2ViMCIsInN1YiI6IjY2MjdmMGJlNjJmMzM1MDE0YmQ4NTFmMiIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.h3KpPvkiaz8uNz1bntAKqsPrxG_4UUWaY3kYME6N6m8",
    auto_detect = "yes",     -- when no id is given, look the media up on TMDB from the filename
    tmdb_id = "",            -- manual override
    imdb_id = "",            -- manual override (fallback when no tmdb_id)
    season = "",             -- manual override for TV
    episode = "",            -- manual override for TV
    duration_ms = "",        -- optional video duration to pick a release version
    auto_skip = "no",        -- auto-skip intro & recap segments
    auto_skip_types = "intro,recap",
    key_skip_intro = "Alt+i",
    key_skip_recap = "Alt+r",
    key_skip_credits = "Alt+c",
    key_skip_preview = "",
    key_skip_next = "n",
    key_toggle_ui = "Ctrl+i",
    key_toggle_auto_skip = "Alt+a",
    mouse_buttons = "yes",   -- clickable on-screen button bar
    show_osd = "yes",        -- OSD notifications on skip / load
    retry_secs = "5",        -- base delay before retrying a failed fetch (doubles)
    max_retries = "4",
}

local function read_opts()
    require("mp.options").read_options(o, "theintrodb")
    local prefix = "theintrodb-"
    for name, _ in pairs(o) do
        local v = mp.get_opt(prefix .. name)
        if v ~= nil then
            local cur = o[name]
            if type(cur) == "number" then
                o[name] = tonumber(v) or cur
            elseif type(cur) == "boolean" then
                o[name] = v == "yes" or v == "true" or v == "1"
            else
                o[name] = tostring(v)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------
local ui=dofile(mp.command_native({'expand-path','~~/extensions/ui_locale.lua'}))
ui.install_messages()
local config_root=mp.command_native({'expand-path','~~/'})
local title_format=dofile(config_root..'/extensions/title_format.lua')
local anime_identity=dofile(config_root..'/extensions/anime_identity.lua')
local skip_segments=dofile(config_root..'/extensions/skip_segments.lua')
local ru_kind = {intro="Заставка", recap="Ранее в сериале", credits="Титры", preview="Анонс"}
local tidb = {
    media = nil,          -- parsed API response
    segments = {},        -- flat list: {kind=, start=, end=} in seconds
    segments_by_kind = { intro = {}, recap = {}, credits = {}, preview = {} },
    file_key = nil,       -- filename (cache key)
    identified = false,
    loaded = false,       -- data fetched for current file
    none_msg_shown = false,
    ui_visible = false,
    auto_skip = false,
    overlay_timer = nil,
    hide_timer = nil,
    mouse_pos = { x = -1, y = -1 },
    buttons = {},         -- {kind=, start=, end=, x0=, x1=, y0=, y1=}
    retry_timer = nil,
    retry_count = 0,
    last_fetch_error = nil,
    cache = {},           -- file_key -> media table (TheIntroDB responses)
    tmdb_cache = {},      -- file_key -> tmdb_id (auto-detect results)
    api_timer = nil,
    seek_grace_until = 0, -- skip grace after a manual seek
    hint_shown = false,
}

-- forward declarations (defined later in the file; Lua locals are not hoisted)
local build_segments, hide_overlay, update_overlay, on_mouse_left_click, show_overlay
local schedule_retry, fetch_media

local function log(...)
    mp.msg.log("info", string.format(...))
end

local function fmt_time(secs)
    if secs == nil then return "?" end
    local s = math.floor(secs + 0.5)
    if s < 0 then s = 0 end
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local sec = s % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, sec)
    end
    return string.format("%d:%02d", m, sec)
end

-- ---------------------------------------------------------------------------
-- identification: tmdb/imdb id + season/episode from filename & options
-- ---------------------------------------------------------------------------
-- split a comma-separated list, trimmed ("intro, recap" -> {"intro","recap"})
local function split_csv(s)
    local out = {}
    for part in string.gmatch(s or "", "[^,]+") do
        local p = part:gsub("^%s+", ""):gsub("%s+$", "")
        if p ~= "" then out[#out + 1] = p end
    end
    return out
end

-- returns season, episode or nil,nil
local function split_season_episode(s)
    local se, ep = string.match(s, "[Ss]%s*(%d+)%s*[Ee]%s*(%d+)")
    if not se then
        se, ep = string.match(s, "(%d+)%s*[xX]%s*(%d+)")
    end
    if not se then
        se, ep = string.match(s, "[Ss]eason%s+(%d+)%s+[Ee]pisode%s+(%d+)")
    end
    return se, ep
end

local function identify(path)
    local tmdb_id = o.tmdb_id
    local imdb_id = o.imdb_id
    local season, episode = o.season, o.episode

    local base = path or ""
    if tmdb_id == "" then
        tmdb_id = string.match(base, "[Tt][Mm][Dd][Bb][%s_%-%.]*(%d+)")
    end
    if imdb_id == "" then
        imdb_id = string.match(base, "tt%d%d%d%d%d%d%d%d?")
    end
    if season == "" or episode == "" then
        local se, ep = split_season_episode(base)
        if se then
            if season == "" then season = tostring(tonumber(se)) end
            if episode == "" then episode = tostring(tonumber(ep)) end
        end
    end
    -- normalize: empty strings become nil so callers can check truthiness
    if tmdb_id == "" then tmdb_id = nil end
    if imdb_id == "" then imdb_id = nil end
    if season == "" then season = nil end
    if episode == "" then episode = nil end
    return tmdb_id, imdb_id, season, episode
end

-- ---------------------------------------------------------------------------
-- API fetch (curl subprocess, cached per file, rate-limit retry with backoff)
-- ---------------------------------------------------------------------------
local function api_url(tmdb_id, imdb_id, season, episode, duration_ms)
    local params = {}
    if tmdb_id then
        params[#params + 1] = "tmdb_id=" .. tostring(tmdb_id)
    elseif imdb_id then
        params[#params + 1] = "imdb_id=" .. tostring(imdb_id)
    end
    if season and episode then
        params[#params + 1] = "season=" .. tostring(season)
        params[#params + 1] = "episode=" .. tostring(episode)
    end
    if duration_ms and duration_ms ~= "" then
        params[#params + 1] = "duration_ms=" .. tostring(duration_ms)
    end
    return o.api_url .. "?" .. table.concat(params, "&")
end

local function on_fetch_result(status, stdout, file_key, tmdb_id, imdb_id)
    if file_key ~= tidb.file_key then return end -- stale (file changed while fetching)
    tidb.retry_timer = nil
    if status ~= 0 then
        tidb.last_fetch_error = "curl exit " .. tostring(status)
        schedule_retry(file_key, tmdb_id, imdb_id)
        return
    end
    -- parse "\n<code>" trailer appended by curl -w (code comes AFTER the body)
    local http_code = tonumber(string.match(stdout or "", "\n(%d+)$")) or 0
    local body = string.gsub(stdout or "", "\n%d+$", "")
    if http_code == 429 then
        tidb.last_fetch_error = "rate limited (429)"
        schedule_retry(file_key, tmdb_id, imdb_id)
        return
    end
    if http_code == 404 or http_code == 400 then
        tidb.media = nil
        tidb.loaded = true
        tidb.retry_count = 0
        if o.show_osd == "yes" then
            if #tidb.segments == 0 then mp.osd_message("TheIntroDB: для этой серии пока нет таймкодов", 2.5) end
        end
        return
    end
    if http_code ~= 200 then
        tidb.last_fetch_error = "HTTP " .. tostring(http_code)
        schedule_retry(file_key, tmdb_id, imdb_id)
        return
    end
    local ok, data = pcall(utils.parse_json, body)
    if not ok or data == nil then
        tidb.last_fetch_error = "invalid JSON"
        schedule_retry(file_key, tmdb_id, imdb_id)
        return
    end
    tidb.retry_count = 0
    tidb.media = data
    tidb.loaded = true
    tidb.cache[file_key] = data
    build_segments(data)
    if o.show_osd == "yes" then
        local count = #tidb.segments
        if count == 0 then
            mp.osd_message("Для этой серии нет фрагментов для пропуска", 2)
        else
            mp.osd_message(
                string.format("Найдено фрагментов для пропуска: %d", count), 1.5)
        end
    end
end

schedule_retry = function(file_key, tmdb_id, imdb_id)
    if file_key ~= tidb.file_key then return end
    if tidb.retry_count >= tonumber(o.max_retries) then
        tidb.last_fetch_error = nil
        if o.show_osd == "yes" then
            mp.osd_message("Не удалось получить таймкоды пропуска", 2.5)
        end
        return
    end
    tidb.retry_count = tidb.retry_count + 1
    local delay = tonumber(o.retry_secs) * (2 ^ (tidb.retry_count - 1))
    log("fetch failed (%s), retrying in %ds", tidb.last_fetch_error, delay)
    tidb.retry_timer = mp.add_timeout(delay, function()
        tidb.retry_timer = nil
        fetch_media(file_key, tmdb_id, imdb_id)
    end)
end

-- Additional read-only sources used by Just+: fill gaps in TheIntroDB.
local function get_json(url, headers, callback)
    local args = {'curl', '-fsS', '--connect-timeout', '5', '--max-time', '10', '--globoff'}
    for _, header in ipairs(headers or {}) do args[#args+1]='-H'; args[#args+1]=header end
    args[#args+1]=url
    mp.command_native_async({name='subprocess', args=args, capture_stdout=true, capture_stderr=true}, function(ok,res)
        local value = ok and res and res.status == 0 and utils.parse_json(res.stdout or '') or nil
        callback(type(value)=='table' and value or nil)
    end)
end
local function fetch_additional_sources(file_key, tmdb_id, imdb_id)
    if tidb.extra_started_key == file_key then return end
    tidb.extra_started_key = file_key
    local function fetch(imdb)
        if file_key ~= tidb.file_key or not imdb or imdb == '' then return end
        local season, episode = tonumber(tidb.season), tonumber(tidb.episode)
        local query = '?imdb_id=' .. imdb
        if season and episode then query=query..'&season='..season..'&episode='..episode end
        local duration=mp.get_property_number('duration',0)
        local urls={
            {'SkipDB','https://api.skipdb.tv/api/segments'..query..'&duration='..math.floor(duration)},
            {'IntroDB','https://api.introdb.app/segments'..query..(season and '' or '&is_movie=true')},
        }
        for _, source in ipairs(urls) do
            get_json(source[2],nil,function(data)
                if file_key ~= tidb.file_key or not data then return end
                local result={}
                local body=source[1]=='SkipDB' and data.segments or data
                if type(body)~='table' then return end
                for _, pair in ipairs({{'intro','intro'},{'recap','recap'},{'outro','credits'}}) do
                    local seg=body[pair[1]]
                    if type(seg)=='table' then
                        local start=tonumber(seg.start_ms) or (tonumber(seg.start_sec) or -1)*1000
                        local finish=tonumber(seg.end_ms) or (tonumber(seg.end_sec) or -1)*1000
                        if start>=0 and finish>start and (duration<=0 or finish<=duration*1000+5000) then
                            result[pair[2]]={{start_ms=start,end_ms=finish}}
                        end
                    end
                end
                tidb.extra_sources[source[1]]=result
                build_segments(tidb.media or {})
            end)
        end
    end
    if imdb_id then fetch(imdb_id); return end
    if not tmdb_id then return end
    local media_type=tidb.season and 'tv' or 'movie'
    get_json('https://api.themoviedb.org/3/'..media_type..'/'..tmdb_id..'/external_ids',
        {'Authorization: Bearer '..o.tmdb_api_key},function(data) if data then fetch(data.imdb_id) end end)
end

fetch_media = function(file_key, tmdb_id, imdb_id)
    fetch_additional_sources(file_key, tmdb_id, imdb_id)
    if file_key ~= tidb.file_key then return end
    if tidb.cache[file_key] then
        tidb.media = tidb.cache[file_key]
        tidb.loaded = true
        build_segments(tidb.media)
        return
    end
    local url = api_url(tmdb_id, imdb_id, tidb.season, tidb.episode, o.duration_ms)
    local args = {
        "curl", "-s", "--max-time", "10", "-w", "\n%{http_code}",
    }
    if o.api_key ~= "" then
        args[#args + 1] = "-H"
        args[#args + 1] = "Authorization: Bearer " .. o.api_key
    end
    args[#args + 1] = url
    mp.command_native_async({ name = "subprocess", args = args, capture_stdout = true },
        function(success, res)
            if not success or not res then
                on_fetch_result(1, nil, file_key, tmdb_id, imdb_id)
                return
            end
            on_fetch_result(res.status or 0, res.stdout or "", file_key, tmdb_id, imdb_id)
        end)
end

-- ---------------------------------------------------------------------------
-- segment handling
-- ---------------------------------------------------------------------------
build_segments = function(data)
    local duration = mp.get_property_number("duration") or 0
    -- Merge AniSkip data for this file into the existing uosc skip button.
    -- Keep one online anime source, then prefer matching embedded chapters.
    local combined = {}
    for key, value in pairs(data or {}) do combined[key] = value end
    for _, name in ipairs({'SkipDB','IntroDB'}) do
        for kind, list in pairs((tidb.extra_sources or {})[name] or {}) do
            if not combined[kind] or #combined[kind]==0 then combined[kind]=list end
        end
    end
    local merged = {}
    local key = (mp.get_property('path') or '') .. '|' .. tostring(mp.get_property_number('playlist-pos', -1))
    if mp.get_property_native('user-data/autochapters-media') == key then
        local times = mp.get_property_native('user-data/autochapters') or {}
        for _, pair in ipairs({{'op','intro'}, {'mixed-op','intro'}, {'ed','credits'}, {'mixed-ed','credits'}, {'recap','recap'}}) do
            local seg = times[pair[1]]
            local start = type(seg) == 'table' and tonumber(seg.start)
            local finish = type(seg) == 'table' and tonumber(seg['end'])
            if start and finish and start >= 0 and finish > start then
                local kind = pair[2]
                merged[kind] = merged[kind] or {}
                merged[kind][#merged[kind]+1] = {start_ms=start*1000, end_ms=finish*1000}
            end
        end
    end
    local native=mp.get_property_native('user-data/file-chapters',{})
    local local_segments=native.key==key and skip_segments.from_chapters(native.chapters,duration,title_format.normalize) or {}
    data=skip_segments.combine(combined,merged,local_segments)
    tidb.segments = {}
    for _, kind in ipairs({ "intro", "recap", "credits", "preview" }) do
        tidb.segments_by_kind[kind] = {}
        local list = data[kind]
        if type(list) == "table" then
            for _, seg in ipairs(list) do
                if type(seg) == "table" then
                    local start_ms = seg.start_ms
                    local end_ms = seg["end_ms"]
                    -- 0-length => "no segment"
                    if start_ms == 0 and end_ms == 0 then
                        -- skip
                    elseif end_ms == nil or end_ms == 0 then
                        -- end of media
                        if start_ms ~= nil and start_ms > 0 then
                            tidb.segments[#tidb.segments + 1] = {
                                kind = kind, start = start_ms / 1000, ["end"] = nil,
                            }
                        end
                    else
                        local start = (start_ms or 0) / 1000
                        local fin = end_ms / 1000
                        -- clamp end to duration
                        if duration > 0 and fin > duration then fin = duration end
                        tidb.segments[#tidb.segments + 1] = {
                            kind = kind, start = start, ["end"] = fin,
                        }
                    end
                end
            end
        end
    end
    table.sort(tidb.segments, function(a, b)
        local as = a.start or 0
        local bs = b.start or 0
        if as == bs then
            local ae = a["end"] or math.huge
            local be = b["end"] or math.huge
            return ae < be
        end
        return as < bs
    end)
    for _, seg in ipairs(tidb.segments) do
        tidb.segments_by_kind[seg.kind][#tidb.segments_by_kind[seg.kind] + 1] = seg
    end
    hide_overlay()
    update_overlay()
end

local function segment_contains(seg, pos)
    local s = seg.start or 0
    local e = seg["end"] or math.huge
    return pos >= s and (e == math.huge or pos <= e)
end

local function current_segment(pos)
    for _, seg in ipairs(tidb.segments) do
        if segment_contains(seg, pos) then return seg end
    end
    return nil
end

local function next_segment_after(pos)
    local best = nil
    for _, seg in ipairs(tidb.segments) do
        local s = seg.start or 0
        if s > pos then
            if best == nil or s < (best.start or 0) then best = seg end
        end
    end
    return best
end

local function duration()
    return mp.get_property_number("duration") or 0
end

local function do_skip(seg, via_ui)
    if seg == nil then return false end
    local target = seg["end"]
    if target == nil or target == math.huge then
        target = duration()
    end
    -- don't skip "to" a position we're already past
    local pos = mp.get_property_number("time-pos") or 0
    if target <= pos then return false end
    -- land just before EOF if the segment runs to the end
    local max = duration()
    if max > 0 and target >= max - 0.2 then
        target = math.max(0, max - 0.1)
    end
    mp.set_property("pause", "no")
    mp.commandv("seek", tostring(target), "absolute", "exact")
    tidb.seek_grace_until = mp.get_time() + 1.5
    if o.show_osd == "yes" then
        local label = ru_kind[seg.kind] or seg.kind
        if seg["end"] == nil or seg["end"] == math.huge then
            mp.osd_message(string.format("Пропущено: %s → конец", label), 1.2)
        else
            mp.osd_message(
                string.format("Пропущено: %s → %s", label, fmt_time(seg["end"])), 1.2)
        end
    end
    return true
end

local function skip_kind(kind)
    local pos = mp.get_property_number("time-pos") or 0
    -- try to find a segment of this kind that contains the position
    for _, seg in ipairs(tidb.segments_by_kind[kind]) do
        if segment_contains(seg, pos) then
            if do_skip(seg, false) then return end
        end
    end
    -- else next upcoming segment of this kind
    local next_seg = nil
    for _, seg in ipairs(tidb.segments_by_kind[kind]) do
        local s = seg.start or 0
        if s > pos then
            if next_seg == nil or s < (next_seg.start or 0) then next_seg = seg end
        end
    end
    if next_seg then
        do_skip(next_seg, false)
        return
    end
    if o.show_osd == "yes" then
        mp.osd_message("Нет таймкода: " .. (ru_kind[kind] or kind), 1.5)
    end
end

local function skip_next()
    local pos = mp.get_property_number("time-pos") or 0
    local seg = current_segment(pos)
    if seg and seg["end"] then
        if do_skip(seg, false) then return end
    end
    local nxt = next_segment_after(pos)
    if nxt then
        do_skip(nxt, false)
        return
    end
    if o.show_osd == "yes" then
        mp.osd_message("Нет фрагментов для пропуска", 1.5)
    end
end

-- ---------------------------------------------------------------------------
-- auto-skip (intro/recap by default)
-- ---------------------------------------------------------------------------
local auto_skip_timer = nil

local function auto_skip_tick()
    if not tidb.auto_skip then return end
    local paused = mp.get_property_bool("pause")
    if paused then return end
    local pos = mp.get_property_number("time-pos")
    if pos == nil then return end
    if mp.get_time() < tidb.seek_grace_until then return end
    -- only seek forward, never fight the user
    local seg = current_segment(pos)
    if seg == nil then return end
    local want = {}
    for _, kind in ipairs(split_csv(o.auto_skip_types)) do
        want[kind] = true
    end
    if not want[seg.kind] then return end
    if seg["end"] == nil or seg["end"] == math.huge then return end -- don't auto-skip to EOF
    do_skip(seg, false)
end

local function start_auto_skip_timer()
    if auto_skip_timer then
        auto_skip_timer:kill()
        auto_skip_timer = nil
    end
    auto_skip_timer = mp.add_periodic_timer(0.4, auto_skip_tick)
end

local function toggle_auto_skip()
    tidb.auto_skip = not tidb.auto_skip
    if tidb.auto_skip then
        start_auto_skip_timer()
        mp.osd_message("Автоматический пропуск включён", 1.2)
    else
        if auto_skip_timer then auto_skip_timer:kill() end
        auto_skip_timer = nil
        mp.osd_message("Автоматический пропуск выключен", 1.2)
    end
end

-- ---------------------------------------------------------------------------
-- on-screen button bar (ASS overlay, clickable)
-- ---------------------------------------------------------------------------
-- Use uosc controls instead of global mouse bindings that conflict with its UI.
local last_button_state = nil
local function send_button(seg)
    local label = seg and (ru_kind[seg.kind] or seg.kind) or nil
    mp.set_property_native('user-data/skip-prompt', seg or {})
    local key = ui.language()..':'..(seg and (seg.kind .. ':' .. tostring(seg.start)) or 'none')
    if key == last_button_state then return end
    last_button_state = key
    mp.commandv('script-message-to', 'uosc', 'set-button', 'theintrodb', utils.format_json({
        icon = 'fast_forward', active = seg ~= nil,
        badge = false,
        tooltip = seg and ui.text('Пропустить: '..(seg.kind=='intro' and 'Заставку' or label)) or ui.text('Заставки и титры (Ctrl+I)'),
        command = seg and 'script-binding theintrodb/theintrodb-skip-next'
            or 'script-binding theintrodb/theintrodb-toggle-ui',
    }))

end

update_overlay = function()
    send_button(current_segment(mp.get_property_number('time-pos') or -1))
end

hide_overlay = function()
    tidb.ui_visible = false
    mp.commandv('script-message-to', 'uosc', 'close-menu', 'theintrodb')
end

show_overlay = function()
    local items = {}
    for i, seg in ipairs(tidb.segments) do
        local finish = seg['end'] and fmt_time(seg['end']) or ui.text('конец')
        items[#items + 1] = {
            title = ui.text('Пропустить: ' .. (seg.kind == 'intro' and 'Заставку' or ru_kind[seg.kind] or seg.kind)),
            hint = fmt_time(seg.start) .. ' → ' .. finish,
            value = {'script-message-to', 'theintrodb', 'skip-segment', tostring(i)},
        }
    end
    if #items == 0 then
        items[1] = {title = ui.text('Для этой серии таймкоды не найдены'), selectable = false}
    end
    mp.commandv('script-message-to', 'uosc', 'open-menu', utils.format_json({
        type = 'theintrodb', title = ui.text('Заставки и титры'), items = items,
    }))
end

local function toggle_overlay() show_overlay() end
mp.register_script_message('skip-segment', function(index)
    local seg = tidb.segments[tonumber(index)]
    if seg then do_skip(seg, true) end
end)
mp.add_periodic_timer(0.4, update_overlay)
mp.add_timeout(0.5, function() last_button_state = nil; update_overlay() end)


-- ---------------------------------------------------------------------------
-- auto-detection: resolve a TMDB id from the filename via TMDB search
-- ---------------------------------------------------------------------------
local function urlencode(s)
    s = tostring(s)
    s = s:gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return s
end

-- returns title, year, is_tv, ep_hint (episode number parsed from the
-- filename when it used "Show - 01" / "Show E02" style naming)
local function parse_title_for_search(filename)
    local base = filename:gsub("%.[%w]+$", "")  -- strip extension

    local t = base
    t = t:gsub("%[[^%]]*%]", " ")               -- [group] tags
    t = t:gsub("[._]", " ")                     -- separators
    t = t:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

    -- find the earliest "metadata" cut point: the title ends there
    local cut_pos = nil
    local is_tv = false
    local ep_hint = nil

    -- Some releases put the episode first: "S01E04. MobLand (2025). Rat Trap".
    -- Keep its TV identity, then search the title that follows the marker.
    local prefix_end = t:match("^[Ss]%s*%d+%s*[Ee]%s*%d+()")
        or t:match("^%d+%s*[xX]%s*%d+()")
        or t:match("^[Ss]eason%s+%d+%s+[Ee]pisode%s+%d+()")
    if prefix_end then
        is_tv = true
        t = t:sub(prefix_end):gsub("^[%s%-%._:]+", "")
    end

    local function consider(pos, tv, ep)
        if pos and (cut_pos == nil or pos < cut_pos) then
            cut_pos = pos
            if tv then is_tv = true end
            if ep then ep_hint = ep end
        end
    end

    -- TV markers (highest priority)
    local i = t:find("[Ss]%d+[Ee]%d+")
    consider(i, true)
    i = t:find("%d+[xX]%d+")
    consider(i, true)
    local i2, _, e2 = t:find("%s%-%s(%d+)")     -- "Show - 01"
    consider(i2, true, e2)
    i2, _, e2 = t:find("%s[Ee](%d+)")            -- "Show E02"
    consider(i2, true, e2)

    -- year: the last plausible 4-digit group (title digits come first,
    -- the release year comes last, before the technical suffix)
    local year, year_pos
    for p, y in t:gmatch("()(%d%d%d%d)") do
        local yv = tonumber(y)
        if yv and yv >= 1900 and yv <= 2100 then
            year, year_pos = y, p
        end
    end
    if year_pos then
        local before = t:sub(1, year_pos - 1):gsub("%s+", "")
        if before == "" then
            year = nil  -- numeric title ("1917.1080p"): digits are the title
        elseif year_pos > 1 then
            consider(year_pos, false)
        end
    end

    -- first technical marker (resolution / source / codec)
    local tl = t:lower()
    local tech = { "1080p", "720p", "2160p", "480p", "4k", "web%-dl",
        "webrip", "bluray", "hdtv", "x264", "x265", "hevc", "h264", "h265",
        "aac", "ac3", "dts" }
    for _, pat in ipairs(tech) do
        local ti = tl:find(pat)
        if ti then
            consider(ti, false)
            break  -- only the first marker matters
        end
    end

    if cut_pos then
        t = t:sub(1, cut_pos - 1)
    end

    -- clean leftovers; keep pure-digit words ("1917") as the title
    -- only when nothing else survived the cut
    local out, digit_out = {}, {}
    for w in t:gmatch("%S+") do
        local wl = w:lower():gsub("[^%w%.]", "")
        if wl ~= "" and not wl:match("^%d+$") then
            out[#out + 1] = w
        else
            digit_out[#digit_out + 1] = w
        end
    end
    t = table.concat(out, " ")
    if t == "" then
        t = table.concat(digit_out, " ")
    end
    return t, year, is_tv, ep_hint
end

-- async TMDB search; calls cb(tmdb_id or nil)
local function tmdb_search(title, year, is_tv, cb)
    if o.tmdb_api_key == "" then cb(nil) return end
    local endpoint = is_tv and "/search/tv" or "/search/movie"
    local url = "https://api.themoviedb.org/3" .. endpoint
        .. "?query=" .. urlencode(title)
        .. "&language=en-US"
    if year then
        url = url .. (is_tv and "&first_air_date_year=" or "&year=") .. year
    end
    -- note: the key is sent ONLY as a Bearer header (TMDB v4 JWTs are not
    -- accepted via the api_key query parameter)
    local args = {
        "curl", "-s", "--max-time", "10",
        "-H", "Authorization: Bearer " .. o.tmdb_api_key,
        url,
    }
    mp.command_native_async({ name = "subprocess", args = args, capture_stdout = true },
        function(success, res)
            if not success or not res or res.status ~= 0 then cb(nil) return end
            local ok, data = pcall(utils.parse_json, res.stdout or "")
            if not ok or not data or not data.results or #data.results == 0 then
                cb(nil)
                return
            end
            -- prefer a result matching the year, else the top hit
            local best = data.results[1]
            if year then
                for _, r in ipairs(data.results) do
                    local d = r.release_date or r.first_air_date or ""
                    if d:sub(1, 4) == year then best = r break end
                end
            end
            cb(best.id)
        end)
end

-- called when no explicit id was found: guess title, search TMDB, then fetch
local function auto_detect(file_key, filename)
    if tidb.tmdb_cache[file_key] then
        local cached = tidb.tmdb_cache[file_key]
        if cached and cached ~= "" then
            fetch_media(file_key, cached, nil)
        end
        return
    end
    -- AniSkip identifies anime seasons separately. A generic TMDB top hit can
    -- refer to another adaptation or season; use the verified anime path instead.
    if anime_identity.enrich(filename,title_format.parse(filename)).anime then return end
    local title, year, is_tv, ep_hint = parse_title_for_search(filename)
    if not title or title == "" then
        mp.msg.info("Не удалось определить название для поиска заставок", 3)
        return
    end
    if o.show_osd == "yes" then
        mp.msg.info(
            string.format("Поиск заставок: поиск в TMDB \"%s\"%s...",
                title, year and (" (" .. year .. ")") or ""), 2)
    end
    tmdb_search(title, year, is_tv, function(id)
        if file_key ~= tidb.file_key then return end  -- stale (file changed)
        tidb.tmdb_cache[file_key] = id or ""
        if id then
            tidb.tmdb_id = tostring(id)
            -- TV with an episode-only filename ("Show - 01"): assume season 1
            if is_tv and (not tidb.season or not tidb.episode) and ep_hint then
                tidb.season = tidb.season or "1"
                tidb.episode = tidb.episode or ep_hint
            end
            if is_tv and (not tidb.season or not tidb.episode) then
                mp.msg.info(
                    string.format("Найден сериал TMDB %d, но не определён номер серии", id), 3)
                return
            end
            if o.show_osd == "yes" then
                mp.msg.info(string.format("Для поиска заставок определён TMDB %d", id), 1.5)
            end
            fetch_media(file_key, tostring(id), nil)
        else
            mp.msg.info(
                string.format("В TMDB не найдено совпадение для \"%s\"", title), 3)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- file load lifecycle
-- ---------------------------------------------------------------------------
local function on_file_loaded()
    read_opts()  -- re-read script-opts (they can change per file / reload)
    local path = mp.get_property("path") or ""
    -- TorrServer exposes /stream?link=... as filename; use its M3U title.
    local playlist = mp.get_property_native("playlist") or {}
    local pos = (mp.get_property_number("playlist-pos") or -1) + 1
    local item = playlist[pos] or {}
    local filename = item.title or mp.get_property("media-title") or mp.get_property("filename") or ""
    if filename:match("^edl://") then filename = "" end
    filename = filename:gsub("[?#].*$", ""):match("([^/\\]+)$") or filename
    -- Lampa can encode URL names twice ("%2520" -> "%20" -> space).
    for _ = 1, 2 do
        local decoded = filename:gsub("%%(%x%x)", function(h) return string.char(tonumber(h,16)) end)
        if decoded == filename then break end
        filename = decoded
    end
    local file_key = path .. "|" .. filename
    -- resolve ids for this file
    local tmdb_id, imdb_id, season, episode = identify(filename)
    tidb.file_key = file_key
    tidb.extra_sources = {}
    tidb.extra_started_key = nil
    tidb.media = nil
    tidb.loaded = false
    tidb.none_msg_shown = false
    tidb.segments = {}
    for _, k in ipairs({ "intro", "recap", "credits", "preview" }) do
        tidb.segments_by_kind[k] = {}
    end
    tidb.buttons = {}
    tidb.retry_count = 0
    -- clear any state carried over from the previous file
    tidb.tmdb_id, tidb.imdb_id, tidb.season, tidb.episode = nil, nil, nil, nil
    if tidb.retry_timer then tidb.retry_timer:kill() end
    tidb.retry_timer = nil
    hide_overlay()

    -- Handles either ordering of the two scripts' file-loaded events.
    mp.add_timeout(0.1, function()
        if tidb.file_key == file_key then build_segments(tidb.media or {}) end
    end)
    if filename == "" or filename == "stream" then return end

    -- store resolved ids so the fetch uses them
    tidb.tmdb_id = tmdb_id
    tidb.imdb_id = imdb_id
    tidb.season = season
    tidb.episode = episode

    if not tmdb_id and not imdb_id then
        if o.auto_detect == "yes" then
            auto_detect(file_key, filename)
        else
            mp.msg.info("Не определён TMDB/IMDb ID для поиска заставок", 3.5)
        end
        return
    end
    fetch_media(file_key, tmdb_id, imdb_id)
end

-- ---------------------------------------------------------------------------
-- bindings
-- ---------------------------------------------------------------------------
read_opts()  -- must run before bind() reads o.key_* values

local function bind(keys, name, fn)
    -- Always expose script bindings, including buttons without keyboard shortcuts.
    mp.add_key_binding(keys and keys ~= "" and keys or nil, name, fn)
end

bind(o.key_skip_intro, "theintrodb-skip-intro", function() skip_kind("intro") end)
bind(o.key_skip_recap, "theintrodb-skip-recap", function() skip_kind("recap") end)
bind(o.key_skip_credits, "theintrodb-skip-credits", function() skip_kind("credits") end)
bind(o.key_skip_preview, "theintrodb-skip-preview", function() skip_kind("preview") end)
bind(o.key_skip_next, "theintrodb-skip-next", skip_next)
bind(o.key_toggle_ui, "theintrodb-toggle-ui", toggle_overlay)
bind(o.key_toggle_auto_skip, "theintrodb-toggle-auto-skip", toggle_auto_skip)

if o.mouse_buttons == "yes" then
    mp.add_key_binding("MOUSE_MOVE", "theintrodb-mouse-move", on_mouse_move)
    -- MBTN_LEFT/RIGHT are bound dynamically in show_overlay() so they only
    -- intercept clicks while the button bar is on screen (the OSC keeps
    -- working normally otherwise).
end

-- ---------------------------------------------------------------------------
-- init
-- ---------------------------------------------------------------------------
tidb.auto_skip = (o.auto_skip == "yes")
if tidb.auto_skip then
    start_auto_skip_timer()
end

mp.observe_property('user-data/autochapters', 'native', function()
    if tidb.file_key then build_segments(tidb.media or {}) end
end)
mp.observe_property('user-data/file-chapters','native',function()
    if tidb.file_key then build_segments(tidb.media or {}) end
end)
mp.observe_property('user-data/interface-language','string',function()
    last_button_state=nil;update_overlay()
    if mp.get_property_native('user-data/uosc/menu/type')=='theintrodb' then show_overlay() end
end)
mp.register_event("file-loaded", on_file_loaded)
-- also react to end-file to clean overlay
mp.register_event("end-file", function()
    hide_overlay()
    tidb.file_key = nil
    tidb.media = nil
    tidb.segments = {}
    for _, kind in ipairs({'intro','recap','credits','preview'}) do tidb.segments_by_kind[kind] = {} end
    update_overlay()
end)

-- debug hook: expose internals for the test harness (no-op in real mpv)
if mp.get_opt("theintrodb-debug") == "yes" then
    _G.__tidb_debug = function() return tidb end
end

log("loaded (TheIntroDB %s)", "1.0.0")

