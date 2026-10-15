-- Season-aware anime identity. Never substitute season one for an unknown season.
local folder=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*)[/\\]'))
local root=folder..'/..'
local fmt=dofile(folder..'/title_format.lua')
local M={}
local cached, catalog
function M.catalog()
    if catalog then return catalog end
    local file=io.open(root..'/data/anime-catalog.json','rb')
    if not file then return {} end
    catalog=require('mp.utils').parse_json(file:read('*a'));file:close()
    return catalog or {}
end
function M.invalidate() cached=nil end
local function copy(value) local result={};for k,v in pairs(value) do result[k]=v end;return result end
function M.index(database)
    local result={}
    for name,id in pairs(database or {}) do
        if type(name)=='string' and tonumber(id) then
            local key=fmt.normalize(name);id=tostring(id)
            if result[key] and result[key]~=id then result[key]=false
            elseif result[key]==nil then result[key]=id end
        end
    end
    return result
end
function M.database()
    if cached then return cached end
    local file=io.open(root..'/scripts/autochapters/anime.json','rb')
    if not file then return {} end
    local data=require('mp.utils').parse_json(file:read('*a'));file:close()
    cached=M.index(data);return cached
end
local function ordinal(n)
    local last=n%10
    local suffix=(n%100>=11 and n%100<=13) and 'th' or ({[1]='st',[2]='nd',[3]='rd'})[last] or 'th'
    return tostring(n)..suffix
end
local function season_id(title,season,index)
    local hits={}
    for _,suffix in ipairs({ordinal(season)..' Season','Season '..season,'S'..season,tostring(season)}) do
        local id=index[fmt.normalize(title..' '..suffix)]
        if id then hits[id]=true end
    end
    local id,count=nil,0
    for key in pairs(hits) do id=key;count=count+1 end
    return count==1 and id or nil
end
local function identify(data,index)
    data=copy(data)
    local direct=index[fmt.normalize(data.title)]
    local base,n=data.title:match('^(.-)%s+(%d+)[snrt][tdh]%s+[Ss]eason$')
    if not base then base,n=data.title:match('^(.-)%s+[Ss]eason%s+(%d+)$') end
    if not base then base,n=data.title:match('^(.-)%s+(%d+)$') end
    n=tonumber(n)
    if base and n and n>=1 and n<=20 and index[fmt.normalize(base)] then
        local resolved=n==1 and index[fmt.normalize(base)] or season_id(base,n,index)
        if resolved and (n==1 or resolved~=index[fmt.normalize(base)]) then
            data.title,data.season,direct=base,n,resolved
        end
    end
    local base_id=index[fmt.normalize(data.title)]
    if (data.season or 1)>1 then
        data.mal_id=season_id(data.title,data.season,index)
    else data.mal_id=direct or base_id end
    data.anime=base_id~=nil and base_id~=false or direct~=nil and direct~=false or data.mal_id~=nil
    if data.anime and (data.episode or data.season) then data.kind='tv' end
    local metadata=data.mal_id and M.catalog()[tostring(data.mal_id)]
    if metadata then
        -- An explicit conflicting release year can identify a live-action remake.
        -- Keep the source identity instead of substituting an anime namesake.
        if data.year and metadata.year and math.abs(tonumber(data.year)-metadata.year)>1 then
            data.anime,data.mal_id=false,nil
        elseif metadata.tmdb_id and (not data.tmdb_id or tostring(data.tmdb_id)==tostring(metadata.tmdb_id)) then
            data.tmdb_id=metadata.tmdb_id
            data.tmdb_season=metadata.season
            data.tmdb_offset=metadata.offset or 0
            data.kind=metadata.kind
        end
    end
    return data
end
function M.enrich(raw,data,index)
    index=index or M.database()
    local result=identify(data,index)
    -- Leading episode numbers are stripped only after a database-confirmed anime match.
    local name=fmt.decode(raw or ''):gsub('^.*[/\\]','')
    local episode,rest=name:match('^(%d%d?%d?%d?)%.%s+(.+)$')
    if episode and tonumber(episode)>0 then
        local candidate=identify(fmt.parse(rest),index)
        if candidate.anime then
            candidate.episode=tonumber(episode);candidate.season=candidate.season or 1;candidate.kind='tv'
            return candidate
        end
    end
    return result
end
return M
