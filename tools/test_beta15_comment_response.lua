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
assert(res.complete==false and #res.pending_ranges==2 and res.thought_count==0,
    'Empty response must retain pending ranges')
api.answer={reviews={{range='1-4',pageReviews={}}}}
res=ann:fetch_chapter('book','chapter')
assert(res.complete==false and #res.pending_ranges==1 and res.pending_ranges[1]=='5-9',
    'Partial response must retain only missing range')
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
assert(client:readreviews('b',5,batch)==agent and agent_calls==1,
    'Incomplete Web result must attempt Gateway')
web={reviews={{range='1-4',pageReviews={}}}}
assert(client:readreviews('b',5,batch)==web and agent_calls==1,
    'Covered Web result must not retry Gateway')
web={reviews={}};agent={reviews={}}
assert(client:readreviews('b',5,batch)==web and agent_calls==2,
    'Two empty replies remain unconfirmed')
print('PASS: zero / partial coverage, nested text, Gateway recovery, no redundant calls')
