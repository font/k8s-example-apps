FROM node:boron

MAINTAINER Ivan Font <ifont@redhat.com>

# Create app directory
RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

# Clone game source code
RUN git clone https://github.com/font/pacman.git .

# Update mongo host from 'localhost' to 'mongo'
RUN sed -i 's/localhost/mongo/' routes/config.js

# Install app dependencies
RUN npm install

# Expose port 80
EXPOSE 80

# Run container
CMD ["npm", "start"]
