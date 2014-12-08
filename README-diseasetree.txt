# get all basic mesh info including ancestors,children
SELECT DISTINCT meshid, mh, treeloc,
group_concat( child  SEPARATOR ';' ) AS kids,
group_concat( parent SEPARATOR ';' ) AS ancestors
FROM `meshtree`
GROUP BY meshid
filter kids and ancestors to remove nulls or empry (can be multiple semicolons w/o text)

create 

# remove heads found by
SELECT *
FROM `relayextra`
WHERE act = 'delete-head': col src id has meshids to be deleted

or both together ?

SELECT DISTINCT meshid, mh, treeloc,
group_concat( child  SEPARATOR ';' ) AS kids,
group_concat( parent SEPARATOR ';' ) AS ancestors
FROM `meshtree` where meshid not in (SELECT srcid as meshid
FROM `relayextra`
WHERE (act = 'delete-head'))
GROUP BY meshid

# iterate through edited table:

need to dedupe ancestors

create

1. AOA [meshid, mh]
2. AOA [meshid, treeloc, kids, ancestors]

save these as 2 json structures

---------------------
# build data structures for navigation in Perl:

1) above: two hashes to do lookup by k or v head/meshid

2) above: 2 data structures:
    hash1: key is meshid: v = array of  [multiple] treelocs
    hash1a: need reverse of this ???
    
    hash2a: key is treeloc:  v = array of ancestors (treelocs)
    hash2k: key is treeloc:  v= array of kids(treelocs)
    
----
navigation for our problem:
Given a condition ht (i.e. mh):
look up meshid


