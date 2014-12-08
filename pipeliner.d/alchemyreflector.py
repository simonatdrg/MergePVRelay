
from sqlalchemy import create_engine, MetaData, Table

engine = create_engine('mysql+pymysql://root:mysql@localhost/ct')
meta = MetaData(bind=engine)
old = Table("ctdocs_old", meta, autoload=True, autoload_with=engine)
# >>> [c.name for c in person.columns]

for c in old.columns:
    print(c.name)
