#!/bin/bash
umask 022

# Choose the simulation mode:
export MODERUN=G     # R=Regional simulation and G=Global simulation.
export LBCINT=10800  # Interval (seconds) for updating lateral boundary conditions (when regional mode).

# Choose your compiler here (only on Jaci; on Egeon the compiler is fixed to ‘gnu’):
export COMPILER=intel
#export COMPILER=gnu
#export COMPILER=cray
#export COMPILER=nvidia

# Squeduler detect:
if command -v sbatch &> /dev/null
then
   export SCHEDULER_SYSTEM="SLURM"
   echo "SLURM detected." 
elif command -v qsub &> /dev/null
then
   export SCHEDULER_SYSTEM="PBS"
   echo "PBS detected."
else
   export SCHEDULER_SYSTEM="GENERIC"
   echo "No SCHEDULER detected."
fi

# Detect hostname
THOSTNAME=$(hostname -s)

# Identifying several names of the egeon:
case ${THOSTNAME} in
   egeon-login|headnode|n[0-9]|n[1-2][0-9]|n3[0-3])
      export HOSTNAME="egeon"
      export MAKE_TARG=gfortran
      export MAKE_TARG2=gfortran
      COMPILER=gnu
      ;;
   ian[0-9]*|cn-0[0-9][0-9][0-9])
      export HOSTNAME="ian"
      if [ "$COMPILER" == "intel" ]; then
         export MAKE_TARG=intel-xd2000
         export MAKE_TARG2=intel2-xd2000
      elif [ "$COMPILER" == "gnu" ]; then
         export MAKE_TARG=gfortran-xd2000
         export MAKE_TARG2=gfortran-xd2000
      elif [ "$COMPILER" == "cray" ]; then
         export MAKE_TARG=cray-xd2000
         export MAKE_TARG2=cray-xd2000
      elif [ "$COMPILER" == "nvidia" ]; then
         export MAKE_TARG=nvhpc-xd2000
         export MAKE_TARG2=nvhpc-xd2000
      fi
      ;;
esac
# Make the same for other machines/systems...
echo "Host detected: $HOSTNAME"
echo "Compiler to be used: ${COMPILER}"

# Set unique key: scheduler + host:
export SYSTEM_KEY="${SCHEDULER_SYSTEM}_${HOSTNAME}"
export SYSTEM_KEYC="${SCHEDULER_SYSTEM}_${HOSTNAME}_${COMPILER}"


# Set environment variables and importants directories-------------------------------------------------- 


# MONAN-suite install root directories:
# Put your directories:
export DIR_SCRIPTS=$(dirname $(dirname $(pwd)))
export DIR_DADOS=${DIR_SCRIPTS}
export DIR_SUITE=scripts_CD-CT-regional
export MONANDIR=${DIR_SCRIPTS}/${DIR_SUITE}/sources/MONAN-Model

# Optional local override (modify MONANDIR in setenv.local.bash to use a different MONAN repo version)
LOCAL_SETENV="${DIR_SCRIPTS}/${DIR_SUITE}/scripts/setenv.local.bash"

if [ -f "${LOCAL_SETENV}" ]; then
    echo "Loading local environment configuration: ${LOCAL_SETENV}"
    . "${LOCAL_SETENV}"
else
    echo "No local environment configuration found; using default settings."
fi

echo "MONANDIR=${MONANDIR}"

# Load your system setenv:
. ${DIR_SCRIPTS}/${DIR_SUITE}/scripts/stools/setenv_${SYSTEM_KEYC}.bash

#module list
#echo ""
#read -p "Mostrando modulos carregados - Pressione Enter para continuar.... "
#echo ""


#-----------------------------------------------------------------------
# We discourage changing the variables below:

# Others variables:


# Colors:
#
export GREEN='\033[1;32m'  # Green
export RED='\033[1;31m'    # Red
export NC='\033[0m'        # No Color
export BLUE='\033[01;34m'  # Blue


# Functions: ======================================================================================================

how_many_nodes () { 
   nume=${1}   
   deno=${2}
   num=$(echo "${nume}/${deno}" | bc -l)  
   how_many_nodes_int=$(echo "${num}/1" | bc)
   dif=$(echo "scale=0; (${num}-${how_many_nodes_int})*100/1" | bc)
   rest=$(echo "scale=0; (((${num}-${how_many_nodes_int})*${deno})+0.5)/1" | bc -l)
   if [ ${dif} -eq 0 ]; then how_many_nodes_left=0; else how_many_nodes_left=1; fi
   if [ ${how_many_nodes_int} -eq 0 ]; then how_many_nodes_int=1; how_many_nodes_left=0; rest=0; fi
   how_many_nodes=$(echo "${how_many_nodes_int}+${how_many_nodes_left}" | bc )
   #echo "INT number of nodes needed: \${how_many_nodes_int}  = ${how_many_nodes_int}"
   #echo "number of nodes left:       \${how_many_nodes_left} = ${how_many_nodes_left}"
   echo "The number of nodes needed: \${how_many_nodes}  = ${how_many_nodes}"
   echo ""
}
#----------------------------------------------------------------------------------------------


