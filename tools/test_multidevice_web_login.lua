-- Offline contract tests: two independent Web QR logins, persistent identity,
-- server cookie overwrites, login rollback and Native credential isolation.
-- Run from repository root: lua5.1 tools/test_multidevice_web_login.lua
package.path='miuread.koplugin/?.lua;'..package.path
local function copy(v)
    if type(v)~='table' then return v end
    local out={}; for k,x in pairs(v) do out[k]=copy(x) end; return out
end
package.preload['miuread.util']=function() return {
    copy=copy,trim=function(s) return tostring(s or ''):match('^%s*(.-)%s*$') end,
    first_line=function(s,n) return tostring(s):sub(1,n or 200) end,
} end
package.preload['miuread.protocol']=function() return {
    escape=function(s) return tostring(s):gsub('([^%w_.%-])',function(c) return string.format('%%%02X',c:byte()) end) end,
} end
package.preload['miuread.text']=function() return {tr=function(s) return s end} end
package.preload['miuread.gesture_bridge']=function() return {handle=function() end} end
package.preload['logger']=function() return {info=function() end,warn=function() end} end
package.preload['device']=function() return {screen={getWidth=function() return 600 end,getHeight=function() return 800 end}} end
local Widget={}
function Widget:extend(t) return setmetatable(t or {},{__index=self}) end
function Widget:new(t) return setmetatable(t or {},{__index=self}) end
for _,name in ipairs({'qrmessage','buttondialog','inputdialog'}) do
    package.preload['ui/widget/'..name]=function() return Widget end
end
package.preload['ui/uimanager']=function() return {close=function() end,show=function() end,scheduleIn=function() end} end
local Identity=require('miuread.device_identity')
local Cookies=require('miuread.cookies')
local Auth=require('miuread.auth')

local random_bytes=string.char(0,1,2,3)
local original_open=io.open
io.open=function(path, mode)
    if path=='/dev/urandom' then
        assert(mode=='rb')
        local bytes=random_bytes
        return {read=function(_,size) assert(size==4); return bytes end,close=function() end}
    end
    return original_open(path,mode)
end
local function store()
    local obj={settings={},account={},requests=0}
    function obj:get(key,default)
        local v=self.settings[key]; if v==nil then return copy(default) end; return copy(v)
    end
    function obj:set(key,value)
        if self.fail_write then return false,'simulated disk write failed' end
        self.settings[key]=copy(value); return true
    end
    function obj:read_persisted(key)
        if self.fail_readback then return nil,'simulated readback failure' end
        return copy(self.settings[key])
    end
    function obj:auth() return copy(self.account) end
    function obj:save_auth(auth)
        self.account=copy(auth); self.settings.auth=copy(auth); return true
    end
    function obj:generate_login_session_id() return 'login-session-'..tostring(self.requests) end
    function obj:clear_auth() self.account={}; self.settings.auth={}; return true end
    return obj
end
local function http(fp)
    local mock={calls={}}
    local function observe(opt)
        local cookie=tostring((opt.headers or {}).Cookie or '')
        mock.calls[#mock.calls+1]={url=opt.url,cookie=cookie}
        assert(cookie:find('wr_fp='..fp,1,true), 'missing installation fingerprint in '..opt.url)
        assert(not cookie:find('wr_skey=old-session',1,true), 'old account leaked into new login')
    end
    function mock:request(opt)
        assert(opt.auth==false and opt.method=='GET')
        observe(opt)
        return 'login-page',200,{['Set-Cookie']='qr_preflight=preflight; Path=/'}
    end
    function mock:get_json(url,opt)
        observe({url=url,headers=opt.headers})
        if url:find('getLoginUid',1,true) then
            -- A server-supplied collision must not silently alter device identity.
            return {uid='web-uid'},{['set-cookie']='wr_fp=0; Path=/'}
        elseif url:find('getLoginInfo',1,true) then
            return {succeed=true,webLoginVid='same-user',accessToken='new-token',refreshToken='refresh-token'},{}
        elseif url:find('userInfo',1,true) then
            return {name='Demo'},{}
        elseif url:find('apikeyGet',1,true) then
            return {apikey='skills-key'},{}
        end
        error('unexpected get_json: '..url)
    end
    function mock:post_json(url,body,opt)
        assert(url=='https://weread.qq.com/web/login/renewal')
        assert(body.ql==false)
        observe({url=url,headers=opt.headers})
        return {succ=1},{['set-cookie']='wr_fp=0; Path=/',['x-wr-ticket']='t'}
    end
    return mock
end

local a,b=store(),store()
random_bytes=string.char(0,1,2,3)
local afp=assert(Identity.get(a))
random_bytes=string.char(0,1,2,4)
local bfp=assert(Identity.get(b))
assert(afp=='66051' and bfp=='66052' and afp~=bfp)
assert(Identity.get(a)==afp and Identity.get(b)==bfp)
assert(not Identity.valid('invalid; wr_skey=evil'))
assert(not Identity.valid('4294967296'))
assert(Identity.valid('4294967295'))
local ah,bh=http(afp),http(bfp)
local host={}
local aa,bb=Auth:new(ah,a,host),Auth:new(bh,b,host)
local au,bu=aa:_uid(),bb:_uid()
assert(au=='web-uid' and bu=='web-uid')
assert(aa.jar.wr_fp==afp and bb.jar.wr_fp==bfp)
assert(aa:_poll(au).succeed and bb:_poll(bu).succeed)
local aname=aa:_finish({webLoginVid='same-user',accessToken='new-token',refreshToken='refresh-token'})
local bname=bb:_finish({webLoginVid='same-user',accessToken='new-token',refreshToken='refresh-token'})
assert(aname=='Demo' and bname=='Demo')
assert(a:auth().cookies.wr_fp==afp and b:auth().cookies.wr_fp==bfp)
assert(a:auth().cookies.qr_preflight==nil and b:auth().cookies.qr_preflight==nil)
assert(a:auth().cookies.wr_skey=='new-token')
assert(#ah.calls==6 and #bh.calls==6)
assert(Cookies.header(a:auth().cookies):find('wr_fp='..afp,1,true))
local protected=Cookies.absorb({wr_fp=afp,wr_skey='original'},'wr_fp=987654321; Path=/',{protect_core=true})
assert(protected.wr_fp==afp, 'authenticated response rotated Web device identity')
protected=Cookies.absorb(protected,'wr_fp=; Max-Age=0; Path=/',{protect_core=true})
assert(protected.wr_fp==afp, 'authenticated response deleted Web device identity')
aa:cancel(); a:clear_auth()
assert(Identity.get(a)==afp,'logout changed installation identity')

-- Never request an unbound QR code if identity cannot be stored securely.
local failed=store(); failed.fail_write=true
local failing_auth=Auth:new(http('none'),failed,host)
local ok=pcall(function() failing_auth:_uid() end)
assert(not ok and #failing_auth.http.calls==0,'unsafe QR request after save failure')
failed.fail_write=false; failed.fail_readback=true
ok=pcall(function() failing_auth:_uid() end)
assert(not ok and #failing_auth.http.calls==0,'unsafe QR request after persistence verification failure')

-- Existing Native shelf auth remains separate and never acquires a Web device ID.
local native={uid=function() return 'native-uid' end}
local native_auth=Auth:new({},a,host,native)
assert(native_auth:_uid()=='native-uid' and native_auth.login_fingerprint==nil)
print('Multi-device Web QR login: PASS')
