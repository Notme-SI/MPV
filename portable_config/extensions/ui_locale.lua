-- Shared interface language. Media titles and track preferences are independent.
if package.loaded['mpv-build/ui_locale'] then return package.loaded['mpv-build/ui_locale'] end
local M={}
package.loaded['mpv-build/ui_locale']=M
local utils=require 'mp.utils'
local root=mp.command_native({'expand-path','~~/'})
local function read(path)
    local f=io.open(root..'/'..path,'rb')
    if not f then return '' end
    local value=f:read('*a');f:close();return value
end
local saved=read('script-opts/interface.conf'):match('language%s*=%s*(%a+)') or 'ru'
local entries=assert(utils.parse_json(read('extensions/interface-translations.json')))
local exact,formats={},{}
local function escape(s) return (s:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])','%%%1')) end
local function pattern(s)
    local parts,start={},1
    while true do
        local a,b=s:find('%%[sdg]',start)
        if not a then parts[#parts+1]=escape(s:sub(start));break end
        parts[#parts+1]=escape(s:sub(start,a-1));parts[#parts+1]='(.-)';start=b+1
    end
    return '^'..table.concat(parts)..'$'
end
for _,entry in ipairs(entries) do
    exact[entry.ru],exact[entry.en]=entry,entry
    if entry.en:find('%%[sdg]') then
        formats[#formats+1]={en=pattern(entry.en),ru=pattern(entry.ru),entry=entry}
    end
end
table.sort(formats,function(a,b) return #a.ru>#b.ru end)
function M.language()
    local current=mp.get_property_native('user-data/interface-language',saved)
    return current=='en' and 'en' or 'ru'
end
function M.text(value,language)
    if type(value)~='string' then return value end
    language=language or M.language()
    local entry=exact[value]
    if entry then return entry[language] end
    for _,item in ipairs(formats) do
        for _,source in ipairs({'ru','en'}) do
            local captures={value:match(item[source])}
            if #captures>0 then
                local i=0
                return (item.entry[language]:gsub('%%[sdg]',function()
                    i=i+1
                    local v=captures[i] or ''
                    return item.entry.translate_args and M.text(v,language) or v
                end))
            end
        end
    end
    -- Fixed help fragments can be combined with shortcuts or track metadata.
    for _,separator in ipairs({' · ', ', '}) do
        if value:find(separator,1,true) then
            local pieces,start={},1
            while true do
                local a,b=value:find(separator,start,true)
                if not a then pieces[#pieces+1]=M.text(value:sub(start),language);break end
                pieces[#pieces+1]=M.text(value:sub(start,a-1),language);start=b+1
            end
            return table.concat(pieces,separator)
        end
    end
    local label,suffix=value:match('^(.-)( %b())$')
    if label and exact[label] then return M.text(label,language)..suffix end
    return value
end
local interface_menus={menu=true,keybinds=true,['player-timeline-style']=true,['player-icons']=true,
    ['interface-language']=true,['picture-controls']=true,['language-defaults']=true,['audio-memory']=true,
    autocrop=true,['autocrop-settings']=true,theintrodb=true}
function M.menu(data)
    local kind=data.type
    local function walk(node,is_menu)
        local copy={}
        for k,v in pairs(node) do copy[k]=v end
        local command=type(node.value)=='table' and node.value[1] or node.value
        local special=type(command)=='string' and command:match('^%{')
        if is_menu or interface_menus[kind] or node.items or special then copy.title=M.text(node.title) end
        -- Track and file titles are never translated. Only their standard UI metadata is.
        copy.hint=M.text(node.hint)
        copy.footnote=M.text(node.footnote)
        copy.search_suggestion=M.text(node.search_suggestion)
        for _,field in ipairs({'actions','item_actions'}) do
            if node[field] then
                copy[field]={}
                for i,action in ipairs(node[field]) do
                    local a={};for k,v in pairs(action) do a[k]=v end
                    a.label=M.text(a.label);copy[field][i]=a
                end
            end
        end
        if node.items then
            copy.items={}
            for i,item in ipairs(node.items) do copy.items[i]=walk(item,false) end
        end
        return copy
    end
    return walk(data,true)
end
function M.install_messages()
    if M.installed then return end
    M.installed=true
    local osd=mp.osd_message
    mp.osd_message=function(text,...) return osd(M.text(text),...) end
    local ok,input=pcall(require,'mp.input')
    if not ok then return end
    for _,name in ipairs({'get','select'}) do
        local fn=input[name]
        if fn then input[name]=function(args)
            local copy={};for k,v in pairs(args) do copy[k]=v end
            copy.prompt=M.text(copy.prompt)
            return fn(copy)
        end end
    end
    local log=input.log
    if log then input.log=function(text,...) return log(M.text(text),...) end end
end
return M
