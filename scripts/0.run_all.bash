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
github_link="https://github.com/monanadmin/MONAN-Model.git"   # Switch to your fork when you need to make changes or develop the model.
monan_branch=2.0.0-rc
convertmpas_branch=1.2.0
EXP=GFS                    # Options: GFS or ERA
RES=655362                 # Options-Global: 40962=120km; 163842=60km; 655362=30Km; 1024002=24km; 2621442=15Km; 5898242=10Km
                           # Options-Regional: 655362.REG.AMS_CAR=30km; 5898242.REG.AMS_CAR=10km; 23592962.REG.AMS_CAR=5km
YYYYMMDDHHi=2026080100     # Check the available dates for the initial and boundary conditions (regional), especially for ERA5 data.
FCST=24

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
