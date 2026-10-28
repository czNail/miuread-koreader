-- Public comment hotfix regression. Run from repository root with Lua 5.4.
package.path='./miuread.koplugin/?.lua;./miuread.koplugin/?/init.lua;'..package.path
package.preload['logger']=function()
    return {warn=function() end,info=function() end,dbg=function() end,err=function() end}
end
package.preload['miuread.thoughts']=function() return {} end
package.preload['miuread.http']=function()
    return {is_auth_error=function() return false end,
            is_rate_limit_error=function() return false end,
            is_forbidden_error=function() return false end}
end
package.preload['miuread.util']=function() return {} end
package.preload['miuread.annotation_coord']=function() return {} end
package.preload['miuread.annotations.posmap']=function() return {} end
package.preload['miuread.annotations.range']=function() return {} end
package.preload['miuread.annotation_style']=function() return {CSS=''} end

local Ann=require('miuread.annotations')
local api={answer={reviews={}}}
function api:underlines() return {underlines={{range='1-4'},{range='5-9'}}} end
function api:review_batches(ranges)
    local batch={}
    for _,r in ipairs(ranges) do batch[#batch+1]={range=r} end
    return {batch}
end
function api:readreviews() return self.answer end
local ann=Ann:new(api)
local res=ann:fetch_chapter('book','chapter')
assert(res.complete and #res.pending_ranges==0 and res.thought_count==0,
    'Well-formed empty first-page is a completed bounded fetch')
api.answer={reviews={{range='1-4',pageReviews={}}}}
res=ann:fetch_chapter('book','chapter')
assert(res.complete and #res.pending_ranges==0,
    'Sparse first-page result must not force endless missing-range retries')
api.answer={reviews={{range='1-4',pageReviews={}},{range='5-9',
    pageReviews={{review={reviewId='r1',review={content='Nested comment',author={name='reader'}}}}}}}}
res=ann:fetch_chapter('book','chapter')
assert(res.complete==true and #res.pending_ranges==0 and res.thought_entry_count==1,
    'Nested review parsing / range coverage failed')
assert(res.review_groups[1].texts[1].content=='Nested comment','Nested text missing')

package.preload['miuread.protocol']=function() return {} end
package.preload['miuread.codec']=function() return {} end
local Api=require('miuread.api_web')
local client=Api:new({}, {}, {})
local agent_calls=0
local web={reviews={}}
local agent={reviews={{range='1-4',pageReviews={}}}}
client._web_readreviews=function() return web end
client._agent_readreviews=function() agent_calls=agent_calls+1;return agent end
local batch={{range='1-4'}}
local recovered=client:readreviews('b',5,batch)
assert(type(recovered)=='table' and #recovered.reviews==1 and agent_calls==1,
    'Incomplete Web result must attempt Gateway and merge ranges')
web={reviews={{range='1-4',pageReviews={}}}}
local empty=client:readreviews('b',5,batch)
assert(type(empty)=='table' and agent_calls==2 and empty._miu_uncertain_ranges['1-4']==true,
    'Covered but empty Web result must still cross-check Gateway')
web={reviews={}};agent={reviews={}}
local two_empty=client:readreviews('b',5,batch)
assert(type(two_empty)=='table' and agent_calls==3,
    'Two empty replies require cross-source verification')
print('PASS: zero / partial coverage, nested text, Gateway recovery, no redundant calls')
