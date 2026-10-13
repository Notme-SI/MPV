local M = {}
-- Compare the server origin without credentials and normalize default ports.
-- Lampa may omit :80 and use a different spelling of URL user information.
local function server_origin(url)
    local scheme, authority = url:match('(https?)://([^/;\\%s]+)')
    if not scheme then return end
    authority = authority:match('.*@(.+)') or authority
    local host, port = authority:match('^(.-):(%d+)$')
    host = (host or authority):lower()
    if host == 'localhost' or host == '127.0.0.1' or host == '[::1]' then host = 'localhost' end
    port = tonumber(port) or (scheme == 'https' and 443 or 80)
    return scheme .. '://' .. host .. ':' .. port
end

function M.matcher(url)
    local expected = server_origin(url)
    return function(path) return expected ~= nil and server_origin(path or '') == expected end
end
local exact = {
    ["Requesting TorrServer's API..."]='Запрос к TorrServer...',
    ["No response from TorrServer's API!"]='TorrServer не ответил',
    ["Invalid BTIH extracted from path!"]='Не удалось определить хеш торрента',
    ["Select an entry of torrent:"]='Выберите серию:',
    ["Select a torrent:"]='Выберите сериал или фильм:',
}
function M.translate(text)
    if exact[text] then return exact[text] end
    -- Translate fixed UI fragments only, leaving filenames untouched.
    if text:match('^Curl error:') then
        return (text:gsub('^Curl error:', 'Ошибка подключения:'):gsub(' status code:', ' код:'))
    end
    if text:match('^Loading ') then
        text=text:gsub('^Loading (.-)%.%.%.\nCurrent state:','Загрузка %1...\nСостояние:')
        local changes={
            {'Torrent load info:', 'Информация о раздаче:'}, {'Speed:', 'Скорость:'},
            {'Cache:', 'Кеш:'}, {'Peers·Seeders:', 'Пиры·Сиды:'}, {' GB', ' ГБ'},
            {'opening', 'открытие'}, {'caching', 'буферизация'},
            {'connecting external files','подключение внешних файлов'},
            {'Connected ', 'Подключено '}, {' external files',' внешних файлов'},
            {'Errors:', 'Ошибки:'},
        }
        for _,pair in ipairs(changes) do text=text:gsub(pair[1],pair[2]) end
    end
    return text
end
function M.install()
    local ui=dofile(mp.command_native({'expand-path','~~/extensions/ui_locale.lua'}))
    ui.install_messages()
    local show=mp.osd_message
    mp.osd_message=function(text,seconds) return show(ui.language()=='en' and text or M.translate(text),seconds) end
    local input=require 'mp.input'
    local select=input.select
    input.select=function(args)
        if args.prompt then args.prompt=ui.language()=='en' and args.prompt or M.translate(args.prompt) end
        return select(args)
    end
end
return M
