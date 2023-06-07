#!/bin/bash

#
# Do NOT edit this file unless you are editing this file in the root directory
# of the the liferay-docker repository. Edit that file, and then fork it to the
# repository where it is used.
#

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

function lc_download {
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
	fi

	if [ -e "${file_name}" ]
	then
		lc_log DEBUG "Skipping the download of ${file_url} because it already exists."

		return
	fi

	local cache_file="${LIFERAY_COMMON_DOWNLOAD_CACHE_DIR}/${file_url##*://}"

	if [ -e "${cache_file}" ]
	then
		lc_log DEBUG "Copying file from cache: ${cache_file}."

		cp "${cache_file}" "${file_name}"

		return
	fi

	mkdir -p $(dirname "${cache_file}")

	lc_log DEBUG "Downloading ${file_url}."

	local current_date=$(lc_date)

	local timestamp=$(lc_date "${current_date}" "+%Y%m%d%H%M%S")

	if (! curl "${file_url}" --fail --output "${cache_file}.temp${timestamp}" --silent)
	then
		lc_log ERROR "Unable to download ${file_url}."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	else
		mv "${cache_file}.temp${timestamp}" "${cache_file}"

		cp "${cache_file}" "${file_name}"
	fi
}

function lc_echo_time {
	local seconds=${1}

	printf '%02dh:%02dm:%02ds' $((seconds/3600)) $((seconds%3600/60)) $((seconds%60))
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
	if [ -z "${LIFERAY_COMMON_STEP_FILE}" ]
	then
		LIFERAY_COMMON_STEP_FILE=$(mktemp)
	fi

	local step=$(cat "${LIFERAY_COMMON_STEP_FILE}")

	step=$((step + 1))

	echo ${step} > "${LIFERAY_COMMON_STEP_FILE}"

	printf '%02d' ${step}
}

function lc_time_run {
	local run_id=$(echo "${@}" | tr " " "_")
	local start_time=$(date +%s)

	if [ -n "${LIFERAY_COMMON_LOG_DIR}" ]
	then
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

	if [ "${exit_code}" == "${SKIPPED}" ]
	then
		echo -e "$(lc_date) < ${*} - \e[1;34mskip\e[0m"
	else
		local seconds=$((end_time - start_time))

		if [ "${exit_code}" -gt 0 ]
		then
			echo -e "$(lc_date) ! ${*} exited with \e[1;31merror\e[0m in $(lc_echo_time ${seconds}) (exit code: ${exit_code})."

			if [ -z "${LIFERAY_COMMON_DEBUG_ENABLED}" ] && [ -n "${LIFERAY_COMMON_LOG_DIR}" ]
			then
				echo "Full log file: ${log_file}. Printing the last 100 lines:"

				tail -n 100 "${log_file}"
			fi

			exit ${exit_code}
		else
			echo -e "$(lc_date) < ${*} - \e[1;32msuccess\e[0m in $(lc_echo_time ${seconds})"
		fi
	fi
}

function _lc_init {
	LIFERAY_COMMON_START_TIME=$(date +%s)

	if [ -z "${LIFERAY_COMMON_DOWNLOAD_CACHE_DIR}" ]
	then
		LIFERAY_COMMON_DOWNLOAD_CACHE_DIR=${HOME}/.liferay-common-cache
	fi

	LIFERAY_COMMON_EXIT_CODE_BAD=1
	LIFERAY_COMMON_EXIT_CODE_CD=3
	LIFERAY_COMMON_EXIT_CODE_HELP=2
	LIFERAY_COMMON_EXIT_CODE_OK=0
	LIFERAY_COMMON_EXIT_CODE_SKIPPED=4
	
	export LC_ALL=en_US.UTF-8
	export TZ=UTC
}

_lc_init