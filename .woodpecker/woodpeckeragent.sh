#!/bin/sh

# PROVIDE: woodpeckeragent
# REQUIRE: LOGIN
# KEYWORD: shutdown
#
# Add the following lines to /etc/rc.conf.local or /etc/rc.conf
# to enable this service:
#
# woodpeckeragent_enable (bool):          Set to NO by default.
#               Set it to YES to enable woodpeckeragent.

. /etc/rc.subr

name=woodpeckeragent
rcvar=woodpeckeragent_enable

load_rc_config $name

: ${woodpeckeragent_enable:="NO"}
: ${woodpeckeragent_token:="foo"}
: ${woodpeckeragent_server:="grpc.ci.codeberg.org"}


pidfile=/var/run/woodpeckeragent.pid
command="/usr/sbin/daemon"
procname="/usr/local/bin/woodpecker-agent"
command_args="-f -p ${pidfile} -T ${name} \
    /usr/bin/env PATH=$PATH:/usr/local/bin ${procname} \
    --server ${woodpeckeragent_server} \
    --grpc-token ${woodpeckeragent_token} \
    --grpc-secure true \
    --agent-config /tmp/woodpecker-agent \
    --log-level debug"

load_rc_config $name
run_rc_command "$1"
