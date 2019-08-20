#!/usr/bin/env bash

echo "*********************"
echo "Installing packages"
echo "*********************"

sudo apt-get update
sudo apt-get install git nano composer htop
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
git clone https://github.com/a-hardin/homeserver.git


echo "*********************"
echo "Restart docker containers on reboot"
echo "*********************"
(crontab -l 2>/dev/null; echo "@reboot /var/www/homeserver/system/reboot.sh") | crontab -


echo "*********************"
echo "Setup a static IP"
echo "*********************"
sudo cp /var/www/homeserver/system/01-network-manager-all.yaml /etc/netplan/01-network-manager-all.yaml
sudo netplan apply


echo "*********************"
echo "Setup env file"
echo "*********************"
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