#!/bin/bash

## Config
VIRSH_DOMAIN="win10-dev"
SSH_NAME="dev-machine"
#DEF_MSBUILD='C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\MSBuild\15.0\Bin\msbuild.exe'
DEF_MSBUILD='C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\msbuild.exe'
DEF_OUTPUTDIR='bin\'
DEF_BCONFIG="Release"
DEF_BPLAT="x64"
## This is the path you want to replace for your share directory.
Z_PATH="/opt/"
CONFUSER_INSTALL='C:\ConfuserEx\'
CONFUSER_PRESET="maximum"

## SSH PARAMS
SSH_TIMEOUT=5
SSH_RETRIES=3

function print_help {
	if [[ $1 ]]; then
		echo -e "[!] Error: $1\n"
	fi
	echo "################################################"
	echo "############ Linux Libvirt Pipeline ############"
	echo -e "################################################\n"
	echo -e "A build pipeline tool that utilizes libvirt to run\nA Windows VM and build executables"
	echo -e "\nRequired Parameters: "
	echo -e "\t-b|--build\t\tSpecify the build's csproj file location"
	echo -e "\nOptional Parameters: "
	echo -e "\t-r|--release\t\tSet Build Configuration to 'Release'. Cannot be used with -d. (default)"
	echo -e "\t-d|--debug\t\tSet Build Configuration to 'Debug'. Cannot be used with -r"
	echo -e "\t-p|--platform\t\tSet Build Platform.\n\t\t\t\tExpected Values: x86 | x64 (default) | AnyCpu"
	echo -e "\t-m|--msbuild-path\tSet MSBuild.exe Path which inherently sets the version.\n\t\t\t\tExample: \"C:\Windows\Microsoft.NET\Framework64\\\v4.0.30319\MSBuild.exe\""
	echo -e "\t-c|--confuser\t\tConfuser the files dropped. This uses the same rules as \"Maximum\" setting in gui"
	echo -e "\t-o|--outputdir\t\tSet Windows output path for the build. Defaults to ./bin/<release/debug>."
	echo -e "\t--dont-stop-vm\t\tIf set, this will not kill the vm after the build"
}

function print_error {
	if [[ $1 ]]; then
		echo -e "[!] Error: $1"
	fi
}

while [[ $# -gt 0 ]]; do
	key="$1"

	case $key in
		-h|--help|--h)
			print_help
			exit
			;;
		-b|--buildir)
			if [[ "$2" =~ ^\. ]]; then
				BUILD_DIR=$(readlink -f $2)
			else
				BUILD_DIR="$2"
			fi
			if [[ ! "$BUILD_DIR" =~ ^$Z_PATH ]]; then
				print_help "The build path specified is not in the defined Z_PATH!"
				exit
			fi
			shift
			shift
			;;
		-r|--release)
			if [[ $BUILD_DEBUG ]]; then
				print_help "-r can't be used with -d!"
				exit
			fi
			BUILD_RELEASE=1
			BUILD_CONFIG="Release"
			shift
			;;
		-d|--debug)
			if [[ $BUILD_RELEASE ]]; then
				print_help "-d can't be used with -r!"
				exit
			fi
			BUILD_DEBUG=1
			BUILD_CONFIG="Debug"
			shift
			;;
		-o|--outputdir)
			if [[ -z "$2" ]]; then
				print_help "No output directory specified!"
				exit
			fi
			TEMP="$2"
			if [[ "${TEMP: -1}" !=  '\' ]]; then
			       TEMP+='\'
			fi		
			OUTPUT_DIR=$TEMP
			shift
			shift
			;;
		-p|--platform)
			if [[ "$2" != "x86" ]] && [[ "$2" != "x64" ]] && [[ "$2" != "AnyCpu" ]]; then
				print_help "'$2' is not a legitimate platform option!"
				exit
			fi
			BUILD_PLAT="$2"
			shift
			shift
			;;
		-m|--msbuild-path)
			MSBUILD_PATH="$2"
			shift
			shift
			;;
		--dont-stop-vm)
			DONT_STOP_VM=1
			shift
			;;
		-c|--confuser)
			USE_CONFUSER=1
			shift
			;;
	esac
done

if [[ -z $BUILD_DIR ]]; then
	print_help "No build path specified!"
	exit
fi

## Lets setup the defaults of the build isn't setup
if [[ -z $BUILD_CONFIG ]]; then
	echo "[-] Configuration not set using default ($DEF_BCONFIG)."
	BUILD_CONFIG=$DEF_BCONFIG
fi

if [[ -z $BUILD_PLAT ]]; then
	echo "[-] Platform not set using default ($DEF_BPLAT)."
	BUILD_PLAT=$DEF_BPLAT
fi

