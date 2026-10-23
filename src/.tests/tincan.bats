#!/usr/bin/env bats
# Copyright (c) 2026 Joseph Hale
# SPDX-License-Identifier: MPL-2.0

bats_require_minimum_version 1.5.0

setup() {
	command -v socat >/dev/null || skip "tincan needs socat, which this device does not have"
	TINCAN="$BATS_TEST_DIRNAME/../tincan"
	cd "${BATS_TEST_TMPDIR:?}"

	export TINCAN_DIR="$PWD/cans"
	export TINCAN_HOME="$PWD/home"
	export TINCAN_PORT=47391
	PEER=127.0.0.2
}

teardown() {
	jobs -p | xargs -r kill 2>/dev/null || true
	find . -name '*.pid' -exec cat {} + | xargs -rI{} kill -- -{} 2>/dev/null || true
}

listen_as() {
	"$TINCAN" --as "$1" listen >"$1.heard" 3>&- &
	LISTENER=$!
	wait_for processes "^tail .* $TINCAN_DIR/$1.log$"
}

processes() {
	ps -eo args | grep -c -- "$1"
}

receivers() {
	ps -eo pgid=,args= | awk -v sock="UNIX-LISTEN:$TINCAN_DIR/$1.sock" '$2 == "socat" && index($0, sock) { print $1 }' |
		sort -u | wc -l
}

heard() {
	wait_for test -s "$1.heard"
	cat "$1.heard"
}

wait_for() {
	local tries=50
	until "$@" || ((--tries == 0)); do
		sleep 0.1
	done
}

on() {
	TINCAN_HOME="$PWD/$1" TINCAN_DIR="$PWD/$1/cans" "${@:2}"
}

device() {
	on "$1" "$TINCAN" init "$1" >/dev/null
	TINCAN_BIND="$1" TINCAN_HOME="$PWD/$1" TINCAN_DIR="$PWD/$1/cans" "$TINCAN" serve 2>/dev/null 3>&- &
	wait_for socat -u /dev/null TCP:"$1":"$TINCAN_PORT"
}

pair() {
	echo y | on "$1" "$TINCAN" pair "$2"
}

group() {
	device localhost
	device "$PEER"
	pair localhost "$PEER"
	pair "$PEER" localhost
	on localhost listen_as bob
}

@test "a message sent to a name reaches the process listening as that name" {
	listen_as bob

	"$TINCAN" tell bob "hello, bob"

	[ "$(heard bob | jq -r .message)" = "hello, bob" ]
}

@test "each message says who sent it and from which device" {
	listen_as bob

	"$TINCAN" --as alice tell bob "hi"

	[ "$(heard bob | jq -r .from)" = "alice" ]
	[ "$(heard bob | jq -r .host)" = "$(hostname)" ]
}

@test "a message left off the command line is read whole from stdin" {
	listen_as bob

	printf 'line one\nline two\n' | "$TINCAN" tell bob

	[ "$(heard bob | wc -l)" -eq 1 ]
	[ "$(heard bob | jq -r .message)" = $'line one\nline two' ]
}

@test "telling a name nobody listens as fails and says so" {
	run -1 "$TINCAN" tell nobody "anyone there?"

	[[ "$output" == *"nothing is listening as nobody"* ]]
}

@test "list shows the names someone is still listening as" {
	listen_as bob
	listen_as carol
	"$TINCAN" --as carol hangup

	run -0 "$TINCAN" list

	[ "$output" = "bob@$(hostname)" ]
}

@test "listening under a name already in use joins it instead of replacing it" {
	listen_as bob
	"$TINCAN" --as bob listen >bob.again 3>&- &

	"$TINCAN" tell bob "hello, both of you"

	wait_for test -s bob.again
	[ "$(jq -r .message bob.again)" = "hello, both of you" ]
	[ "$(heard bob | jq -r .message)" = "hello, both of you" ]
}

