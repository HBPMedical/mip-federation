#!/usr/bin/env bash
#                    Copyright (c) 2016-2017
#   Data Intensive Applications and Systems Labaratory (DIAS)
#            Ecole Polytechnique Federale de Lausanne
#
#                      All Rights Reserved.
#
# Permission to use, copy, modify and distribute this software and its
# documentation is hereby granted, provided that both the copyright notice
# and this permission notice appear in all copies of the software, derivative
# works or modified versions, and any portions thereof, and that both notices
# appear in supporting documentation.
#
# This code is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. THE AUTHORS AND ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE
# DISCLAIM ANY LIABILITY OF ANY KIND FOR ANY DAMAGES WHATSOEVER RESULTING FROM THE
# USE OF THIS SOFTWARE.

federation_nodes=""
federation_hosts=""
for h in $(docker node ls --format '{{ .Hostname }}')
do
	federation_nodes="${federation_nodes} $(docker node inspect --format '{{ .Spec.Labels.name }}' ${h})"
	federation_hosts="${federation_hosts} ${h}"
done

usage() {
	( # This is just in case the user wants to check the settings
		. ./settings.sh
	)

	cat <<EOT
usage: $0 [-h|--help] (all|nodename [nodename ...])
	-h, --help: show this message and exit
	all: Start the federation on all the nodes currently known
	nodename: one or more nodes on which to deploy the stack

You can use environment variables, or add them into settings.local.sh
to change the default values.

To see the full list, please refer to settings.default.sh

Please find below the list of known Federation nodes:
${federation_nodes}

Errors: This script will exit with the following error codes:
 1	No arguments provided
 2	Federation node is incorrect
EOT
}

start_node() {
	(
		FEDERATION_NODE=$1
		LDSM_HOST=$2
		EXAREME_ROLE=$3

		. ./settings.sh ${FEDERATION_NODE}

		# Export the settings to the docker-compose files
		export FEDERATION_NODE

		export LDSM_USERNAME LDSM_PASSWORD LDSM_HOST LDSM_PORT

		export CONSUL_IMAGE CONSUL_VERSION
		export EXAREME_IMAGE EXAREME_VERSION
		export EXAREME_ROLE EXAREME_KEYSTORE EXAREME_MODE EXAREME_WORKERS_WAIT
		export EXAREME_LDSM_ENDPOINT EXAREME_LDSM_RESULTS EXAREME_LDSM_DATAKEY

		# Finally deploy the stack
		docker stack deploy -c docker-compose-${EXAREME_ROLE}.yml ${FEDERATION_NODE}
	)
}

start_nodes() {
	# Make sure we start from empty lists
	nodes="$*"
	hosts=""
	managers=""
	workers=""

	for n in ${nodes}
	do
		for h in ${federation_hosts}
		do
			label=$(docker node inspect --format '{{ .Spec.Labels.name }}' ${h})
			if [ "x${label}" == "x${n}" ];
			then
				hosts="${hosts} ${h}"
				break 1
			fi
		done
	done

	# Sort the nodes based on their roles
	for h in ${hosts}
	do
		if [ "manager" == "$(docker node inspect --format '{{ .Spec.Role }}' ${h})" ];
		then 
			managers="${managers} ${h}"
		else
			workers="${workers} ${h}"
		fi
	done

	# Start all the manager nodes
	for h in ${managers}
	do
		label=$(docker node inspect --format '{{ .Spec.Labels.name }}' ${h})
		(
			# Retrieve LDSM_HOST if it has been set manually.
			SHOW_SETTINGS=false . ./settings.sh ${label}
			test -z "${LDSM_HOST}" && \
				LDSM_HOST=$(docker node inspect --format '{{ .Status.Addr }}' ${h})
			EXAREME_WORKERS_WAIT=$(echo "$workers" | wc -w)
			start_node ${label} ${LDSM_HOST} manager
		)
	done

	# Then start all the worker nodes
	for h in ${workers}
	do
		label=$(docker node inspect --format '{{ .Spec.Labels.name }}' ${h})
		(
			# Retrieve LDSM_HOST if it has been set manually.
			SHOW_SETTINGS=false . ./settings.sh ${label}
			test -z "${LDSM_HOST}" && \
				LDSM_HOST=$(docker node inspect --format '{{ .Status.Addr }}' ${h})

			start_node ${label} ${LDSM_HOST} worker
		)
	done
}

start_all_nodes() {
	start_nodes ${federation_nodes}
}

start_one_node() {
	for h in ${federation_hosts}
	do
		label=$(docker node inspect --format '{{ .Spec.Labels.name }}' ${h})
		if [ "x${label}" == "x${FEDERATION_NODE}" ];
		then
			# Retrieve LDSM_HOST, EXAREME_ROLE if they have been set manually.
			SHOW_SETTINGS=false . ./settings.sh ${label}
			test -z "${LDSM_HOST}" && \
				LDSM_HOST=$(docker node inspect --format '{{ .Status.Addr }}' ${h})

			test -z "${EXAREME_ROLE}" && \
				EXAREME_ROLE=$(docker node inspect --format '{{ .Spec.Role }}' ${h})

			start_node ${label} ${LDSM_HOST} ${EXAREME_ROLE}
			break
		fi
	done
}

if [ $# -lt 1 ];
then
	usage
	exit 1
fi

if [ $# -eq 1 ];
then
	case $1 in
		-h|--help)
			usage
			exit 0
		;;
	
		*)
			FEDERATION_NODE="$1"
		;;
	esac

	if [ -z "${FEDERATION_NODE}" ]; then
		echo "Invalid federation node name"
		usage
		exit 3
	fi

	case ${FEDERATION_NODE} in
		all)
			start_all_nodes
		;;

		*)
			start_one_node ${FEDERATION_NODE}
		;;
	esac
else
	start_nodes $*
fi

exit 0
