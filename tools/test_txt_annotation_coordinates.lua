-- Run on KOReader from its directory:
--   ./luajit <repo>/tools/test_txt_annotation_coordinates.lua <repo>/miuread.koplugin [original posmap.lua]
-- TXT chapters are addressed on their raw text; markup maps must not change.
require('setupkoenv')
local plugin=assert(arg[1],'plugin path required')
package.path=plugin..'/?.lua;'..package.path
local PosMap=require('miuread.annotations.posmap')
local Coord=require('miuread.annotation_coord')
local IDEO='\227\128\128'

-- 1. Plain maps keep markup-looking text, CRLF and indentation as positions.
local raw='第一段，甲<不是标签>&乙。\r\n'..IDEO..IDEO..'第二段开头，他说：“走吧！”\r\n'..IDEO..IDEO..'第三段结尾。'
local map=PosMap.build(raw,true)
assert(map.plain_text==true and map.text==raw,'plain map changed the raw text')
assert(PosMap.build('<p>甲</p>').text=='甲' and not PosMap.build('<p>甲</p>').plain_text,'markup map changed')

-- 2. A selection spanning a paragraph break (KOReader gives "\n" + indentation)
--    resolves to the raw-text range of exactly that text.
local selection='他说：“走吧！”\n'..IDEO..IDEO..'第三段'
local range=assert(PosMap.locate(map,selection),'cross-paragraph selection not found')
local resolved=assert(Coord.resolveRangeOnMap(map,range))
local function clean(s) return (s:gsub('%s',''):gsub(IDEO,''):gsub('%*','')) end
assert(clean(resolved.text)==clean(selection),'resolved text differs: '..resolved.text)
local bridge={coord=map,injected=map,stars={}}
local injected_range=assert(PosMap.locateInjected(bridge,selection),'bridge locate failed')
assert(injected_range==range,'bridge and direct ranges differ')
-- Positions count raw runes: the range starts after the CRLF and indentation.
local start=tonumber(range:match('^(%d+)'))
local runes=require('miuread.annotations.runes').toRunes(raw)
assert(table.concat(runes,'',start+1,start+3)=='他说：','range does not address raw text runes') -- ranges are 0-based

-- 3. Markup maps are byte-for-byte unchanged against the original module.
local original_path=arg[2]
if original_path then
    local Original=assert(loadfile(original_path))()
    math.randomseed(17)
    local pieces={'甲','乙','丙','，','。','<p>','</p>','<b>','</b>',' ','\n','\r\n',IDEO,'*','“','”','a','1'}
    local function random_html(n)
        local out={}
        for i=1,n do out[i]=pieces[math.random(#pieces)] end
        return table.concat(out)
    end
    local compared=0
    for _=1,400 do
        local html='<p>'..random_html(math.random(20,80))..'</p>'
        local a,b=Original.build(html),PosMap.build(html)
        assert(a.text==b.text and a.norm_text==b.norm_text,'markup map normalisation changed')
        local text_runes=b.text_runes
        if #text_runes>4 then
            local i=math.random(1,#text_runes-2)
            local j=math.min(#text_runes,i+math.random(1,6))
            local needle=table.concat(text_runes,'',i,j)
            local ra,ea=Original.locate(a,needle)
            local rb,eb=PosMap.locate(b,needle)
            assert(ra==rb and ea==eb,'markup locate changed for '..needle)
            local ba={coord=a,injected=a,stars={}}
            local bb={coord=b,injected=b,stars={}}
            local ia,iea=Original.locateInjected(ba,needle)
            local ib,ieb=PosMap.locateInjected(bb,needle)
            assert(ia==ib and iea==ieb,'markup locateInjected changed for '..needle)
            compared=compared+1
        end
    end
    assert(compared>300,'too few markup comparisons')
end
-- 4. Annotation sync: TXT contexts use the raw text (version 0 allowed only
--    there), EPUB contexts are unchanged, and a TXT state without raw text
--    fails closed instead of falling back to generated HTML coordinates.
local inert=setmetatable({},{__index=function() return function() end end})
package.loaded['device']=setmetatable({model='test',screen=inert,input=inert,powerd=inert},{__index=function(_,k)
    if type(k)=='string' and (k:match('^is') or k:match('^has') or k:match('^can')) then return function() return false end end
end})
G_reader_settings=G_reader_settings or require('luasettings'):open(os.tmpname())
local Sync=require('miuread.annotation_sync')
local state
local saved_versions={}
local service=setmetatable({store={save_book=function(_,id,patch) saved_versions[#saved_versions+1]=patch.version end},
    reader={chapter=function() return state.coord_html,nil,nil,state end}},Sync)
local function ctx_for() return service:_coord_map_for_chapter({bookId='b'},{chapter_uid='5',chapter_idx=5},nil,{}) end
state={coord_html='<p>generated</p>',raw_xhtml='<p>generated</p>',raw_text=raw,content_format='txt'}
local txt=assert(ctx_for())
assert(txt.plain_text==true and txt.coord_source=='raw_txt' and txt.book_version==0 and txt.html==raw,'TXT context')
assert(#saved_versions==0,'version 0 was written to the library')
state={coord_html='<p>generated</p>',raw_xhtml='<p>generated</p>',content_format='txt'}
local missing,missing_err=ctx_for()
assert(missing==nil and missing_err=='raw_txt_missing','TXT without raw text did not fail closed')
state={coord_html='<p>甲乙丙</p>',raw_xhtml='<p>甲乙丙</p>',content_format='epub',book_version=7}
local epub=assert(ctx_for())
assert(not epub.plain_text and epub.html==state.coord_html and epub.book_version==7 and epub.coord_source=='raw_xhtml','EPUB context changed')
assert(#saved_versions==1 and saved_versions[1]==7,'positive EPUB version was not saved')
local validate
for i=1,200 do local k,v=debug.getupvalue(Sync.sync_book,i); if k=='validate_payload' then validate=v break end; if not k then break end end
assert(validate,'validate_payload not found')
local payload={bookId='b',chapterUid='c',range='1-3',type=1,markText='文本',bookVersion=0}
assert(validate({kind='highlight'},payload,true),'TXT version 0 rejected')
assert(not validate({kind='highlight'},payload,false),'EPUB version 0 accepted')
payload.bookVersion=nil
assert(not validate({kind='highlight'},payload,true),'missing TXT version accepted')
payload.bookVersion=7
assert(validate({kind='highlight'},payload,false),'EPUB version rejected')

print('TXT annotation coordinates: raw text map, cross-paragraph selection, bridge locate, sync contexts and versions'..(original_path and ', markup maps unchanged' or '')..': PASS')
