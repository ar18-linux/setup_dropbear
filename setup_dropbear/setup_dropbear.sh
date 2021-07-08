#!/usr/bin/env bash
# ar18

# Prepare script environment
{
  # Script template version 2021-07-06_08:05:30
  # Make sure some modification to LD_PRELOAD will not alter the result or outcome in any way
  LD_PRELOAD_old="${LD_PRELOAD}"
  LD_PRELOAD=
  # Determine the full path of the directory this script is in
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
  script_path="${script_dir}/$(basename "${0}")"
  #Set PS4 for easier debugging
  export PS4='\e[35m${BASH_SOURCE[0]}:${LINENO}: \e[39m'
  # Determine if this script was sourced or is the parent script
  if [ ! -v ar18_sourced_map ]; then
    declare -A -g ar18_sourced_map
  fi
  if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    ar18_sourced_map["${script_path}"]=1
  else
    ar18_sourced_map["${script_path}"]=0
  fi
  # Initialise exit code
  if [ ! -v ar18_exit_map ]; then
    declare -A -g ar18_exit_map
  fi
  ar18_exit_map["${script_path}"]=0
  # Save PWD
  if [ ! -v ar18_pwd_map ]; then
    declare -A -g ar18_pwd_map
  fi
  ar18_pwd_map["${script_path}"]="${PWD}"
  # Get old shell option values to restore later
  shopt -s inherit_errexit
  IFS=$'\n' shell_options=($(shopt -op))
  # Set shell options for this script
  set -o pipefail
  set -eu
  if [ ! -v ar18_parent_process ]; then
    export ar18_parent_process="$$"
  fi
  # Get import module
  if [ ! -v ar18.script.import ]; then
    mkdir -p "/tmp/${ar18_parent_process}"
    cd "/tmp/${ar18_parent_process}"
    curl -O https://raw.githubusercontent.com/ar18-linux/ar18_lib_bash/master/ar18_lib_bash/script/import.sh > /dev/null 2>&1 && . "/tmp/${ar18_parent_process}/import.sh"
    cd "${ar18_pwd_map["${script_path}"]}"
  fi
}
#################################SCRIPT_START##################################

ar18.script.import ar18.script.obtain_sudo_password
ar18.script.import ar18.script.import_vars
ar18.script.import ar18.script.execute_with_sudo
ar18.script.import ar18.pacman.install
ar18.script.import ar18.aur.install
ar18.script.import ar18.script.read_target
ar18.script.import ar18.script.source_or_execute_config

ar18.script.obtain_sudo_password
ar18.script.import_vars

# TODO: If openssh is installed at the time, existing host keys needs to be converted
# If not, then what?
# (Temporary) solution: We hide the ssh folder from dropbear, this way it will generate
# fresh private keys. SSH clients will see 2 different machines when unlocking the disk
# and when doing normal ssh stuff. Maybe the openssh private key could be converted for dropbear,
# but that would also mean that the real private key is now embedded in the initramfs.
# It might be safer to use the embedded key only for unlocking.
if [ -d "/etc/ssh" ]; then
  ar18.script.execute_with_sudo mv "/etc/ssh" "/etc/ssh_bak"
fi

ar18.pacman.install mkinitcpio-dropbear mkinitcpio-netconf mkinitcpio-utils

ar18.aur.install mkinitcpio-wifi

set +u
ar18_deployment_target="$(ar18.script.read_target "${1}")"
set -u

ar18.script.source_or_execute_config "source" "setup_dropbear" "${ar18_deployment_target}"

. "/etc/mkinitcpio.conf"

IFS=$' \t\n'
NEW_MODULES=""
for module in $(echo ${MODULES}); do
  included=0
  for my_module in "${ar18_modules[@]}"; do
    if [ "${my_module}" = "${module}" ]; then
      included=1
      break
    fi
  done
  if [ "${included}" = "0" ]; then
    NEW_MODULES="${NEW_MODULES}${module} "
  fi
done
NEW_MODULES="${NEW_MODULES}${ar18_modules[@]}"
ar18.script.execute_with_sudo sed -i -e "s/^MODULES=.*/MODULES=\"${NEW_MODULES}\"/g" "/etc/mkinitcpio.conf"

NEW_HOOKS=""
for hook in $(echo ${HOOKS}); do
  if [ "${hook}" = "filesystems" ]; then
    NEW_HOOKS="${NEW_HOOKS}wifi netconf dropbear encryptssh openswap resume ${hook} "
  elif [ "${hook}" = "netconf" ] \
  || [ "${hook}" = "dropbear" ] \
  || [ "${hook}" = "wifi" ] \
  || [ "${hook}" = "openswap" ] \
  || [ "${hook}" = "resume" ] \
  || [ "${hook}" = "encryptssh" ] \
  || [ "${hook}" = "encrypt" ]; then
    continue
  else
    NEW_HOOKS="${NEW_HOOKS}${hook} "
  fi
done
ar18.script.execute_with_sudo sed -i -e "s/^HOOKS=.*/HOOKS=\"${NEW_HOOKS}\"/g" "/etc/mkinitcpio.conf"

# Setup allowed public keys to connect
ar18.script.execute_with_sudo rm -f "/etc/dropbear/root_key"
ar18.script.execute_with_sudo sh -c "echo '' > '/etc/dropbear/root_key'"
for my_key in "${ar18_public_keys[@]}"; do
  ar18.script.execute_with_sudo sh -c "echo \"${my_key}\" >> \"/etc/dropbear/root_key\""
done
ar18.script.execute_with_sudo chmod 600 "/etc/dropbear/root_key"

# Setup wifi
cd "/tmp"
rm -rf "/tmp/secrets"
git clone http://github.com/ar18-linux/secrets
rm -rf "/tmp/gpg"
git clone http://github.com/ar18-linux/gpg
rm -rf "/tmp/wifi_passwords"
"/tmp/gpg/gpg/decrypt.sh" "/tmp/secrets/secrets/wifi_passwords.gpg" "/tmp/wifi_passwords" "${ar18_sudo_password}"
ar18.script.execute_with_sudo rm -f "/etc/wpa_supplicant/initcpio.conf"
while read line; do
  old_ifs="${IFS}"
  IFS=$'\t' 
  arr=(${line})
  ar18.script.execute_with_sudo sh -c "wpa_passphrase \"${arr[0]}\" \"${arr[1]}\" >> \"/etc/wpa_supplicant/initcpio.conf\""
  #echo "${arr[0]}"
  IFS="${old_ifs}" 
done < "/tmp/wifi_passwords/wifi_passwords"

ar18.script.execute_with_sudo mkinitcpio -P

if [ -d "/etc/ssh_bak" ]; then
  ar18.script.execute_with_sudo mv "/etc/ssh_bak" "/etc/ssh"
fi

##################################SCRIPT_END###################################
# Restore environment
{
  # Restore old shell values
  set +x
  for option in "${shell_options[@]}"; do
    eval "${option}"
  done
  # Restore LD_PRELOAD
  LD_PRELOAD="${LD_PRELOAD_old}"
  # Restore PWD
  cd "${ar18_pwd_map["${script_path}"]}"
}
# Return or exit depending on whether the script was sourced or not
{
  if [ "${ar18_sourced_map["${script_path}"]}" = "1" ]; then
    return "${ar18_exit_map["${script_path}"]}"
  else
    exit "${ar18_exit_map["${script_path}"]}"
  fi
}
