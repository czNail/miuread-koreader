local Client = require("miuread.shelf_client")
local Http = require("miuread.http")
local Protocol = require("miuread.protocol")
local M = {}
M.__index = M
local BASE = "https://i.weread.qq.com"

function M.new(http,store) return setmetatable({http=http,store=store,catalogs={},resources={},translation_modes={}},M) end
function M:cache_key(id)
    local auth=self.store:auth()
    return tostring(auth.login_session_id)..":"..tostring((auth.account or {}).vid)..":"..tostring(id)
end
function M:options(credentials,timeout)
    local options=Client.request_options(credentials,timeout)
    options.keepalive=self.keepalive==true
    return options
end
local function raise_request_error(value,stage)
    local limited=Http.rate_limit_details(value)
    if limited then
        -- Keep only safe diagnostics; response bodies, URLs and tokens must not
        -- be copied into the saved route result or its failure dialog.
        error("E-Ink 请求受限 [MiuReadRateLimit]"
            ..(limited.local_cooldown and " [MiuReadLocalCooldown]" or "")
            .." native_stage="..tostring(limited.native_stage or stage or "unknown")
            ..(limited.code and (" error_code="..tostring(limited.code)) or "")
            ..(limited.wait_seconds and (" wait_seconds="..tostring(limited.wait_seconds)) or ""),0)
    end
    error(tostring(value).." native_stage="..tostring(stage or "client_download"),0)
end
function M:authorized(fn,stage)
    if self.before_request then self.before_request(stage) end
    local credentials = Client.credentials(self.store:auth())
    if not credentials then error("E-Ink 下载需要客户端授权") end
    local ok,a,b,c = pcall(fn,credentials)
    if ok then return a,b,c end
    if Http.is_rate_limit_error(a) or not Http.is_auth_error(a) then raise_request_error(a,stage) end
    if self.before_request then self.before_request("refresh") end
    local renewed,value=pcall(Client.refresh,self.http,self.store)
    if not renewed then raise_request_error(value,"refresh") end
    if self.before_request then self.before_request(stage) end
    local retried,x,y,z=pcall(fn,value)
    if not retried then raise_request_error(x,stage) end
    return x,y,z
end
function M:request(method,path,parameters,stage)
    local value=self:authorized(function(credentials)
        local options=self:options(credentials,{5,20})
        if method=="GET" then
            return self.http:get_json(BASE..path.."?"..Protocol.query(parameters or {}),options)
        end
        return self.http:post_json(BASE..path,parameters,options)
    end,stage)
    if type(value)~="table" then error("E-Ink 客户端响应无效 native_stage="..stage,0) end
    return value
end
function M:underlines(id,uid)
    local value=self:request("GET","/book/underlines",{bookId=tostring(id),chapterUid=tonumber(uid) or uid,synckey=0},"annotations")
    if type(value.underlines)~="table" then error("E-Ink 划线响应不完整",0) end
    return value
end
function M:readreviews(id,uid,batch)
    local value=self:request("POST","/book/readreviews",{bookId=tostring(id),chapterUid=tonumber(uid) or uid,
        cht2sMode="",reviews=batch},"annotations")
    if type(value.reviews)~="table" then error("E-Ink 想法响应不完整",0) end
    return value
end
function M:translation_member_summary()
    local value=self:request("GET","/pay/memberCardSummary",{pf="wechat_wx-2001-android-100-weread"},"translation")
    if value.isPaying==nil then error("E-Ink 会员响应不完整",0) end
    return value
end
function M:toggle_translate(id,enabled)
    local key=self:cache_key(id)
    if self.translation_modes[key]==enabled then return {succ=true} end
    local value=self:request("GET","/trans/pdfepub",{cbid=tostring(id),
        transFormat=enabled and "epubTranslate" or "epub",transType="epubTranslate"},"translation")
    if value.succ~=true and tonumber(value.succ)~=1 then error("E-Ink 译文模式未能开启",0) end
    self.translation_modes[key]=enabled
    return value
