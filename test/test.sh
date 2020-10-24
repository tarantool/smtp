#/bin/bash

SMTP_TEST_URL='smtps://smtp.example.com:465' \
SMTP_TEST_FROM='from@example.com' \
SMTP_TEST_TO='to@example.com' \
SMTP_TEST_USER='from@example.com' \
SMTP_TEST_PASS='secret' \
tarantool test/attach.test.lua
