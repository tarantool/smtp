#!/usr/bin/env tarantool

local tap = require('tap')
local client = require('smtp').new()
local test = tap.test("curl")
local fiber = require('fiber')
local socket = require('socket')
local os = require('os')

test:plan(1)
mails = fiber.channel(100)

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
            s:write('250 OK\r\n')
        elseif l:find('RCPT TO:') then
            mail.rcpt[#mail.rcpt + 1] = l:sub(9):sub(1, -3)
            if l:find('3xx') then
                s:write('354 Start mail input\r\n')
            elseif l:find('4xx') then
                s:write('421 Service not available, closing transmission channel\r\n')
            elseif l:find('5xx') then
                s:write('510 Bad email address\r\n')
            elseif l:find('10xx') then
                s:write('1000 Some unexpected error\r\n')
                return
            elseif l:find('timeout') then
                s:write('1000 timeout error\r\n')
            else
                s:write('250 OK\r\n')
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
            return
        else
            return
        end
    end
end

local server = socket.tcp_server('127.0.0.1', 0, smtp_h)
local addr = 'smtp://127.0.0.1:' .. server:name().port

test:test("smtp.client", function(test)
    test:plan(15)
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

    r = client:request(addr, 'sender@tarantool.org',
                       '3xx@tarantool.org',
                       'mail.body')
    test:is(r.reason, 'RCPT failed: 354', 'Errors 3xx')

    r = client:request(addr, 'sender@tarantool.org',
            '4xx@tarantool.org',
            'mail.body')
    test:is(r.reason, 'RCPT failed: 421', 'service unavailable')

    r = client:request(addr, 'sender@tarantool.org',
            '5xx@tarantool.org',
            'mail.body')
    test:is(r.reason, 'RCPT failed: 510', 'unexisting recipient')

    r = client:request(addr, 'sender@tarantool.org',
            '10xx@tarantool.org',
            'mail.body')
    test:is(r.reason, 'response reading failed', 'unexpected error - disconnect')

    r = client:request(addr, 'sender@tarantool.org',
            'timeout@tarantool.org',
            'mail.body', {timeout = 1})
    test:is(r.reason, 'Timeout was reached', 'timeout')
end)

os.exit(test:check() == true and 0 or -1)
