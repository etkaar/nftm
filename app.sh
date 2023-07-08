#!/bin/sh
: '''
Copyright (c) 2020-23 etkaar <https://github.com/etkaar/nftm>
Version 1.0.8 (July, 8th 2023)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE
OR OTHER DEALINGS IN THE SOFTWARE.
'''
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Change working directory
ABSPATH="$(cd "$(dirname "$0")"; pwd -P)"
cd "$ABSPATH"

# Import generic functions
. ./inc/_defs.sh

# Include whitelist and blacklist generating functions
. ./inc/_whiteblacklists.sh

# Ensure only root can run this script
if [ ! "$(whoami)" = "root" ]
then
	func_EXIT_ERROR 1 "You need to run this command as root."
fi

# Paths
CONF_PATH="$ABSPATH/conf"
INC_PATH="$ABSPATH/inc"
PRESETS_PATH="$CONF_PATH/presets"
TMP_PATH="$ABSPATH/.tmp"

AVAILABLE_PRESETS_PATH="$PRESETS_PATH/available"
ENABLED_PRESETS_PATH="$PRESETS_PATH/enabled"

ADDITIONAL_RULES_FILE="$CONF_PATH/additional_rules.txt"

# Create dirs if not existing
for CHECKPATH in "$TMP_PATH" "$ENABLED_PRESETS_PATH"
do
	if [ ! -d "$CHECKPATH" ]
	then
		mkdir "$CHECKPATH"
		chmod 0700 "$CHECKPATH"
	fi
done

# Minimum required nftables >= 0.9.0
NFTABLES_REQUIRED_MIN_VERSION_STRING="0.9.0"
NFTABLES_REQUIRED_MIN_VERSION_INTEGER="$(func_VERSION_STRING_TO_INTEGER 3 "$NFTABLES_REQUIRED_MIN_VERSION_STRING")"

# Currently installed nftables version
NFTABLES_INSTALLED_VERSION_STRING="$(printf '%s' "$(nft --version)" | awk '{print $2}' | tr -d 'v')"
NFTABLES_INSTALLED_VERSION_INTEGER="$(func_VERSION_STRING_TO_INTEGER 3 "$NFTABLES_INSTALLED_VERSION_STRING")"

# Crontab for whitelists and blacklists update
# (Prevents you from being locked out after IP change)
CRONTAB_INTERVAL_MINUTES="3"
CRONTAB_COMMAND="$ABSPATH/app.sh cron"
CRONTAB_LINE="*/$CRONTAB_INTERVAL_MINUTES * * * * $CRONTAB_COMMAND"

# Firewall startup script
STARTUP_SCRIPT_PATH="/etc/network/if-up.d/nftm"
STARTUP_SCRIPT_CONTENT="$(cat << EOF
#!/bin/sh
if [ ! "\$IFACE" = "lo" ]
then
	$ABSPATH/app.sh init
fi
EOF
)"

# Command
CMD="$1"

# Options
OPT_NO_WARNINGS=0
OPT_DEBUG=0
OPT_DRY_RUN=0
OPT_NO_VERSION_CHECK=0

# Are any options set?
ANY_OPT_IS_SET=0

n=1
for ARG in "$@"
do
	if [ "$ARG" = "--no-warnings" ]
	then
		OPT_NO_WARNINGS=1
	elif [ "$ARG" = "--no-version-check" ]
	then
		OPT_NO_VERSION_CHECK=1
	elif [ "$ARG" = "--dry-run" ]
	then
		OPT_DRY_RUN=1
	elif [ "$ARG" = "--debug" ]
	then
		OPT_DEBUG=1
	fi
	
	# Make sure --opt are always appended to
	# the end of the command
	if [ "${ARG##--*}" = "" ]
	then
		ANY_OPT_IS_SET=1
	fi
	
	if [ "$n" = "$#" ]
	then
		if [ "$ANY_OPT_IS_SET" = "1" ] && [ "${ARG##--*}" != "" ]
		then
			func_EXIT_ERROR 1 "ERROR: All options (--opt) must be appended at the end of command."
		fi
	fi
	
	n=$((n + 1))
done

