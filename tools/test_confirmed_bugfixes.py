"""Source-level regressions for confirmed beta fixes (stdlib only).

Requires neither a Kindle device nor a configured WeRead account. This does
NOT substitute for the runtime tests in test_eink_download.py.
"""
from pathlib import Path
import ctypes
import ctypes.util
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
def source(relative):
    return (ROOT/relative).read_text(encoding='utf-8')

checks=[]
def check(condition,description):
    checks.append((bool(condition),description))
    print(('PASS' if condition else 'FAIL')+': '+description)

crypto=source('miuread.koplugin/miuread/eink_crypto.lua')
http=source('miuread.koplugin/miuread/http.lua')
sheet=source('miuread.koplugin/miuread/action_sheet.lua')
main=source('miuread.koplugin/main.lua')

check('pcall(ffi.load,name)' in crypto and 'ffi.loadlib' not in re.sub(r'--[^\n]*','',crypto),'native inflater calls the actual LuaJIT FFI loader')
check('ffi.load,name' in crypto and 'libz.so.1' in crypto,'zlib SONAME candidates are supported')
check('M.inflate = inflate_impl' in crypto and crypto.count('E-Ink ZIP 解压长度无效')>=2,'cached inflater checks size on every call')
check('local callback_ok,callback_result=pcall(opt.on_chunk,total_bytes,current)' in http and http.count('if not callback_ok')>=2,
      'both streaming and completion callback errors are checked')
check('if callback_error then return nil,callback_error end' in http and 'if callback_error then error(callback_error,0) end' in http,
      'a callback error cancels transfer and is propagated without retries')
check('stream_error or callback_error' in http and 'socketutil:reset_timeout()' in http,
      'HTTP keepalive cleanup accounts for callback cancellation')
check('priority_action=confirm_label=="退出"' in main and 'priority_action=true,callback=function() self:_show_home_power_confirm' in main,
      'quit confirmation and its initiating action cannot be silently discarded')
check('local priority = self.pending_action_priority==true' in sheet and 'DialogTransition.after_close(region,nil,"ActionSheet")' in sheet,
      'only marked critical callbacks bypass dialog generation invalidation')
check('UIManager:broadcastEvent(Event:new("Exit"))' in main and 'if UIManager._exit_code==nil then UIManager:quit(0) end' in main,
      'KOReader exit retains lifecycle event and has an explicit completion fallback')
check('if not requested then' in main and 'reason=hibernate_timeout' in main,
      'existing download hibernation failure guards remain in place')

# Cross-check every Lua file's grammar with liblua5.4 where available. LuaJIT
# production-only symbols are not executed here; no module loading occurs.
lib=ctypes.util.find_library('lua5.4')
if lib:
    dll=ctypes.CDLL(lib)
    dll.luaL_newstate.restype=ctypes.c_void_p
    dll.luaL_loadfilex.argtypes=(ctypes.c_void_p,ctypes.c_char_p,ctypes.c_char_p)
    dll.luaL_loadfilex.restype=ctypes.c_int
    dll.lua_tolstring.argtypes=(ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p)
    dll.lua_tolstring.restype=ctypes.c_char_p
    dll.lua_settop.argtypes=(ctypes.c_void_p,ctypes.c_int)
    dll.lua_close.argtypes=(ctypes.c_void_p,)
    state=dll.luaL_newstate()
    failures=[]
    paths=sorted(ROOT.rglob('*.lua'))
    for p in paths:
        if dll.luaL_loadfilex(state,str(p).encode(),None):
            failures.append((str(p.relative_to(ROOT)),repr(dll.lua_tolstring(state,-1,None))))
        dll.lua_settop(state,0)
    dll.lua_close(state)
    check(not failures,f'all {len(paths)} Lua files compile under Lua 5.4 parser')
    for name,error in failures[:10]: print('  ',name,error)
else:
    print('SKIP: Lua 5.4 library unavailable: syntax compilation not executed')

failed=sum(not ok for ok,_ in checks)
print(f'checks={len(checks)} failed={failed}')
sys.exit(1 if failed else 0)
