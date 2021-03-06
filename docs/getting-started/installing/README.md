---
title: Installing
toc_order: 2
---

# Installing Kontena

Please see below instructions for automated installation of Kontena.

* [AWS EC2](aws-ec2.md)
* [Azure](azure.md)
* [DigitalOcean](digitalocean.md)
* [Packet](packet.md)
* [UpCloud](upcloud.md)
* [Vagrant](vagrant.md)

Please see below instructions for custom Kontena installations.

* [CoreOS](coreos.md)
* [Docker Compose](docker-compose.md)
* [Ubuntu 14.04](ubuntu.md)

## Needed open ports:

To operate properly Kontena needs only a few ports opened in firewalls. The provisioning plugins should take care of these automatically for you. If making a more custom installation make sure you have the following ports open.

### On Master:

* 443, on master server. Nodes connect to master using this port. If for some reason you are using insecure http connection, use port 80.
* 22, for possible ssh connections

### On nodes:

**For incoming connections:**

* 22/tcp, for incoming ssh connections
* 1194/udp, for incoming VPN connection. *Optional*
* plus any other that you need for your services.

**Between nodes:**

* 6783-6784/tcp+udp, overlay network connections between nodes.
