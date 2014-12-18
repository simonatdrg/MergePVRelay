#!/usr/bin/env python3

"""
module to pull mapping tables from SQL Server using FreeTDS driver
Uses sqlalchemy(pip install), pyodbc(pip install) and odbc(Centos)
TDS config: /usr/local/etc/freetds.conf
Let us give thanks to the recipe at https://gist.github.com/rduplain/1293636/download#
"""

from sqlalchemy import create_engine, MetaData, Table
from sqlalchemy.sql import *
from urllib.parse import quote
import csv

# constants
dbuser   = "pharmaview1"
dbserver = "USE1B-SQL3.dresources.com"
dbpasswd = "pharmaview1"
pvdb="Pharmaview"


class pvmap:
    def __init__(self):
        conn='DRIVER=FreeTDS;SERVER={0};PORT=1433;DATABASE={1};UID={2};PWD={3};TDS_Version=8.0;'.\
        format(dbserver, pvdb, dbuser, dbpasswd)

        u=quote(conn)
 #       print(u)
        self.engine = create_engine('mssql+pyodbc:///?odbc_connect=' + u)
        self.conn = self.engine.connect()
        self.meta = MetaData(bind=self.engine)


# dumptable - pull a  mapping table do a sleect all> returns a dictionary

    def dumptable(self,sch, tablename, fname=''):
        tname = Table(tablename, self.meta, \
            autoload=True, autoload_with=self.engine, schema=sch)
        if (len(fname) > 0):
            fh = open(fname,"w")
        st = select([tname])
        result=self.conn.execute(st)
       # test
        resultset =[]
        nc=0
        for row in result:
          #  print(row.keys())
            if(len(fname) > 0):
                if(nc ==0):
                    fh.write('\t'.join(row.keys())+"\n")
                          
                fh.write('\t'.join(str(k) for k in row.values())+"\n")
                nc += 1
# need to be able to iterate through columns here
            resultset.append(dict(row))
            
        return resultset

        
