return function(path)
    local saved=package.loaded['mpv-build/ui_locale']
    package.loaded['mpv-build/ui_locale']=nil
    local command_native=mp.command_native
    mp.command_native=function(args) return path(args[2]:gsub('^~~/','')) end
    local ui=dofile(path('extensions/ui_locale.lua'))
    mp.command_native=command_native
    assert(ui.text('Скорость (Колесо мыши)','en')=='Speed (Mouse wheel)')
    assert(ui.text('Speed (Mouse wheel)','ru')=='Скорость (Колесо мыши)')
    assert(ui.text('Контрастность: +12','en')=='Contrast: +12')
    assert(ui.text('Пропущено: Заставка → 00:30','en')=='Skipped: Intro → 00:30')
    for _,text in ipairs({'TorrServer','AniSkip','4K','HEVC','AC-3','English','Русский','Protector (2025)'}) do
        assert(ui.text(text,'en')==text and ui.text(text,'ru')==text,'Universal label: '..text)
    end
    local language=ui.language
    ui.language=function() return 'en' end
    local command={'script-binding','picture_controls/menu'}
    local menu={type='menu',items={{title='Изображение',value=command},{title='TorrServer',value='noop'}}}
    assert(ui.menu(menu).items[1].title=='Picture')
    assert(menu.items[1].title=='Изображение' and ui.menu(menu).items[1].value==command,'Menu copy preserves commands')
    local updated=ui.menu(menu)
    assert(#ui.menu(updated).items==#updated.items,'Old menu migration must be idempotent')
    assert(#menu.items==2,'Personal menu source must not be mutated')
    assert(ui.menu({type='network-playback',items={{title='Запас видео'}}}).items[1].title=='Buffered video')
    assert(ui.menu({type='subtitle-memory',items={{title='Сохранённый выбор'}}}).items[1].title=='Saved preference')
    for _,kind in ipairs({'playlist','sub','audio','open-file'}) do
        local source={type=kind,title='Субтитры',items={{title='Изображение',value='file.mkv'},
            {title='Выключить субтитры',value='{disable}'}}}
        local translated=ui.menu(source)
        assert(translated.title=='Subtitles' and translated.items[1].title=='Изображение','Media title must not be translated')
        assert(translated.items[2].title=='Disable subtitles','Special track menu command')
    end
    ui.language=language
    package.loaded['mpv-build/ui_locale']=saved
end
