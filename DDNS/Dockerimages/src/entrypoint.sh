#!/bin/bash
while [ 1 -eq 1 ]
do
    `/bin/bash namesiloddns-dk.sh`
    sleep ${looptime:-10}m
done