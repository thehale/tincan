#!/usr/bin/env bats
# Copyright (c) 2026 Joseph Hale
# SPDX-License-Identifier: MPL-2.0

bats_require_minimum_version 1.5.0

setup() {
	command -v socat >/dev/null || skip "tincan needs socat, which this device does not have"
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

start_session() {
	export CLAUDE_CODE_MESSAGING_SOCKET="$PWD/session.sock"
	socat -u UNIX-LISTEN:"$CLAUDE_CODE_MESSAGING_SOCKET",fork STDOUT >session.heard 3>&- &
	start_relay "$1"
}

start_relay() {
	sleep 60 3>&- &
	SESSION=$!
	"$TINCAN" --as "$1" relay claude "$SESSION" 3>&- &
	RELAY=$!
	RELAYS=$((${RELAYS:-0} + 1))
	wait_for is_forwarded_by "$1" "$RELAYS"
}

is_forwarded_by() {
	[ "$(ps -eo args | grep -c "^tail .* $TINCAN_DIR/$1.log$")" -eq "$2" ]
}

end_session() {
	kill "$SESSION"
	wait_for test ! -e "/proc/$RELAY"
}

receiver() {
	cat "$TINCAN_DIR/$1.pid" 2>/dev/null
}

is_listening() {
	socat -u /dev/null UNIX-CONNECT:"$TINCAN_DIR/$1.sock" 2>/dev/null
}

is_picked_up_again() {
	[[ "$(receiver "$1")" != "$2" ]] && is_listening "$1"
}

prompts() {
	grep '"user"' session.heard | jq -r .message.content | paste -sd,
}

@test "relay hands each message to a Claude session as a line saying who sent it" {
	"$TINCAN" init desk >/dev/null
	start_session bob

	"$TINCAN" --as alice tell bob "hi"
	wait_for grep -q '"user"' session.heard
	end_session

	[ "$(grep '"user"' session.heard | jq -r .message.content)" = "alice@desk: hi" ]
}

@test "a message sent without a name is credited to its device" {
	"$TINCAN" init desk >/dev/null
	start_session bob

	"$TINCAN" tell bob "hi"
	wait_for grep -q '"user"' session.heard
	end_session

	[ "$(grep '"user"' session.heard | jq -r .message.content)" = "desk: hi" ]
}

@test "relay stops listening when the session ends" {
	start_session bob

	end_session

	[ ! -e "/proc/$RELAY" ]
	[ -z "$("$TINCAN" list)" ]
}

@test "a relay started again for the same session leaves the first one to prompt it" {
	start_session bob

	run -0 timeout 5 "$TINCAN" --as bob relay claude "$SESSION" 3>&-
	"$TINCAN" --as alice tell bob "just once"
	wait_for grep -q '"user"' session.heard
	end_session

	[ "$(grep -c '"user"' session.heard)" -eq 1 ]
}

@test "hanging up a name a relay keeps listening fails and says so" {
	"$TINCAN" init desk >/dev/null
	start_session bob

	run -1 "$TINCAN" --as bob hangup
	"$TINCAN" --as alice tell bob "still there?"
	wait_for grep -q '"user"' session.heard
	end_session

	[[ "$output" == *"a relay keeps bob listening"* ]]
	[ "$(prompts)" = "alice@desk: still there?" ]
}

@test "a forced hangup stops the relay along with the listener" {
	start_session bob

	"$TINCAN" --as bob hangup --force

	[ ! -e "/proc/$RELAY" ]
	! is_listening bob
}

@test "a forced hangup while a relay picks the name up again leaves the name silent" {
	start_session bob
	kill -- -"$(receiver bob)"

	run "$TINCAN" --as bob hangup --force

	[ ! -e "/proc/$RELAY" ]
	! is_listening bob
}

@test "a relay keeps its session listening after an earlier session on the same name ends" {
	"$TINCAN" init desk >/dev/null
	start_session bob
	local earlier_session=$SESSION earlier_relay=$RELAY
	start_relay bob
	kill "$earlier_session"
	wait "$earlier_relay"

	is_listening bob
	"$TINCAN" --as alice tell bob "still there?"
	wait_for grep -q '"user"' session.heard
	end_session

	[ "$(prompts)" = "alice@desk: still there?" ]
}

@test "a relay that picks the name up again does not forward what it already forwarded" {
	"$TINCAN" init desk >/dev/null
	start_session bob
	"$TINCAN" --as alice tell bob "once"
	wait_for grep -q once session.heard
	kill -- -"$(receiver bob)"

	wait_for is_picked_up_again bob "$(receiver bob)"
	"$TINCAN" --as alice tell bob "twice"
	wait_for grep -q twice session.heard
	end_session

	[ "$(prompts)" = "alice@desk: once,alice@desk: twice" ]
}
