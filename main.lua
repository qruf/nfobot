#! /usr/bin/env lua

local irc = require "ircclient"
local urls = {}
assert(loadfile("urls.lua", "t", urls))()
local cfg = {}
assert(loadfile("cfg.lua", "t", cfg))()

local ssn = irc.create_session()
debug.getmetatable(ssn).__index.msgf = function(self, chan, fmt, ...)
    self:msg(chan, string.format(fmt, ...))
end

local sleep = function(n)
    os.execute("sleep " .. n)
end

local help = function()
    return "Available functions: muxer demuxer encoder decoder filter source sink indev outdev protocol bsf"
end

local filter = function(tbl, match)
    local out = {}
    for k, v in pairs(tbl) do
        if v:find(match, 1, true) then
            out[#out+1] = v
        end
    end
    table.sort(out)
    return out
end

local format = function(tbl)
    local chars, elems = 0
    for i, v in ipairs(tbl) do
        local len = #v
        if chars + len > 300 then
            break
        end
        elems = i
        chars = chars + len
    end
    local mcount = #tbl - elems
    local more = mcount > 0 and string.format("... (%d more)", mcount) or ""
    return table.concat(tbl, ", ", 1, elems) .. more
end

local floodprotect = { list = {}, grep = {} }

local connect = function(s)
    for _, chan in ipairs(cfg.channels) do
        s:join(chan)
    end
end

local responder = function(s, nick, chan, text)
    if not text:match("^!") then
        return
    end
    text = text:gsub("@(%S+)", function(m) nick = m return "" end)
    local args = {}
    for m in text:gmatch("%w+") do
        args[#args+1] = m
    end
    local cmd, name, arg = unpack(args)
    if cmd == "help" then
        return s:msgf(chan, "%s: %s", nick, help())
    end
    if not urls[cmd] then
        return
    end
    name = name:lower()
    if name == "list" then
        if floodprotect[cmd] and floodprotect[cmd] + 30 > os.time() then
            return
        end
        floodprotect[cmd] = os.time()
        return s:msgf(chan, "%s: %s", nick, format(urls[cmd].__list))
    end
    if name == "grep" then
        local list = filter(urls[cmd].__list, arg)
        if #list == 0 then
            return
        end
        if #list > 1 then
            return s:msgf(chan, "%s: %s", nick, format(list))
        end
        name = list[1]
    end
    if not urls[cmd][name] then
        return
    end
    s:msgf(chan, "%s: http://ffmpeg.org/%s%s", nick, urls[cmd].__page, urls[cmd][name])
end

ssn:register("connect", connect)
ssn:register("channel", responder)
ssn:register("privmsg", responder)
ssn:option_set(irc.options.STRIPNICKS)

local delay = 5
repeat
    ssn:connect(cfg)
    local _, err = ssn:run()
    io.stderr:write("Disconnected, reconnecting in ", delay, " seconds...\n")
    ssn:disconnect()
    sleep(delay)
    delay = math.min(60, delay + 5)
until err ~= irc.errors.TERMINATED and err ~= irc.errors.CONNECT
io.stderr:write("Disconnected: ", irc.errors[err], "\n")
