#!/bin/bash

# Set environment variables exports:
echo ""
echo -e "\033[1;32m==>\033[0m Moduling environment for MONAN model...\n"
. setenv.bash

# Standart directories variables:---------------------------------------
export DIRHOMES=${DIR_SCRIPTS}/${DIR_SUITE}
export DIRHOMED=${DIR_DADOS}/${DIR_SUITE}
export SCRIPTS=${DIRHOMES}/scripts
export DATAIN=${DIRHOMED}/datain
export DATAOUT=${DIRHOMED}/dataout
export SOURCES=${DIRHOMES}/sources
export EXECS=${DIRHOMED}/execs

mkdir -p \
    "${DIRHOMES}" \
    "${DIRHOMED}" \
    "${SCRIPTS}" \
    "${DATAIN}" \
    "${DATAOUT}" \
    "${SOURCES}" \
    "${EXECS}"
#----------------------------------------------------------------------

# Import setup variables:-----------------------------------------------------
LOCAL_RUN_CONFIG="${SCRIPTS}/run_config.local.bash"

if [ ! -f "${LOCAL_RUN_CONFIG}" ]; then
    echo "ERROR: Run configuration file not found:"
    echo "  ${LOCAL_RUN_CONFIG}"
    echo ""
    echo "Create it from the template:"
    echo "  cp ${SCRIPTS}/run_config.local.bash.TEMPLATE ${LOCAL_RUN_CONFIG}"
    exit 1
fi

. "${LOCAL_RUN_CONFIG}"
#----------------------------------------------------------------------

STEP=${1:-ALL}
STEP=${STEP^^}

# Validate workflow option:---------------------------------------------
case "${STEP}" in
    COMPILE|PRE|RUN|POST|ALL)
        ;;
    *)
        echo "Unknown workflow step: ${STEP}" >&2
        echo "Usage: $0 {ALL|COMPILE|PRE|RUN|POST}" >&2
        exit 1
        ;;
esac

# Configure MODEL resources only when this workflow will run the model.
# System defaults and run_config.local.bash have already been loaded.
if [[ "${STEP}" == "RUN" || "${STEP}" == "ALL" ]]; then
    MODEL_RESOURCE_HELPER="${SCRIPTS}/stools/configure_model_resources.bash"

    if [[ ! -r "$MODEL_RESOURCE_HELPER" ]]; then
        echo "ERROR: Missing resource configuration helper:" >&2
        echo "  $MODEL_RESOURCE_HELPER" >&2
        exit 1
    fi

    source "$MODEL_RESOURCE_HELPER" || exit 1
    configure_model_resources || exit 1
fi
#----------------------------------------------------------------------

# Check and confirm run configuration:---------------------------------
if [[ "${STEP}" == "POST" || "${STEP}" == "ALL" ]]; then
    if ! declare -F how_many_nodes >/dev/null; then
        echo "ERROR: setenv.bash did not define how_many_nodes." >&2
        exit 1
    fi

    export -f how_many_nodes
fi

