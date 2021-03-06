#!/bin/bash
# Author: Vitaliy Kukharik (vitabaks@gmail.com)
# Title: /usr/bin/pgbackrest_auto - Automatic Restore PostgreSQL from backup

# Dependencies: OS Debian/Ubuntu, PostgreSQL >= 9.4, pgbackrest >= 2.01;
# for "--checkdb": amcheck_next extension/SQL version >=2 (https://github.com/petergeoghegan/amcheck)
# for "--report": sendemail, gawk, /usr/bin/ansi2html.sh (https://github.com/pixelb/scripts/blob/master/scripts/ansi2html.sh)
# Requirements: local trust for postgres (login by Unix domain socket) in the pg_hba.conf or ".pgpass"
# Run as user: postgres

ver="1.3"

# variables for function "sendmail()"
attach_report=true  # or 'false'

# Send report to mail address
function sendmail(){
    if [[ -z ${mail_to} ]]; then
        errmsg "missing email address"
    fi
    SUBJECT="pgbackrest restore report for ${FROM}: $(date +%Y-%m-%d) (auto-generated)"

    # convert log to html
    #if [ ! -f "${log}".html ]; then touch "${log}".html; fi
    #cat "${log}" | ansi2html.sh --bg=dark > "${log}".html

    # send mail
    if [ "$attach_report" = true ]; then
        cat ${log} | mail ${mail_to} -s "${SUBJECT}" -A ${log}
        #sendemail -v -o message-content-type=html -o message-file="${log}".html -f "${MAIL_FROM}" -t "${EMAIL}" -u "${SUBJECT}" -s "${SMTP}" -a "${log}".html
    else
        #sendemail -v -o message-content-type=html -o message-file="${log}".html -f "${MAIL_FROM}" -t "${EMAIL}" -u "${SUBJECT}" -s "${SMTP}"
        cat ${log} | mail ${mail_to} -s "${SUBJECT}"
    fi
}

function errmsg(){
    # Print error message
    # ARG: "error message"
    msg="$1"
    echo -e "$(date "+%F %T") WARN: $msg"
    return 1
}
function error(){
    # Print error message and exit
    # ARG: "error message"
    msg="$1"
    echo -e "$(date "+%F %T") ERROR: $msg"
    if [[ "${REPORT}" = "yes" ]]; then sendmail; fi
    exit 1
}
function info(){
    # Print info message
    # ARG: "info message"
    msg="$1"
    echo -e "$(date "+%F %T") INFO: $msg"
}
function blinkmsg(){
    # Print blink info message
    # ARG: "info message"
    msg="$1"
    echo -e "$(date "+%F %T") WARN: $msg"
}


while getopts ":-:" optchar; do
    [[ "${optchar}" == "-" ]] || continue
    case "${OPTARG}" in
        from=* )
            FROM=${OPTARG#*=}
            ;;
        to=* )
            TO=${OPTARG#*=}
            ;;
        amcheck )
             AMCHECK=yes
            ;;
        datname=* )
            DATNAME=${OPTARG#*=}
            ;;
        backup-set=* )
            BACKUPSET=${OPTARG#*=}
            ;;
        recovery-type=* )
            RECOVERYTYPE=${OPTARG#*=}
            ;;
        recovery-target=* )
            RECOVERYTARGET=${OPTARG#*=}
            ;;
        backup-host=* )
            BACKUPHOST=${OPTARG#*=}
            ;;
        pgver=* )
            PGVER=${OPTARG#*=}
            ;;
        checkdb )
            CHECKDB=yes
            ;;
        clear )
            CLEAR=yes
            ;;
        report )
            REPORT=yes
            ;;
        norestore )
            NORESTORE=yes
            ;;
        mail=* )
            mail_to=${OPTARG#*=}
            ;;
    esac
done


function help(){
echo -e "
$0

Automatic Restore PostgreSQL from backup

Support three types of restore:
        1) Restore last backup  (recovery to earliest consistent point) [default]
        2) Restore latest       (recovery to the end of the archive stream)
        3) Restore to the point (recovery to restore point)

Important: Run on the nodes on which you want to restore the backup

Usage: $0 --from=STANZANAME --to=DATA_DIRECTORY [ --datname=DATABASE [...] ] [ --recovery-type=( default | immediate | time ) ] [ --recovery-target=TIMELINE  [ --backup-set=SET ] [ --backup-host=HOST ] [ --pgver=( 94 | 10 ) ] [ --checkdb ] [ --clear ] [ --report ] ]


