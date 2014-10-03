/*
"id", "drug","company","indication", "phase","therapy_area","flag"
*/
use pharmaview;
DROP TABLE IF EXISTS DGpipeline;

CREATE TABLE DGpipeline (
id int(10),
drug varchar(255),
company varchar(255),
indication varchar(255),
phase varchar(255),
therapy_area varchar(255),
flags tinyint
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

LOAD DATA LOCAL INFILE 'res.txt' into table DGpipeline FIELDS TERMINATED BY '\t';