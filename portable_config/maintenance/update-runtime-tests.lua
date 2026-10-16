return function(path)
    local real=mp
    local utils=require 'mp.utils'
    local messages,commands,request,callback={},{},nil,nil
    local mock={
        command_native=function(args)
            if args[1]=='expand-path' then return path('') end
            commands[#commands+1]=args;return {status=0}
        end,
        get_property=function(_,fallback) return fallback end,
        get_property_native=function(_,fallback) return fallback end,
        get_property_number=function(name) if name=='pid' then return 12345 end end,
        commandv=function(...) commands[#commands+1]={...} end,
        command_native_async=function(args,fn) request,callback=args,fn end,
        register_script_message=function(name,fn) messages[name]=fn end,
        add_key_binding=function() end,observe_property=function() end,
        add_timeout=function() end,osd_message=function() end,
    }
    local ok,err=xpcall(function()
        mp=mock;dofile(path('scripts/component_updates.lua'))
        messages.install();assert(#commands==0,'No install before a successful check')
        messages.check()
        assert(request.args[#request.args-1]=='-ReportPath')
        callback(false,{status=1})
        local count=#commands;messages.install();assert(#commands==count,'Failed check must not close the player')
        messages.check()
        local f=assert(io.open(request.args[#request.args],'wb'))
        f:write(utils.format_json({available=1,components={}}));f:close()
        callback(true,{status=0})
        messages.install()
        local worker=commands[#commands-1]
        local joined=table.concat(worker.args,' ')
        assert(worker.detach and joined:find('-WaitProcessId 12345',1,true))
        assert(commands[#commands][1]=='quit','Exit only after launching update coordinator')
    end,debug.traceback)
    mp=real;assert(ok,err)
end
