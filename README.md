UPDATED VERSION: pg-patroni-backrest

Latest changes are:

- Archive command is now set upon initialization to pgbackrest 

- Recovery.conf is now configured with pgbackrest as the restore command 
  and persists even if a node is shutdown.  You can see this with:
  pc edit-config prod

- A template for pgbackrest.conf is now built in /etc/pgbackrest.conf (which 
  is the default for pgbackrest) and is owned by postgres

- /etc/patroni_prod.yml is now owned by postgres

- Patroni service is enabled so it restarts on reboot

- Etcd service is enabled for restart on reboot

- In the hosts.cfg file, you can now specify a master host and 2 replicas 
  in separate sections.  The master will start first and be the leader in 
  the cluster.

- Cluster is now expected to be 3 postgres hosts so that etcd will not have 
  a problem picking a new leader if the current master fails.  I’ve been 
  testing this all day and it works correctly.   It was easier than trying 
  to modify files all over the cluster and is more redundant (if one server 
  fails, there will always be a master and a replica running).  
  Etcd is installed on the postgres hosts by default.

- All the postgressql.conf parameters are very basic during the 
  initial build of the system.  These can be changed anytime with 

  pc edit-config <cluster_id> followed by pc restart <cluster_id>.

- The pgpass file is now being put in /var/lib/pgsql/.pgpass.prod. I moved 
  it there because, if a system crashes, it might be lost in /tmp.

You will need to modify the following files to match your environment:
 
- Hosts.cfg – where you define all the hosts in the cluster.

- /group_vars/all/vars.yml – where you define the cluster name, whether 
  to add disks or not, etc.

- /roles/install-patroni-master/templates/pgbackrest_master.conf. 
   put in your AWS info there before building the cluster and change anything 
   else you need.

- /roles/install-patroni-replica/templates/pgbackrest_replica.conf – put 
   AWS info in there before building the cluster and change anything else you 
   need.

In those same two directories, you can see the changes I made in 
patroni_yml.j2 for the archive command and the recovery.conf section.
 
For pgbackrest.conf, I am defaulting the stanza name to the 
cluster name (prod) and the default location for logs to 
/data1/backups_prod. Pg1-path is set to /data1/data_prod. That is also 
what Is being put in the archive_command and recovery.conf restore command.

Everything below here is the original instructions.

Jim McCann
July, 2020

- Overview

This has been tested on AWS using the base CentOS 7 image.
This ansible script will do the following:

After meeting the prerequisites, it will:

- update the OS (if it has not already had yum update -y run)
- reboot the system (if this script runs yum update -y) to apply changes
- format and mount multiple disks for data/indexes/etc. if required
- install packages required for vmware-postgres and Patroni
- install PostGIS 2.5 for this version of Postgres
- install etcd as the heartbeat service on either the haproxy server
  OR on the Postgres servers themselves.  I recommend the latter setup.
- set up Patroni service and YAML file
- use Patroni to initialize the database and start replication
- set up the HAproxy server and start the web service for it.

A Makefile has been provided to simplify this.  Typing "make" will
show you what options are available.  These are:

make ping    - insure your PC can ping the AWS servers.  It is recommended
that you run this after you modify pghosts.cfg to insure you can connect
to your AWS instance before you run make deploy-timescaledb

make check-syntax   - quick syntax check of the playbook

make deploy-ha      - actually runs the playbook for you

NOTE: the PostGIS included does not include the following two extensions:

- postgis_raster
- postgis_sfcgal

It will create the following extensions:
- postgis
- postgis_topology
- fuzzystrmatch
- address_standardizer
- address_standardizer_data_us
- postgis_tiger_geocoder

These scripts assume you have ansible installed and a working internet 
connection that can connect to AWS.