if [[ "${STEP}" != "COMPILE" ]]; then

    case "${VARTABLE}" in
        .OPER|.MICROPHYSICS)
            ;;
        *)
            echo "ERROR: Unsupported VARTABLE: ${VARTABLE}"
            exit 1
            ;;
    esac

    export VARTABLE

    case "${MODERUN:-}" in
       R)
          MODE_DESCRIPTION="REGIONAL"
          ;;
       G)
          MODE_DESCRIPTION="GLOBAL"
          ;;
       *)
          echo "ERROR: MODERUN must be R or G." >&2
          echo "Check MODERUN in setenv.bash or setenv.local.bash." >&2
          exit 1
          ;;
    esac

    if [[ ! "${YYYYMMDDHHi}" =~ ^[0-9]{10}$ ]]; then
        echo "ERROR: YYYYMMDDHHi must have format YYYYMMDDHH." >&2
        exit 1
    fi

    if [[ ! "${RUN_ID}" =~ ^${YYYYMMDDHHi}(_[A-Za-z0-9._-]+)?$ ]]; then
        echo "ERROR: RUN_ID must equal YYYYMMDDHHi or start with YYYYMMDDHHi_." >&2
        echo "       YYYYMMDDHHi=${YYYYMMDDHHi}" >&2
        echo "       RUN_ID=${RUN_ID}" >&2
        exit 1
    fi

    if ! [[ "${N_MODEL_LEV}" =~ ^[1-9][0-9]*$ ]]; then
        echo "ERROR: NUMBER_OF_LEVELS must be a positive integer." >&2
        exit 1
    fi

    # Validate integration/forecast duration
    if ! [[ "${FCST}" =~ ^[1-9][0-9]*$ ]]; then
        echo "ERROR: FCST must be a positive integer number of hours." >&2
        exit 1
    fi

    # PRE also needs the restart time when generating new LBCs.
    if [[ "${STEP}" == "PRE" ]]; then

        case "${INIT_MODE}" in
            COLD)
                ;;
            RESTART)
                if [[ ! "${YYYYMMDDHHi_restart}" =~ ^[0-9]{10}$ ]]; then
                    echo "ERROR: Invalid YYYYMMDDHHi_restart." >&2
                    exit 1
                fi

                if [[ "${YYYYMMDDHHi_restart}" < "${YYYYMMDDHHi}" ]]; then
                    echo "ERROR: Restart precedes original initialization." >&2
                    exit 1
                fi

                if [[ "${MODERUN}" != "R" ]]; then
                    echo "ERROR: Boundary-condition preprocessing requires MODERUN=R." >&2
                    exit 1
                fi
                ;;
            *)
                echo "ERROR: INIT_MODE must be COLD or RESTART." >&2
                exit 1
                ;;
        esac

    fi

    # RUN and POST need to know which integration segment is selected.
    if [[ "${STEP}" == "RUN" || "${STEP}" == "POST" || "${STEP}" == "ALL" ]]; then

        case "${INIT_MODE}" in
            COLD)
                MODEL_START_TIME="${YYYYMMDDHHi}"
                ;;

            RESTART)
                if [[ ! "${YYYYMMDDHHi_restart}" =~ ^[0-9]{10}$ ]]; then
                    echo "ERROR: Invalid YYYYMMDDHHi_restart." >&2
                    exit 1
                fi

                if [[ "${YYYYMMDDHHi_restart}" < "${YYYYMMDDHHi}" ]]; then
                    echo "ERROR: Restart precedes original initialization." >&2
                    exit 1
                fi

                if [[ "${STEP}" == "ALL" ]]; then
                    echo "ERROR: ALL is not supported for RESTART." >&2
                    echo "Use RUN or POST." >&2
                    exit 1
                fi

                MODEL_START_TIME="${YYYYMMDDHHi_restart}"
                ;;

            *)
                echo "ERROR: INIT_MODE must be COLD or RESTART." >&2
                exit 1
                ;;
        esac

        # POST only needs DIAG_INTERVAL.
        # RUN additionally needs HIST_INTERVAL and RESTART_INTERVAL.
        intervals=(DIAG_INTERVAL)

        if [[ "${STEP}" == "RUN" || "${STEP}" == "ALL" ]]; then
            intervals+=(HIST_INTERVAL RESTART_INTERVAL)
        fi

        for interval_name in "${intervals[@]}"; do

            interval_value="${!interval_name:-}"

            if [[ ! "${interval_value}" =~ ^[0-9]{2}:[0-5][0-9]:[0-5][0-9]$ ]]; then
                echo "ERROR: ${interval_name} must be HH:MM:SS." >&2
                exit 1
            fi

            IFS=: read -r ih im is <<< "${interval_value}"

            if (( 10#$ih*3600 + 10#$im*60 + 10#$is == 0 )); then
                echo "ERROR: ${interval_name} must be positive." >&2
                exit 1
            fi

        done

        # The current GrADS template uses whole-minute intervals.
        if [[ "${STEP}" == "POST" || "${STEP}" == "ALL" ]]; then
            IFS=: read -r dh dm ds <<< "${DIAG_INTERVAL}"

            if (( 10#$ds != 0 )); then
                echo "ERROR: POST requires DIAG_INTERVAL in whole minutes." >&2
                exit 1
            fi
        fi

    fi

    echo ""
    echo "============================================================"
    echo " Run configuration: ${STEP}"
    echo "============================================================"

    printf " Input dataset:            %s\n" "${EXP}"
    printf " Resolution/grid:          %s\n" "${RES}"
    printf " Number of levels:         %s\n" "${N_MODEL_LEV}"

    if [[ "${STEP}" == "RUN" || "${STEP}" == "POST" || "${STEP}" == "ALL" ]]; then

        printf " Initialization mode:      %s\n" "${INIT_MODE}"

        if [[ "${INIT_MODE}" == "RESTART" ]]; then
            printf " Original start:           %s\n" "${YYYYMMDDHHi}"
            printf " Restart time:             %s\n" "${YYYYMMDDHHi_restart}"
        else
            printf " Initialization:           %s\n" "${YYYYMMDDHHi}"
        fi

    elif [[ "${STEP}" == "PRE" && "${INIT_MODE}" == "RESTART" ]]; then

        printf " Initialization mode:      %s\n" "${INIT_MODE}"
        printf " Original start:           %s\n" "${YYYYMMDDHHi}"
        printf " Restart time:             %s\n" "${YYYYMMDDHHi_restart}"

    else
        printf " Initialization:           %s\n" "${YYYYMMDDHHi}"
    fi

    printf " Run ID:                   %s\n" "${RUN_ID}"

    if [[ "${STEP}" == "RUN" || "${STEP}" == "ALL" ]]; then

        printf " Integration time:         %s hours\n" "${FCST}"
        printf " Namelists version:        %s\n" "${VARTABLE}"
        printf " DIAG output interval:     %s\n" "${DIAG_INTERVAL}"
        printf " HIST output interval:     %s\n" "${HIST_INTERVAL}"
        printf " RESTART output interval:  %s\n" "${RESTART_INTERVAL}"

    elif [[ "${STEP}" == "POST" ]]; then

        printf " Segment duration:         %s hours\n" "${FCST}"
        printf " Namelists version:        %s\n" "${VARTABLE}"
        printf " DIAG output interval:     %s\n" "${DIAG_INTERVAL}"

    else
        printf " Forecast length:          %s hours\n" "${FCST}"
    fi

    printf " Run mode:                 %s (%s)\n" \
        "${MODERUN}" "${MODE_DESCRIPTION}"

    printf " Data directory:           %s\n" "${DATAOUT}/${RUN_ID}"

    echo "============================================================"
    echo ""

    read -r -p "Continue with this configuration? [y/N] " answer

    case "${answer}" in
        y|Y|yes|YES)
            ;;
        *)
            echo "Execution cancelled."
            exit 1
            ;;
    esac
fi
#----------------------------------------------------------------------


# ----------------------------------------------------------------------
# Select workflow step
#
# Usage:
#   ./0.run_all.bash COMPILE
#   ./0.run_all.bash PRE
#   ./0.run_all.bash RUN
#   ./0.run_all.bash POST
#   ./0.run_all.bash ALL
# ----------------------------------------------------------------------

case "${STEP}" in

    COMPILE)
        echo "Running STEP 1: install and compile MONAN"
        time ${SCRIPTS}/1.install_monan.bash \
            "${github_link}" "${monan_branch}" "${convertmpas_branch}"
        ;;

    PRE)
        echo "Running STEP 2: preprocessing"
        time "${SCRIPTS}/2.pre_processing.bash" \
            "${EXP}" "${RES}" "${N_MODEL_LEV}" "${YYYYMMDDHHi}" "${RUN_ID}" "${FCST}" \
            "${INIT_MODE}" "${YYYYMMDDHHi_restart}"
        ;;

    RUN)
        echo "Running STEP 3: model"
        time ${SCRIPTS}/3.run_model.bash \
            "${EXP}" "${RES}" "${N_MODEL_LEV}" "${YYYYMMDDHHi}" "${RUN_ID}" "${FCST}" \
            "${INIT_MODE}" "${YYYYMMDDHHi_restart}" \
            "${DIAG_INTERVAL}" "${HIST_INTERVAL}" "${RESTART_INTERVAL}"
        ;;

    POST)
        echo "Running STEP 4: post-processing"
        time ${SCRIPTS}/4.run_post.bash \
            "${EXP}" "${RES}" "${N_MODEL_LEV}" "${YYYYMMDDHHi}" "${RUN_ID}" "${FCST}" \
            "${INIT_MODE}" "${YYYYMMDDHHi_restart}" "${DIAG_INTERVAL}"
        ;;

    ALL)
        echo "Running complete workflow"

        time ${SCRIPTS}/1.install_monan.bash \
            "${github_link}" "${monan_branch}" "${convertmpas_branch}" || exit 1

        time "${SCRIPTS}/2.pre_processing.bash" \
            "${EXP}" "${RES}" "${N_MODEL_LEV}" "${YYYYMMDDHHi}" "${RUN_ID}" "${FCST}" \
            "${INIT_MODE}" "${YYYYMMDDHHi_restart}" || exit 1

        time ${SCRIPTS}/3.run_model.bash \
            "${EXP}" "${RES}" "${N_MODEL_LEV}" "${YYYYMMDDHHi}" "${RUN_ID}" "${FCST}" \
            "${INIT_MODE}" "${YYYYMMDDHHi_restart}" \
            "${DIAG_INTERVAL}" "${HIST_INTERVAL}" "${RESTART_INTERVAL}" || exit 1

        time ${SCRIPTS}/4.run_post.bash \
            "${EXP}" "${RES}" "${N_MODEL_LEV}" "${YYYYMMDDHHi}" "${RUN_ID}" "${FCST}" \
            "${INIT_MODE}" "${YYYYMMDDHHi_restart}" "${DIAG_INTERVAL}" || exit 1
        ;;

    *)
        echo "Unknown workflow step: ${STEP}"
        echo "Usage: $0 {ALL|COMPILE|PRE|RUN|POST}"
        exit 1
        ;;

esac
