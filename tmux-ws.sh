#!/usr/bin/env bash

set -o pipefail
set -o errexit
set -o nounset


EXIT_CODE_READ_NAME=10
EXIT_CODE_READ_PATH=11

function tmux_ws_select() {
	function find_config_files() {
		if ! [[ -d "${PROJECT_CFG_DIR}" ]]; then
			return 1
		fi
		if ! find -L "${PROJECT_CFG_DIR}/" -type f -print; then
			return 1
		fi
		return 0
	}

	function SETUP_ENVIRONMENT() {
		local config_files
		if ! readarray -t config_files < <(find_config_files); then
			return 1
		fi
		
		local config_file
		for config_file in "${config_files[@]}"; do
			if ! local project_name="$(yq ".name" -r "${config_file}")"; then
				return ${EXIT_CODE_READ_NAME:-1}
			fi
			if ! local project_path="$(yq ".path" -r "${config_file}")"; then
				return ${EXIT_CODE_READ_PATH:-1}
			fi
			PROJECTS+=("${project_name}")
			PROJECT_PATHS["${project_name}"]="${project_path}"
			PROJECT_CONFIG_FILES["${project_name}"]="${config_file}"
		done

		return 0
	}

	function debug_config_files_array() {
		local project_name
		for project_name in "${PROJECTS[@]}"; do
			printf 'Debugging project "%s"\n' "${project_name}"
			printf '\tPath: %s\n' "${PROJECT_PATHS["${project_name}"]}"
			printf 'add to fzf loop %s\n' "${project_name}" >/dev/stderr
			printf '\tConfig %s\n' "${PROJECT_CONFIG_FILES[${project_name}]}"
			printf '\n'
		done

		return 0
	}

	function preview_project() {

		if [[ ${#} -ne 1 ]]; then
			printf 'No project selected for preview'
			return 1
		fi

		local project_name="${1}" && shift
		local project_config_file="${PROJECT_CONFIG_FILES["${project_name}"]}"
		local project_path="${PROJECT_PATHS["${project_name}"]}"
		printf 'Name: %s\n' "${project_name}"
		printf 'Path: %s\n' "${project_path}"
		if [[ -d ${project_path}/.git ]]; then
			local git_branch="$(git -C "${project_path/.git/}" rev-parse --abbrev-ref HEAD)"
			printf 'Branch %s\n' "${git_branch}"
			git -C "${project_path/.git/}" remote -v
		fi

		return 0
	}
	function prompt_bool(){
		local prompt="${1:-"?"}"
		local result=''
		while ! echo "${result}" | rg -i '^(y(es)?|no?)$' 1> /dev/null 2> /dev/null

		do
			read -p "${prompt} " result
		done

		if echo "${result}" | rg -i '^y' 1> /dev/null 2> /dev/null

		then
			return 0
		fi
		return 1
	}

	function create_new_project(){
		project_dir="$(pwd | sd "$HOME" '$$HOME')"

		file_safe_name="$(printf '%s' "${project_name}"\
			| sd '\s' '-'\
			| sd '[$+()\[\]+%~#&\n\r]' '').yml"

		if test "${file_safe_name}" = ".yml"
		then
			printf 'No file name!\n' > /dev/stderr
			return 1
		elif test -f "${PROJECT_CFG_DIR}/${file_safe_name}"
		then
			printf '%s already exists!\n' "${file_safe_name}" > /dev/stderr
			return 1
		fi
		printf 'You entered: "%s"\n' "${project_name}"
		printf 'File name: %s\n' "${file_safe_name}"
		
		if ! prompt_bool 'Ok?'
		then
			printf 'Better luck next time!\n'
			return 0
		fi
		
		FULL_PATH="${PROJECT_CFG_DIR}/${file_safe_name}"
		touch "${FULL_PATH}"
		local set_name="$(printf '.name = "%s"' "${project_name}")"
		local set_dir="$(printf '.path = "%s"' "${project_dir}")"
		yq "${set_name}" -i "${FULL_PATH}"
		yq "${set_dir}" -i "${FULL_PATH}"
		return 0
	}
	function select_project() {
		local project_name
		local selected_project
		if ! selected_project="$(
			for project_name in "${PROJECTS[@]}"; do
				printf '%s\n' "${project_name}"
			done | sort | fzf --no-multi \
					--prompt='project> ' \
					--info=hidden \
					--margin=1 \
					--layout=reverse \
					--preview="$0 -p {}" \
					--border \
					--preview-window="right:70%:wrap" \
					--bind 'ctrl-p:toggle-preview'
					#--height=100 \
		)"; then
			return 1
		fi
		printf '%s' "${selected_project}"
		return 0

	}

	function ensure_session_exists() {
		if [[ ${#} -ne 1 ]] || [[ -z ${1} ]]; then
			return 1
		fi
		local project_name="${1}"
		local project_path="${PROJECT_PATHS["${project_name}"]}"
		local real_path="$(echo ${project_path} | envsubst)"

		if ! test -d "${real_path}"
		then
			printf 'Directory %s does not exist.' "${real_path}" > /dev/stderr
			return 1
		fi
		if ! tmux has-session -t="${project_name}" 2>/dev/null; then
			if ! tmux new-session -c "${real_path}" -s "${project_name}" -d; then
				return 1
			fi
		fi

		if ! tmux switch-client -t "${project_name}"; then
			return 1
		fi

		return 0
	}

	function show_usage() {
		printf '%s option\n' "${0}"
		printf '\n'
		printf 'If multiple options are provided, only the first will be used.\n'
		printf 'There are %d processes running\n' "${tmux_processes}"
		printf 'Exception for the undocumented -e flag which may be removed later\n'
		printf '\n'
		printf '  -p "Project Name"       Generate the preview pane for fzf\n'
		printf '  -s                      Select a project from a dropdown\n'
		printf '  -c					  Create a new workspace for the current directory\n'
		printf '  -h                      Print the help menu\n'
		return 0
	}

	local TMUX_WS_CFG_HOME="${XDG_CONFIG_HOME:-${XDG_HOME:-${HOME}}}/.config/tmux-ws"
	local PROJECT_CFG_DIR="${TMUX_WS_CFG_HOME}/project.d"
	local PROJECTS
	local PROJECT_PATHS
	local PROJECT_CONFIG_FILES
	declare -A PROJECT_PATHS
	declare -A PROJECT_CONFIG_FILES

	if [[ -L ${PROJECT_CFG_DIR} ]]; then
		PROJECT_CFG_DIR="$(readlink -f "${PROJECT_CFG_DIR}")"
	fi

	if ! SETUP_ENVIRONMENT; then
		return 1
	fi
	# If a subcommand is requested, run that
	local option
	while getopts "sp:hc" option; do
		case "${option}" in
		p)
			EXTRA_DEBUG_MODE=0
			if ! preview_project "${OPTARG}"; then
				return 1
			fi
			return 0
			;;
		s)
			if ! selected_project="$(select_project)"; then
				return 1
			fi
			if ! ensure_session_exists "${selected_project}"; then
				return 1
			fi
			return 0
			;;
		c)
			if ! create_new_project;
			then
				return 1
			fi
			return 0
			;;
		h)
			display-popupshow_usage
			return 0
			;;
		*)
			display show_usage
			return 1
			;;
		esac
	done

	show_usage
	printf '\nInput was: %s\n' "${@}"
	return 1
}

if ! tmux_ws_select "${@}"; then
	exit 1
fi

exit 0
