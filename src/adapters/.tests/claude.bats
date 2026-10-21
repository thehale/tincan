#!/usr/bin/env bats
# Copyright (c) 2026 Joseph Hale
# SPDX-License-Identifier: MPL-2.0

bats_require_minimum_version 1.5.0

setup() {
	TINCAN="$BATS_TEST_DIRNAME/../../tincan"
	cd "${BATS_TEST_TMPDIR:?}"

	export TINCAN_DIR="$PWD/cans"
	export TINCAN_HOME="$PWD/home"
}

teardown() {
	jobs -p | xargs -r kill 2>/dev/null || true
	find . -name '*.pid' -exec cat {} + | xargs -rI{} kill -- -{} 2>/dev/null || true
}

wait_for() {
	local tries=50
	until "$@" || ((--tries == 0)); do
		sleep 0.1
	done
}

session() {
	export CLAUDE_CODE_MESSAGING_SOCKET="$PWD/session.sock"
	socat -u UNIX-LISTEN:"$CLAUDE_CODE_MESSAGING_SOCKET",fork STDOUT >session.heard 3>&- &
	sleep 60 3>&- &
	SESSION=$!
	"$TINCAN" --as "$1" relay claude "$SESSION" 3>&- &
	RELAY=$!
	wait_for held "$TINCAN_DIR/$1.$SESSION.relay"
}

held() {
	[[ -e "$1" ]] && ! flock -n "$1" true
}

end_session() {
	kill "$SESSION"
	wait_for test ! -e "/proc/$RELAY"
}

@test "relay hands each message to a Claude session as a line saying who sent it" {
	"$TINCAN" init desk >/dev/null
	session bob

	"$TINCAN" --as alice tell bob "hi"
	wait_for grep -q '"user"' session.heard
	end_session

	[ "$(grep '"user"' session.heard | jq -r .message.content)" = "alice@desk: hi" ]
}

@test "a message sent without a name is credited to its device" {
	"$TINCAN" init desk >/dev/null
	session bob

	"$TINCAN" tell bob "hi"
	wait_for grep -q '"user"' session.heard
	end_session

	[ "$(grep '"user"' session.heard | jq -r .message.content)" = "desk: hi" ]
}

@test "relay stops listening when the session ends" {
	session bob

	end_session

	[ ! -e "/proc/$RELAY" ]
	[ -z "$("$TINCAN" list)" ]
}

@test "a relay started again for the same session leaves the first one to prompt it" {
	session bob

	run -0 timeout 5 "$TINCAN" --as bob relay claude "$SESSION" 3>&-
	"$TINCAN" --as alice tell bob "just once"
	wait_for grep -q '"user"' session.heard
	end_session

	[ "$(grep -c '"user"' session.heard)" -eq 1 ]
}
