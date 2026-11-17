#!/bin/bash
umask 022
#-----------------------------------------------------------------------------#
# !SCRIPT: run_model
#
# !DESCRIPTION:
#     Script to run the MONAN model over the forecast horizon.
#     
#     Performs the following tasks:
# 
#        o Check all input files before 
#        o Creates the submission script
#        o Submit the model
#        o Verify all files generated
#        
#
#-----------------------------------------------------------------------------#

if [ $# -ne 11 ]
then
   echo ""
   echo "Instructions: execute the command below"
   echo ""
   echo "${0} EXP RESOLUTION NUMBER_OF_LEVELS LABELI RUN_ID FCST INIT_MODE RESTART_TIME DIAG_INTERVAL HIST_INTERVAL RESTART_INTERVAL"
   echo ""
   echo "EXP         :: Initial or lateral boundary condition dataset (GFS or ERA)"
   echo "RESOLUTION  :: Number of horizontal grid cells (global) or regional mesh identifier (e.g., 1024002 for the ~24 km mesh)"
   echo "NUMBER_OF_LEVELS :: Number of vertical levels (e.g., 55)"
   echo "LABELI      :: Forecast initialization date and time (YYYYMMDDHH), e.g., 2026080100"
   echo "RUN_ID      :: Output directory name (must start with YYYYMMDDHH)"
   echo "FCST        :: Forecast length in hours (e.g., 24, 36, 48, etc.)"
   echo "INIT_MODE        :: COLD or RESTART"
   echo "RESTART_TIME     :: Checkpoint timestamp YYYYMMDDHH (empty for COLD)"
   echo "DIAG_INTERVAL    :: Diagnostic output interval HH:MM:SS"
   echo "HIST_INTERVAL    :: History output interval HH:MM:SS"
   echo "RESTART_INTERVAL :: Restart output interval HH:MM:SS"
   echo ""
   echo "Example for a 24-hour forecast:"
   echo "${0} GFS 1024002 55 2026080100 2026080100_CTRL 24 COLD '' 01:00:00 03:00:00 24:00:00"
   echo ""
   exit 1
fi

if [ -z "${SCRIPTS:-}" ] || [ -z "${DIRHOMED:-}" ]; then
    echo "ERROR: Environment not initialized."
    echo "Run this workflow through 0.run_all.bash."
    exit 1
fi

echo ""
echo "---- Run Model ----"
echo ""

# Input variables:--------------------------------------
EXP=${1};         #EXP=GFS
RES=${2};         #RES=1024002
N_MODEL_LEV=${3}; #NLEV=55
YYYYMMDDHHi=${4}; #YYYYMMDDHHi=2024012000
RUN_ID=${5};      #RUN_ID=2024012000_CTRL
FCST=${6};        #FCST=24
INIT_MODE=${7}
YYYYMMDDHHi_restart=${8}  # Restart checkpoint
DIAG_INTERVAL=${9}
HIST_INTERVAL=${10}
RESTART_INTERVAL=${11}
#-------------------------------------------------------

# Determine actual model start time
case "${INIT_MODE}" in
    COLD)
        MODEL_START_TIME="${YYYYMMDDHHi}"
        DO_RESTART=false
        ;;

    RESTART)
        MODEL_START_TIME="${YYYYMMDDHHi_restart}"
        DO_RESTART=true
        ;;

    *)
        echo "ERROR: INIT_MODE must be COLD or RESTART." >&2
        exit 1
        ;;
esac

if [[ ! "${MODEL_START_TIME}" =~ ^[0-9]{10}$ ]]; then
    echo "ERROR: Invalid model start timestamp: ${MODEL_START_TIME}" >&2
    exit 1
fi

# MPAS start time
start_date=${MODEL_START_TIME:0:4}-${MODEL_START_TIME:4:2}-${MODEL_START_TIME:6:2}_${MODEL_START_TIME:8:2}:00:00

cores=${MODEL_ncores}
CONFIG_CONV_INTERVAL="00:30:00"

