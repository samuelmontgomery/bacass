# Get base ubuntu docker image
FROM ubuntu:24.04

# Install and update packages
RUN apt-get update && apt-get install -y
