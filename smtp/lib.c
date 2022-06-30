/*
 * Copyright 2010-2017, Tarantool AUTHORS, please see AUTHORS file.
 *
 * Redistribution and use in source and binary forms, with or
 * without modification, are permitted provided that the following
 * conditions are met:
 *
 * 1. Redistributions of source code must retain the above
 *    copyright notice, this list of conditions and the
 *    following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above
 *    copyright notice, this list of conditions and the following
 *    disclaimer in the documentation and/or other materials
 *    provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY AUTHORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 * AUTHORS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
 * BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
 * THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

/**
 * Unique name for userdata metatables
 */
#define DRIVER_LUA_UDATA_NAME	"smtpc"

#include <lua.h>
#include <lauxlib.h>

#include "module.h"
#include "smtpc.h"

/** Internal util functions
 * {{{
 */

static inline struct smtpc_env*
luaT_smtpc_checkenv(lua_State *L)
{
	return (struct smtpc_env *)
			luaL_checkudata(L, 1, DRIVER_LUA_UDATA_NAME);
}

static inline void
lua_add_key_u64(lua_State *L, const char *key, uint64_t value)
{
	lua_pushstring(L, key);
	lua_pushinteger(L, value);
	lua_settable(L, -3);
}
/* }}}
 */

/** lib Lua API {{{
 */

static int
luaT_smtpc_request(lua_State *L)
{
	struct smtpc_env *ctx = luaT_smtpc_checkenv(L);
	if (ctx == NULL)
		return luaL_error(L, "can't get smtpc environment");

	const char *url = luaL_checkstring(L, 2);
	const char *from = luaL_checkstring(L, 3);

	struct smtpc_request *req = smtpc_request_new(ctx, url, from);
	if (req == NULL)
		return luaT_error(L);

	double timeout = 365 * 24 * 3600;

	if (!lua_istable(L, 4)) {
		smtpc_request_delete(req);
		return luaL_error(L, "fifth argument must be a table");
	}
	lua_pushnil(L);
	while (lua_next(L, 4) != 0) {
		smtpc_add_recipient(req, lua_tostring(L, -1));
		lua_pop(L, 1);
	}

	if (lua_isstring(L, 5)) {
		size_t len = 0;
		const char *body = lua_tolstring(L, 5, &len);
		if (len > 0 && smtpc_set_body(req, body, len) != 0) {
			smtpc_request_delete(req);
			return luaT_error(L);
		}
	} else if (!lua_isnil(L, 5)) {
		smtpc_request_delete(req);
		return luaL_error(L, "fourth argument must be a string");
	}

	if (!lua_istable(L, 6)) {
		smtpc_request_delete(req);
		return luaL_error(L, "fifth argument must be a table");
	}

	lua_getfield(L, 6, "ca_path");
	if (!lua_isnil(L, -1))
		smtpc_set_ca_path(req, lua_tostring(L, -1));
	lua_pop(L, 1);

	lua_getfield(L, 6, "ca_file");
	if (!lua_isnil(L, -1))
		smtpc_set_ca_file(req, lua_tostring(L, -1));
	lua_pop(L, 1);

	lua_getfield(L, 6, "verify_host");
	if (!lua_isnil(L, -1))
		smtpc_set_verify_host(req, lua_toboolean(L, -1) == 1 ? 2 : 0);
	lua_pop(L, 1);

	lua_getfield(L, 6, "verify_peer");
	if (!lua_isnil(L, -1))
		smtpc_set_verify_peer(req, lua_toboolean(L, -1));
	lua_pop(L, 1);

	lua_getfield(L, 6, "ssl_key");
	if (!lua_isnil(L, -1))
		smtpc_set_ssl_key(req, lua_tostring(L, -1));
	lua_pop(L, 1);

	lua_getfield(L, 6, "ssl_cert");
	if (!lua_isnil(L, -1))
		smtpc_set_ssl_cert(req, lua_tostring(L, -1));
	lua_pop(L, 1);

	lua_getfield(L, 6, "use_ssl");
	if (!lua_isnil(L, -1)) {
		if (!lua_isnumber(L, -1)) {
			smtpc_request_delete(req);
			return luaL_error(L, "use_ssl option must be a number");
		}
		long use_ssl_in = lua_tonumber(L, -1);
		long use_ssl_curl = 0;
		switch (use_ssl_in) {
		case 0:
			use_ssl_curl = CURLUSESSL_NONE;
			break;
		case 1:
			use_ssl_curl = CURLUSESSL_TRY;
			break;
		case 2:
			use_ssl_curl = CURLUSESSL_CONTROL;
			break;
		case 3:
			use_ssl_curl = CURLUSESSL_ALL;
			break;
		default:
			smtpc_request_delete(req);
			return luaL_error(
				L, "use_ssl option must be >= 0 and <= 3");
		}
		smtpc_set_use_ssl(req, use_ssl_curl);
	}
	lua_pop(L, 1);

	lua_getfield(L, 6, "timeout");
	if (!lua_isnil(L, -1))
		timeout = lua_tonumber(L, -1);
	lua_pop(L, 1);

	lua_getfield(L, 6, "verbose");
	if (!lua_isnil(L, -1) && lua_isboolean(L, -1))
		smtpc_set_verbose(req, lua_toboolean(L, -1));
	lua_pop(L, 1);

	lua_getfield(L, 6, "username");
	if (!lua_isnil(L, -1))
		smtpc_set_username(req, lua_tostring(L, -1));
	lua_pop(L, 1);

	lua_getfield(L, 6, "password");
	if (!lua_isnil(L, -1))
		smtpc_set_password(req, lua_tostring(L, -1));
	lua_pop(L, 1);

	if (smtpc_execute(req, timeout) != 0) {
		smtpc_request_delete(req);
		return luaT_error(L);
	}

	lua_newtable(L);

	lua_pushstring(L, "status");
	lua_pushinteger(L, req->status);
	lua_settable(L, -3);

	lua_pushstring(L, "reason");
	lua_pushstring(L, req->reason);
	lua_settable(L, -3);

	/* clean up */
	smtpc_request_delete(req);
	return 1;
}

