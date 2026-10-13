-- Local extension: weekly background refresh, preserving the last working database.
local utils = require 'mp.utils'
local encoding = require 'encoding'
local M = {}
local function extract_mal_id(url)
    local prefix = "https://myanimelist.net/anime/"
    if url:find(prefix) == 1 then
        return url:sub(31) -- #prefix + 1
    end
    return nil
end


function M.parse_relations(text)
    local rules = text:match('::rules(.+)')
    if not rules then return nil end
    local relations = {}
    local in_title, out_title, number_title, number_index = "", "", false, 0
    for rule in rules:gmatch("[^\r\n]+") do
        local in_mal_id, in_ep_start, in_ep_end, out_mal_id, out_ep_start, out_ep_end, self_redirect = string.match(rule, "^%- ([0-9]+)|[0-9?]+|[0-9?]+:([0-9]+)%-?([0-9?]*) %-> ([0-9~]+)|[0-9?~]+|[0-9?~]+:([0-9]+)%-?([0-9?]*)(!?)")
        if in_mal_id then
            local out_mal_id_string = out_mal_id
            in_ep_start, in_ep_end, out_ep_start, self_redirect = tonumber(in_ep_start), tonumber(in_ep_end), tonumber(out_ep_start), self_redirect
            if not relations[in_mal_id] then
                relations[in_mal_id] = {}
            end
            if out_mal_id == "~" then
                out_mal_id = tonumber(in_mal_id)
            else
                out_mal_id = tonumber(out_mal_id)
            end
            local title = out_title
            if number_title then
                number_index = number_index + 1
                local number_list = string.match(title, "~? ?(.+)")
                local numbers = {}
                for num in number_list:gmatch("([^,]+)") do
                    numbers[#numbers + 1] = num
                end
                local number = numbers[number_index]
                if number then
                    local new_title, count = string.gsub(in_title, "%%d", number)
                    title = new_title
                    if count == 0 then
                        title = in_title .. " " .. number
                    end
                end
            end
            title = string.gsub(title, "~", in_title)
            table.insert(relations[in_mal_id], {a=in_ep_start, b=in_ep_end, x=out_ep_start, z=out_mal_id, t=title})
            if self_redirect == "!" then
                if not relations[out_mal_id_string] then
                    relations[out_mal_id_string] = {}
                end
                table.insert(relations[out_mal_id_string], {a=in_ep_start, b=in_ep_end, x=out_ep_start, z=out_mal_id, t=title})
            end
        else
            local _in_title, _out_title = string.match(rule, "^# (.+) %-> (.*)")
            if _in_title then
                number_title = false
                number_index = 0
                in_title, out_title = _in_title, _out_title
                if string.find(out_title, ",[0-9]") or string.find(out_title, "[0-9],") then
                    number_title = true
                    in_title = string.gsub(in_title, "S?%d", "%%d")
                end
            end
        end
    end


    return next(relations) and relations or nil
end
function M.parse_anime(text)
    local json = utils.parse_json(text)
    if type(json) ~= 'table' or type(json.data) ~= 'table' then return nil end
    local result, canonical = {}, {}

    for _, item in ipairs(json.data) do
        local mal_id = nil
        for _, source in ipairs(item.sources) do
            mal_id = extract_mal_id(source)
            if mal_id then
                break
            end
        end

        mal_id = tonumber(mal_id)

        if mal_id then
            -- A sequel's synonym must not replace the original show's title.
            local key = encoding.key(item.title)
            if not canonical[key] then result[key] = mal_id; canonical[key] = true end
            for _, synonym in ipairs(item.synonyms) do
                local alias = encoding.key(synonym)
                if not result[alias] then result[alias] = mal_id end
            end
        end
    end


    return next(result) and result or nil
end
local function read_json(path)
    local f = io.open(path, 'rb')
    if not f then return {} end
    local text = f:read('*a'); f:close()
    local data = utils.parse_json(text)
    return type(data) == 'table' and data or {}
end
local function write_json(path, data)
    local f = io.open(path, 'wb')
    if not f then return false end
    local ok = f:write(utils.format_json(data))
    local closed = f:close()
    return ok ~= nil and closed ~= nil
end
-- Prepare both files before replacing either; restore originals on a write failure.
local function commit(items)
    local suffix = '.refresh-' .. tostring(utils.getpid())
    for _, item in ipairs(items) do
        item.tmp, item.backup = item.path .. suffix, item.path .. suffix .. '.previous'
        if not write_json(item.tmp, item.data) then
            for _, cleanup in ipairs(items) do if cleanup.tmp then os.remove(cleanup.tmp) end end
            return false
        end
    end
    local ok = true
    for _, item in ipairs(items) do
        if utils.file_info(item.path) then
            if not os.rename(item.path, item.backup) then ok = false; break end
            item.moved = true
        end
        if not os.rename(item.tmp, item.path) then ok = false; break end
        item.installed = true
    end
    for _, item in ipairs(items) do
        if not ok then
            if item.installed then os.remove(item.path) end
            if item.moved then os.rename(item.backup, item.path) end
        elseif item.moved then os.remove(item.backup) end
        os.remove(item.tmp)
    end
    return ok
end
function M.new(directory, days, on_ready)
    local busy = false
    local anime_path = utils.join_path(directory, 'anime.json')
    local relations_path = utils.join_path(directory, 'relations.json')
    local state_path = utils.join_path(directory, 'database-state.json')
    local object = {}
    function object.request(force, invalid_cache)
        if busy then return false end
        local now = os.time()
        local state = read_json(state_path)
        local a, r = utils.file_info(anime_path), utils.file_info(relations_path)
        local updated = tonumber(state.success) or (a and r and math.min(a.mtime, r.mtime)) or 0
        if not force then
            if not invalid_cache and a and r and now - updated < (tonumber(days) or 7) * 86400 then return false end
            if now - (tonumber(state.attempt) or 0) < 6 * 3600 then return false end
        end
        busy = true
        state.attempt = now
        write_json(state_path, state)
        local function fail()
            busy = false
            mp.msg.verbose('AniSkip: background database refresh deferred; keeping existing data')
        end
        local function fetch(url, parser, callback)
            mp.command_native_async({name='subprocess', playback_only=false,
                capture_stdout=true, capture_stderr=true,
                args={'curl.exe','-fsSL','--connect-timeout','10','--max-time','90',url}},
                function(success, result)
                    if not success or not result or result.status ~= 0 then fail(); return end
                    local ok, parsed = pcall(parser, result.stdout or '')
                    if not ok or not parsed then fail(); return end
                    callback(parsed)
                end)
        end
        fetch('https://raw.githubusercontent.com/erengy/anime-relations/master/anime-relations.txt', M.parse_relations, function(relations)
            fetch('https://github.com/manami-project/anime-offline-database/releases/download/latest/anime-offline-database-minified.json', M.parse_anime, function(anime)
                if not commit({{path=anime_path,data=anime},{path=relations_path,data=relations}}) then fail(); return end
                state.success = os.time()
                write_json(state_path, state)
                busy = false
                on_ready(anime, relations)
            end)
        end)
        return true
    end
    return object
end
return M
