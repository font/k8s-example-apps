FROM ubuntu:16.04

MAINTAINER Ivan Font <ifont@redhat.com>

# Update and install packages
# Mongo
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 0C49F3730359A14518585931BC711F9BA15703C6
RUN echo "deb [ arch=amd64,arm64 ] http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.4 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-3.4.list
# Install Packages
RUN apt-get -y update && apt-get -y install mongodb-org

# node.js
RUN curl -sL https://deb.nodesource.com/setup_6.x | bash - \
    apt-get install -y nodejs

# Add mongod data directory
RUN mkdir -p /data/db

# Create app directory and specify volume that will be bind mounted at runtime
RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app
VOLUME ["/usr/src/app"]

# expose mongo port
EXPOSE 27017

# Expose port 8080
EXPOSE 8080

# Run mongo
CMD /usr/bin/mongod --fork --replSet rs0 && npm run dev
