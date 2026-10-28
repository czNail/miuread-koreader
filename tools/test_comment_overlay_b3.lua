-- B3 standalone non-network projection test (Lua 5.3/LuaJIT compatible).
local root=assert(arg[1],"pass miuread module root")
local source_text="章节中独一无二的引用"
local calls={search=0,saved=0}
local saved={}
local document={file="/tmp/b3-test.epub",info={has_pages=false}}
function document:findAllText(quote)
    calls.search=calls.search+1
    if quote==source_text then return {{start="1",["end"]="2"}} end
    return {}
end
function document:getTextFromXPointers() return source_text end
function document:clearSelection() end
function document:isXPointerInDocument(xp) return tonumber(xp)~=nil end
function document:getScreenBoxesFromPositions() return {{x=80,y=100,w=100,h=25}} end
function document:compareXPointers(a,b)
    a,b=tonumber(a),tonumber(b)
    if a==b then return 0 end
    return a<b and 1 or -1
end

package.preload["miuread.util"]=function() return {} end
package.preload["miuread.annotations.range"]=function() return {parse=function(range)
    return 1,2,range:find("-",1,true)==nil end} end
package.preload["miuread.annotation_coord"]=function() return {
    build=function() return {} end,
    resolveRangeOnMap=function() return {text=source_text,point=false} end,
} end
package.preload["miuread.source_position"]=function() return {
    readCachedChapter=function() return "cached local coordinate source" end,
} end
package.preload["miuread.thought_database"]=function() return {
    load_checkpoint=function() return {underlines={{range="10-30",markText=source_text}}} end,
    load_locations=function() return saved end,
    save_locations=function(_,_,_,rows)
        calls.saved=calls.saved+1
        for _,row in ipairs(rows) do
            saved[row.range]={document_fingerprint=row.document_fingerprint,
                xpointer_start=row.xpointer_start,xpointer_end=row.xpointer_end,
                match_status=row.match_status}
        end
        return true
    end,
} end
package.preload["libs/libkoreader-lfs"]=function() return {attributes=function()
    return {mode="file",size=123,modification=42}
end} end
local locator=assert(loadfile(root.."/comment_locator.lua"))()
local ui={document=document}
local group={range="10-30",texts={{content="某条评论"}}}
local rows,stats=locator.resolve({},nil,ui,"book","chapter",{chapter_map={{uid="chapter"}}},{group})
assert(#rows==1 and stats.matched==1 and calls.search==1)
assert(saved["10-30"].match_status=="matched")
-- Same document & same verified quote: no duplicate full-document search.
rows,stats=locator.resolve({},nil,ui,"book","chapter",{chapter_map={{uid="chapter"}}},{group})
assert(#rows==1 and calls.search==1)
-- Ambiguity must never generate an incorrect in-text underline.
document.findAllText=function(_,quote)
    calls.search=calls.search+1
    return {{start="1",["end"]="2"},{start="5",["end"]="6"}}
end
saved={}
rows,stats=locator.resolve({},nil,ui,"book","chapter",{chapter_map={{uid="chapter"}}},{group})
assert(#rows==0 and stats.unmatched==1 and saved["10-30"].match_status=="ambiguous_quote")
-- Untrusted chapter identity must not silently search another chapter.
rows,stats=locator.resolve({},nil,ui,"book","other",{chapter_map={{uid="chapter"}}},{group})
assert(#rows==0 and stats.error=="chapter_bounds_unavailable")
-- Overlay consumes taps only for verified, visible boxes.
package.preload["device"]=function() return {screen={
    scaleBySize=function(_,v) return v end,getWidth=function() return 600 end,
    getHeight=function() return 800 end}} end
local painted={}
package.preload["ffi/blitbuffer"]=function() return {Color8=function(x) return x end} end
local overlay=assert(loadfile(root.."/comment_overlay.lua"))():new()
overlay.ui={document=document,dimen={x=0,y=0,w=600,h=800}}
overlay:setRecords({{pos0="1",pos1="2",range="10-30"}})
overlay:paintTo({paintRect=function(_,...) painted[#painted+1]={...} end})
assert(#painted>0 and overlay:hitTest({x=90,y=105}).range=="10-30")
assert(overlay:hitTest({x=5,y=5})==nil)
overlay:setEnabled(false)
assert(overlay:hitTest({x=90,y=105})==nil)
print("B3 locator/overlay: 7 assertions groups passed")