# Help message
func_USAGE() {
	func_STDOUT "Basic: ${0} {list|update|full-reload|flush}"
	func_STDOUT "Setup:  ${0} {setup-crontab|setup-startupscript|update-permissions}"
	func_STDOUT ""
	func_STDOUT "Options (general):"
	func_STDOUT "  --no-warnings          Do not show warnings."
	func_STDOUT "  --no-version-check     Ignore version checks (forces to run even with incompatible versions)."
	func_STDOUT "  --dry-run              Do generate, but not actually update the nft ruleset."
	func_STDOUT "  --debug                Show debug messages."
	func_STDOUT ""
	func_STDOUT "Configuration:"
	func_STDOUT "  $CONF_PATH/whitelist.conf"
	func_STDOUT "  $CONF_PATH/blacklist.conf"
	func_STDOUT "  $CONF_PATH/additional_rules.txt"
	func_STDOUT ""
	func_STDOUT "Presets:"
	func_STDOUT "  $AVAILABLE_PRESETS_PATH/"
	func_STDOUT ""
}

# Update permissions
func_UPDATE_PERMISSIONS() {
	# dirs: all
	for CHECKPATH in "$CONF_PATH" "$INC_PATH" "$PRESETS_PATH" "$AVAILABLE_PRESETS_PATH" "$ENABLED_PRESETS_PATH"
	do
		PERMISSIONS=700
		if ! func_VALIDATE_PERMISSIONS "$CHECKPATH" "$PERMISSIONS"
		then
			printf '%s\n' "Permissions for $CHECKPATH changed to:"
			printf '%s\n' "  $PERMISSIONS"
		fi
	done

	# files: executable
	PERMISSIONS=700
	FILE="$ABSPATH/presets.sh"
	if ! func_VALIDATE_PERMISSIONS "$FILE" "$PERMISSIONS"
	then
		printf '%s\n' "Permissions for $FILE changed to:"
		printf '%s\n' "  $PERMISSIONS"
	fi

	# files: scripts
	for FILE in $(ls "$INC_PATH"/*)
	do
		PERMISSIONS=500
		if ! func_VALIDATE_PERMISSIONS "$FILE" "$PERMISSIONS"
		then
			printf '%s\n' "Permissions for $FILE changed to:"
			printf '%s\n' "  $PERMISSIONS"
		fi
	done

	# files: configuration files
	for FILE in $(find "$CONF_PATH" -maxdepth 1 -type f)
	do
		PERMISSIONS=600
		if ! func_VALIDATE_PERMISSIONS "$FILE" "$PERMISSIONS"
		then
			printf '%s\n' "Permissions for $FILE changed to:"
			printf '%s\n' "  $PERMISSIONS"
		fi
	done

	# files: presets
	for FILE in $(ls "$AVAILABLE_PRESETS_PATH"/*)
	do
		PERMISSIONS=600
		if ! func_VALIDATE_PERMISSIONS "$FILE" "$PERMISSIONS"
		then
			printf '%s\n' "Permissions for $FILE changed to:"
			printf '%s\n' "  $PERMISSIONS"
		fi
	done
}

# Check certain things and show warn messages if applicable
#
# NOTE: Do NOT use this for any critical stuff, as warnings
# may be suppressed for legitime reasons.
func_SHOW_WARNINGS() {
	# Check if crontab exists
	if ! func_USER_CRONTAB_EXISTS "$CRONTAB_LINE"
	then
		printf '%s\n' "WARNING: No user crontab for root found (see \"crontab -l\"). Run following command to setup it automatically:"
		printf '%s\n' "  ${0} setup-crontab"
	fi

	# Check if the old firewall startup script still exists
	# (Since 1.0.7, 24th Jan 2023)
	if [ -f "/etc/network/if-pre-up.d/firewall" ]
	then
		printf '%s\n' "WARNING: Startup script has changed and moved. You should delete and re-create it:"
		printf '%s\n' "  rm /etc/network/if-pre-up.d/firewall && ${0} setup-startupscript"
	else
		# Check if firewall startup script exists
		if [ ! -f "$STARTUP_SCRIPT_PATH" ]
		then
			printf '%s\n' "WARNING: No startup script found. Run following command to setup it automatically:"
			printf '%s\n' "  ${0} setup-startupscript"
		fi
	fi
}

# Make sure supported version of nftables is installed
if ! nft --version >/dev/null 2>&1
then
	func_EXIT_ERROR 1 "ERROR: Package 'nftables' not installed."
fi

if [ ! "$CMD" = "" ] && [ "$OPT_NO_VERSION_CHECK" = 0 ]
then
	# Check for nftables version
	if [ "$NFTABLES_INSTALLED_VERSION_INTEGER" -lt "$NFTABLES_REQUIRED_MIN_VERSION_INTEGER" ]
	then
		func_EXIT_ERROR 1 "ERROR: You need nftables >= $NFTABLES_REQUIRED_MIN_VERSION_STRING (current: $NFTABLES_INSTALLED_VERSION_STRING)."
	fi
fi

# Warn of missing crontab or startup script
if [ ! "$OPT_NO_WARNINGS" = 1 ]
then
	if [ ! "$CMD" = "" ] && [ ! "$CMD" = "init" ] && [ ! "$CMD" = "cron" ] && [ ! "$CMD" = "setup-crontab" ] && [ ! "$CMD" = "setup-startupscript" ] && [ ! "$CMD" = "update-permissions" ]
	then
		WARNINGS="$(func_SHOW_WARNINGS)"
		
		if [ ! "$WARNINGS" = "" ]
		then
			func_PRINT_ERROR "Script stopped. You can turn off these checks using --no-warnings."
			func_EXIT_WARNING 1 "$WARNINGS"
		fi
	fi
fi

# Validate permissions as long any command is given
if [ ! "$CMD" = "" ]
then
	func_UPDATE_PERMISSIONS
fi

# Check if IPv6 preset is enabled
IPV6_ENABLED=1

if ./presets.sh status default ipv4-only >/dev/null 2>&1
then
	IPV6_ENABLED=0
fi

# Whitelist and blacklist presets
IP_VERSIONS="all"

if [ "$IPV6_ENABLED" = 0 ]
then
	IP_VERSIONS=4
fi

# Commands
func_CMD_LIST_RULESET() {
	nft list ruleset
}

func_CMD_FLUSH_RULESET() {
	nft flush ruleset
}

func_CMD_UPDATE() {
	# Ensure default preset is enabled
	if ! ls "$ENABLED_PRESETS_PATH"/*default* >/dev/null 2>&1
	then
		func_EXIT_ERROR 1 "No default preset enabled."
	fi

	# Update only (reloads whitelist and blacklist)
	if [ "$(nft list ruleset)" = "" ]
	then
		func_EXIT_ERROR 1 "No ruleset loaded. Run following command to reload the ruleset:" "  ${0} full-reload"
	fi

	# Update whitelist and blacklist
	if ! func_CREATE_WHITE_OR_BLACKLIST_TEMPLATE whitelist update "$IP_VERSIONS" >/dev/null
	then
		func_EXIT_ERROR 1 "ERROR: Failed to generate whitelist."
	fi
	
	if ! func_CREATE_WHITE_OR_BLACKLIST_TEMPLATE blacklist update "$IP_VERSIONS" >/dev/null
	then
		func_EXIT_ERROR 1 "ERROR: Failed to generate blacklist."
	fi
}

func_CMD_FULL_RELOAD() {
	# Ensure default preset is enabled
	if ! ls "$ENABLED_PRESETS_PATH"/*default* >/dev/null 2>&1
	then
		func_EXIT_ERROR 1 "No default preset enabled."
	fi
	
	# Temporary ruleset file which is later
	# used to atomically reload the ruleset
	TMP_RULESET_FILE="$TMP_PATH/ruleset"
	func_TRUNCATE "$TMP_RULESET_FILE"
	
	printf '%s\n' "#!/usr/sbin/nft -f" >> "$TMP_RULESET_FILE"
	printf '%s\n' "flush ruleset" >> "$TMP_RULESET_FILE"

	# Apply all presets
	for PRESET in $(ls "$ENABLED_PRESETS_PATH")
	do
		printf '\n' >> "$TMP_RULESET_FILE"
	
		# Apply replacements and append to ruleset file
		func_APPLY_TEMPLATE_SUBSTITUTIONS "$(cat "$ENABLED_PRESETS_PATH/$PRESET")" >> "$TMP_RULESET_FILE"
	done

	# Re-generate whitelist and blacklist
	if ! GENERATED="$(func_CREATE_WHITE_OR_BLACKLIST_TEMPLATE whitelist generate "$IP_VERSIONS")"
	then
		func_EXIT_ERROR 1 "ERROR: Failed to generate whitelist."
	else
		printf '%s\n' "$GENERATED" >> "$TMP_RULESET_FILE"
	fi
	
	if ! GENERATED="$(func_CREATE_WHITE_OR_BLACKLIST_TEMPLATE blacklist generate "$IP_VERSIONS")"
	then
		func_EXIT_ERROR 1 "ERROR: Failed to generate blacklist."
	else
		printf '%s\n' "$GENERATED" >> "$TMP_RULESET_FILE"
	fi
	
	# Append additional rules
	if [ -f "$ADDITIONAL_RULES_FILE" ]
	then
		cat "$ADDITIONAL_RULES_FILE" >> "$TMP_RULESET_FILE"
	fi
	
	# We redirect this to STDERR instead of STDOUT just to make
	# sure that one does not accidentally leaves that option
	# turned on after testing.
	if [ "$OPT_DRY_RUN" = 1 ]
	then
		func_STDERR "Generated ruleset can be found here:"
		func_STDERR "  $TMP_RULESET_FILE"
		
		CHECKRESULT="$(2>&1 nft -c -f "$TMP_RULESET_FILE")"
		
		if [ ! "$CHECKRESULT" = "" ]
		then
			func_PRINT_ERROR "DRY-RUN: ***FAILED***"
			func_STDERR "$CHECKRESULT"
		else
			func_STDERR "DRY-RUN: Success."
		fi
	else
		if nft -f "$TMP_RULESET_FILE"
		then
			rm "$TMP_RULESET_FILE"
		fi
	fi
}

func_CMD_SETUP_CRONTAB() {
	if func_USER_CRONTAB_EXISTS "$CRONTAB_LINE"
	then
		func_PRINT_ERROR "Crontab already exists:"
		func_PRINT_ERROR "  $(crontab -l 2>/dev/null | grep "$CRONTAB_COMMAND\$")"
	else
		if func_ADD_USER_CRONTAB "$CRONTAB_LINE"
		then
			func_STDOUT "Crontab for current user added:"
			func_STDOUT "  $CRONTAB_LINE"
		fi
	fi
}

func_CMD_SETUP_STARTUP_SCRIPT() {
	if [ -f "$STARTUP_SCRIPT_PATH" ]
	then
		func_PRINT_ERROR "Startup script already exists:"
		func_PRINT_ERROR "  $STARTUP_SCRIPT_PATH"
	else
		printf '%s\n' "$STARTUP_SCRIPT_CONTENT" > "$STARTUP_SCRIPT_PATH"
		chmod 0755 "$STARTUP_SCRIPT_PATH"
		
		func_STDOUT "Startup script created:"
		func_STDOUT "  $STARTUP_SCRIPT_PATH"
	fi
}

case "$CMD" in

	# List active ruleset
	show)
		func_CMD_LIST_RULESET
	;;
	
	# Alias for 'show'
	list)
		func_CMD_LIST_RULESET
	;;
	
	# Flushes whole ruleset
	flush)
		func_CMD_FLUSH_RULESET
	;;
	
	# Setups user crontab if not exists
	setup-crontab)
		func_CMD_SETUP_CRONTAB
	;;
	
	# Setups the firewall startup script to keep ruleset after reboot
	setup-startupscript)
		func_CMD_SETUP_STARTUP_SCRIPT
	;;
	
	# No function, because permissions are
	# always automatically checked.
	update-permissions)
		exit 0
	;;
	
	# Manually update whitelists
	update)
		func_CMD_UPDATE
	;;
	
	# Manually initate full reload of all rules
	full-reload)
		func_CMD_FULL_RELOAD
	;;
	
	# For crontabs only
	cron)
		func_CMD_UPDATE
	;;
	
	# Used for startup script after reboot
	init)
		func_CMD_FULL_RELOAD
	;;	
	
	*)
		func_STDOUT "$(func_USAGE)"
		exit 1
    ;;
	
esac

# Delete .tmp dir if empty
if [ ! "$OPT_DRY_RUN" = 1 ]
then
	rmdir "$TMP_PATH" 2>/dev/null
fi

exit 0
