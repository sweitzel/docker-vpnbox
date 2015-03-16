# VPN-Box on Docker

Docker containers for OpenVPN and transparent Proxy (Squid+C-ICAP+ClamAV)

This creates several containers to server as VPN server with transparent proxy capability.
The OpenVPN container will forward all HTTP (Port 80) / HTTPS (Port 443) traffic to the Squid container. All other VPN traffic will be SNAT'd.
Squid is configured to scan all traffic via ClamAV for Virii and against Google Safebrowsing database. Additionally the Shallalist blacklist is configured.

> It has been tested on Windows OpenVPN client as well as IOS 8.2

```
+----------------------------------------------------------------------------+
|                                                                            |
|                                     3128/tcp                               |
|   +-------------+ 80/tcp            3129/tcp TPROXY http  +------------+   |
|   |             | 443/tcp           3130/tcp TPROXY https |            |   |
|   |   openvpn   +----------------------------------------->   squid    |   |
|   |             |                                         |            |   |
|   +------^------+                                         +------+-----+   |
|          | 1194/udp                                              |         |
|          |                                                       |         |
|          |                                              1344/tcp |         |
|          |       +------------+                           +------v-----+   |
|          |       |            |                           |            |   |
|          |       |   clamav   <---------------------------+   cicap    |   |
|          |       |            | 3310/tcp                  |            |   |
|          |       +------------+                           +------------+   |
|          |                                                                 |
|          | 5443/udp                                                        |
+-------------------------------------------------------------- Docker-host -+
           |
           |
  +-----------------------------------------------------------------------+
  |        |                                                              |
  |        |                                                              |
  |  +-----+------+                                                       |
  |  | VPN client |                                                       |
  |  +------------+                                                       |
  |                                                                       |
  |                                                                       |
  +-------------------------------------------------------------Internet--+
```

## Quick Start

> Requires [Docker](https://docs.docker.com/) 1.5 or later, and [Docker Compose](https://docs.docker.com/compose/) 1.1.0 or later

### Setup OpenVPN container

* Create data container for OpenVPN (store the CA and some more data persistently)
```bash
docker run --name=ovpn_data sweitzel/vpnbox-openvpn --entrypoint bash echo ovpn_data
```

* Initialize OpenVPN CA (has to run interactively)
```bash
docker run -ti --rm --volumes-from=ovpn_data sweitzel/vpnbox-openvpn --init=udp://vpn.my-server.com:5443
```
> Note: Some password choices will be offered. Make sure to store the CA password somewhere safely, you need it again to create Client certificates

### Setup Squid container

* Create data container for Squid (stores CA and some more data persistently)
```bash
docker run --name=squid_data sweitzel/vpnbox-squid --entrypoint bash echo squid_data
```

* Initialize Squid
```bash
docker run -ti --rm --volumes-from squid_data sweitzel/vpnbox-squid --init
```
> Note: This process will output the CA, you should safe it for later (if not you can still retrieve it with --getca).

### Starting up

* After steps above have been executed, the containers can be started
```bash
docker-compose -f <path_to>/docker-compose.yml
```
> Note: Make sure to read the output, and if everything went well, the containers keep running

* Currently cross-links between containers are not supported by docker-compose. Thus we need to run:

```bash
docker exec -t vpnbox_openvpn_1 --post-run=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' vpnbox_squid_1)
```

## Setting up Clients

* Add a client to certificate store
```bash
docker run -ti --rm --volumes-from=ovpn_data sweitzel/vpnbox-openvpn --getclient=<client_cn>
```
> Note: Feel free to use a descriptive string of the purpose of the VPN client
* Save the programs output as *.ovpn file

### Windows VPN client

* OpenVPN on Windows is easy to use. Just copy the *.ovpn file over to C:\Program Files\OpenVPN\config (adjust if needed)
* Start OpenVPN, you will probably Admin permissions or else the Tunnel will not be properly created.
* Import Squid CA into Certificate Stores
    - create file squidCA.crt with content you saved
    - double click the file (info window should be presented)
    - click "Install Certificate"
    - pick local user as install destination
    - select "Trusted Root Certification Authorities" / "Vertrauenswürdige Stammzertifizierungsstellen" as store
    - verify in Internet Explorer that e.g. on https://www.google.com no certificate error is popping up anymore
      (Note: Google Chrome is using also the Windows store)
    - Firefox uses its own Cert store (Settings -> Extended -> Certificates)

### IOS

* Application & VPN Profile
    * Install on your device [OpenVPN Connect](https://itunes.apple.com/de/app/openvpn-connect/id590379981)
    * Use Itunes put the *.ovpn file in the OpenVPN Connect files. The application will then offer to import the profile 
* Squid CA to prevent SSL errors
    * Install iPhone Configuration Utility on [MacOS](https://itunes.apple.com/us/app/apple-configurator/id434433123?mt=12) / [Windows](http://download.cnet.com/iPhone-Configuration-Utility-for-Windows/3000-20432_4-10969175.html)
    * Create a profile and add the Squid CA to the certificate store. Then assign the profile to your device.

### Building Images yourself

The default docker-compose.yml file is refering to the ready-to-use Images from the Docker Hub.
If one wants to modify the stuff, or just be sure that the content is "safe" use the dockerfile-build.yml.

* Download snapshot from https://github.com/sweitzel/docker-vpnbox
* Extract, change to the directory, and finally build using:
```bash
docker-compose -f <path_to>/docker-compose-build.yml build
```

### Verification on Client

After the tunnel has been established, make sure it is working:

* Ping the VPN server:
```bash
ping 10.128.81.1
```
* Check Transparent Proxy is working by downloading a (harmless) [Eicar Test Virus](http://www.eicar.org/85-0-Download.html)
    > Note: Try the different variants, SSL should also work. If it works you will see a message from Squid/ClamAV, and not from your local Virus Scanner.

## Miscellaneous

### Choice for CentOS

* I decided to use CentOS for all images

### Security Aspects

* Each application has its own container, thus high isolation
* Applications run non-root
* VPN CA is kept in data container. Password should be kept in a secure location
* VPN is using TLS 1.2 with DHE and tls-auth HMAC signature

### Blacklist
* The blacklists can be configured by adjusting the Squid containers ENV var SQUIDGUARD_FILTER (list of space separated categories)
    * Check a list of supported [Shallalist Categories](http://www.shallalist.de/categories.html)
