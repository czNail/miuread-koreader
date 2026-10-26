-- beta.9: Pure, side-effect-free reader of Web getProgress protocol fields.
-- Used by the isolated reading-time worker, NOT the Agent progress response.
local Wire={}
function Wire.parse(result,book_id)
    if type(result)~="table" then return nil,"missing_response","context" end
    local code=tonumber(result.errCode or result.errcode)
    if code and code~=0 then
        local msg=tostring(result.errMsg or result.errmsg or code)
        local low=msg:lower()
        local auth=code==401 or code==403 or code==-2012 or code==1024
            or low:find("login",1,true) or low:find("cookie",1,true)
            or msg:find("登录",1,true)
        return nil,msg,auth and "authentication" or "server"
    end
    local raw=type(result.book)=="table" and result.book
        or (type(result.data)=="table" and (type(result.data.book)=="table" and result.data.book or result.data))
        or result
    local id=raw.bookId or raw.book_id
    if id~=nil and tostring(id)~=tostring(book_id) then return nil,"book_identity_mismatch","context" end
    local uid=raw.chapterUid or raw.chapterId or raw.chapter_uid
    local co=tonumber(raw.chapterOffset or raw.chapterPos or raw.offset)
    -- Protocol pr is not KOReader's EPUB-wide percentage.
    local pr=tonumber(raw.progress)
    local idx=tonumber(raw.chapterIdx or raw.chapterIndex or raw.chapter_idx)
    if tostring(uid or "")=="" or co==nil or co<0 or pr==nil or pr<0 or pr>100 then
        return nil,"web_position_incomplete","context"
    end
    if idx~=nil and (idx<0 or idx~=math.floor(idx)) then return nil,"invalid_chapter_idx","context" end
    return {chapter_uid=uid,chapter_idx=idx,chapter_offset=co,protocol_progress=pr},nil,nil
end
return Wire
