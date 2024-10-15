# homeserver
homeserver setup


Notes on setting up guacamole database
docker exec -it mysql /bin/bash
mysql -u root -p
<enter root password>
CREATE DATABASE <guacamole db name>;
GRANT ALL PRIVILEGES ON <guacamole db name>.* TO '<db username>'@'%';
FLUSH PRIVILEGES;
EXIT;