# Separate logs for restart segments
if [[ "${INIT_MODE}" == "RESTART" ]]; then
    LOG_DIR="${DATAOUT}/${RUN_ID}/Model/logs/restart_${MODEL_START_TIME}"
else
    LOG_DIR="${DATAOUT}/${RUN_ID}/Model/logs"
fi

if [[ -e "${LOG_DIR}/model.bash" ]]; then
    echo "ERROR: Existing logs for this segment: ${LOG_DIR}" >&2
    exit 1
fi

mkdir -p "${LOG_DIR}" || exit 1

# Temporary run directory
export DIRRUN="${DIRHOMED}/run.${RUN_ID}"

if [[ -e "${DIRRUN}" ]]; then
    echo "ERROR: Run directory already exists: ${DIRRUN}" >&2
    echo "Check for unsaved files before deleting it." >&2
    exit 1
fi

mkdir -p "${DIRRUN}" || exit 1

# Diagnostic output interval in seconds
IFS=: read -r dh dm ds <<< "${DIAG_INTERVAL}"

DIAG_INTERVAL_SEC=$((10#$dh*3600 + 10#$dm*60 + 10#$ds))

if (( DIAG_INTERVAL_SEC <= 0 )); then
    echo "ERROR: DIAG_INTERVAL must be positive." >&2
    exit 1
fi

# Calculating default parameters for different resolutions
# global mesh
if [[ "$RES" == "40962" ]]; then      #120Km
   CONFIG_DT=600.0
   CONFIG_CONV_INTERVAL="00:15:00"
   CONFIG_LEN_DISP=120000
elif [[ "$RES" == "163842" ]]; then   #60Km
   CONFIG_DT=300.0
   CONFIG_CONV_INTERVAL="00:15:00"
   CONFIG_LEN_DISP=60000
elif [[ "$RES" == "655362" ]]; then   #30Km
   CONFIG_DT=150.0
   CONFIG_CONV_INTERVAL="00:15:00"
   CONFIG_LEN_DISP=30000
elif [[ "$RES" == "1024002" ]]; then  #24Km
   CONFIG_DT=150.0
   CONFIG_CONV_INTERVAL="00:15:00"
   CONFIG_LEN_DISP=24000
elif [[ "$RES" == "2621442" ]]; then  #15Km
   CONFIG_DT=90.0
   CONFIG_CONV_INTERVAL="00:15:00"
   CONFIG_LEN_DISP=15000
elif [[ "$RES" == "5898242" ]]; then  #10Km
   CONFIG_DT=60.0
   CONFIG_CONV_INTERVAL="00:15:00"
   CONFIG_LEN_DISP=10000
elif [[ "$RES" == "23592962" ]]; then  #5km
   CONFIG_DT=30.0
   CONFIG_CONV_INTERVAL="00:15:00"
   CONFIG_LEN_DISP=5000
elif [[ "$RES" == "65536002" ]]; then  #3Km
   CONFIG_DT=18.0
   CONFIG_CONV_INTERVAL="00:15:00"
   CONFIG_LEN_DISP=3000
# regional mesh
elif [[ "$RES" == "655362.REG.AMS_CAR" ]]; then #30 km (AMS + Caribe)
   CONFIG_DT=150.0
   CONFIG_CONV_INTERVAL="00:15:00"
   CONFIG_LEN_DISP=30000
elif [[ "$RES" == "5898242.REG.AMS_CAR" ]]; then #10 km (AMS + Caribe)
   CONFIG_DT=60.0
   CONFIG_CONV_INTERVAL="00:15:00"
   CONFIG_LEN_DISP=10000
elif [[ "$RES" == "23592962.REG.AMS_CAR" ]]; then #5 km (AMS + Caribe)
   CONFIG_DT=30.0
   CONFIG_CONV_INTERVAL="00:15:00"
   CONFIG_LEN_DISP=5000
elif [[ "$RES" == "ellipse_5km_nowcasting" ]]; then #5 km (Bacia do La Plata+Sudeste+Nordeste)
   CONFIG_DT=30.0
   CONFIG_CONV_INTERVAL="00:15:00"
   CONFIG_LEN_DISP=5000
elif [[ "$RES" == "ellipse_3km_nowcasting" ]]; then #3 km (Bacia do La Plata+Sudeste+Nordeste)
   CONFIG_DT=18.0
   CONFIG_CONV_INTERVAL="00:15:00"
   CONFIG_LEN_DISP=3000
else
    echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"
    echo -e  "${RED}==>${NC} [${0}] Simulation parameters for resolution $RES have not been set! Edit them in '3.run_model.bash'.\n"
    exit -1
fi
#-------------------------------------------------------

#-------------------------------------------------------
# Scale model timestep according to vertical resolution.
#
# CONFIG_DT values above are defined for the reference
# configuration with 55 vertical levels. For finer vertical
# grids, reduce the timestep proportionally.
#
# The final CONFIG_DT is chosen so that CONFIG_CONV_INTERVAL
# is an integer multiple of CONFIG_DT.
#-------------------------------------------------------

NLEV_REF=55
CONFIG_DT_REF=${CONFIG_DT}

if (( N_MODEL_LEV > NLEV_REF )); then

    # Timestep suggested by linear vertical-resolution scaling
    CONFIG_DT_TARGET=$(awk -v dt="${CONFIG_DT_REF}" \
                           -v nref="${NLEV_REF}" \
                           -v nlev="${N_MODEL_LEV}" \
                           'BEGIN {printf "%.6f", dt*nref/nlev}')

    # Convert convection interval HH:MM:SS -> seconds
    IFS=: read -r conv_h conv_m conv_s <<< "${CONFIG_CONV_INTERVAL}"
    CONFIG_CONV_INTERVAL_SEC=$((10#$conv_h*3600 + 10#$conv_m*60 + 10#$conv_s))

    # Use the largest integer timestep <= target that exactly divides
    # the convection interval.
    CONFIG_DT_INT=$(awk -v x="${CONFIG_DT_TARGET}" 'BEGIN {print int(x)}')

    (( CONFIG_DT_INT < 1 )) && CONFIG_DT_INT=1

    while (( CONFIG_DT_INT > 1 )); do
        if (( CONFIG_CONV_INTERVAL_SEC % CONFIG_DT_INT == 0 )); then
            break
        fi
        ((CONFIG_DT_INT--))
    done

    CONFIG_DT="${CONFIG_DT_INT}.0"
fi

echo "Vertical timestep scaling:"
echo "  N_MODEL_LEV             = ${N_MODEL_LEV}"
echo "  reference levels        = ${NLEV_REF}"
echo "  reference CONFIG_DT     = ${CONFIG_DT_REF} s"
echo "  final CONFIG_DT         = ${CONFIG_DT} s"
echo "  CONFIG_CONV_INTERVAL    = ${CONFIG_CONV_INTERVAL}"
#-------------------------------------------------------

# Setting configuration to apply or not lateral boundary conditions and output filename
if [[ $MODERUN == "R" ]]; then
   APPLY_LBCS=true
   RORG=R
elif [[ $MODERUN == "G" ]]; then
   APPLY_LBCS=false
   RORG=G
else
   echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"
   echo -e  "${RED}==>${NC} Atmosphere phase fails! Please select MODERUN=R (Regional) or MODERUN=G (Global) in 'setenv.bash' so that MONAN knows whether to read or not lateral boundary conditions.\n"
   echo -e  "${RED}==>${NC} Exiting script. \n"
   exit -1
fi
#-------------------------------------------------------

# Calculating final forecast dates in model namelist format: DD_HH:MM:SS 
# using: start_date(yyyymmdd) + FCST(hh) :
printf -v DD_HHMMSS_forecast '%02d_%02d:00:00' \
    "$((FCST / 24))" "$((FCST % 24))"

if [ ! -s ${DATAIN}/fixed/x1.${RES}.graph.info.part.${cores} ]
then
   if [ ! -s ${DATAIN}/fixed/x1.${RES}.graph.info ]
   then
      cd ${DATAIN}/fixed
      echo -e "${GREEN}==>${NC} downloading meshes tgz files ... \n"
      wget https://www2.mmm.ucar.edu/projects/mpas/atmosphere_meshes/x1.${RES}.tar.gz
      tar -xzvf x1.${RES}.tar.gz
   fi
   echo -e "${GREEN}==>${NC} Creating x1.${RES}.graph.info.part.${cores} ... \n"
   cd ${DATAIN}/fixed
   gpmetis -minconn -contig -niter=200 x1.${RES}.graph.info ${cores}
   rm -fr x1.${RES}.tar.gz
fi

# Check that the selected templates support restart configuration
if ! grep -q '#DO_RESTART#' \
    "${SCRIPTS}/namelists/namelist.atmosphere${VARTABLE}"; then

    echo "ERROR: Missing #DO_RESTART# in namelist template." >&2
    exit 1
fi

for placeholder in \
    '#DIAG_INTERVAL#' \
    '#HIST_INTERVAL#' \
    '#RESTART_INTERVAL#'; do

    if ! grep -q "${placeholder}" \
        "${SCRIPTS}/namelists/streams.atmosphere${VARTABLE}"; then

        echo "ERROR: Missing ${placeholder} in streams template." >&2
        exit 1
    fi

done

files_needed=("${SCRIPTS}/namelists/stream_list.atmosphere.output${VARTABLE}" "${SCRIPTS}/namelists/stream_list.atmosphere.diagnostics${VARTABLE}" "${SCRIPTS}/namelists/stream_list.atmosphere.surface" "${SCRIPTS}/namelists/GF_ConvPar_nml${VARTABLE}" "${EXECS}/atmosphere_model" "${DATAIN}/fixed/x1.${RES}.static.nc" "${DATAIN}/fixed/x1.${RES}.ugwp_oro_data.nc" "${DATAIN}/fixed/x1.${RES}.graph.info.part.${cores}" "${DATAIN}/fixed/Vtable.${EXP}" "${DATAIN}/fixed/ugwp_limb_tau.nc")

if [[ "${INIT_MODE}" == "COLD" ]]; then

    files_needed+=(
        "${DATAOUT}/${RUN_ID}/Pre/x1.${RES}.init.nc"
    )

else

    restart_stamp="${start_date//:/.}"
    restart_file="restart.${restart_stamp}.nc"

    restart_source="${DATAOUT}/${RUN_ID}/Model/${restart_file}"

    files_needed+=("${restart_source}")

fi

for file in "${files_needed[@]}"
do
  if [ ! -s "${file}" ]
  then
    echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"   
    echo -e  "${RED}==>${NC} [${0}] At least the file ${file} was not generated. \n"
    exit -1
  fi
done

cp -f ${EXECS}/atmosphere_model ${DIRRUN}
cp -f ${DATAIN}/fixed/*TBL ${DIRRUN}
cp -f ${DATAIN}/fixed/*DBL ${DIRRUN}
cp -f ${DATAIN}/fixed/*DATA ${DIRRUN}
cp -f ${DATAIN}/fixed/x1.${RES}.static.nc ${DIRRUN}
cp -f ${DATAIN}/fixed/x1.${RES}.ugwp_oro_data.nc ${DIRRUN}
cp -f ${DATAIN}/fixed/x1.${RES}.graph.info.part.${cores} ${DIRRUN}
cp -f ${DATAIN}/fixed/Vtable.${EXP} ${DIRRUN}
cp -f ${DATAIN}/fixed/ugwp_limb_tau.nc ${DIRRUN}

if [[ "${INIT_MODE}" == "COLD" ]]; then

    cp -f "${DATAOUT}/${RUN_ID}/Pre/x1.${RES}.init.nc" \
        "${DIRRUN}/" || exit 1

else

    echo "Restarting MONAN from: ${restart_source}"

    cp -f "${restart_source}" "${DIRRUN}/" || exit 1

fi

if [[ "${MODERUN}" == "R" ]]; then

    LBC_SOURCE="${DATAOUT}/${RUN_ID}/Pre"
    lbc_files=("${LBC_SOURCE}"/lbc.*.nc)

    if [[ ! -s "${lbc_files[0]}" ]]; then
        echo "ERROR: No LBC files in ${LBC_SOURCE}" >&2
        exit 1
    fi

    first_lbc="${lbc_files[0]##*/}"
    first_lbc="${first_lbc#lbc.}"
    first_lbc="${first_lbc%.nc}"

    last_lbc="${lbc_files[${#lbc_files[@]}-1]##*/}"
    last_lbc="${last_lbc#lbc.}"
    last_lbc="${last_lbc%.nc}"

    start_lbc="${start_date//:/.}"

    segment_epoch=$(
        date -u -d "${start_date:0:10} ${start_date:11:8}" +%s
    ) || exit 1

    end_lbc=$(
        date -u -d "@$((segment_epoch + FCST*3600))" \
            '+%Y-%m-%d_%H.%M.%S'
    ) || exit 1

    if [[ "${first_lbc}" > "${start_lbc}" ||
          "${last_lbc}" < "${end_lbc}" ]]; then

        echo "ERROR: LBC files do not cover the simulation." >&2
        echo "Available: ${first_lbc} to ${last_lbc}" >&2
        echo "Required:  ${start_lbc} to ${end_lbc}" >&2
        exit 1
    fi

    cp -f "${lbc_files[@]}" "${DIRRUN}/" || exit 1

fi

if [[ ${EXP} == "GFS" ||  ${EXP} == "ERA" ]]
then
   sed -e "s,#LABELI#,${start_date},g;
   s,#FCSTS#,${DD_HHMMSS_forecast},g;
   s,#RES#,${RES},g;
   s,#CONFIG_DT#,${CONFIG_DT},g;
   s,#CONFIG_LEN_DISP#,${CONFIG_LEN_DISP},g;
   s,#CONFIG_CONV_INTERVAL#,${CONFIG_CONV_INTERVAL},g;
   s,#APPLY_LBCS#,${APPLY_LBCS},g;
   s,#DO_RESTART#,${DO_RESTART},g" \
   "${SCRIPTS}/namelists/namelist.atmosphere${VARTABLE}" \
   > "${DIRRUN}/namelist.atmosphere"

   sed -e "s,#RES#,${RES},g;
   s,#RORG#,${RORG},g;
   s,#LBCINT#,${LBCINT},g;
   s,#CIORIG#,${EXP},g;
   s,#LABELI#,${YYYYMMDDHHi},g;
   s,#N_MODEL_LEV#,${N_MODEL_LEV},g;
   s,#DIAG_INTERVAL#,${DIAG_INTERVAL},g;
   s,#HIST_INTERVAL#,${HIST_INTERVAL},g;
   s,#RESTART_INTERVAL#,${RESTART_INTERVAL},g" \
   "${SCRIPTS}/namelists/streams.atmosphere${VARTABLE}" \
   > "${DIRRUN}/streams.atmosphere"
fi
cp -f ${SCRIPTS}/namelists/stream_list.atmosphere.output${VARTABLE} ${DIRRUN}/stream_list.atmosphere.output
cp -f ${SCRIPTS}/namelists/stream_list.atmosphere.diagnostics${VARTABLE} ${DIRRUN}/stream_list.atmosphere.diagnostics
cp -f ${SCRIPTS}/namelists/stream_list.atmosphere.diag_ugwp${VARTABLE} ${DIRRUN}/stream_list.atmosphere.diag_ugwp
cp -f ${SCRIPTS}/namelists/stream_list.atmosphere.surface ${DIRRUN}
cp -f ${SCRIPTS}/namelists/GF_ConvPar_nml${VARTABLE} ${DIRRUN}/GF_ConvPar_nml


chmod 755 ${DIRRUN}

rm -f ${DIRRUN}/model.bash 

if [ ${SCHEDULER_SYSTEM} != "GENERIC" ]
then
   sed -e "s,#JOBNAME#,${MODEL_jobname},g;
   s,#NNODES#,${MODEL_nnodes},g;
   s,#NCPUS#,${MODEL_ncpus},g;
   s,#NTASKS#,${MODEL_ncores},g;
   s,#NTASKSPNODE#,${MODEL_ncpn},g;
   s,#NTHREADS#,${MODEL_nthreads},g;
   s,#PARTITION#,${MODEL_QUEUE},g;
   s,#WALLTIME#,${MODEL_walltime},g;
   s,#OUTPUTJOB#,${LOG_DIR}/model.bash.o,g;
   s,#ERRORJOB#,${LOG_DIR}/model.bash.e,g" \
   ${SCRIPTS}/stools/submit_${SYSTEM_KEY}.bash_TEMPLATE > ${DIRRUN}/model.bash 
else
   echo "#!/bin/bash " > ${DIRRUN}/model.bash 
fi

cat << EOF0 >> ${DIRRUN}/model.bash 

export executable=atmosphere_model

ulimit -c unlimited
ulimit -v unlimited
ulimit -s unlimited

cd ${DIRRUN}
. ${SCRIPTS}/setenv.bash

date
beg_secs=\`date +"%s"\`

if [ ${SCHEDULER_SYSTEM} == "SLURM" ]; then
   echo "-- SLURM_JOB_ID: \$SLURM_JOB_ID"
   time mpirun -np ${MODEL_ncores} ./\${executable}
elif [ ${SCHEDULER_SYSTEM} == "PBS" ]; then
   echo "-- PBS_JOBID: \$PBS_JOBID"
   time mpirun --ppn ${MODEL_ncpn} -np ${MODEL_ncores} --depth=${MODEL_nthreads} --cpu-bind depth ./\${executable}
fi

model_exit=\$?

if [ "\$model_exit" -ne 0 ]; then
    echo "ERROR: MONAN exited with status \$model_exit" >&2
    exit "\$model_exit"
fi

date
end_secs=\`date +"%s"\`

let wallsecs=\$end_secs-\$beg_secs
echo "MONAN time taken by run in seconds is " \$wallsecs

#
# move dataout, clean up and remove files/links
#
for file in MONAN_DIAG_* MONAN_HIST_*; do
    [ -f "\$file" ] || continue
    mv -f "\$file" "${DATAOUT}/${RUN_ID}/Model/" || exit 1
done

for file in restart.*.nc; do

    [ -f "\$file" ] || continue

    destination="${DATAOUT}/${RUN_ID}/Model/\$file"

    if [ "${INIT_MODE}" = "RESTART" ]; then

        # Preserve the checkpoint used to start this segment.
        if [ "\$file" = "${restart_file}" ]; then
            rm -f "\$file" || exit 1
            continue
        fi

        # Do not replace checkpoints preceding the restart time.
        if [[ "\$file" < "${restart_file}" ]]; then
            echo "ERROR: Unexpected older restart file: \$file" >&2
            exit 1
        fi

    elif [ -e "\$destination" ]; then

        echo "ERROR: Existing checkpoint during cold start: \$destination" >&2
        exit 1

    fi

    # New checkpoints after the restart time replace older versions.
    mv -f "\$file" "\$destination" || exit 1

done

if [ -f restart_timestamp ]; then
    mv restart_timestamp ${DATAOUT}/${RUN_ID}/Model/ || exit 1
fi

cp -f ${EXECS}/MONAN-VERSION.txt ${DATAOUT}/${RUN_ID}/Model
cp -f ${EXECS}/MONAN-VERSION.txt ${LOG_DIR}/
cp -f ${DIRHOMES}/VERSION.txt ${LOG_DIR}/SCRIPTSCDCT-VERSION.txt
cp -f ${MONANDIR}/README.md ${LOG_DIR}/

mv log.atmosphere.* ${LOG_DIR}/
mv namelist.atmosphere ${LOG_DIR}/
mv stream* ${LOG_DIR}/
mv GF_ConvPar_nml ${LOG_DIR}/
EOF0
chmod a+x ${DIRRUN}/model.bash


case "${SCHEDULER_SYSTEM}" in
   SLURM)
      echo -e  "${GREEN}==>${NC} Submitting MONAN atmosphere model and waiting for finish before exit... \n"
      echo -e  "${GREEN}==>${NC} Logs being generated at ${DATAOUT}/logs... \n"
      echo -e  "sbatch ${SCRIPTS}/model.bash"
      cd ${DIRRUN}
      sbatch --wait "${DIRRUN}/model.bash"
      job_status=$?
      ;;
    PBS)
      echo -e  "${GREEN}==>${NC} Submitting MONAN atmosphere model and waiting for finish before exit... \n"
      echo -e  "${GREEN}==>${NC} Logs being generated at ${DATAOUT}/logs... \n"
      echo -e  "${GREEN}==>${NC} qsub model.bash...\n"
      cd ${DIRRUN}
      qsub -W block=true "${DIRRUN}/model.bash"
      job_status=$?
      ;;
#    GENERIC)
#      echo "Nenhum gerenciador detectado"
#      cd ${DIRRUN}
#      ${DIRRUN}/model.bash
#      ;;
esac
if (( job_status != 0 )); then
    echo "ERROR: Model job failed (${job_status})." >&2
    echo "Preserving ${DIRRUN}" >&2
    exit "${job_status}"
fi
mv "${DIRRUN}/model.bash" "${LOG_DIR}/" || exit 1

if [ ${SCHEDULER_SYSTEM} = "SLURM" ]; then
   : # Slurm já gera JOBID na submissão.
elif [ ${SCHEDULER_SYSTEM} = "PBS" ]; then
   JOBID=$(sed -n '5p' ${LOG_DIR}/model.bash.o | awk '{print $3}' | sed "s/.pbs-ha//g")
   mv ${LOG_DIR}/model.bash.o ${LOG_DIR}/model.bash.o.${JOBID}
   mv ${LOG_DIR}/model.bash.e ${LOG_DIR}/model.bash.e.${JOBID}
fi
chmod a+r ${LOG_DIR}/model.bash.o.*
chmod a+r ${LOG_DIR}/model.bash.e.*

# Verify DIAG outputs for this segment
start_epoch=$(
    date -u -d "${start_date:0:10} ${start_date:11:8}" +%s
) || exit 1

forecast_sec=$((FCST * 3600))

if [[ "${INIT_MODE}" == "RESTART" ]]; then
    first_offset=${DIAG_INTERVAL_SEC}
else
    first_offset=0
fi

for (( offset=first_offset; offset<=forecast_sec; offset+=DIAG_INTERVAL_SEC )); do

    currentdate=$(
        date -u -d "@$((start_epoch + offset))" +"%Y%m%d%H.%M.%S"
    )

    file="MONAN_DIAG_${RORG}_MOD_${EXP}_${YYYYMMDDHHi}_${currentdate}.x${RES}L${N_MODEL_LEV}.nc"

    if [[ ! -s "${DATAOUT}/${RUN_ID}/Model/${file}" ]]; then
        echo "ERROR: Missing diagnostic output: ${file}" >&2
        echo "Preserving ${DIRRUN}" >&2
        exit 1
    fi

done

# Remove only the staged input checkpoint, after confirming
# the original still exists.
if [[ "${INIT_MODE}" == "RESTART" &&
      -f "${DIRRUN}/${restart_file}" ]]; then

    if [[ ! -s "${restart_source}" ]]; then
        echo "ERROR: Original restart checkpoint is missing." >&2
        exit 1
    fi

    rm -f "${DIRRUN}/${restart_file}" || exit 1
fi

# Preserve DIRRUN if any output files remain
for file in \
    "${DIRRUN}"/restart.*.nc \
    "${DIRRUN}"/MONAN_DIAG_* \
    "${DIRRUN}"/MONAN_HIST_*; do

    if [[ -f "${file}" ]]; then
        echo "ERROR: Untransferred file: ${file}" >&2
        echo "Preserving ${DIRRUN}" >&2
        exit 1
    fi

done

rm -fr "${DIRRUN}"
