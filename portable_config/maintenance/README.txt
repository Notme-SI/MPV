mpv+-1.0.1

ОБНОВЛЕНИЕ
«Обновить mpv+.cmd» проверит версии и предложит обновить: Y - да, N - нет.
Перед установкой закройте mpv. В Program Files запускайте установку от имени администратора.
Настройки сохраняются. Автоматические бэкапы не создаются.
Загрузки проверяются по SHA-256. Затем выполняются проверки расширений и запуска.
Несовместимый патч или изменённый вручную файл не перезаписывается.
Иконка mpv.exe восстанавливается после обновления.

ДОРАБОТКИ
• uosc и sub-select: оригинальный код, настройки и отдельные дополнения.
• thumbfast: оригинал в vendor; отдельный запускатель определяет путь mpv.exe.
• autocrop и TorrServer: расширения в extensions, небольшие проверяемые адаптеры.
• TheIntroDB и autochapters: пока остаются патчи к внутренним функциям.
  Их обновление пропускается, если патч больше не подходит.

Полной гарантии совместимости нет: проверки не заменяют просмотр всех форматов.
При ошибке замены файлов установщик пытается отменить изменения в рамках текущего запуска.

ПЕРЕНОС
Переносите всю папку вместе с portable_config.
«Сохранить бэкап.cmd» сохраняет ZIP, включая ваши данные TorrServer.
Для публикации используйте чистый mpv+-1.0.1.zip.

ФАЙЛЫ
script-opts - настройки; scripts - запускатели, плагины и отдельные дополнения.
vendor - отдельно обновляемые thumbfast, TorrServer и главный файл uosc.
extensions - доработки сборки, которые обновления плагинов не перезаписывают.
maintenance/patches - точки подключения и оставшиеся патчи.
maintenance/manifest.json - версии и контрольные суммы.
maintenance/compatibility.lua - проверки перед установкой.

1.0.1 - версия сборки; mpv и плагины имеют собственные номера версий.

Оформление: extensions/uosc_skin.lua и uosc_theme.lua; исходный main.lua в vendor/uosc.
Характеристики файла: extensions/media_info.lua и scripts/file_fps.lua.
Стиль и метки: script-opts/player_ui.conf. Субтитры: scripts/subtitle_controls.lua.
Названия: readable_titles.lua, title_format.lua. Изображение: picture_controls.lua.
Язык интерфейса: scripts/interface_language.lua, extensions/ui_locale.lua и interface-translations.json.
Сеть и буфер: scripts/network_playback.lua, script-opts/network_playback.conf.
Память субтитров: scripts/subtitle_memory.lua и личный subtitle-preferences.json.
При сохранённом старом input.conf новые пункты меню добавляются расширением интерфейса.
Эти файлы не заменяются при обновлении сторонних плагинов.
