#!/usr/bin/env bash

echo "Installing Java10..."

# sudo apt-get install -y software-properties-common
# sudo add-apt-repository -y ppa:webupd8team/java
# sudo apt-get update -y
# echo oracle-java9-installer shared/accepted-oracle-license-v1-1 select true | sudo /usr/bin/debconf-set-selections
# sudo apt-get install -y oracle-java9-installer
# sudo apt-get install -y oracle-java9-set-default

sudo wget https://download.java.net/java/GA/jdk10/10.0.1/fb4372174a714e6b8c52526dc134031e/10/openjdk-10.0.1_linux-x64_bin.tar.gz
sudo tar xzvf openjdk-10.0.1_linux-x64_bin.tar.gz
sudo mv jdk-10.0.1 /usr/lib/jvm/java-10-openjdk-amd64/
sudo update-alternatives --install /usr/bin/java java /usr/lib/jvm/java-10-openjdk-amd64/bin/java 1
sudo update-alternatives --install /usr/bin/javac javac /usr/lib/jvm/java-10-openjdk-amd64/bin/javac 1
echo 1 | sudo update-alternatives --config java
echo 1 | sudo update-alternatives --config javac
sudo java --version
sudo javac --version

echo "done."
