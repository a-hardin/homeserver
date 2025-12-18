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