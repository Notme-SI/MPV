# Сборка

Нужны Git, Python 3, .NET Framework 4 (для совместимого запускателя Lampa) и, для установщика, Inno Setup 6.7.3. Компилятор берите с [официального сайта](https://jrsoftware.org/isdl.php).

## ZIP

Перед сборкой создайте компактный каталог из снимков [anime-offline-database](https://github.com/manami-project/anime-offline-database) (`anime-offline-database.json`) и [Fribb/anime-lists](https://github.com/Fribb/anime-lists) (`anime-list-full.json`):

```powershell
python tools/build-anime-catalog.py --database anime-offline-database.json --mapping anime-list-full.json
```

Сформированный `portable_config/data/anime-catalog.json` включается в ZIP. Версии и источники данных указаны в `SOURCES.txt`.

Скачайте чистый `mpv+-1.0.1.zip` из Releases. Он содержит двоичные компоненты, шрифты и базы данных. Скрипт проверит его SHA-256, затем наложит отслеживаемые Git файлы этого репозитория:

```powershell
python tools/build-package.py --base "C:\Downloads\mpv+-1.0.1.zip"
```

Результат: `dist/mpv+-1.0.2.zip` и файл SHA-256. Исходный ZIP не изменяется. Новые файлы расширений и обслуживания включаются из соответствующих каталогов.

## Установщик

```powershell
python installer/prepare.py dist/mpv+-1.0.2.zip
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer/MPV.iss
```

Результат: `installer/output/mpv+-1.0.2-Setup.exe`. Путь к ISCC зависит от места установки Inno Setup.

Скрипт подготовки сверяет ZIP с его файлом `.sha256`. Установщик устанавливается для текущего пользователя. При переустановке сохраняются `mpv.conf`, `input.conf`, все файлы `script-opts` и личное состояние плеера. При удалении личные настройки остаются на месте.

## Проверка

В распакованной сборке:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File portable_config/maintenance/Test-Extensions.ps1 -Executable .\mpv+.exe -ConfigRoot .\portable_config
```

Установщик проверяйте в отдельной папке: установка, запуск, изменение настроек, повторная установка и удаление. Не используйте для теста рабочую копию плеера.

## Публикация

В Releases размещайте ZIP и установщик. Контрольные суммы храните в releases/1.0.2/SHA256SUMS.txt. Для новой версии обновите `VERSION`, `installer/MPV.iss`, `README.txt` и описания выпуска. `AppId` установщика должен оставаться прежним.

Не копируйте в репозиторий личную установку: в ней могут находиться пароль TorrServer, токены, история и кэш. В `script-opts` хранятся только чистые настройки по умолчанию.
