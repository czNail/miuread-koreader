-- Run in a Lua 5.4/SQLite harness. Uses the real B2 annotation parser,
-- comment sync and database modules; only network, KOReader and JSON are stubbed.
-- To run outside KOReader, supply the test-only Lua/SQLite shim on
-- MIUREAD_TEST_SQLITE_CPATH; the shim is not a production dependency.
package.path='./miuread.koplugin/?.lua;./miuread.koplugin/?/init.lua;'..package.path
package.cpath=(os.getenv('MIUREAD_TEST_SQLITE_CPATH') or '')..';'..package.cpath
local function serialize(value)
    local kind=type(value)
    if kind=='string' then return string.format('%q',value) end
    if kind=='number' or kind=='boolean' then return tostring(value) end
    if kind~='table' then return 'nil' end
    local out={}
    for k,v in pairs(value) do out[#out+1]='['..serialize(k)..']='..serialize(v) end
    return '{'..table.concat(out,',')..'}'
end
package.preload['miuread.json']=function()
    return {encode=function(t) return 'return '..serialize(t) end,
        decode=function(t) return assert(load(t))() end}
end
package.preload['logger']=function() return {warn=function() end,info=function() end,err=function() end,dbg=function()end} end
package.preload['miuread.util']=function()
    return {id_name=function(s) local v=tostring(s):gsub('[^%w%-_]','_'); return v end,
        mkdir=function(p) os.execute('mkdir -p '..string.format('%q',p)) end,
        read_file=function(p) local f=io.open(p,'rb'); if not f then return nil end;local x=f:read('*a');f:close();return x end}
end
package.preload['libs/libkoreader-lfs']=function()
    return {attributes=function(path,kind) local f=io.open(path,'rb');if f then f:close();return kind=='mode' and 'file' or {modification=1,size=1} end end}
end
package.preload['lua-ljsqlite3/init']=function() return require('sqlitetest') end
package.preload['miuread.http']=function()
    return {is_auth_error=function() return false end,
        is_rate_limit_error=function() return false end,is_forbidden_error=function() return false end}
end
package.preload['miuread.annotation_style']=function()return {CSS=''} end
package.preload['miuread.annotation_coord']=function()return {} end
package.preload['miuread.annotations.posmap']=function()return {} end
package.preload['miuread.annotations.range']=function()return {} end
local db=require('miuread.thought_database')
local Comments=require('miuread.comment_sync')
local root=os.getenv('MIUREAD_B2_TEST_ROOT') or './.test-beta13-b2-comment-sync'
os.execute('rm -rf '..string.format('%q',root))
local store={book_dir=function(_,book) return root..'/'..book end}
local api={broken=false, first_phase=true, first_calls=0, fail_underlines=false}
function api:underlines(_,uid)
    if uid=='empty' then return {underlines={}} end
    if uid=='badunderlines' or self.fail_underlines then error('network request failed') end
    return {underlines={{range='1-4'},{range='5-9'}}}
end
function api:review_batches(ranges)
    local batches={}
    for _,r in ipairs(ranges) do batches[#batches+1]={{range=r,maxIdx=0,count=30,synckey=0}} end
    return batches
end
function api:readreviews(_,uid,batch)
    local range=batch[1].range
    if uid=='badreview' then return {} end
    if range=='5-9' and self.first_phase then error('network request failed') end
    if range=='1-4' then
        self.first_calls=self.first_calls+1
        return {reviews={{range=range,pageReviews={{review={reviewId='r1',content='First',authorName='A',createdAt=1}}}}}}
    end
    return {reviews={{range=range,pageReviews={{review={reviewId='r2',content='Second',authorName='B',createdAt=2}}}}}}
end
local sync=Comments:new(api,store)
local first=assert(sync:fetch('book','chapter'))
assert(first.partial==true and first.comments==1,'partial must keep first successful batch')
local partial=assert(db.load_checkpoint(store,'book','chapter'))
assert(#partial.pending_ranges==1 and partial.pending_ranges[1]=='5-9','checkpoint must retain failed range')
assert(#partial.underlines==2,'store original range coordinates for resume')
local read=assert(sync:load('book','chapter'))
assert(#read==1 and read[1].texts[1].content=='First','visible cached rows survive first failure')
local offline=Comments:new(api,store)
local status=offline:status('book','chapter')
assert(status.has_cache and status.status=='partial' and status.comments==1,'offline restart')
api.first_phase=false
local recovered=assert(offline:fetch('book','chapter'))
assert(recovered.partial==false and recovered.comments==2,'resume to two cached comments')
local after=assert(db.load_checkpoint(store,'book','chapter'))
assert(#after.pending_ranges==0,'resume must clear pending ranges')
local before_calls=api.first_calls
local reused=assert(offline:fetch('book','chapter'))
assert(reused.cached and api.first_calls==before_calls,'cached chapter must not request network again')
local forced=assert(offline:fetch('book','chapter',{force=true}))
assert(forced.comments==2 and api.first_calls==before_calls+1,'forced update must deduplicate')
api.fail_underlines=true
local refresh_error=offline:fetch('book','chapter',{force=true})
assert(refresh_error==nil and offline:status('book','chapter').comments==2,
    'failed forced refresh must not delete older cached reviews')
api.fail_underlines=false
local retry_before=api.first_calls
local retry=assert(offline:fetch('book','chapter'))
assert(retry.comments==2 and api.first_calls==retry_before+1,
    'retry after failed refresh must actually contact the server')
local empty=assert(offline:fetch('book','empty',{force=true}))
assert(empty.status=='empty' and empty.comments==0 and offline:status('book','empty').has_cache,'valid empty response persists')
local bad=assert(offline:fetch('book','badreview',{force=true}))
assert(bad.status=='partial' and not db.load_checkpoint(store,'book','badreview').complete,'invalid payload must not masquerade as empty')
local error_res=offline:fetch('book','badunderlines',{force=true})
assert(error_res==nil and offline:status('book','badunderlines').status=='error'
    and offline:status('book','badunderlines').has_cache==false,
    'failed underline request must remain an error without fake empty cache')
assert(db.integrity(store,'book'),'real SQLite integrity after partial/resume/force/empty')
os.execute('rm -rf '..string.format('%q',root))
print('PASS B2 real SQLite: partial checkpoint, restart, resume, dedup, offline, force refresh, empty and invalid response')
