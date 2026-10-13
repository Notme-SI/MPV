-- Local bootstrap using thumbfast's public frontend integration property.
local ok, ffi = pcall(require, 'ffi')
if ok and ffi.os == 'Windows' and not mp.get_property_native('user-data/frontend/process-path') then
    ffi.cdef[[unsigned long GetModuleFileNameW(void*, wchar_t*, unsigned long);
        int WideCharToMultiByte(unsigned int,unsigned long,const wchar_t*,int,char*,int,const char*,int*);]]
    local kernel = ffi.load('kernel32')
    local buffer = ffi.new('wchar_t[32768]')
    local n = kernel.GetModuleFileNameW(nil, buffer, 32768)
    if n > 0 and n < 32768 then
        local count = kernel.WideCharToMultiByte(65001,0,buffer,n,nil,0,nil,nil)
        if count > 0 then
            local out = ffi.new('char[?]',count)
            kernel.WideCharToMultiByte(65001,0,buffer,n,out,count,nil,nil)
            local frontend = mp.get_property_native('user-data/frontend',{})
            frontend['process-path'] = ffi.string(out,count)
            assert(mp.set_property_native('user-data/frontend',frontend))
        end
    end
end
