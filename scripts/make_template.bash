#!/bin/bash 
umask 022

set -Eeuo pipefail

#-----------------------------------------------------------------------------#
# !SCRIPT: run_post
#
# !DESCRIPTION:
#     Script to run the pos-processing of MONAN model over the forecast horizon.
#     
#     Performs the following tasks:
# 
#        o Check all input files before
#        o Creates the submission script
#        o Submit the post
#        o Verify all files generated
#        
#
#-----------------------------------------------------------------------------#

if [ $# -ne 9 ]
then
   echo ""
   echo "Instructions: execute the command below"
   echo ""
   echo "${0} EXP RESOLUTION NUMBER_OF_LEVELS LABELI RUN_ID FCST INIT_MODE RESTART_TIME DIAG_INTERVAL"
   echo ""
   echo "EXP         :: Initial or lateral boundary condition dataset (GFS or ERA)"
   echo "RESOLUTION  :: Number of horizontal grid cells (global) or regional mesh identifier (e.g., 1024002 for the ~24 km mesh)"
   echo "NUMBER_OF_LEVELS :: Number of vertical levels (e.g., 55)"
   echo "LABELI      :: Forecast initialization date and time (YYYYMMDDHH), e.g., 2026080100"
   echo "RUN_ID      :: Output directory name (must start with YYYYMMDDHH)"
   echo "FCST        :: Forecast length in hours (e.g., 24, 36, 48, etc.)"
   echo ""
   echo "Example for a 24-hour forecast:"
   echo "${0} GFS 1024002 55 2026080100 2026080100_CTRL 24 COLD '' 01:00:00"
   echo ""
   exit 1
fi

# Set environment variables exports:
echo ""
echo -e "\033[1;32m==>\033[0m Moduling environment for MONAN model...\n"
. setenv.bash

echo ""
echo "---- Make Template ----"
echo ""


# Standart directories variables:---------------------------------------
DIRHOMES=$(dirname "$(pwd)");          mkdir -p ${DIRHOMES}  
DIRHOMED=${DIR_DADOS}/${DIR_SUITE};   mkdir -p ${DIRHOMED}
export SCRIPTS=${DIRHOMES}/scripts;    mkdir -p ${SCRIPTS}
DATAIN=${DIRHOMED}/datain;             mkdir -p ${DATAIN}
DATAOUT=${DIRHOMED}/dataout;           mkdir -p ${DATAOUT}
SOURCES=${DIRHOMES}/sources;           mkdir -p ${SOURCES}
EXECS=${DIRHOMED}/execs;               mkdir -p ${EXECS}
#----------------------------------------------------------------------


# Input variables:--------------------------------------
EXP=${1};         #EXP=GFS
RES=${2};         #RES=1024002
N_MODEL_LEV=${3}; #N_MODEL_LEV=55
YYYYMMDDHHi=${4}; #YYYYMMDDHHi=2024012000
RUN_ID=${5};      #RUN_ID=2024012000_CTRL
FCST=${6};        #FCST=24
INIT_MODE=${7}
YYYYMMDDHHi_restart=${8}
DIAG_INTERVAL=${9}
#-------------------------------------------------------

# Determine the selected segment
if [[ "${INIT_MODE}" == "RESTART" ]]; then
    MODEL_START_TIME="${YYYYMMDDHHi_restart}"
else
    MODEL_START_TIME="${YYYYMMDDHHi}"
fi

# Diagnostic interval
IFS=: read -r dh dm ds <<< "${DIAG_INTERVAL}"

DIAG_INTERVAL_SEC=$((10#$dh*3600 + 10#$dm*60 + 10#$ds))

if (( DIAG_INTERVAL_SEC <= 0 || DIAG_INTERVAL_SEC % 60 != 0 )); then
    echo "ERROR: GrADS templates require a positive whole-minute interval." >&2
    exit 1
fi

TDEF_MIN=$((DIAG_INTERVAL_SEC / 60))

# Simulation segment time range
START_EPOCH=$(
    date -u -d \
    "${MODEL_START_TIME:0:4}-${MODEL_START_TIME:4:2}-${MODEL_START_TIME:6:2} ${MODEL_START_TIME:8:2}:00:00" \
    +%s
)

FORECAST_SEC=$((FCST * 3600))

if [[ "${INIT_MODE}" == "RESTART" ]]; then
    FIRST_OFFSET=${DIAG_INTERVAL_SEC}
else
    FIRST_OFFSET=0
fi

if (( FIRST_OFFSET > FORECAST_SEC )); then
    echo "ERROR: No diagnostic outputs expected within this segment." >&2
    exit 1
fi

nfiles=$(( (FORECAST_SEC - FIRST_OFFSET) / DIAG_INTERVAL_SEC + 1 ))

if (( nfiles < 1 )); then
    echo "ERROR: No GrADS times available for this segment." >&2
    exit 1
fi

FIRST_POST_VALID=$(
    date -u -d "@$((START_EPOCH + FIRST_OFFSET))" \
        +'%Y%m%d%H.%M.%S'
)

mkdir -p ${DATAOUT}/${RUN_ID}/Post/logs


# Local variables--------------------------------------
START_DATE_YYYYMMDD="${YYYYMMDDHHi:0:4}-${YYYYMMDDHHi:4:2}-${YYYYMMDDHHi:6:2}"
START_HH="${YYYYMMDDHHi:8:2}"
maxpostpernode=20    # <------ qtde max de convert_mpas por no!

export DIRRUN="${DIRHOMED}/run.${RUN_ID}"

if [[ -e "${DIRRUN}" ]]; then
    echo "ERROR: Working directory already exists: ${DIRRUN}" >&2
    exit 1
fi

mkdir -p "${DIRRUN}" || exit 1
#-------------------------------------------------------

cd ${DIRRUN}

# NLEVS get from t_iso_levels in Registry_isobaric.xml:
if [ -s ${MONANDIR}/src/core_atmosphere/diagnostics/Registry_isobaric.xml ]
then
   NLEV=$(grep "t_iso_levels" ${MONANDIR}/src/core_atmosphere/diagnostics/Registry_isobaric.xml | grep definition | cut -d\" -f4)
else
   NLEV=18
fi

# Definindo G ou R no MONAN_DIAG
if [[ $MODERUN == "R" ]]; then
   RORG=R
elif [[ $MODERUN == "G" ]]; then
   RORG=G
else
   echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"
   echo -e  "${RED}==>${NC} Make post template phase fails! Please select MODERUN=R (Regional) or MODERUN=G (Global) in 'setenv.bash'.\n"
   echo -e  "${RED}==>${NC} Exiting script. \n"
   exit -1
fi

diag_name_post=MONAN_DIAG_${RORG}_POS_${EXP}_${YYYYMMDDHHi}_${FIRST_POST_VALID}.x${RES}L${N_MODEL_LEV}.nc
diag_name_templ=MONAN_DIAG_${RORG}_POS_${EXP}_${YYYYMMDDHHi}_%y4%m2%d2%h2.%n2.00.x${RES}L${N_MODEL_LEV}.nc


rm -fr ${DIRRUN}/qctlinfo.gs
cp -f ${SCRIPTS}/setenv.bash ${DIRRUN}

chmod 755 ${DATAOUT}/${RUN_ID}/Post/*
cat > ${DIRRUN}/qctlinfo.gs <<EOGS
'reinit'
'sdfopen ${DATAOUT}/${RUN_ID}/Post/${diag_name_post}'

'q ctlinfo'
say result

'quit'
EOGS


cd ${DIRRUN}

. ${SCRIPTS}/setenv.bash
chmod 755 *

if [[ ! -s "${DATAOUT}/${RUN_ID}/Post/${diag_name_post}" ]]; then
    echo "ERROR: First postprocessed file is missing:" >&2
    echo "  ${diag_name_post}" >&2
    exit 1
fi

grads -blc "run ${DIRRUN}/qctlinfo.gs" | awk '/dset/,/endvars/' > ${DIRRUN}/qctlinfo.ctl

if [[ ! -s "${DIRRUN}/qctlinfo.ctl" ]]; then
    echo "ERROR: GrADS did not generate a valid control-file description." >&2
    exit 1
fi

chmod 755 ${DIRRUN}/qctlinfo.ctl


timectl=$(grep tdef ${DIRRUN}/qctlinfo.ctl | cut -d" " -f4)
sed -i '3a\options template' ${DIRRUN}/qctlinfo.ctl
sed -i "/tdef/c\tdef ${nfiles} linear ${timectl} ${TDEF_MIN}mn" ${DIRRUN}/qctlinfo.ctl
sed -i "/dset/c\dset ^${diag_name_templ}" ${DIRRUN}/qctlinfo.ctl

chmod 755 ${DIRRUN}/*
mv ${DIRRUN}/qctlinfo.ctl ${DATAOUT}/${RUN_ID}/Post/${diag_name_post}.template.ctl
rm -fr ${DIRRUN}
