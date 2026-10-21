# Copyright (c) 2026 Joseph Hale
# SPDX-License-Identifier: MPL-2.0
#
# shellcheck shell=bash

_tincan() {
	local cur="${COMP_WORDS[COMP_CWORD]}"
	if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == tell ]]; then
		mapfile -t COMPREPLY < <(compgen -W "$(tincan list 2>/dev/null)" -- "$cur")
	elif [[ $COMP_CWORD -eq 1 || ($COMP_CWORD -eq 3 && ${COMP_WORDS[1]} == --as) ]]; then
		mapfile -t COMPREPLY < <(compgen -W "pickup listen hangup tell relay list init serve service pair forget whoami" -- "$cur")
	fi
}

complete -F _tincan tincan
