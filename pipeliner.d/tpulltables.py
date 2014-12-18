#!/usr/bin/env python3
# test pvmaptablespull by pulling the two drug tables
from pvmaptablespull import pvmap

map = pvmap()
#map.makecsv("pvp_production.molecule", "foo.txt")
map.dumptable("pvp_production", "molecule", fname='moltab.txt')
map.dumptable("pvp_production", "drug", fname='drugtab.txt')
