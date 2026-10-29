-- beta.17 offline behavioral tests: no WeRead network and no KOReader device required.
package.path='./miuread.koplugin/?.lua;./miuread.koplugin/?/init.lua;'..package.path
package.preload['logger']=function()
    return {warn=function() end,info=function() end,dbg=function() end,err=function() end}
end
package.preload['miuread.util']=function()
    return {trim=function(x)return tostring(x or '') end,first_line=function(x)return tostring(x or '') end}
end
package.preload['miuread.http']=function()
    return {is_auth_error=function() return false end,is_network_error=function()return false end,
        is_rate_limit_error=function()return false end,is_forbidden_error=function()return false end,
        auth_error_code=function()return nil end}
end
package.preload['miuread.legacy.cookie']=function()
    return {has_login_cookie=function()return true end}
end
package.preload['miuread.legacy.content']=function()
    return {is_structural_chapter=function()return false end,
        ensure_reader_state=function() end,
        fetch_catalog=function() error('catalog fetch should be unnecessary') end}
end
local requests={}
local web_reply={bookId='b',chapterUid='20',chapterIdx=1,chapterOffset=222,progress=72}
package.preload['miuread.legacy.client']=function()
    local C={}
    function C:new()return setmetatable({}, {__index=self})end
    function C:get_web_progress()
        if web_reply==false then error('temporary web outage') end
        return web_reply
    end
    function C:parse_web_progress(result,id)
        return require('miuread.legacy.web_progress_wire').parse(result,id)
    end
    function C:get_progress()error('agent getProgress unavailable')end
    function C:report_read(payload)
        requests[#requests+1]=payload
        return {succ=1,synckey=123},200,{}
    end
    return C
end
package.preload['miuread.legacy.weread']=function()
    return {reader_url=function()return 'https://weread.qq.com/web/reader/abc' end,
        web_app_id=function()return 'test' end,
        make_read_payload=function(o)
            return {ci=o.chapter_idx,co=o.chapter_offset,pr=o.progress,rt=o.elapsed_seconds,
                appId='test',pc='safe',s='safe'}
        end}
end
local Worker=require('miuread.legacy.read_report_worker')
local function book(progress,offset,uid)
    return {book_id='b',title='Book',chapters={
        {chapterUid='10',chapterIdx=0,wordCount=500},
        {chapterUid='20',chapterIdx=1,wordCount=500}},
        read_context_updated_at=os.time(),read_context_ready=true,
        psvts='ctx',chapter_uid='10',chapter_idx=0,
        local_chapter_uid=uid or '10',local_chapter_idx=0,
        local_chapter_offset=offset or 80,local_native_chapter_offset=true,
        local_chapter_offset_basis='wr_data_co',progress=progress,
        catalog_complete=true,core_map_hash='h'}
end
-- Local Kindle position intentionally differs from the confirmed server tuple.
local result=Worker.run{book_id='b',book=book(12,81),cookies={k='v'},
    core_map_hash='h',elapsed_seconds=47,progress_ratio=.12,
    time_only=true,report_mode='reading_time_compat'}
assert(result.ok==true,'fresh Web time echo must be dispatchable')
assert(#requests==1 and requests[1].ci==1 and requests[1].co==222
    and requests[1].pr==72 and requests[1].rt==47,
    'time must echo fresh Web tuple, never approximate Kindle position')

local no_native=book(23,82)
no_native.local_native_chapter_offset=false
local no_native_result=Worker.run{book_id='b',book=no_native,cookies={k='v'},
    core_map_hash='h',elapsed_seconds=45,time_only=true,report_mode='reading_time_compat'}
assert(no_native_result.ok==true and #requests==2,
    'time-only worker must not depend on local native offset')

web_reply=false
local outage=Worker.run{book_id='b',book=book(25,84),cookies={k='v'},
    core_map_hash='h',elapsed_seconds=45,time_only=true,report_mode='reading_time_compat'}
assert(outage.ok==false and outage.meta.request_dispatched==false
    and #requests==2,'Web unavailable must fail closed before sending time')

web_reply={bookId='b',chapterUid='20',chapterIdx=0,chapterOffset=222,progress=72}
local mismatch=Worker.run{book_id='b',book=book(25,84),cookies={k='v'},
    core_map_hash='h',elapsed_seconds=45,time_only=true,report_mode='reading_time_compat'}
assert(mismatch.ok==false and mismatch.meta.request_dispatched==false
    and #requests==2,'Web chapter-index mismatch must refuse POST')

local nonterminal=Worker.run{book_id='b',book=book(100,99),cookies={k='v'},
    core_map_hash='h',progress_ratio=1,time_only=false}
assert(nonterminal.ok==false and #requests==2,
    'a nonfinal chapter must never masquerade as 100% whole-book progress')
print('PASS 6.2: Web-position time echo, unsafe Web guard, terminal progress isolation')

package.preload['miuread.codec']=function()return {} end
package.preload['miuread.protocol']=function()return {} end
local Api=require('miuread.api_web')
local api=Api:new({}, {}, {})
local gateway_calls=0
local web={reviews={{range='1-3',pageReviews={}}}}
local gateway={reviews={{range='1-3',pageReviews={{reviewId='a',content='real comment'}}}}}
api._web_readreviews=function()return web end
api._agent_readreviews=function() gateway_calls=gateway_calls+1;return gateway end
local batch={{range='1-3'}}
local value=api:readreviews('b',10,batch)
assert(gateway_calls==1 and #value.reviews==1 and #value.reviews[1].pageReviews==1,
    'Web zero must recover Gateway real comment')
web={reviews={{range='1-3',pageReviews={}}}}
gateway={reviews={{range='1-3',pageReviews={}}}}
local empty=api:readreviews('b',10,batch)
assert(empty._miu_uncertain_ranges['1-3']==true,
    'two unverified zero responses must not be declared complete')
web={reviews={{range='1-3',totalCount=0,pageReviews={}}}}
gateway={reviews={{range='1-3',totalCount=0,pageReviews={}}}}
local confirmed_empty=api:readreviews('b',10,batch)
assert(confirmed_empty._miu_uncertain_ranges['1-3']==nil,
    'explicit zero totals can be confirmed as genuinely empty')
print('PASS beta17: fallback, merged real comments, ambiguous vs confirmed empty')
