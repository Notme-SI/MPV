local ui=dofile(mp.command_native({'expand-path','~~/extensions/ui_locale.lua'}))
ui.install_messages()
-- Store dubbing preferences per series; never record play positions or watched episodes.
local utils=require 'mp.utils'
local store_path=mp.command_native({'expand-path','~~/audio-preferences.json'})
local data={enabled=true,series={}}
local file=io.open(store_path,'rb')
if file then local parsed=utils.parse_json(file:read('*a'));file:close();if type(parsed)=='table' and type(parsed.series)=='table' then data=parsed end end
local key,ready,applying,last_aid=nil,false,false,nil
local function normalize(s)
    s=(s or ''):lower():gsub('Ё','ё'):gsub('\208[\144-\175]',function(c)
        local b=c:byte(2);return b<160 and string.char(208,b+32) or string.char(209,b-32)
    end)
    return s:gsub('[%p%s]','')
end
local function series_key()
    local playlist=mp.get_property_native('playlist',{})
    local item=playlist[mp.get_property_number('playlist-pos',-1)+1] or {}
    local title=item.title or mp.get_property('media-title') or mp.get_property('filename') or ''
    title=title:gsub('%%(%x%x)',function(h)return string.char(tonumber(h,16)) end)
    title=title:gsub('[?#].*$',''):match('([^/\\]+)$') or title
    local show=title:match('^(.-)[Ss]%d+[Ee]%d+') or title:match('^(.-)%d+[xX]%d+')
    if show and #normalize(show)>1 then return 'show:'..normalize(show) end
    local hash=(mp.get_property('path') or ''):match('[?&]link=(%x+)')
    if hash and #hash==40 then return 'torrent:'..hash:lower() end
    -- Anime commonly has names such as "[Group] Show - 03 [1080p].mkv".
    show=title:gsub('^%b[]%s*',''):match('^(.-)%s+%-%s+%d+')
    if show and #normalize(show)>1 then return 'show:'..normalize(show) end
end
local function save()
    local f=io.open(store_path,'wb')
    if f then f:write(utils.format_json(data));f:close() end
end
local function publish()
    local chosen=key and data.series[key]
    mp.set_property_native('user-data/audio-memory',{enabled=data.enabled~=false,selected=chosen and chosen.title or '',series=key~=nil})
end
local function restore()
    local chosen=key and data.enabled~=false and data.series[key]
    if not chosen then return end
    for _,t in ipairs(mp.get_property_native('track-list',{})) do
        if t.type=='audio' and normalize(t.title)==chosen.match and normalize(t.lang)==chosen.lang then
            applying=true;mp.set_property_number('aid',t.id);last_aid=t.id;applying=false;return
        end
    end
end
mp.register_event('start-file',function() key=nil;ready=false;last_aid=nil end)
mp.register_event('file-loaded',function()
    key=series_key();restore();publish()
    local this_key=key
    mp.add_timeout(0.7,function()
        if key==this_key then last_aid=mp.get_property_number('aid');ready=true end
    end)
end)
mp.observe_property('aid','number',function(_,aid)
    if not ready or applying or not key or data.enabled==false or aid==last_aid then return end
    last_aid=aid
    if mp.get_time()<mp.get_property_number('user-data/audio-memory-ignore-until',0) then return end
    for _,t in ipairs(mp.get_property_native('track-list',{})) do
        if t.type=='audio' and t.id==aid and t.title and normalize(t.title)~='' then
            data.series[key]={title=t.title,match=normalize(t.title),lang=normalize(t.lang)}
            save();publish();return
        end
    end
end)
local function menu_data()
    local chosen=key and data.series[key]
    return {type='audio-memory',title='Озвучка сериала',keep_open=true,items={
        {title='Запоминать выбранную озвучку',hint=data.enabled~=false and 'ВКЛ' or 'ВЫКЛ',
         value={'script-binding','audio_memory/toggle'}},
        {title=chosen and ('Сохранено: '..chosen.title) or 'Выбор ещё не сохранён',selectable=false},
        {title='Забыть выбор для этого сериала',selectable=chosen~=nil,value={'script-binding','audio_memory/forget'}},
    }}
end
local function update_menu() mp.commandv('script-message-to','uosc','update-menu',utils.format_json(menu_data())) end
mp.add_key_binding(nil,'menu',function() mp.commandv('script-message-to','uosc','open-menu',utils.format_json(menu_data())) end)
mp.add_key_binding(nil,'toggle',function() data.enabled=data.enabled==false;save();publish();update_menu() end)
mp.add_key_binding(nil,'forget',function() if key then data.series[key]=nil;save();publish();update_menu() end end)
mp.register_event('end-file',function() ready=false;key=nil end)
publish()
