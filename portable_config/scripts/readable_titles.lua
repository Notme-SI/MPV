local utils=require 'mp.utils'
local root=mp.command_native({'expand-path','~~/'})
local fmt=dofile(root..'/extensions/title_format.lua')
local opts={enabled=true,online=true,tmdb_api_key=''}
require('mp.options').read_options(opts,'readable_titles')
local token=opts.tmdb_api_key~='' and opts.tmdb_api_key or dofile(root..'/extensions/tmdb_client.lua')
local active=false
local generation=0
local current,language
local display_details={}
local requests,cache,pending={},{},{}
local cache_order={}
local timer
local function encode(s) return tostring(s):gsub('[^%w%-._~]',function(c) return string.format('%%%02X',c:byte()) end) end
local function cancel()
    for id in pairs(requests) do mp.abort_async_command(id) end
    requests,pending={},{}
end
local function get(endpoint,callback)
    if cache[endpoint] then callback(cache[endpoint]);return end
    if pending[endpoint] then pending[endpoint][#pending[endpoint]+1]=callback;return end
    pending[endpoint]={callback}
    local id,gen
    gen=generation
    id=mp.command_native_async({name='subprocess',capture_stdout=true,capture_stderr=true,
        args={'curl','--silent','--fail','--connect-timeout','3','--max-time','7',
            '--header','Authorization: Bearer '..token,'https://api.themoviedb.org/3/'..endpoint}},function(ok,res)
        requests[id]=nil
        if gen~=generation then return end
        local callbacks=pending[endpoint] or {};pending[endpoint]=nil
        local data=ok and res and res.status==0 and utils.parse_json(res.stdout or '') or nil
        if type(data)=='table' and not data.status_code then
            cache[endpoint]=data;cache_order[#cache_order+1]=endpoint
            if #cache_order>64 then cache[table.remove(cache_order,1)]=nil end
        else data=nil end
        for _,fn in ipairs(callbacks) do fn(data) end
    end)
    requests[id]=true
end
local function audio_language()
    local track=mp.get_property_native('current-tracks/audio') or {}
    if track.lang then return fmt.language(track.lang) end
    local id=mp.get_property_native('aid')
    for _,t in ipairs(mp.get_property_native('track-list',{})) do
        if t.type=='audio' and (t.selected or t.id==id) then return fmt.language(t.lang) end
    end
    return 'ru'
end
local function publish(data,title,episode_title,episodes)
    local text=fmt.label(data,language,title,episode_title)
    if text=='' then text=mp.get_property('media-title','') end
    if title then display_details.title=title end
    if episodes then display_details.episodes=episodes end
    mp.set_property_native('user-data/readable-title',{text=text,language=language,
        source_title=data.title,title=display_details.title,season=data.season,episodes=display_details.episodes})
    mp.set_property('title',text)
end
local function identity()
    local list=mp.get_property_native('playlist',{})
    local pos=(mp.get_property_number('playlist-pos',-1))+1
    local item=list[pos] or {}
    local raw=item.title or mp.get_property('media-title') or mp.get_property('filename','')
    local data=fmt.parse(raw)
    local guess=mp.get_property_native('user-data/guessit',{})
    if type(guess)=='table' and guess.input==mp.get_property('path') then
        if data.title=='' and type(guess.title)=='string' then data.title=guess.title end
        if not data.episode and type(guess.episode)=='number' then data.episode=guess.episode end
        if not data.season and type(guess.season)=='number' then data.season=guess.season end
        if data.episode then data.kind='tv' end
    end
    return data,raw
end
local function refresh()
    if not active or not opts.enabled then return end
    local data,raw=identity()
    local lang=audio_language()
    local signature=raw..'|'..lang..'|'..tostring(data.episode)..'|'..tostring(data.season)
    if signature==current then return end
    generation=generation+1;cancel()
    current,language=signature,lang
    display_details={}
    local gen=generation
    publish(data)
    if not opts.online or data.title=='' or not token or token=='' then return end
    local locale=lang
    local function resolved(id)
        if gen~=generation or not id then return end
        local endpoint=data.kind..'/'..id
        get(endpoint..'?language='..locale,function(details)
            if gen~=generation or not details then return end
            local title=details.name or details.title
            publish(data,title)
            if data.kind=='tv' and data.episode then
                get(endpoint..'/season/'..(data.season or 1)..'?language='..locale,function(season)
                    if gen~=generation or not season then return end
                    local episodes,episode_title={},nil
                    for _,episode in ipairs(season.episodes or {}) do
                        episodes[tostring(episode.episode_number)]=episode.name
                        if episode.episode_number==data.episode then episode_title=episode.name end
                    end
                    publish(data,title,episode_title,episodes)
                end)
            end
        end)
    end
    if data.tmdb_id then resolved(data.tmdb_id);return end
    local base_search='search/'..data.kind..'?language='..locale..'&query='..encode(data.title)
    local search=base_search
    if data.year then search=search..(data.kind=='tv' and '&first_air_date_year=' or '&year=')..data.year end
    get(search,function(result)
        if gen~=generation or not result then return end
        local match=fmt.match_result(result.results,data)
        if match then resolved(match.id)
        elseif data.year then
            -- Production and release dates can differ by one year between catalogs.
            get(base_search,function(broader)
                if gen~=generation or not broader then return end
                local nearby=fmt.match_result(broader.results,data,true)
                if nearby then resolved(nearby.id) end
            end)
        end
    end)
end
local function schedule()
    if timer then timer:kill() end
    timer=mp.add_timeout(0.3,refresh)
end
local function clear()
    active=false;current=nil;generation=generation+1;cancel()
    mp.set_property_native('user-data/readable-title',{})
    mp.set_property('title','${media-title}')
end
mp.register_event('start-file',clear)
mp.register_event('end-file',clear)
mp.register_event('file-loaded',function() active=true;schedule() end)
mp.observe_property('current-tracks/audio','native',schedule)
mp.observe_property('media-title','string',schedule)
mp.observe_property('user-data/guessit','native',schedule)
