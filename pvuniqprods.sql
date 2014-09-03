use pharmaview;
drop table if exists pvprods;
create table pvprods select * from pvsuperset group by product_id ;