- Prerequisites (these are required for these ansible scripts to work):

  1. Modify file hosts.cfg   Change the following:
  
  - ansible_user   I've defaulted this to centos for the base Amazon image
    but you can use whatever user you need.
  - ansible_ssh_private_key_file   Set this to your PEM file for access
  - ansible_host  Put in the external IP of your AWS CentOS image
  - etcd_id - this is for etcd to recognize who does what in the cluster.
    There must be at least one server labeled "etcd0".  Whether this is
    the haproxy server or the first database server, this value must be 
    there.   Set it for both groups; it is ignored depending on what the
    use_external_dcs flag is set to in the group_vars file.

  2. Modfiy group_vars/all/vars.yml.  These are global variables required for
     the ansible script to work correctly.  I've set up a symbolic link to
     this file in the main directory to make it easier to edit.

  - If you are not adding disks to the system (for postgres data),
    do the following:

    - set the variable add_disk to 0
    - The default location for catalogs/data in vmware-postgres is: 
      /var/lib/pgsql
    - in the last section (postgresql_cluster), set datadir_parent to 
      the location/path where you want the catalog and data files stored.

  - If you are are adding additional disk(s) to the system (for postgres data)
    and want this script to format and mount them, do the following:

    - set the variable add_disk to 1
    - set the variable only_change_disk_permissions to false
    - modify the disk_list section 
    - for each disk you want formatted/mounted, set up:
       - mount_point:  where the disk should be mounted
       - device_raw:  the device name shown by the lsblk command
       - device_formatted: after formatting, what the device name is to 
         actually mount 
    - in the last section (postgresql_cluster), set datadir_parent to 
      the disk/path location where the catalogs/data will be stored.

  - If you have additional disks to be used by postgres that are already
    formatted and mounted, set the following:

    - add_disks: 1
    - only_change_disk_permissions: true

    This will change the ownership of the mount points in disk_list to
    postgres:postgres so that tablespaces can be created there.

    3. To setup the system to be deployed, edit the postgresql_cluster:
       section of group_vars/all/vars.yml.  This needs to be set to:

       name: the name of the cluster.  REQUIRED by patroni

       primary_port:  the port you will talk to the read/write master instance
       on.
       
       replica_port:  The port that haproxy can talk to the read-only
       replica instance of Postgres on.

       patroni_port:  default is 8008.  This is where patroni listens for
       changes to the system and is REQUIRED.
 
       datadir_parent:  The path to where the Postgres catalog and data
       files will be set up on both the master and replica servers.  Must
       be physically identical on each host.   
  
    4. In this same file, set the variable "use_external_dcs" to either 
       True or False.   If set to False, etcd will be installed on the 
       postgres servers.  If set to True, etcd will be installed on the
       HAproxy server.   I recommend setting this to False.

- Because this system is managed by patroni, all the timescaledb-tune
  parameters are set in the /etc/patroni_<name>.yml file.  You do not
  need to run timescaledb-tune.  

- Because it is Patroni-managed, it will initialize all servers.  You cannot
  have a running Postgres instance on one server and add this later.  All
  database servers should have no Postgres already set up on them.

- To deploy a replicated, patroni-managed system, run:

   make ping     This insures that all host IPs in the hosts.cfg file
                 can be pinged and are accessible by ansible.
   
   make deploy-ha

  That will set up a running mware postgres with postgis and timescaledb 
  installed.   You can confirm this is working one of two ways:

  - in a browser, put in the the IP address of the HAproxy server with 
    port 7000.  That is:  http://<haproxy-ip>:7000   This will give you
    the HAproxy monitoring web interface.  You should see both the master
    and replica running there.

  - log onto the master Postgres server and, as user postgres, run:

    pc list <name of the cluster assigned in postgresql_cluster>

    That should show the first host as leader (master) and the second
    host as the replica.

  After executing this, to get timescaledb working, you will 
  need to log into the Pivotal Postgres master host and do the following:

  - To use timescaledb, become the postgres user and log into postgres.
    Create a new database and connect to it.
    In psql, run:  create extension if not exists timescaledb cascade;
    At this point, you can use timescale feature.   Refer to their 
    documentation at: 

    https://docs.timescale.com/latest/getting-started/creating-hypertables

    to get an idea on how to do this.

  - For PostGIS, log into your database and enter: 
    
    create extension postgis;

NOTES ON PATRONI and POSTGRES

You will no longer be using any Postgres commands (pg_ctl) to manage the
system.   Instead, everything is managed by a program called "patronictl".
I've set up a helper script called "pc" in /usr/local/bin to run this for 
you.

On any indidual server, root can start/restart/stop the patrioni process
with:  systemctl <cmd> patroni_<cluster name>.  However, this only stops
patroni ON THAT SERVER.  It does not stop all the instances in the cluster.

Instead, patronictl can do that for you. The normal syntax is:

patronictl -c <patroni.yml file> <command>  OR
patronictl -d etcd://<etcd IP address> <command>

The pc script is automatically set to the etcd server to use.  Some
examples of this command are (assuming the cluster is named "dev"):

pc list dev     - lists the members of the cluster and current status
pc restart dev  - restarts one or all of the servers in the cluster
pc reload dev   - reloads the configuration files of all cluster servers

Note that you know longer manually edit pg_hba.conf or postgresql.conf.
Instead use:  pc edit-config <cluster id>

This will let you make changes to either of these files.  Typically, if
you change postgresql.conf parameters, it will require:  pc restart <cluster>

If you change pg_hba.conf, you would use:  pc reload <cluster>

I have included a file in /var/lib/pgsql called hba_proto.txt.  This can be
included in the configuration the first time you edit it so that any 
patroni service restart won't overwrite changes to pg_hba.conf.

If you wish to failover the master to a replica, or switch roles, you can
use:

pc failover <cluster>

That will confirm which cluster member you will failover to and will make
the current master a replica server.

To work on server, you can use:

pc pause <cluster>

This disables automatic failover so you can then do something on a specific 
host like stop a database (with pg_ctl), upgrade software, 
then restart it (pg_ctl) and issue:  pc resume <cluster>
