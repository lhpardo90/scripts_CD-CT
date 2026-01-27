#!/bin/bash 
umask 022

#set -euo pipefail

# Accept 4 or 5 args (5th = SST on/off)
if [ $# -ne 4 ] && [ $# -ne 5 ]; then
  echo ""
  echo "Usage: ${0} EXP_NAME RESOLUTION LABELI FCST [USE_SST]"
   echo ""
   echo "EXP_NAME    :: Forcing: GFS"
   echo "            :: Others options to be added later..."
   echo "RESOLUTION  :: number of points in resolution model grid, e.g: 1024002  (24 km)"
   echo "LABELI      :: Initial date YYYYMMDDHH, e.g.: 2024010100"
   echo "FCST        :: Forecast hours, e.g.: 24 or 36, etc."
   echo "USE_SST    :: on | off  (default: off)"
   echo ""
   echo "24 hour forecast example:"
   echo "${0} GFS 1024002 2024010100 24"
   echo ""

   exit
fi

# Set environment variables exports:
echo ""
echo -e "\033[1;32m==>\033[0m Moduling environment for MONAN model...\n"
. setenv.bash

echo ""
echo "---- Make Init Atmosphere ----"
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
USE_SST=${5:-off}
#-------------------------------------------------------


# Local variables--------------------------------------
date_base="${YYYYMMDDHHi:0:4}-${YYYYMMDDHHi:4:2}-${YYYYMMDDHHi:6:2} ${YYYYMMDDHHi:8:2}:00:00"
start_epoch=$(date -d "${date_base}" +%s)
final_epoch=$(( start_epoch + FCST*3600 ))
start_date=$(date -d "@${start_epoch}" +%Y-%m-%d_%H:%M:%S)
final_date=$(date -d "@${final_epoch}" +%Y-%m-%d_%H:%M:%S)

GEODATA=${DATAIN}/WPS_GEOG
cores=${INITATMOS_ncores}
export DIRRUN=${DIRHOMED}/run.${YYYYMMDDHHi}; rm -fr ${DIRRUN}; mkdir -p ${DIRRUN}
#-------------------------------------------------------
mkdir -p ${DATAOUT}/${YYYYMMDDHHi}/Pre/logs


if [ ! -s "${DATAIN}/fixed/x1.${RES}.graph.info.part.${cores}" ]
then
   if [ ! -s "${DATAIN}/fixed/x1.${RES}.graph.info" ]
   then
      cd ${DATAIN}/fixed
      echo -e "${GREEN}==>${NC} downloading meshes tgz files ... \n"
      cd ${DATAIN}/fixed
      wget https://www2.mmm.ucar.edu/projects/mpas/atmosphere_meshes/x1.${RES}.tar.gz
      wget https://www2.mmm.ucar.edu/projects/mpas/atmosphere_meshes/x1.${RES}_static.tar.gz
      tar -xzvf x1.${RES}.tar.gz
      tar -xzvf x1.${RES}_static.tar.gz
   fi
   echo -e "${GREEN}==>${NC} Creating x1.${RES}.graph.info.part.${cores} ... \n"
   cd ${DATAIN}/fixed
   gpmetis -minconn -contig -niter=200 x1.${RES}.graph.info ${cores}
   rm -fr x1.${RES}.tar.gz x1.${RES}_static.tar.gz
fi

if [ "${USE_SST}" = "on" ]; then
  NAMELIST_TMPL="${SCRIPTS}/namelists/namelist.init_atmosphere.SST"
else
  NAMELIST_TMPL="${SCRIPTS}/namelists/namelist.init_atmosphere.TEMPLATE"
fi
[ -f "${NAMELIST_TMPL}" ] || { echo "Missing ${NAMELIST_TMPL}"; exit 1; }


files_needed=("${NAMELIST_TMPL}" "${SCRIPTS}/namelists/streams.init_atmosphere.TEMPLATE" "${DATAIN}/fixed/x1.${RES}.graph.info.part.${cores}" "${DATAIN}/fixed/x1.${RES}.static.nc" "${DATAOUT}/${YYYYMMDDHHi}/Pre/${EXP}:${start_date:0:13}" "${EXECS}/init_atmosphere_model")
for file in "${files_needed[@]}"
do
  if [ ! -s "${file}" ]
  then
    echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"	  
    echo -e  "${RED}==>${NC} [${0}] At least the file ${file} was not generated. \n"
    exit -1
  fi
done


sed -e "s,#LABELI#,${start_date},g;s,#LABELF#,${final_date},g;s,#GEODAT#,${GEODATA},g;s,#RES#,${RES},g" \
	 ${NAMELIST_TMPL} > ${DIRRUN}/namelist.init_atmosphere

sed -e "s,#RES#,${RES},g" \
    ${SCRIPTS}/namelists/streams.init_atmosphere.TEMPLATE > ${DIRRUN}/streams.init_atmosphere


# --- Lianet: SST per-file links into run dir ----------
if [ "${USE_SST:-off}" = "on" ]; then
  SSTSRC="${DATAIN}/SST"
  if [ ! -d "${SSTSRC}" ]; then
    echo -e "${RED}ERROR${NC}: Expected SST directory not found: ${SSTSRC}"
    exit -1
  fi

  # fg_interval (seconds) from the final namelist we're about to run
  fg_interval=$(
    awk -F'=' 'tolower($1) ~ /config_fg_interval/ { gsub(/[^0-9]/,"",$2); print $2 }' \
      "${DIRRUN}/namelist.init_atmosphere"
  )
  if ! [[ "${fg_interval}" =~ ^[0-9]+$ ]] || [ -z "${fg_interval}" ]; then
    echo -e "${RED}ERROR${NC}: config_fg_interval must be an integer (seconds) in ${DIRRUN}/namelist.init_atmosphere"
    exit -1
  fi

  echo -e "${GREEN}==>${NC} Linking SST tiles into run dir (per-file)..."
  sst_missing=0

  for ((t=${start_epoch}; t<=${final_epoch}; t+=fg_interval)); do
    tag=$(date -d "@${t}" +"%Y-%m-%d_00")
    src="${SSTSRC}/SST:${tag}"
    dst="${DIRRUN}/SST:${tag}"
    if [ -e "${src}" ]; then
      ln -sfn "${src}" "${dst}"
    else
      echo -e "${YELLOW}WARNING${NC}: Missing SST file: ${src}"
      sst_missing=1
    fi
  done

  # Fail hard if coverage is incomplete (flip to a soft warning if you prefer)
  if [ ${sst_missing} -ne 0 ]; then
    echo -e "${RED}ERROR${NC}: SST files are incomplete for the required init window. Aborting."
    exit -1
  fi
fi
# -------------------------------------------------------------------------------

cp -f "${DATAIN}/fixed/x1.${RES}.graph.info.part.${cores}" ${DIRRUN}
cp -f "${DATAIN}/fixed/x1.${RES}.static.nc" ${DIRRUN}
cp -f "${DATAOUT}/${YYYYMMDDHHi}/Pre/${EXP}:${start_date:0:13}" ${DIRRUN}
cp -f "${EXECS}/init_atmosphere_model" ${DIRRUN}
cp -f "${SCRIPTS}/setenv.bash" ${DIRRUN}

chmod 755 "${DIRRUN}/"*
chmod 755 "${DATAOUT}/${YYYYMMDDHHi}/Pre/"*

rm -f "${DIRRUN}/initatmos.bash"

if [ ${SCHEDULER_SYSTEM} != "GENERIC" ]
then
   sed -e "s,#JOBNAME#,${INITATMOS_jobname},g;
   s,#NNODES#,${INITATMOS_nnodes},g;
   s,#NCPUS#,${INITATMOS_ncpus},g;
   s,#NTASKS#,${INITATMOS_ncores},g;
   s,#NTASKSPNODE#,${INITATMOS_ncpn},g;
   s,#NTHREADS#,${INITATMOS_nthreads},g;
   s,#PARTITION#,${INITATMOS_QUEUE},g;
   s,#WALLTIME#,${INITATMOS_walltime},g;
   s,#OUTPUTJOB#,${DATAOUT}/${YYYYMMDDHHi}/Pre/logs/initatmos.bash.o,g;
   s,#ERRORJOB#,${DATAOUT}/${YYYYMMDDHHi}/Pre/logs/initatmos.bash.e,g" \
   ${SCRIPTS}/stools/submit_${SYSTEM_KEY}.bash_TEMPLATE > "${DIRRUN}/initatmos.bash" 
else
   echo "#!/bin/bash -x" > "${DIRRUN}/initatmos.bash" 
fi

cat << EOF > "${DIRRUN}/initatmos.bash"

export executable=init_atmosphere_model

ulimit -c unlimited
ulimit -v unlimited
ulimit -s unlimited


cd ${DIRRUN}
. ${SCRIPTS}/setenv.bash

date
beg_secs=\`date +"%s"\`

if [ "$HOSTNAME" = "egeon" ]; then
   echo "-- SLURM_JOB_ID: \$SLURM_JOB_ID"
   time mpirun -np ${INITATMOS_ncores} ./\${executable}
else
   echo "-- PBS_JOBID: \$PBS_JOBID"
   time mpirun --ppn ${INITATMOS_ncpn} -np ${INITATMOS_ncores} --depth=${INITATMOS_nthreads} --cpu-bind depth ./\${executable}
fi

date
end_secs=\`date +"%s"\`

let wallsecs=\$end_secs-\$beg_secs
echo "INITATMOS time taken by run in seconds is " \$wallsecs


mv "${DIRRUN}/log.init_atmosphere.0000.out" "${DATAOUT}/${YYYYMMDDHHi}/Pre/logs/log.init_atmosphere.0000.x1.${RES}.init.nc.${YYYYMMDDHHi}.out"
mv "${DIRRUN}/namelist.init_atmosphere" "${DATAOUT}/${YYYYMMDDHHi}/Pre/logs"
mv "${DIRRUN}/streams.init_atmosphere" "${DATAOUT}/${YYYYMMDDHHi}/Pre/logs"
if [ "${USE_SST}" = "on" ]; then
  mv "${DIRRUN}/x1.${RES}.sfc_update.nc" "${DATAOUT}/${YYYYMMDDHHi}/Pre"
else
  mv "${DIRRUN}/x1.${RES}.init.nc" "${DATAOUT}/${YYYYMMDDHHi}/Pre"
fi

EOF

chmod a+x ${DIRRUN}/initatmos.bash

case "${SCHEDULER_SYSTEM}" in
   SLURM)
      echo -e  "${GREEN}==>${NC} Sbatch initatmos.bash...\n"
      cd ${DIRRUN}
      sbatch --wait ${DIRRUN}/initatmos.bash
      ;;
    PBS)
      echo -e  "${GREEN}==>${NC} qsub initatmos.bash...\n"
      cd ${DIRRUN}
      qsub -W block=true ${DIRRUN}/initatmos.bash
      ;;
#    GENERIC)
#      echo "Nenhum gerenciador detectado"
#      cd ${DIRRUN}
#      ${DIRRUN}/initatmos.bash
#      ;;
esac

mv "${DIRRUN}/initatmos.bash" "${DATAOUT}/${YYYYMMDDHHi}/Pre/logs"

# NOTE: THIS CHECK DOES NOT ACCOUNT FOR LEFTOVER FILES FROM PREVIOUS EXECUTIONS FOR THE SAME INITIAL DATE
if [ "${USE_SST}" = "on" ]; then
  if [ ! -s "${DATAOUT}/${YYYYMMDDHHi}/Pre/x1.${RES}.sfc_update.nc" ]; then
    echo -e "\n${RED}==>${NC} Init Atmosphere failed: missing x1.${RES}.sfc_update.nc\n"
    exit -1
  fi
else
  if [ ! -s "${DATAOUT}/${YYYYMMDDHHi}/Pre/x1.${RES}.init.nc" ]; then
    echo -e "\n${RED}==>${NC} Init Atmosphere failed: missing x1.${RES}.init.nc\n"
    exit -1
  fi
fi

chmod 775 "${DATAOUT}/${YYYYMMDDHHi}/Pre/"*
rm -fr ${DIRRUN}
