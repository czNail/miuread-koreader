-- B3: paints cached comment anchors after the reader text, never into EPUB.
local M={}; M.__index=M

function M:new()
    return setmetatable({records={},visible={},enabled=true,last_page=nil},self)
end

function M:setRecords(rows)
    self.records=type(rows)=="table" and rows or {}
    self:invalidate()
end
function M:setEnabled(value)
    self.enabled=value==true
    self:invalidate()
end
function M:invalidate()
    self.visible={}
    self.last_page=nil
    self.generation=(self.generation or 0)+1
    self._last_visible_key=nil
    self._last_visible={}
end

local function intersects(a,b)
    return a.x<b.x+b.w and a.x+a.w>b.x and a.y<b.y+b.h and a.y+a.h>b.y
end

function M:paintTo(bb)
    self.visible={}
    if not self.enabled or #self.records==0 then return end
    local doc=self.ui and self.ui.document
    if not doc or type(doc.getScreenBoxesFromPositions)~="function" then return end
    local okBB,BB=pcall(require,"ffi/blitbuffer")
    if not okBB or not BB then return end
    local screen=require("device").screen
    local ink=BB.Color8(0x80)
    local px=math.max(1,screen:scaleBySize(1))
    local viewport=self.ui.dimen or {x=0,y=0,w=screen:getWidth(),h=screen:getHeight()}
    local top=type(doc.getCurrentPos)=="function" and tonumber(doc:getCurrentPos()) or nil
    local count=type(doc.getVisiblePageCount)=="function" and
        tonumber(doc:getVisiblePageCount()) or 1
    local bottom=top and top+viewport.h*math.max(1,count or 1) or nil
    local key=tostring(self.generation or 0)..":"..tostring(top or "")..":"..tostring(viewport.w)
    if self._last_visible_key~=key then
        local entries={}
        for _,record in ipairs(self.records) do
            local should_check=true
            if top and type(doc.getPosFromXPointer)=="function" then
                local ok0,first=pcall(doc.getPosFromXPointer,doc,record.pos0)
                local ok1,last=pcall(doc.getPosFromXPointer,doc,record.pos1)
                if ok0 and ok1 and tonumber(first) and tonumber(last) then
                    should_check=first<=bottom and last>=top
                end
            end
            if should_check then
                local ok,boxes=pcall(doc.getScreenBoxesFromPositions,doc,record.pos0,record.pos1,true)
                if ok and type(boxes)=="table" then
                    for _,rect in ipairs(boxes) do
                        if type(rect)=="table" and tonumber(rect.x) and tonumber(rect.y)
                            and tonumber(rect.w) and tonumber(rect.h) and rect.w>0 and rect.h>0
                            and intersects(rect,viewport) then
                            entries[#entries+1]={rect=rect,record=record}
                        end
                    end
                end
            end
        end
        self._last_visible=entries
        self._last_visible_key=key
    end
    self.visible=self._last_visible
    for _,entry in ipairs(self.visible) do
        local rect=entry.rect
        -- Screen boxes can straddle the reader viewport. Never draw a mark
        -- into the toolbar, margins outside the viewport, or negative pixels.
        local left=math.max(0,viewport.x,rect.x)
        local right=math.min(screen:getWidth(),viewport.x+viewport.w,rect.x+rect.w)
        local y=rect.y+rect.h-px
        local top=math.max(0,viewport.y)
        local bottom=math.min(screen:getHeight(),viewport.y+viewport.h)
        if left<right and y>=top and y+px<=bottom then
            for x=left,right-1,7*px do
                local width=math.min(4*px,right-x)
                if width>0 then bb:paintRect(x,y,width,px,ink) end
            end
        end
    end
end

function M:hitTest(pos)
    if not self.enabled or type(pos)~="table" then return nil end
    local x,y=tonumber(pos.x),tonumber(pos.y)
    if not x or not y then return nil end
    for i=#self.visible,1,-1 do
        local item=self.visible[i];local r=item.rect
        if x>=r.x-2 and x<=r.x+r.w+2 and y>=r.y-2 and y<=r.y+r.h+2 then
            return item.record
        end
    end
end
return M
