#!/usr/bin/env bats
# Copyright (c) 2026 Joseph Hale
# SPDX-License-Identifier: MPL-2.0

bats_require_minimum_version 1.5.0

setup() {
	TINCAN="$BATS_TEST_DIRNAME/../tincan"
	cd "${BATS_TEST_TMPDIR:?}"

	export TINCAN_HOME="$PWD/home"
	export XDG_CONFIG_HOME="$PWD/config"
	UNIT="$XDG_CONFIG_HOME/systemd/user/tincan.service"
	record systemctl
}

record() {
	mkdir -p bin
	printf '#!/bin/sh\necho "$*" >>"%s"\n' "$PWD/$1.log" >"bin/$1"
	chmod +x "bin/$1"
	export PATH="$PWD/bin:$PATH"
}

@test "an installed service serves this device's tincan home" {
	"$TINCAN" init desk >/dev/null

	"$TINCAN" service install

	grep -Fx "ExecStart=$(realpath -s "$TINCAN") serve" "$UNIT"
	grep -F "TINCAN_HOME=$TINCAN_HOME" "$UNIT"
	grep -Fx -- "--user enable tincan.service" systemctl.log
	grep -Fx -- "--user restart tincan.service" systemctl.log
}

@test "a device must be initialised before it can install its service" {
	run -1 "$TINCAN" service install

	[[ "$output" == *"run tincan init first"* ]]
	[ ! -e "$UNIT" ]
}

@test "an uninstalled service is stopped and removed" {
	"$TINCAN" init desk >/dev/null
	"$TINCAN" service install

	"$TINCAN" service uninstall

	grep -Fx -- "--user disable --now tincan.service" systemctl.log
	[ ! -e "$UNIT" ]
}
