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
yum -y update
yum -y groupinstall "Development Tools"

# Install GateOne and Prerequisites
yum -y install krb5-devel libffi-devel openssl-devel
yum -y install --enablerepo=epel PyPAM
ln -s /usr/lib64/python2.6/site-packages/PAMmodule.so /usr/lib64/python2.7/site-packages/PAMmodule.so
pip -q install "tornado<3.0" kerberos pyOpenSSL
yum -y install "${GATEONE_RPM}"
useradd -s /sbin/nologin -d /opt/gateone "${USER}"
echo "${PASSWORD}" | passwd --stdin "${USER}"
chown -R "${USER}":"${USER}" /opt/gateone
ln -s /opt/gateone/logs /var/log/gateone

# Install supervisor
pip -q install supervisor
mkdir /etc/supervisord.d
/usr/local/bin/echo_supervisord_conf > /etc/supervisord.conf
sed -i -e "s|^logfile=/tmp/supervisord.log|logfile=/var/log/supervisord|" /etc/supervisord.conf
sed -i -e "s|^pidfile=/tmp/supervisord.pid|pidfile=/var/run/supervisord.pid|" /etc/supervisord.conf
sed -i -e "s|^;\[include\]|[include]|" /etc/supervisord.conf
sed -i -e "s|^;files = .*|files = /etc/supervisord.d/*.ini|" /etc/supervisord.conf
curl -o /etc/init.d/supervisord $SUPERVISORD_INIT
sed -i -e "s|^PREFIX=/usr|PREFIX=/usr/local|" /etc/init.d/supervisord
chmod a+x /etc/init.d/supervisord

# Register GateOne service
ORIGINS="https://${PUBLIC_IP}"
[ -n "${DOMAIN_NAME}" ] && ORIGINS="${ORIGINS};https://${DOMAIN_NAME}"
cat > /etc/supervisord.d/gateone.ini <<EOF
[program:gateone]
command=/opt/gateone/gateone.py --origins="${ORIGINS}" --auth="pam" --pam_realm="GateOne"
directory=/opt/gateone
numprocs=1
autostart=true
autorestart=true
user=root
EOF

# Start services
chkconfig supervisord on
service supervisord start