The Samba-AD project is a suite of Shell and Python scripts designed to automate the deployment and management of a Linux-based Active Directory Domain Controller. Driven by a lightweight text-based interface, it covers every essential step:

Domain creation & configuration
With a single command, Samba is installed, the AD domain is provisioned, and DNS/Kerberos services are configured to work together securely and reliably.

Centralized administration
Users and groups can be imported, modified or deleted in bulk via scripts, eliminating manual errors and streamlining day-to-day management.

Share protection
ClamAV is deployed automatically on all CIFS/SMB shares, with scheduled scans and alert notifications to ensure continuous data protection.

Operational monitoring
The Wazuh agent is installed and configured to centralize domain logs, detect anomalies, and generate security or performance alerts.

Windows admin made easy
A PowerShell script produces an RSAT installer package (.msi) ready for deployment on Windows workstations, so administrators can manage the domain from their familiar tools.

The text-based interface (TUI) lets you manage user accounts, groups, OUs, computers and GPOs without a graphical console or dedicated admin workstation.

It can be run on any Linux distribution.
