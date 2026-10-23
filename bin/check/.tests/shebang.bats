#!/usr/bin/env bats
# Copyright (c) 2026 Joseph Hale
# SPDX-License-Identifier: MPL-2.0

bats_require_minimum_version 1.5.0

WANTED='#!/usr/bin/env bash'

setup() {
	SHEBANG="$BATS_TEST_DIRNAME/../shebang"
	cd "${BATS_TEST_TMPDIR:?}"

	printf '%s\necho right\n' "$WANTED" >right.sh
	printf '#!/bin/sh\necho wrong\n' >wrong.sh
	printf 'echo bare\n' >bare.sh
}

@test "passes a file whose shebang matches" {
	run "$SHEBANG" "$WANTED" <<<"right.sh"

	[ "$status" -eq 0 ]
}

@test "fails and names the offender on stderr" {
	run --separate-stderr "$SHEBANG" "$WANTED" <<<"wrong.sh"

	[ "$status" -eq 1 ]
	[[ "$stderr" == *"wrong.sh"* ]]
}

@test "reports every offender, not just the first" {
	printf '#!/bin/zsh\n' >alsowrong.sh

	run --separate-stderr "$SHEBANG" "$WANTED" <<<"$(printf 'wrong.sh\nalsowrong.sh\n')"

	[ "$status" -eq 1 ]
	[[ "$stderr" == *"wrong.sh"* ]]
	[[ "$stderr" == *"alsowrong.sh"* ]]
}

@test "ignores a file with no shebang at all" {
	run "$SHEBANG" "$WANTED" <<<"bare.sh"

	[ "$status" -eq 0 ]
}

@test "accepts empty stdin" {
	run "$SHEBANG" "$WANTED" </dev/null

	[ "$status" -eq 0 ]
}

@test "--fix rewrites a wrong shebang in place" {
	run "$SHEBANG" --fix "$WANTED" <<<"wrong.sh"

	[ "$status" -eq 0 ]
	[ "$(head -1 wrong.sh)" = "$WANTED" ]
}

@test "--fix keeps the file executable" {
	chmod +x wrong.sh

	run "$SHEBANG" --fix "$WANTED" <<<"wrong.sh"

	[ "$status" -eq 0 ]
	[ -x wrong.sh ]
}

@test "--fix leaves the rest of the file alone" {
	"$SHEBANG" --fix "$WANTED" <<<"wrong.sh"

	[ "$(sed -n '2 p' wrong.sh)" = 'echo wrong' ]
	[ "$(wc -l <wrong.sh)" -eq 2 ]
}

@test "--fix adds no blank line to a file that is only a shebang" {
	printf '#!/bin/sh\n' >only.sh

	"$SHEBANG" --fix "$WANTED" <<<"only.sh"

	[ "$(cat only.sh)" = "$WANTED" ]
	[ "$(wc -l <only.sh)" -eq 1 ]
}

@test "--fix does not add a shebang to a file without one" {
	"$SHEBANG" --fix "$WANTED" <<<"bare.sh"

	[ "$(head -1 bare.sh)" = 'echo bare' ]
}

@test "exits with usage when given no shebang" {
	run --separate-stderr "$SHEBANG" </dev/null

	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Usage:"* ]]
}
