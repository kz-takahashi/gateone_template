#!/bin/bash -e
# Setup GateOne Server on Amazon Linux

if [ -f /tmp/cfn_parameters ]; then
  . /tmp/cfn_parameters
fi

GATEONE_RPM="https://github.com/downloads/liftoff/GateOne/gateone-1.1-1.noarch.rpm"
SUPERVISORD_INIT="https://raw.githubusercontent.com/Supervisor/initscripts/master/redhat-init-mingalevme"
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
USER=${USER:-gateone}
PASSWORD=${PASSWORD:-gateone}

# Update Packages
sudo yum -y update
sudo yum -y groupinstall "Development Tools"

# Install GateOne and Prerequisites
sudo yum -y install krb5-devel libffi-devel openssl-devel
sudo yum -y install --enablerepo=epel PyPAM
sudo ln -s /usr/lib64/python2.6/site-packages/PAMmodule.so /usr/lib64/python2.7/site-packages/PAMmodule.so
sudo pip -q install "tornado<3.0" kerberos pyOpenSSL
sudo yum -y install "${GATEONE_RPM}"
sudo useradd -s /sbin/nologin -d /opt/gateone "${USER}"
echo "${PASSWORD}" | sudo passwd --stdin "${USER}"
sudo chown -R "${USER}":"${USER}" /opt/gateone
sudo ln -s /opt/gateone/logs /var/log/gateone

# Install supervisor
sudo pip -q install supervisor
sudo mkdir /etc/supervisord.d
echo_supervisord_conf | sudo tee /etc/supervisord.conf > /dev/null
sudo sed -i -e "s|^logfile=/tmp/supervisord.log|logfile=/var/log/supervisord|" /etc/supervisord.conf
sudo sed -i -e "s|^pidfile=/tmp/supervisord.pid|pidfile=/var/run/supervisord.pid|" /etc/supervisord.conf
sudo sed -i -e "s|^;\[include\]|[include]|" /etc/supervisord.conf
sudo sed -i -e "s|^;files = .*|files = /etc/supervisord.d/*.ini|" /etc/supervisord.conf
sudo curl -o /etc/init.d/supervisord $SUPERVISORD_INIT
sudo sed -i -e "s|^PREFIX=/usr|PREFIX=/usr/local|" /etc/init.d/supervisord
sudo chmod a+x /etc/init.d/supervisord

# Register GateOne service
ORIGINS="https://${PUBLIC_IP}"
[ -n "${DOMAIN_NAME}" ] && ORIGINS="${ORIGINS};https://${DOMAIN_NAME}"
cat <<EOF | sudo tee /etc/supervisord.d/gateone.ini > /dev/null
[program:gateone]
command=/opt/gateone/gateone.py --origins="${ORIGINS}" --auth="pam" --pam_realm="GateOne"
directory=/opt/gateone
numprocs=1
autostart=true
autorestart=true
user=root
EOF

# Start services
sudo chkconfig supervisord on
sudo service supervisord start