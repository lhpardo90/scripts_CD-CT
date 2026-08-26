#!/bin/bash

# Set environment variables exports:
echo ""
echo -e "\033[1;32m==>\033[0m Moduling environment for MONAN model...\n"
. setenv.bash

# Standart directories variables:---------------------------------------
DIRHOMES=${DIR_SCRIPTS}/${DIR_SUITE}; mkdir -p ${DIRHOMES}
DIRHOMED=${DIR_DADOS}/${DIR_SUITE};   mkdir -p ${DIRHOMED}
SCRIPTS=${DIRHOMES}/scripts;           mkdir -p ${SCRIPTS}
DATAIN=${DIRHOMED}/datain;             mkdir -p ${DATAIN}
DATAOUT=${DIRHOMED}/dataout;           mkdir -p ${DATAOUT}
SOURCES=${DIRHOMES}/sources;           mkdir -p ${SOURCES}
EXECS=${DIRHOMED}/execs;               mkdir -p ${EXECS}
#----------------------------------------------------------------------

# Input variables:-----------------------------------------------------

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

STEP=${1:-ALL}
STEP=${STEP^^}

case "${STEP}" in

    COMPILE)
        echo "Running STEP 1: install and compile MONAN"
        time ${SCRIPTS}/1.install_monan.bash \
            ${github_link} ${monan_branch} ${convertmpas_branch}
        ;;

    PRE)
        echo "Running STEP 2: preprocessing"
        time ${SCRIPTS}/2.pre_processing.bash \
            ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}
        ;;

    RUN)
        echo "Running STEP 3: model"
        time ${SCRIPTS}/3.run_model.bash \
            ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}
        ;;

    POST)
        echo "Running STEP 4: post-processing"
        time ${SCRIPTS}/4.run_post.bash \
            ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}
        ;;

    ALL)
        echo "Running complete workflow"

        time ${SCRIPTS}/1.install_monan.bash \
            ${github_link} ${monan_branch} ${convertmpas_branch}

        time ${SCRIPTS}/2.pre_processing.bash \
            ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}

        time ${SCRIPTS}/3.run_model.bash \
            ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}

        time ${SCRIPTS}/4.run_post.bash \
            ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}
        ;;

    *)
        echo "Unknown workflow step: ${STEP}"
        echo "Usage: $0 {ALL|COMPILE|PRE|RUN|POST}"
        exit 1
        ;;

esac