--from=STANZANAME
        Stanza from which you need to restore from a backup

--to=DATA_DIRECTORY
        PostgreSQL Data directory Path to restore from a backup
        Example: /var/lib/postgresql/11/rst

--datname=DATABASE [...]
        Database name to be restored (After this you MUST drop other databases)
        Note that built-in databases (template0, template1, and postgres) are always restored.
        To be restore more than one database specify them in brackets separated by spaces.
        Example: --datname=\"db1 db2\"

--recovery-type=TYPE
        immediate - recover only until the database becomes consistent           (Type 1. Restore last backup)  [default]
        default   - recover to the end of the archive stream                     (Type 2. Restore latest)
        time      - recover to the time specified in --recovery-target           (Type 3. Restore to the point)

--recovery-target=TIMELINE
        time - recovery point time. The time stamp up to which recovery will proceed.
        Example: \"2018-08-08 12:46:54\"

--backup-set=SET
        If you need to restore not the most recent backup. Example few days ago.
        Get info of backup. Login to pgbackrest server. User postgres
        pgbackrest --stanza=[STANZA NAME] info
        And get it. Example:
                    incr backup: 20180807-212125F_20180808-050002I
        This is the name of SET: 20180807-212125F_20180808-050002I

--backup-host=HOST
        pgBacRest repository ip address (Use SSH Key-Based Authentication)
        localhost [default]

--pgver=VERSION
        PostgreSQL cluster (instance) version [ optional ]

--checkdb
        Validate for Physical and Logical Database Corruption (requires Full PostgreSQL Restore)

--amcheck
        Validate Indexes (requires --checkdb)

--clear
        Clear PostgreSQL Data directory after Restore (the path was specified in the \"--to\" parameter ) [ optional ]

--report
        Send report to mail address

--norestore
        Do not restore a stanza but use an already existing cluster)

EXAMPLES:
( example stanza \"app-db\" , backup-host \"localhost\" )

| Restore last backup.

    # $0 --from=app-db --to=/var/lib/postgresql/11/rst

| Restore latest backup (recover to the end of the archive stream).

    # $0 --from=app-db --to=/var/lib/postgresql/11/rst --recovery-type=default

| Restore backup made a few days ago.

    # $0 --from=app-db --to=/var/lib/postgresql/11/rst --backup-set=20180807-212125F_20180808-050002I

| Restore backup made a few days ago and pick time.

    # $0 --from=app-db --to=/var/lib/postgresql/11/rst --backup-set=20180807-212125F_20180808-050002I --recovery-type=time --recovery-target=\"2018-08-08 12:46:54\"

| Restore backup made a few days ago and pick time. And we have restore only one database with the name \"app_db\".

    # $0 --from=app-db --to=/var/lib/postgresql/11/rst --datname=app_db --backup-set=20180807-212125F_20180808-050002I --recovery-type=time --recovery-target=\"2018-08-08 12:46:54\"

| Restore and Validate of databases (for example: pgBacRest repository 10.128.64.50, PostgreSQL version 11)

    # $0 --from=app-db --to=/var/lib/postgresql/11/rst --backup-host=10.128.64.50 --pgver=11 --checkdb
"
exit
}
[ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ] && help
if [ "$1" = "-v" ] || [ "$1" = "--version" ] || [ "$1" = "version" ]; then echo "$0 version ${ver}" && exit; fi

USR=$(whoami)
if [ "$USR" != 'postgres' ]; then
    error "$0 must be run as postgres"
fi

sleep=1
limit=3600
# Log - add date to prevent rotation
log="/var/log/pgbackrest/pgbackrest_testrestore_${FROM}.log"
# Global lock
lock="/tmp/pgbackrest_auto_${FROM}.lock"
exec 9>"${lock}"
flock -n 9 || exit

if [[ -z ${mail_to} ]]; then
    errmsg "missing email address"
fi


[[ -z "${FROM}" ]] && error "--from is missing"
[[ -z "${TO}" ]] && error "--to is missing"
[[ -z $RECOVERYTYPE && -n $RECOVERYTARGET ]] && error "--recovery-type is missing"
if [[ $RECOVERYTYPE != default ]]; then
    [[ -n $RECOVERYTYPE && -z $RECOVERYTARGET ]] && error "--recovery-target is missing"
