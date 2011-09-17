jobid="$1"	;shift
chanid="$1"	;shift
starttime="$1"	;shift

DBHostName=
DBUserName=
DBPassword=
DBName=

hostname="$(hostname)"

storagegroup=
dir=
file=

function myexec {
	MYSQL_PWD="${DBPassword}" mysql --host "${DBHostName}" --user "${DBUserName}" "${DBName}" --batch --skip-column-names --execute "$*"
}

function escape {
	echo "${*//\'/''}"
}

function job_log {
	myexec "UPDATE jobqueue SET comment='$(escape $*)' WHERE id='${jobid}'"
}

function console_log {
	echo "$*" >&2
}

function die {
	status=$1
	shift
	$log $*
	exit ${status}
}

log=console_log

function checkdb {
	which mysql >/dev/null || die 1 "Missing command : mysql"

	[ -r ${HOME}/.mythtv/mysql.txt ] || die 1 "Cannot read ${HOME}/.mythtv/mysql.txt"

	eval $(grep -E '^\s*DB(HostName|UserName|Password|Name|Type)\s*=' ${HOME}/.mythtv/mysql.txt | sed -r 's/^\s*(.*\S)\s*=\s*(.*\S)\s*$/\1="\2"/')

	[ -n "${DBHostName}" ] || die 1 "Missing config : DBHostName"
	[ -n "${DBUserName}" ] || die 1 "Missing config : DBUserName"
	[ -n "${DBPassword}" ] || die 1 "Missing config : DBPassword"
	[ -n "${DBName}" ] || die 1 "Missing config : DBName"

	myexec "SELECT 1" >/dev/null || die 1 "Database test failed"
}

function checkjob {
	if [ "${jobid}" != 0 ]
	then
		[ $(myexec "SELECT count(*) FROM jobqueue WHERE id='${jobid}' AND chanid='${chanid}' AND starttime='${starttime}' AND status=4") -eq 1 ] || die 2 "Job ${jobid} not found"
		log=job_log
	fi
}

function checkdir {
	[ -n "${dir}" ] || die 1 "Unspecified directory"
	[ -n "$(myexec "SELECT dirname FROM storagegroup WHERE dirname='${dir}' AND hostname='${hostname}'")" ] || die 2 "Specified path is not a storage directory"
	$log "Found storage directory ${dir} on ${hostname}"
}

function findfile {
	local found=
	while read storagegroup dir file
	do
		[ -n "${dir}" -a -n "${file}" ] || continue
		found=no
		[ -f "${dir}/${file}" -a -r "${dir}/${file}" ] || continue
		found=yes
		break
	done <<EOF
$(myexec "SELECT recorded.storagegroup,storagegroup.dirname,recorded.basename FROM recorded LEFT JOIN storagegroup ON recorded.storagegroup=storagegroup.groupname AND recorded.hostname=storagegroup.hostname WHERE chanid='${chanid}' AND starttime='${starttime}' AND recorded.hostname='${hostname}'")
EOF

	case "${found}" in
	no)
		die 2 "File not found in storage dirs"
		;;
	yes)
		$log "Found ${file} in dir ${dir} of storagegroup ${storagegroup}"
		;;
	*)
		die 2 "Record not found"
		;;
	esac
}

function filesize {
	stat -c %s "$1"
}
