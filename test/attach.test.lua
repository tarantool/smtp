#!/usr/bin/env tarantool

local smtp_client = require('smtp').new()
local json = require('json')

local function parse_env()
    local ret = {}
    for argname, argvalue in pairs(os.environ()) do
        argname = string.upper(argname)
        ret[argname] = argvalue
    end
    return ret
end

local args = parse_env()

local response = smtp_client:request(
    args.SMTP_TEST_URL,
    args.SMTP_TEST_FROM,
    args.SMTP_TEST_TO,
    'Test message',
    {
        cc = nil,
        bcc = nil,
        subject = 'Tarantool SMTP connector test',
        headers = nil,
        content_type = nil,
        charset = nil,
        ca_path = nil,
        ca_file = nil,
        verify_host = false,
        verify_peer = false,
        ssl_cert = nil,
        ssl_key = nil,
        use_ssl = 3,
        timeout = 10,
        username = args.SMTP_TEST_USER,
        password = args.SMTP_TEST_PASS,
        verbose = true,
        attachments = {
            {
                body = json.encode('{"key1":"value1"}'),
                content_type = 'application/json',
                charset = 'UTF-8',
                filename = 'json1.json',
                base64_encode = true
            }, {
                body = json.encode('{"key2":"value2"}'),
                content_type = 'application/json',
                filename = 'json2.json',
                base64_encode = false
            }
        }
    }
)

print("status: " .. tostring(response.status) .. ", response message: " ..
          response.reason)
