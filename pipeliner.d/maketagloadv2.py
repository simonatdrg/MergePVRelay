#!/usr/bin/env python3
"""
maketagloadv2
main program to generate an input file for the tagger from PV drug data
This pulls the drug and molecule tables from the PV db and merges so that we
have a syn file for the tagger with the following (enhanced) data structure:

The syn field will have all brand/molecule/research names and the head field will have one or more
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
import pdb

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
    molnamedict = set()
    molname2brand = dict()
 #   pdb.set_trace()
    
    for ro in moltablist:
        sys.stderr.write(str(ro) +"\n")
        nm = ro['molecule_name']
        if nm == None:
            sys.stderr.write('#')
            continue
        
        moldict[ro['id']] = nm
    #    if nm not in molnamedict:  
    #        molnamedict[nm].add(ro['id'])  # list of molids for each name
    
            
    # keep track of molecules we've seen in the drug table
    molseenset= set()
    mnameseenset = set()
 # start builing complete syn/head list
 # outdict will be the main data structure
 # key = drug to lookup: (concatenation of brand, rcode and molname)
 # val : list of two sets(): 0) = heads  1) = ids()
    outdict = dict()
    
    for ro in drugtablist:
        sys.stderr.write(str(ro) +"\n")
 #       print(ro, file=sys.stderr)
        bid =ro.get('id')
        brand = ro.get('brand_name');
        brand = brand.lstrip().rstrip()
        mid = ro.get('molecule_id')
        rcode = ro.get('research_code','')
        if (rcode != None):
            rcode = rcode.lstrip().rstrip()
        else:
            rcode=''

        
        if mid != None:
            molseenset.add(mid)
    # if not seen, set up head/syn/id and make self a syn   
        if (brand not in outdict):
            outdict[brand] = (set(),set())  # list of two dicts as above
            outdict[brand][0].add(brand)
        
        outdict[brand][1].add("B"+str(bid))
        outdict[brand][0].add(brand)
        
        if (len(rcode) > 0) and (not rcode.isspace()):
            outdict[brand][0].add(rcode)
            # also create a syn for the rcode
            if (rcode not in outdict):
                outdict[rcode] = (set(),set())
                outdict[rcode][0].add(rcode)
    # mol ids
        if mid != None:
            molname = moldict[mid]
            outdict[brand][0].add(molname)
            outdict[brand][1].add("M" + str(mid))
            if molname not in outdict:
                 outdict[molname] = (set(),set())
                 outdict[molname][0].add(molname)
      
        
 # now generate entires for all molecules not previously seen
    sys.stderr.write('starting mol syns\n')
    
    for mrow in moltablist:
        mid = mrow.get('id')
        moname = mrow.get('molecule_name')
        # then (creating elements if needed in outdict) add the information
        if moname not in outdict:
            outdict[moname] = (set(),set())
        outdict[moname][0].add(moname)
        outdict[moname][1].add("M" + str(mid))
        
    # now write out the rows
    sys.stderr.write("start write\n")
    for ro in sorted(outdict):
        if (ro.isspace()) or (len(ro) == 0): continue
        s1 = '|'.join(outdict[ro][0])
        s1 = s1.lstrip().rstrip()
        s2 = '|'.join(outdict[ro][1])
        s2 = s2.lstrip().rstrip()
        print(ro + "\t" + s1 + "\t" + s2)
        
    sys.stderr.write("end write\n")
################

main()
