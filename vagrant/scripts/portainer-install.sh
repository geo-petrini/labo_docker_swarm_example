#!/bin/bash

mkdir /tmp/portainer
echo -n mypassword > /tmp/portainer/portainer_password.txt
docker volume create portainer_data
# https://docs.portainer.io/advanced/cli

# run portainer-ce image with
# - connection to docker socket
# - mount the local /tmp/portainer folder as /tmp/portainer (which contains the portainer_password.txt file)
# - mount the volume portainer_data as /data
# - expose ports 9443 and 8000 (but 8000 does not work)
# - detached mode
docker run -d -p 9443:9443 -p 8000:8000 --name portainer -v /var/run/docker.sock:/var/run/docker.sock -v /tmp/portainer:/tmp/portainer -v portainer_data:/data portainer/portainer-ce:latest --admin-password-file /tmp/portainer/portainer_password.txt

echo ---------------------------------------------
echo "Open link https://192.168.56.10:9443 and log in with admin:"`cat /tmp/portainer/portainer_password.txt`
echo ---------------------------------------------