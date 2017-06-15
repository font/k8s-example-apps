FROM node:boron

MAINTAINER Ivan Font <ifont@redhat.com>

# Create app directory and specify volume that will be bind mounted at runtime
RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app
VOLUME ["/usr/src/app"]

# Expose port 8080
EXPOSE 8080

# Run container
CMD ["npm", "run", "dev"]
