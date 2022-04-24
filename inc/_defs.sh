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

# Notes
: """
	local VAR
		The local keyword is not POSIX-compliant, therefore not used. Instead,
		if required and where suitable, we make use of a subshell.
"""

# If colors are enabled
func_COLORS_ENABLED() {
	return 0
}

# Message to STDERR
func_STDERR() {
	# Subshell
	(
		MESSAGE="$1"
		NO_LINE_BREAK="$2"
		NO_COLORS="$3"
		
		if func_COLORS_ENABLED && [ "$NO_COLORS" != "1" ]
		then
			# Red
			>&2 echo -n "\e[0;31m"
		fi
		
		if [ "$NO_LINE_BREAK" = "1" ]
		then
			>&2 echo -n "$MESSAGE"
		else
			>&2 echo "$MESSAGE"
		fi
		
		if func_COLORS_ENABLED && [ "$NO_COLORS" != "1" ]
		then
			>&2 echo -n "\e[m"
		fi
	)
}

# Prints error message to stderr and exit
func_EXIT_ERROR() {
	# Subshell
	(
		EXIT_CODE="$1"
		MESSAGE="$2"
		NO_COLORS="$3"
		
		func_STDERR "$MESSAGE" 0 "$NO_COLORS"
		
		return "$EXIT_CODE"
	)
	
	exit "$?"
}

# Check if string is an unsigned integer (so both +1 and -1 is not considered as be valid)
func_IS_UNSIGNED_INTEGER() {
	NUMBER="$1"
	
	case "$NUMBER" in
		*[!0-9]* | '')
			return 1
		;;
	esac
	
	return 0
}

# Check if string is an signed *or* unsigned integer
func_IS_INTEGER() {
	NUMBER="$1"
	
	# Remove leading - or +
	func_IS_UNSIGNED_INTEGER ${NUMBER#[-+]}
}

# Check if string is a valid hexadecimal number
func_IS_HEX() {
	STRING="$1"
	
	case "$STRING" in
		*[!0-9a-fA-F]* | '')
			return 1
		;;
	esac
	
	return 0
}

# Get number of occurrences (n) of a substring (needle) in another string (haystack) 
func_SUBSTR_COUNT() {
	SUBSTRING="$1"
	STRING="$2"
	
	echo "$STRING" | awk -F"$SUBSTRING" '{print NF-1}'
}

# Get nftables version integer
func_GET_NFT_VERSION_INTEGER() {
	func_VERSION_STRING_TO_INTEGER 3 $(echo "`nft --version`" | awk '{print $2}')
}

# Converts a version string such as "v0.9.0" to an integer to allow comparisons.
#
#	BEWARE:	If you simply convert it to an integer by removing leading zeros and the
#			dots (.), "v0.20.3" (= 203) would be considered as newer version than
#			"v1.2.3" (= 123). Thats why we need to apply a factor with a difference
#			of (* 1'000) to the single digits 1, 2, 3 of 1'000'000, 1'000 and 1.
#
func_VERSION_STRING_TO_INTEGER() {
	# Remove whitespaces and the leading 'v'
	MIN_MAX_DIGITS="$1"
	VERSION_STRING=`echo "$2" | tr -d 'v[:space:]'`
	
	echo "$VERSION_STRING" "$MIN_MAX_DIGITS" | awk '{
		digits_min = $2
		digits_max = $2
		digits_count = split($1, digits, ".")
		
		if (digits_count < digits_min) {
			for (i = (digits_count + 1); i <= digits_min; i++) {
				digits[i] = 0
			}
			
			digits_count = digits_min
		} else if (digits_count > digits_max) {
			print(0)
			exit 1
		}
		
		version_integer = 0
		
		for (i in digits) {
			if (digits[i] > 999) {
				print(0)
				exit 1
			}
			
			version_integer += (1000 ^ (digits_count - i)) * digits[i];
		}
		
		print(version_integer)
	}'
}

# Check if user crontab exists
func_USER_CRONTAB_EXISTS() {
	CRONTAB_LINE="$1"
	
	COMMAND=`echo "$CRONTAB_LINE" | cut -d' ' -f6-`
	LINE=`crontab -l 2>/dev/null | grep "$COMMAND\$"`
	
	if [ ! "$LINE" = "" ]
	then
		return 0
	else
		return 1
	fi
}

# Add user crontab if not exists
func_ADD_USER_CRONTAB() {
	CRONTAB_LINE="$1"
	(crontab -l 2>/dev/null; echo "$CRONTAB_LINE") | crontab -
}

# This is a workaround, because neither <IFS=\'n'> or <IFS=$(printf '\n')> will work in Dash
func_SET_IFS() {
	NEW_IFS="$1"

	eval "$(printf "IFS='$NEW_IFS'")"
}

# Don't forget to unset after using func_SET_IFS() if not executed within a subshell
func_RESTORE_IFS() {
	unset IFS
}
