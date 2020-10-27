<a href="http://tarantool.org">
	<img src="https://avatars2.githubusercontent.com/u/2344919?v=2&s=250" align="right">
</a>
<!--
<a href="https://travis-ci.org/tarantool/smtp">
	<img src="https://travis-ci.org/tarantool/smtp.png?branch=master" align="right">
</a>
-->

# SMTP client for Tarantool 1.6+

The `tarantool/smtp` module is for sending email via SMTP with
the [Tarantool](http://https://tarantool.org) application server.

Since Tarantool already has facilities for setting up Internet servers,
and can take advantage of the [libcurl](http://https://curl.haxx.se/libcurl)
library for data transfer via URLs, `tarantool/smtp` simply builds on
functionality that is in the main package.

With Tarantool and `tarantool/smtp`, developers have the routines for
setting up an email client, and the facilities for testing locally before
deploying to the Internet. This may be particularly interesting for developers
who use Tarantool's database, Lua application server, and HTTP features.

## Contents

* [How to install](#how-to-install)
* [The client request function](#the-client-request-function)
* [The server](#the-server)
* [OK, run it](#ok-run-it)
* [Contacts](#contacts)

## How to install

You will need:

* Tarantool 1.6+ with header files (`tarantool` and `tarantool-dev` modules)
* `curl`
* an operating system with developer tools including `cmake`, a C compiler,
  `git` and Lua

You have two ways to install `tarantool/smtp`:

1. The first way is to
   [use the Tarantool Lua rocks repository](https://tarantool.org/en/doc/1.7/book/app_server/installing_module.html#installing-a-module-from-a-repository).

   With Tarantool 1.7.4+, say:

   ```sh
   tarantoolctl rocks install smtp
   ```

   With earlier Tarantool versions, set up Lua rocks and then say:

   ```sh
   luarocks --local install smtp
   ```

2. The second way is to clone from https://github.com/tarantool/smtp, build,
   and use the produced library:

   ```bash
   git clone https://github.com/tarantool/smtp.git smtp
   cd smtp
   cmake . && make
   # and use the library as shown in "Ok, run it" section below
   ```

Whichever way you choose, it is still a good idea to look at the files in the
github.com/tarantool/smtp repository.
There are example files and commented test files, which will aid you in
understanding how `tarantool/smtp` was put together.

[Back to contents](#contents)

## The client request function

There is only one function in the smtp module: `client()`.

It is a tool for handling the job of communicating with the server
at a high level.

Format: *client(url, from, to, body [, options])*

The parameters are:

`url` -- type = string; value = the URL of the SMTP, including the protocol.
Example: `"smtp://127.0.0.1:34324"`.

`from` -- type = string; value = the name of the sender as it would
appear in an email 'From:' line.
Example: `"sender@tarantool.org"`.

`to` -- type = string; value = the name of the recipients as they would
appear in an email 'To:' line.
There can be more than one recipient, defined as an array.
Example: {"receiver_1@tarantool.org", "receiver_2@tarantool.org"}.

`body` -- type = string; value = the contents of the message.
Example: `"Test Message"`.

`options` -- type = table; value = one or more of the following:

* `cc` -- a string or a list to send email copy
* `bcc` -- a string or a list to send a hidden copy
* `subject` -- a subject for the email
* `headers` -- a list of headers (say,
   `{'Message-id: <1567551362.79420629@example.org>', ...}`)
* `content_type` (string) -- set a content type (part of a Content-Type header,
  defaults to 'text/plain')
* `charset` (string) -- set a charset (part of a Content-Type header, defaults
  to 'UTF-8')
* `ca_path` -- path to an ssl certificate directory
* `ca_file` (string) -- path to file containing
  [certificates for verifying the peer](http://curl.haxx.se/libcurl/c/CURLOPT_CAINFO.html)
* `ca_path` (string) -- path to directory containing certificates for
  verifying the peer
* `verify_host` (boolean) -- whether to
  [verify certificate names](http://curl.haxx.se/libcurl/c/CURLOPT_CAINFO.html)
* `verify_peer` (boolean) -- whether to verify
  [the peer's SSL certificate](http://curl.haxx.se/libcurl/c/CURLOPT_SSL_VERIFYPEER.html)
* `ssl_cert` (string) -- path to
  [SSL client certificate](http://curl.haxx.se/libcurl/c/CURLOPT_SSLCERT.html)
* `ssl_key` (string) -- path to
  [private key for TLS and/or SSL client certificate](http://curl.haxx.se/libcurl/c/CURLOPT_SSLKEY.html)
* `use_ssl` -- request using SSL/TLS (1 - preferably, 3 - mandatory)
* `timeout` (number) -- number of seconds to wait for the `libcurl` API
* `verbose` (boolean) -- whether `libcurl` verbose mode is enabled
* `username` (string) -- a username for server authorization
* `password` (string) -- a password for server authorization

Example: `{timeout = 2}`

Example of a complete request:

```lua
response =
client:request("smtp://127.0.0.1:34324",`"sender@tarantool.org"`,`"receiver@tarantool.org"`,"Test
Message",{timeout=2})
```

The response to the request will be a table containing a status (number)
and a reason (string).
Example: `{status: 250, reason: Ok}`
(The standard status code 250 means the request was executed.)

[Back to contents](#contents)

## The server

An SMTP server does not come with `tarantool/smtp`, but `tarantool/smtp` does
supply example code of an SMTP server that can be run on Tarantool --
[tmtp.test.lua](https://github.com/tarantool/smtp/blob/master/test/smtp.test.lua).
We will use some of the code from this example to show that the request function
works correctly.

Before simply presenting the code and saying "OK, run it", we should explain
what it is supposed to handle.

Tarantool has a module named
[socket](https://tarantool.org/doc/1.7/reference/reference_lua/socket.html)
which contains a `tcp_server()` function.
It is possible to make the TCP server run in the background as a
[fiber](https://tarantool.org/doc/1.7/reference/reference_lua/fiber.html).
As is common with client/server action, the example code has a loop that watches
for incoming messages and processes them. In this case, it is processing
according to the standard expected format that goes to an SMTP server, such as
"EHLO", "RCPT FROM", "RCPT TO", and "DATA", which are all
[Simple Mail Transfer Protocol](https://https://en.wikipedia.org/wiki/Simple_Mail_Transfer_Protocol)
commands. When it encounters "DATA", it starts another loop to get all the lines
of the message body.

To make the example simple, it is done on the local host without troubling to
check CA certificates or passwords. The idea is not to compete with Internet
giants like Mail.Ru, but to prove `tarantool/smtp`'s request function calls work
quickly.

[Back to contents](#contents)

## OK, run it

Start Tarantool, run as a console:

```bash
tarantool
```

If you cloned and built the library from source, add the library path to
`package.cpath`, for example:

```lua
-- for Ubuntu
package.cpath = package.cpath .. './smtp/?.so;'
-- for Mac OS
package.cpath = package.cpath .. './smtp/?.dylib;'
```

Execute these requests:

```lua
-- STARTUP

box.cfg{}

fiber = require('fiber')
socket = require('socket')
mails = fiber.channel(100)
```

```lua
-- SERVER CODE

function smtp_h(s)
     s:write('220 localhost ESMTP Tarantool\r\n')
     local l
     local mail = {rcpt = {}}
     while true do
         l = s:read('\r\n')
print(l)
         if l:find('EHLO') then
print(' EHLO')
             s:write('250-localhost Hello localhost.lan [127.0.0.1]\r\n')
             s:write('250-SIZE 52428800\r\n')
             s:write('250-8BITMIME\r\n')
             s:write('250-PIPELINING\r\n')
             s:write('250-CHUNKING\r\n')
             s:write('250-PRDR\r\n')
             s:write('250 HELP\r\n')
         elseif l:find('MAIL FROM:') then
print(' MAIL FROM')
             mail.from = l:sub(11):sub(1, -3)
             s:write('250 OK\r\n')
         elseif l:find('RCPT TO:') then
print(' RCPT TO')
             mail.rcpt[#mail.rcpt + 1] = l:sub(9):sub(1, -3)
             s:write('250 OK\r\n')
         elseif l == 'DATA\r\n' then
print(' DATA')
             s:write('354 Enter message, ending with "." on a line by itself\r\n')
             while true do
                 local l = s:read('\r\n')
print(' DATA: ' .. l)
                 if l == '.\r\n' then
                     break
                 end
                 mail.text = (mail.text or '') .. l
             end
             mails:put(mail)
             mail = {rcpt = {}}
             s:write('250 OK OK OK\r\n')
         elseif l:find('QUIT') then
print(' QUIT')
             return
         elseif l ~= nil then
print(' not implemented')
             s:write('502 Not implemented')
         else
             return
         end
     end
end

server = socket.tcp_server('127.0.0.1', 0, smtp_h)
addr = 'smtp://127.0.0.1:' .. server:name().port
```

```lua
-- TARANTOOL/SMTP REQUEST CODE

client = require('smtp').new()

response = client:request(addr, 'sender@tarantool.org',
     'receiver@tarantool.org',
     'mail.body')
```

Now pause and look at what the server's `print()` requests did: they should show
that the server received EHLO, MAIL FROM, RCPT TO and DATA.

Now look at the response. It should look like this:

```lua
tarantool> response
---
- status: 250
   reason: Ok
...
```

This means the request has been sent and handled. (It does not mean that the
request will pop up on the mailbox of `receiver@tarantool.org`, because this
is done with a local test server, with none of the usual authorization options.)

Once you see that the response is 'Ok', you can switch from being a sender to
being a receiver. Say:

```lua
mails:get()
```

And now the response should look like this:

```lua
tarantool> mails.get()
---
- from: <sender@tarantool.org>
   rcpt:
   - <receiver@tarantool.org>
   text: "TO: receiver@tarantool.org\r\nCC: \r\n\r\nmail.body\r\n"
...

```

If that is what you see, then you have successfully installed `tarantool/smtp`
and successfully executed a request function that sent an email to an SMTP
server, and confirmed it by getting the email back to yourself.

[Back to contents](#contents)

## Contacts

The Tarantool organization at this time includes dozens of developers and
support staffers, so you will have no trouble contacting and getting a response
from an expert.

If you see what you think is a bug, or if you have a feature request, go to
[github.com/tarantool/smtp/issues](https://github.com/tarantool/smtp/issues)
and fill out a description.

If you want to hear more about Tarantool, go to tarantool.org and look for new
announcements about this and other modules.

[Back to contents](#contents)
