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

    echo ""
    echo "============================================================"
    echo " Run configuration"
    echo "============================================================"
    printf " Input dataset:        %s\n" "${EXP}"
    printf " Resolution/grid:      %s\n" "${RES}"
    printf " Initialization:       %s\n" "${YYYYMMDDHHi}"
    printf " Run ID:               %s\n" "${RUN_ID}"
    printf " Forecast length:      %s hours\n" "${FCST}"
    printf " Namelists version:    %s\n" "${VARTABLE}"
    printf " Run mode:             %s (%s)\n" \
        "${MODERUN}" "${MODE_DESCRIPTION}"
    printf " Data directory:       %s\n" "${DATAOUT}/${RUN_ID}"
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
        time ${SCRIPTS}/2.pre_processing.bash \
            "${EXP}" "${RES}" "${YYYYMMDDHHi}" "${RUN_ID}" "${FCST}"
        ;;

    RUN)
        echo "Running STEP 3: model"
        time ${SCRIPTS}/3.run_model.bash \
            "${EXP}" "${RES}" "${YYYYMMDDHHi}" "${RUN_ID}" "${FCST}"
        ;;

    POST)
        echo "Running STEP 4: post-processing"
        time ${SCRIPTS}/4.run_post.bash \
            "${EXP}" "${RES}" "${YYYYMMDDHHi}" "${RUN_ID}" "${FCST}"
        ;;

    ALL)
        echo "Running complete workflow"

        time ${SCRIPTS}/1.install_monan.bash \
            "${github_link}" "${monan_branch}" "${convertmpas_branch}"

        time ${SCRIPTS}/2.pre_processing.bash \
            "${EXP}" "${RES}" "${YYYYMMDDHHi}" "${RUN_ID}" "${FCST}"

        time ${SCRIPTS}/3.run_model.bash \
            "${EXP}" "${RES}" "${YYYYMMDDHHi}" "${RUN_ID}" "${FCST}"

        time ${SCRIPTS}/4.run_post.bash \
            "${EXP}" "${RES}" "${YYYYMMDDHHi}" "${RUN_ID}" "${FCST}"
        ;;

    *)
        echo "Unknown workflow step: ${STEP}"
        echo "Usage: $0 {ALL|COMPILE|PRE|RUN|POST}"
        exit 1
        ;;

esac