fi
# recovery-type - default
if [[ -z $RECOVERYTYPE ]]; then RECOVERYTYPE="immediate"; fi

[[ $RECOVERYTYPE = immediate || $RECOVERYTYPE = default || $RECOVERYTYPE = time ]] || error "--recovery-type=( immediate | default | time )"
[[ $RECOVERYTYPE = default && -n $RECOVERYTARGET ]] && error "Not use --recovery-type=default with --recovery-target"
if [[ -n $DATNAME && -n $CHECKDB ]]; then
error "Not use --checkdb with --datname. It work with only Full PostgreSQL Restore"
fi

PGVER=$(pgbackrest info --stanza=${FROM} --output=json | jq '.[].db[]."version"'  | sed 's/"//g')

# PostgreSQL
#pg_instance="main"
pg_instance="${FROM}_restore"
if [[ -z $PGVER ]]; then
    error "PGVER not found"
fi

# get the databese size of the given or last backup set
# json output does not support --set parameter
if [[ $RECOVERYTARGET ]]; then
    DBSIZE=$(pgbackrest info --stanza=${FROM} --output=json | jq '.[].backup[] |  select(.label == "${RECOVERYTARGET}") | .info.size')
else
    DBSIZE=$(pgbackrest info --stanza=${FROM} --output=json | jq '.[].backup[].info.size'|tail -1)
fi

parent_dir=$(echo $TO | sed 's/\(.*\)\/[^\/]*/\1/')
DIRSIZE=$(df $parent_dir |tail -1 | awk '{print $4}')

if [[ $( echo "$DIRSIZE * 1000" | bc ) -le $DBSIZE && "$NORESTORE" != "yes" ]];
then
    error "Not enough disk space on $parent_dir to restore."
    exit 1
fi

# checkdb
if [[ -z $CHECKDB ]]; then CHECKDB="No"; fi

# Variables for function "pgbackrest_exec()"
if [[ -z $BACKUPHOST ]]; then BACKUPHOST="localhost"; fi
backup_conf=/tmp/pgbackrest_auto.conf
if [ ! -f $backup_conf ]; then touch $backup_conf; fi

# restore_type_msg
if [[ -z $DATNAME && $RECOVERYTYPE = time ]]; then
    restore_type_msg="Full PostgreSQL Restore with Point-in-Time"
elif [[ -z $DATNAME ]]; then
    restore_type_msg="Full PostgreSQL Restore"
elif [[ -n $DATNAME && $RECOVERYTYPE = time ]]; then
    restore_type_msg="Partial PostgreSQL Restore with Point-in-Time"
elif [[ -n $DATNAME ]]; then
    restore_type_msg="Partial PostgreSQL Restore"
fi


function sigterm_handler(){
    info "Recieved QUIT|TERM|INT signal"
    error "Clean up and exit"
}

trap sigterm_handler QUIT TERM INT

function check_errcode(){
    # ARG: "error message"
    [[ $? -ne 0 ]] && error "${1}"
}

function check_mistake_run(){
    if [[ -n "${TO}" ]]; then
        blinkmsg "Restoring to ${TO} Waiting 30 seconds. The directory will be overwritten. If mistake, press ^C"
        sleep 30s
    fi
}

function cycle_simple(){
    # ARG: command
    # Assign variable 'status' = "ok" or "er"
    status=
    cmd=$1
    attempt=1
    info "cycle_simple command: $cmd"
    while [[ $attempt -le $limit ]]; do
        info "attempt: ${attempt}/${limit}"
        $cmd
        if [[ "$status" = "ok" ]]; then
            # Ready to work
            break
        elif [[ "$status" = "er" ]]; then
            error "exit"
        fi
        ((attempt++))
	sleep 1s
    done

    [[ $attempt -ge $limit && $status != ok ]] && error "attempt limit exceeded"
}

function pg_stop_check(){
    # Use with function cycle_simple
    info "PostgreSQL check status"
    /usr/bin/pg_ctlcluster ${PGVER} "${pg_instance}" status &> /dev/null
    code=$?
    if [[ $code -eq 3 ]]; then
        info "PostgreSQL instance ${pg_instance} not running"
        status=ok
    elif [[ $code -eq 0 ]]; then
        info "Wait PostgreSQL instance ${pg_instance} stop: wait ${sleep}s"
        sleep ${sleep}s
    elif [[ $code -eq 4 ]]; then
        info "${TO} is not a database cluster directory. May be its clean."
        status=ok
    else
        errmsg "PostgreSQL check failed"
        status=er
    fi
}

