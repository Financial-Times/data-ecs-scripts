#!/usr/bin/env bash

echo "Installing Java 11..."

sudo wget https://download.java.net/java/GA/jdk11/13/GPL/openjdk-11.0.1_linux-x64_bin.tar.gz
sudo tar xzvf openjdk-11.0.1_linux-x64_bin.tar.gz
sudo mv jdk-11.0.1 /usr/lib/jvm/java-11-openjdk-amd64/
sudo update-alternatives --install /usr/bin/java java /usr/lib/jvm/java-11-openjdk-amd64/bin/java 1
sudo update-alternatives --install /usr/bin/javac javac /usr/lib/jvm/java-11-openjdk-amd64/bin/javac 1
echo 1 | sudo update-alternatives --config java
echo 1 | sudo update-alternatives --config javac
sudo java --version
sudo javac --version

echo "done."
