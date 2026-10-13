-- Disable both layers. subtitle_memory remembers the explicit choice for this series.
mp.add_key_binding(nil,'off',function()
    mp.set_property('file-local-options/sid','no')
    mp.set_property('file-local-options/secondary-sid','no')
end)