function pg_stop(){
    /usr/bin/pg_ctlcluster ${PGVER} "${pg_instance}" status &> /dev/null
    code=$?
    if [[ $code -eq 0 ]]; then
        info "PostgreSQL stop"
        /usr/bin/pg_ctlcluster ${PGVER} "${pg_instance}" stop -m fast &> /dev/null
        if [[ $? -eq 0 ]]; then
            info "PostgreSQL instance ${pg_instance} stopped"
        else
            errmsg "PostgreSQL instance ${pg_instance} stop failed"
        fi
    fi
}

function pgisready(){
    info "pgisready port ${PGPORT}"
    pg_isready -p "${PGPORT}"
    if [[ $? -eq 0 ]]; then
        info "PostgreSQL instance ${pg_instance} started and accepting connections"
        status=ok
    else
        info "PostgreSQL instance ${pg_instance} no response"
        errmsg "PostgreSQL instance ${pg_instance} no response"
        sleep 3s
    fi
}
function pg_start(){
    info "PostgreSQL start"
    /usr/bin/pg_ctlcluster ${PGVER} "${pg_instance}" start &> /dev/null
    if [[ $? -ne 0 ]]; then
        error "PostgreSQL instance ${pg_instance} start failed"
    else
        pgisready 1> /dev/null
    fi
}

function pgbackrest_exec(){
    [[ -n "${BACKUPSET}" ]] && pgbackrest_opt="--set=${BACKUPSET}"
    [[ -n "${DATNAME}" ]] && for db in ${DATNAME}; do pgbackrest_opt+=" --db-include=${db}"; done
    if [[ "${RECOVERYTYPE}" = "default" || "${RECOVERYTYPE}" = "time" ]]; then
        [[ -n "${RECOVERYTYPE}" ]] && pgbackrest_opt+=" --type=${RECOVERYTYPE}"
        [[ -n "${RECOVERYTARGET}" ]] && pgbackrest_opt+=" --target=\"${RECOVERYTARGET}\""
        else
    pgbackrest_opt+=" --type=immediate"
    fi
    pgbackrest_opt+=" --target-action=promote"
    # -- repo1-path
    mkdir ${TO}_remapped_tablespaces
    # tablespace-map-all=${TO}/remapped_tablespaces
    if [[ -f /etc/pgbackrest.conf ]]; then grep -q "repo1-path" /etc/pgbackrest.conf && pgbackrest_opt+=" --$(bash -c "grep \"repo1-path=\" /etc/pgbackrest.conf")"; fi
    # --
        info "Restore from backup started. Type: $restore_type_msg"
        detail_rst_log="/var/log/pgbackrest/$FROM-restore.log"
        if [ -f "${detail_rst_log}" ]; then info "See detailed log in the file ${detail_rst_log}"; fi
    # execute pgbackrest
    echo "pgbackrest --config=${backup_conf} --repo1-host=${BACKUPHOST} --repo1-host-user=postgres --stanza=${FROM} --pg1-path=${TO} ${pgbackrest_opt} --delta restore --process-max=4 --log-level-console=error --log-level-file=detail --recovery-option=${recovery_opt} --tablespace-map-all=${TO}/remapped_tablespaces"
    bash -c "pgbackrest --config=${backup_conf} --repo1-host=${BACKUPHOST} --repo1-host-user=postgres --stanza=${FROM} --pg1-path=${TO} ${pgbackrest_opt} --delta restore --process-max=4 --log-level-console=error --log-level-file=detail --tablespace-map-all=${TO}_remapped_tablespaces"
        if [[ $? -eq 0 ]]; then
            info "Restore from backup done"
        else
            error "Restore from backup failed"
        fi
}

function pg_info_replay(){
    if [[ "${RECOVERYTYPE}" = "time" ]]; then
        info "RECOVERYTYPE time"
        result=$(psql -p ${PGPORT} -tAc "SELECT pg_last_xact_replay_timestamp(), '${RECOVERYTARGET}' - pg_last_xact_replay_timestamp()")
    else
        result=$(psql -p ${PGPORT} -tAc "SELECT pg_last_xact_replay_timestamp()")
    fi
    info "PGPORT: $PGPORT result: $result"
    while IFS='|' read -r replay_timestamp left_timestamp; do
        if [[ -n "${left_timestamp}" ]]; then
            info "Replayed: ${replay_timestamp} Left: ${left_timestamp}"
        else
            info "Replayed: ${replay_timestamp}"
        fi
    done <<< "${result}"
}

