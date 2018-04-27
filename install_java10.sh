#!/usr/bin/env bash

echo "Installing Java 10..."

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
