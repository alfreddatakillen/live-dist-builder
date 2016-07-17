# live-dist-builder

Example: How to build a USB live distro within a docker container. Based on Debian Jessie.

## What is this?

This was made as an example on how to build your own USB live distribution within a Docker container, so your build environment just depends on docker, bash and an Internet connection.

Run the `./run.sh` bash script. When finished, there will be an `usb.img`, which is the USB image file.

## How to use it?

Grab the code and build something cool! This example just builds a very thin Debian Jessie.

You probably should begin at row 174 in `run.sh`, installing and fixing stuff that you need for your own Live USB Linux Distribution.