@test "a name picked up in the background takes messages before anyone listens" {
	"$TINCAN" --as bob pickup
	"$TINCAN" tell bob "left on the line"

	listen_as bob

	[ "$(heard bob | jq -r .message)" = "left on the line" ]
}

@test "--since leaves out what the name heard before then" {
	listen_as bob
	"$TINCAN" tell bob "old news"
	heard bob >/dev/null
	"$TINCAN" --as bob listen --since now >later.heard 3>&- &
	wait_for test "$(processes "^tail .* $TINCAN_DIR/bob.log$")" -eq 2

	"$TINCAN" tell bob "new news"

	wait_for test -s later.heard
	[ "$(jq -r .message later.heard)" = "new news" ]
}

@test "--since counts a duration back from now" {
	"$TINCAN" --as bob pickup
	"$TINCAN" tell bob "a moment ago"

	"$TINCAN" --as bob listen --since 1m >bob.heard 3>&- &

	[ "$(heard bob | jq -r .message)" = "a moment ago" ]
}

@test "names picked up at the same moment share one receiver" {
	local pickups=()
	for _ in 1 2 3 4 5; do
		"$TINCAN" --as bob pickup 3>&- &
		pickups+=($!)
	done
	wait "${pickups[@]}"

	[ "$(receivers bob)" -eq 1 ]
}

@test "a socket left behind by a listener that died is taken over" {
	mkdir -m 700 "$TINCAN_DIR"
	timeout 0.2 socat -u UNIX-LISTEN:"$TINCAN_DIR/bob.sock",unlink-close=0 /dev/null || true
	listen_as bob

	"$TINCAN" tell bob "anyone home?"

	[ "$(heard bob | jq -r .message)" = "anyone home?" ]
}

@test "hanging up a name stops its listeners and frees the name" {
	listen_as bob

	"$TINCAN" --as bob hangup
	wait "$LISTENER"

	run -1 "$TINCAN" tell bob "hello?"
}

@test "hanging up a name nobody listens as fails and says so" {
	run -1 "$TINCAN" --as nobody hangup

	[[ "$output" == *"nothing is listening as nobody"* ]]
}

@test "a name cannot reach outside the tincan directory" {
	run -1 "$TINCAN" tell ../bob "escape"

	[[ "$output" == *"is not a name"* ]]
}

@test "a device in the group delivers to a listener on another device" {
	group

	on "$PEER" "$TINCAN" tell bob@localhost "across the wire"

	[ "$(heard bob | jq -r .message)" = "across the wire" ]
	[ "$(heard bob | jq -r .host)" = "$PEER" ]
}

@test "list shows the listeners on every device in the group" {
	group

	run -0 on "$PEER" "$TINCAN" list

	[ "$output" = "bob@localhost" ]
}

@test "list leaves out a device that does not answer and still lists the rest" {
	group
	on "$PEER" listen_as carol
	cp "$PEER/peers/localhost.pem" localhost/peers/127.0.0.9.pem

	run -0 on localhost "$TINCAN" list

	[ "$output" = $'bob@localhost\ncarol@'"$PEER" ]
}

@test "list --all marks a device that does not answer" {
	group
	cp "$PEER/peers/localhost.pem" localhost/peers/127.0.0.9.pem

	run -0 on localhost "$TINCAN" list --all

	[ "$output" = $'bob@localhost\n127.0.0.9 (unreachable)' ]
}

@test "two devices pairing see the same code" {
	device localhost
	device "$PEER"

	pair localhost "$PEER" >here.code
	pair "$PEER" localhost >there.code

	[ "$(grep code: here.code)" = "$(grep code: there.code)" ]
}

@test "a device is trusted only once its code is confirmed" {
	device localhost
	device "$PEER"

	echo n | on localhost "$TINCAN" pair "$PEER" || true

	[ ! -e "localhost/peers/$PEER.pem" ]
}

