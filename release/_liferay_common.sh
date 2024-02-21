#!/bin/bash

#
# Do NOT edit this file unless you are editing this file in the root directory
# of the the liferay-docker repository. Edit that file, and then fork it to the
# repository where it is used.
#

function lc_background_run {
	if [ -n "${LIFERAY_COMMON_DEBUG_ENABLED}" ]
	then
		lc_time_run "${@}"
	else
		lc_time_run "${@}" &

		local pid=${!}

		LIFERAY_COMMON_BACKGROUND_PIDS["${pid}"]="${*}"
	fi
}

function lc_cd {
	if [ -d "${1}" ]
	then
		cd "${1}" || exit "${LIFERAY_COMMON_EXIT_CODE_CD}"
	else
		lc_log ERROR "${1} directory does not exist."

		exit "${LIFERAY_COMMON_EXIT_CODE_CD}"
	fi
}

function lc_check_utils {
	local exit_code=${LIFERAY_COMMON_EXIT_CODE_OK}

	for util in "${@}"
	do
		if (! command -v "${util}" &>/dev/null)
		then
			lc_log ERROR "The utility ${util} is not installed."

			exit_code="${LIFERAY_COMMON_EXIT_CODE_BAD}"
		fi
	done

	return "${exit_code}"
}

function lc_clone_repository {
	local repository_name=${1}
	local repository_path=${2}

	if [ -z "${repository_path}" ]
	then
		repository_path="${repository_name}"
	fi

	if [ -e "${repository_path}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	if [ -e "/home/me/dev/projects/${repository_name}" ]
	then
		lc_log DEBUG "Copying Git repository from /home/me/dev/projects/${repository_name}."

		cp -a "/home/me/dev/projects/${repository_name}" "${repository_path}"
	elif [ -e "/opt/dev/projects/github/${repository_name}" ]
	then
		lc_log DEBUG "Copying Git repository from /opt/dev/projects/github/${repository_path}."

		cp -a "/opt/dev/projects/github/${repository_name}" "${repository_path}"
	else
		git clone "git@github.com:liferay/${repository_name}.git" "${repository_path}"
	fi

	lc_cd "${repository_path}"

	if (git remote get-url upstream &>/dev/null)
	then
		git remote set-url upstream "git@github.com:liferay/${repository_name}.git"
	else
		git remote add upstream "git@github.com:liferay/${repository_name}.git"
	fi

	git remote --verbose
}

function lc_curl {
	local url=${1}

	if (! curl "${url}" --fail --max-time "${LIFERAY_COMMON_DOWNLOAD_MAX_TIME}" --output - --retry 10 --retry-delay 5 --show-error --silent)
	then
		lc_log ERROR "Unable to curl ${url}."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

function lc_date {
	if [ -z ${1+x} ] || [ -z ${2+x} ]
	then
		if [ "$(uname)" == "Darwin" ]
		then
			/bin/date
		elif [ -e /bin/date ]
		then
			/bin/date --iso-8601=seconds
		else
			/usr/bin/date --iso-8601=seconds
		fi
	else
		if [ "$(uname)" == "Darwin" ]
		then
			/bin/date -jf "%a %b %e %H:%M:%S %Z %Y" "${1}" "${2}"
		elif [ -e /bin/date ]
		then
			/bin/date -d "${1}" "${2}"
		else
			/usr/bin/date -d "${1}" "${2}"
		fi
	fi
}

function lc_docker_compose {
	if [ -n "${LIFERAY_COMMON_DOCKER_COMPOSE}" ]
	then
		echo "${LIFERAY_COMMON_DOCKER_COMPOSE}"

		return
	fi

	local LIFERAY_COMMON_DOCKER_COMPOSE="docker compose"

	if (command -v docker-compose &>/dev/null)
	then
		LIFERAY_COMMON_DOCKER_COMPOSE="docker-compose"
	fi

	echo "${LIFERAY_COMMON_DOCKER_COMPOSE}"
}

function lc_download {

	#
	# Usage:
	#
	#    lc_download https://www.google.com/logo.png
	#
	# Result:
	#
	#    ${LIFERAY_COMMON_DOWNLOAD_CACHE_DIR}/www.google.com/logo.png
	#
	# Usage:
	#
	#    lc_download https://www.google.com/logo.png /tmp/hello.png
	#
	# Result:
	#
	#    ${LIFERAY_COMMON_DOWNLOAD_CACHE_DIR}/www.google.com/logo.png
	#    /tmp/hello.png
	#

	local file_url=${1}

	if [ -z "${file_url}" ]
	then
		lc_log ERROR "File URL is not set."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	local file_name=${2}

	if [ -z "${file_name}" ]
	then
		file_name=${file_url##*/}

		local skip_copy="true"
	fi

	if [ -e "${file_name}" ]
	then
		lc_log DEBUG "Skipping the download of ${file_url} because it already exists."

		echo "${file_name}"

		return
	fi

	local cache_file="${LIFERAY_COMMON_DOWNLOAD_CACHE_DIR}/${file_url##*://}"

	if [ -e "${cache_file}" ]
	then
		if [ -n "${LIFERAY_COMMON_DOWNLOAD_SKIP_CACHE}" ]
		then
			lc_log DEBUG "Deleting file from cache: ${cache_file}."

			rm -f "${cache_file}"
		else
			lc_log DEBUG "Skipping the download of ${file_url} because it already exists."

			if [ "${skip_copy}" = "true" ]
			then
				lc_log DEBUG "Skipping copy."

				echo "${cache_file}"
			else
				lc_log DEBUG "Copying from cache: ${cache_file}."

				cp "${cache_file}" "${file_name}"

				echo "${file_name}"
			fi

			return
		fi
	fi

	local cache_file_dir="$(dirname "${cache_file}")"

	mkdir -p "${cache_file_dir}"

	lc_log DEBUG "Downloading ${file_url}."

	local current_date=$(lc_date)

	local temp_suffix="temp_$(lc_date "${current_date}" "+%Y%m%d%H%M%S")"

	local http_code

	#
	# Define http_code in a separate line to capture the exit code.
	#

	http_code=$(curl "${file_url}" --fail --max-time "${LIFERAY_COMMON_DOWNLOAD_MAX_TIME}" --output "${cache_file}.${temp_suffix}" --show-error --silent --write-out "%{http_code}")

	if [ "${?}" -gt 0 ]
	then
		lc_log DEBUG "Unable to download ${file_url}. HTTP response code was ${http_code}."

		if [ "${http_code}" == "404" ]
		then
			return "${LIFERAY_COMMON_EXIT_CODE_MISSING_RESOURCE}"
		fi

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	mv "${cache_file}.${temp_suffix}" "${cache_file}"

	if [ "${skip_copy}" = "true" ]
	then
		echo "${cache_file}"
	else
		lc_log DEBUG "Copying from cache: ${cache_file}."

		cp "${cache_file}" "${file_name}"

		echo "${file_name}"
	fi
}

function lc_echo {
	local level=${1}

	shift

	if [ "${level}" == DEBUG ]
	then
		if [ "${LIFERAY_COMMON_LOG_LEVEL}" == "DEBUG" ]
		then
			echo -e "\e[2;96m[DEBUG] ${*}\e[0m"
		fi
	elif [ "${level}" == ERROR ]
	then
		echo -e "\e[1;31m[ERROR] ${*}\e[0m"
	elif [ "${level}" == WARN ]
	then
		echo -e "\e[1;33m[WARN] ${*}\e[0m"
	else
		echo -e "\e[2;94m${*}\e[0m"
	fi
}

function lc_echo_time {
	local seconds=${1}

	printf "%02dh:%02dm:%02ds" $((seconds / 3600)) $((seconds % 3600 / 60)) $((seconds % 60))
}

function lc_get_property {
	file=${1}
	property_key=${2}

	if [ "${file##*.}" == "bnd" ]
	then
		local property_value=$(grep -F "${property_key}: " "${file}")

		echo "${property_value##*: }"
	else
		local property_value=$(sed -r "s/\\\r?\n[ \t]*//g" -z < "${file}" | grep -F "${property_key}=")

		echo "${property_value##*=}"
	fi
}

function lc_log {
	local level=${1}
	local message=${2}

	if [ "${level}" != "DEBUG" ] || [ "${LIFERAY_COMMON_LOG_LEVEL}" == "DEBUG" ]
	then
		echo "$(lc_date) [${level}] ${message}"
	fi
}

function lc_next_step {
	local step=$(cat "${LIFERAY_COMMON_STEP_FILE}")

	step=$((step + 1))

	echo ${step} > "${LIFERAY_COMMON_STEP_FILE}"

	printf "%02d" ${step}
}

function lc_time_run {
	local run_id=$(echo "${@}" | tr " /:" "_")
	local start_time=$(date +%s)

	if [ -n "${LIFERAY_COMMON_LOG_DIR}" ]
	then
		mkdir -p "${LIFERAY_COMMON_LOG_DIR}"

		local log_file="${LIFERAY_COMMON_LOG_DIR}/log_${LIFERAY_COMMON_START_TIME}_step_$(lc_next_step)_${run_id}.txt"
	fi

	echo "$(lc_date) > ${*}"

	if [ -z "${LIFERAY_COMMON_DEBUG_ENABLED}" ] && [ -n "${LIFERAY_COMMON_LOG_DIR}" ]
	then
		"${@}" &> "${log_file}"
	else
		"${@}"
	fi

	local exit_code=${?}

	local end_time=$(date +%s)

	if [ "${exit_code}" == "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}" ]
	then
		echo -e "$(lc_date) < ${*}: \e[1;34mSkip\e[0m"

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	else
		local seconds=$((end_time - start_time))

		if [ "${exit_code}" -gt 0 ]
		then
			echo -e "$(lc_date) ! ${*} exited with \e[1;31merror\e[0m in $(lc_echo_time ${seconds}) (exit code: ${exit_code})."

			if [ -z "${LIFERAY_COMMON_DEBUG_ENABLED}" ] && [ -n "${LIFERAY_COMMON_LOG_DIR}" ]
			then
				echo "Full log file is at ${log_file}. Printing the last 100 lines:"

				tail -n 100 "${log_file}"
			fi

			if (declare -F lc_time_run_error &>/dev/null)
			then
				LC_TIME_RUN_ERROR_EXIT_CODE="${exit_code}"
				LC_TIME_RUN_ERROR_FUNCTION="${*}"
				LC_TIME_RUN_ERROR_LOG_FILE="${log_file}"

				lc_time_run_error
			fi

			exit ${exit_code}
		else
			echo -e "$(lc_date) < ${*}: \e[1;32mSuccess\e[0m in $(lc_echo_time ${seconds})"
		fi
	fi
}

function lc_wait {
	for pid in "${!LIFERAY_COMMON_BACKGROUND_PIDS[@]}"
	do
		wait "${pid}"

		local exit_code=$?

		if [ "${exit_code}" -ne "${LIFERAY_COMMON_EXIT_CODE_OK}" ] && [ "${exit_code}" -ne "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}" ]
		then
			lc_log ERROR "Background job exit code was ${exit_code}. Exiting."

			exit "${exit_code}"
		fi
	done

	LIFERAY_COMMON_BACKGROUND_PIDS=()
}

function _lc_init {
	LIFERAY_COMMON_START_TIME=$(date +%s)
	LIFERAY_COMMON_STEP_FILE=$(mktemp)

	trap 'rm -f "${LIFERAY_COMMON_STEP_FILE}"' EXIT ERR SIGINT SIGTERM

	declare -A LIFERAY_COMMON_BACKGROUND_PIDS

	if [ -z "${LIFERAY_COMMON_DOWNLOAD_CACHE_DIR}" ]
	then
		LIFERAY_COMMON_DOWNLOAD_CACHE_DIR=${HOME}/.liferay-common-cache
	fi

	LIFERAY_COMMON_DOWNLOAD_MAX_TIME=1200
	LIFERAY_COMMON_EXIT_CODE_BAD=1
	LIFERAY_COMMON_EXIT_CODE_CD=3
	LIFERAY_COMMON_EXIT_CODE_HELP=2
	LIFERAY_COMMON_EXIT_CODE_MISSING_RESOURCE=5
	LIFERAY_COMMON_EXIT_CODE_OK=0
	LIFERAY_COMMON_EXIT_CODE_SKIPPED=4

	if (locale -a | grep -q en_US.utf8)
	then
		export LC_ALL=en_US.utf8
	else
		export LC_ALL=C.utf8
	fi

	export TZ=UTC
}

_lc_init