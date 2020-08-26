#!/usr/bin/env bash

# check if MySQL master slave replication is running by checking slave status

# CONSTANTS
# email to send alert to
MAILTO=""
SENDMAIL=0
MASTER=""
SLAVE=""

# slave replication checks
# if either Slave_SQL_Running or Slave_IO_Running report as No, then replication is not working
slave_sql_running=$(mysql -e "SHOW SLAVE STATUS\G;" | grep "Slave_SQL_Running\: Yes")
if [ $? -eq 1 ]; then
  # the slave SQL thread is not running, replication is not working, need to alert via email
  slave_sql_running="Slave SQL not running"
  SENDMAIL=1
fi

slave_io_running=$(mysql -e "SHOW SLAVE STATUS\G;" | grep "Slave_IO_Running\: Yes";)
if [ $? -eq 1 ]; then
  # the slave IO thread is not running, replication is not working, need to alert via email
  slave_io_running="Slave IO not running"
  SENDMAIL=1
fi

last_error=$(mysql -e "SHOW SLAVE STATUS\G;" | grep "Last_Error\:")

if [ $SENDMAIL -eq 1 ]; then
  echo -e "MySQL replication found not working.\n\nSlave SQL status:\n$slave_sql_running\n\nSlave IO status:\n$slave_io_running\n\n$last_error" | mail -v -s "MySQL replication between $MASTER and $SLAVE not working" $MAILTO
fi
