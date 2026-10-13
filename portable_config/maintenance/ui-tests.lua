return function(path)
    local info=dofile(path('extensions/media_info.lua'))
    local function video(w,h,fps,codec) return {['demux-w']=w,['demux-h']=h,['demux-fps']=fps,codec=codec or 'hevc'} end
    local function badge(data,kind)
        for _,entry in ipairs(data.badges) do if entry.kind==kind then return entry.text end end
    end
    local data=info.describe(video(3840,1600,24000/1001),{codec='eac3'},{w=1920,h=800},60)
    assert(badge(data,'quality')=='4K' and badge(data,'video')=='HEVC')
    assert(badge(data,'audio')=='E-AC-3' and data.fps=='23,976 FPS','Static source metadata')
    assert(badge(info.describe(video(1440,1080,25),nil,{},nil),'quality')=='1080p','4:3 source')
    assert(badge(info.describe(video(1920,800,24),nil,{},nil),'quality')=='1080p','Cinemascope source')
    assert(info.describe(video(0,0,0),nil,{},29.97).fps=='29,97 FPS','Container fallback')
    assert(info.describe(video(nil,nil,math.huge),nil,{},0).fps==nil,'Invalid FPS')
    assert(#info.describe(nil,nil,{},0).badges==0,'New file clears old metadata')
    assert(info.describe({image=true,['demux-fps']=30},nil,{},60).fps==nil,'No FPS for cover images')

    -- Check the real numeric-input callback without creating settings or opening a window.
    local real=mp
    local saved_input,saved_options=package.loaded['mp.input'],package.loaded['mp.options']
    local saved_ui=package.loaded['mpv-build/ui_locale']
    local values,messages,bindings,input_opts={},{},{},nil
    local log_count,closed=0,false
    local mock={command_native=function(args) return path(args[2]:gsub('^~~/','')) end,
        get_property=function(_,default) return default end,
        get_property_native=function(_,default) return default end,
        get_script_name=function() return 'picture_controls' end,
        set_property_number=function(key,value) values[key]=value;return true end,
        get_property_number=function(key,default) return values[key] or default end,
        observe_property=function() end,commandv=function() end,register_event=function() end,
        add_key_binding=function(_,name,fn) bindings[name]=fn end,
        register_script_message=function(name,fn) messages[name]=fn end}
    local ok,err=xpcall(function()
        mp=mock
        package.loaded['mp.options']={read_options=function() end}
        package.loaded['mp.input']={get=function(opts) input_opts=opts end,
            log=function() log_count=log_count+1 end,terminate=function() closed=true end}
        dofile(path('scripts/picture_controls.lua'))
        local utils=require 'mp.utils'
        messages.event(utils.format_json({type='activate',value='contrast',action='edit'}))
        assert(input_opts and input_opts.default_text=='0')
        for _,bad in ipairs({'','abc','-101','101','nan','inf'}) do input_opts.submit(bad) end
        assert(log_count==6 and values.contrast==0 and not closed,'Reject invalid values')
        input_opts.submit('-12,5')
        assert(values.contrast==-12.5 and closed,'Comma decimal input')
        input_opts.submit('100');assert(values.contrast==100,'Upper boundary')
        input_opts.submit('-100');assert(values.contrast==-100,'Lower boundary')
    end,debug.traceback)
    mp=real
    package.loaded['mp.input'],package.loaded['mp.options']=saved_input,saved_options
    package.loaded['mpv-build/ui_locale']=saved_ui
    assert(ok,err)
end
