-- Remember one window size for all videos; never store media names or positions.
local utils = require 'mp.utils'
local path = mp.command_native({'expand-path', '~~/window-state.json'})
local saved, last_written = {}, nil
local file = io.open(path, 'rb')
if file then
    local text = file:read('*all'); file:close()
    saved = utils.parse_json(text) or {}
end
local function valid_size(w,h)
    return type(w)=='number' and type(h)=='number' and w>=200 and h>=120 and w<=16384 and h<=16384
end
if valid_size(saved.width, saved.height) then
    mp.set_property('geometry', string.format('%dx%d', saved.width, saved.height))
end
if saved.maximized == true then mp.set_property_bool('window-maximized', true) end

local ready, settled, debounce = false, false, nil
local function write_state()
    if not valid_size(saved.width,saved.height) then return end
    local text = utils.format_json(saved)
    if text==last_written then return end
    local out = io.open(path, 'wb')
    if out then out:write(text); out:close(); last_written=text end
end
local function capture()
    if not ready or mp.get_property_bool('fullscreen', false) or mp.get_property_bool('window-minimized', false) then return end
    local size = mp.get_property_native('osd-dimensions') or {}
    if not valid_size(size.w,size.h) then return end
    saved.maximized = mp.get_property_bool('window-maximized', false)
    if not saved.maximized then saved.width, saved.height = math.floor(size.w), math.floor(size.h) end
    write_state()
end
local function changed()
    if debounce then debounce:kill() end
    debounce=mp.add_timeout(0.5,capture)
end
-- Clamp restored dimensions when this configuration is moved to a smaller screen.
mp.observe_property('osd-dimensions','native',function(_,size)
    if not settled and size and valid_size(size.w,size.h) then
        settled=true
        if valid_size(saved.width,saved.height) and not mp.get_property_bool('fullscreen',false)
            and not mp.get_property_bool('window-maximized',false) then
            local sw=mp.get_property_number('display-width',0)
            local sh=mp.get_property_number('display-height',0)
            if sw>0 and sh>0 then
                local w=math.min(saved.width,math.floor(sw*0.95))
                local h=math.min(saved.height,math.floor(sh*0.90))
                if w~=saved.width or h~=saved.height then mp.set_property('geometry',string.format('%dx%d',w,h)) end
            end
        end
        mp.add_timeout(0.7,function() ready=true; changed() end)
    end
    changed()
end)
for _,name in ipairs({'window-maximized','window-minimized','fullscreen'}) do mp.observe_property(name,'bool',changed) end
mp.register_event('shutdown',function() capture(); write_state() end)
