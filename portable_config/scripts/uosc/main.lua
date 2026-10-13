-- Local skin, independent of the upstream uosc distribution.
local root = mp.command_native({'expand-path', '~~/'})
dofile(root .. '/extensions/uosc_skin.lua')(mp.get_script_directory())
dofile(root .. '/vendor/uosc/main.lua')
