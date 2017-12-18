<a href="http://tarantool.org">
	<img src="https://avatars2.githubusercontent.com/u/2344919?v=2&s=250" align="right">
</a>
<a href="https://travis-ci.org/tarantool/modulekit">
	<img src="https://travis-ci.org/tarantool/modulekit.png?branch=ckit" align="right">
</a>

# SMTP client tarantool module

Use this module to send emails  over a smtp server.

## Table of contents
* [Prerequisites](#prerequisites)
* [Examples](#examples)

## Prerequisites

Tarantool 1.6.5+ with header files (`tarantool`, `tarantool-dev` packages)
Curl library

## Usage

```lua
local client = require('smtp').new()
r = client:request(addr, 'sender@tarantool.org',
                   'receiver@tarantool.org',
                   'mail.body',
                   {cc = 'cc@tarantool.org',
                    timeout = 2})
```
