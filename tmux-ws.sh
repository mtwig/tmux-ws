#!/usr/bin/env bash

#
# Command to run on repeat during testing
#  fdfind . | entr -cp tmux-ws.sh
#

function tmux_ws_select() {
	function find_config_files() {
		if ! find "${PROJECT_CFG_DIR}" -type f -print; then
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
			if ! local project_name="$(jq .projectName -r "${config_file}")"; then
				return 1
			fi
			if ! local project_path="$(jq .projectPath -r "${config_file}")"; then
				return 1
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
		local project_path_to_print="$(echo $project_path | rg -o '([^/]+/){0,2}/?$')"
		printf '%s\n' "${project_name}"
		printf '%s\n' "${project_path_to_print}"
		if [[ -d ${project_path}/.git ]]; then
			local git_branch="$(git -C "${project_path/.git/}" rev-parse --abbrev-ref HEAD)"
			printf 'Branch %s\n' "${git_branch}"
			git -C "${project_path/.git/}" remote -v
		fi

		return 0
	}

	function select_project() {
		local project_name
		local selected_project
		if ! selected_project="$(
			for project_name in "${PROJECTS[@]}"; do
				printf '%s\n' "${project_name}"
			done |
				sort |
				fzf --no-multi \
					--prompt='project> ' \
					--info=hidden \
					--margin=1 \
					--layout=reverse \
					--border \
					--preview="$0 -p {}" \
					--preview-window="right:70%:wrap:hidden" \
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

		#printf 'the project name is %s, btw\n' "${project_name}"
		#2>/dev/stderr
		if ! tmux has-session -t="${project_name}" 2>/dev/null; then
			if ! tmux new-session -c "${project_path}" -s "${project_name}" -d; then
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

	if ! SETUP_ENVIRONMENT; then
		return 1
	fi
	# If a subcommand is requested, run that
	local option
	while getopts "sp:h" option; do
		case "${option}" in
		p)
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