function pg_check_recovery(){
    state=$(psql -p "${PGPORT}" -tAc 'SELECT pg_is_in_recovery()') 2>/dev/null
    pg_info_replay
    # Is the restore complete? YES
    if [ "$state" = "f" ]; then
        recovery=ok
    # Is the restore complete? No
    elif [ "$state" = "t" ]; then
        sleep 10
    else
    # Is everything all right? check connection with PostgreSQL
        pgisready 1> /dev/null; check_errcode "exit"
    fi
}

function pg_data_validation(){
    info "pg_data_validation on port ${PGPORT}"
    databases=$(bash -c "psql -p ${PGPORT} -tAc \"select datname from pg_database where not datistemplate\"")
        for db in $databases; do
            info "Start data validation for database $db"
            if pgisready 1> /dev/null; then
                info "starting pg_dump"
                pg_dump -d ${db} --cluster=${PGVER}/${FROM}_restore >> /dev/null
                if [[ $? -ne 0 ]]; then
                    errmsg "Data validation in the database $db - Failed"
                else
                    info "Data validation in the database $db - Successful"
                    ok_dbArray+=("$db")
                fi
            else
                errmsg "PostgreSQL instance ${pg_instance} no response"
            fi
        done
}

# amcheck CREATE EXTENSION if not exists
function amcheck_exists(){
    if [ "$PGVER" -lt "90" ]; then
        extension='amcheck'
    else
        extension='amcheck_next'
    fi
    psql -v "ON_ERROR_STOP" -p "${PGPORT}" -U postgres -d "$db_name" -tAc "CREATE EXTENSION if not exists $extension" 1> /dev/null
    if [ $? -ne 0 ]
    then
        error "CREATE EXTENSION $extension failed"
    fi
}
# amcheck - verify the logical consistency of the structure of PostgreSQL B-Tree indexes
function pg_logical_validation(){
    info "starting pg_checksums validation"
    /usr/lib/postgresql/${PGVER}/bin/pg_checksums -c -D ${TO}
    if [[ $? -ne 0 ]]; then
        errmsg "pg_checksums validation failed"
    else
        info "pg_checksums validation ok"
    fi
    if [ "$AMCHECK" ]; then
        for db_name in "${ok_dbArray[@]}"; do
            if pgisready 1> /dev/null; then
                if amcheck_exists; then
                    info "Verify the logical consistency of the structure of indexes and heap relations in the database $db_name"
                    indexes=$(psql -p "${PGPORT}" -d "$db_name" -tXAc "SELECT quote_ident(n.nspname)||'.'||quote_ident(c.relname) FROM pg_index i JOIN pg_opclass op ON i.indclass[0] = op.oid JOIN pg_am am ON op.opcmethod = am.oid JOIN pg_class c ON i.indexrelid = c.oid JOIN pg_namespace n ON c.relnamespace = n.oid WHERE am.amname = 'btree' AND n.nspname NOT IN ('pg_catalog', 'pg_toast') AND c.relpersistence != 't' AND c.relkind = 'i' AND i.indisready AND i.indisvalid")
                    for index in $indexes; do
                       # info "Verify the logical consistency of the structure of index ${index}"
                        psql -v ON_ERROR_STOP=on -p "${PGPORT}" -d "$db_name" -tAc "SELECT bt_index_parent_check('${index}')" 1> /dev/null
                            if [[ $? -ne 0 ]]; then
                                errmsg "Logical validation for index ${index} ( database $db_name ) - Failed"
                            fi
                    done
                fi
            fi
        done
    fi
}


### MAIN ###
STEP=1
rm -f "${log}"
touch "${log}"
exec &> >(tee -a "${log}")
info "[STEP $((STEP++))]: Starting"

if [[ "$NORESTORE" = "yes" ]]; then
    PGPORT=$(pg_lsclusters |grep "${PGVER} *${FROM}_restore"| awk '{print $3}')
    export PGPORT
    info "skipping restore, using port $PGPORT Cluster ${PGVER}/${FROM}_restore "
