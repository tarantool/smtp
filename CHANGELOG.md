# Changelog

## Unreleased

## 0.0.7

## New features

* Added `_VERSION` field with the module version and `_CURL_VERSION` with the
  libcurl library version (PR #72, PR #71).

## Bugfixes

* Improved libcurl dynamic library search (#44, PR #51)
* Improved handling and reporting of 3xx, 4xx and 5xx responses (#13, PR #53).
* Eliminated a memleak after a failed request (#55, PR #63).
* Adjust error handling code to support libcurl 7.86.0+ (#70, PR #71, PR #75).
* Fixed signed integer overflow in the client statistics (PR #73).

## Testing

* Added debug prints for the SMTP server mock (PR #58).

## Infrastructure

* Upload a source rock to the rockserver (PR #41).
* Resolved Mac OS specific CI problems (PR #43), (#49, PR #52, PR #56).
* Build and verify RPM/Deb packages, update distributions list (#34, PR #42).
* Added an entrypoint for tarantool's integration testing (PR #48).
* Use `git+https://` in the rockspec (PR #50).
* Use setup-tarantool GitHub Action to speed up testing on Linux (PR #59).
* Added tarantool 2.10.0 into CI (#49, PR #59).
* Eliminated a problem with stale Ubuntu repository metadata (PR #62).
* Use vault.centos.org mirror for CentOS 8 (#60, PR #61).
* Removed macOS 10.15 from CI (PR #65).
* Added macOS 12 to CI (PR #66).
* Added tarantool 2.10.0 into macOS testing (7c5c7da56a8b).
* Added package testing for Ubuntu Jammy and Fedora 35, 36 (PR #68).
* Switched to node16 runtime in CI (PR #69).
