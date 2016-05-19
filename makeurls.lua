local html = require "htmlparser"

local fetch = function(base, url)
    local ok = os.execute("wget -P cache/ --no-use-server-timestamps --no-if-modified -N http://ffmpeg.org/" .. url)
    if not ok then
        return nil, ok
    end
    local f, err = io.open("cache/" .. url)
    if not f then
        return nil, err
    end
    local out = f:read("*a")
    f:close()
    return out
end

local out = {}

local makelist = function(url, sections)
    local page, err = fetch("http://ffmpeg.org", url)
    if not page then
        io.stderr:write("error fetching page: ", url, ": ", err, "\n")
        return
    end
    local root = html.parse(page)
    local toc = root:select("div.contents a")
    for k, v in ipairs(toc) do
        local content = v:getcontent()
        local section = sections[tonumber(content:match("^(%d+)%.%d+ "))]
        if section then
            out[section] = out[section] or {}
            for m in content:gmatch(setfenv and "%w+%f[,%z]" or "%w+%f[,\0]") do
                out[section][m:lower()] = v.attributes.href
            end
        end
    end
    for _, section in pairs(sections) do
        local list = {}
        for k in pairs(out[section]) do
            if not k:match("^__") then
                list[#list+1] = string.format("%q", k)
            end
        end
        table.sort(list)
        out[section].__list = list
        out[section].__page = url
    end
end

makelist("ffmpeg-filters.html", { [6] = "filter", [7] = "source", [8] = "sink", [9] = "filter", [10] = "source", [11] = "sink", [12] = "filter", [13] = "source" })
makelist("ffmpeg-devices.html", { [3] = "indev", [4] = "outdev" })
makelist("ffmpeg-protocols.html", { [3] = "protocol" })
makelist("ffmpeg-formats.html", { [3] = "demuxer", [4] = "muxer" })
makelist("ffmpeg-bitstream-filters.html", { [2] = "bsf" })
makelist("ffmpeg-codecs.html", { [4] = "decoder", [5] = "decoder", [6] = "decoder", [8] = "encoder", [9] = "encoder", [10] = "encoder" })

local write = function(file, name, tbl)
    file:write(name, " = {\n")
    for k, v in pairs(tbl) do
        file:write(string.format("\t[%q] = ", k))
        if type(v) == "table" then
            file:write("{ ", table.concat(v, ", "), " },\n")
        else
            file:write(string.format("%q,\n", v))
        end
    end
    file:write("}\n")
end

local tmp = os.tmpname()
local f = io.open(tmp, "w")
for k, v in pairs(out) do
    write(f, k, v)
end
f:close()
os.rename(tmp, "urls.lua")
