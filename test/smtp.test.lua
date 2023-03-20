#!/usr/bin/env tarantool

local tap = require('tap')
local test = tap.test("curl")
local smtp = require('smtp')
local fiber = require('fiber')
local socket = require('socket')
local os = require('os')
local log = require('log')

local client = smtp.new()

local SEMVER_RE = '(%d+)%.(%d+)%.(%d+)'

local function curl_version()
    local curl_version_str = smtp._CURL_VERSION
    local major, minor, patch = string.match(curl_version_str, SEMVER_RE)
    return tonumber(major), tonumber(minor), tonumber(patch)
end

-- Whether current curl version is greater or equal to the provided one.
local function is_curl_version_ge(maj, min, patch)
    local cur_maj, cur_min, cur_patch = curl_version()

    if cur_maj < maj then return false end
    if cur_maj > maj then return true end

    if cur_min < min then return false end
    if cur_min > min then return true end

    if cur_patch < patch then return false end
    if cur_patch > patch then return true end

    return true
end

test:diag(string.format('libcurl version: %s', smtp._CURL_VERSION))
test:plan(1)
local mails = fiber.channel(100)

-- {{{ Debugging

-- Wrap socket read/write methods to log data.
local function wrap_socket(s)
    local mt = getmetatable(s)
    if mt.__wrapped then
        return
    end

    local function prettify(s)
        if s == nil then
            return '[nil]'
        end
        assert(type(s) == 'string')
        return s:gsub('\r', '\\r'):gsub('\n', '\\n')
    end

    local saved_read = mt.__index.read
    mt.__index.read = function(self, ...)
        local data = saved_read(self, ...)
        log.info('DEBUG: READ: ' .. prettify(data))
        return data
    end

    local saved_write = mt.__index.write
    mt.__index.write = function(self, ...)
        log.info('DEBUG: WRITE: ' .. prettify((...)))
        return saved_write(self, ...)
    end

    mt.__wrapped = true
end

-- Wrap TCP server handler to log connect/disconnect events and
-- data from read/write.
local function wrap_server_handler(handler)
    if os.getenv('DEBUG') == nil then
        return handler
    end

    return function(s)
        log.info('DEBUG: A CLIENT CONNECTED')
        wrap_socket(s)
        -- Don't handle raised error, we don't do that in the
        -- server mock.
        local message = handler(s)
        log.info('DEBUG: CLOSING CONNECTION')
        return message
    end
end

-- }}} Debugging

local function write_reply_code(s, l)
    if l:find('3xx') then
        s:write('354 Start mail input\r\n')
    elseif l:find('4xx') then
        s:write('421 Service not available, closing transmission channel\r\n')
    elseif l:find('5xx') then
        s:write('510 Bad email address\r\n')
    elseif l:find('breakconnect') then
        return -1
    else
        s:write('250 OK\r\n')
    end
    return 1
end

