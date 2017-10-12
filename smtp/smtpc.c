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

#include "smtpc.h"

#include <stdlib.h>

#include <assert.h>
#include <curl/curl.h>

#include <module.h>

int
smtpc_env_create(struct smtpc_env *env)
{
	memset(env, 0, sizeof(*env));
	return 0;
}

void
smtpc_env_destroy(struct smtpc_env *ctx)
{
	(void) ctx;
	assert(ctx);
}

static size_t
smtpc_read_body(void *ptr, size_t size, size_t nmemb, void *userp)
{
	struct smtpc_request *req = (struct smtpc_request *)userp;

	size_t to_read = size * nmemb < req->body_size - (req->body_rpos - req->body) ?
			 size * nmemb : req->body_size - (req->body_rpos - req->body);
	if (to_read < 1)
		return 0;

	memcpy(ptr, req->body_rpos, to_read);
	req->body_rpos += to_read;

	return to_read;
}

struct smtpc_request *
smtpc_request_new(struct smtpc_env *env, const char *url, const char *from)
{
	struct smtpc_request *req = malloc(sizeof(*req));
	if (req == NULL) {
		box_error_set(__FILE__, __LINE__, ER_MEMORY_ISSUE,
			      "Can't alloc smtp request body");
		return NULL;
	}
	memset(req, 0, sizeof(*req));
	req->env = env;

	req->easy = curl_easy_init();
	if (req->easy == NULL) {
		free(req);
		box_error_set(__FILE__, __LINE__, ER_MEMORY_ISSUE,
			      "Can't alloc curl handle");
		return NULL;
	}
	curl_easy_setopt(req->easy, CURLOPT_URL, url);
	curl_easy_setopt(req->easy, CURLOPT_MAIL_FROM, from);

	return req;
}

static long int
smtpc_task_delete(va_list list)
{
	struct smtpc_request *req = va_arg(list, struct smtpc_request *);
	curl_easy_cleanup(req->easy);
	return 0;
}

void
smtpc_request_delete(struct smtpc_request *req)
{
	if (req->easy != NULL)
		coio_call(smtpc_task_delete, req);
	free(req->body);
	if (req->recipients)
		curl_slist_free_all(req->recipients);

	free(req);
}

int
smtpc_set_body(struct smtpc_request *req, const char *body, size_t size)
{
	req->body_rpos = req->body = malloc(size);
	if (req->body == NULL) {
		box_error_set(__FILE__, __LINE__, ER_MEMORY_ISSUE,
			      "Can't alloc smtp request body");
		return -1;
	}
	memcpy(req->body, body, size);
	req->body_size = size;

	return 0;
}

void
smtpc_set_verbose(struct smtpc_request *req, bool curl_verbose)
{
	curl_easy_setopt(req->easy, CURLOPT_VERBOSE, curl_verbose);
}

void
smtpc_set_ca_path(struct smtpc_request *req, const char *ca_path)
{
	curl_easy_setopt(req->easy, CURLOPT_CAPATH, ca_path);
}

void
smtpc_set_ca_file(struct smtpc_request *req, const char *ca_file)
{
	curl_easy_setopt(req->easy, CURLOPT_CAINFO, ca_file);
}

void
smtpc_set_verify_host(struct smtpc_request *req, long verify)
{
	curl_easy_setopt(req->easy, CURLOPT_SSL_VERIFYHOST, verify);
}

void
smtpc_set_verify_peer(struct smtpc_request *req, long verify)
{
	curl_easy_setopt(req->easy, CURLOPT_SSL_VERIFYPEER, verify);
}

void
smtpc_set_ssl_key(struct smtpc_request *req, const char *ssl_key)
{
	curl_easy_setopt(req->easy, CURLOPT_SSLKEY, ssl_key);
}

void
smtpc_set_ssl_cert(struct smtpc_request *req, const char *ssl_cert)
{
	curl_easy_setopt(req->easy, CURLOPT_SSLCERT, ssl_cert);
}

void
smtpc_set_username(struct smtpc_request *req, const char *username)
{
	curl_easy_setopt(req->easy, CURLOPT_USERNAME, username);
}

void
smtpc_set_password(struct smtpc_request *req, const char *password)
{
	curl_easy_setopt(req->easy, CURLOPT_PASSWORD, password);
}

void
smtpc_set_from(struct smtpc_request *req, const char *from)
{
	curl_easy_setopt(req->easy, CURLOPT_MAIL_FROM, from);
}

int
smtpc_add_recipient(struct smtpc_request *req, const char *recipient)
{
	struct curl_slist *l = curl_slist_append(req->recipients, recipient);
	if (l == NULL)
		return -1;
	req->recipients = l;
	return 0;
}

static long int
smtpc_task_execute(va_list list)
{
	struct smtpc_request *req = va_arg(list, struct smtpc_request *);
	req->code = curl_easy_perform(req->easy);
	return 0;
}

int
smtpc_execute(struct smtpc_request *req, double timeout)
{
	struct smtpc_env *env = req->env;

	curl_easy_setopt(req->easy, CURLOPT_PRIVATE,
			 (void *) &req);

	curl_easy_setopt(req->easy, CURLOPT_READFUNCTION,
			 smtpc_read_body);
	curl_easy_setopt(req->easy, CURLOPT_READDATA, req);
	curl_easy_setopt(req->easy, CURLOPT_UPLOAD, 1L);
	curl_easy_setopt(req->easy, CURLOPT_MAIL_RCPT,
			 req->recipients);
	curl_easy_setopt(req->easy, CURLOPT_TIMEOUT, (long)timeout);

	++env->stat.total_requests;
	++env->stat.active_requests;

	if (coio_call(smtpc_task_execute, req) != 0)
		return -1;

	--env->stat.active_requests;

	long longval = 0;
	switch (req->code) {
	case CURLE_OK:
		curl_easy_getinfo(req->easy, CURLINFO_RESPONSE_CODE, &longval);
		req->status = (int) longval;
		req->reason = "Ok";
		break;
	case CURLE_SSL_CACERT:
	case CURLE_PEER_FAILED_VERIFICATION:
		/* SSL Certificate Error */
		req->status = -1;
		req->reason = curl_easy_strerror(req->code);
		++env->stat.failed_requests;
		break;
	case CURLE_OPERATION_TIMEDOUT:
		/* Request Timeout */
		req->status = -1;
		req->reason = curl_easy_strerror(req->code);
		++env->stat.failed_requests;
		break;
	case CURLE_GOT_NOTHING:
		/* No Response */
		req->status = -1;
		req->reason = curl_easy_strerror(req->code);
		++env->stat.failed_requests;
		break;
	case CURLE_COULDNT_RESOLVE_HOST:
	case CURLE_COULDNT_CONNECT:
		/* Connection Problem (AnyEvent non-standard) */
		req->status = -1;
		req->reason = curl_easy_strerror(req->code);
		++env->stat.failed_requests;
		break;
	case CURLE_OUT_OF_MEMORY:
		box_error_set(__FILE__, __LINE__, ER_MEMORY_ISSUE,
			      "Curl internal memory issue");
		++env->stat.failed_requests;
		smtpc_request_delete(req);
		return -1;
	default:
		curl_easy_getinfo(req->easy, CURLINFO_OS_ERRNO, &longval);
		errno = longval ? longval : EINVAL;
		box_error_set(__FILE__, __LINE__, ER_UNKNOWN,
			      "Curl internal issue");
		++env->stat.failed_requests;
		smtpc_request_delete(req);
		return -1;
	}

	return 0;
}
