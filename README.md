# Linux Libvirt Build Pipeline
![](https://koloss.online/wp-content/uploads/2021/12/LinuxLibvirtPipelineDiagram.png)
A build pipeline tool that utilizes libvirt to run a Windows VM and build executables

This may not work for all projects but works well for compiling tools / exploits for Red Team/Pentesting and doesn't mean you won't ever have to touch the VM again to add packages but it is also a start for an easier building from linux. I will be expanding this as I run into issues or find improvements. For Example, I want to add other obfuscation techniques.

A little write-up on this project: https://koloss.online/2021/12/17/linux-libvirt-build-pipeline/

## Usage:
```
################################################
############ Linux Libvirt Pipeline ############
################################################

A build pipeline tool that utilizes libvirt to run
A Windows VM and build executables

Required Parameters: 
	-b|--build		Specify the build's csproj file location

Optional Parameters: 
	-r|--release		Set Build Configuration to 'Release'. Cannot be used with -d. (default)
	-d|--debug		Set Build Configuration to 'Debug'. Cannot be used with -r
	-p|--platform		Set Build Platform.
				Expected Values: x86 | x64 (default) | AnyCpu
	-m|--msbuild-path	Set MSBuild.exe Path which inherently sets the version.
				Example: "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe"
	-c|--confuser		Confuser the files dropped. This uses the same rules as "Maximum" setting in gui
	-o|--outputdir		Set Windows output path for the build. Defaults to ./bin/<release/debug>.
	--dont-stop-vm		If set, this will not kill the vm after the build
```

## Features:
	- Automatically Start/Stop VM with virtsh
	- Automatically Start/Stop smbD using libvirt hooks
	- Auto mouting the SMB share.
	- Utilizes SSH to vm into VM and run build tools
	- ConfuserEx support:
		- Creates a crproj file in the build directory
		- Iterates over the files to find all PE32 files.


## Setup:
This assumes you have a working libvirt VM running windows 10 named "win10-dev". 

 - Requirements:
	- Linux Host:
		- LibvirtD
		- smbD
	- Windows Guest:
		- OpenSSH Server
		- Visual Studio / Other Build Tools.

#### Windows Guest:
 - Generate SSH key, copy to Host.
 - Add SSH key to authorized_keys
 - Install Visual studio.
 - Create (```New-Item -type file -force $profile```) or modify powershell profile:
 	- Add the line  ```net use Z: \\<vm_default_gateway>\<share_name> /user:<smb_user> <smb_pass>```
 - Set Powershell Execution policy to prevent future issues: ```Set-ExecutionPolicy Unrestricted```
 - Set OpenSSH Default shell to powershell with Regedit: ```/HKLM/SOFTWARE/OpenSSH/DefaultShell``` -> ```C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe```
 - Allow Linked Connections: ```reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "EnableLinkedConnections" /t REG_DWORD /d 0x00000001 /f```
 - To prevent issues from future versions add ```<loadFromRemoteSources enabled="true"/>``` to ```%windir%\Microsoft.NET\Framework\[version]\config\machine.config``` (32 bit) and ```%windir%\Microsoft.NET\Framework64\[version]\config\machine.config``` (64bit) under the 'runtime' tag. Otherwise this could result in an exception from HRESULT: 0x80131515.
 - *Recommended:*
 	- Assuming you use this for a similar purpose, Disable Defender using Group Policy
 	- Administrative Templates > Windows Components > Windows Defender Antivirus > Turn off Windows Defender Antivirus = Enabled
 	- Administrative Templates > Windows Components > Windows Defender Antivirus > Real-Time Protection > Turn off real-time protection = Enabled
 - Download and extract confuserEx into your favorite directory (I chose C:\ConfuserEx\).

#### Linux Host:
 - Add a hostname / ip to your ```/etc/hosts``` file.
 - Copy the SSH private from the windows host to your favorite ssh key storage location.
 - Add a ~/.ssh/config entry for your VM with the hostname you used in the /etc/hosts file. (Example in ssh/config)
 - Install smbd using your prefered method.
 - Modify the config to have a share where you typically build. I used /opt and disable all other shares including printer and home directories. (Example in etc/samba/smb.conf)
 - Create a hooks script and make it executable in ```/etc/libvirt/hooks/qemu``` (Example/Working in etc/libvirt/hooks/qemu)
 - Modify the default values in the build_exe.sh to fit your setup / build tools.
 - Add the build_exe.sh to your build path for easier use.

#### Configurables:
The default values I used is available in the top of the file
```
VIRSH_DOMAIN="win10-dev" # Your VM name / domain
SSH_NAME="dev-machine" # The name of your machine from /etc/hosts
DEF_MSBUILD='C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\msbuild.exe' # The MSBuild version you want to use by default
DEF_OUTPUTDIR='bin\' # The windows path you want the built exe to be
DEF_BCONFIG="Release" # The default build type
DEF_BPLAT="x64" # This is the platform you wish to deploy this
Z_PATH="/opt/" # The path to your linux share. Ensures you only give paths that work in the windows host
CONFUSER_INSTALL='C:\ConfuserEx\' # your confuser install location
CONFUSER_PRESET="maximum" # the preset you want to use with confuser.

## SSH PARAMS
SSH_TIMEOUT=5
SSH_RETRIES=3

```
