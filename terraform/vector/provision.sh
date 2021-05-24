set -e

# Install curl, gnupg, ca-certificates
sudo apt-get update -y
sudo apt-get install -y unzip ca-certificates curl gnupg apt-transport-https

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install -i /usr/local/aws-cli -b /usr/local/bin

# Install Vector
curl -1sLf "https://repositories.timber.io/public/vector/gpg.3543DB2D0A2BC4B8.key" | sudo apt-key add -
curl -1sLf 'https://repositories.timber.io/public/vector/config.deb.txt?distro=ubuntu&codename=focal&version=20.04&arch=x86_64' > /tmp/builder/timber-vector.list
sudo mv /tmp/builder/timber-vector.list /etc/apt/sources.list.d/timber-vector.list
sudo apt-get update -y
sudo apt-get install -y vector

# Move Vector config file to the correct location
sudo mkdir -p /etc/vector
sudo mkdir -p /var/lib/vector
sudo mv /tmp/builder/vector.toml /etc/vector/vector.toml

# Clean up uploaded files & apt cache
rm -rf /tmp/builder/
sudo apt clean