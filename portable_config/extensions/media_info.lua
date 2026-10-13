-- Source metadata only. Crop filters and playback speed do not change these badges.
local M={}
local codecs={h264='H.264',hevc='HEVC',av1='AV1',vp9='VP9',vp8='VP8',mpeg2video='MPEG-2',
    mpeg4='MPEG-4',aac='AAC',ac3='AC-3',eac3='E-AC-3',dts='DTS',truehd='TrueHD',
    flac='FLAC',opus='Opus',vorbis='Vorbis',mp3='MP3',alac='ALAC'}
function M.number(n)
    n=tonumber(n)
    return n and n>0 and n<math.huge and n==n and n or nil
end
function M.codec(value)
    if type(value)~='string' or value=='' then return nil end
    return codecs[value:lower()] or (value:match('^pcm_') and 'PCM') or value:upper()
end
function M.describe(video,audio,params,container_fps)
    local out={badges={}}
    local function add(kind,text)
        if text then out.badges[#out.badges+1]={kind=kind,text=text} end
    end
    if type(video)=='table' and not video.image and not video.albumart then
        params=params or {}
        local w=M.number(video['demux-w']) or M.number(params.w)
        local h=M.number(video['demux-h']) or M.number(params.h)
        if w and h then
            local edge,short=math.max(w,h),math.min(w,h)
            local quality=(edge>=7680 or short>=4320) and '8K' or (edge>=3840 or short>=2160) and '4K'
                or (edge>=2560 or short>=1440) and '1440p' or (edge>=1920 or short>=1080) and '1080p'
                or (edge>=1280 or short>=720) and '720p' or tostring(short)..'p'
            add('quality',quality)
        end
        add('video',M.codec(video.codec))
        if params.gamma=='pq' or params.gamma=='hlg' then add('hdr','HDR') end
        local fps=M.number(video['demux-fps']) or M.number(container_fps)
        if fps then out.fps=string.format('%.3f',fps):gsub('0+$',''):gsub('%.$',''):gsub('%.',',')..' FPS' end
    end
    if type(audio)=='table' then add('audio',M.codec(audio.codec)) end
    add('fps',out.fps)
    return out
end
return M
