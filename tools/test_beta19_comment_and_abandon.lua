-- beta.19 offline contract: public comments are best-effort, user-facing
-- errors must not be manufactured from sparse/malformed individual records.
package.path='./miuread.koplugin/?.lua;./miuread.koplugin/?/init.lua;'..package.path
-- Reuse the complete beta.18 transport/merge test fixtures, now running under
-- the beta.19 bounded-first-page expectations.
dofile('tools/test_beta18_comment_refresh.lua')
local Ann=require('miuread.annotations')
local Api=require('miuread.api_web')
local api=Api:new({}, {}, {})
local marks={}
for i=1,45 do marks[#marks+1]={range=tostring(i)..'-'..tostring(i+1)} end
api.underlines=function() return {underlines=marks} end
api._web_readreviews=function(_,_,_,batch)
    local rows={}
    for _,request in ipairs(batch) do
        local key=tostring(request.range)
        if key=='1-2' then
            rows[#rows+1]={range=key,pageReviews={
                {reviewId='good-1',content='Useful public thought'},
                'bad nested record',
            }}
        elseif key=='31-32' then
            rows[#rows+1]={range=key,pageReviews={
                {reviewId='good-2',content='Later batch thought'},
            }}
        end
    end
    return {reviews=rows}
end
api._agent_readreviews=function()return {reviews={}} end
api.chapter_public_reviews=function()return {reviews={}} end
local result=Ann:new(api):fetch_chapter('sample-book',9)
assert(result.underline_count==45,'all requested ranges must survive a sparse response')
assert(result.thought_entry_count==2 and #result.review_groups==2,
    'valid comments from both batches must survive a malformed neighbor')
assert(result.complete and result.review_complete and #result.pending_ranges==0,
    'sparse first-page response should not cause phantom missing-range errors')
assert(#result.errors==0,'a few malformed entries are diagnostics, not fatal errors')

-- Native authorized E-Ink write is mandatory on shelf REMOVE, even when Web
-- is the preferred read channel, and must be verified with a separate read.
local membership=require('miuread.shelf_membership')
local writer={}
local calls={read=0,web_write=0,eink_write=0}
function writer:remove_from_shelf(id) assert(id=='sample-book');calls.eink_write=calls.eink_write+1 end
local provider={present=true}
function provider:book_on_shelf(id)
    calls.read=calls.read+1
    if calls.eink_write>0 then self.present=false end
    return self.present
end
function provider:for_channel(which)
    assert(which=='eink');return writer
end
function provider:remove_from_shelf()calls.web_write=calls.web_write+1;error('Web delete is unsupported')end
local removed=membership.run(provider,'sample-book',false,false)
assert(removed.state=='verified' and removed.present==false,
    'shelf removal must be verified against remote membership')
assert(calls.eink_write==1 and calls.web_write==0 and calls.read>=2,
    'shelf remove used Web writer or repeated native deletion')
provider.present=false
local already=membership.run(provider,'sample-book',false,false)
assert(already.state=='verified' and already.already==true and calls.eink_write==1,
    'already removed shelf item must not trigger a second write')
local worker=assert(io.open('miuread.koplugin/miuread/download_task.lua','rb')):read('*a')
assert(worker:find('clean_options.annotations=clean_options.annotations==true',1,true),
    'download worker must preserve the explicit notes EPUB choice')
assert(not worker:find('clean_options.annotations=false',1,true),
    'old B4 worker gate still silently strips public comments')
print('PASS beta19: two sparse batches, malformed entry isolation, native shelf removal, notes worker')
