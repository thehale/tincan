#!/usr/bin/env bats
# Copyright (c) 2026 Joseph Hale
# SPDX-License-Identifier: MPL-2.0

setup() {
	source "$BATS_TEST_DIRNAME/../tincan.bash"
}

tincan() {
	printf '%s\n' bob@laptop bob@desktop carol@desktop
}

complete_line() {
	read -ra COMP_WORDS <<<"$1"
	if [[ "$1" == *" " ]]; then
		COMP_WORDS+=("")
	fi
	COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
	_tincan
	printf '%s\n' "${COMPREPLY[@]}"
}

@test "tincan completes its commands" {
	[ "$(complete_line "tincan pi")" = "pickup" ]
}

@test "a command completes after --as names the sender" {
	[ "$(complete_line "tincan --as alice te")" = "tell" ]
}

@test "tell completes every name tincan list shows" {
	[ "$(complete_line "tincan tell ")" = $'bob@laptop\nbob@desktop\ncarol@desktop' ]
}

@test "tell completes a name on a chosen device" {
	[ "$(complete_line "tincan --as alice tell bob@d")" = "bob@desktop" ]
}
