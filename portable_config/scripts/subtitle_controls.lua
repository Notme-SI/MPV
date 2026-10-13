-- Disable both subtitle layers for this file. The next file retains language defaults.
mp.add_key_binding(nil,'off',function()
    mp.set_property('file-local-options/sid','no')
    mp.set_property('file-local-options/secondary-sid','no')
end)
