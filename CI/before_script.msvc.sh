#!/bin/bash
# set -x  # turn-on for debugging

function wrappedExit {
	if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
		exit $1
	else
		return $1
	fi
}

MISSINGTOOLS=0

WORKINGDIR="$(pwd)"
case "$WORKINGDIR" in
	*[[:space:]]*)
		echo "Error: Working directory contains spaces."
		wrappedExit 1
		;;
esac

set -euo pipefail

function windowsPathAsUnix {
	if command -v cygpath >/dev/null 2>&1; then
		cygpath -u $1
	else
		echo "$1" | sed "s,\\\\,/,g" | sed "s,\(.\):,/\\1,"
	fi
}

function unixPathAsWindows {
	if command -v cygpath >/dev/null 2>&1; then
		cygpath -w $1
	else
		echo "$1" | sed "s,^/\([^/]\)/,\\1:/," | sed "s,/,\\\\,g"
	fi
}

APPVEYOR=${APPVEYOR:-}
CI=${CI:-}
STEP=${STEP:-}

VERBOSE=""
STRIP=""
VS_VERSION=""
NMAKE=""
NINJA=""
PDBS=""
PLATFORM=""
CONFIGURATIONS=()
INSTALL_PREFIX="./install"

ACTIVATE_MSVC=""
SINGLE_CONFIG=""

while [ $# -gt 0 ]; do
	ARGSTR=$1
	shift

	if [ ${ARGSTR:0:1} != "-" ]; then
		echo "Unknown argument $ARGSTR"
		echo "Try '$0 -h'"
		wrappedExit 1
	fi

	for (( i=1; i<${#ARGSTR}; i++ )); do
		ARG=${ARGSTR:$i:1}
		case $ARG in
			V )
				VERBOSE=true ;;

			d )
				SKIP_DOWNLOAD=true ;;

			e )
				SKIP_EXTRACT=true ;;

			v )
				VS_VERSION=$1
				shift ;;

			n )
				NMAKE=true ;;
			
			N )
				NINJA=true ;;

			p )
				PLATFORM=$1
				shift ;;

			P )
				PDBS=true ;;

			c )
				CONFIGURATIONS+=( $1 )
				shift ;;

			i )
				INSTALL_PREFIX=$(echo "$1" | sed 's;\\;/;g' | sed -E 's;/+;/;g')
				shift ;;

			h )
				cat <<EOF
Usage: $0 [-chpvnNVi]
Options:
	-c <Release/Debug/RelWithDebInfo>
		Set the configuration, can also be set with environment variable CONFIGURATION.
		For mutli-config generators, this is ignored, and all configurations are set up.
		For single-config generators, several configurations can be set up at once by specifying -c multiple times.
	-h
		Show this message.
	-p <Win32/Win64>
		Set the build platform, can also be set with environment variable PLATFORM.
	-u
		Configure for unity builds.
	-v <2017/2019>
		Choose the Visual Studio version to use.
	-n
		Produce NMake makefiles instead of a Visual Studio solution. Cannot be used with -N.
	-N
		Produce Ninja (multi-config if CMake is new enough to support it) files instead of a Visual Studio solution. Cannot be used with -n..
	-V
		Run verbosely
	-i
		CMake install prefix
EOF
				wrappedExit 0
				;;

			* )
				echo "Unknown argument $ARG."
				echo "Try '$0 -h'"
				wrappedExit 1 ;;
		esac
	done
done

if [ -n "$NMAKE" ] || [ -n "$NINJA" ]; then
	if [ -n "$NMAKE" ] && [ -n "$NINJA" ]; then
		echo "Cannot run in NMake and Ninja mode at the same time."
		wrappedExit 1
	fi
	ACTIVATE_MSVC=true
fi

if [ -z $VERBOSE ]; then
	STRIP="> /dev/null 2>&1"
fi

if [ -z $APPVEYOR ]; then
	echo "Running prebuild outside of Appveyor."

	DIR=$(windowsPathAsUnix "${BASH_SOURCE[0]}")
	cd $(dirname "$DIR")/..
else
	echo "Running prebuild in Appveyor."

	cd "$APPVEYOR_BUILD_FOLDER"
fi

run_cmd() {
	CMD="$1"
	shift

	if [ -z $VERBOSE ]; then
		RET=0
		eval $CMD $@ > output.log 2>&1 || RET=$?

		if [ $RET -ne 0 ]; then
			if [ -z $APPVEYOR ]; then
				echo "Command $CMD failed, output can be found in $(real_pwd)/output.log"
			else
				echo
				echo "Command $CMD failed;"
				cat output.log
			fi
		else
			rm output.log
		fi

		return $RET
	else
		RET=0
		eval $CMD $@ || RET=$?
		return $RET
	fi
}

real_pwd() {
	if type cygpath >/dev/null 2>&1; then
		cygpath -am "$PWD"
	else
		pwd # not git bash, Cygwin or the like
	fi
}

