#!/usr/bin/env bats
# Copyright (c) 2026 Joseph Hale
# SPDX-License-Identifier: MPL-2.0

bats_require_minimum_version 1.5.0

setup() {
	TINCAN="$BATS_TEST_DIRNAME/../tincan"
	cd "${BATS_TEST_TMPDIR:?}"
}

@test "a device without socat says tincan needs it" {
	mkdir bin
	ln -s "$(command -v bash)" "$(command -v dirname)" "$(command -v readlink)" bin/

	PATH="$PWD/bin" run -1 "$TINCAN" --as bob pickup

	[[ "$output" == *"needs socat"* ]]
}
