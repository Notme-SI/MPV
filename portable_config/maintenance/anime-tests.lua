return function(path)
    local fmt=dofile(path('extensions/title_format.lua'))
    local anime=dofile(path('extensions/anime_identity.lua'))
    local skips=dofile(path('extensions/skip_segments.lua'))
    local index=anime.index({['Kusuriya no Hitorigoto']=54492,['Kusuriya no Hitorigoto 2nd Season']=58514,
        ['Kusuriya no Hitorigoto 3rd Season']=61987,['The Apothecary Diaries Season 3']=61987})
    for _,raw in ipairs({'Kusuriya no Hitorigoto S3 - 01.mkv','01. Kusuriya no Hitorigoto 3 (WEBRip 1080p).mkv',
        'Kusuriya no Hitorigoto 3rd Season - 01.mkv'}) do
        local data=anime.enrich(raw,fmt.parse(raw),index)
        assert(data.title=='Kusuriya no Hitorigoto' and data.episode==1 and data.season==3,raw)
        assert(data.mal_id=='61987','Third season must not resolve to first season: '..raw)
    end
    local unknown='Kusuriya no Hitorigoto S4 - 01.mkv'
    assert(not anime.enrich(unknown,fmt.parse(unknown),index).mal_id,'Unknown season must not use first-season times')
    local raw='01. Unknown Film 3.mkv'
    assert(anime.enrich(raw,fmt.parse(raw),index).title==fmt.parse(raw).title,'Do not strip unconfirmed titles')
    local chapters={{time=0,title='Prologue'},{time=62.94,title='Opening'},{time=152.993,title='Episode'},
        {time=1335,title='Ending'},{time=1425.053,title='Epilogue'}}
    local native=skips.from_chapters(chapters,1440.085,fmt.normalize)
    assert(math.abs(native.intro[1].start_ms-62940)<0.001 and math.abs(native.intro[1].end_ms-152993)<0.001)
    assert(native.credits[1].start_ms==1335000 and not native.preview,'Epilogue is not automatically skippable')
    assert(not next(skips.from_chapters({{time=0,title='Part 01'},{time=90,title='Part 02'}},1440,fmt.normalize)))
    assert(not next(skips.from_chapters({{time=0,title='Opening'}},1440,fmt.normalize)),'Unknown intro end is unsafe')
    assert(not next(skips.from_chapters({{time=0,title='Opening'},{time=700,title='Episode'}},1440,fmt.normalize)))
    local online={intro={{start_ms=63313,end_ms=153237}},credits={{start_ms=1335252,end_ms=1425384}}}
    local combined=skips.combine({intro={{start_ms=0,end_ms=95000}},preview={{start_ms=1355000}}},online,native)
    assert(combined.intro==native.intro and combined.credits==native.credits and not combined.preview)
    assert(skips.combine({},online,{}).intro==online.intro,'Online fallback for files without chapters')

    -- Exercise the actual clickable prompt in both languages, including a live switch.
    local real=mp
    local saved=package.loaded['mpv-build/ui_locale'];package.loaded['mpv-build/ui_locale']=nil
    local props={['time-pos']=70,['idle-active']=false,['user-data/interface-language']='ru'}
    local observers,overlay={},{}
    local function get(k,d) if props[k]==nil then return d end;return props[k] end
    local function noop() end
    local mock={get_property_native=get,get_property_number=get,get_property_bool=get,
        set_property_native=function(k,v) props[k]=v end,
        command_native=function(a) return path(a[2]:gsub('^~~/','')) end,
        create_osd_overlay=function() return overlay end,get_osd_size=function() return 1280,720 end,
        observe_property=function(k,_,f) observers[k]=f end,register_event=noop,
        add_forced_key_binding=noop,remove_key_binding=noop,commandv=noop}
    overlay.update=noop;overlay.remove=function() overlay.data='' end
    local ok,err=xpcall(function()
        mp=mock
        local ui=dofile(path('extensions/ui_locale.lua'))
        dofile(path('scripts/skip_prompt.lua'))
        for kind,text in pairs({intro={'Пропустить: Заставку','Skip: Intro'},credits={'Пропустить: Титры','Skip: Credits'},
            recap={'Пропустить: Ранее в сериале','Skip: Recap'},preview={'Пропустить: Анонс','Skip: Preview'}}) do
            props['user-data/interface-language']='ru'
            observers['user-data/skip-prompt'](nil,{kind=kind,start=63,['end']=153})
            assert(overlay.data:find(text[1],1,true),'Russian prompt '..kind)
            props['user-data/interface-language']='en';observers['user-data/interface-language']()
            assert(overlay.data:find(text[2],1,true),'Live English prompt '..kind)
            assert(not overlay.data:find('Пропустить',1,true),'Stale Russian prompt')
        end
        assert(ui.chapter_text('Opening','ru')=='Заставка (OP)' and ui.chapter_text('Ending','en')=='Credits (ED)')
        assert(ui.menu({type='chapters',items={{title='Opening'},{title='Chapter named by author'}}}).items[1].title=='Intro (OP)')
        props['time-pos']=160;observers['time-pos']()
        assert(props['user-data/skip-prompt-visible']==false,'Hide the prompt after its interval')
    end,debug.traceback)
    mp=real;package.loaded['mpv-build/ui_locale']=saved
    assert(ok,err)
end