CMAKE_OPTS=""
add_cmake_opts() {
	CMAKE_OPTS="$CMAKE_OPTS $@"
}

if [ -z $PLATFORM ]; then
	PLATFORM="$(uname -m)"
fi

if [ -z $VS_VERSION ]; then
	VS_VERSION="2017"
fi

case $VS_VERSION in
	16|16.0|2019 )
		GENERATOR="Visual Studio 16 2019"
		TOOLSET="vc142"
		MSVC_REAL_VER="16"
		MSVC_VER="14.2"
		MSVC_YEAR="2015"
		MSVC_REAL_YEAR="2019"
		MSVC_DISPLAY_YEAR="2019"
		BOOST_VER="1.71.0"
		BOOST_VER_URL="1_71_0"
		BOOST_VER_SDK="107100"
		;;

	15|15.0|2017 )
		GENERATOR="Visual Studio 15 2017"
		TOOLSET="vc141"
		MSVC_REAL_VER="15"
		MSVC_VER="14.1"
		MSVC_YEAR="2015"
		MSVC_REAL_YEAR="2017"
		MSVC_DISPLAY_YEAR="2017"
		BOOST_VER="1.67.0"
		BOOST_VER_URL="1_67_0"
		BOOST_VER_SDK="106700"
		;;

	14|14.0|2015 )
		echo "Visual Studio 2015 is no longer supported"
		wrappedExit 1
		;;

	12|12.0|2013 )
		echo "Visual Studio 2013 is no longer supported"
		wrappedExit 1
		;;
esac

case $PLATFORM in
	x64|x86_64|x86-64|win64|Win64 )
		ARCHNAME="x86-64"
		ARCHSUFFIX="64"
		BITS="64"
		;;

	x32|x86|i686|i386|win32|Win32 )
		ARCHNAME="x86"
		ARCHSUFFIX="86"
		BITS="32"
		;;

	* )
		echo "Unknown platform $PLATFORM."
		wrappedExit 1
		;;
esac

if [ $BITS -eq 64 ] && [ $MSVC_REAL_VER -lt 16 ]; then
	GENERATOR="${GENERATOR} Win64"
fi

if [ -n "$NMAKE" ]; then
	GENERATOR="NMake Makefiles"
	SINGLE_CONFIG=true
fi

if [ -n "$NINJA" ]; then
	GENERATOR="Ninja Multi-Config"
	if ! cmake -E capabilities | grep -F "$GENERATOR" > /dev/null; then
		SINGLE_CONFIG=true
		GENERATOR="Ninja"
	fi
fi

