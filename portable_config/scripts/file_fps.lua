-- Static source metadata, independent of titles, crop and playback speed.
local info=dofile(mp.command_native({'expand-path','~~/extensions/media_info.lua'}))
local loaded=false
local function publish(data)
    mp.set_property_native('user-data/media-info',data)
    mp.set_property('user-data/file-fps/label',data.fps or '')
    mp.set_property('user-data/file-fps/suffix','')
end
local function refresh()
    if not loaded then publish({badges={}});return end
    publish(info.describe(mp.get_property_native('current-tracks/video'),
        mp.get_property_native('current-tracks/audio'),mp.get_property_native('video-dec-params'),
        mp.get_property_number('container-fps')))
end
local function clear() loaded=false;refresh() end
mp.register_event('start-file',clear)
mp.register_event('end-file',clear)
mp.register_event('file-loaded',function() loaded=true;refresh() end)
for _,property in ipairs({'current-tracks/video','current-tracks/audio','video-dec-params','container-fps'}) do
    mp.observe_property(property,'native',refresh)
end
refresh()
