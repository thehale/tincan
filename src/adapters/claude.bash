# Copyright (c) 2026 Joseph Hale
# SPDX-License-Identifier: MPL-2.0
#
# shellcheck shell=bash

claude() {
	local session="${2:?Usage: tincan --as <name> relay claude <claude-pid>}"
	local since lock
	since="$(parse_time now)"
	pickup "$1"
	exec {lock}>"$TINCAN_DIR/$1.$session.relay"
	if flock -n "$lock"; then
		forward "$1" "$session" "$since"
	fi
}

forward() {
	replay "$1" "$3" > >(prompt_session) &
	outlast "$2"
	hangup "$1"
}

prompt_session() {
	local message
	while IFS= read -r message; do
		render_prompt "$message" | socat - UNIX-CONNECT:"$CLAUDE_CODE_MESSAGING_SOCKET"
	done
}

render_prompt() {
	jq -nc --arg token "${CLAUDE_CODE_MESSAGING_TOKEN:-}" '{type: "auth", token: $token}'
	jq -c '{type: "user", message: {role: "user", content: "\([.from, .host] | map(select(. != "")) | join("@")): \(.message)"}}' <<<"$1"
}

outlast() {
	while kill -0 "$1" 2>/dev/null; do
		sleep 1
	done
}
