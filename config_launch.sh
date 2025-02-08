apt update && apt upgrade -y
apt install samba smbclient winbind krb5-user krb5-admin-server dnsutils -y
systemctl stop smbd nmbd winbind
systemctl disable smbd nmbd winbind
samba-tool domain provision --use-rfc2307 --realm=NORTHSTAR.COM --domain=NORTHSTAR --adminpass=@fterTheB@ll33/ --server-role=dc | tee -a /var/log/samba-setup.log
