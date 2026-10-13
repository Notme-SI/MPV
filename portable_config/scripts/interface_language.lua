local utils=require 'mp.utils'
local ui=dofile(mp.command_native({'expand-path','~~/extensions/ui_locale.lua'}))
local path=mp.command_native({'expand-path','~~/script-opts/interface.conf'})
local current=ui.language()
local function menu()
    return {type='interface-language',title=ui.text('Язык интерфейса'),keep_open=true,items={
        {title='Русский',active=current=='ru',value={'script-message-to','interface_language','choose','ru'}},
        {title='English',active=current=='en',value={'script-message-to','interface_language','choose','en'}},
    },footnote=ui.text('Меняет интерфейс и названия. Озвучка и субтитры сохраняются.')}
end
local function publish()
    mp.set_property_native('user-data/interface-language',current)
    mp.commandv('script-message-to','uosc','update-menu',utils.format_json(menu()))
end
mp.register_script_message('choose',function(value)
    if value~='ru' and value~='en' then return end
    local f=io.open(path,'wb')
    if not f then mp.osd_message(ui.text('Не удалось сохранить язык интерфейса'),3);return end
    local ok=f:write('language='..value..'\n')
    local closed=f:close()
    if not ok or not closed then mp.osd_message(ui.text('Не удалось сохранить язык интерфейса'),3);return end
    current=value;publish()
end)
mp.add_key_binding(nil,'menu',function()
    mp.commandv('script-message-to','uosc','open-menu',utils.format_json(menu()))
end)
publish()
