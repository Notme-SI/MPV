-- A transient, clickable skip suggestion above the lower player controls.
local ui=dofile(mp.command_native({'expand-path','~~/extensions/ui_locale.lua'}))
local utils=require 'mp.utils'
local assdraw=require 'mp.assdraw'
local overlay=mp.create_osd_overlay('ass-events')
overlay.z=1001
local cue,box,hover,bound=nil,nil,false,false
local labels={intro='Пропустить: Заставку',recap='Пропустить: Ранее в сериале',credits='Пропустить: Титры',preview='Пропустить: Анонс'}
local draw
local function clicked()
    local t=mp.get_property_number('time-pos',-1)
    if cue and box and t>=cue.start and (not cue['end'] or t<cue['end']) then
        mp.commandv('script-binding','theintrodb/theintrodb-skip-next')
    end
end
draw=function()
    local w,h=mp.get_osd_size()
    local t=mp.get_property_number('time-pos',-1)
    local visible=cue and labels[cue.kind] and w>0 and h>0 and t>=cue.start and (not cue['end'] or t<cue['end'])
        and not mp.get_property_bool('idle-active',true)
        and not mp.get_property_bool('user-data/mpv/console/open',false)
    if not visible then
        box=nil;overlay:remove()
        if bound then mp.remove_key_binding('click');bound=false end
        mp.set_property_native('user-data/skip-prompt-visible',false)
        return
    end
    local scale=math.max(0.65,math.min(2,h/720))
    local widths=ui.language()=='en' and {intro=165,recap=180,credits=195,preview=195} or {intro=280,recap=360,credits=245,preview=245}
    local bw=widths[cue.kind]*scale
    local bh=46*scale
    local x1=w-25*scale
    local y1=h-105*scale
    box={x0=x1-bw,y0=y1-bh,x1=x1,y1=y1}
    local mouse=mp.get_property_native('mouse-pos',{})
    hover=mouse.hover~=false and mouse.x and mouse.y and mouse.x>=box.x0 and mouse.x<=box.x1 and mouse.y>=box.y0 and mouse.y<=box.y1
    if hover and not bound then
        mp.add_forced_key_binding('MBTN_LEFT','click',function(event)
            if event.event=='up' or event.event=='press' then clicked() end
        end,{complex=true})
        bound=true
    elseif not hover and bound then mp.remove_key_binding('click');bound=false end
    local ass=assdraw.ass_new()
    local radius=12*scale
    local function panel(tags,x0,y0,x1,y1)
        ass:new_event()
        ass:append('{\\an7\\pos(0,0)\\bord0\\shad0'..tags..'}')
        ass:draw_start()
        ass:round_rect_cw(x0 or box.x0,y0 or box.y0,x1 or box.x1,y1 or box.y1,radius)
        ass:draw_stop()
    end
    -- Lightweight glass styling: live video remains visible through the panel.
    -- ASS blends transparent layers; it does not blur or refract the video below.
    panel(string.format('\\1c&H000000&\\1a&HE0&\\blur%.2f',4*scale),
        box.x0,box.y0+2*scale,box.x1,box.y1+2*scale)
    panel('\\1c&H181818&\\1a&H'..(hover and '78' or '88')..'&')
    -- A restrained vertical sheen, brighter at the top edge.
    for i=0,11 do
        local alpha=math.floor((hover and 204 or 220)+i*2.4)
        panel(string.format('\\1c&HFFFFFF&\\1a&H%02X&\\clip(%d,%d,%d,%d)',
            math.min(250,alpha),math.floor(box.x0),math.floor(box.y0+bh*i/12),
            math.ceil(box.x1),math.floor(box.y0+bh*(i+1)/12)))
    end
    panel(string.format('\\1a&HFF&\\3c&HFFFFFF&\\3a&H%s&\\bord%.2f\\blur%.2f',
        hover and 'AE' or 'CA',0.75*scale,0.3*scale))
    ass:new_event()
    ass:append(string.format('{\\an5\\pos(%.1f,%.1f)\\fnSegoe UI Semibold\\fs%.1f\\1c&HFFFFFF&\\1a&H00&\\3c&H000000&\\3a&H90&\\4c&H000000&\\4a&H80&\\bord%.2f\\shad%.2f\\blur%.2f}%s',
        (box.x0+box.x1)/2,(box.y0+box.y1)/2,30*scale,0,0,0,ui.text(labels[cue.kind])))
    overlay.res_x=w;overlay.res_y=h;overlay.data=ass.text;overlay:update()
    mp.set_property_native('user-data/skip-prompt-visible',true)
    mp.set_property_native('user-data/skip-prompt-box',box)
end
mp.observe_property('user-data/skip-prompt','native',function(_,data) cue=type(data)=='table' and data.kind and data or nil;draw() end)
for _,name in ipairs({'time-pos','osd-dimensions','mouse-pos','user-data/mpv/console/open','user-data/interface-language'}) do mp.observe_property(name,'native',draw) end
mp.register_event('end-file',function() cue=nil;draw() end)