end
function M:en_read(id,uid,read)
    local entries={}
    for _,item in ipairs(read or {}) do
        entries[#entries+1]={uid=tonumber(item.uid) or item.uid,translateVersion=tonumber(item.translateVersion) or 0}
    end
    if #entries<1 or #entries>2 then error("E-Ink 译文请求章节数无效",0) end
    -- freeTrial=0 follows the Native request contract without activating a trial.
    local value=self:authorized(function(credentials)
        local Json=require("miuread.json")
        local options=self:options(credentials,{5,20})
        options.url=BASE.."/en/bookread"; options.method="POST"
        options.body='{"bookId":'..Json.encode(tostring(id))..',"read":'..Json.encode(entries)
            ..',"reference":{"uid":'..Json.encode(tonumber(uid) or uid)..',"texts":[]},"freeTrial":0}'
        return self.http:json(options)
    end,"translation")
    if type(value)~="table" or (value.curStatus==nil and value.stopPoll==nil and value.tips==nil
        and value.translationProgress==nil) then error("E-Ink 译文状态响应无效",0) end
    if value.stopPoll==nil and value.translationProgress~=nil then value.stopPoll=0 end
    return value
end
function M:catalog(id)
    local cache_key = self:cache_key(id)
    if self.catalogs[cache_key] then return self.catalogs[cache_key] end
    local data = self:authorized(function(credentials)
        -- Request a complete catalog, using parallel arrays for the one book.
        -- Zero versions prevent an incremental/unchanged response from being
        -- mistaken for an empty catalog on the first request of a run.
        return self.http:post_json(BASE.."/book/chapterInfos",
            {bookIds={id},synckeys={0},updateTimes={0},maxfreeIdx={0}},self:options(credentials,{5,12}))
    end,"catalog")
    for _,record in ipairs(type(data)=="table" and (data.data or {}) or {}) do
        if tostring(record.bookId or "") == id and type(record.updated)=="table" then
            self.catalogs[cache_key] = record
            return record
        end
    end
    error("E-Ink 未返回对应书籍目录")
end
function M:download(book,chapter,path,opt)
    opt=opt or {}
    local id,uid = tostring(book.bookId or book.book_id), tostring(chapter.chapterUid or chapter.uid)
    local catalog = self:catalog(id)
    if opt.web_catalog_version~=nil and tostring(opt.web_catalog_version)~=tostring(catalog.synckey) then
        error("E-Ink 与 Web 目录版本不同")
    end
    local selected
    for _,row in ipairs(catalog.updated) do if tostring(row.chapterUid)==uid then selected=row; break end end
    if not selected then error("E-Ink 目录中不存在当前章节") end
    -- Avoid native auto-purchase semantics: only request chapters whose catalog
    -- explicitly says free or already paid. Other entitlements stay with Web.
    if not ((tonumber(selected.price)~=nil and tonumber(selected.price)<=0) or (tonumber(selected.paid) or 0)>0) then
        error("E-Ink 目录未确认章节免费或已购买")
    end
    local format = tostring((catalog.book or {}).format or catalog.format or ""):lower()
    if format ~= "epub" and format ~= "txt" then error("E-Ink 书籍格式暂不支持") end
    local version = format=="txt" and "0" or tostring((catalog.book or {}).version or book.version or catalog.synckey or "")
    if version == "" then error("E-Ink 书籍版本缺失") end
    local resource_key=self:cache_key(id)..":"..version
    local chapters=format=="epub" and not self.resources[resource_key] and uid~="0" and ("0,"..uid) or uid
    local url = BASE.."/book/chapterdownload?bookId="..Protocol.escape(id).."&chapters="..Protocol.escape(chapters)
        .."&bookType="..format.."&bookVersion="..Protocol.escape(version)
        .."&pf=wechat_wx-2001-android-100-weread&pfkey=pfKey&zoneId=1"
        .."&quote=&release=1&stopAutoPayWhenBNE=1&preload=2&preview=0&offline=1"
    return self:authorized(function(credentials)
        local options = self:options(credentials,{5,22})
        options.keepalive=options.keepalive or opt.keepalive==true
        options.integrity_attempts = 1
        options.on_chunk = function(bytes)
            if type(opt.yield)=="function" then opt.yield("content") end
            if type(opt.activity)=="function" then opt.activity("native_archive_download",{bytes=bytes}) end
        end
        local downloaded,headers,_,meta = self.http:download_to_file(url,path,options)
        local envelope
        for key,value in pairs(headers or {}) do if tostring(key):lower()=="encryptkey" then envelope=value end end
        if not envelope then
            -- Classify JSON auth/rate errors through the same HTTP JSON path,
            -- without logging or displaying the response body or envelope.
            local raw = type(meta)=="table" and tostring(meta.preview or "") or ""
            local code = tonumber(raw:match('"err[Cc]ode"%s*:%s*(%-?%d+)') or raw:match('"errcode"%s*:%s*(%-?%d+)'))
            if code==-2011 or code==-2012 or code==-2041 then error(Http.auth_error_message(code)) end
            if code==-10102 or code==-2014 then error("[MiuReadRateLimit] error_code="..tostring(code)) end
            if code and code~=0 then error("E-Ink 章节服务返回错误 error_code="..tostring(code),0) end
            error("E-Ink 未返回章节下载密钥")
        end
        self.resources[resource_key]=true
        return downloaded,envelope,credentials.vid
    end,"chapter_download")
end
return M
