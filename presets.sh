#!/bin/sh
: '''
Copyright (c) 2020-22 etkaar <https://github.com/etkaar/nftm>

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
cd $ABSPATH

CONF_PATH="$ABSPATH/conf"
PRESETS_PATH="$CONF_PATH/presets"

AVAILABLE_PRESETS_PATH="$PRESETS_PATH/available"
ENABLED_PRESETS_PATH="$PRESETS_PATH/enabled"

# Ensure only root runs this command
if [ ! `whoami` = "root" ]
then
	>&2 echo "You need to run this command as root (or use sudo)."
	exit 1
fi

# Command (enable custom minecraft, ...)
CMD=$1

case "$CMD" in

	list)
		# Number of presets
		TOTAL_AVAILABLE_PRESETS=`ls $AVAILABLE_PRESETS_PATH | wc -l`
		TOTAL_ENABLED_PRESETS=`ls $ENABLED_PRESETS_PATH | wc -l`
		
		echo "Presets"
		echo "  Available: $TOTAL_AVAILABLE_PRESETS"
		echo "  Enabled: $TOTAL_ENABLED_PRESETS"

		# Show all available presets
		if [ $TOTAL_AVAILABLE_PRESETS -gt 0 ]
		then
			echo "\nAvailable presets"
			
			for PRESET in `ls $AVAILABLE_PRESETS_PATH`
			do
				echo "  $PRESET"
			done
			
			echo ""
			echo "  Note: Use \"${0} enable custom [name]\" to enable custom preset."
		fi
		
		# Show all enabled presets
		if [ $TOTAL_ENABLED_PRESETS -gt 0 ]
		then
			echo "\nEnabled presets"
			
			for PRESET in `ls $ENABLED_PRESETS_PATH`
			do
				echo "  $PRESET"
			done
		fi
	;;
	
	status|enable|disable)
		# Preset type
		PRESET_TYPE=$2
		
		if [ "$PRESET_TYPE" = "" ]
		then
			>&2 echo "No preset type provided."
			exit 1
		elif [ ! "$PRESET_TYPE" = "default" ] && [ ! "$PRESET_TYPE" = "custom" ]
		then
			>&2 echo "Invalid preset type '$PRESET_TYPE'."
			exit 1
		fi
		
		# Preset name
		PRESET_NAME=$3
		
		if [ "$PRESET_NAME" = "" ]
		then
			>&2 echo "No preset name provided."
			exit 1
		fi
	
		# Prefix
		if [ "$PRESET_TYPE" = "default" ]
		then
			PREFIX="01"
		elif [ "$PRESET_TYPE" = "custom" ]
		then
			PREFIX="20"
		fi
		
		# Filename
		PRESET_FILENAME="$PRESET_TYPE.$PRESET_NAME"
		
		AVAILABLE_PRESET_PATH="$AVAILABLE_PRESETS_PATH/$PRESET_FILENAME.txt"
		ENABLED_PRESET_PATH="$ENABLED_PRESETS_PATH/${PREFIX}${PRESET_FILENAME}.txt"
		
		# Return status only
		if [ "$CMD" = "status" ]
		then
		
			if [ ! -f $AVAILABLE_PRESET_PATH ]
			then
				>&2 echo "Preset '$PRESET_FILENAME' was not found."
				exit 2
			fi
		
			if [ -f $ENABLED_PRESET_PATH ]
			then
				echo "Preset '$PRESET_FILENAME' is enabled."
				exit 0
			else
				echo "Preset '$PRESET_FILENAME' is disabled."
				exit 1
			fi
		
		fi
		
		# Checks
		if [ "$CMD" = "enable" ]
		then
		
			if [ ! -f $AVAILABLE_PRESET_PATH ]
			then
				>&2 echo "Preset '$PRESET_FILENAME' was not found."
				exit 1
			fi
			
			if [ -f $ENABLED_PRESET_PATH ]
			then
				>&2 echo "Preset '$PRESET_FILENAME' is already enabled."
				exit 1
			fi
			
			# Prevent enabling of multiple default presets
			if [ "$PRESET_TYPE" = "default" ]
			then
				if ls $ENABLED_PRESETS_PATH/${PREFIX}* >/dev/null 2>&1
				then
					>&2 echo "Cannot enable multiple default presets."
					exit 1
				fi
			fi
			
		elif [ "$CMD" = "disable" ]
		then
			
			if [ ! -f $ENABLED_PRESET_PATH ]
			then
				>&2 echo "Preset '$PRESET_FILENAME' is not enabled."
				exit 1
			fi
			
		fi
		
		# Enable/disable presets using symbolic links
		if [ "$CMD" = "enable" ]
		then
		
			if ln -s $AVAILABLE_PRESET_PATH $ENABLED_PRESET_PATH
			then
				echo "Enabled preset '$PRESET_FILENAME'."
			fi
			
		elif [ "$CMD" = "disable" ]
		then
		
			if rm $ENABLED_PRESET_PATH
			then
				echo "Disabled preset '$PRESET_FILENAME'."
			fi
			
		fi
	;;
	
	*)
		>&2 echo "Usage: ${0} {list|status [preset]|enable [preset]|disable [preset]}"
		exit 1
    ;;
	
esac

exit 0
