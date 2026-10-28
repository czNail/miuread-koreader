-- Independent public-comment refresh regression scenarios. Offline, no credentials.
package.path='./miuread.koplugin/?.lua;./miuread.koplugin/?/init.lua;'..package.path
package.preload['logger']=function()
    return {warn=function()end,info=function()end,dbg=function()end,err=function()end}
end
package.preload['miuread.util']=function()
    return {first_line=function(v)return tostring(v or '') end,trim=function(v)return tostring(v or '') end,
        copy=function(value)
            if type(value)~='table' then return value end
            local out={} for k,v in pairs(value) do out[k]=v end return out
        end}
end
package.preload['miuread.thoughts']=function()return {} end
package.preload['miuread.http']=function()
    return {is_auth_error=function()return false end,is_rate_limit_error=function()return false end,
        is_forbidden_error=function()return false end,auth_error_code=function()return nil end}
end
package.preload['miuread.annotation_coord']=function()return {} end
package.preload['miuread.annotations.posmap']=function()return {} end
package.preload['miuread.annotations.range']=function()return {} end
package.preload['miuread.annotation_style']=function()return {CSS=''} end
package.preload['miuread.codec']=function()return {} end
package.preload['miuread.protocol']=function()
    return {escape=function(v) return tostring(v or '') end,
        reader_url=function()return 'https://weread.qq.com/web/reader/demo' end}
end
local Api=require('miuread.api_web')
local Ann=require('miuread.annotations')
local api=Api:new({}, {}, {})
local network={web={reviews={{range='1-4',pageReviews={}}}},agent={reviews={{range='1-4',pageReviews={}}}},feed={reviews={}}}
api.underlines=function()return {underlines={{range='1-4'}}} end
api._web_readreviews=function() return network.web end
api._agent_readreviews=function() return network.agent end
api.chapter_public_reviews=function()return network.feed end

-- A structurally sound empty batch is a valid bounded, best-effort fetch.
-- The user can explicitly update later; do not retry indefinitely.
local first=Ann:new(api):fetch_chapter('book',4)
assert(first.complete and first.review_complete and #first.pending_ranges==0,
    'valid empty range response must not create endless retries')

-- A flat public-thought list can rescue content missing from the range API,
-- including a range that was not returned by /book/underlines.
network.feed={reviews={{reviewId='public-one',review={range='9-14',content='Published thought',
    abstract='A quote',author={name='Reader'},createTime=5}}}}
local recovered=Ann:new(api):fetch_chapter('book',4)
assert(recovered.thought_entry_count==1 and recovered.complete==true,
    'chapter feed must add public thoughts without falsely failing the bounded fetch')
assert(recovered.review_map['9-14'][1].content=='Published thought',
    'supplemental public thought must be saved under its own range')
local has_anchor=false
for _,mark in ipairs(recovered.underlines) do
    if mark.range=='9-14' then has_anchor=true end
end
assert(has_anchor,'chapter feed-only range must not be discarded by storage merge')

-- A valid explicit zero from *both* sources can be complete, but an independent
-- chapter feed disclosing a real thought overrides the empty conclusion.
network.web={reviews={{range='1-4',totalCount=0,pageReviews={}}}}
network.agent={reviews={{range='1-4',totalCount=0,pageReviews={}}}}
local contradiction=Ann:new(api):fetch_chapter('book',4)
assert(contradiction.thought_entry_count==1 and contradiction.complete,
    'positive chapter feed must preserve content without making a successful fetch partial')
network.feed={reviews={}}
local legitimate_empty=Ann:new(api):fetch_chapter('book',4)
assert(legitimate_empty.complete and #legitimate_empty.pending_ranges==0,
    'both explicit zero counts with an empty feed may be marked complete')

-- Flat /web/book/readReviews records must be counted, parsed and persisted.
network.web={reviews={{reviewId='r-flat',review={range='1-4',content='Flat response',
    author={name='Author'}}}}}
network.agent={reviews={}}
local flat=Ann:new(api):fetch_chapter('book',4)
assert(flat.thought_entry_count==1 and flat.review_map['1-4'][1].content=='Flat response',
    'flat review entries must not be lost to the pageReviews-only decoder')

-- Previously saved valid rows must NEVER disappear on a forced refresh with
-- zero responses, even when transport reported the range complete.
local previous={underline_request_ok=true,underlines={{range='1-4'}},review_groups={
    {range='1-4',texts={{review_id='kept',content='Previously cached'}}}},review_map={
    ['1-4']={{review_id='kept',content='Previously cached'}}},pending_ranges={},completed_ranges={'1-4'},complete=true}
network.web={reviews={{range='1-4',totalCount=0,pageReviews={}}}}
network.agent={reviews={{range='1-4',totalCount=0,pageReviews={}}}}
local now=Ann:new(api):fetch_chapter('book',4)
local merged=Ann:new(api):merge(previous,now)
assert(merged.thought_entry_count==1 and merged.review_map['1-4'][1].content=='Previously cached',
    'empty forced refresh must preserve previously cached public thoughts')

-- A later underline response can omit a previously stored range: refresh
-- must not silently delete valid cached comments or the matching anchor.
local no_range={underline_request_ok=true,underlines={},review_map={},review_groups={},
    completed_ranges={},pending_ranges={},complete=true}
local retained=Ann:new(api):merge(previous,no_range)
assert(retained.thought_entry_count==1 and retained.review_map['1-4'][1].content=='Previously cached'
    and #retained.underlines==1,'vanished underline must not delete cached reviews')

-- chapter-level URL must use the explicit list endpoint and a bounded GET;
-- book/chapter identity must not be omitted.
local capture={}
local transport=Api:new({get_json=function(_,url,options)
    capture.url=url;capture.options=options
    return {reviews={}}
end},{},{})
transport:chapter_public_reviews('123',4)
assert(capture.url:find('/web/review/list?',1,true)
    and capture.url:find('bookId=123',1,true)
    and capture.url:find('chapterUid=4',1,true)
    and capture.options.retries==0,
    'chapter feed must use bounded Web GET with correct book/chapter coordinates')

-- JSON POST chapterUid must be numeric first for numeric chapters.
local seen_uid
local post=Api:new({post_json=function(_,_,payload)
    seen_uid=payload.chapterUid
    return {reviews={}}
end},{},{})
post:_web_readreviews('123','4',{{range='1-4',count=30,maxIdx=0,synckey=0}})
assert(type(seen_uid)=='number' and seen_uid==4,
    'JSON readReviews must prefer numeric chapterUid')
-- A malformed item must not invalidate all other completed ranges.
network.web={reviews={{range='1-4',pageReviews={{reviewId='good',content='Good'},'bad-shape'}}}}
network.agent={reviews={}}
local tolerant=Ann:new(api):fetch_chapter('book',4)
assert(tolerant.thought_entry_count==1 and tolerant.complete and #tolerant.pending_ranges==0,
    'one malformed entry must not mark the entire batch incomplete')
assert(#tolerant.errors==0,'malformed item must remain a diagnostic, not a user-facing failure')
print('PASS beta19: best-effort first page, public feed, malformed entry isolation, cache merge, Web parameters')
