#!/bin/bash
#
# db.sh - The tool to manage your libpurple-omemo-plugin db's
#   One of the tools with loads of sql injection possibilities :-)
#
# Steffen Jaeckel, 2017

MY_NAME=$0
PRPL=$HOME/.purple
ACCS=$PRPL/accounts.xml
OMEMO=$PRPL/omemo

NUM=$(xmllint --xpath 'count(//account/account)' $ACCS)

NAMES=
OMEMO_DBS=
for n in $(seq 1 1 $NUM)
do
	n1=$(($n-1))
	NAMES[$n1]=$(xmllint --xpath "string(account/account[$n]/name)" $ACCS)
	OMEMO_DBS[$n1]=$(xmllint --xpath 'string(account/account[name="'${NAMES[$n1]}'"]/settings/setting[@name="'omemo-db-id'"])' $ACCS)
done

# Helpers

function find_function()
{
	typeset -F | grep $1 | sed -e "s/declare -f //g"
}

function find_functions()
{
	typeset -F | grep $1 | sed -e "s/declare -f $1_//g"
}

ERROUT=2
function errcho()
{
	echo $@ >&${ERROUT}
}

function run()
{
	if [ "$#" != "1" ]; then
		errcho "No parameter given"
		exit 1
	fi
	f=$1
	if [ "$(find_function ${f})" != "${f}" ]; then
		errcho "Unknown function \"$1\""
		exit 1
	else
		$f
	fi
}

function die()
{
	f=db_help_$1
	$f
	exit 1
}

function sql()
{
	sqlite3 -separator ", " "$@"
}


# Accounts listing

function db_summary_accounts() { errcho "List all accounts"; }

function db_help_accounts()
{
	errcho "This lists all account names and the number they can be accessed by."
	errcho "All further commands that require an account ID [aID] expect the accounts' number."
	errcho "An example output is:"
	errcho "0: account@jabber.server"
}

function db_exec_accounts()
{
	for i in ${!NAMES[@]}; do
		echo "$i: ${NAMES[$i]}"
	done
}

# Contacts listing

function db_summary_contacts() { errcho "List all contacts"; }

function db_help_contacts()
{
	errcho "Usage: $MY_NAME contacts <aID>"
	errcho "This lists all contact names and the number they can be accessed by."
	errcho "All further commands that require a contact ID [cID] expect the contacts' number."
	errcho "An example output is:"
	errcho "0: contact@jabber.server"
}

function db_exec_contacts()
{
	[[ $# -lt 1 || $1 -ge $NUM ]] && die contacts
	sql $OMEMO/${OMEMO_DBS[$1]}.sqlite 'select id,jid from contacts order by id' | sed 's/, /: /'
}

# Enable encryption

function db_summary_encrypt() { errcho "Enable encryption"; }

function db_help_encrypt()
{
	errcho "Usage: $MY_NAME encrypt <aID> <cID|all=default> [0|1=default]"
}

function db_exec_encrypt()
{
	[[ $# -lt 1 || $1 -ge $NUM ]] && die encrypt

	where=
	which="all"
	[[ $# -ge 2 ]] && which=$2
	if [ "$which" != "all" ]; then
		where="where id=$2"
		which=$(sql $OMEMO/${OMEMO_DBS[$1]}.sqlite "select jid from contacts where id = $2")
	fi
	[[ "$which" == "all" ]] && die encrypt

	crypt=1
	[[ $# -ge 3 ]] && crypt=$3
	[[ $crypt != 0 && $crypt != 1 ]] && die encrypt
	read -p "Are you sure you want to set the encryption of $which to $crypt? [Y/n] " okay
	okay="${okay:-y}"
	okay="${okay,,}"

	[ "$okay" == "y" ] && sql $OMEMO/${OMEMO_DBS[$1]}.sqlite "update contacts set encryption = $crypt $where"
}

# Trust a contact

function db_summary_trust() { errcho "Trust a contact"; }

function db_help_trust()
{
	errcho "Usage: $MY_NAME trust <aID> <cID>"
}

function db_exec_trust()
{
	[[ $# -lt 3 || $1 -ge $NUM ]] && die trust
	jid=$(sql $OMEMO/${OMEMO_DBS[$1]}.sqlite "select jid from contacts where id = $2")
	read -p "Are you sure you want to set the trust-level of $jid to $3? [Y/n] " okay
	okay="${okay:-y}"
	okay="${okay,,}"

	[ "$okay" == "y" ] && sql $OMEMO/${OMEMO_DBS[$1]}.sqlite "update devices set trust = $3 where contact_id = $2"
}


# sqlite3 cmd

function db_summary_cmd() { errcho "Execute a sqlite3 cmd"; }

function db_help_cmd()
{
	errcho "Usage: $MY_NAME cmd <aID>|<path to sqlite db> <commands to pass to db>"
}

function db_exec_cmd()
{
	[ $# -lt 2 ] && die cmd
	if [[ $1 -ge 0 && $1 -lt $NUM ]]; then
		db=$OMEMO/${OMEMO_DBS[$1]}.sqlite
	else
		db=$1
	fi
	shift

	sql $db "$@"
}



# Help

function db_summary_help() { errcho "Get help; use 'help <command>' to get help for <command>"; }

function db_help_help()
{
	errcho "Usage for this is as following: $0 help <command you want help for>"
}

function db_exec_help()
{
	[ $# -lt 1 ] && die help
	f=db_help_$1
	if [ "$(find_function ${f})" != "${f}" ]; then
		errcho "Unknown function \"$1\""
		exit 1
	else
		ERROUT=1
		$f
	fi
}


# find the part to execute ...

f=db_exec_$1

if [ "$(find_function ${f})" != "${f}" ]; then
	errcho "Unknown parameter \"$1\""
	funcs=($(find_functions db_exec))
	errcho "Available commands:"
	for i in "${funcs[@]}"; do
		f=db_summary_$i
		[ ${#i} -lt 8 ] && { printf "%s\t\t- " $i; } || { printf "%s\t- " $i; }
		$f
	done
	exit 1
fi

# ... and go
shift
$f "$@"
