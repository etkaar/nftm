#!/bin/dash
: '''
Copyright (c) 2020-21 etkaar <https://github.com/etkaar>

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

# Import functions
. ./inc/_defs.sh

# Ensure only root runs this script
func_ENSURE_ROOT

# Options
OPT_NO_WARNINGS=0
OPT_DEBUG=0
OPT_DRY_RUN=0

# I know, perhaps using getopts would have been better
for ARG in "$@"
do
	if [ "$ARG" = "--no-warnings" ]
	then
		OPT_NO_WARNINGS=1
	elif [ "$ARG" = "--debug" ]
	then
		OPT_DEBUG=1
	elif [ "$ARG" = "--dry-run" ]
	then
		OPT_DRY_RUN=1
	fi
done

# Help message
func_USAGE() {
	echo "Basic: ${0} {show|update|full-reload}"
	echo "Setup:  ${0} {full-setup|setup-crontab|setup-startupscript}"
	echo ""
	echo "Options (general):"
	echo "  --no-warnings     Do not show warnings."
	echo "  --debug           Show debug messages."
	echo "  --dry-run         Do generate, but not actually update the nft ruleset."
	echo ""
}

# Update permissions
func_UPDATE_PERMISSIONS() {

	# dirs
	for CHECKPATH in "$CONF_PATH" "$INC_PATH" "$PRESETS_PATH" "$AVAILABLE_PRESETS_PATH" "$ENABLED_PRESETS_PATH"
	do
		chmod --changes 0700 "$CHECKPATH"
	done

	# files
	for FILE in `ls "$INC_PATH"/*`
	do
		chmod --changes 0500 "$FILE"
	done

	for FILE in `ls "$CONF_PATH"/*.conf`
	do
		chmod --changes 0600 "$FILE"
	done

	for FILE in `ls "$AVAILABLE_PRESETS_PATH"/*`
	do
		chmod --changes 0600 "$FILE"
	done
	
}

# dependencies: nftables >= 0.9.0
if ! nft --version >/dev/null 2>&1
then
	func_EXIT_ERROR 1 "ERROR: Package 'nftables' not installed."
fi

NFTABLES_REQUIRED_MIN_VERSION_STRING="0.9.0"
NFTABLES_REQUIRED_MIN_VERSION_INTEGER="`func_VERSION_STRING_TO_INTEGER 3 "$NFTABLES_REQUIRED_MIN_VERSION_STRING"`"

NFTABLES_INSTALLED_VERSION_STRING="$(echo "`nft --version`" | awk '{print $2}' | tr -d 'v')"
NFTABLES_INSTALLED_VERSION_INTEGER="`func_VERSION_STRING_TO_INTEGER 3 "$NFTABLES_INSTALLED_VERSION_STRING"`"

# Check for nftables version
if [ $NFTABLES_INSTALLED_VERSION_INTEGER -lt $NFTABLES_REQUIRED_MIN_VERSION_INTEGER ]
then
	func_EXIT_ERROR 1 "ERROR: You need nftables >= $NFTABLES_REQUIRED_MIN_VERSION_STRING (current: $NFTABLES_INSTALLED_VERSION_STRING)."
fi

# Crontab for whitelists and blacklists update
# (Prevents you from being locked out after IP change)
CRONTAB_INTERVAL_MINUTES="3"
CRONTAB_COMMAND="$ABSPATH/app.sh cron"
CRONTAB_LINE="*/$CRONTAB_INTERVAL_MINUTES * * * * $CRONTAB_COMMAND"

# Firewall startup script
STARTUP_SCRIPT_PATH="/etc/network/if-pre-up.d/firewall"
STARTUP_SCRIPT_CONTENT=`cat <<-_EOF_
						#!/bin/sh
						$ABSPATH/app.sh init
						_EOF_`

# Paths
CONF_PATH="$ABSPATH/conf"
INC_PATH="$ABSPATH/inc"
PRESETS_PATH="$CONF_PATH/presets"
TMP_PATH="$ABSPATH/.tmp"

AVAILABLE_PRESETS_PATH="$PRESETS_PATH/available"
ENABLED_PRESETS_PATH="$PRESETS_PATH/enabled"

ADDITIONAL_RULES_FILE="$CONF_PATH/additional_rules.txt"

# Create dirs if not exist
for CHECKPATH in "$TMP_PATH" "$ENABLED_PRESETS_PATH"
do
	if [ ! -d "$CHECKPATH" ]
	then
		mkdir "$CHECKPATH"
		chmod 0700 "$CHECKPATH"
	fi
done

func_UPDATE_PERMISSIONS

# Command
CMD="$1"

if [ ! "$OPT_NO_WARNINGS" = 1 ]
then
	if [ ! "$CMD" = "setup-crontab" ] && [ ! "$CMD" = "setup-startupscript" ] && [ ! "$CMD" = "full-setup" ]
	then
		# Check if crontab exists
		if ! func_USER_CRONTAB_EXISTS "$CRONTAB_LINE"
		then
			>&2 echo "WARNING: No user crontab for root found (see \"crontab -l\"). Run following command to setup it automatically:"
			>&2 echo "  ${0} setup-crontab\n"
		fi

		# Check if firewall startup script exists
		if [ ! -f "$STARTUP_SCRIPT_PATH" ]
		then
			>&2 echo "WARNING: No startup script found. Run following command to setup it automatically:"
			>&2 echo "  ${0} setup-startupscript\n"
		fi
	fi
fi

case "$CMD" in

	# Show full ruleset
	show)
		nft -nn list ruleset
	;;
	
	# For crontabs only
	cron)
		$0 update
	;;
	
	# Shorthand for all setup commands
	full-setup)
		$0 setup-crontab 2> /dev/null
		$0 setup-startupscript 2> /dev/null
	;;
	
	# Setups user crontab if not exists
	setup-crontab)
		if func_USER_CRONTAB_EXISTS "$CRONTAB_LINE"
		then
			>&2 echo "Crontab already exists:"
			>&2 echo "  " "`crontab -l 2>/dev/null | grep "$CRONTAB_COMMAND\$"`"
		else
			if func_ADD_USER_CRONTAB "$CRONTAB_LINE"
			then
				echo "Crontab for current user added:"
				echo "  $CRONTAB_LINE"
			fi
		fi
	;;
	
	# Setups the firewall startup script to keep ruleset after reboot
	setup-startupscript)
		if [ -f $STARTUP_SCRIPT_PATH ]
		then
			>&2 echo "Startup script already exists:"
			>&2 echo "  $STARTUP_SCRIPT_PATH"
		else
			echo "$STARTUP_SCRIPT_CONTENT" > $STARTUP_SCRIPT_PATH
			chmod 0755 $STARTUP_SCRIPT_PATH
			
			echo "Startup script created:"
			echo "  $STARTUP_SCRIPT_PATH"
		fi
	;;
	
	# Used for startup script after reboot
	init)
		$0 full-reload
	;;
	
	# Update whitelists or do a
	# full reload of all rules
	update|full-reload)

		# We need this to replace some __VARIABLES__ in the template files
		func_SUBSTITUTIONS() {
			CONTENT=$1
			
			# The interval flag (concatenated sets with more than one type) may be not supported,
			# so we only set it if support is guaranteed (nftables >= 0.9.4). Blacklists are not
			# affected, since they do not concatenate anything.
			if func_ARE_CONCATENATED_SETS_SUPPORTED
			then
				INTERVAL_FLAG_IF_SUPPORTED=" flags interval;"
			else
				INTERVAL_FLAG_IF_SUPPORTED=""
			fi
			
			CONTENT=`echo "$CONTENT" | sed "s/__INTERVAL_FLAG_IF_SUPPORTED_/$INTERVAL_FLAG_IF_SUPPORTED/g"`
			
			echo "$CONTENT"
		}

		# Ensure default preset is enabled
		if ! ls $ENABLED_PRESETS_PATH/*default* >/dev/null 2>&1
		then
			func_EXIT_ERROR 1 "No default preset enabled."
		fi

		# Check if IPv6 is enabled
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
		
		# Include whitelist and blacklist generating functions
		. ./inc/_whiteblacklists.sh
		
		# Update only (reloads whitelist and blacklist)
		if [ "$CMD" = "update" ]
		then
		
			if [ "`nft list ruleset`" = "" ]
			then
				func_EXIT_ERROR 1 "No ruleset loaded. Run \"${0} full-reload\"."
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
			
		elif [ "$CMD" = "full-reload" ]
		then

			# Temporary ruleset file which is later
			# used to atomically reload the ruleset
			TMP_RULESET_FILE="$TMP_PATH/ruleset"
			
			echo -n "" > $TMP_RULESET_FILE
			
			echo "#!/usr/sbin/nft -f" >> $TMP_RULESET_FILE
			echo "flush ruleset" >> $TMP_RULESET_FILE

			# Apply all presets
			for PRESET in `ls $ENABLED_PRESETS_PATH`
			do
				echo "" >> $TMP_RULESET_FILE
			
				# Apply replacements and append to ruleset file
				func_SUBSTITUTIONS "`cat $ENABLED_PRESETS_PATH/$PRESET`" >> $TMP_RULESET_FILE
			done

			# Re-generate whitelist and blacklist
			if ! GENERATED=`func_CREATE_WHITE_OR_BLACKLIST_TEMPLATE whitelist generate $IP_VERSIONS`
			then
				func_EXIT_ERROR 1 "ERROR: Failed to generate whitelist."
			else
				echo "$GENERATED" >> $TMP_RULESET_FILE
			fi
			
			if ! GENERATED=`func_CREATE_WHITE_OR_BLACKLIST_TEMPLATE blacklist generate $IP_VERSIONS`
			then
				func_EXIT_ERROR 1 "ERROR: Failed to generate blacklist."
			else
				echo "$GENERATED" >> $TMP_RULESET_FILE
			fi
			
			# Append additional rules
			cat $ADDITIONAL_RULES_FILE >> $TMP_RULESET_FILE
			
			if [ "$OPT_DRY_RUN" = 1 ]
			then
				>&2 echo "DRY-RUN: Successfully generated rulset (nft ruleset was *not* updated):\n  $TMP_RULESET_FILE"
			else
				if nft -f $TMP_RULESET_FILE
				then
					rm $TMP_RULESET_FILE
				fi
			fi
		
		fi
		
	;;
	
	*)
		func_EXIT_ERROR 1 "`func_USAGE`"
    ;;
	
esac

# Delete .tmp dir if empty
if [ ! "$OPT_DRY_RUN" = 1 ]
then
	rmdir $TMP_PATH 2>/dev/null
fi

exit 0
