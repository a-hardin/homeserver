# homeserver
homeserver setup


Notes on setting up guacamole database
docker exec -it mysql /bin/bash
mysql -u root -p
<enter root password>
CREATE DATABASE guacamole_db;
CREATE USER 'guacamole_user'@'%' IDENTIFIED BY 'fakepassword';
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


## Deployment

Automatic. A push is live in about 5 minutes.

- Push to a site repo: its GitHub Action commits the new submodule pointer here.
- Push here (`master`): the server polls every 5 minutes and runs `scripts/deploy.sh` (pull, submodules, `docker compose up -d`, `nginx -t`, reload). Failed deploys retry.

On the server (repo is owned by root, use `sudo` for git):
```
systemctl status homeserver-deploy.service         # last run
journalctl -u homeserver-deploy -n 40 --no-pager   # logs
sudo systemctl start homeserver-deploy.service     # deploy now
```

Install the timer (new server, or after editing the unit files):
```
sudo cp /var/www/homeserver/system/systemd/homeserver-deploy.* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now homeserver-deploy.timer
```

Tokens (fine-grained, values shown only once):
- Sites read-only (`Contents: Read-only` on the site repos): saved in `/root/.git-credentials` on the server.
- Homeserver write (`Contents: Read and write` on `homeserver`): `HOMESERVER_TOKEN` secret in each site repo.

Before committing here: `git pull --ff-only && git submodule update`.

### Adding a new private site

1. GitHub: add the repo to the sites read-only token's repository list (do not regenerate).
2. Here: `git submodule add https://github.com/a-hardin/<repo>.git system/<site>`
3. Here: add `system/nginx/conf.d/<site>.conf` (copy `streamline.conf`).
4. Here: add `- ./system/<site>/public:/var/www/<site>:ro` to the nginx volumes in `docker-compose.yaml`.
5. Commit and push.
6. Site repo: copy `.github/workflows/update-homeserver.yml` from another site; set the branch and `SUBMODULE_PATH`.
7. Site repo: add the `HOMESERVER_TOKEN` secret, then push.
8. `ovh-vps` repo: add the domain, certificate and server block.

## Troubleshooting

### 502 Bad Gateway

If a site is returning 502, work through these checks in order:

#### 1. Check the VPS nginx error log
```
docker compose exec nginx cat /var/log/nginx/hardin-resources-error.log
```
If you see `connect() failed (111: Connection refused) while connecting to upstream: http://10.13.13.2:80` — the WireGuard tunnel is up but port 80/443 DNAT rules are missing inside the WireGuard container.

#### 2. Verify the WireGuard tunnel is up
From the VPS:
```
ping 10.13.13.2
```
If ping fails, the WireGuard tunnel is down. Restart the WireGuard container on the homeserver:
```
docker compose restart wireguard
```

#### 3. Check wg0.conf has the DNAT PostUp rules
On the homeserver:
```
sudo cat /var/www/homeserver/system/wireguard/wg_confs/wg0.conf
```
The `[Interface]` section must include:
```
PostUp = iptables -t nat -A PREROUTING -i wg0 -p tcp --dport 80 -j DNAT --to-destination 10.20.20.1:80
PostUp = iptables -t nat -A PREROUTING -i wg0 -p tcp --dport 443 -j DNAT --to-destination 10.20.20.1:443
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT

PostDown = iptables -t nat -D PREROUTING -i wg0 -p tcp --dport 80 -j DNAT --to-destination 10.20.20.1:80
PostDown = iptables -t nat -D PREROUTING -i wg0 -p tcp --dport 443 -j DNAT --to-destination 10.20.20.1:443
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
```
If the rules are missing, add them and restart the WireGuard container.

#### 4. Verify port 80 is reachable from the VPS
```
curl -v http://10.13.13.2:80
```
If still refused after confirming the PostUp rules are in place, restart the WireGuard container to re-apply them:
```
docker compose restart wireguard
```

#### 5. Confirm nginx is serving correctly on the homeserver
```
docker compose exec nginx nginx -t
curl -v http://172.19.0.3
```
If nginx config has errors or curl fails, the issue is local to the homeserver nginx container.

## Wireguard
### Adding vpn entry
This is done on the vps. A new peer needs to be added to the docker_composer.yaml file on the ovh-vps repo.