-- B7 integration checks: no resurrected cache dirs, bounded overlay, compact header.
-- Runs with the system Lua 5.4 library; no device or cloud services used.
package.path = "miuread.koplugin/?.lua;miuread.koplugin/?/init.lua;" .. package.path
local created = 0
local root = "/tmp/miuread-b7-absent-book"
local store = {
    book_cache_path = function(_,id) return root.."/"..id end,
    book_dir = function(_,id) created=created+1; return root.."/"..id end,
}
package.preload["miuread.sqlite_store"] = function() return {} end
package.preload["miuread.json"] = function() return {} end
package.preload["miuread.util"] = function()
    return { id_name=function(id) return tostring(id) end,
        read_file=function() return nil end }
end
package.preload["libs/libkoreader-lfs"] = function()
    return { attributes=function() return nil end }
end
local DB = require("miuread.thought_database")
assert(DB.exists(store,"deleted") == false)
assert(DB.sync_state(store,"deleted","chapter") == nil)
local rows,err = DB.load_chapter(store,"deleted","chapter")
assert(rows == nil and type(err)=="string")
local Thoughts = require("miuread.thoughts")
rows,err = Thoughts.load(store,"deleted","chapter")
assert(rows==nil and type(err)=="string")
assert(created==0,"reading deleted comments recreated a cache directory")
local layout = require("miuread.home_header_layout")
local row = layout.arrange(115,{
    {key="title",width=70,priority=0},
    {key="wifi",width=46,priority=0},
    {key="tools",width=46,priority=0},
},10)
assert(#row>0)
for _,item in ipairs(row) do
    assert(item.x>=0 and item.x+item.width<=115,"small viewport overflow")
end
package.preload["device"]=function()
    return {screen={
        scaleBySize=function(_,v) return v end,
        getWidth=function() return 300 end,
        getHeight=function() return 200 end,
    }}
end
package.preload["ffi/blitbuffer"]=function()return {Color8=function(v)return v end}end
local overlay = require("miuread.comment_overlay"):new()
local doc = {
    getScreenBoxesFromPositions=function()return {{x=90,y=45,w=150,h=15}} end,
    getCurrentPos=function()return 0 end,
}
overlay.ui={document=doc,dimen={x=100,y=30,w=90,h=55}}
overlay:setRecords({{pos0="xp1",pos1="xp2",range="r"}})
local paint={}
overlay:paintTo({paintRect=function(_,x,y,w,h)
    assert(x>=100 and x+w<=190 and y>=30 and y+h<=85,"overlay painted outside viewport")
    paint[#paint+1]={x=x,y=y,w=w,h=h}
end})
assert(#paint>0,"visible, partially clipped mark should still be painted")
doc.getScreenBoxesFromPositions=function()return {{x=90,y=82,w=150,h=25}} end
overlay:invalidate();paint={}
overlay:paintTo({paintRect=function(_,...)paint[#paint+1]=true end})
assert(#paint==0,"mark outside viewport bottom must not paint")
print("B7 integration: safe deleted-book reads, narrow header, clipped overlay passed")
