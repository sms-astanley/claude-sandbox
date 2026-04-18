#!/bin/bash
# Wrapper for gsd-sdk that adds the `query` subcommand.
#
# The published @gsd-build/sdk provides run/auto/init but not the
# `query X.Y <args>` interface get-shit-done-cc agents call. Route those
# to the bundled gsd-tools.cjs, which implements the handlers as
# `<subsystem> <action>` (dot → space). Pass everything else through.

if [ "$1" = "query" ]; then
    shift
    HANDLER="$1"
    shift
    exec node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" ${HANDLER/./ } "$@"
fi

exec /usr/local/bin/gsd-sdk-real "$@"
