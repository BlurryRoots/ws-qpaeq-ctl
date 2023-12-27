#!/bin/bash

# https://www.freedesktop.org/wiki/Software/PulseAudio/Documentation/User/Equalizer/
# Consider integrating https://gist.github.com/leogama/35961ec0d279e6cf409f783c3851569e
qpaeq-ctl () {
	# Utility script to manage alsa equalizer 'qpaeq' (e.g. deb pulseaudio-equalizer)
	# More info about 'qpaeq' at:
	# https://www.freedesktop.org/wiki/Software/PulseAudio/Documentation/User/Equalizer/
	#
	#
	# Copyright (c) 2023 Sven Freiberg
	#
	# Permission is hereby granted, free of charge, to any person obtaining a
	# copy of this software and associated documentation files (the “Software”),
	# to deal in the Software without restriction, including without limitation
	# the rights to use, copy, modify, merge, publish, distribute, sublicense,
	# and/or sell copies of the Software, and to permit persons to whom the
	# Software is furnished to do so, subject to the following conditions:
	#
	# The above copyright notice and this permission notice shall be included
	# in all copies or substantial portions of the Software.
	#
	# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS
	# OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
	# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
	# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
	# OTHER DEALINGS IN THE SOFTWARE.
	#
	#
	# Usage:
	#
	# Switch to equalizer:
	# 	qpaeq-ctl activate
	#		- Loads modules
	#		- Checks current sink and stores it at ~/.config/pulse/qpaeq-ctl.cache
	#		- Sets sink to equalizer
	# Check if equalizer is active:
	# 	qpaeq-ctl is-active
	# Deactivate and switch back to default / previous sink:
	# 	qpaeq-ctl deactivate
	#		- Resets sink to either ~/.config/pulse/qpaeq-ctl.cache or first available
	#		- Unloads modules
	# 
	# Open equalizer GUI:
	# 	qpaeq-ctl open
	# Check if GUI is running (and get its PID):
	# 	qpaeq-ctl get-pid
	# Close GUI:
	# 	qpaeq-ctl close
	#
	# Manuall load / unload modules:
	# 	qpaeq-ctl modules-(load | unload) 
	#
	# Query the name of the equalizer sink:
	# 	qpaeq-ctl get-equalizer-sink
	#
	# Ask pulseaudio to load equalizer modules on startup:
	# 	qpaeq-ctl install
	# 	qpaeq-ctl uninstall
	#

	if ! which pactl > /dev/null; then
		echo "Cannot find pactl."
		return 1
	fi

	if ! which qpaeq > /dev/null; then
		echo "Cannot find qpaeq."
		return 1
	fi

	local selfabs="${0}"
	local self="$(basename ${selfabs})"
	local cmd="${1}"
	local configfile="${HOME}/.config/pulse/default.pa"
	local cachefile="${HOME}/.config/pulse/${self}.cache"
	local module_sink=module-equalizer-sink
	local module_dbus=module-dbus-protocol
	local python_split_src="
import sys
c = ''
for x in sys.stdin:
	c += x.strip()
r = c.split(':')
if 2 != len(r):
	sys.stderr.write('Nothing there.\n')
	exit (1)

sys.stdout.write(f'{r[0]}')
exit(0)
"

	case ${cmd} in
		activate)
			${selfabs} is-active > /dev/null && {
				echo "Equalizer already active."
				return 1
			}

			echo "Checking modules ..."
			if ! ${selfabs} modules-load; then
				echo "Aborting ..."
				return 1
			fi

			if ! ${selfabs} get-equalizer-sink > /dev/null; then
				echo "Cannot find equalizer sink."
				return 1
			fi

			local equalizersink="$(${selfabs} get-equalizer-sink)"
			local activesink="$(pactl info \
				| grep -i "default sink" \
				| awk '{ print $3 }')"
			
			if [ 0 -eq ${#activesink} ]; then
				echo "Error: Could not find any active/default sink!"
				return 1
			fi

			echo "Remembering current sink (${activesink}) ..."
			echo ${activesink} > ${cachefile}

			echo "Changing sink to: ${equalizersink} ..."
			if ! pactl set-default-sink ${equalizersink}; then
				echo "Panic!"
				return 1
			fi
		;;

		deactivate)
			local deactivated=0

			if ${selfabs} is-active > /dev/null; then
				local defaultsink=""

				if [ -e ${cachefile} ]; then
					echo "Using cached default sink ..."
					defaultsink=$(cat ${cachefile})
				else
					echo "Using first available sink ..."
					defaultsink="$(pactl list sinks short \
						| awk '/0\t/ { print $2 }')"
				fi

				echo "Changing sink to: ${defaultsink} ..."
				if ! pactl set-default-sink ${defaultsink}; then
					echo "Panic!"
					return 1
				fi
			
				echo "Unloading modules ..."
				${selfabs} modules-unload
			else
				local activesink="$(pactl info \
					| grep -i "default sink" \
					| awk '{ print $3 }' \
				)"
				echo "Equalizer not active. (Active sink: ${activesink})"
				deactivated=1
			fi

			return ${deactivated}
		;;

		is-active)
			local equalizersink="$(${selfabs} get-equalizer-sink)"
			local activesink="$(pactl info \
				| grep -i "default sink" \
				| awk '{ print $3 }' \
			)"
			
			[[ ${activesink} == ${equalizersink} ]] && {
				echo "Equalizer active."
				return 0
			} || {
				echo "Equalizer off. Sink: ${activesink}"
				return 1
			}
		;;

		get-equalizer-sink)
			local equalizersink="$(pactl list sinks short \
				| awk '/equalizer/ { print $2 }' \
			)"
			echo ${equalizersink}

			if [ 0 -eq ${#equalizersink} ]; then
				return 1
			fi
			
			return 0
		;;

		modules-load)
			echo "Checking sink module ..."
			if ! pactl list modules | grep -iq ${module_sink}; then
				echo "Loading sink module ..."
				if ! pactl load-module ${module_sink}; then
					return 1
				fi
			fi

			echo "Checking dbus module ..."
			if ! pactl list modules | grep -iq ${module_dbus}; then
				echo "Loading dbus module ..."
				if ! pactl load-module ${module_dbus}; then
					return 1
				fi
			fi

			return 0
		;;

		modules-unload)
			echo "Checking sink module ..."
			if pactl list modules | grep -iq $module_sink; then
				echo "Unloading sink module ..."
				pactl unload-module ${module_sink}
			else
				echo "Not loaded. Skipping."
			fi

			echo "Checking dbus module ..."
			if pactl list modules | grep -iq ${module_dbus}; then
				echo "Unloading dbus module ..."
				pactl unload-module ${module_dbus}
			else
				echo "Not loaded. Skipping."
			fi
		;;

		open)
			if ! ${selfabs} is-active > /dev/null; then
				echo "Equalizer not activated."
				return 1
			fi

			if ${selfabs} get-pid > /dev/null; then
				echo "GUI application already running."
				return 1
			fi

			qpaeq&

			if [ 0 -ne $? ] ; then
				echo "Unable to open qpaep. Please check if all modules are properly loaded."
				return 1
			fi

			return 0
		;;

		close)
			local qpaeqpid="$(${selfabs} get-pid)"

			if [ 0 -eq ${#qpaeqpid} ]; then
				echo "Could not find any qpaeq instance running."
			else
				echo "Asking ${qpaeqpid} to quit ..."
				if ! kill -9 ${qpaeqpid} > /dev/null; then
					echo "Could not close qpaeq."
					return 1
				fi
			fi

			return 0
		;;

		get-pid)
			local qpaeqpath="$(which qpaeq)"
			local qpaeqpid="$(ps aux | grep -E "(.*)${qpaeqpath}" | grep -v grep | awk '{ print $2 }')"

			echo "${qpaeqpid}"

			if [ 0 -eq ${#qpaeqpid} ]; then
				return 1
			fi

			return 0
		;;

		install)
			if ! ${selfabs} modules-load; then
				echo "Error: Cannot load equalizer module. Aborting."
				return 1
			fi

			echo "Installing ${configfile} ..."

			if [ -e ${configfile} ]; then
				echo "Checking sink module ..."
				if ! grep -qF "load-module $module_sink" ${configfile}; then
					echo "Adding sink module ..."
					echo "load-module $module_sink" | tee -a ${configfile}
				fi
				
				echo "Checking dbus module ..."
				if ! grep -qF "load-module $module_dbus" ${configfile}; then
					echo "Adding dbus module ..."
					echo "load-module $module_dbus" | tee -a ${configfile}
				fi
			else
				echo "Creating config at ${configfile} ..."
				touch ${configfile}
				
				echo "load-module $module_sink" | tee -a ${configfile}
				echo "load-module $module_dbus" | tee -a ${configfile}
			fi
		;;

		uninstall)
			if [ -e ${configfile} ]; then
				echo "Checking sink module ..."
				grep -nF "load-module $module_sink" ${configfile} \
					| python3 -c $python_split_src \
					| xargs -I{} bash -c "sed -i '{}d' ${configfile}" \
						&& echo "Done." \
						|| echo "Failed removal."
				
				echo "Checking dbus module ..."
				grep -nF "load-module $module_dbus" ${configfile} \
					| python3 -c $python_split_src \
					| xargs -I{} bash -c "sed -i '{}d' ${configfile}" \
						&& echo "Done." \
						|| echo "Failed removal."
			else
				echo "No installation detected."
				return 1
			fi
		;;

		*)
			local usage="USAGE: ${self} <options> [command] [arguments]"
			usage="${usage}\ncommands:"
			usage="${usage}\n\tactivate"
			usage="${usage}\n\tdeactivate"
			usage="${usage}\n\tis-active"
			usage="${usage}\n\tget-equalizer-sink"
			usage="${usage}\n\tmodules-load"
			usage="${usage}\n\tmodules-unload"
			usage="${usage}\n\topen"
			usage="${usage}\n\tclose"
			usage="${usage}\n\tinstall"
			usage="${usage}\n\tuninstall"

			printf "%b" "${usage}"

			return 1
		;;
	esac

	return $?
}

qpaeq-ctl $*
