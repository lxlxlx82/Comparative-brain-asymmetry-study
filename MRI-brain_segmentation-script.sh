#!/bin/bash

export FREESURFER_HOME=/Applications/freesurfer
source $FREESURFER_HOME/SetUpFreeSurfer.sh

# Inputs
# $1 - the directory where the FreeSurfer subjects are to be saved, such as /Users/s0789354/Dropbox/Language_Dominance/FS_results/
# $2 - the stage of the procedure
# $3 - the directory where original brain files, such as nifti, DICOMs are saved


export SUBJECTS_DIR=$1
INPUT_DIR = $3
cd $INPUT_DIR
option=$2

while read line
do
    FILENAME=$(echo $line | cut -d' ' -f1)
    NAME=${FILENAME%.*}
    echo $NAME

    #### STEP 1
    # (1)   build FS archieve from the original MRI brain scan
    case $option in
    "stage1")
    recon-all -i $FILENAME -s $NAME -no-isrunning
    cp $FILENAME $SUBJECTS_DIR/$NAME

    # (2)   perform FSL skull stripping (check the segmented brain results)
    bet $SUBJECTS_DIR/$NAME/$FILENAME $SUBJECTS_DIR/$NAME/"skullstrip" -R -f 0.2
    ;;
    
    #### STEP 2
    "stage2")
    # (1)   perform FSL strength field bias correction
    fast -B -b -o $SUBJECTS_DIR/$NAME/"bcorr" $SUBJECTS_DIR/$NAME/"skullstrip"
    rm -r $SUBJECTS_DIR/$NAME/*"pve"* $SUBJECTS_DIR/$NAME/*"bias"* $SUBJECTS_DIR/$NAME/*"mixel"*

    # (2)   perform FSL brain normalization (to MNI152) (check whether the normalization is successful)
    # firstly, coase registration
    flirt -in $SUBJECTS_DIR/$NAME/"skullstrip" -ref /usr/local/fsl/data/standard/MNI152_T1_1mm_brain_mask.nii.gz -dof 7 -searchrx -180 180 -searchry -180 180 -searchrz -180 180 -cost corratio -omat $SUBJECTS_DIR/$NAME/"flirt_transform_init.mat" -out $SUBJECTS_DIR/$NAME/"brain_flirt_7DOF"
    # secondly, fine registration based on the inital transformation matrix obtained in (1)
    flirt -in $SUBJECTS_DIR/$NAME/skullstrip.nii.gz -ref /usr/local/fsl/data/standard/MNI152_T1_1mm_brain.nii.gz -dof 7 -cost corratio -omat $SUBJECTS_DIR/$NAME/"flirt_transform.mat" -out $SUBJECTS_DIR/$NAME/"brain_flirt_7DOF" -init $SUBJECTS_DIR/$NAME/"flirt_transform_init.mat"
    # save the transformation matrix to file for later
    avscale $SUBJECTS_DIR/$NAME/"flirt_transform.mat" >> $SUBJECTS_DIR/$NAME/"transform_decomposition.txt"
    #  apply the transformation to the input brain scan and check whether the normalization is successful
    flirt -in $SUBJECTS_DIR/$NAME/$NAME.nii -ref /usr/local/fsl/data/standard/MNI152_T1_1mm_brain.nii.gz -dof 7 -applyxfm -init $SUBJECTS_DIR/$NAME/"flirt_transform.mat" -out $SUBJECTS_DIR/$NAME/$NAME"_trans.nii" -noresample
    ;;
    
    #### STEP 3 - FreeSurfer pipeline
    "stage3")
    # (1)   prepare for FreeSurfer processing by converting the file format to mgz
    mri_convert $SUBJECTS_DIR/$NAME/"brain_flirt_7DOF.nii.gz" $SUBJECTS_DIR/$NAME/mri/orig/001.mgz
    # (2)   perform FreeSurfer segmentation - autorecon1
    recon-all -autorecon1 -s $NAME -hires -no-isrunning
    # (3)   perform FreeSurfer segmentation - autorecon2
    cd $SUBJECTS_DIR/$NAME/mri
    mri_em_register -uns 3 -mask brainmask.mgz nu.mgz /Users/s0789354/Dropbox/1.5T_chimpanzee/segmentstion_code/CHIMP_all_2019-03-28.gca transforms/talairach.lta
    mri_ca_normalize -c ctrl_pts.mgz -mask brainmask.mgz nu.mgz /Users/s0789354/Dropbox/1.5T_chimpanzee/segmentstion_code/CHIMP_all_2019-03-28.gca transforms/talairach.lta norm.mgz
    mri_ca_register -align-after -nobigventricles -mask brainmask.mgz -T transforms/talairach.lta norm.mgz /Users/s0789354/Dropbox/1.5T_chimpanzee/segmentstion_code/CHIMP_all_2019-03-28.gca transforms/talairach.m3z
    mri_ca_label -relabel_unlikely 9 .3 -prior 0.5 -align norm.mgz transforms/talairach.m3z /Users/s0789354/Dropbox/1.5T_chimpanzee/segmentstion_code/CHIMP_all_2019-03-28.gca aseg.auto_noCCseg.mgz
    mri_cc -force -lta transforms/cc_up.lta -aseg aseg.auto_noCCseg.mgz -o aseg.auto.mgz $NAME
    cp aseg.auto_noCCseg.mgz aseg.auto.mgz
    cp aseg.auto_noCCseg.mgz aseg.presurf.mgz
    recon-all -normalization2 -maskbfs -segmentation -s $NAME -no-isrunning
    
    recon-all -autorecon2-wm -s $NAME -no-isrunning
    # (4)   perform FreeSurfer segmentation - autorecon3
    recon-all -autorecon3 -s $NAME -no-isrunning
    ;;
    
    #### STEP 4 - Find inter-hemispherical correspondence - FreeSurfer
    "stage4")
    # (1)   based on the lh.fsaverage_sym
    if [ -f $BASEDIR/$name/xhemi/surf/lh.fsaverage_sym.sphere.reg ];
    then
        echo #$name #$BASEDIR/$name/surf/lh.fsaverage_sym.sphere.reg
    else
        xhemireg --s $NAME
        surfreg --s $NAME --t fsaverage_sym --lh
        surfreg --s $NAME --t fsaverage_sym --xhemi --lh
    fi
    
    # (2)   based on the rh.fsaverage_sym
    if [ -f $BASEDIR/$name/xhemi/surf/rh.fsaverage_sym.sphere.reg ];
    then
        echo #$name #$BASEDIR/$name/surf/rh.fsaverage_sym.sphere.reg
    else
        #xhemireg --s $NAME
        surfreg --s $NAME --t fsaverage_sym --rh
        surfreg --s $NAME --t fsaverage_sym --xhemi --rh
    fi
    ;;
    
    #### STEP 5 - Generate brain binary volume data from the reconstructed cerebral surfaces
    "stage5")
    #   generate binary files
    mris_volmask --surf_pial pial --save_ribbon --save_distance $NAME
    cd $SUBJECTS_DIR/$NAME/mri
    mri_binarize --i rh.dpial.ribbon.mgz --o rh.pial.ribbon_binary_uchar.mgz --min 0.1 --uchar
    mri_binarize --i lh.dpial.ribbon.mgz --o lh.pial.ribbon_binary_uchar.mgz --min 0.1 --uchar

    mri_convert lh.pial.ribbon_binary_uchar.mgz lh.pial.ribbon_binary_uchar.nii
    mri_convert rh.pial.ribbon_binary_uchar.mgz rh.pial.ribbon_binary_uchar.nii

    esac

done</Users/s0789354/Dropbox/Language_Dominance/script/sub_list_61



