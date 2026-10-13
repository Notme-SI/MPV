local ui=dofile(mp.command_native({'expand-path','~~/extensions/ui_locale.lua'}))
ui.install_messages()
-- Native mpv picture controls with a persistent, independent uosc menu.
local utils=require 'mp.utils'
local input=require 'mp.input'
local labels={brightness='Яркость',contrast='Контрастность',saturation='Насыщенность',gamma='Гамма',hue='Оттенок'}
local order={'brightness','contrast','saturation','gamma','hue'}
local values={brightness=0,contrast=0,saturation=0,gamma=0,hue=0}
require('mp.options').read_options(values,'picture_controls')
local path=mp.command_native({'expand-path','~~/script-opts/picture_controls.conf'})
for _,key in ipairs(order) do
    values[key]=math.max(-100,math.min(100,tonumber(values[key]) or 0))
    mp.set_property_number(key,values[key])
end
local function menu()
    local items={}
    for _,key in ipairs(order) do
        items[#items+1]={title=labels[key]..': '..string.format('%+g',values[key]),value=key,
            actions={{name='edit',icon='edit',label='Ввести значение'},
                {name='minus',icon='remove',label='Уменьшить'},
                {name='plus',icon='add',label='Увеличить'},
                {name='reset',icon='restart_alt',label='Сбросить'}}}
    end
    items[#items+1]={title='Сбросить все настройки',icon='restart_alt',value='reset-all'}
    return {type='picture-controls',title='Изображение',keep_open=true,items=items,item_actions_place='outside',
        callback={mp.get_script_name(),'event'},footnote='Нажмите на параметр, чтобы ввести число. Кнопки - / +: шаг 1.'}
end
local function open_menu()
    mp.commandv('script-message-to','uosc','open-menu',utils.format_json(menu()))
end
local function edit(key)
    mp.commandv('script-message-to','uosc','close-menu')
    input.get({prompt=labels[key]..' (-100 ... 100):',default_text=tostring(values[key]),keep_open=true,
        submit=function(text)
            local value=tonumber(((text or ''):gsub(',','.')))
            if not value or value~=value or value < -100 or value > 100 then
                input.log('Введите число от -100 до 100.');return
            end
            local ok=mp.set_property_number(key,value)
            if not ok then input.log('Не удалось применить значение.');return end
            input.terminate()
        end,
        closed=function() mp.add_timeout(0.05,open_menu) end})
end
local timer,dirty
local function save()
    if not dirty then return end
    local f=io.open(path,'wb')
    local ok=f~=nil
    if f then
        for _,key in ipairs(order) do if not f:write(key..'='..values[key]..'\n') then ok=false end end
        if not f:close() then ok=false end
    end
    if ok then dirty=false else mp.osd_message('Не удалось сохранить настройки изображения',3) end
end
for _,key in ipairs(order) do
    mp.observe_property(key,'number',function(_,value)
        if value==nil or value==values[key] then return end
        values[key]=value;dirty=true
        if timer then timer:kill() end
        timer=mp.add_timeout(0.5,save)
        mp.commandv('script-message-to','uosc','update-menu',utils.format_json(menu()))
    end)
end
mp.register_script_message('event',function(json)
    local e=utils.parse_json(json)
    if not e or e.type~='activate' then return end
    if e.value=='reset-all' then
        for _,key in ipairs(order) do mp.set_property_number(key,0) end
    elseif labels[e.value] then
        if not e.action or e.action=='edit' then edit(e.value);return end
        local old=mp.get_property_number(e.value,0)
        local value=e.action=='reset' and 0 or old+(e.action=='minus' and -1 or 1)
        mp.set_property_number(e.value,math.max(-100,math.min(100,value)))
    end
end)
mp.add_key_binding(nil,'menu',open_menu)
mp.register_event('shutdown',save)
