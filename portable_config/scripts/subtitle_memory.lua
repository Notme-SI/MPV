local root=mp.command_native({'expand-path','~~/'})
local ui=dofile(root..'/extensions/ui_locale.lua')
ui.install_messages()
local utils=require 'mp.utils'
local fmt=dofile(root..'/extensions/title_format.lua')
local prefs=dofile(root..'/extensions/playback_preferences.lua')
local store_path=dofile(mp.command_native({'expand-path','~~/'})..'/extensions/user_settings.lua').path('subtitle-preferences.json')
local data={enabled=true,series={}}
local file=io.open(store_path,'rb')
if file then
    local decoded=utils.parse_json(file:read('*a'));file:close()
    if type(decoded)=='table' and type(decoded.series)=='table' then data=decoded end
end
local key,ready,last_sid,last_visible,waiting,generation=nil,false,nil,nil,false,0
local function ignored() return mp.get_time()<mp.get_property_number('user-data/subtitle-memory-ignore-until',0) end
local function series_key()
    local list=mp.get_property_native('playlist',{})
    local item=list[mp.get_property_number('playlist-pos',-1)+1] or {}
    local identity=fmt.parse(item.title or mp.get_property('media-title') or mp.get_property('filename',''))
    if identity.kind=='tv' and #fmt.normalize(identity.title)>1 then return 'show:'..fmt.normalize(identity.title) end
    local hash=mp.get_property('path',''):match('[?&]link=(%x+)')
    if hash and #hash==40 then return 'torrent:'..hash:lower() end
end
local function save()
    local count=0;for _ in pairs(data.series) do count=count+1 end
    while count>500 do
        local oldest,stamp
        for k,v in pairs(data.series) do
            local at=type(v)=='table' and tonumber(v.updated) or 0
            at=at or 0
            if k~=key and (not stamp or at<stamp) then oldest,stamp=k,at end
        end
        if not oldest then break end
        data.series[oldest]=nil;count=count-1
    end
    local f=io.open(store_path,'wb')
    if not f then mp.osd_message('Не удалось сохранить выбор субтитров',3);return end
    local ok=f:write(utils.format_json(data));local closed=f:close()
    if not ok or not closed then mp.osd_message('Не удалось сохранить выбор субтитров',3) end
end
local function chosen()
    local value=key and data.series[key]
    return type(value)=='table' and value or nil
end
local function publish()
    mp.set_property_native('user-data/subtitle-memory',{enabled=data.enabled~=false,series=key~=nil,saved=chosen()~=nil})
end
local function baseline()
    last_sid=mp.get_property('sid','no');last_visible=mp.get_property_bool('sub-visibility',true)
end
local function restore()
    local value=chosen()
    if not value or data.enabled==false or ignored() then waiting=false;return end
    local id=value.off and 'no' or prefs.find_subtitle(mp.get_property_native('track-list',{}),value,fmt.normalize)
    waiting=id==nil
    if not id then return end
    last_sid=tostring(id);last_visible=value.visible~=false
    mp.set_property('file-local-options/sid',last_sid)
    mp.set_property_bool('file-local-options/sub-visibility',last_visible)
    if value.off then mp.set_property('file-local-options/secondary-sid','no') end
end
local function remember()
    if not ready or not key or data.enabled==false then return end
    local sid=mp.get_property('sid','no')
    local visible=mp.get_property_bool('sub-visibility',true)
    if sid==last_sid and visible==last_visible then return end
    last_sid,last_visible=sid,visible
    if ignored() then waiting=false;return end
    local value
    if sid=='no' then value={off=true}
    else
        for _,track in ipairs(mp.get_property_native('track-list',{})) do
            if track.type=='sub' and tostring(track.id)==sid then value=prefs.subtitle(track,fmt.normalize);break end
        end
    end
    if not value then return end
    value.visible=visible;value.updated=os.time()
    waiting=false;data.series[key]=value;save();publish()
end
mp.register_event('start-file',function() generation=generation+1;ready=false;key=nil;waiting=false end)
mp.add_hook('on_preloaded',80,function() key=series_key();restore();publish() end)
mp.register_event('file-loaded',function()
    local gen=generation
    mp.add_timeout(0,function() if gen==generation then restore();baseline() end end)
    mp.add_timeout(0.7,function() if gen==generation then baseline();ready=true end end)
end)
mp.observe_property('sid','string',remember)
mp.observe_property('sub-visibility','bool',remember)
mp.observe_property('track-list','native',function()
    if waiting then local gen=generation;mp.add_timeout(0,function() if gen==generation and waiting then restore() end end) end
end)
mp.register_event('end-file',function() generation=generation+1;ready=false;key=nil;waiting=false;publish() end)
local function menu()
    local value=chosen()
    local description='Выбор ещё не сохранён'
    if value then description=value.off and 'Выключены' or (value.title~='' and value.title or value.lang or '') end
    return {type='subtitle-memory',title='Субтитры сериала',keep_open=true,items={
        {title='Запоминать выбранные субтитры',hint=data.enabled~=false and 'ВКЛ' or 'ВЫКЛ',value={'script-binding','subtitle_memory/toggle'}},
        {title='Сохранённый выбор',hint=description,selectable=false},
        {title='Забыть выбор для этого сериала',selectable=value~=nil,value={'script-binding','subtitle_memory/forget'}},
    },footnote='Сохраняет дорожку и отключение. Если подходящей дорожки нет, используются языки по умолчанию.'}
end
local function update() publish();mp.commandv('script-message-to','uosc','update-menu',utils.format_json(menu())) end
mp.add_key_binding(nil,'menu',function() mp.commandv('script-message-to','uosc','open-menu',utils.format_json(menu())) end)
mp.add_key_binding(nil,'toggle',function() data.enabled=data.enabled==false;save();update() end)
mp.add_key_binding(nil,'forget',function() if key then data.series[key]=nil;waiting=false;save();update() end end)
publish()
