curl -LsSf https://www.tarantool.io/release/2.11/installer.sh | sudo bash

# Workaround https://github.com/tarantool/installer.sh/issues/10
printf '%s\n' 'Package: tarantool-dev'             | sudo tee    /etc/apt/preferences.d/tarantool-dev
printf '%s\n' 'Pin: origin download.tarantool.org' | sudo tee -a /etc/apt/preferences.d/tarantool-dev
printf '%s\n' 'Pin-Priority: 1001'                 | sudo tee -a /etc/apt/preferences.d/tarantool-dev