if [ -n "$SINGLE_CONFIG" ]; then
	if [ ${#CONFIGURATIONS[@]} -eq 0 ]; then
		if [ -n "${CONFIGURATION:-}" ]; then
			CONFIGURATIONS=("$CONFIGURATION")
		else
			CONFIGURATIONS=("Debug")
		fi
	elif [ ${#CONFIGURATIONS[@]} -ne 1 ]; then
		# It's simplest just to recursively call the script a few times.
		RECURSIVE_OPTIONS=()
		if [ -n "$VERBOSE" ]; then
			RECURSIVE_OPTIONS+=("-V")
		fi
		if [ -n "$NMAKE" ]; then
			RECURSIVE_OPTIONS+=("-n")
		fi
		if [ -n "$NINJA" ]; then
			RECURSIVE_OPTIONS+=("-N")
		fi
		if [ -n "$PDBS" ]; then
			RECURSIVE_OPTIONS+=("-P")
		fi
		RECURSIVE_OPTIONS+=("-v $VS_VERSION")
		RECURSIVE_OPTIONS+=("-p $PLATFORM")
		RECURSIVE_OPTIONS+=("-i '$INSTALL_PREFIX'")

		for config in ${CONFIGURATIONS[@]}; do
			$0 ${RECURSIVE_OPTIONS[@]} -c $config
		done

		wrappedExit 1
	fi
else
	if [ ${#CONFIGURATIONS[@]} -ne 0 ]; then
		echo "Ignoring configurations argument - generator is multi-config"
	fi
	CONFIGURATIONS=("Release" "Debug" "RelWithDebInfo")
fi

for i in ${!CONFIGURATIONS[@]}; do
	case ${CONFIGURATIONS[$i]} in
		debug|Debug|DEBUG )
			CONFIGURATIONS[$i]=Debug
			;;

		release|Release|RELEASE )
			CONFIGURATIONS[$i]=Release
			;;

		relwithdebinfo|RelWithDebInfo|RELWITHDEBINFO )
			CONFIGURATIONS[$i]=RelWithDebInfo
			;;
	esac
done

if [ $MSVC_REAL_VER -ge 16 ] && [ -z "$NMAKE" ] && [ -z "$NINJA" ]; then
	if [ $BITS -eq 64 ]; then
		add_cmake_opts "-G\"$GENERATOR\" -A x64"
	else
		add_cmake_opts "-G\"$GENERATOR\" -A Win32"
	fi
else
	add_cmake_opts "-G\"$GENERATOR\""
fi

if [ -n "$SINGLE_CONFIG" ]; then
	add_cmake_opts "-DCMAKE_BUILD_TYPE=${CONFIGURATIONS[0]}"
fi

echo
echo "==================================="
echo "Starting prebuild on MSVC${MSVC_DISPLAY_YEAR} WIN${BITS}"
echo "==================================="
echo

# Set up dependencies
BUILD_DIR="MSVC${MSVC_DISPLAY_YEAR}_${BITS}"

if [ -n "$NMAKE" ]; then
	BUILD_DIR="${BUILD_DIR}_NMake"
elif [ -n "$NINJA" ]; then
	BUILD_DIR="${BUILD_DIR}_Ninja"
fi

if [ -n "$SINGLE_CONFIG" ]; then
	BUILD_DIR="${BUILD_DIR}_${CONFIGURATIONS[0]}"
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

echo
echo "Setting up CrabNet build..."
add_cmake_opts -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}"
add_cmake_opts -DCRABNET_ENABLE_STATIC=TRUE -DCRABNET_ENABLE_DLL=FALSE

if [ -n "$ACTIVATE_MSVC" ]; then
	echo -n "- Activating MSVC in the current shell... "
	command -v vswhere >/dev/null 2>&1 || { echo "Error: vswhere is not on the path."; wrappedExit 1; }

	# There are so many arguments now that I'm going to document them:
	# * products: allow Visual Studio or standalone build tools
	# * version: obvious. Awk helps make a version range by adding one.
	# * property installationPath: only give the installation path.
	# * latest: return only one result if several candidates exist. Prefer the last installed/updated
	# * requires: make sure it's got the MSVC compiler instead of, for example, just the .NET compiler. The .x86.x64 suffix means it's for either, not that it's the x64 on x86 cross compiler as you always get both
	MSVC_INSTALLATION_PATH=$(vswhere -products '*' -version "[$MSVC_REAL_VER,$(awk "BEGIN { print $MSVC_REAL_VER + 1; exit }"))" -property installationPath -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64)
	if [ -z "$MSVC_INSTALLATION_PATH" ]; then
		echo "vswhere was unable to find MSVC $MSVC_DISPLAY_YEAR"
		wrappedExit 1
	fi
	
	echo "@\"${MSVC_INSTALLATION_PATH}\Common7\Tools\VsDevCmd.bat\" -no_logo -arch=$([ $BITS -eq 64 ] && echo "amd64" || echo "x86") -host_arch=$([ $(uname -m) == 'x86_64' ] && echo "amd64" || echo "x86")" > ActivateMSVC.bat
	
	cp "../CI/activate_msvc.sh" .
	sed -i "s/\$MSVC_DISPLAY_YEAR/$MSVC_DISPLAY_YEAR/g" activate_msvc.sh
	source ./activate_msvc.sh
	
	cp "../CI/ActivateMSVC.ps1" .
	sed -i "s/\$MSVC_DISPLAY_YEAR/$MSVC_DISPLAY_YEAR/g" ActivateMSVC.ps1

	echo "done."
	echo
fi

if [ -z $VERBOSE ]; then
	printf -- "- Configuring... "
else
	echo "- cmake .. $CMAKE_OPTS"
fi
RET=0
run_cmd cmake .. $CMAKE_OPTS || RET=$?
if [ -z $VERBOSE ]; then
	if [ $RET -eq 0 ]; then
		echo Done.
	else
		echo Failed.
	fi
fi
if [ $RET -ne 0 ]; then
	wrappedExit $RET
fi

echo "Script completed successfully."
echo "You now have an OpenMW build system at $(unixPathAsWindows "$(pwd)")"

if [ -n "$ACTIVATE_MSVC" ]; then
	echo
	echo "Note: you must manually activate MSVC for the shell in which you want to do the build."
	echo
	echo "Some scripts have been created in the build directory to do so in an existing shell."
	echo "Bash: source activate_msvc.sh"
	echo "CMD: ActivateMSVC.bat"
	echo "PowerShell: ActivateMSVC.ps1"
	echo
	echo "You may find options to launch a Development/Native Tools/Cross Tools shell in your start menu or Visual Studio."
	echo
	if [ $(uname -m) == 'x86_64' ]; then
		if [ $BITS -eq 64 ]; then
			inheritEnvironments=msvc_x64_x64
		else
			inheritEnvironments=msvc_x64
		fi
	else
		if [ $BITS -eq 64 ]; then
			inheritEnvironments=msvc_x86_x64
		else
			inheritEnvironments=msvc_x86
		fi
	fi
	echo "In Visual Studio 15.3 (2017 Update 3) or later, try setting '\"inheritEnvironments\": [ \"$inheritEnvironments\" ]' in CMakeSettings.json to build in the IDE."
fi

wrappedExit $RET
