# Copyright (c) 2026 Joseph Hale
# SPDX-License-Identifier: MPL-2.0
#
# shellcheck shell=bash

claude() {
	local session="${2:?Usage: tincan --as <name> relay claude <claude-pid>}"
	if attach "$1" "$session"; then
		while is_alive "$session"; do
			listen_from_now "$1" "$session"
		done
		hangup "$1"
	fi
}

attach() {
	install -d -m 700 "$TINCAN_DIR"
	exec {RELAY_LOCK}>"$TINCAN_DIR/$1.$2.relay"
	flock -n "$RELAY_LOCK"
}

is_alive() {
	kill -0 "$1" 2>/dev/null
}

listen_from_now() {
	local since
	since="$(parse_time now)"
	(pickup "$1") {RELAY_LOCK}>&-
	forward "$1" "$2" "$since"
}

forward() {
	replay "$1" "$3" > >(prompt_session) &
	outlast "$2" &
	wait_for_either
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
	while is_alive "$1"; do
		sleep 1
	done
}

wait_for_either() {
	local pids
	mapfile -t pids < <(jobs -p)
	wait -n "${pids[@]}" || true
	kill "${pids[@]}" 2>/dev/null || true
	wait
}
