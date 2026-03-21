# homeserver
homeserver setup


Notes on setting up guacamole database
docker exec -it mysql /bin/bash
mysql -u root -p
<enter root password>
CREATE DATABASE guacamole_db;
CREATE USER 'guacamole_user'@'%' IDENTIFIED BY 'mAXM2QuaTNKCmhDim9C6';
GRANT ALL PRIVILEGES ON guacamole_db.* TO 'guacamole_user'@'%';
FLUSH PRIVILEGES;
EXIT;


GRANT ALL PRIVILEGES ON guacamole_db.* TO 'guacamole_user'@'%';

sudo docker exec -i mysql mysql -u root -p guacamole_db < /home/initdb.sql



##Adding a New Storage Device

This server is designed so additional drives can be added without disrupting existing data.

1. Identify the new disk

After physically connecting the drive:

lsblk


Look for the new device (for example /dev/sdd). Do not assume the letter will stay the same across reboots.

2. Partition the disk

If the disk is empty, create a single GPT partition:

sudo fdisk /dev/sdX


Inside fdisk:

g → create GPT

n → new partition (accept defaults)

w → write changes

3. Format the partition

Format as ext4 (recommended for server storage):

sudo mkfs.ext4 /dev/sdX1

4. Create a mount point

Choose a clear, descriptive path:

sudo mkdir -p /media/<disk_name>


Example:

sudo mkdir -p /media/data_ssd2

5. Get the UUID

Always mount by UUID, not device name:

blkid /dev/sdX1


Copy the UUID value.

6. Add to /etc/fstab

Edit fstab:

sudo vi /etc/fstab


Add a line like:

UUID=<uuid_here> /media/data_ssd2 ext4 defaults 0 2


Notes:

0 = no dump

2 = filesystem check after root on boot

7. Mount and verify

Reload systemd and mount:

sudo systemctl daemon-reload
sudo mount -a


Verify:

df -hT | grep media


### Back up storage device

#### Confirm Main Drive Is Mounted
Verify the main drive is mounted:
df -h /media/data_ssd

#### Plug In the Backup Drive
Plug in the backup USB drive and confirm it mounted correctly:
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL

#### Final Sanity Check (Critical)
ls /media/data_ssd
ls /media/external_1

#### Dry Run (Required)
sudo rsync -avh --progress --delete --dry-run /media/data_ssd/ /media/external_1/

#### Run the Real Mirror Backup
sudo rsync -avh --progress --delete /media/data_ssd/ /media/external_1/

#### Verify the Mirror
ls /media/external_1
sudo rsync -avh --dry-run /media/data_ssd/ /media/external_1/

#### Safely Unmount the Backup Drive
sudo umount /media/external_1

### Docker
#### stop all containers, delete all containers, then delete all images
docker stop $(docker ps -aq) && docker rm $(docker ps -aq) && docker rmi -f $(docker images -aq)


## Nextcloud
user is db user not root
password is db pass not root pass


create a new user like alanh and sym link it to alan directory
docker exec -it nextclound /bin/bash
remove newly created user folder
rm -R alanh/
ln -s /var/www/html/alan/ /var/www/html/alanh
chown -h www-data:www-data alanh

then scan folders so the database will recognize them 
/var/www/html# php occ files:scan --all


## Networking
make wg-docker-routing.sh executable
sudo chmod +x system/networking/wg-docker-routing.sh

copy wg-docker-routing.sh to /usr/local/sbin/wg-docker-routing.sh
sudo cp system/networking/wg-docker-routing.sh /usr/local/sbin/wg-docker-routing.sh

run wg-docker-routing.sh file on the host machine
sudo wg-docker-routing.sh

make sure system\networking\wg-docker-routing.service is placed in /etc/systemd/system/wg-docker-routing.service
sudo cp system/networking/wg-docker-routing.service /etc/systemd/system/wg-docker-routing.service

run 
sudo systemctl daemon-reload
sudo systemctl enable wg-docker-routing


## Git Submodules

### Adding a new submodule

```
git submodule add <repo-url> <path>
```

Example:
```
git submodule add https://github.com/a-hardin/hardin-resources system/hardin-resources
```

Then commit the changes:
```
git add .gitmodules <path>
git commit -m "Add <name> as submodule"
```

### Initializing submodules on the server

After cloning the repo or pulling changes that include new submodules, run:

```
git submodule update --init --recursive
```

To pull the latest changes for all submodules:
```
git submodule update --remote --recursive
```

## Wireguard
### Adding vpn entry
This is done on the vps. A new peer needs to be added to the docker_composer.yaml file on the ovh-vps repo.