else
    # check data dir
    if [[ -d "${TO}" ]]; then
        error "${TO} data directory already exists"
    fi

    pg_createcluster ${PGVER} ${FROM}_restore -D ${TO}

    if [ $? -ne 0 ]
    then
        error "pg_createcluster ${PGVER} ${FROM}_restore -D ${TO} failed"
        exit
    fi

    PGPORT=$(pg_lsclusters |grep "${PGVER} *${FROM}_restore"| awk '{print $3}')
    export PGPORT

    info "Starting. Restore Type: ${restore_type_msg} FROM Stanza: ${FROM} ---> TO Directory: ${TO}"
    info "Starting. Restore Settings: ${RECOVERYTYPE} ${RECOVERYTARGET} ${BACKUPSET} ${DATNAME}"
    info "Starting. Run settings: Backup host: ${BACKUPHOST}"
    info "Starting. Run settings: Log: ${log}"
    info "Starting. Run settings: Lock run: ${lock}"
    info "Starting. PostgreSQL instance: ${pg_instance}"
    info "Starting. PostgreSQL version: ${PGVER}"
    info "Starting. PostgreSQL PGPORT: ${PGPORT}"
    info "Starting. PostgreSQL Database Validation: ${CHECKDB}"
    if [[ "${CLEAR}" = "yes" ]]; then info "Starting. Clear Data Directory after restore: ${CLEAR}";fi
    check_mistake_run
    info "[STEP $((STEP++))]: Stopping PostgreSQL"
    pg_stop
    cycle_simple pg_stop_check
    info "[STEP $((STEP++))]: Restoring from backup"
    # Restore from backup
    pgbackrest_exec

    # determine and set max_locks_per_xact parameter in postgresql.conf
    max_locks_per_xact=$(/usr/lib/postgresql/${PGVER}/bin/pg_controldata ${TO} | grep max_locks_per_xact | awk '{print $3}')
    # max_locks_per_transaction = 1024        # min 10
    sed -i "s/^#max_locks_per_transaction.*/max_locks_per_transaction = ${max_locks_per_xact}        # min 10/" /etc/postgresql/${PGVER}/${FROM}_restore/postgresql.conf
    max_connections=$(/usr/lib/postgresql/${PGVER}/bin/pg_controldata ${TO} | grep max_connections | awk '{print $3}')
    sed -i "s/^max_connections.*/max_connections = ${max_connections}                   # (change requires restart)/" /etc/postgresql/${PGVER}/${FROM}_restore/postgresql.conf

    info "[STEP $((STEP++))]: PostgreSQL Starting for recovery"
    pg_start
fi

cycle_simple pgisready
info "[STEP $((STEP++))]: PostgreSQL Recovery Checking"
# Expect recovery result
while true; do
    info "Checking if restoring from archive is done"
    pg_check_recovery
    # TODO bei recovery_target immediate wird $recovery nicht ok.
    # recovery="ok"
    if [[ "${recovery}" = "ok" ]]; then
        info "Restoring from archive is done"
        info "Restore done"
        break
    elif [[ "${recovery}" = "er" ]]; then
        errmsg "[STEP [ER]: PostgreSQL Recovery Failed"
        errmsg "Restoring from archive failed"
        pg_stop; check_errcode "exit"
    else
        continue
    fi
done
if [[ "${CHECKDB}" = "yes" && "${recovery}" = "ok" ]]; then
info "[STEP $((STEP++))]: Validate for physical database corruption"
pg_data_validation
info "[STEP $((STEP++))]: Validate for logical database corruption"
# amcheck + pg_checksums
pg_logical_validation
fi
# [ optional ]
if [[ "${CLEAR}" = "yes" ]]; then
    info "[STEP $((STEP++))]: Stopping PostgreSQL and Clear Data Directory"

    pg_ctlcluster -m i ${PGVER} ${FROM}_restore stop

    if [ $? -ne 0 ]
    then
        errmsg "Cluster ${PGVER}/${FROM}_restore did not stop"
    fi
    cycle_simple pg_stop_check
    if [[ $code -eq 3 ]]; then
        pg_dropcluster ${PGVER} ${FROM}_restore
        rm -rf ${TO}_remapped_tablespaces
    fi
fi
if [[ "${REPORT}" = "yes" ]]; then
    info "[STEP $((STEP++))]: Send report to mail address"
    sendmail
    # remove html log
    # rm "${log}"
fi
info "Finish"

# remove log file
#if [ -f "${log}" ]; then
#    rm "${log}"
#fi

# remove lock file
if [ -f "${lock}" ]; then
    rm "${lock}"
fi

exit
