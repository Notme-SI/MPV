-- Windows standalone GuessIt may write ANSI JSON even with PYTHONUTF8 set.
-- Validate UTF-8 first, then decode the process ANSI code page if necessary.
local M = {}
local ok, ffi = pcall(require, 'ffi')
if ok and ffi.os == 'Windows' then
    ffi.cdef[[
        unsigned int GetACP(void);
        int MultiByteToWideChar(unsigned int, unsigned long, const char*, int, wchar_t*, int);
        int WideCharToMultiByte(unsigned int, unsigned long, const wchar_t*, int, char*, int, const char*, int*);
    ]]
    local win = ffi.load('kernel32')
    function M.utf8(s)
        if win.MultiByteToWideChar(65001, 8, s, #s, nil, 0) > 0 then return s end
        local n = win.MultiByteToWideChar(win.GetACP(), 0, s, #s, nil, 0)
        if n <= 0 then return s end
        local wide = ffi.new('wchar_t[?]', n)
        win.MultiByteToWideChar(win.GetACP(), 0, s, #s, wide, n)
        local count = win.WideCharToMultiByte(65001, 0, wide, n, nil, 0, nil, nil)
        local buffer = ffi.new('char[?]', count)
        win.WideCharToMultiByte(65001, 0, wide, n, buffer, count, nil, nil)
        return ffi.string(buffer, count)
    end
else
    function M.utf8(s) return s end
end
function M.key(s)
    s = s:lower():gsub('Ё', 'ё')
    s = s:gsub('\208[\144-\175]', function(c)
        local b = c:byte(2)
        return b < 160 and string.char(208, b + 32) or string.char(209, b - 32)
    end)
    return s:gsub('%s+', '')
end
return M
