#!/usr/bin/env bash

# Installs ConfigServ Firewall (CSF)
# and removes APF and the "Add IP to Firewall" WHM
# plugin

error_exit() {
  # echo an error message and exit with status '1'
  echo "$1"
  exit 1
}

add_imh_default_allow_ips() {
  # this downloads the csf-ded imh package, extracts ./etc/csf/csf.allow.example
  # and copies it to /etc/csf/csf.allow with the intent of obtaining the most
  # up to date imh allowed IP entries

  tmpdir="/tmp/csf-ded_extract_dir"

  echo "downloading latest copy of IMH allow IPs from csf-ded repo"
  if [ ! -d "$tmpdir" ]; then
    mkdir $tmpdir && \
    cd $tmpdir && \
    yumdownloader csf-ded || error_exit "yumdownloader does not exist or failed"
    rpm2cpio csf-ded*.rpm | cpio -imd || error_exit "rpm2cpio and or cpio do not exist or failed"
    yes | cp -v ~/csf-ded_extract_dir/etc/csf/csf.allow.example /etc/csf/csf.allow
    rm -rfv "$tmpdir"
  else
    echo "$tmpdir exists. Manually add default IMH csf.allow entries"
  fi
}

install_csf() {
  # TODO -- set lf_ipset = "1" and find out best number for "DENY_IP_LIMIT" for VZ VPS containers
  #         it appears that with VZ7, ipset works and CSF allows use of ipset,
  #         so many more IPs can be added to iptables via ipset

  # TODO -- set lf_ipset = "1" for dedicated servers as well?

  # current limit for imh setup for number of iptables rules is 3000 via the
  # 'numiptent' beancounter

  # grab CSF package from configserver and run the install script
  cd /usr/src && wget https://download.configserver.com/csf.tgz && tar -xzf csf.tgz && cd csf
  ./install.cpanel.sh
  cd ~

  # configure /etc/csf/csf.conf with the following
  sed -i -r \
    -e '/^TESTING/s/1/0/' \
    -e '/^VERBOSE /s/1/0/' \
    -e '/^PT_LIMIT /s/[0-9]{1,}/120/' \
    -e '/^PT_ALL_USERS /s/[0-9]{1,}/1/' \
    -e '/^PT_USERPROC /s/[0-9]{1,}/0/' \
    -e '/^PT_USERMEM /s/[0-9]{1,}/0/' \
    -e '/^SYSLOG_CHECK /s/[0-9]{1,}/900/' \
    -e '/^LF_SYMLINK /s/[0-9]{1,}/1/' \
    -e '/^LF_SCRIPT_ALERT /s/[0-9]{1,}/1/' \
    -e '/^RESTRICT_SYSLOG /s/[0-9]{1,}/2/' \
    -e '/^LF_TRIGGER /s/[0-9]{1,}/5/' \
    -e '/^LF_SSHD / s/[0-9]{1,}/1/' \
    -e '/^LF_FTPD / s/[0-9]{1,}/1/' \
    -e '/^LF_SMTPAUTH /s/[0-9]{1,}/1/' \
    -e '/^LF_EXIMSYNTAX /s/[0-9]{1,}/1/' \
    -e '/^LF_POP3D /s/[0-9]{1,}/1/2' \
    -e '/^LF_IMAPD /s/[0-9]{1,}/1/' \
    -e '/^LF_HTACCESS /s/[0-9]{1,}/1/' \
    -e '/^LF_CPANEL /s/[0-9]{1,}/1/' \
    -e '/^LF_MODSEC /s/[0-9]{1,}/1/' \
    -e '/^TCP_IN /c\TCP_IN = "20,21,25,53,80,110,143,443,465,587,993,995,2082,2083,2086,2087,2095,2096,3306,30000:35000"' \
    -e '/^TCP_OUT / c\TCP_OUT = "1:65535"' \
    -e '/^UDP_OUT / c\UDP_OUT = "1:65535"' \
    -e '/^UDP_IN /s/"/,33434:33529"/2' \
    /etc/csf/csf.conf
  
  # check if we are in a VPS or dedicated server as denied IP limits will be different
  if [[ ! -d '/proc/vz/vzaquota/' ]]; then
   # in a dedicated server
    sed -i.bk \
      -e '/^DENY\_IP\_LIMIT \=/ s/\"[0-9]*\"/\"15000\"/' \
      -e '/^DENY\_TEMP\_IP\_LIMIT \=/ s/\"[0-9]*\"/\"200\"/' \
      /etc/csf/csf.conf
  else
    # in a VPS
    sed -i.bk -e \
      '/^DENY\_IP\_LIMIT \=/ s/\"[0-9]*\"/\"2500\"/' \
      -e '/^DENY\_TEMP\_IP\_LIMIT \=/ s/\"[0-9]*\"/\"500\"/' \
      /etc/csf/csf.conf
  fi

  # ensure resellers have CSF plugin in WHM
  for reseller in $(cat /var/cpanel/resellers | awk -F':' {'print $1'})
    do sed -i.bk "/$reseller/s/$/\,software\-ConfigServer\-csf/" /var/cpanel/resellers
    echo -e "\n$reseller:0:USE,ALLOW,DENY,UNBLOCK" >> /etc/csf/csf.resellers
  done

  # update CSF
  cd /usr/src && wget http://download.configserver.com/csupdate && sed -i 's/\r//' csupdate
  chmod +x csupdate
  ./csupdate
}

remove_apf() {
  
  # removes APF if exists and "Add IP to Firewall" WHM plugin

  # check for APF via 'apf-ded' package, exit if it does not exist
  rpm -q apf-ded || error_exit "APF does not exist"

  date_now=$(date +%s)
  echo "backing up /etc/apf to /etc/apf.bk-$date_now"
  cp -r /etc/apf{,.bk-$date_now}
  systemctl stop apf || service apf stop

  # remove apf check from tailwatch, remove APF
  chkconfig --del apf
  rm -rfv /etc/init.d/apf \
          /usr/local/sbin/apf \
          /etc/apf \
          /usr/local/cpanel/whostmgr/cgi/{apfadd,addon_add2apf.cgi} \
          /usr/local/cpanel/whostmgr/cgi/apfadd \
          /usr/local/cpanel/whostmgr/cgi/addon_add2apf.cgi

  yum -y remove apf-ded whm-addip
  cp /var/cpanel/pluginscache.yaml{,.bk$(date +%F)} && \
  grep -q add_ip_to_firewall /var/cpanel/pluginscache.yaml && \
  sed '3,/add_ip_to_firewall/d' -i /var/cpanel/pluginscache.yaml
}

# runnning some functions in subshells so the script will exit on error
# but won't exit script entirely 
(remove_apf)
install_csf
(add_imh_default_allow_ips)