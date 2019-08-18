#!/usr/bin/env bash

echo "*********************"
echo "Installing packages"
echo "*********************"

sudo apt-get update
sudo apt-get install git nano composer
sudo apt install docker.io

echo "*********************"
echo "Docker Version"
echo $(docker -v)
echo "*********************"

sudo curl -L "https://github.com/docker/compose/releases/download/1.23.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

echo $(docker-compose -v)


echo "*********************"
echo "Cloning Git Repositories"
echo "*********************"

sudo mkdir /var/www
cd /var/www
git clone https://github.com/a-hardin/homeserver.git


echo "*********************"
echo "Restart docker containers on reboot"
echo "*********************"
(crontab -l 2>/dev/null; echo "@reboot /var/www/homeserver/docker/reboot.sh") | crontab -


echo "*********************"
echo "Setup a static IP"
echo "*********************"



echo "*********************"
echo "start docker container"
echo "*********************"
docker-compose up