#!/bin/bash
# shellcheck disable=SC2034,2154

# --------------------------------------------------------- terraform inputs ---

HAPROXY_CONFIG_ENCODED=${haproxy_config_encoded}

# ------------------------------------------------------------------- script ---
#
yum install -y haproxy
echo "$HAPROXY_CONFIG_ENCODED" | base64 -d >/etc/haproxy/haproxy.cfg
systemctl enable --now haproxy
