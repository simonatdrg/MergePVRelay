#!/bin/bash
python3 maketagload.py | sort |uniq > allpvdrugs.txt
