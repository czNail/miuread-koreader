package.path='miuread.koplugin/?.lua;'..package.path
local function copy(v) if type(v)~='table' then return v end; local o={}; for k,x in pairs(v) do o[k]=copy(x) end; return o end
package.preload['miuread.util']=function() return {copy=copy} end
package.preload['logger']=function() return {info=function() end} end
package.preload['miuread.http']=function() return {
    is_rate_limit_error=function(v) return tostring(v):find('[MiuReadRateLimit]',1,true)~=nil end,
} end
package.preload['miuread.shelf_client']=function() return {credentials=function(a) return a.native_shelf end} end
local Transport=require('miuread.download_transport')
local function reader(authorized)
    local r={web=0,native=0,cleanups=0,prefs={}}
    r.store={preferences=function() return r.prefs end,auth=function() return {native_shelf=authorized~=false and {} or nil} end}
    function r:chapter() self.web=self.web+1; if self.web_error then error(self.web_error) end; return 'web','css',{},{} end
    function r:eink_chapter()
        self.native=self.native+1
        if self.native_error and self.native>=(self.fail_at or 1) then error(self.native_error) end
        return 'native','css',{}, {coordinate_source_authoritative=false}
    end
    function r:cleanup_transient_images() self.cleanups=self.cleanups+1 end
    return r
end
local function fetch(t,uid,opt) return t:chapter({bookId='b'},{chapterUid=uid or 1},'epub',opt or {}) end
-- No benchmark, content comparison or minimum chapter count precedes a download.
for _,options in ipairs({{},{chapter_uid=1},{range_start_index=1,range_end_index=2},
    {annotations=true},{translation=true},{translation_only=true},{generate_translation=true},
    {generate_translation_uid='1'},{prefetch=true},{prefetch_hidden=true}}) do
    local r=reader(); local t=Transport.new(r,options); t:configure('epub')
    for uid=1,4 do assert(fetch(t,uid)=='native') end
    assert(r.native==4 and r.web==0 and t:result().schema==2 and t:result().eink_chapters==4)
end
for _,options in ipairs({{download_transport='web'},{fresh_context=true}}) do
    local r=reader(); local t=Transport.new(r,options)
    assert(fetch(t)=='web' and r.native==0 and r.web==1)
end
local r=reader(false); local t=Transport.new(r,{})
assert(fetch(t)=='web' and t.reason=='authorization_required')
r=reader(); r.prefs.download_transport='web'; t=Transport.new(r,{})
assert(fetch(t)=='web' and t.reason=='manual_web')
r=reader(); t=Transport.new(r,{}); t:configure('pdf')
assert(fetch(t)=='web' and t.reason=='unsupported_format')
-- A real Native failure fixes the rest of the run to Web, including resumes.
r=reader(); r.native_error='E-Ink ZIP 内容校验失败'; r.fail_at=2; t=Transport.new(r,{})
assert(fetch(t,1)=='native')
for uid=2,21 do assert(fetch(t,uid)=='web') end
assert(r.native==2 and r.web==20 and r.cleanups==1)
local result=t:result()
assert(result.eink_chapters==1 and result.web_chapters==20 and result.reason=='eink_failed')
assert(Transport.summary(result):find('本次获取 E-Ink 1 章 / Web 20 章',1,true))
local resumed=Transport.new(reader(),{}); resumed:restore(result)
assert(fetch(resumed)=='web' and resumed.reason=='eink_failed' and resumed.failure.code=='archive_invalid')
result.stopped=true; result.reason='rate_limited'; result.stopped_channel='web'
resumed=Transport.new(reader(),{}); resumed:restore(result)
assert(fetch(resumed)=='web','Web restriction after Native failure must preserve the fallback on resume')
for _,prior in ipairs({{schema=1,reason='eink_failed',selected='web'},
    {schema=2,reason='eink_failed',selected='web',stopped=true},
    {schema=2,reason='rate_limited',selected='eink',stopped=true}}) do
    resumed=Transport.new(reader(),{}); resumed:restore(prior); assert(fetch(resumed)=='native')
end
resumed=Transport.new(reader(),{download_transport='web'}); resumed:restore(result)
assert(fetch(resumed)=='web' and resumed.reason=='manual_web')
-- A Web failure cannot trigger another Native attempt.
r=reader(); r.web_error='Web unavailable'; t=Transport.new(r,{download_transport='web'})
assert(not pcall(fetch,t) and r.native==0 and t:result().web_chapters==0)
for _,err in ipairs({'[MiuReadRateLimit] error_code=499 wait_seconds=300 native_stage=catalog',
    '[MiuReadRateLimit] [MiuReadLocalCooldown] error_code=429 wait_seconds=270 native_stage=chapter_download',
    'download cancelled','__MIUREAD_HIBERNATE__:content'}) do
    r=reader(); r.native_error=err; t=Transport.new(r,{})
    assert(not pcall(fetch,t) and r.native==1 and r.web==0 and t:result().eink_chapters==0)
    if err:find('[MiuReadRateLimit]',1,true) then
        result=t:result(); assert(result.reason=='rate_limited' and result.stopped and result.stopped_channel=='eink')
        assert(result.stopped_phase=='download' and result.limit_code and result.wait_seconds)
        assert(Transport.summary(result):find('已停止',1,true))
    end
end
-- Persist only fixed classifications and numeric codes, never raw responses.
for _,case in ipairs({{'E-Ink 下载密钥填充无效','key_decode'},
    {'E-Ink 正文图片未完整获取','image_missing'},{'E-Ink 书籍样式未能获取','style_missing'},
    {'E-Ink 章节清单文件缺失或重复','chapter_manifest'},
    {'HTTP 403 private-response-token','http_status'},{'error_code=-9 private-response-token','service_error'},
    {'network request failed private-response-token','network'},{'private-response-token','unknown'}}) do
    r=reader(); r.native_error='C:/private/eink_crypto.lua:37: '..case[1]; t=Transport.new(r,{})
    assert(fetch(t)=='web' and t.failure.code==case[2])
    local summary=Transport.summary(t:result())
    assert(not summary:find('private',1,true) and not summary:find('C:/',1,true))
end
assert(Transport.summary({schema=1,benchmark=true,selected='web'})==nil)
-- The production wrapper still exposes the final route on failure and closes sockets.
local file=assert(io.open('miuread.koplugin/miuread/downloader.lua','rb'))
local source=file:read('*a'); file:close()
assert(source:find('transport:restore(cache.manifest.download_transport)',1,true))
assert(source:find('coordinate_source_authoritative==false',1,true))
assert(not source:find('transport_probe',1,true))
local wrapper=assert(source:match('(function Downloader:book%(input, opt, progress%).-\nend)'))
local Downloader=assert(loadstring('local Downloader={}\n'..wrapper..'\nreturn Downloader'))()
r=reader(); r.native_error='[MiuReadRateLimit] error_code=499'; t=Transport.new(r,{})
local closed=false
local d=setmetatable({http={close_idle_connections=function() closed=true end}}, {__index=Downloader})
function d:_book_once() self._download_transport=t; return fetch(t) end
assert(not pcall(d.book,d,{},{}) and closed and d._download_transport==nil and d.last_transport_result.reason=='rate_limited')
file=assert(io.open('miuread.koplugin/main.lua','rb')); source=file:read('*a'); file:close()
assert(not source:find('eink_diagnostic',1,true) and not source:find('download_transport_probe',1,true))
print('download transport: PASS')
