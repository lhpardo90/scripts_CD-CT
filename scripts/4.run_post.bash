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
#        o VCheck all input files before
#        o Creates the submition script
#        o Submit the post
#        o Veriffy all files generated
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

if [ -z "${SCRIPTS:-}" ] || [ -z "${DIRHOMED:-}" ]; then
    echo "ERROR: Environment not initialized."
    echo "Run this workflow through 0.run_all.bash."
    exit 1
fi

echo ""
echo "---- Run Post ----"
echo ""

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

# Determine the segment being postprocessed
if [[ "${INIT_MODE}" == "RESTART" ]]; then
    MODEL_START_TIME="${YYYYMMDDHHi_restart}"
    POST_LOG_DIR="${DATAOUT}/${RUN_ID}/Post/logs/restart_${MODEL_START_TIME}"
else
    MODEL_START_TIME="${YYYYMMDDHHi}"
    POST_LOG_DIR="${DATAOUT}/${RUN_ID}/Post/logs"
fi

# Diagnostic interval in seconds
IFS=: read -r dh dm ds <<< "${DIAG_INTERVAL}"

DIAG_INTERVAL_SEC=$((10#$dh*3600 + 10#$dm*60 + 10#$ds))

# Start and duration of the selected segment
START_EPOCH=$(
    date -u -d \
    "${MODEL_START_TIME:0:4}-${MODEL_START_TIME:4:2}-${MODEL_START_TIME:6:2} ${MODEL_START_TIME:8:2}:00:00" \
    +%s
)

FORECAST_SEC=$((FCST * 3600))

# Skip the handoff timestamp for restart segments.
# That output belongs to the preceding segment.
if [[ "${INIT_MODE}" == "RESTART" ]]; then
    FIRST_OFFSET=${DIAG_INTERVAL_SEC}
else
    FIRST_OFFSET=0
fi

if (( FIRST_OFFSET > FORECAST_SEC )); then
    echo "ERROR: No diagnostic outputs expected within this segment." >&2
    exit 1
fi

# Number of diagnostic files to process
nfiles=$(( (FORECAST_SEC - FIRST_OFFSET) / DIAG_INTERVAL_SEC + 1 ))

if (( nfiles < 1 )); then
    echo "ERROR: No diagnostic times within requested segment." >&2
    exit 1
fi

mkdir -p "${POST_LOG_DIR}"

# Local variables--------------------------------------
START_DATE_YYYYMMDD="${YYYYMMDDHHi:0:4}-${YYYYMMDDHHi:4:2}-${YYYYMMDDHHi:6:2}"
START_HH="${YYYYMMDDHHi:8:2}"
maxpostpernode=30    # <------ qtde max de convert_mpas por no!

export DIRRUN="${DIRHOMED}/run.${RUN_ID}"

if [[ -e "${DIRRUN}" ]]; then
    echo "ERROR: Working directory already exists: ${DIRRUN}" >&2
    echo "A model or preprocessing job may still be running." >&2
    exit 1
fi

mkdir -p "${DIRRUN}" || exit 1

NLEV=18
#-------------------------------------------------------

# Definindo G ou R no MONAN_DIAG
if [[ $MODERUN == "R" ]]; then
   RORG=R
elif [[ $MODERUN == "G" ]]; then
   RORG=G
else
   echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"
   echo -e  "${RED}==>${NC} Post fails! Please select MODERUN=R (Regional) or MODERUN=G (Global) in 'setenv.bash'.\n"
   echo -e  "${RED}==>${NC} Exiting script. \n"
   exit -1
fi
#------------------------------------------------------------------------------------

# Calculating default parameters for different resolutions
# global mesh
if [[ "$RES" == "40962" ]]; then  #120Km
   NLAT=151 #180/1.2
   NLON=301 #360/1.2
   STARTLAT=-90.0
   STARTLON=0.0
   ENDLAT=90.0
   ENDLON=360.0
elif [[ "$RES" == "163842" ]]; then  #60Km
   NLAT=301 #180/0.6
   NLON=601 #360/0.6
   STARTLAT=-90.0
   STARTLON=0.0
   ENDLAT=90.0
   ENDLON=360.0
elif [[ "$RES" == "655362" ]]; then  #30Km
   NLAT=601 #180/0.3
   NLON=1201 #360/0.3
   STARTLAT=-90.0
   STARTLON=0.0
   ENDLAT=90.0
   ENDLON=360.0
elif [[ "$RES" == "1024002" ]]; then  #24Km
   NLAT=721  #180/0.25
   NLON=1441 #360/0.25
   STARTLAT=-90.0
   STARTLON=0.0
   ENDLAT=90.0
   ENDLON=360.0
elif [[ "$RES" == "2621442" ]]; then  #15Km
   NLAT=1201 #180/0.15
   NLON=2401 #360/0.15
   STARTLAT=-90.0
   STARTLON=0.0
   ENDLAT=90.0
   ENDLON=360.0
elif [[ "$RES" == "5898242" ]]; then  #10Km
   NLAT=1801 #180/0.10
   NLON=3601 #360/0.10
   STARTLAT=-90.0
   STARTLON=0.0
   ENDLAT=90.0
   ENDLON=360.0
elif [[ "$RES" == "23592962" ]]; then  #5Km
   NLAT=3601 #180/0.05
   NLON=7201 #360/0.05
   STARTLAT=-90.0
   STARTLON=0.0
   ENDLAT=90.0
   ENDLON=360.0
elif [[ "$RES" == "65536002" ]]; then  #3Km
   NLAT=6001 #180/0.03 
   NLON=12001 #360/0.03 
   STARTLAT=-90.0
   STARTLON=0.0
   ENDLAT=90.0
   ENDLON=360.0
# regional mesh
elif [[ "$RES" == "655362.REG.AMS_CAR" ]]; then #30 km (AMS + Caribe)
   NLAT=354     #106/0.3 +1
   NLON=301     #90/0.3 +1
   STARTLAT=-64.0
   ENDLAT=42
   STARTLON=254.0
   ENDLON=344.0
elif [[ "$RES" == "5898242.REG.AMS_CAR" ]]; then #10 km (AMS + Caribe)
   NLAT=1061   #106/0.1 +1
   NLON=901   #90/0.1 +1
   STARTLAT=-64.0
   ENDLAT=42.0
   STARTLON=254.0
   ENDLON=344.0
elif [[ "$RES" == "23592962.REG.AMS_CAR" ]]; then #5 km (AMS + Caribe)
   NLAT=2121    #106/0.05 +1
   NLON=1801    #90/0.05 +1
   STARTLAT=-64.0
   ENDLAT=42.0
   STARTLON=254.0
   ENDLON=344.0
elif [[ "$RES" == "ellipse_5km_nowcasting" ]]; then # 5 km nowcasting grid
   NLAT=921     # 46/0.05 + 1
   NLON=1001    # 50/0.05 + 1
   STARTLAT=-42.0
   ENDLAT=4.0
   STARTLON=281.0
   ENDLON=331.0
elif [[ "$RES" == "ellipse_3km_nowcasting" ]]; then # 3 km nowcasting grid
   NLAT=1504    # 45.09/0.03 + 1
   NLON=1601    # 48/0.03 + 1
   STARTLAT=-42.0
   ENDLAT=3.09
   STARTLON=282.0
   ENDLON=330.0
else
   echo -e "\n${RED}==>${NC} ***** ATTENTION *****\n"
   echo -e "${RED}==>${NC} [${0}] Post-processing parameters for resolution ${RES} have not been set.\n"
   exit -1
fi
#-------------------------------------------------------


files_needed=("${SCRIPTS}/namelists/include_fields.diag${VARTABLE}" "${SCRIPTS}/namelists/convert_mpas.nml" "${SCRIPTS}/namelists/target_domain.TEMPLATE" "${EXECS}/convert_mpas" "${DATAOUT}/${RUN_ID}/Pre/x1.${RES}.init.nc")
for file in "${files_needed[@]}"
do
  if [ ! -s "${file}" ]
  then
    echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"	  
    echo -e  "${RED}==>${NC} [${0}] At least the file ${file} was not generated. \n"
    exit -1
  fi
done


echo "${nfiles} post to submit."
echo "Max ${maxpostpernode} submits per nodes."
how_many_nodes ${nfiles} ${maxpostpernode}

# Cria os diretorios e arquivos/links para cada saida do convert_mpas:
cd ${DIRRUN}

for ii in $(seq 1 ${nfiles})
do
   i=$(printf "%04d" ${ii})
   mkdir -p ${DIRRUN}/dir.${i}
   cp -f ${SCRIPTS}/namelists/include_fields.diag${VARTABLE}  ${DIRRUN}/dir.${i}/include_fields.diag${VARTABLE}
   cp -f ${DIRRUN}/dir.${i}/include_fields.diag${VARTABLE} ${DIRRUN}/dir.${i}/include_fields
   sed -e "s,#NISOLEV#,${NLEV},g;s,#NMODELLEV#,${N_MODEL_LEV},g" \
      ${SCRIPTS}/namelists/convert_mpas.nml > ${DIRRUN}/dir.${i}/convert_mpas.nml
   sed -e "s,#NLAT#,${NLAT},g;s,#NLON#,${NLON},g;s,#STARTLAT#,${STARTLAT},g;s,#ENDLAT#,${ENDLAT},g;s,#STARTLON#,${STARTLON},g;s,#ENDLON#,${ENDLON},g;" \
      ${SCRIPTS}/namelists/target_domain.TEMPLATE > ${DIRRUN}/dir.${i}/target_domain

done

cd ${DIRRUN}
chmod -R 755 ${DIRRUN}/*

# Laco para criar os arquivos de submissao com os blocos de convertmpas para cada node:
echo "scheduler system = " ${SCHEDULER_SYSTEM} 
echo "system key = " ${SYSTEM_KEY}
echo ""
# Laco para criar os arquivos de submissao com os blocos de convertmpas para cada node:
node=1
inicio=1   
fim=$((maxpostpernode <= nfiles ? maxpostpernode : nfiles))
while [ ${inicio} -le ${nfiles} ]
do
   rm -f ${DIRRUN}/PostAtmos_node.${node}.sh

   if [ ${SCHEDULER_SYSTEM} != "GENERIC" ]   
   then
      sed -e "s,#JOBNAME#,MO.Pos${node},g;
      s,#NNODES#,${POST_nnodes},g;
      s,#NCPUS#,${POST_ncpus},g;
      s,#NTASKS#,${POST_ncores},g;
      s,#NTASKSPNODE#,${POST_ncpn},g;
      s,#NTHREADS#,${POST_nthreads},g;
      s,#PARTITION#,${POST_QUEUE},g;
      s,#WALLTIME#,${POST_walltime},g;
      s,#OUTPUTJOB#,${POST_LOG_DIR}/PostAtmos_node.${node}.o,g;
      s,#ERRORJOB#,${POST_LOG_DIR}/PostAtmos_node.${node}.e,g" \
      ${SCRIPTS}/stools/submit_${SYSTEM_KEY}.bash_TEMPLATE > \
      ${DIRRUN}/PostAtmos_node.${node}.sh
   else
      echo "#!/bin/bash " > ${DIRRUN}/PostAtmos_node.${node}.sh
   fi
   
cat << EOSH >> ${DIRRUN}/PostAtmos_node.${node}.sh 

cd ${DIRRUN}

set +eu
. ${SCRIPTS}/setenv.bash
set -Eeuo pipefail

if [ ${SCHEDULER_SYSTEM} == "SLURM" ]; then
   echo "-- SLURM_JOB_ID: \$SLURM_JOB_ID"
elif [ ${SCHEDULER_SYSTEM} == "PBS" ]; then
   echo "-- PBS_JOBID: \$PBS_JOBID"
fi

chmod 755 ${DIRRUN}/*

echo "Executing posts ${inicio} to ${fim} in node Node ${node}."

for ii in \$(seq  ${inicio} ${fim})
do
   i=\$(printf "%04d" \${ii})
   echo "Preparing post files \${i}"
   cp -f ${DATAOUT}/${RUN_ID}/Pre/x1.${RES}.init.nc ${DIRRUN}/dir.\${i} &
   cp -f ${EXECS}/convert_mpas ${DIRRUN}/dir.\${i} &
done

wait

pids=()
post_indices=()

for ii in \$(seq  ${inicio} ${fim})
do
   i=\$(printf "%04d" \${ii})
   echo "Executing post \${i}"
   cd ${DIRRUN}/dir.\${i}
   chmod 755 *
   hh=${YYYYMMDDHHi:8:2}
   currentdate=\$(date -u -d "@\$(( ${START_EPOCH} + ${FIRST_OFFSET} + (\${i}-1)*${DIAG_INTERVAL_SEC} ))" +"%Y%m%d%H.%M.%S")
   diag_name=MONAN_DIAG_${RORG}_MOD_${EXP}_${YYYYMMDDHHi}_\${currentdate}.x${RES}L${N_MODEL_LEV}.nc

   model_file=${DATAOUT}/${RUN_ID}/Model/\${diag_name}

   if [[ ! -s "\${model_file}" ]]; then
      echo "ERROR: Missing or empty input: \${model_file}" >&2
      exit 1
   fi

   rm -f latlon.nc convert_mpas.output

   echo ""
   echo "Executing convert_mpas for \${diag_name}"
   chmod 755 ${DATAOUT}/${RUN_ID}/Model/*
   ./convert_mpas x1.${RES}.init.nc "\${model_file}"  > convert_mpas.output 2>&1 &

   pids[\${ii}]=\$!
   post_indices+=("\${ii}")
done

# necessario aguardar as rodadas em background
conversion_failed=0

for ii in "\${post_indices[@]}"
do
   if ! wait "\${pids[\${ii}]}"; then
      i=\$(printf "%04d" "\${ii}")
      echo "ERROR: convert_mpas failed for post \${i}" >&2
      echo "       Log: ${DIRRUN}/dir.\${i}/convert_mpas.output" >&2
      conversion_failed=1
   fi
done

if (( conversion_failed != 0 )); then
   exit 1
fi

for ii in \$(seq  ${inicio} ${fim})
do
   i=\$(printf "%04d" \${ii})
   hh=${YYYYMMDDHHi:8:2}
   currentdate=\$(date -u -d "@\$(( ${START_EPOCH} + ${FIRST_OFFSET} + (\${i}-1)*${DIAG_INTERVAL_SEC} ))" +"%Y%m%d%H.%M.%S")
   diag_name_post=MONAN_DIAG_${RORG}_POS_${EXP}_${YYYYMMDDHHi}_\${currentdate}.x${RES}L${N_MODEL_LEV}.nc

   cd ${DIRRUN}/dir.\${i}

   if [[ ! -s latlon.nc ]]; then
      echo "ERROR: Missing or empty latlon.nc in \$PWD" >&2
      exit 1
   fi

   if ! ncdump -k latlon.nc >/dev/null 2>&1; then
      echo "ERROR: latlon.nc is not a readable NetCDF file in \$PWD" >&2
      exit 1
   fi

   chmod 755 *

   # Replace existing postprocessed output for this segment.
   if ! cp -f latlon.nc \
       "${DATAOUT}/${RUN_ID}/Post/\${diag_name_post}" \
       >> convert_mpas.output 2>&1; then

       echo "ERROR: Could not save postprocessed output:" >&2
       echo "       \${diag_name_post}" >&2
       exit 1

   fi
   
done
 
wait

EOSH
  
   chmod a+x ${DIRRUN}/PostAtmos_node.${node}.sh
   chmod 755 ${DIRRUN}/*
   cp -f ${DIRRUN}/PostAtmos_node.${node}.sh ${POST_LOG_DIR}
   chmod 755 ${DATAOUT}/${RUN_ID}/Post/*
   case "${SCHEDULER_SYSTEM}" in
      SLURM)
         echo "Sbatch PostAtmos_node.${node}.sh"
         jobid[${node}]=$(sbatch --parsable ${DIRRUN}/PostAtmos_node.${node}.sh)
         echo "JobId node ${node} = ${jobid[${node}]} , convert_mpas ${inicio} to ${fim}"
         echo ""
         ;;
       PBS)
         echo "Rodando em PBS"
         echo -e  "${GREEN}==>${NC} qsub PostAtmos_node.${node}.sh...\n"
         cd ${DIRRUN}
	 		jobid[${node}]=$(qsub ${DIRRUN}/PostAtmos_node.${node}.sh | cut -d '.' -f1)
          ;;
#      GENERIC)
#         echo "Nenhum gerenciador detectado"
#         ${DIRRUN}/PostAtmos_node.${node}.sh
#         ;;
   esac
  
   inicio=$((fim + 1))
   temp=$((fim + maxpostpernode))
   fim=$(( temp < nfiles ? temp : nfiles ))
   node=$((node+1))
   sleep 5
done

total_nodes=${node}

# Dependencias JobId:
dependency="afterok"
for job_id in "${jobid[@]}"
do
   dependency="${dependency}:${job_id}"
done


# Script final , para conferir todos os arquivos, criar o template final  e apagar o diretorio DIRRUN
node=0
rm -f ${DIRRUN}/PostAtmos_node.${node}.sh


if [ ${SCHEDULER_SYSTEM} != "GENERIC" ]   
then
   sed -e "s,#JOBNAME#,MO.Pos${node},g;
   s,#NNODES#,${POST_nnodes},g;
   s,#NCPUS#,${POST_ncpus},g;
   s,#NTASKS#,${POST_ncores},g;
   s,#NTASKSPNODE#,${POST_ncpn},g;
   s,#NTHREADS#,${POST_nthreads},g;
   s,#PARTITION#,${POST_QUEUE},g;
   s,#WALLTIME#,${POST_walltime},g;
   s,#OUTPUTJOB#,${POST_LOG_DIR}/PostAtmos_node.${node}.o,g;
   s,#ERRORJOB#,${POST_LOG_DIR}/PostAtmos_node.${node}.e,g" \
   ${SCRIPTS}/stools/submit_${SYSTEM_KEY}.bash_TEMPLATE > \
   ${DIRRUN}/PostAtmos_node.${node}.sh
else
   echo "#!/bin/bash " > ${DIRRUN}/PostAtmos_node.${node}.sh
fi

cat << EOSH >> ${DIRRUN}/PostAtmos_node.${node}.sh 

cd ${DIRRUN}
. ${SCRIPTS}/setenv.bash

if [ ${SCHEDULER_SYSTEM} == "SLURM" ]; then
   echo "-- SLURM_JOB_ID: \$SLURM_JOB_ID"
elif [ ${SCHEDULER_SYSTEM} == "PBS" ]; then
   echo "-- PBS_JOBID: \$PBS_JOBID"
fi

# Saving important files to the logs directory:
cp -f ${EXECS}/CONVMPAS-VERSION.txt ${DATAOUT}/${RUN_ID}/Post
cp -f ${EXECS}/CONVMPAS-VERSION.txt ${POST_LOG_DIR}
cp -f ${DIRRUN}/dir.0001/target_domain ${POST_LOG_DIR}
cp -f ${DIRRUN}/dir.0001/convert_mpas.nml ${POST_LOG_DIR}
cp -f ${DIRRUN}/dir.0001/include_fields ${POST_LOG_DIR}
cp -f ${DIRRUN}/dir.0001/convert_mpas.output ${POST_LOG_DIR}
cp -f ${DIRRUN}/PostAtmos_node.*.sh ${POST_LOG_DIR}
cp -f ${DATAOUT}/${RUN_ID}/Model/MONAN-VERSION.txt ${POST_LOG_DIR}
if [ "${INIT_MODE}" = "RESTART" ]; then
    cp -f ${DATAOUT}/${RUN_ID}/Model/logs/restart_${MODEL_START_TIME}/* \
        ${POST_LOG_DIR}/
else
    find ${DATAOUT}/${RUN_ID}/Model/logs -maxdepth 1 -type f \
        -exec cp -f {} ${POST_LOG_DIR}/ \;
fi

cd ${DIRRUN}/..
rm -fr ${DIRRUN}


EOSH
chmod a+x ${DIRRUN}/PostAtmos_node.${node}.sh


case "${SCHEDULER_SYSTEM}" in
   SLURM)
      echo "Sbatch PostAtmos_node.${node}.sh"
      sbatch --wait --dependency=${dependency} "${DIRRUN}/PostAtmos_node.${node}.sh" || exit 1
      ;;
    PBS)
      echo "Rodando em PBS"
      echo -e  "${GREEN}==>${NC} qsub PostAtmos_node.${node}.sh...\n"
      cd ${DIRRUN}
      qsub -W depend=${dependency} -W block=true "${DIRRUN}/PostAtmos_node.${node}.sh" || exit 1
      ;;
#   GENERIC)
#      echo "Nenhum gerenciador detectado"
#      ${DIRRUN}/PostAtmos_node.${node}.sh
#      ;;
esac


#CR: passar este scriptpara dentro do script PostAtmos_node.0.sh, submetido.
cd ${SCRIPTS}
chmod 755 ${DATAOUT}/${RUN_ID}/Post/*
if ! time "${SCRIPTS}/make_template.bash" \
   "${EXP}" "${RES}" "${N_MODEL_LEV}" "${YYYYMMDDHHi}" "${RUN_ID}" "${FCST}" \
   "${INIT_MODE}" "${YYYYMMDDHHi_restart}" "${DIAG_INTERVAL}"
then
   echo "ERROR: Postprocessing failed." >&2
   exit 1
fi

for ((n=0 ; n<total_nodes ; n++)) 
do

   if [ ${SCHEDULER_SYSTEM} = "SLURM" ]; then
      : # Slurm já gera JOBID na submissão.
   elif [ ${SCHEDULER_SYSTEM} = "PBS" ]; then
      JOBID=$(sed -n '4p' ${POST_LOG_DIR}/PostAtmos_node."${n}".o | awk '{print $3}' | sed "s/.pbs-ha//g")
      mv ${POST_LOG_DIR}/PostAtmos_node."${n}".o ${POST_LOG_DIR}/PostAtmos_node."${n}".o.${JOBID}
      mv ${POST_LOG_DIR}/PostAtmos_node."${n}".e ${POST_LOG_DIR}/PostAtmos_node."${n}".e.${JOBID}
fi
done
chmod a+r ${POST_LOG_DIR}/PostAtmos_node.*.o.*
chmod a+r ${POST_LOG_DIR}/PostAtmos_node.*.e.*
