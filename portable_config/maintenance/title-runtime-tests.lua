return function(path)
    local real=mp
    local options=package.loaded['mp.options']
    local utils=require 'mp.utils'
    local props={path='fixture.mkv',['media-title']='Reacher.S01E04.In.a.Tree.2160p.mkv',
        ['current-tracks/audio']={lang='rus'},['playlist-pos']=0,
        playlist={{filename='fixture.mkv',title='Reacher.S01E04.In.a.Tree.2160p.mkv'}},['user-data/guessit']={}}
    local events,observers,requests,timers={},{},{},{}
    local function get(k,d) if props[k]==nil then return d end;return props[k] end
    local function set(k,v) props[k]=v end
    local function noop() end
    local mock={get_property=get,get_property_native=get,get_property_number=get,
        set_property=set,set_property_native=set,abort_async_command=noop,
        command_native=function() return path('') end,
        observe_property=function(k,_,fn) observers[k]=fn end,
        register_event=function(k,fn) events[k]=fn end,
        add_timeout=function(_,fn)
            local t={callback=fn,active=true,kill=function(self) self.active=false end}
            timers[#timers+1]=t;return t
        end,
        command_native_async=function(args,fn)
            requests[#requests+1]={args=args,callback=fn};return #requests
        end}
    local function tick()
        local copy=timers;timers={}
        for _,t in ipairs(copy) do if t.active then t.callback() end end
    end
    local function respond(n,data)
        assert(requests[n],'missing metadata request '..n)
        requests[n].callback(true,{status=0,stdout=utils.format_json(data)})
    end
    local ok,err=xpcall(function()
        mp=mock;package.loaded['mp.options']={read_options=noop}
        dofile(path('scripts/readable_titles.lua'))
        events['file-loaded']();tick()
        assert(props['user-data/readable-title'].text:find('серия 4',1,true))
        props['current-tracks/audio']={lang='eng'};observers['current-tracks/audio']();tick()
        assert(#requests==2)
        respond(1,{results={{id=99,name='Устаревший ответ',original_name='Reacher'}}})
        assert(#requests==2,'stale response started more requests')
        respond(2,{results={{id=108978,name='Reacher',original_name='Reacher'}}})
        respond(3,{name='Reacher'})
        respond(4,{episodes={{episode_number=4,name='In a Tree'}}})
        assert(props['user-data/readable-title'].text=='Reacher · Season 1, episode 4: In a Tree')
        props['current-tracks/audio']={lang='rus'};observers['current-tracks/audio']();tick()
        respond(5,{results={{id=108978,name='Ричер',original_name='Reacher'}}})
        respond(6,{name='Ричер'})
        respond(7,{episodes={{episode_number=4,name='Укрытие'}}})
        assert(props['user-data/readable-title'].text=='Ричер · Сезон 1, серия 4: Укрытие')
        assert(props['user-data/readable-title'].episodes['4']=='Укрытие')
        assert(props['media-title']==props.playlist[1].title,'source title changed')
        events['end-file']()
        assert(props['user-data/readable-title'].text==nil,'stale title on end-file')
        props['media-title']='Protector.2025.2160p.mkv'
        props.playlist[1].title=props['media-title']
        events['file-loaded']();tick()
        assert(requests[8].args.args[#requests[8].args.args]:find('&year=2025',1,true))
        respond(8,{results={}})
        assert(not requests[9].args.args[#requests[9].args.args]:find('&year=',1,true),'Fallback removes strict year')
        respond(9,{results={{id=1383731,title='Мститель',original_title='Protector',release_date='2026-02-20'}}})
        respond(10,{title='Мститель'})
        assert(props['user-data/readable-title'].text=='Мститель (2025)','Localized movie with release-year offset')
        assert(props['media-title']=='Protector.2025.2160p.mkv','Movie source title preserved')
        events['end-file']()
    end,debug.traceback)
    mp=real;package.loaded['mp.options']=options
    assert(ok,err)
end
