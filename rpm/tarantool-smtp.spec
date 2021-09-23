Name: tarantool-smtp
Version: 1.0.0
Release: 1%{?dist}
Summary: SMTP client module for Tarantool
Group: Applications/Databases
License: BSD
URL: https://github.com/tarantool/smtp
Source0: smtp-%{version}.tar.gz
BuildRequires: cmake >= 2.8
BuildRequires: gcc >= 4.5
BuildRequires: tarantool-devel >= 1.6.8.0
BuildRequires: curl-devel
BuildRequires: /usr/bin/prove
Requires: tarantool >= 1.6.8.0
Requires: curl

%description
This package provides SMTP client module for Tarantool.

%prep
%setup -q -n %{name}-%{version}

%build
%cmake -B . -DCMAKE_BUILD_TYPE=RelWithDebInfo
make %{?_smp_mflags}

%check
make %{?_smp_mflags} check

%install
%make_install

%files
%{_libdir}/tarantool/*/
%{_datarootdir}/tarantool/*/
%doc README.md
%{!?_licensedir:%global license %doc}
%license LICENSE AUTHORS

%changelog
* Mon Oct 09 2017 Georgy Kirichenko <georgy@tarantool.org> 1.0.0-1
- Initial commit.
