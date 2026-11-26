# Minimal stand-in for $ORACLE_HOME/install/response/db_install.rsp.
# Used only by the test suite: it reproduces the awkward parts of the real
# template (commented-out keys, a pre-set key, and keys that are absent
# entirely) so the generator's replace/append/de-duplicate paths get exercised.

oracle.install.responseFileVersion=/oracle/install/rspfmt_dbinstall_response_schema_v19.0.0
oracle.install.option=INSTALL_DB_AND_CONFIG
ORACLE_HOSTNAME=localhost.example.com
UNIX_GROUP_NAME=
INVENTORY_LOCATION=
SELECTED_LANGUAGES=en
ORACLE_HOME=
ORACLE_BASE=
oracle.install.db.InstallEdition=EE
oracle.install.db.OSDBA_GROUP=dba
oracle.install.db.OSOPER_GROUP=
# oracle.install.db.OSBACKUPDBA_GROUP=dba
# oracle.install.db.rootconfig.executeRootScript=true
