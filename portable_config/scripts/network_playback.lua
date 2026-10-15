-- Local extension: bounded reconnects, network cache presets and on-demand diagnostics.
local root=mp.command_native({'expand-path','~~/'})
local ui=dofile(root..'/extensions/ui_locale.lua');ui.install_messages()
local utils=require 'mp.utils'
local policy=dofile(root..'/extensions/playback_preferences.lua')
local ts=dofile(root..'/extensions/torrserver.lua')
local opts={reconnect=true,buffer='auto'}
dofile(mp.command_native({'expand-path','~~/'})..'/extensions/user_settings.lua').options(opts,'network_playback')
local profiles={auto=false,normal={seconds=60,bytes=256*1024*1024,wait=2},large={seconds=180,bytes=512*1024*1024,wait=3}}
if profiles[opts.buffer]==nil then opts.buffer='auto' end
local session,pending,restarting,held,timer
local diagnostics=false
local server={scheme='http',host='127.0.0.1',port='8090',use_edl=true}
dofile(mp.command_native({'expand-path','~~/'})..'/extensions/user_settings.lua').options(server,'torrserver-loader')
local origin=server.scheme..'://'..server.host..':'..server.port
local matches_server=ts.matcher(origin)
local stat,request,request_generation={},nil,0
local function save()
    local f=io.open(dofile(mp.command_native({'expand-path','~~/'})..'/extensions/user_settings.lua').path('script-opts/network_playback.conf'),'wb')
    if not f then mp.osd_message('Не удалось сохранить настройки сети',3);return end
    local ok=f:write('reconnect='..(opts.reconnect and 'yes' or 'no')..'\nbuffer='..opts.buffer..'\n');local closed=f:close()
    if not ok or not closed then mp.osd_message('Не удалось сохранить настройки сети',3) end
end
local function status(state)
    mp.set_property_native('user-data/network-playback',{state=state,attempt=session and session.tries or 0,
        reconnect=opts.reconnect,buffer=opts.buffer})
end
local function release_hook()
    if timer then timer:kill();timer=nil end
    mp.remove_key_binding('cancel-reconnect')
    if held then local hook=held;held=nil;hook:cont() end
end
local function cancel()
    pending,restarting=nil,nil
    release_hook();status(session and session.active and 'playing' or 'idle')
end
local function entry_index(id)
    for index,item in ipairs(mp.get_property_native('playlist',{})) do if item.id==id then return index-1,item end end
end
local function selected_id()
    local index=mp.get_property_number('playlist-pos',-1)
    local item=mp.get_property_native('playlist',{})[index+1]
    return item and item.id
end
local function capture()
    if not session or not session.active then return end
    local time=mp.get_property_number('time-pos')
    if time then session.time=time end
    session.duration=mp.get_property_number('duration',session.duration)
    session.seekable=mp.get_property_bool('seekable',session.seekable)
    session.pause=mp.get_property_bool('pause',false)
    session.intentional_end=mp.get_property('end','none')~='none' or mp.get_property('length','none')~='none'
end
mp.register_event('start-file',function(event)
    local path=mp.get_property('path','')
    if restarting and restarting.id==event.playlist_entry_id then
        session=restarting;restarting=nil
    else
        cancel();session={id=event.playlist_entry_id,path=path,time=0,tries=0,stable=0,loaded=false}
    end
    session.path=path;session.active=true
    status('loading')
end)
mp.add_hook('on_load',70,function()
    if session and session.resume then
        if session.seekable then mp.set_property('file-local-options/start',tostring(math.max(0,session.time-2))) end
        mp.set_property_bool('pause',session.pause==true)
        session.resume=nil
    end
    if policy.network(mp.get_property('path','')) then
        local profile=profiles[opts.buffer]
        if profile then
            mp.set_property('file-local-options/cache','yes')
            mp.set_property_number('file-local-options/cache-secs',profile.seconds)
            mp.set_property_number('file-local-options/demuxer-max-bytes',profile.bytes)
            mp.set_property_number('file-local-options/cache-pause-wait',profile.wait)
        end
    end
end)
mp.register_event('file-loaded',function() if session then session.loaded=true;capture();status('playing') end end)
mp.add_periodic_timer(1,function()
    if session and session.active then
        local previous=session.time;capture()
        if not session.pause and session.time>previous and session.time-previous<3 then
            session.stable=session.stable+session.time-previous
            if session.stable>=60 then session.tries=0;session.stable=0 end
        end
    end
end)
mp.add_hook('on_unload',90,capture)
mp.register_event('end-file',function(event)
    if not session then return end
    session.active=false
    local limit=session.loaded and 5 or 2
    if opts.reconnect and session.id==event.playlist_entry_id and policy.retry(session,event.reason) then
        if session.tries<limit then
            session.tries=session.tries+1;session.stable=0;pending=session;status('waiting')
        else pending=nil;status('failed');mp.osd_message('Не удалось восстановить поток. Проверьте сеть или TorrServer.',5) end
    else pending=nil;status('idle') end
end)
mp.add_hook('on_after_end_file',50,function(hook)
    if not pending then return end
    local attempt=pending
    local delay=math.min(10,attempt.tries*attempt.tries)
    hook:defer();held=hook
    mp.osd_message(string.format(ui.text('Восстановление потока: попытка %d. Esc - отменить'),attempt.tries),delay+1)
    mp.add_forced_key_binding('ESC','cancel-reconnect',function() cancel() end)
    timer=mp.add_timeout(delay,function()
        local index,item=entry_index(attempt.id)
        local selected=selected_id()
        if pending~=attempt or not opts.reconnect or not index or item.filename~=attempt.path or (selected and selected~=attempt.id) then
            cancel();return
        end
        pending=nil;restarting=attempt;attempt.resume=true
        mp.commandv('playlist-play-index',index,'yes')
        mp.remove_key_binding('cancel-reconnect');release_hook()
    end)
end)
mp.observe_property('playlist-pos','number',function()
    if held and pending and selected_id()~=pending.id then cancel() end
end)
mp.observe_property('playlist','native',function() if pending and not entry_index(pending.id) then cancel() end end)
mp.register_event('shutdown',function() cancel();if request then mp.abort_async_command(request) end end)
mp.add_key_binding(nil,'cancel',cancel)
local function stop_stat()
    request_generation=request_generation+1
    if request then mp.abort_async_command(request);request=nil end
    stat={}
