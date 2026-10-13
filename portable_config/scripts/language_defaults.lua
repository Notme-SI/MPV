local ui=dofile(mp.command_native({'expand-path','~~/extensions/ui_locale.lua'}))
ui.install_messages()
-- Persistent language defaults; current-file track menus remain available in uosc.
local utils = require 'mp.utils'
local options = {audio='ru', subtitles='forced_ru'}
require('mp.options').read_options(options, 'language_defaults')
local function path(name) return mp.command_native({'expand-path','~~/' .. name}) end
local audio = {
    {'ru','Русская','ru,rus,en,eng'}, {'en','Английская','en,eng,ru,rus'},
    {'ja','Японская','ja,jpn,en,eng,ru,rus'}, {'default','По умолчанию в файле',''},
}
local subs = {
    {'forced_ru','Только форсированные русские'}, {'full_ru','Полные русские'},
    {'full_en','Полные английские'}, {'off','Выключены'},
}
local function write(name, text)
    local f = io.open(path(name),'wb')
    if not f then return false end
    local ok=f:write(text); local closed=f:close()
    return ok~=nil and closed~=nil
end
local function save_settings()
    return write('script-opts/language_defaults.conf','audio='..options.audio..'\nsubtitles='..options.subtitles..'\n')
end
local function menu()
    local items={}
    local function choices(list,key)
        local out={}
        for _,v in ipairs(list) do
            out[#out+1]={title=v[2],active=options[key]==v[1],
                value={'script-message-to','language_defaults','choose',key,v[1]}}
        end
        return out
    end
    items[1]={title='Озвучка по умолчанию',items=choices(audio,'audio')}
    items[2]={title='Субтитры по умолчанию',items=choices(subs,'subtitles')}
    return {type='language-defaults',title='Языки по умолчанию',keep_open=true,items=items}
end
local function publish()
    mp.set_property_native('user-data/language-defaults',options)
    mp.commandv('script-message-to','uosc','update-menu',utils.format_json(menu()))
end
local function save_alang(value)
    local f=io.open(path('mpv.conf'),'rb')
    if not f then return false end
    local text='\n'..f:read('*a'):gsub('\r\n','\n'); f:close()
    local replaced,n=text:gsub('\nalang%s*=[^\n]*','\nalang='..value)
    if n==0 then replaced=replaced..'\nalang='..value..'\n' end
    return write('mpv.conf',replaced:sub(2))
end
local function select_audio(langs)
    mp.set_property_number('user-data/audio-memory-ignore-until',mp.get_time()+1)
    mp.set_property('alang',langs)
    local tracks=mp.get_property_native('track-list',{})
    local first,default,best,rank
    for _,t in ipairs(tracks) do
        if t.type=='audio' then
            first=first or t.id
            if t.default then default=default or t.id end
            local i=0
            for lang in langs:gmatch('[^,]+') do
                i=i+1
                if t.lang and (t.lang:lower()==lang or t.lang:lower():match('^'..lang..'%-')) and (not rank or i<rank) then
                    best,rank=t.id,i
                end
            end
        end
    end
    if best or default or first then mp.set_property_number('aid',best or default or first) end
end
mp.register_script_message('choose',function(key,value)
    local chosen
    for _,entry in ipairs(key=='audio' and audio or key=='subtitles' and subs or {}) do
        if entry[1]==value then chosen=entry; break end
    end
    if not chosen then return end
    local saved
    if key=='audio' then
        saved=save_alang(chosen[3])
        if saved then select_audio(chosen[3]) end
    else
        saved=true
    end
    if saved then options[key]=value; saved=save_settings() end
    publish()
    if saved and key=='subtitles' then
        mp.set_property('sid','auto')
        mp.commandv('script-message-to','sub_select','select-subtitles')
    end
    if not saved then mp.osd_message('Не удалось сохранить языковые настройки',3) end
    publish()
end)
mp.add_key_binding(nil,'menu',function()
    mp.commandv('script-message-to','uosc','open-menu',utils.format_json(menu()))
end)
publish()
