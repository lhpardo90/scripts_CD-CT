#!/bin/bash 
umask 022
#-----------------------------------------------------------------------------#
# !SCRIPT: pre_processing
#
# !DESCRIPTION:
#     Script to prepare boundary and initials conditions for MONAN model.
#     
#     Performs the following tasks:
# 
#        o Creates topography, land use and static variables
#        o Ungrib GFS data
#        o Interpolates to model the grid
#        o Creates initial and boundary conditions
#        o Creates scripts to run the model and post-processing (CR: to be modified to phase 3 and 4)
#        o Integrates the MONAN model ((CR: to be modified to phase 3)
#        o Post-processing (netcdf for grib2, latlon regrid, crop) (CR: to be modified to phase 4)
#
#-----------------------------------------------------------------------------#

if [ $# -ne 4 ] && [ $# -ne 5 ]; then
   echo ""
   echo "Usage: ${0} EXP_NAME RESOLUTION LABELI FCST [SST_FLAG]"
   echo ""
   echo "EXP_NAME    :: Forcing: GFS"
   echo "            :: Others options to be added later..."
   echo "RESOLUTION  :: number of points in resolution model grid, e.g: 1024002  (24 km)"
   echo "                                                                 40962  (120 km)"
   echo "LABELI      :: Initial date YYYYMMDDHH, e.g.: 2024010100"
   echo "FCST        :: Forecast hours, e.g.: 24 or 36, etc."
   echo "SST_FLAG    :: on | off  (default: off)"
   echo ""
   echo "24 hour forecast example for 24km:"
   echo "${0} GFS 1024002 2024010100 24"
   echo "48 hour forecast example for 120km:"
   echo "${0} GFS   40962 2024010100 48"
   echo ""

   exit
fi

# Set environment variables exports:
echo ""
echo -e "\033[1;32m==>\033[0m Moduling environment for MONAN model...\n"
. setenv.bash


echo ""
echo "---- Pre Processing ----"
echo ""


# Standart directories variables:---------------------------------------
DIRHOMES=${DIR_SCRIPTS}/scripts_CD-CT; mkdir -p ${DIRHOMES}    
DIRHOMED=${DIR_DADOS}/scripts_CD-CT;   mkdir -p ${DIRHOMED}  
SCRIPTS=${DIRHOMES}/scripts;           mkdir -p ${SCRIPTS}
DATAIN=${DIRHOMED}/datain;             mkdir -p ${DATAIN}
DATAOUT=${DIRHOMED}/dataout;           mkdir -p ${DATAOUT}
SOURCES=${DIRHOMES}/sources;           mkdir -p ${SOURCES}
EXECS=${DIRHOMED}/execs;               mkdir -p ${EXECS}
#----------------------------------------------------------------------


# Input variables:--------------------------------------
EXP=${1};         #EXP=GFS
RES=${2};         #RES=1024002
YYYYMMDDHHi=${3}; #YYYYMMDDHHi=2024012000
FCST=${4};        #FCST=24
SST_FLAG="${5:-off}"   # allow optional 5th arg
#-------------------------------------------------------


# Lianet: Choose namelist template based on flag -------
if [ "${SST_FLAG}" = "on" ]; then
  NAMELIST="${SCRIPTS}/namelists/namelist.init_atmosphere.SST"
else
  NAMELIST="${SCRIPTS}/namelists/namelist.init_atmosphere.TEMPLATE"
fi

if [ ! -f "${NAMELIST}" ]; then
  echo -e "${RED}ERROR${NC}: ${NAMELIST} not found."
  exit 1
fi

# (Optional guardrail: if user forced on/off, ensure namelist agrees)
if [ "${SST_FLAG}" = "on" ]; then
  config_init_case=$(grep -i 'config_init_case' "${NAMELIST}" | sed 's/!.*$//' | tail -n1 | awk -F'=' '{print $2}' | tr -cd '0-9')
  config_input_sst=$(grep -i 'config_input_sst' "${NAMELIST}" | sed 's/!.*$//' | tail -n1 | awk -F'=' '{print tolower($2)}' | tr -d ' .,\t')
  if [ "${config_init_case}" != "8" ] || [ "${config_input_sst}" != "true" ]; then
    echo -e "${RED}ERROR${NC}: SST_FLAG=on requires init_case=8 and config_input_sst=true in ${NAMELIST}."
    exit 1
  fi
fi
#------------------------------------------------------


# Local variables--------------------------------------
# Calculating CIs and final forecast dates in model namelist format:
yyyymmddi=${YYYYMMDDHHi:0:8}
hhi=${YYYYMMDDHHi:8:2}
yyyymmddhhf=$(date +"%Y%m%d%H" -d "${yyyymmddi} ${hhi}:00 ${FCST} hours" )
final_date=${yyyymmddhhf:0:4}-${yyyymmddhhf:4:2}-${yyyymmddhhf:6:2}_${yyyymmddhhf:8:2}.00.00
export DIRRUN=${DIRHOMED}/run.${YYYYMMDDHHi}; rm -fr ${DIRRUN}; mkdir -p ${DIRRUN}
#-------------------------------------------------------



echo -e  "${GREEN}==>${NC} Scripts_CD-CT last commit: \n"
git log | head -1


if [ ! -d ${DATAIN}/fixed ]
then
	echo -e  "${GREEN}==>${NC} copying and linking fixed input data ${SYSTEM_KEYC}... \n"
	mkdir -p ${DATAIN}
	rsync -rv --chmod=ugo=rw ${DIRDADOS}/MONAN_datain/datain/fixed ${DATAIN}
	rsync -rv --chmod=ugo=rwx ${DIRDADOS}/MONAN_datain/execs ${DIRHOMED}
	ln -sf ${DIRDADOS}/MONAN_datain/datain/WPS_GEOG ${DATAIN}
fi

# --- Lianet: SST handling (based on namelist and forecast window) -----------------------

if [ "${SST_FLAG}" = "on" ]; then

   config_fg_interval=$(grep -i 'config_fg_interval' "${NAMELIST}" | sed 's/!.*$//' | tail -n1 | awk -F'=' '{print $2}' | tr -d ' ,\t')
   
   SSTDIR="/pesq/dados/bam/paulo.kubota/monan/databcs/sst"
   SSTDESTDIR="${DATAIN}/SST"
   echo -e "${GREEN}==>${NC} Copying files from ${SSTDIR} into ${SSTDESTDIR} ...\n"
   
   mkdir -p $SSTDESTDIR
   
   # Start/end epochs from the script's start (YYYYMMDDHHi) and computed final (yyyymmddhhf)
   start_epoch=$(date -d "${yyyymmddi} ${hhi}:00" +%s)
   end_epoch=$(date -d "${yyyymmddhhf:0:4}-${yyyymmddhhf:4:2}-${yyyymmddhhf:6:2} ${yyyymmddhhf:8:2}:00" +%s)
   
   # Set step_sec based on config_fg_interval
   if [ -z "${config_fg_interval}" ]; then
      echo -e "${RED}ERROR${NC}: config_fg_interval is not set in ${NAMELIST}."
      exit 1
   else
      step_sec=$config_fg_interval
   fi
   echo "Using step_sec: $step_sec seconds"   
   
   # Copy files
   for ((t=${start_epoch}; t<=${end_epoch}; t+=step_sec)); do
      tag=$(date -d "@${t}" +"%Y-%m-%d_%H")
      src="${SSTDIR}/SST:${tag}"
      dst="${SSTDESTDIR}/SST:${tag}"
      if [ -e "${src}" ]; then
         if [ ! -e "${dst}" ]; then
            cp "${src}" "${dst}"
         else
            echo -e "${YELLOW}INFO${NC}: File already exists in destination: ${dst}"
         fi
      else
         echo -e "${YELLOW}WARNING${NC}: Missing SST source file: ${src}"
      fi      
   done
fi
# -------------------------------------------------------------------------------



# Creating the x1.${RES}.static.nc file once, if does not exist yet:---------------
if [ ! -s ${DATAIN}/fixed/x1.${RES}.static.nc ]
then
   echo -e "${GREEN}==>${NC} Creating static.bash for submiting init_atmosphere to create x1.${RES}.static.nc...\n"
   time ./make_static.bash ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}
else
   echo -e "${GREEN}==>${NC} File x1.${RES}.static.nc already exist in ${DATAIN}/fixed.\n"
fi
#----------------------------------------------------------------------------------


# Degrib phase:---------------------------------------------------------------------
echo -e  "${GREEN}==>${NC} Running Degrib:\n"
time ./make_degrib.bash ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST}
#----------------------------------------------------------------------------------




# Init Atmosphere phase:------------------------------------------------------------
echo -e  "${GREEN}==>${NC} Running Init Atmosphere...\n"
time ./make_initatmos.bash ${EXP} ${RES} ${YYYYMMDDHHi} ${FCST} ${SST_FLAG}
#----------------------------------------------------------------------------------




