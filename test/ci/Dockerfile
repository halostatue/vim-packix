# syntax=docker/dockerfile:1

ARG ALPINE_VERSION=3.20

FROM alpine:$ALPINE_VERSION

RUN <<SETUP
set -eux

apk update
apk add \
      bash \
      curl \
      git \
      openssl \
      vim

rm -rf /var/cache/apk/* /tmp/*

adduser --disabled-password packix
mkdir -p /home/packix/.vim/pack/packix/opt/vim-packix/plugin
chown -R packix:packix /home/packix /home/packix/.vim
SETUP

ENV LESS=-R LC_ALL=C.UTF-8 LANG=C.UTF-8
ENV HOME=/home/packix

USER packix
WORKDIR /home/packix

ENTRYPOINT []
