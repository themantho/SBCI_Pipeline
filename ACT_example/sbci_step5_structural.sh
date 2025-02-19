#!/bin/bash

echo "Sourcing SBCI config file"
source ${SBCI_CONFIG}

OUTPUTDIR=dwi_pipeline/sbci_connectome
SETDIR=dwi_pipeline/set

if [ -z ${SCRIPT_PATH+x} ]; then 
    SCRIPT_PATH=${SBCI_PATH}/scripts
fi
if [ -z ${CONCON_PATH+x} ]; then 
    CONCON_PATH=${SBCI_PATH}/concon
fi

echo "Begin processing SBCI structural: $(date)"

##############################
#    CONCATENATE SET DATA    #
##############################
INTERSECTIONS=""

# Step1) Collect all intersecstions runs
for ((RUN = 1; RUN <= N_RUNS; RUN++)); do
  INTERSECTIONS="$INTERSECTIONS ${SETDIR}/streamline/intersections_random_loop${RUN}_filtered.npz"
done

# Step2) Do the concatenation
scil_concatenate_surfaces_intersections.py ${INTERSECTIONS} \
        --output_intersections ${SETDIR}/streamline/set_filtered_intersections.npz -f

################################################################
##            GROUP SPACE STRUCTURAL CONNECTIVITY             ## 
################################################################

# Step1) Snap fiber endpoints generated by SET to the nearest vertices on the full resolution mesh
python ${SCRIPT_PATH}/snap_fibers.py \
       --surfaces ${SETDIR}/out_surf/surfaces.vtk \
       --surface_map ${SETDIR}/preprocess/surfaces_id.npy \
       --intersections ${SETDIR}/streamline/set_filtered_intersections.npz \
       --output ${OUTPUTDIR}/snapped_fibers.npz -f

# Step2) Calculate smooth SC matrix
python ${SCRIPT_PATH}/concon/intersections_to_sphere.py \
       --lh_surface ${OUTPUTDIR}/lh_sphere_reg_lps.vtk \
       --rh_surface ${OUTPUTDIR}/rh_sphere_reg_lps.vtk \
       --intersections ${OUTPUTDIR}/snapped_fibers.npz \
       --output ${OUTPUTDIR}/subject_xing_sphere_avg_coords.tsv -f

# run concon to get the smooth SC matrix
${CONCON_PATH}/c3_main \
  Compute_Kernel \
  --subj subject \
  --sigma ${BANDWIDTH} \
  --epsilon 0.001 \
  --final_thold 0.000000001 \
  --OPT_VAL_exp_num_kern_samps 6 \
  --OPT_VAL_exp_num_harm_samps 5 \
  --OPT_VAL_num_harm 33 \
  --LOAD_xing_path "${OUTPUTDIR}/" \
  --LOAD_xing_postfix "_xing_sphere_avg_coords.tsv" \
  --LOAD_kernel_path "" \
  --LOAD_kernel_postfix "" \
  --LOAD_mask_file MASK \
  --SAVE_Compute_Kernel_prefix "${OUTPUTDIR}/" \
  --SAVE_Compute_Kernel_postfix "_avg_${BANDWIDTH}_${RESOLUTION}.raw" \
  --LOAD_grid_file "${OUTPUT_PATH}/lh_grid_avg_${RESOLUTION}.m" \
  --LOAD_rh_grid_file "${OUTPUT_PATH}/rh_grid_avg_${RESOLUTION}.m" 

# convert the binary output of concon into something we can use
python ${SCRIPT_PATH}/concon/convert_raw.py \
       --input ${OUTPUTDIR}/subject_avg_${BANDWIDTH}_${RESOLUTION}.raw \
       --intersections ${OUTPUTDIR}/snapped_fibers.npz \
       --mesh ${OUTPUT_PATH}/mapping_avg_${RESOLUTION}.npz \
       --output ${OUTPUTDIR}/smoothed_sc_avg_${BANDWIDTH}_${RESOLUTION} -f

# Step3) Calculate subcortical SC matrices
python ${SCRIPT_PATH}/calculate_subcortical_sc.py \
       --intersections ${OUTPUTDIR}/snapped_fibers.npz \
       --grid ${OUTPUT_PATH}/grid_coords_${RESOLUTION}.npz \
       --coordinates ${OUTPUTDIR}/subject_coords.npz \
       --bandwidth ${BANDWIDTH} \
       --output ${OUTPUTDIR}/sub_sc_avg_${BANDWIDTH}_${RESOLUTION}.mat -f

echo "Finished processing SBCI structural: $(date)"
