"""B6 deterministic geometry/event-order checks; hardware E-Ink tests remain separate."""
from pathlib import Path
import ctypes
import ctypes.util
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / 'miuread.koplugin' / 'miuread'

class ModalB6Static(unittest.TestCase):
    def test_old_frame_restored_by_redrawing_current_stack(self):
        code = (PLUGIN / 'dialog_transition.lua').read_text()
        self.assertIn('UIManager:setDirty("all", mode or "ui", Geom:new(safe))', code)
        self.assertIn('Geometry.union(old, current_modal_frame())', code)
        self.assertNotIn('scheduleIn(.05', code)
        self.assertIn('if token ~= M.generation then return end', code)

    def test_layout_bounds_and_overflow(self):
        for filename, indicator in [
            ('action_sheet.lua', 'action sheet height exceeds viewport'),
            ('reader_list_dialog.lua', 'reader list contents exceed available panel height'),
            ('reader_settings_dialog.lua', 'reader settings contents exceed available panel height'),
            ('reader_progress_dialog.lua', 'reader progress frame exceeds screen'),
            ('reader_frontlight_dialog.lua', 'frontlight dialog cannot fit screen'),
        ]:
            self.assertIn(indicator, (PLUGIN / filename).read_text(), filename)
        self.assertIn('self._settings_pages > 1', (PLUGIN / 'reader_settings_dialog.lua').read_text())
        self.assertIn('for candidate = columns + 1, 3', (PLUGIN / 'action_sheet.lua').read_text())

    def test_partial_frame_is_not_misidentified_as_opaque_screen(self):
        for name in ['reader_settings_dialog.lua', 'reader_progress_dialog.lua',
                     'reader_frontlight_dialog.lua', 'reader_typography_dialog.lua',
                     'reader_toc_dialog.lua','reader_toolbar.lua',
                     'reader_control_center.lua','home_quick_panel.lua']:
            code = (PLUGIN / name).read_text()
            self.assertIn('covers_fullscreen = false', code)

    def test_close_paths_use_shared_transition(self):
        for name in ['reader_progress_dialog.lua','reader_frontlight_dialog.lua',
                     'reading_stats_dialog.lua','home_quick_panel.lua',
                     'reader_toolbar.lua','reader_control_center.lua']:
            code = (PLUGIN / name).read_text()
            self.assertIn('DialogTransition.after_close(', code)
        popup = (PLUGIN / 'thought_native_popup.lua').read_text()
        self.assertIn('DialogTransition.restore(region)', popup)
        first_paint = popup.split('function NativePopup:onShow()',1)[1].split('function NativePopup:onTapPage',1)[0]
        self.assertIn('return "ui", self.popup_dimen',first_paint)
        self.assertNotIn('return "partial"',first_paint)

class LuaModalB6Runtime(unittest.TestCase):
    def test_geometry_and_transition(self):
        libname = ctypes.util.find_library('lua5.4')
        if not libname:
            self.skipTest('System Lua 5.4 shared library unavailable (static suite still runs)')
        lua = ctypes.CDLL(libname)
        lua.luaL_newstate.restype = ctypes.c_void_p
        lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
        lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lua.luaL_loadstring.restype = ctypes.c_int
        lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                                  ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
        lua.lua_pcallk.restype = ctypes.c_int
        lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
        lua.lua_tolstring.restype = ctypes.c_char_p
        lua.lua_close.argtypes = [ctypes.c_void_p]
        L = lua.luaL_newstate()
        try:
            lua.luaL_openlibs(L)
            script = r'''
package.path = %r..'/?.lua;'..package.path
local calls, queue, logs = {}, {}, {}
local uim = {_window_stack={}}
function uim:nextTick(fn) queue[#queue+1]=fn end
function uim:setDirty(who,mode,rect)
    assert(who=='all' and mode=='ui' and rect.w>0 and rect.h>0)
    calls[#calls+1]={x=rect.x,y=rect.y,w=rect.w,h=rect.h}
end
package.preload['ui/uimanager']=function()return uim end
package.preload['ui/geometry']=function()
    local geom={};function geom:new(r)return setmetatable(r,{__index=self})end
    return geom
end
package.preload['logger']=function()return {warn=function(...)logs[#logs+1]=true end}end
local G=require('miuread.modal_geometry')
assert(G.rect({x=10,y=10,w=-1,h=20})==nil)
assert(G.rect({x=1,y=1,w=10,h=10},3,10,10).w==10)
local a=G.rect({x=20,y=10,w=200,h=190},3)
local b=G.rect({x=60,y=50,w=90,h=80},3)
local u=G.union(a,b)
assert(u.w==a.w and u.h==a.h)
local scaled, ok=G.scale_to_fit(150,{30,40,70,60},1)
assert(ok)
local total=0; for _,v in ipairs(scaled)do total=total+v end
assert(total<=150)
local T=require('miuread.dialog_transition')
local function flush()
    local guard=0
    while #queue>0 do
        guard=guard+1;assert(guard<40)
        table.remove(queue,1)()
    end
end
local fired=0
-- Large replaced by small: old footprint must be repainted on both sides.
T.after_close({x=20,y=10,w=200,h=190},function()
    fired=fired+1
    uim._window_stack={{widget={_miuread_modal_surface=true,
        frame_dimen={x=60,y=50,w=90,h=80}}}}
end)
flush()
assert(fired==1 and #calls==2 and calls[2].w>=200)
-- Small replaced by large: union contains the new frame (not only old).
calls={};uim._window_stack={}
T.after_close({x=60,y=50,w=90,h=80},function()
    uim._window_stack={{widget={_miuread_modal_surface=true,
        panel_dimen={x=10,y=10,w=260,h=230}}}}
end)
flush()
assert(#calls==2 and calls[2].w>=260 and calls[2].h>=230)
-- Cancel stale navigation, but do not cancel restoration of physical pixels.
calls={};fired=0;uim._window_stack={}
T.after_close({x=10,y=10,w=70,h=70},function() fired=fired+1 end)
T.cancel_pending();flush()
assert(fired==0 and #calls==1)
return true
''' % str(ROOT/'miuread.koplugin').replace('\\','/')
            rc = lua.luaL_loadstring(L, script.encode())
            if not rc:
                rc = lua.lua_pcallk(L, 0, 1, 0, 0, None)
            if rc:
                err = lua.lua_tolstring(L, -1, None)
                self.fail((err or b'Lua test error').decode(errors='replace'))
        finally:
            lua.lua_close(L)

if __name__ == '__main__': unittest.main()
