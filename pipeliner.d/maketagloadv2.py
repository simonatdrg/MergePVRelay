#!/usr/bin/env python3
"""
maketagloadv2
main program to generate an input file for the tagger from PV drug data
This pulls the drug and molecule tables from the PV db and merges so that we
have a syn file for the tagger with the following i(enhanced) data structure:

The syn field will have all brnd/molecule/research names and the head field will have one or more
head terms depending on what the syn field is:

If the synfield is a brandname:
- then the head will have a delim separated list of
brandname|mol name|[research code] (there are a few brands w/o mol name)
This Id field will have BID and MID(for most)

If the synfield is a molecule name:

# drug data
syn   | brand as head | drug id | mol id
syn can be each of non-empty brandname, researchcode or  molname (pulled from join)
# mol data where mol is not joined to drug data
mol name | mol name | mol id

Ids are prefixed by B or M to indicate their provenance
"""
#######    V1 --- rewrite ###
from pvmaptablespull import pvmap
import sys

def drug_syn_entry(syn,head,id, molid):
#    print("debug", str(syn),str(head), str(id),str(molid))
    mid = '' if (molid == None) else 'M'+str( molid)
    bid = 'B' + str(id) if (id > -1) else ""
    s ='\t'.join([syn,head,bid, mid])
    return s


def main():
    sys.stderr = open("err.log","w")
    pvconn = pvmap()
    
    drugtablist = pvconn.dumptable('pvp_production', 'drug')
    moltablist  = pvconn.dumptable('pvp_production', 'molecule')
    # now some code to mimic joins ... maybe move this into pvmaptablespull
    # once we work out how to handle joins
    # create a dict from mol ids/mol name. drug
    moldict = dict()
    for ro in moltablist:
        moldict[ro['id']] = ro['molecule_name']
    # keep track of molecules we've seen in the drug table
    molseenset= set()
    mnameseenset = set()
    
    outlist =[]    
    for ro in drugtablist:
        sys.stderr.write(str(ro) +"\n")
 #       print(ro, file=sys.stderr)
        mid = ro.get('molecule_id')
        if mid != None:
            molseenset.add(mid)
            
        rol = drug_syn_entry(ro['brand_name'], ro['brand_name'], ro['id'],mid)
        print(rol)
        
    # entry for research code
        if ro['research_code'] != '' \
        and  ( ro['research_code'] != None):
            rol =drug_syn_entry(ro['research_code'],\
                ro['brand_name'], ro['id'], mid)
            print(rol)
            
    # entry for molecule
       
        mname = moldict.get(ro['molecule_id'],'')
    #    print("checking "+ mname)   
        if (mname != '') and ( mname != None):
            rol =drug_syn_entry(mname,\
            ro['brand_name'], ro['id'], mid)
            # this will eliminate mol--mol lines hopefully
            mnameseenset.add(mname)
            print(rol)       
        
 # now generate entires for all molecules not previously seen
    sys.stderr.write('starting mol syns\n')
    
    for mr in moltablist:
        sys.stderr.write(str(mr) +"\n")
        if mr['id'] not in molseenset:
            mname = mr['molecule_name']
            if (mname != '') and ( mname != None) and (mname not in mnameseenset):
                rol = drug_syn_entry(mname, mname, -1, mid)
                mnameseenset.add(mname)
                print(rol)       
        
################

main()
