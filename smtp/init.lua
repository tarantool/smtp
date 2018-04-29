--
--  Copyright (C) 2016-2017 Tarantool AUTHORS: please see AUTHORS file.
--
--  Redistribution and use in source and binary forms, with or
--  without modification, are permitted provided that the following
--  conditions are met:
--
--  1. Redistributions of source code must retain the above
--   copyright notice, this list of conditions and the
--   following disclaimer.
--
--  2. Redistributions in binary form must reproduce the above
--   copyright notice, this list of conditions and the following
--   disclaimer in the documentation and/or other materials
--   provided with the distribution.
--
--  THIS SOFTWARE IS PROVIDED BY <COPYRIGHT HOLDER> ``AS IS'' AND
--  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
--  TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
--  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
--  <COPYRIGHT HOLDER> OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
--  INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
--  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
--  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
--  BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
--  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
--  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
--  THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
--  SUCH DAMAGE.
--

local fiber = require('fiber')
local driver = require('smtp.lib')

local curl_mt

--
--  <smtp> - create a new curl instance.
--
--  Parameters:
--
--  max_connectionss -  Maximum number of entries in the connection cache */
--
--  Returns:
--  curl object or raise error()
--

local smtp_new = function(opts)

    opts = opts or {}

    opts.max_connections = opts.max_connections or 5

    local curl = driver.new(opts.max_connections)
    return setmetatable({ curl = curl, }, curl_mt )
end

local check_args_fmt = 'Use client:%s(...) instead of client.%s(...):'

local function check_args(self, method)
    if type(self) ~= 'table' then
        error(check_args_fmt:format(method, method), 2)
    end
end

--
--  <request> This function does SMTP request
--
--  Parameters:
--
--  url     - smtp url, like smtps://imap.tarantool.org
--  from    - email sender
--  to      - email recipients
--  body    - this parameter is optional, you may use it for passing
--  options - this is a table of options.
--      cc      - a list to send email copy;
--
--      bcc     - a list to send a hidden copy;
--
--      subject - a subject for the email;
--
--      headers - a list of header;
--
--      ca_path - a path to ssl certificate dir;
--
--      ca_file - a path to ssl certificate file;
--
--      verify_host - set on/off verification of the certificate's name (CN)
--          against host;
--
--      verify_peer - set on/off verification of the peer's SSL certificate;
--
--      ssl_key - set path to the file with private key for TLS and SSL client
--          certificate;
--
--      ssl_cert - set path to the file with SSL client certificate;
--
--      use_ssl - request using SSL/TLS (1 - preferably, 3 - mandatory);
--
--      timeout - Time-out the read operation and
--          waiting for the curl api request
--          after this amount of seconds;
--
--      verbose - set on/off verbose mode
--
--  Returns:
--      {
--          status=NUMBER,
--          reason=ERRMSG
--      }
--
--  Raises error() on invalid arguments and OOM
--

local function add_recipients(list, recipients)
    if recipients == nil then
        return ''
    end
    if type(recipients) ~= 'table' then
        recipients = {recipients}
    end
    for _, r in pairs(recipients) do
        list[#list + 1] = r
    end
    return table.concat(recipients, ', ')
end

-- TODO: parse according to [3.4. Address Specification][1], correctly
-- distinguish name-addr and addr-spec cases, handle group case, mailbox-list
-- and address-list cases.
--
-- [1]: https://tools.ietf.org/html/rfc2822#section-3.4
local function addr_spec(mailbox)
    return mailbox:match('^.*[ \t]*<(.-)>[ \t]*$') or mailbox
end

curl_mt = {
    __index = {
        --
        --  <request> see above <request>
        --
        request = function(self, url, from, to, body, opts)
            opts = opts or {}
            to = to or {}
            if not body or not url or not from then
                error('request(url, from, to, body [, options]])')
            end
            local header = ''
            local recipients = {}
            header = 'From: ' .. from .. '\r\n' ..
                     'To: ' .. add_recipients(recipients, to) .. '\r\n'
            if opts.cc then
                header = header .. 'Cc: ' .. add_recipients(recipients, opts.cc) .. '\r\n'
            end
            add_recipients(recipients, opts.bcc)
            if opts.headers and #opts.headers > 0 then
                header = header .. table.concat(opts.headers, '\r\n') .. '\r\n'
            end

            local content_type = opts.content_type or 'text/plain'
            local charset = opts.charset or 'UTF-8'
            header = header .. 'Content-Type: ' .. content_type .. '; charset=' .. charset .. '\r\n'

            if opts.subject then
                header = header .. 'Subject: ' .. opts.subject .. '\r\n'
            end

            body = header .. '\r\n' .. body
            local from_addr = addr_spec(from)
            local recipients_addr = {}
            for _, recipient in ipairs(recipients) do
                recipients_addr[#recipients_addr + 1] = addr_spec(recipient)
            end
            local resp = self.curl:request(url, from_addr, recipients_addr, body, opts or {})
            return resp
        end,

        --
        -- <stat> - this function returns a table with many values of statistic.
        --
        -- Returns {
        --
        --  active_requests - this is number of currently executing requests
        --
        --  total_requests - this is a total number of requests
        --
        --  failed_requests - this is a total number of requests which have
        --      failed (included systeme erros, curl errors, SMTP
        --      errors and so on)
        --  }
        --  or error()
        --
        stat = function(self)
            return self.curl:stat()
        end,

    },
}

--
-- Export
--
local smtp_default = smtp_new()
local this_module = { new = smtp_new, }

package.loaded['smtp.client'] = this_module
return this_module
-- vim: ts=4 sts=4 sw=4 et
