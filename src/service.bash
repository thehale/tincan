# Copyright (c) 2026 Joseph Hale
# SPDX-License-Identifier: MPL-2.0
#
# shellcheck shell=bash

UNIT="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/tincan.service"

service() {
	case "${1:-}" in
	install) install_service ;;
	uninstall) uninstall_service ;;
	start | stop | status) systemctl --user "$1" tincan.service ;;
	*)
		echo "Usage: tincan service install|uninstall|start|stop|status" >&2
		exit 1
		;;
	esac
}

install_service() {
	if [[ ! -f "$TINCAN_HOME/me.pem" ]]; then
		echo "tincan: this device has no name yet; run tincan init first" >&2
		exit 1
	fi
	install -d "$(dirname "$UNIT")"
	unit >"$UNIT"
	systemctl --user daemon-reload
	systemctl --user enable tincan.service
	systemctl --user restart tincan.service
}

unit() {
	cat <<EOF
[Unit]
Description=tincan: let paired devices reach this device's listeners

[Service]
Environment="TINCAN_HOME=$TINCAN_HOME" "TINCAN_PORT=$TINCAN_PORT"
ExecStart=$(realpath -s "$0") serve
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
}

uninstall_service() {
	systemctl --user disable --now tincan.service
	rm "$UNIT"
	systemctl --user daemon-reload
}
