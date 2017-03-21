FROM ubuntu:16.04

MAINTAINER Ivan Font <ifont@redhat.com>

# Update and install packages
# Mongo
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 0C49F3730359A14518585931BC711F9BA15703C6
RUN echo "deb [ arch=amd64,arm64 ] http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.4 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-3.4.list
# Install Packages
RUN apt-get -y update && apt-get -y install mongodb-org

# Add mongod data directory
RUN mkdir -p /data/db

# expose mongo port
EXPOSE 27017

# Run mongo
CMD /usr/bin/mongod --replSet rs0
