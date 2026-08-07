#!/bin/bash 


#if [ $# -ne 5 ]
#then
#   echo ""
#   echo "Instructions: execute the command below"
#   echo ""
#   echo "${0} GitHubUserRepo EXP_NAME RESOLUTION LABELI FCST"
#   echo ""
#   echo "GitHubUserRepo :: GitHub link for your personal fork, eg: https://github.com/MYUSER/MONAN-Model.git"
#   echo "EXP_NAME       :: Forcing: GFS"
#   echo "RESOLUTION     :: number of points in resolution model grid, e.g: 1024002  (24 km)"
#   echo "LABELI         :: Initial date YYYYMMDDHH, e.g.: 2024010100"
#   echo "FCST           :: Forecast hours, e.g.: 24 or 36, etc."
#   echo ""
#   echo "24 hour forcast example:"
#   echo "${0} https://github.com/MYUSER/MONAN-Model.git GFS 1024002 2024010100 24"
#   echo ""
#   exit
#fi

# Set environment variables exports:
echo ""
echo -e "\033[1;32m==>\033[0m Moduling environment for MONAN model...\n"
. setenv.bash


# Standart directories variables:---------------------------------------
DIRHOMES=${DIR_SCRIPTS}/scripts_CD-CT; mkdir -p ${DIRHOMES}  
DIRHOMED=${DIR_DADOS}/scripts_CD-CT;   mkdir -p ${DIRHOMED}  
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
#   ./0.run_all.bash install
#   ./0.run_all.bash pre
#   ./0.run_all.bash pre-sst
#   ./0.run_all.bash model
#   ./0.run_all.bash post
#   ./0.run_all.bash all
#   ./0.run_all.bash all-sst
# ----------------------------------------------------------------------

STEP=${1:-all}

case "${STEP}" in

    install)
        echo "Running STEP 1: install and compile MONAN"
        time ${SCRIPTS}/1.install_monan.bash \
            ${github_link} ${monan_branch} ${convertmpas_branch}
        ;;

    pre)
        echo "Running STEP 2: preprocessing"
        time ${SCRIPTS}/2.pre_processing.bash \
            ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}
        ;;

    pre-sst)
        echo "Running STEP 2.1: preprocessing with updated SST"
        time ${SCRIPTS}/2.pre_processing.bash \
            ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST} on
        ;;

    model)
        echo "Running STEP 3: model"
        time ${SCRIPTS}/3.run_model.bash \
            ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}
        ;;

    post)
        echo "Running STEP 4: post-processing"
        time ${SCRIPTS}/4.run_post.bash \
            ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}
        ;;

    all)
        echo "Running complete workflow without updated SST"

        time ${SCRIPTS}/1.install_monan.bash \
            ${github_link} ${monan_branch} ${convertmpas_branch}

        time ${SCRIPTS}/2.pre_processing.bash \
            ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}

        time ${SCRIPTS}/3.run_model.bash \
            ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}

        time ${SCRIPTS}/4.run_post.bash \
            ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}
        ;;

    all-sst)
        echo "Running complete workflow with updated SST"

        time ${SCRIPTS}/1.install_monan.bash \
            ${github_link} ${monan_branch} ${convertmpas_branch}

        time ${SCRIPTS}/2.pre_processing.bash \
            ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}

        time ${SCRIPTS}/2.pre_processing.bash \
            ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST} on

        time ${SCRIPTS}/3.run_model.bash \
            ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}

        time ${SCRIPTS}/4.run_post.bash \
            ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}
        ;;

    *)
        echo "Unknown step: ${STEP}"
        echo "Usage: $0 {install|pre|pre-sst|model|post|all|all-sst}"
        exit 1
        ;;

esac