if [[ -z $OUTPUT_DIR ]]; then
	OUTPUT_DIR="$DEF_OUTPUTDIR$DEF_BPLAT\\$BUILD_CONFIG\\"
	echo "[-] Output Directory not set, using default ($OUTPUT_DIR)."
else
	OUTPUT_DIR+=$DEF_BPLAT'\'$BUILD_CONFIG'\'
fi

if [[ -z $MSBUILD_PATH ]]; then
	echo "[-] MSBuild path not set, using default ($DEF_MSBUILD)."
	MSBUILD_PATH=$DEF_MSBUILD
fi

function check_vm_status {
	echo "[+] Checking VM Status..."
	VIRSH_LIST=$(sudo virsh list | grep "$VIRSH_DOMAIN")
	if [[ -z $VIRSH_LIST ]]; then
		VM_STATUS=0
	else
		VM_STATUS=1
	fi
}

function start_vm {
	sudo virsh start "$VIRSH_DOMAIN"
}

function stop_vm {
	sudo virsh shutdown "$VIRSH_DOMAIN" --mode acpi
}

function build_confuser_file {
	echo "[+] Building confuser csproj file..."
	OUTPUT_LOC=$(echo $OUTPUT_DIR | sed -E "s/\\\/\//g")
	BUILD_LOC=$(echo "$BUILD_DIR" | sed -E "s/$BUILD_FILE//g")
	CONFUSER_STRING="<project baseDir='$1' outputDir='$1confused\' xmlns='http://confuser.codeplex.com'>"
	CONFUSER_STRING+="<rule pattern='true' preset='$CONFUSER_PRESET' inherit='false' />"
	CONFUSER_STRING+="<packer id='compressor' />"
	for x in $(ls "$BUILD_LOC$OUTPUT_LOC"); do
		filetype=$(file "$BUILD_LOC$OUTPUT_LOC$x" | grep PE32)
		if [[ ! -z $filetype ]]; then
			echo "[+] Adding '$x' to confuser file..."
			CONFUSER_STRING+="<module path='$x' />"
		fi
	done
	CONFUSER_STRING+="</project>"
	echo "[+] Writing confuser.crproj ($BUILD_LOC$OUTPUT_LOC)"
	echo $CONFUSER_STRING > $BUILD_LOC$OUTPUT_LOC/confuser.crproj
}

## Check the vm - if it isn't started, start it.
check_vm_status
if [[ "$VM_STATUS" == 0 ]]; then
	echo "[+] VM is not active. Starting..."
	start_vm
else
	echo "[-] VM Already started. Skipping..."
fi

DISABLE_FODY=""
if [[ $USE_CONFUSER ]]; then
	DISABLE_FODY=" /p:DisableFody='true'"
fi

BUILD_FILE=$(echo "$BUILD_DIR" | rev | cut -d '/' -f 1 | rev)
BUILD_CD=$(echo "$BUILD_DIR" | sed -E "s/$BUILD_FILE//g" | sed -E "s/$(echo $Z_PATH | sed -e "s/\\//\\\\\//g")/Z:\//g" | sed -E "s/\//\\\/g" )
BUILD_STRING=".'$MSBUILD_PATH' './$BUILD_FILE' /p:Configuration=$BUILD_CONFIG,OutputPath='$OUTPUT_DIR' /p:Platform='$BUILD_PLAT'$DISABLE_FODY"

SSH_READ=0
while [[ $SSH_RETRIES > 0 ]]; do
	TEST_SSH=$(ssh -o ConnectTimeout=$SSH_TIMEOUT $SSH_NAME "exit")

	if [[ $TEST_SSH ]]; then
		SSH_READY=1
		break
	else
		echo "[-] SSH not ready. Trying again in $SSH_TIMEOUT seconds..."
		sleep 3
		SSH_RETRIES=$(($SSH_RETRIES-1))
	fi
done

if [[ $SSH_READY > 0 ]]; then
	echo "[+] SSH Ready, Running build command ($BUILD_STRING) in $BUILD_CD"
	ssh $SSH_NAME "cd '$BUILD_CD'; $BUILD_STRING"
	if [[ $USE_CONFUSER ]]; then
		build_confuser_file "$BUILD_CD$OUTPUT_DIR"
		CONFUSER_BUILD_STRING="Confuser.CLI.exe -noPause $(echo $BUILD_CD$OUTPUT_DIR)confuser.crproj"
		echo "[+] Executing confuser in '$BUILD_CD$OUTPUT_DIR' ('$CONFUSER_BUILD_STRING') "
		ssh $SSH_NAME "cd '$CONFUSER_INSTALL'; .\\$CONFUSER_BUILD_STRING"
	fi
else
	echo -e "[!] SSH did not initialize!"
fi

if [[ -z $DONT_STOP_VM ]]; then
	echo "[+] Shutting down VM..."
	stop_vm
else
	echo "[-] DONT_STOP_VM set. Skipping shutdown."
fi

