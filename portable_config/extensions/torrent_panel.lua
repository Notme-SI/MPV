-- Presentation of the loader's own statistics; no requests or playback changes.
local M={}
function M.parse(message)
    if type(message)~='string' then return end
    local file,state,speed,cache,peers,extra=message:match(
        '^%s*Loading (.-)%.%.%.\nCurrent state: (.-)\nTorrent load info:\nSpeed: (.-)\nCache: (.-)\nPeers·Seeders: ([^\n]*)\n*(.*)$')
    if not file then return end
    return {file=file,state=state,speed=speed,cache=cache,peers=peers,extra=extra:match('^%s*(.-)%s*$')}
end
local function escape(value)
    return tostring(value or ''):gsub('\\','\\e'):gsub('{','\\{'):gsub('}','\\}'):gsub('[\r\n]',' ')
end
local function shorten(value,limit)
    local chars={}
    for c in value:gmatch('[%z\1-\127\194-\244][\128-\191]*') do chars[#chars+1]=c end
    if #chars<=limit then return value end
    return table.concat(chars,'',1,limit-1)..'…'
end
function M.render(data,language,w,h)
    local ass=require('mp.assdraw').ass_new()
    local en=language=='en'
    local scale=math.max(0.65,math.min(1.8,h/720))
    local x,y=24*scale,24*scale
    local width=math.min(370*scale,w-2*x)
    local height=(data.extra~='' and 248 or 224)*scale
    ass:new_event()
    ass:append('{\\an7\\pos(0,0)\\bord0\\shad0\\1c&H202020&\\1a&H20&}')
    ass:draw_start();ass:round_rect_cw(x,y,x+width,y+height,12*scale);ass:draw_stop()
    local function text(value,px,py,size,color,bold,align)
        ass:new_event()
        ass:append(string.format('{\\an%d\\pos(%.1f,%.1f)\\fnSegoe UI\\fs%.1f\\1c&H%s&\\bord0\\shad0\\b%d}%s',
            align or 7,px,py,size*scale,color,bold and 1 or 0,escape(value)))
    end
    text(en and 'NETWORK STATISTICS' or 'СТАТИСТИКА СЕТИ',x+18*scale,y+15*scale,15,'C8C8C8',true)
    text(shorten(data.file,48),x+18*scale,y+44*scale,12,'9B9B9B')
    ass:new_event()
    ass:append('{\\an7\\pos(0,0)\\bord0\\shad0\\1c&HFFFFFF&\\1a&HE0&}')
    ass:draw_start();ass:rect_cw(x+18*scale,y+70*scale,x+width-18*scale,y+71*scale);ass:draw_stop()
    local state=data.state
    if not en then
        state=state:gsub('connecting external files','подключение внешних файлов'):gsub('opening','открытие'):gsub('caching','буферизация')
    end
    local cache=en and data.cache or data.cache:gsub(' GB',' ГБ')
    local rows={
        {en and 'State' or 'Состояние',state},
        {en and 'Speed' or 'Скорость',data.speed},
        {en and 'Cache' or 'Кеш',cache},
        {en and 'Peers · seeders' or 'Пиры · сиды',data.peers},
    }
    for i,row in ipairs(rows) do
        local yy=y+(83+(i-1)*32)*scale
        text(row[1],x+18*scale,yy,14,'999999')
        text(row[2],x+width-18*scale,yy,14,'FFFFFF',true,9)
    end
    if data.extra~='' then
        local extra=data.extra
        if not en then extra=extra:gsub('Connected ','Подключено '):gsub(' external files',' внешних файлов'):gsub('Errors:','Ошибки:') end
        text(shorten(extra,48),x+18*scale,y+218*scale,12,'999999')
    end
    return ass.text
end
function M.new(ui)
    local overlay=mp.create_osd_overlay('ass-events')
    overlay.z=1100
    local value,timer
    local function hide()
        value=nil;overlay:remove()
        if timer then timer:kill();timer=nil end
    end
    local function draw()
        local w,h=mp.get_osd_size()
        if not value or w<=0 or h<=0 then overlay:remove();return end
        overlay.res_x=w;overlay.res_y=h
        overlay.data=M.render(value,ui.language(),w,h);overlay:update()
    end
    mp.observe_property('osd-dimensions','native',draw)
    mp.observe_property('user-data/interface-language','native',draw)
    mp.register_event('end-file',hide)
    mp.register_event('shutdown',hide)
    return {
        show=function(message)
            local parsed=M.parse(message)
            if not parsed then return false end
            value=parsed;draw()
            -- Loader refreshes every 0.5s only while buffering.
            if timer then timer:kill() end
            timer=mp.add_timeout(1.2,hide)
            return true
        end,
        hide=hide,
    }
end
return M
