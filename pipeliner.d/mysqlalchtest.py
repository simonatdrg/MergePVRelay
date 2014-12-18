
from sqlalchemy import create_engine, MetaData, Table
from sqlalchemy.sql import *

engine = create_engine('mysql+pymysql://root:mysql@192.168.100.150/ct')
conn=engine.connect()

meta = MetaData(bind=engine)
ctdocs = Table("ctdocs", meta, autoload=True, autoload_with=engine)
# >>> [c.name for c in person.columns]
#for c in old.columns:
#    print(c.name)
s = select([ctdocs.c.all_facet_date])
result=conn.execute(s)
for row in result:
    print(row)

