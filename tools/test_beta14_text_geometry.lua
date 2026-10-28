-- Isolated runtime test of the common text widget geometry contract.
-- Run: luatex --luaonly tools/test_beta14_text_geometry.lua
package.path='miuread.koplugin/?.lua;miuread.koplugin/?/init.lua;'..package.path
package.preload['ffi/blitbuffer']=function() return {COLOR_BLACK=0} end
package.preload['ui/geometry']=function()
 local G={}
 function G:new(obj) return setmetatable(obj or {},{__index=self}) end
 return G
end
local created={}
package.preload['ui/widget/textboxwidget']=function()
 return {new=function(_,spec)
    created[#created+1]=spec
    local obj={spec=spec}
    function obj:getSize()return {w=self.spec.width,h=self.spec.height or 400}end
    function obj:paintTo()end
    return obj
 end}
end
package.preload['ui/widget/textwidget']=function()
 return {new=function(_,spec)
    local obj={spec=spec};function obj:getSize() return {w=spec.max_width,h=14} end
    function obj:paintTo()end
    return obj
 end}
end
package.preload['ui/widget/container/widgetcontainer']=function()
 local Base={}
 function Base:extend(properties)
     properties=properties or {};properties.__index=properties
     return setmetatable(properties,{__index=self})
 end
 function Base:new(spec)
     local obj=setmetatable(spec or {},self)
     if obj.init then obj:init() end
     return obj
 end
 return Base
end
package.preload['miuread.icon_registry']=function() return {widget=function() return {getSize=function()return{w=8,h=8}end,paintTo=function()end}end}end
local Ui=require('miuread.ui_components')
local regular=Ui.textbox('很长的文字',147,35,{}, {})
assert(created[1].width==147 and created[1].height==35)
assert(created[1].height_overflow_show_ellipsis==true)
assert(regular:getSize().w==147 and regular:getSize().h==35)
local natural=Ui.textbox('完整文本',150,60,{}, {natural_height=true})
assert(created[2].height==nil,'natural-height text must not be truncated')
assert(natural:getSize().h==400)
local override=Ui.textbox('隐藏文字',150,20,{}, {ellipsis=false})
assert(created[3].height==20 and created[3].height_overflow_show_ellipsis==false)
print('beta14 text geometry: PASS (bounded and natural height)')
