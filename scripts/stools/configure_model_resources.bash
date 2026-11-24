#!/bin/bash
#
# Sourced by 0.run_all.bash AFTER run_config.local.bash.
# Configures MODEL resources for PBS / ian.
#
# Pure MPI: one requested CPU per MPI process, one thread per process.
# PRE/POST resources are unaffected.
#
# Automatic selection uses configured limits, not live queue congestion.

configure_model_resources() {
    # Preserve other systems' existing resource settings.
    [[ "${SYSTEM_KEY:-}" == "PBS_ian" ]] || return 0

    local resource_name
    local wall_seconds requested_cpus
    local queue_name max_seconds max_nodes max_cpus
    local selected_queue=""

    # Require explicit local choices.
    for resource_name in \
        MODEL_NODES \
        MODEL_MPI_PER_NODE \
        MODEL_REQUESTED_WALLTIME \
        MODEL_QUEUE_MODE
    do
        if [[ -z "${!resource_name:-}" ]]; then
            echo "ERROR: Set $resource_name in run_config.local.bash." >&2
            return 1
        fi
    done

    # Validate node count and MPI processes per node.
    for resource_name in MODEL_NODES MODEL_MPI_PER_NODE; do
        if [[ ! "${!resource_name}" =~ ^[1-9][0-9]*$ ]]; then
            echo "ERROR: $resource_name must be a positive integer." >&2
            return 1
        fi
    done

    # Accept one to three hour digits and two-digit minutes/seconds.
    if [[ "$MODEL_REQUESTED_WALLTIME" =~ ^([0-9]{1,3}):([0-5][0-9]):([0-5][0-9])$ ]]; then
        wall_seconds=$((10#${BASH_REMATCH[1]} * 3600 +
                        10#${BASH_REMATCH[2]} * 60 +
                        10#${BASH_REMATCH[3]}))
    else
        echo "ERROR: MODEL_REQUESTED_WALLTIME must use HH:MM:SS or HHH:MM:SS." >&2
        return 1
    fi

    if (( wall_seconds <= 0 )); then
        echo "ERROR: MODEL_REQUESTED_WALLTIME must be positive." >&2
        return 1
    fi

    requested_cpus=$((MODEL_NODES * MODEL_MPI_PER_NODE))

    case "$MODEL_QUEUE_MODE" in
        auto)
            # First compatible queue in this preference order.
            #
            # Limits based on the supplied qstat output:
            # queue     seconds  nodes  CPUs
            #
            # CPUs=0 means no queue-level CPU limit was shown.
            # Server/user limits and physical node capacity still apply.
            # For pesqmini, conservatively enforce its listed nodes=7.
            while read -r queue_name max_seconds max_nodes max_cpus; do
                if (( wall_seconds <= max_seconds &&
                      MODEL_NODES <= max_nodes &&
                      (max_cpus == 0 || requested_cpus <= max_cpus) )); then
                    selected_queue="$queue_name"
                    break
                fi
            done <<'QUEUES'
pesqmini 1800    7 1792
pesqmidi 7200    7 0
pesqhigh 21600  20 0
pesqextra 28800 30 0
longtime 604800  8 0
QUEUES

            if [[ -z "$selected_queue" ]]; then
                echo "ERROR: No configured research queue fits this request." >&2
                echo "  Nodes:    $MODEL_NODES" >&2
                echo "  CPUs:     $requested_cpus" >&2
                echo "  Walltime: $MODEL_REQUESTED_WALLTIME" >&2
                return 1
            fi
            ;;

        manual)
            if [[ -z "${MODEL_MANUAL_QUEUE:-}" ]]; then
                echo "ERROR: Set MODEL_MANUAL_QUEUE for manual selection." >&2
                return 1
            fi

            # PBS validates the manually selected queue and its limits.
            selected_queue="$MODEL_MANUAL_QUEUE"
            ;;

        *)
            echo "ERROR: MODEL_QUEUE_MODE must be auto or manual." >&2
            return 1
            ;;
    esac

    # Override the defaults previously loaded by setenv.
    # These are the variables consumed by 3.run_model.bash.
    export MODEL_nnodes="$MODEL_NODES"
    export MODEL_ncpn="$MODEL_MPI_PER_NODE"
    export MODEL_ncpus="$MODEL_MPI_PER_NODE"
    export MODEL_nthreads=1
    export MODEL_ncores="$requested_cpus"
    export MODEL_walltime="$MODEL_REQUESTED_WALLTIME"
    export MODEL_QUEUE="$selected_queue"

    printf '\nMODEL PBS configuration:\n'
    printf '  Queue selection: %s\n' "$MODEL_QUEUE_MODE"
    printf '  Queue:           %s\n' "$MODEL_QUEUE"
    printf '  Nodes:           %s\n' "$MODEL_nnodes"
    printf '  Total MPI ranks: %s\n' "$MODEL_ncores"
    printf '  MPI ranks/node:  %s\n' "$MODEL_ncpn"
    printf '  CPUs/node:       %s\n' "$MODEL_ncpus"
    printf '  Threads/rank:    %s\n' "$MODEL_nthreads"
    printf '  Walltime:        %s\n\n' "$MODEL_walltime"

    return 0
}
