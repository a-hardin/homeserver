#!/usr/bin/env bash

echo "*********************"
echo "Installing packages"
echo "*********************"

sudo apt-get update
sudo add-apt-repository ppa:stebbins/handbrake-releases
sudo apt-get update
sudo apt-get install git nano composer htop handbrake-cli
sudo apt install openssh-server
sudo apt install docker.io docker-compose 

echo "*********************"
echo "Docker Version"
echo $(docker -v)
echo "*********************"

# sudo curl -L "https://github.com/docker/compose/releases/download/1.23.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
# sudo chmod +x /usr/local/bin/docker-compose

echo $(docker-compose -v)


echo "*********************"
echo "Cloning Git Repositories"
echo "*********************"

sudo mkdir /var/www
cd /var/www
sudo git clone https://github.com/a-hardin/homeserver.git

echo "*********************"
echo "Restart docker containers on reboot"
echo "*********************"
(crontab -l 2>/dev/null; echo "@reboot /var/www/homeserver/system/reboot.sh") | crontab -

echo "*********************"
echo "Mount external drive"
echo "*********************"
# TODO : Mount for each extral drive and make names unique.
#  cd into /dev 
# sudo parted -ls
# sudo lsblk -fm
#  then sudo fdisk -l
# Example:
    # Disk /dev/sda: 1.84 TiB, 2000365289472 bytes, 3906963456 sectors
    # Disk model: Elements 2621   
    # Units: sectors of 1 * 512 = 512 bytes
    # Sector size (logical/physical): 512 bytes / 512 bytes
    # I/O size (minimum/optimal): 512 bytes / 512 bytes
    # Disklabel type: gpt
    # Disk identifier: D7F52B66-DD5D-4CA2-B1C8-7DEED7E9AB0B

    # Device     Start        End    Sectors  Size Type
    # /dev/sda1   2048 3906961407 3906959360  1.8T Linux filesystem

# and do blkid for uuid 
# Example:
    # /dev/sda1: LABEL="2 TB" UUID="d9095fcc-74df-4bdb-8713-45da60b43712" TYPE="ext4" PARTLABEL="Elements" PARTUUID="61d4089a-d22d-489c-bcba-577e78f932cd"

# Make a dir on in media dir
# sudo mkdir /media/external_1
# 2tb example
# sudo mount -t ext4 /dev/sdd1 /media/external_1

# determine if there is a extral storage and mount it so it remains on reboot
# using /etc/fstab
# sudo nano /etc/fstab
# adding the following entry:
# UUID=<uuid from blkid> /media/external_1 ext4 defaults 0 0
# sudo mount -t ntfs /dev/sdb1 /media/external_1TB

echo "*********************"
echo "Setup a static IP"
echo "*********************"
# Set network gateway in env file or auto generate
# to see your network info execute: ip addr show
# make sure you have the right ethernet type enp1s0 might be wrong check ip addr show 
# make ips an environment var
sudo cp /var/www/homeserver/system/01-network-manager-all.yaml /etc/netplan/01-network-manager-all.yaml
sudo netplan apply
sudo ufw allow ssh


echo "*********************"
echo "Setup env file"
echo "*********************"
# Use values from docker-compose ENV vars or use random
sudo touch .env
MYSQL_ROOT_PASSWORD=MYSQL_ROOT_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
MYSQL_PASSWORD=MYSQL_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
MYSQL_DATABASE=MYSQL_DATABASE=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
MYSQL_USER=MYSQL_USER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
echo $MYSQL_ROOT_PASSWORD | sudo tee -a .env
echo $MYSQL_PASSWORD | sudo tee -a .env
echo $MYSQL_DATABASE | sudo tee -a .env
echo $MYSQL_USER | sudo tee -a .env

echo "*********************"
echo "start docker container"
echo "*********************"
docker-compose up