local function smtp_h(s)
    s:write('220 localhost ESMTP Tarantool\r\n')
    local l
    local mail = {rcpt = {}}
    while true do
        l = s:read('\r\n')
        if l:find('EHLO') then
            s:write('250-localhost Hello localhost.lan [127.0.0.1]\r\n')
            s:write('250-SIZE 52428800\r\n')
            s:write('250-8BITMIME\r\n')
            s:write('250-PIPELINING\r\n')
            s:write('250-CHUNKING\r\n')
            s:write('250-PRDR\r\n')
            s:write('250 HELP\r\n')
        elseif l:find('MAIL FROM:') then
            mail.from = l:sub(11):sub(1, -3)
            if write_reply_code(s, l) == -1 then
                return
            end
        elseif l:find('RCPT TO:') then
            mail.rcpt[#mail.rcpt + 1] = l:sub(9):sub(1, -3)
            if write_reply_code(s, l) == -1 then
                return
            end
        elseif l == 'DATA\r\n' then
            s:write('354 Enter message, ending with "." on a line by itself\r\n')
            while true do
                local l = s:read('\r\n')
                if l == '.\r\n' then
                    break
                end
                mail.text = (mail.text or '') .. l
            end
            mails:put(mail)
            mail = {rcpt = {}}
            s:write('250 OK\r\n')
        elseif l:find('QUIT') then
            return
        elseif l ~= nil then
            s:write('502 Not implemented')
        else
            return
        end
    end
end

local server = socket.tcp_server('127.0.0.1', 0, wrap_server_handler(smtp_h))
local addr = 'smtp://127.0.0.1:' .. server:name().port

test:test("smtp.client", function(test)
    test:plan(26)
    local r
    local m

    r = client:request(addr, 'sender@tarantool.org',
                       'receiver@tarantool.org',
                       'mail.body')
    test:is(r.status, 250, 'simple mail')
    m = mails:get()
    test:is(m.from, '<sender@tarantool.org>', 'sender')
    test:is_deeply(m.rcpt, {'<receiver@tarantool.org>'}, 'rcpt')

    r = client:request(addr, 'sender@tarantool.org',
                       'receiver@tarantool.org',
                       'mail.body',
                       {cc = 'cc@tarantool.org'})
    m = mails:get()
    test:is_deeply(m.rcpt, {'<receiver@tarantool.org>', '<cc@tarantool.org>'}, 'cc rcpt')

    r = client:request(addr, 'sender@tarantool.org',
                       nil,
                       'mail.body',
                       {cc = 'cc@tarantool.org'})
    m = mails:get()
    test:is_deeply(m.rcpt, {'<cc@tarantool.org>'}, 'no rcpt')

    r = client:request(addr, 'sender@tarantool.org',
                       'receiver@tarantool.org',
                       'mail.body',{
                           attachments = {
                            {
                                body = 'Test message',
                                content_type = 'text/plain',
                                filename = 'text.txt',
                            }
                        }})
    m = mails:get()
    local boundaries = select(2, string.gsub(m.text, "MULTIPART%-MIXED%-BOUNDARY", ""))
    local attachment = select(2, string.gsub(m.text, "VGVzdCBtZXNzYWdl", ""))
    test:is(boundaries + attachment, 5, 'attach default')

    r = client:request(addr, 'sender@tarantool.org',
                       'receiver@tarantool.org',
                       'mail.body',{
                           attachments = {
                           {
                               body = 'Test message',
                               content_type = 'text/plain',
                               filename = 'text.txt',
                               base64_encode = false,
                           }
                       }})
    m = mails:get()
    boundaries = select(2, string.gsub(m.text, "MULTIPART%-MIXED%-BOUNDARY", ""))
    attachment = select(2, string.gsub(m.text, "Test message", ""))
    test:is(boundaries + attachment, 5, 'attach plain')

    r = client:request(addr, 'sender@tarantool.org',
                       'receiver@tarantool.org',
                       'mail.body',{
                           attachments = {
                           {
                               body = 'Test message',
                               content_type = 'text/plain',
                               filename = 'text.txt',
                               base64_encode = true,
                           }
                       }})
    m = mails:get()
    boundaries = select(2, string.gsub(m.text, "MULTIPART%-MIXED%-BOUNDARY", ""))
    attachment = select(2, string.gsub(m.text, "VGVzdCBtZXNzYWdl", ""))
    test:is(boundaries + attachment, 5, 'attach base64')

    r = client:request(addr, 'sender@tarantool.org',
                       'receiver@tarantool.org',
                       '', {subject  = 'abcdefghijklmnopqrstuvwxyz'})

    m = mails:get()
    local subj = select(2, string.gsub(m.text, "Subject: abcdefghijklmnopqrstuvwxyz",""))
    test:is(subj, 1, 'subject codes <127')

    r = client:request(addr, 'sender@tarantool.org',
                       'receiver@tarantool.org',
                       '', {subject  = 'abcdefghijkяlmnopqrstuvwxyz'})

    m = mails:get()
    subj = select(2, string.gsub(
                  m.text,
                  "Subject: =%?utf%-8%?b%?YWJjZGVmZ2hpamvRj2xtbm9wcXJzdHV2d3h5eg==%?=", ""))
    test:is(subj, 1, 'subject codes >127')

    r = client:request(addr, '3xx@tarantool.org',
                       'receiver@tarantool.org',
                       'mail.body')
    test:is(r.reason, 'MAIL failed: 354', 'errors 3xx')
    test:is(r.status, 354, 'expected code')

    r = client:request(addr, '4xx@tarantool.org',
                       'receiver@tarantool.org',
                       'mail.body')
    test:is(r.reason, 'MAIL failed: 421', 'service unavailable')
    test:is(r.status, 421, 'expected code')

    r = client:request(addr, '5xx@tarantool.org',
                       'receiver@tarantool.org',
                       'mail.body')
    test:is(r.reason, 'MAIL failed: 510', 'unexisting recipient')
    test:is(r.status, 510, 'expected code')

    r = client:request(addr, 'breakconnect@tarantool.org',
                       'receiver@tarantool.org',
                       'mail.body')
    local expected_reason = 'response reading failed'
    if is_curl_version_ge(7, 86, 0) == true then
        expected_reason = 'response reading failed (errno: <errno>)'
    end
    local reason = r.reason:gsub('errno: [0-9]+', 'errno: <errno>')
    test:is(reason, expected_reason, 'unexpected response code',
            {original_reason = r.reason})
    test:is(r.status, -1, 'expected code')

    r = client:request(addr, 'sender@tarantool.org',
                       '3xx@tarantool.org',
                       'mail.body')
    test:is(r.reason, 'RCPT failed: 354', 'errors 3xx')
    test:is(r.status, 354, 'expected code')

    r = client:request(addr, 'sender@tarantool.org',
                       '4xx@tarantool.org',
                       'mail.body')
    test:is(r.reason, 'RCPT failed: 421', 'service unavailable')
    test:is(r.status, 421, 'expected code')

    r = client:request(addr, 'sender@tarantool.org',
                       '5xx@tarantool.org',
                       'mail.body')
    test:is(r.reason, 'RCPT failed: 510', 'unexisting recipient')
    test:is(r.status, 510, 'expected code')

    r = client:request(addr, 'sender@tarantool.org',
                       'breakconnect@tarantool.org',
                       'mail.body')
    local expected_reason = 'response reading failed'
    if is_curl_version_ge(7, 86, 0) == true then
        expected_reason = 'response reading failed (errno: <errno>)'
    end
    local reason = r.reason:gsub('errno: [0-9]+', 'errno: <errno>')
    test:is(reason, expected_reason, 'unexpected response code',
            {original_reason = r.reason})
    test:is(r.status, -1, 'expected code')

end)
os.exit(test:check() == true and 0 or -1)