@test "a device that pairs with you is refused until you pair back" {
	device localhost
	device "$PEER"
	on localhost listen_as bob
	pair "$PEER" localhost

	run -1 on "$PEER" "$TINCAN" tell bob@localhost "let me in"
	run -0 on "$PEER" "$TINCAN" list

	[ ! -s bob.heard ]
	[[ "$output" != *"bob@localhost"* ]]
}

@test "pairing refuses a device that answers under another name" {
	device localhost
	device "$PEER"

	run -1 pair "$PEER" 127.0.0.1

	[[ "$output" == *"answered with a certificate for localhost"* ]]
}

@test "pairing with a device that never answers gives up and says where it waited" {
	socat -u TCP-LISTEN:"$TINCAN_PORT",bind="$PEER",fork,reuseaddr OPEN:/dev/null 3>&- &
	wait_for socat -u /dev/null TCP:"$PEER":"$TINCAN_PORT"
	"$TINCAN" init >/dev/null

	run -1 timeout 10 "$TINCAN" pair "$PEER"

	[[ "$output" == *"$PEER:$TINCAN_PORT"* ]]
}

@test "a device serves on every address it has, not only the one its name resolves to" {
	"$TINCAN" init localhost >/dev/null
	"$TINCAN" serve 2>/dev/null 3>&- &

	wait_for socat -u /dev/null TCP:localhost:"$TINCAN_PORT"

	socat -u /dev/null TCP:127.0.0.3:"$TINCAN_PORT"
}

@test "the receiving device names the sender's device from its certificate" {
	group

	{
		echo "post bob"
		echo '{"host": "localhost", "message": "trust me"}'
	} | socat - OPENSSL:localhost:"$TINCAN_PORT",cert="$PEER/me.pem",cafile="$PEER/peers/localhost.pem"

	[ "$(heard bob | jq -r .host)" = "$PEER" ]
}

@test "a forgotten device is refused at once" {
	group
	on localhost "$TINCAN" forget "$PEER"

	run -1 on "$PEER" "$TINCAN" tell bob@localhost "still friends?"

	[[ "$output" == *"refused this device"* ]]
}

@test "a device refuses to talk to a server that is not who it claims to be" {
	group
	TINCAN_HOME="$PWD/impostor" "$TINCAN" init localhost >/dev/null
	cp impostor/peers/localhost.pem "$PEER/peers/localhost.pem"

	run -1 on "$PEER" "$TINCAN" tell bob@localhost "secret"

	[ ! -s bob.heard ]
	[[ "$output" == *"is not who its certificate says"* ]]
}

@test "a device initialised without a name takes its hostname" {
	"$TINCAN" init >/dev/null

	[ "$(openssl x509 -noout -subject -nameopt RFC2253 -in "$TINCAN_HOME/me.pem")" = "subject=CN=$(hostname)" ]
}

@test "a device initialised again under a new name no longer trusts its old name" {
	"$TINCAN" init desk >/dev/null

	"$TINCAN" init laptop >/dev/null

	[ "$(ls "$TINCAN_HOME/peers")" = "laptop.pem" ]
}

@test "whoami prints the name the device was initialised with" {
	"$TINCAN" init desk >/dev/null

	[ "$("$TINCAN" whoami)" = "desk" ]
}

@test "whoami as a name prints the address that reaches it" {
	"$TINCAN" init desk >/dev/null

	[ "$("$TINCAN" --as bob whoami)" = "bob@desk" ]
}

@test "a device not yet initialised goes by its hostname" {
	[ "$("$TINCAN" whoami)" = "$(hostname)" ]
}

@test "relay does nothing for a session without a name" {
	run -0 "$TINCAN" --as "" relay claude 1

	[ ! -e "$TINCAN_DIR" ]
}

@test "relay names the agents it has adapters for" {
	run -1 "$TINCAN" --as bob relay nobody 1

	[[ "$output" == *"try: claude"* ]]
}