static int
luaT_smtpc_stat(lua_State *L)
{
	struct smtpc_env *ctx = luaT_smtpc_checkenv(L);
	if (ctx == NULL)
		return luaL_error(L, "can't get smtpc environment");

	lua_newtable(L);
	lua_add_key_u64(L, "active_requests",
			(uint64_t) ctx->stat.active_requests);
	lua_add_key_u64(L, "total_requests",
			ctx->stat.total_requests);
	lua_add_key_u64(L, "failed_requests",
			ctx->stat.failed_requests);
	return 1;
}

static int
luaT_smtpc_new(lua_State *L)
{
	struct smtpc_env *ctx = (struct smtpc_env *)
			lua_newuserdata(L, sizeof(struct smtpc_env));
	if (ctx == NULL)
		return luaL_error(L, "lua_newuserdata failed: smtpc_env");

	if (smtpc_env_create(ctx) != 0)
		return luaT_error(L);

	luaL_getmetatable(L, DRIVER_LUA_UDATA_NAME);
	lua_setmetatable(L, -2);

	return 1;
}

static int
luaT_smtpc_cleanup(lua_State *L)
{
	smtpc_env_destroy(luaT_smtpc_checkenv(L));

	/** remove all methods operating on ctx */
	lua_newtable(L);
	lua_setmetatable(L, -2);

	lua_pushboolean(L, true);
	lua_pushinteger(L, 0);
	return 2;
}

/*
 * }}}
 */

/*
 * Lists of exporting: object and/or functions to the Lua
 */

static const struct luaL_Reg Module[] = {
	{"new", luaT_smtpc_new},
	{NULL, NULL}
};

static const struct luaL_Reg Client[] = {
	{"request", luaT_smtpc_request},
	{"stat", luaT_smtpc_stat},
	{"__gc", luaT_smtpc_cleanup},
	{NULL, NULL}
};

/*
 * Lib initializer
 */
LUA_API int
luaopen_smtp_lib(lua_State *L)
{
	if (smtpc_init() != 0)
		return luaT_error(L);

	luaL_newmetatable(L, DRIVER_LUA_UDATA_NAME);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pushstring(L, DRIVER_LUA_UDATA_NAME);
	lua_setfield(L, -2, "__metatable");
	luaL_register(L, NULL, Client);
	lua_pop(L, 1);
	luaL_register(L, "smtp.client.driver", Module);
	return 1;
}

/* vim: syntax=c ts=8 sts=8 sw=8 noet */
