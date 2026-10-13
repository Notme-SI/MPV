-- Local launcher; upstream code and build extensions are maintained separately.
dofile(mp.command_native({'expand-path','~~/extensions/torrserver.lua'})).install()
dofile(mp.command_native({'expand-path','~~/vendor/torrserver_loader.lua'}))
