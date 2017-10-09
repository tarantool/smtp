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
            s:write('250 OK\r\n')
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

local server = socket.tcp_server('127.0.0.1', 0, smtp_h)
local addr = 'smtp://127.0.0.1:' .. server:name().port

test:test("smtp.client", function(test)
    test:plan(5)
    local r
    local m

    r = client:request(addr, 'sender@tarantool.org',
                       'reciever@tarantool.org',
                       'mail.body')
    test:is(r.status, 250, 'simple mail')
    m = mails:get()
    test:is(m.from, '<sender@tarantool.org>', 'sender')
    test:is_deeply(m.rcpt, {'<reciever@tarantool.org>'}, 'rcpt')

    r = client:request(addr, 'sender@tarantool.org',
                       'reciever@tarantool.org',
                       'mail.body',
                       {cc = 'cc@tarantool.org'})
    m = mails:get()
    test:is_deeply(m.rcpt, {'<reciever@tarantool.org>', '<cc@tarantool.org>'}, 'cc rcpt')

    r = client:request(addr, 'sender@tarantool.org',
                       nil,
                       'mail.body',
                       {cc = 'cc@tarantool.org'})
    m = mails:get()
    test:is_deeply(m.rcpt, {'<cc@tarantool.org>'}, 'no rcpt')

end)

os.exit(test:check() == true and 0 or -1)
