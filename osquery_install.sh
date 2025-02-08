wget https://pkg.osquery.io/deb/osquery_5.9.1-1.linux_amd64.deb
dpkg -i osquery_5.9.1-1.linux_amd64.deb
systemctl restart osqueryd

echo "Installation de osqueryd terminée"
