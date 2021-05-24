#!/bin/bash
# Setting AWS_PAGER off to force the cli to just dump the output without
# grabbing the focus of the tty
export AWS_PAGER=
echo "LOKI_USER=${username}" >> /etc/default/vector
echo "LOKI_PASSWORD=${password}" >> /etc/default/vector
service vector restart