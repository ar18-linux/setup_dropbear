#!/bin/bash
# ar18

# Script template version 2021-06-12.03
# Make sure some modification to LD_PRELOAD will not alter the result or outcome in any way
LD_PRELOAD_old="${LD_PRELOAD}"
LD_PRELOAD=
# Determine the full path of the directory this script is in
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
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
if [ -z "${ar18_exit_map+x}" ]; then
  declare -A -g ar18_exit_map
fi
ar18_exit_map["${script_path}"]=0
# Get old shell option values to restore later
shopt -s inherit_errexit
IFS=$'\n' shell_options=($(shopt -op))
# Set shell options for this script
set -o pipefail
set -eu
#################################SCRIPT_START##################################

set -x

if [ ! -v ar18_helper_functions ]; then rm -rf "/tmp/helper_functions_$(whoami)"; cd /tmp; git clone https://github.com/ar18-linux/helper_functions.git; mv "/tmp/helper_functions" "/tmp/helper_functions_$(whoami)"; . "/tmp/helper_functions_$(whoami)/helper_functions/helper_functions.sh"; cd "${script_dir}"; export ar18_helper_functions=1; fi
obtain_sudo_password
import_vars

pacman_install mkinitcpio-dropbear mkinitcpio-netconf mkinitcpio-utils

aur_install mkinitcpio-wifi

set +u
ar18_deployment_target="$(read_target "${1}")"
set -u

source_or_execute_config "source" "setup_dropbear" "${ar18_deployment_target}"

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
echo "${ar18_sudo_password}" | sudo -Sk sed -i -e "s/^MODULES=.*/MODULES=\"${NEW_MODULES}\"/g" "/etc/mkinitcpio.conf"

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
echo "${ar18_sudo_password}" | sudo -Sk sed -i -e "s/^HOOKS=.*/HOOKS=\"${NEW_HOOKS}\"/g" "/etc/mkinitcpio.conf"

# Setup allowed public keys to connect
echo "${ar18_sudo_password}" | sudo -Sk rm -f "/etc/dropbear/root_key"
echo "${ar18_sudo_password}" | sudo -Sk sh -c "echo '' > '/etc/dropbear/root_key'"
for my_key in "${ar18_public_keys[@]}"; do
  echo "${ar18_sudo_password}" | sudo -Sk sh -c "echo \"${my_key}\" >> \"/etc/dropbear/root_key\""
done
echo "${ar18_sudo_password}" | sudo -Sk chmod 600 "/etc/dropbear/root_key"

echo "${ar18_sudo_password}" | sudo -Sk mkinitcpio -P

rm -rf "${script_dir}/secrets"
git clone http://github.com/ar18-linux/secrets
rm -rf "${script_dir}/gpg"
git clone http://github.com/ar18-linux/gpg
rm -rf "${script_dir}/wifi_passwords"
"${script_dir}/gpg/gpg/decrypt.sh" "${script_dir}/secrets/secrets/wifi_passwords.gpg" "${script_dir}/wifi_passwords" "${ar18_sudo_password}"
#cat "${script_dir}/wifi_passwords/wifi_passwords"
echo "${ar18_sudo_password}" | sudo -Sk rm -f "/etc/wpa_supplicant/initcpio.conf"
while read line; do
  old_ifs="${IFS}"
  IFS=$'\t' 
  arr=(${line})
  echo "${ar18_sudo_password}" | sudo -Sk sh -c "wpa_passphrase \"${arr[0]}\" \"${arr[1]}\" >> \"/etc/wpa_supplicant/initcpio.conf\""
  #echo "${arr[0]}"
  IFS="${old_ifs}" 
done < "${script_dir}/wifi_passwords/wifi_passwords"

##################################SCRIPT_END###################################
# Restore old shell values
set +x
for option in "${shell_options[@]}"; do
  eval "${option}"
done
# Restore LD_PRELOAD
LD_PRELOAD="${LD_PRELOAD_old}"
# Return or exit depending on whether the script was sourced or not
if [ "${ar18_sourced_map["${script_path}"]}" = "1" ]; then
  return "${ar18_exit_map["${script_path}"]}"
else
  exit "${ar18_exit_map["${script_path}"]}"
fi
