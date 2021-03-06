#!/bin/sh
#
# Copyright 2017 The Kubernetes Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

init() {
    if [ $# -gt 0 ] && [ "${1:0:2}" != "--" ]; then
        exec "$@"
        exit 0
    fi
    if [ "${1%%=*}" = "--reload-strategy" ]; then
        HA_RELOAD_STRATEGY="${1#*=}"
        shift
    else
        HA_RELOAD_STRATEGY=native
    fi
    case "$HA_RELOAD_STRATEGY" in
        native)
            ;;
        multibinder)
            HAPROXY=/usr/local/sbin/haproxy
            TEMPLATE=/etc/haproxy/template/haproxy.tmpl
            CONFIG=/etc/haproxy/haproxy.cfg.erb
            WRAPPER_PID=/var/run/wrapper.pid
            HAPROXY_PID=/var/run/haproxy.pid
            create_erb
            start_multibinder
            ;;
        *)
            echo "Unsupported reload strategy: $HA_RELOAD_STRATEGY"
            ;;
    esac
    export HA_RELOAD_STRATEGY
    exec /haproxy-ingress-controller "$@"
}

create_erb() {
    # Create a minimal valid starting configuration file
    cat > "$CONFIG" <<EOF
global
    daemon
listen main
    bind unix@/var/run/haproxy-tmp.sock
    timeout client 1s
    timeout connect 1s
    timeout server 1s
EOF

    # Add erb code to a new template file
    sed "/^    bind \+\*\?:/s/\*\?:\(.*\)/<%= bind_tcp('0.0.0.0', \1) %>/" \
        "$TEMPLATE" > "${CONFIG}.tmpl"
}

start_multibinder() {
    # Start multibinder
    export MULTIBINDER_SOCK=/run/multibinder.sock
    multibinder "$MULTIBINDER_SOCK" &
    multibinder_pid=$!

    # Wait for socket
    while [ ! -S "$MULTIBINDER_SOCK" ]; do
        sleep 1
    done

    # Create initial config
    multibinder-haproxy-erb "$HAPROXY" -f "$CONFIG" -c -q

    # Start HAProxy
    multibinder-haproxy-wrapper "$HAPROXY" -Ds -f "$CONFIG" -p "$HAPROXY_PID" &
    wrapper_pid=$!
    echo $wrapper_pid > "$WRAPPER_PID"
}

init "$@"
