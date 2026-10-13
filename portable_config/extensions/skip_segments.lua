-- Embedded chapter boundaries belong to the actual release and outrank online times.
local M={}
local labels={
    intro={'op','opening','intro','заставка','опенинг'},
    credits={'ed','ending','outro','credits','титры','эндинг'},
    recap={'recap','previously','previously on','рекап','ранее в сериале'},
    preview={'preview','next episode','анонс','превью'},
}
function M.kind(title,normalize)
    title=(title or ''):gsub('^%s*%d+[%s%.%-:]+','')
    title=normalize(title:match('^(.-)%s*[%(%[%:/%-]') or title)
    for kind,names in pairs(labels) do
        for _,name in ipairs(names) do
            local prefix=normalize(name)
            if title==prefix or title:match('^'..prefix..'%d+$') then return kind end
        end
    end
end
function M.from_chapters(chapters,duration,normalize)
    local out={}
    for i,chapter in ipairs(chapters or {}) do
        local kind=M.kind(chapter.title,normalize)
        local start=tonumber(chapter.time)
        local next_chapter=chapters[i+1]
        local finish=next_chapter and tonumber(next_chapter.time)
        if not finish and (kind=='credits' or kind=='preview') then finish=duration end
        local max_length=kind=='credits' and 900 or 300
        if kind and start and finish and start>=0 and finish>start and finish-start<=max_length and (duration<=0 or finish<=duration+1) then
            out[kind]=out[kind] or {}
            out[kind][#out[kind]+1]={start_ms=start*1000,end_ms=finish*1000,source='chapters'}
        end
    end
    return out
end
function M.combine(remote,anime,native)
    local combined={}
    -- Do not mix different release/season databases into an identified AniSkip result.
    for k,v in pairs(next(anime or {}) and anime or remote or {}) do combined[k]=v end
    for k,v in pairs(native or {}) do combined[k]=v end
    return combined
end
return M
