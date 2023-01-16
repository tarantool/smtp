#ifndef TARANTOOL_SMTPC_H_INCLUDED
#define TARANTOOL_SMTPC_H_INCLUDED 1
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
#include <stdint.h>
#include <stdbool.h>

#include <curl/curl.h>

/* {{{ Subsystem initialization */

/**
 * Initialize the subsystem.
 *
 * Perform libcurl symbols resolving.
 *
 * Return 0 on success. Otherwise return -1 and set an error into
 * the diagnostics area.
 */
int
smtpc_init(void);

/* Subsystem initialization }}} */

/** {{{ Environment */

typedef void CURLM;
typedef void CURL;
struct curl_slist;

/**
 * SMTP Client Statistics
 */
struct smtpc_stat {
	uint64_t active_requests;
	uint64_t total_requests;
	uint64_t failed_requests;
};

/**
 * SMTP Client Environment
 */
struct smtpc_env {
	/** Statistics */
	struct smtpc_stat stat;
};

/**
 * @brief Creates  new SMTP client environment
 * @param env pointer to a structure to initialize
 * @param max_conn The maximum number of entries in connection cache
 * @retval 0 on success
 * @retval -1 on error, check diag
 */
int
smtpc_env_create(struct smtpc_env *ctx);

/**
 * Destroy SMTP client environment
 * @param env pointer to a structure to destroy
 */
void
smtpc_env_destroy(struct smtpc_env *env);

/** Environment }}} */

/** {{{ Request */

/**
 * SMTP request
 */
struct smtpc_request {
	/** Environment. */
	struct smtpc_env *env;
	/** Curl easy handle. */
	CURL *easy;
	/** Internal libcurl status code. */
	int code;
	/** Recipients. */
	struct curl_slist *recipients;
	/** Buffer for the mail body. */
	char *body;
	/** Body size. */
	int body_size;
	/** Buffer read position. */
	char *body_rpos;
	/**
	 * SMTP status code.
	 * It takes the value of -1 if there is some problem,
	 * which is not related to SMTP, like connection error.
	 */
	int status;
	/**
	 * Error message.
	 * It is a string to report details of an error to a user.
	 * Does not require freeing.
	 * It is never NULL if smtpc_execute() returns zero.
	 */
	const char *reason;
	/**
	 * Error buffer for receiving messages.
	 * It should exist during a request lifetime and
	 * must be freed at freeing the request structure.
	 * This field is not for reading directly, cause
	 * reason field points to it, when appropriate.
	 */
	char *error_buf;
};

/**
 * @brief Create a new SMTP request
 * @param ctx - reference to context
 * @return a new SMTP request object
 */
struct smtpc_request *
smtpc_request_new(struct smtpc_env *env, const char *url, const char *from);

/**
 * @brief Delete SMTP request
 * @param request - reference to object
 * @details Should be called even if error in execute appeared
 */
void
smtpc_request_delete(struct smtpc_request *req);

/**
 * @brief Add recipient to the request
 * @param req - reference to object
 * @param @recipient - a mail recipient
 * @retval 0 on success
 * @retval -1 on error
 */
int
smtpc_add_recipient(struct smtpc_request *req, const char *recipient);

/**
 * Sets body of request
 * @param req request
 * @param body body
 * @param bytes sizeof body
 * @retval 0 on success
 * @retval -1 on error, check diag
 */
int
smtpc_set_body(struct smtpc_request *req, const char *body, size_t size);

void
smtpc_set_username(struct smtpc_request *req, const char *username);

void
smtpc_set_password(struct smtpc_request *req, const char *password);

/**
 * Enables/Disables libcurl verbose mode
 * @param req request
 * @param verbose flag
 */
void
smtpc_set_verbose(struct smtpc_request *req, bool verbose);

/**
 * Specify directory holding CA certificates
 * @param req request
 * @param ca_path path to directory holding one or more certificates
 * to verify the peer with. The application does not have to keep the string
 * around after setting this option.
 */
void
smtpc_set_ca_path(struct smtpc_request *req, const char *ca_path);

/**
 * Specify path to Certificate Authority (CA) bundle
 * @param req request
 * @param ca_file - File holding one or more certificates
 * to verify the peer with. The application does not have to keep the string
 * around after setting this option.
 * @see https://curl.haxx.se/libcurl/c/CURLOPT_CAINFO.html
 */
void
smtpc_set_ca_file(struct smtpc_request *req, const char *ca_file);

/**
 * Enables/disables verification of the certificate's name (CN) against host
 * @param req request
 * @param verify flag
 * @see https://curl.haxx.se/libcurl/c/CURLOPT_SSL_VERIFYHOST.html
 */
void
smtpc_set_verify_host(struct smtpc_request *req, long verify);

/**
 * Enables/disables verification of the peer's SSL certificate
 * @param req request
 * @param verify flag
 * @see https://curl.haxx.se/libcurl/c/CURLOPT_SSL_VERIFYPEER.html
 */
void
smtpc_set_verify_peer(struct smtpc_request *req, long verify);

/**
 * Specify path to private key for TLS ans SSL client certificate
 * @param req request
 * @param ssl_key - path to the private key. The application does not have to
 * keep the string around after setting this option.
 * @see https://curl.haxx.se/libcurl/c/CURLOPT_SSLKEY.html
 */
void
smtpc_set_ssl_key(struct smtpc_request *req, const char *ssl_key);

/**
 * Specify path to SSL client certificate
 * @param req request
 * @param ssl_cert - path to the client certificate. The application does not
 * have to keep the string around after setting this option.
 * @see https://curl.haxx.se/libcurl/c/CURLOPT_SSLCERT.html
 */
void
smtpc_set_ssl_cert(struct smtpc_request *req, const char *ssl_cert);

/**
 * Request using SSL/TLS. STARTTLS is used as preferable / as mandatory
 * depending of this option is case when a connection uses plain text
 * initially. Typically plain text / STARTTLS (explicit TLS) used on 587 port
 * and SMTPS (implicit TLS) on 487 port.
 * @param req request
 * @param use_ssl - whether SSL / TLS is preferable / mandatory:
 * * 0: CURLUSESSL_NONE - don't attempt to use SSL (this is default).
 * * 1: CURLUSESSL_TRY - try using SSL, proceed as normal otherwise.
 * * 2 or 3: CURLUSESSL_CONTROL or CURLUSESSL_ALL - require SSL.
 * @see https://curl.haxx.se/libcurl/c/CURLOPT_USE_SSL.html
 */
void
smtpc_set_use_ssl(struct smtpc_request *req, long use_ssl);

/**
 * This function does async SMTP request
 * @param request - reference to request object with filled fields
 * @param timeout - timeout of waiting for libcurl api
 * @return 0 for success or NULL
 */
int
smtpc_execute(struct smtpc_request *req, double timeout);

/** Request }}} */

/* {{{ Version */

/**
 * Get a Curl library version.
 *
 * @see https://curl.se/libcurl/c/curl_version_info.html
 */
void
smtpc_get_curl_version(unsigned int *major, unsigned int *minor, unsigned int *patch);

/* Version }}} */

#endif /* TARANTOOL_SMTPC_H_INCLUDED */