end
local function poll_stat()
    if not diagnostics or request then return end
    local path=mp.get_property('path','')
    local hash=path:match('[?&]link=(%x+)')
    if not matches_server(path) or not hash or #hash~=40 then stat={};return end
    local gen=request_generation
    request=mp.command_native_async({name='subprocess',capture_stdout=true,capture_stderr=true,args={
        'curl','--silent','--fail','--connect-timeout','2','--max-time','3','--max-filesize','1048576',
        origin..'/stream?link='..hash..'&stat'}},function(ok,result)
        if gen~=request_generation then return end
        request=nil
        local value=ok and result and result.status==0 and utils.parse_json(result.stdout or '') or nil
        stat=type(value)=='table' and value or {unavailable=true}
    end)
end
local function number(value,format)
    value=tonumber(value)
    if not value or value~=value or value==math.huge then return ui.text('Нет данных') end
    return string.format(format or '%.0f',value)
end
local function megabytes(value) value=tonumber(value);return value and value/1048576 end
local function menu()
    local recovery=mp.get_property_native('user-data/network-playback',{})
    local states={waiting='Повторное подключение',failed='Ошибка подключения',loading='Открытие потока',idle='Нет воспроизведения',playing='Воспроизведение'}
    local state=states[recovery.state] or 'Нет воспроизведения'
    if mp.get_property_bool('paused-for-cache',false) then state='Ожидание данных'
    elseif mp.get_property_bool('pause',false) and recovery.state=='playing' then state='Пауза' end
    local cache=mp.get_property_native('demuxer-cache-state',{})
    local items={
        {title='Восстановление после обрыва',hint=opts.reconnect and 'ВКЛ' or 'ВЫКЛ',value={'script-binding','network_playback/toggle'}},
        {title='Буфер',items={
            {title='Авто',hint='Настройки mpv',active=opts.buffer=='auto',value={'script-message-to','network_playback','buffer','auto'}},
            {title='Стандартный',hint='До 60 с / 256 МБ',active=opts.buffer=='normal',value={'script-message-to','network_playback','buffer','normal'}},
            {title='Увеличенный',hint='До 180 с / 512 МБ',active=opts.buffer=='large',value={'script-message-to','network_playback','buffer','large'}},
        }},
        {title='Состояние',hint=state,selectable=false},
        {title='Запас видео',hint=number(mp.get_property_number('demuxer-cache-duration'),'%.1f')..' '..ui.text('с'),selectable=false},
        {title='Буфер плеера',hint=number(cache['fw-bytes'] and cache['fw-bytes']/1048576,'%.1f')..' '..ui.text('МБ'),selectable=false},
        {title='Скорость чтения',hint=number(mp.get_property_number('cache-speed') and mp.get_property_number('cache-speed')/1048576,'%.2f')..' '..ui.text('МБ/с'),selectable=false},
        {title='Пропущено кадров',hint=number(mp.get_property_number('frame-drop-count')),selectable=false},
        {title='Разница аудио и видео',hint=number(mp.get_property_number('avsync'),'%.3f')..' '..ui.text('с'),selectable=false},
    }
    if matches_server(mp.get_property('path','')) then
        items[#items+1]={title='TorrServer',hint=stat.unavailable and 'Нет ответа' or stat.download_speed and 'Подключён' or 'Ожидание данных',selectable=false}
        items[#items+1]={title='Загрузка TorrServer',hint=number(megabytes(stat.download_speed),'%.2f')..' '..ui.text('МБ/с'),selectable=false}
        items[#items+1]={title='Пиры / сиды',hint=number(stat.active_peers)..' / '..number(stat.connected_seeders),selectable=false}
    end
    if pending then items[#items+1]={title='Отменить восстановление',value={'script-binding','network_playback/cancel'}} end
    return {type='network-playback',title='Сеть и буфер',keep_open=true,items=items,
        footnote='Буфер помогает при кратких просадках сети. Новый размер действует со следующего открытия файла.'}
end
local function update_menu() if diagnostics then mp.commandv('script-message-to','uosc','update-menu',utils.format_json(menu())) end end
mp.add_key_binding(nil,'menu',function()
    diagnostics=true;poll_stat();mp.commandv('script-message-to','uosc','open-menu',utils.format_json(menu()))
end)
local function settings_changed()
    save();status(mp.get_property_native('user-data/network-playback',{}).state or 'idle');update_menu()
end
mp.add_key_binding(nil,'toggle',function() opts.reconnect=not opts.reconnect;if not opts.reconnect then cancel() end;settings_changed() end)
mp.register_script_message('buffer',function(value) if profiles[value]~=nil then opts.buffer=value;settings_changed() end end)
mp.observe_property('user-data/uosc/menu/type','string',function(_,kind)
    diagnostics=kind=='network-playback'
    if not diagnostics then stop_stat() end
end)
mp.register_event('start-file',stop_stat)
mp.register_event('end-file',stop_stat)
mp.add_periodic_timer(2,function() if diagnostics then poll_stat();update_menu() end end)
status('idle')
