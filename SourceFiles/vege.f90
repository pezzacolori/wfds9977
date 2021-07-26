MODULE VEGE
 
USE COMP_FUNCTIONS
USE PRECISION_PARAMETERS
USE GLOBAL_CONSTANTS
USE MESH_POINTERS
USE TRAN
USE PART
USE MEMORY_FUNCTIONS, ONLY:CHKMEMERR
USE TYPES, ONLY: PARTICLE_TYPE, PARTICLE_CLASS_TYPE, PARTICLE_CLASS ! , WALL_TYPE,SURFACE_TYPE 
IMPLICIT NONE
PRIVATE
PUBLIC INITIALIZE_LEVEL_SET_FIREFRONT,LEVEL_SET_FIREFRONT_PROPAGATION,END_LEVEL_SET,INITIALIZE_RAISED_VEG, &
       DEALLOCATE_VEG_ARRAYS,RAISED_VEG_MASS_ENERGY_TRANSFER,GET_REV_vege, &
       BNDRY_VEG_MASS_ENERGY_TRANSFER,LEVEL_SET_BC,LEVEL_SET_DT,READ_BRNR,INITIALIZE_RAISED_VEG_FROM_FILE, &
       CREATE_RAISED_VEG_FILE,INITIALIZE_RAISED_VEG_FROM_FILE_2
TYPE (PARTICLE_TYPE), POINTER :: LP=>NULL()
TYPE (PARTICLE_CLASS_TYPE), POINTER :: PC=>NULL()
!TYPE (WALL_TYPE), POINTER :: WC
!TYPE (SURFACE_TYPE), POINTER :: SF 
CHARACTER(255), PARAMETER :: vegeid='$Id: vege.f90 9718 2011-12-30 17:49:06Z drjfloyd $'
CHARACTER(255), PARAMETER :: vegerev='$Revision: 9718 $'
CHARACTER(255), PARAMETER :: vegedate='$Date: 2011-12-30 09:49:06 -0800 (Fri, 30 Dec 2011) $'
LOGICAL, ALLOCATABLE, DIMENSION(:,:,:) :: VEG_PRESENT_FLAG,CELL_TAKEN_FLAG
INTEGER, ALLOCATABLE, DIMENSION(:,:,:) :: IJK_VEGOUT
INTEGER :: IZERO,NLP_VEG_FUEL,NCONE_TREE,NXB,NYB
REAL(EB) :: RCELL,R_TREE,XCELL,XI,YJ,YCELL,ZCELL,ZK,TREEXS,TREEXF,TREEYS,TREEYF,TREEZS,TREEZF
!For Level Set
INTEGER  :: LIMITER_LS,LU_CRWN_PROB_LS,LU_FLI_LS,LU_ROSX_LS,LU_ROSY_LS,LU_TOA_LS  !&
!           ,LU_SLCF_LS,LU_SLCF_FLI_LS,LU_SLCF_PROBC_LS,LU_SLCF_ROS_LS,LU_SLCF_TOA_LS
REAL(EB) :: DX_LS,DY_LS,TIME_FLANKFIRE_QUENCH
!REAL(EB) :: DT_COEF,DYN_SR_MAX,DT_LS,SUM_T_SLCF_LS,SUMTIME_LS,TIME_LS
REAL(EB) :: IDX_LS,IDY_LS,T_FINAL,ROS_HEAD1,UMAG,UMF_TMP 
REAL(EB) :: CPUTIME,LS_T_BEG,LS_T_END,ROS_BACKS,ROS_HEADS
REAL(EB) :: B_ROTH,BETA_OP_ROTH,C_ROTH,E_ROTH

!REAL(EB) :: NX_LS,NY_LX,PHI_MIN_LS,PHI_MAX_LS

CONTAINS

SUBROUTINE INITIALIZE_RAISED_VEG_FROM_FILE(NM)
!Outer loop in over meshes to facilitate the identification of multiply occupied grid cells
!Read in, for each TREE, the TREE_NAME, number of particle classes, PART_ID, 
!number of grid cells occupied by the tree, and the x,y,z coordinates and bulk density
!for each grid cell

USE MEMORY_FUNCTIONS, ONLY: RE_ALLOCATE_PARTICLES
USE TRAN, ONLY: GET_IJK
INTEGER, INTENT(IN) :: NM
INTEGER:: II,JJ,KK,ITREE,IPC,NPART_CLASS,NCELL
INTEGER:: NVOX ! number of voxels for each tree
CHARACTER(30) :: TREE_NAME,PART_ID
REAL(EB) :: X,Y,Z,XI,YJ,ZK,BULK_DENSITY,GRID_CELL_VOLUME_FRACTION
LOGICAL  :: CELL_TAKEN

IF (VEG_INPUT_FILENAME == 'null') RETURN

!OPEN(UNIT=9137,FILE=VEG_INPUT_FILENAME,FORM='UNFORMATTED',STATUS='OLD')

!DO_MESH: DO NM=1,NMESHES

!print*,'read in binary file, total n_trees, nm = ',n_trees,nm

   CALL POINT_TO_MESH(NM)
   ALLOCATE(VEG_PRESENT_FLAG(0:IBP1,0:JBP1,0:KBP1))
   CALL ChkMemErr('VEGE','VEG_PRESENT_FLAG',IZERO)

  TREE_LOOP: DO ITREE = 1, N_TREES 

   VEG_PRESENT_FLAG = .FALSE.

   IF (N_TREE_IN_FILE(ITREE) == 0) CYCLE TREE_LOOP
   READ(9137) TREE_NAME
!print*,'vege:Tree Name=',TREE_NAME
   READ(9137) PART_ID
!print*,'PART_ID= ',PART_ID
   READ(9137) NVOX
!printe*,'vege:NUMBER OF VOXELS= ',NVOX

   NCELL_LOOP: DO NCELL=1,NVOX

     READ(9137) X,Y,Z,BULK_DENSITY,GRID_CELL_VOLUME_FRACTION
     CALL GET_IJK(X,Y,Z,NM,XI,YJ,ZK,II,JJ,KK)
     IPC = TREE_PARTICLE_CLASS(ITREE)
     PC=>PARTICLE_CLASS(IPC)
!print'(A,1x,4I5,5ES13.4)','veg:nm,itree,nlp,ipc,x,y,z,volfrac,rhob', &
!      nm,itree,nlp,ipc,x,y,z,grid_cell_volume_fraction,bulk_density
     IF(MESHES(NM)%XS < X .AND. X < MESHES(NM)%XF .AND. &
        MESHES(NM)%YS < Y .AND. Y < MESHES(NM)%YF .AND. &
        MESHES(NM)%ZS < Z .AND. Z < MESHES(NM)%ZF) THEN 
          TREE_MESH(NM) = .TRUE.
          IF (VEG_PRESENT_FLAG(II,JJ,KK)) CYCLE NCELL_LOOP 
          VEG_PRESENT_FLAG(II,JJ,KK) = .TRUE.
          NLP  = NLP + 1
          IF (NLP>NLPDIM) THEN
            CALL RE_ALLOCATE_PARTICLES(1,NM,0,1000)
            PARTICLE=>MESHES(NM)%PARTICLE
          ENDIF
          LP=>PARTICLE(NLP)
          LP%X = X
          LP%Y = Y
          LP%Z = Z 
          LP%VEG_VOLFRACTION = GRID_CELL_VOLUME_FRACTION
          LP%SHOW = .TRUE.
          LP%T = 0.
          LP%U = 0.
          LP%V = 0.
          LP%W = 0.
          LP%IOR = 0 !airborne static PARTICLE
          IF (PC%DRAG_LAW == SPHERE_DRAG)   LP%R =  3./PC%VEG_SV
          IF (PC%DRAG_LAW == CYLINDER_DRAG) LP%R =  2./PC%VEG_SV 
          LP%VEG_FUEL_MASS     = BULK_DENSITY
          LP%VEG_MOIST_MASS    = PC%VEG_MOISTURE*LP%VEG_FUEL_MASS
          LP%VEG_CHAR_MASS     = 0.0_EB
          LP%VEG_ASH_MASS      = 0.0_EB
          LP%VEG_PACKING_RATIO = BULK_DENSITY/PC%VEG_DENSITY 
          LP%VEG_SV            = PC%VEG_SV 
          LP%VEG_KAPPA         = 0.25*PC%VEG_SV*PC%VEG_BULK_DENSITY/PC%VEG_DENSITY
          LP%TMP               = PC%VEG_INITIAL_TEMPERATURE
          LP%VEG_IGNITED       = .FALSE.
          LP%IGNITOR           = .FALSE.
          LP%VEG_EMISS         = 4._EB*SIGMA*LP%VEG_KAPPA*LP%TMP**4
          LP%VEG_DIVQR         = 0.0_EB
          LP%VEG_N_TREE_PRT_OUTPUT = N_TREE_FOR_PRT_FILE(ITREE)
          LP%PWT               = 1._EB 
          LP%CLASS             = IPC
          PARTICLE_TAG         = PARTICLE_TAG + NMESHES
          LP%TAG               = PARTICLE_TAG
!print'(A,1x,5I3,5ES13.4,1L)','veg:nm,itree,nlp,ipc,lp% class,x,y,z,volfrac,rhob,tree_mesh(nm)', &
!      nm,itree,nlp,ipc,lp%class,lp%x,lp%y,lp%z,lp%veg_volfraction,bulk_density,tree_mesh(nm)
     ENDIF
!print*,'vege:tree_mesh(:)',tree_mesh
   ENDDO NCELL_LOOP
  ENDDO TREE_LOOP
  REWIND(9137)
  DEALLOCATE(VEG_PRESENT_FLAG)
!ENDDO DO_MESH

CLOSE(9137)

END SUBROUTINE INITIALIZE_RAISED_VEG_FROM_FILE

!---------------------------------------------------------------------------

SUBROUTINE CREATE_RAISED_VEG_FILE
!Output raised vegetation to a binary file

INTEGER  :: I,II,IPC,JJ,KK,NM,NCT,N_VEG_GRIDCELLS
REAL(EB) :: XI,YJ,ZK

IF (.NOT. CREATE_VEG_FILE) RETURN

OPEN(8137,FILE=TRIM(CHID)//'_output_veg.bin',FORM='UNFORMATTED',STATUS='REPLACE')

TREE_LOOP: DO NCT=1,N_TREES

  WRITE(8137) VEG_TREE_NAME(NCT) 
  IPC = TREE_PARTICLE_CLASS(NCT)
  PC=>PARTICLE_CLASS(IPC)
  WRITE(8137) PC%ID
  N_VEG_GRIDCELLS = 0

  MESH_LOOP_1: DO NM=1,NMESHES
     CALL POINT_TO_MESH(NM)
     PARTICLE_LOOP2: DO I=1,NLP !Count number of grid cells with veg for current tree
       LP=>PARTICLE(I)
       IF(LP%VEG_N_TREE_PRT_OUTPUT == NCT) N_VEG_GRIDCELLS = N_VEG_GRIDCELLS + 1
     ENDDO PARTICLE_LOOP2
!print'(A,1x,2I5,2A,2I5)','ntree,nm,tree_name,part_id,nlp,n_voxels',&
!                          nct,nm,veg_tree_name(nct),pc%id,nlp,n_veg_gridcells
  ENDDO MESH_LOOP_1 
 
  WRITE(8137) N_VEG_GRIDCELLS

  MESH_LOOP_2: DO NM=1,NMESHES
     CALL POINT_TO_MESH(NM)
     PARTICLE_LOOP3: DO I=1,NLP !Write particle information to binary file
       LP=>PARTICLE(I)
       IF(LP%VEG_N_TREE_PRT_OUTPUT == NCT) THEN
         CALL GET_IJK(LP%X,LP%Y,LP%Z,NM,XI,YJ,ZK,II,JJ,KK)
         WRITE(8137) LP%X,LP%Y,LP%Z,PC%VEG_BULK_DENSITY,LP%VEG_VOLFRACTION
!print'(A,1x,2I5,2A,2I5,3ES13.5)','vege create:ntree,nm,tree_name,part_id,nlp,n_voxels,x,y,z',&
!                          nct,nm,veg_tree_name(nct),pc%id,nlp,n_veg_gridcells,lp%x,lp%y,lp%z
       ENDIF
     ENDDO PARTICLE_LOOP3
  ENDDO MESH_LOOP_2 
 
  ENDDO TREE_LOOP

CLOSE(8137)

PRINT*,'********************************************************************************'
PRINT*,'Binary file with raised veg x,y,z,bulk density,volume fraction has been created'
PRINT*,'Filename is '//TRIM(CHID)//'_output_veg.bin'
PRINT*,'********************************************************************************'
STOP

END SUBROUTINE CREATE_RAISED_VEG_FILE

!---------------------------------------------------------------------------

SUBROUTINE INITIALIZE_RAISED_VEG_FROM_FILE_2
!This version of the subroutine does not check for mulitiply occupied grid cells.
!Read in, for each TREE, the TREE_NAME, number of particle classes, PART_ID, 
!number of grid cells occupied by the tree, and the x,y,z coordinates and bulk density
!for each grid cell

USE MEMORY_FUNCTIONS, ONLY: RE_ALLOCATE_PARTICLES
USE TRAN, ONLY: GET_IJK
INTEGER:: ITREE,IPC,NPART_CLASS,NCELL,NM
INTEGER:: NVOX ! number of voxels for each tree
CHARACTER(30) :: TREE_NAME,PART_ID
REAL(EB) :: X,Y,Z,BULK_DENSITY,GRID_CELL_VOLUME_FRACTION
LOGICAL  :: CELL_TAKEN

IF (VEG_INPUT_FILENAME == 'null') RETURN

OPEN(UNIT=9137,FILE=VEG_INPUT_FILENAME,FORM='UNFORMATTED',STATUS='OLD')

TREE_LOOP: DO ITREE = 1, N_TREES 
   IF (N_TREE_IN_FILE(ITREE) == 0) CYCLE TREE_LOOP
   READ(9137) TREE_NAME
   WRITE(*,*) 'Tree Name=',TREE_NAME
!  READ(9137) NPART_CLASS
!  WRITE(*,*) 'Number of particle classes for this tree= ',NPART_CLASS !this is currently not used
   READ(9137) PART_ID
   WRITE(*,*) 'PART_ID= ',PART_ID
   READ(9137) NVOX
   WRITE(*,*) 'NUMBER OF VOXELS= ',NVOX
!    allocate(bds(nvox))
!    read(9137) bds

     NCELL_LOOP: DO NCELL=1,NVOX
       READ(9137) X,Y,Z,BULK_DENSITY
!        CALL GET_IJK(X,Y,Z,NM,XI,YJ,ZK,II,JJ,KK)
       DO_MESH: DO NM=1,NMESHES
         IF (PROCESS(NM) /= MYID) CYCLE
         CALL POINT_TO_MESH(NM)
         IPC = TREE_PARTICLE_CLASS(ITREE)
         PC=>PARTICLE_CLASS(IPC)
         IF(MESHES(NM)%XS < X .AND. X < MESHES(NM)%XF .AND. &
            MESHES(NM)%YS < Y .AND. Y < MESHES(NM)%YF .AND. &
            MESHES(NM)%ZS < Z .AND. Z < MESHES(NM)%ZF) THEN 
            TREE_MESH(NM) = .TRUE.
            NLP  = NLP + 1
            IF (NLP>NLPDIM) THEN
             CALL RE_ALLOCATE_PARTICLES(1,NM,0,1000)
             PARTICLE=>MESHES(NM)%PARTICLE
            ENDIF
            LP=>PARTICLE(NLP)
            LP%X = X
            LP%Y = Y
            LP%Z = Z 
            LP%VEG_VOLFRACTION = GRID_CELL_VOLUME_FRACTION
            LP%SHOW = .TRUE.
            LP%T = 0.
            LP%U = 0.
            LP%V = 0.
            LP%W = 0.
            LP%IOR = 0 !airborne static PARTICLE
            IF (PC%DRAG_LAW == SPHERE_DRAG)   LP%R =  3./PC%VEG_SV
            IF (PC%DRAG_LAW == CYLINDER_DRAG) LP%R =  2./PC%VEG_SV 
            LP%VEG_FUEL_MASS     = BULK_DENSITY
            LP%VEG_MOIST_MASS    = PC%VEG_MOISTURE*LP%VEG_FUEL_MASS
            LP%VEG_CHAR_MASS     = 0.0_EB
            LP%VEG_ASH_MASS      = 0.0_EB
            LP%VEG_PACKING_RATIO = BULK_DENSITY/PC%VEG_DENSITY 
            LP%VEG_SV            = PC%VEG_SV 
            LP%VEG_KAPPA         = 0.25*PC%VEG_SV*PC%VEG_BULK_DENSITY/PC%VEG_DENSITY
            LP%TMP               = PC%VEG_INITIAL_TEMPERATURE
            LP%VEG_IGNITED       = .FALSE.
            LP%IGNITOR           = .FALSE.
            LP%VEG_EMISS         = 4._EB*SIGMA*LP%VEG_KAPPA*LP%TMP**4
            LP%VEG_DIVQR         = 0.0_EB
            LP%VEG_N_TREE_PRT_OUTPUT = N_TREE_FOR_PRT_FILE(ITREE)
            LP%PWT               = 1._EB 
            LP%CLASS             = IPC
            LP%VEG_VOLFRACTION   = 1._EB
            PARTICLE_TAG         = PARTICLE_TAG + NMESHES
            LP%TAG               = PARTICLE_TAG
!print*,'veg:nm,itree,nlp,ipc,lp% class,x,y,z,rhob,tree_mesh(nm)',nm,itree,nlp,ipc,lp%class,lp%x,lp%y,lp%z,bulk_density,tree_mesh(nm)
         ENDIF
       ENDDO DO_MESH
!print*,'vege:tree_mesh(:)',tree_mesh
     ENDDO NCELL_LOOP
ENDDO TREE_LOOP

CLOSE(9137)

END SUBROUTINE INITIALIZE_RAISED_VEG_FROM_FILE_2
 

SUBROUTINE INITIALIZE_RAISED_VEG(NM)

USE MEMORY_FUNCTIONS, ONLY: RE_ALLOCATE_PARTICLES
USE TRAN, ONLY : GET_IJK
REAL(EB) CROWN_LENGTH,CROWN_VOLUME,TANGENT,CROWN_WIDTH
REAL(EB) DX_RING,DZ_RING,INNER_RADIUS,OUTER_RADIUS,R_CTR_CYL,  &
         RING_BOTTOM,RING_TOP,SLANT_WIDTH
REAL(EB) V_CELL,XLOC,YLOC,ZLOC,X_EXTENT,Y_EXTENT,Z_EXTENT
INTEGER NCT,NLP_TREE,NLP_RECT_VEG,N_TREE,NXB,NYB,NZB,IPC
INTEGER N_CFCR_TREE,N_FRUSTUM_TREE,N_RECT_TREE,N_RING_TREE,N_IGN
INTEGER I,II,I_OUTER_RING,JJ,KK,K_BOTTOM_RING
INTEGER, INTENT(IN) :: NM

!The following are needed for outputting a binary veg file
INTEGER N_VEG_GRIDCELLS 
!CHARACTER(30) :: PART_ID
!CHARACTER(1)  :: CNMESH_1
!CHARACTER(2)  :: CNMESH_2
!CHARACTER(3)  :: CNMESH_3


!IF (.NOT. TREE) RETURN !Exit if there are no trees anywhere
!IF (.NOT. TREE_MESH(NM)) RETURN !Exit routine if no raised veg in mesh
IF (EVACUATION_ONLY(NM)) RETURN  ! Don't waste time if an evac mesh
CALL POINT_TO_MESH(NM)

ALLOCATE(VEG_PRESENT_FLAG(0:IBP1,0:JBP1,0:KBP1))
CALL ChkMemErr('VEGE','VEG_PRESENT_FLAG',IZERO)
ALLOCATE(CELL_TAKEN_FLAG(0:IBP1,0:JBP1,0:KBP1))
CALL ChkMemErr('VEGE','CELL_TAKEN_FLAG',IZERO)
ALLOCATE(IJK_VEGOUT(0:IBP1,0:JBP1,0:KBP1))
CALL ChkMemErr('VEGE','IJK_VEGOUT',IZERO)

!Diagnostic files
!IF (NM == NMESHES) THEN
!OPEN(9999,FILE='total_PARTICLE_mass.out',STATUS='REPLACE')
! OPEN(9998,FILE='diagnostics.out',STATUS='REPLACE')
!ENDIF

!TREE_MESH(NM)          = .FALSE. 
CONE_TREE_PRESENT      = .FALSE.
FRUSTUM_TREE_PRESENT   = .FALSE.
CYLINDER_TREE_PRESENT  = .FALSE.
RING_TREE_PRESENT      = .FALSE.
RECTANGLE_TREE_PRESENT = .FALSE.
IJK_VEGOUT             = 0

TREE_LOOP: DO NCT=1,N_TREES

   IF (N_TREE_IN_FILE(NCT) /= 0) CYCLE TREE_LOOP
   VEG_PRESENT_FLAG = .FALSE. ; CELL_TAKEN_FLAG = .FALSE.
   IPC = TREE_PARTICLE_CLASS(NCT)
   PC=>PARTICLE_CLASS(IPC)
   PC%KILL_RADIUS = 0.5_EB/PC%VEG_SV !radius bound below which fuel elements are removed
!  LP%VEG_VOLFRACTION = 0._EB !default volume fraction of veg in cell
! 
! Build a conical volume of solid (vegetation) fuel
!
   IF_CONE_VEGETATION: IF(VEG_FUEL_GEOM(NCT) == 'CONE') THEN
!
   CONE_TREE_PRESENT = .TRUE.
   N_CFCR_TREE = TREE_CFCR_INDEX(NCT)
   CROWN_WIDTH  = CROWN_W(N_CFCR_TREE)
   CROWN_LENGTH = TREE_H(N_CFCR_TREE) - CROWN_B_H(N_CFCR_TREE)
   IF(CROWN_LENGTH <= 0.0_EB) THEN
     PRINT*,'ERROR CONE TREE: Crown base height >= tree height for (maybe) tree number ', NCT
     PRINT*,'CONE TREE_HEIGHT = ',TREE_H(N_CFCR_TREE)
     PRINT*,'CONE CROWN_BASE_HEIGHT = ',CROWN_B_H(N_CFCR_TREE)
     STOP
   ENDIF
   TANGENT = 0.5_EB*CROWN_W(N_CFCR_TREE)/CROWN_LENGTH
   CROWN_VOLUME = PI*CROWN_WIDTH**2*CROWN_LENGTH/12._EB
 
   NLP_TREE = 0

   DO NZB=1,KBAR
     IF (Z(NZB)>=Z_TREE(N_CFCR_TREE)+CROWN_B_H(N_CFCR_TREE) .AND. & 
         Z(NZB)<=Z_TREE(N_CFCR_TREE)+TREE_H(N_CFCR_TREE)) THEN
      PARTICLE_TAG = PARTICLE_TAG + NMESHES
!      R_TREE = TANGENT*(TREE_H(N_CFCR_TREE)+Z_TREE(N_CFCR_TREE)-Z(NZB)+0.5_EB*DZ(NZB))
      R_TREE = TANGENT*(TREE_H(N_CFCR_TREE)+Z_TREE(N_CFCR_TREE)-Z(NZB))
      DO NXB = 1,IBAR
       DO NYB = 1,JBAR
        RCELL = SQRT((X(NXB)-X_TREE(N_CFCR_TREE))**2 + (Y(NYB)-Y_TREE(N_CFCR_TREE))**2)
        IF (RCELL <= R_TREE) THEN
         NLP  = NLP + 1
         NLP_TREE = NLP_TREE + 1
         IF (NLP>NLPDIM) THEN
          CALL RE_ALLOCATE_PARTICLES(1,NM,0,1000)
          PARTICLE=>MESHES(NM)%PARTICLE
         ENDIF
         LP=>PARTICLE(NLP)
         LP%VEG_VOLFRACTION = 1._EB
         LP%TAG = PARTICLE_TAG
!        LP%TAG = NCT !added to assign a number to each &TREE with OUTPUT=T
         LP%X = REAL(NXB,EB)
         LP%Y = REAL(NYB,EB)
         LP%Z = REAL(NZB,EB)
         LP%CLASS = IPC
         LP%PWT   = 1._EB  ! This is not used, but it is necessary to assign a non-zero weight factor to each particle
         VEG_PRESENT_FLAG(NXB,NYB,NZB) = .TRUE.
        ENDIF
       ENDDO   
      ENDDO 
     ENDIF
   ENDDO
   NLP_VEG_FUEL = NLP_TREE
!
   ENDIF IF_CONE_VEGETATION
! 
! Build a frustum volume of solid (vegetation) fuel
!
   IF_FRUSTUM_VEGETATION: IF(VEG_FUEL_GEOM(NCT) == 'FRUSTUM') THEN
!
   FRUSTUM_TREE_PRESENT = .TRUE.
   N_CFCR_TREE          = TREE_CFCR_INDEX(NCT)
   N_FRUSTUM_TREE       = TREE_FRUSTUM_INDEX(NCT)
   CROWN_LENGTH         = TREE_H(N_CFCR_TREE) - CROWN_B_H(N_CFCR_TREE)
   IF(CROWN_LENGTH <= 0.0_EB) THEN
     PRINT*,'ERROR FRUSTUM TREE: Crown base height >= tree height for (maybe) tree number ', NCT
     PRINT*,'FRUSTUM TREE_HEIGHT = ',TREE_H(N_CFCR_TREE)
     PRINT*,'FRUSTUM CROWN_BASE_HEIGHT = ',CROWN_B_H(N_CFCR_TREE)
     STOP
   ENDIF
   R_CTR_CYL    = 0.5*MIN(CROWN_W_TOP(N_FRUSTUM_TREE),CROWN_W_BOTTOM(N_FRUSTUM_TREE))
   SLANT_WIDTH  = 0.5*ABS(CROWN_W_TOP(N_FRUSTUM_TREE) - CROWN_W_BOTTOM(N_FRUSTUM_TREE))

   TANGENT = SLANT_WIDTH/CROWN_LENGTH
   CROWN_VOLUME = PI*CROWN_LENGTH*(CROWN_W_BOTTOM(N_FRUSTUM_TREE)**2 + & 
                  CROWN_W_TOP(N_FRUSTUM_TREE)*CROWN_W_TOP(N_FRUSTUM_TREE) + CROWN_W_TOP(N_FRUSTUM_TREE)**2)/3._EB
 
   NLP_TREE = 0

   DO NZB=1,KBAR
     IF (Z(NZB)>=Z_TREE(N_CFCR_TREE)+CROWN_B_H(N_CFCR_TREE) .AND. & 
                 Z(NZB)<=Z_TREE(N_CFCR_TREE)+TREE_H(N_CFCR_TREE)) THEN
      PARTICLE_TAG = PARTICLE_TAG + NMESHES
      IF(CROWN_W_TOP(N_FRUSTUM_TREE) <= CROWN_W_BOTTOM(N_FRUSTUM_TREE)) & 
                 R_TREE = R_CTR_CYL + TANGENT*(TREE_H(N_CFCR_TREE)+Z_TREE(N_CFCR_TREE)-Z(NZB))
      IF(CROWN_W_TOP(N_FRUSTUM_TREE) >  CROWN_W_BOTTOM(N_FRUSTUM_TREE)) &
                 R_TREE = R_CTR_CYL + TANGENT*(Z(NZB)-Z_TREE(N_CFCR_TREE)-CROWN_B_H(N_CFCR_TREE))
      DO NXB = 1,IBAR
       DO NYB = 1,JBAR
        RCELL = SQRT((X(NXB)-X_TREE(N_CFCR_TREE))**2 + (Y(NYB)-Y_TREE(N_CFCR_TREE))**2)
        IF (RCELL <= R_TREE) THEN
         NLP  = NLP + 1
         NLP_TREE = NLP_TREE + 1
         IF (NLP>NLPDIM) THEN
          CALL RE_ALLOCATE_PARTICLES(1,NM,0,1000)
          PARTICLE=>MESHES(NM)%PARTICLE
         ENDIF
         LP=>PARTICLE(NLP)
         LP%VEG_VOLFRACTION = 1._EB
         LP%TAG = PARTICLE_TAG
!        LP%TAG = NCT !added to assign a number to each &TREE with OUTPUT=T
         LP%X = REAL(NXB,EB)
         LP%Y = REAL(NYB,EB)
         LP%Z = REAL(NZB,EB)
         LP%CLASS = IPC
         LP%PWT   = 1._EB  ! This is not used, but it is necessary to assign a non-zero weight factor to each particle
         VEG_PRESENT_FLAG(NXB,NYB,NZB) = .TRUE.
        ENDIF
       ENDDO   
      ENDDO 
     ENDIF
   ENDDO
   NLP_VEG_FUEL = NLP_TREE
!
   ENDIF IF_FRUSTUM_VEGETATION
!
! Build a cylindrical volume of vegetative fuel
!
   IF_CYLINDRICAL_VEGETATION: IF (VEG_FUEL_GEOM(NCT) == 'CYLINDER') THEN
!
   CYLINDER_TREE_PRESENT = .TRUE.
   N_CFCR_TREE           = TREE_CFCR_INDEX(NCT)
   CROWN_WIDTH           = CROWN_W(N_CFCR_TREE)
   R_TREE                = 0.5*CROWN_WIDTH
   CROWN_LENGTH          = TREE_H(N_CFCR_TREE) - CROWN_B_H(N_CFCR_TREE)
   IF(CROWN_LENGTH <= 0.0_EB) THEN
     PRINT*,'ERROR CYLINDER TREE: Crown base height >= tree height for (maybe) tree number ', NCT
     PRINT*,'CYLINDER TREE_HEIGHT = ',TREE_H(N_CFCR_TREE)
     PRINT*,'CYLINDER CROWN_BASE_HEIGHT = ',CROWN_B_H(N_CFCR_TREE)
     STOP
   ENDIF
   CROWN_VOLUME = 0.25*PI*CROWN_WIDTH**2*CROWN_LENGTH
   NLP_TREE = 0

   DO NZB=1,KBAR
     IF (Z(NZB)>=Z_TREE(N_CFCR_TREE)+CROWN_B_H(N_CFCR_TREE) .AND. Z(NZB)<=Z_TREE(N_CFCR_TREE)+TREE_H(N_CFCR_TREE)) THEN
      PARTICLE_TAG = PARTICLE_TAG + NMESHES
      DO NXB = 1,IBAR
       DO NYB = 1,JBAR
        RCELL = SQRT((X(NXB)-X_TREE(N_CFCR_TREE))**2 + (Y(NYB)-Y_TREE(N_CFCR_TREE))**2)
        IF (RCELL <= R_TREE) THEN
         NLP  = NLP + 1
         NLP_TREE = NLP_TREE + 1
         IF (NLP>NLPDIM) THEN
          CALL RE_ALLOCATE_PARTICLES(1,NM,0,1000)
          PARTICLE=>MESHES(NM)%PARTICLE
         ENDIF
         LP=>PARTICLE(NLP)
         LP%VEG_VOLFRACTION = 1._EB
         LP%TAG = PARTICLE_TAG
!        LP%TAG = NCT !added to assign a number to each &TREE with OUTPUT=T
         LP%X = REAL(NXB,EB)
         LP%Y = REAL(NYB,EB)
         LP%Z = REAL(NZB,EB)
         LP%CLASS = IPC
         LP%PWT   = 1._EB  ! This is not used, but it is necessary to assign a non-zero weight factor to each particle
         VEG_PRESENT_FLAG(NXB,NYB,NZB) = .TRUE.
        ENDIF
       ENDDO   
      ENDDO 
     ENDIF
   ENDDO
   NLP_VEG_FUEL = NLP_TREE
!
   ENDIF IF_CYLINDRICAL_VEGETATION
!
! Build a rectangular volume containing vegetation
!
   IF_RECTANGULAR_VEGETATION:IF (VEG_FUEL_GEOM(NCT) == 'RECTANGLE')THEN
     RECTANGLE_TREE_PRESENT = .TRUE.
     N_RECT_TREE            = TREE_RECT_INDEX(NCT)
     NLP_RECT_VEG           = 0
     TREEXS = XS_RECT_VEG(N_RECT_TREE) ; TREEXF = XF_RECT_VEG(N_RECT_TREE) 
     TREEYS = YS_RECT_VEG(N_RECT_TREE) ; TREEYF = YF_RECT_VEG(N_RECT_TREE) 
     TREEZS = ZS_RECT_VEG(N_RECT_TREE) ; TREEZF = ZF_RECT_VEG(N_RECT_TREE) 
     X_EXTENT = TREEXF - TREEXS
     Y_EXTENT = TREEYF - TREEYS
     Z_EXTENT = TREEZF - TREEZS
     IF(X_EXTENT <= 0.0_EB .OR. Y_EXTENT <= 0.0_EB .OR. Z_EXTENT <= 0.0_EB) THEN
       PRINT*,'ERROR RECTANGULAR TREE: for (maybe) tree number ', NCT
       PRINT*,'ZERO OR NEGATIVE TREE WIDTH IN ONE OR MORE DIRECTIONS'
       PRINT*,'X LENGTH = ',X_EXTENT
       PRINT*,'Y LENGTH = ',Y_EXTENT
       PRINT*,'Z LENGTH = ',Z_EXTENT
       STOP
     ENDIF

    DO NZB=0,KBAR-1
! -- Check if veg is present in cell NXB,NYB,NZB (it may occupy only a portion of the cell)
      IF (Z(NZB+1) > TREEZS .AND. TREEZF > Z(NZB)) THEN
!print*,'NM',nm
!print '(A,2x,2ES12.4)','z(nzb+1), zs',z(nzb+1),treezs
!print '(A,2x,2ES12.4)','zf,z(nzb)',treezf,z(nzb)
        DO NYB = 0,JBAR-1
          IF (Y(NYB+1) > TREEYS+0.00001_EB .AND. TREEYF > Y(NYB)) THEN !the 0.00001_EB was added to ensure > instead of >=
!                                                                       needs fixing
! print*,'NM',nm
! print '(A,2x,2ES12.4)','y(nyb+1), ys',y(nyb+1),treeys
! print '(A,2x,2ES12.4)','yf,y(nyb)',treeyf,y(nyb)
            DO NXB = 0,IBAR-1
              IF (X(NXB+1) > TREEXS .AND. TREEXF > X(NXB)) THEN
                NLP  = NLP + 1
                NLP_RECT_VEG = NLP_RECT_VEG + 1
                IF (NLP>NLPDIM) THEN
                  CALL RE_ALLOCATE_PARTICLES(1,NM,0,1000)
                  PARTICLE=>MESHES(NM)%PARTICLE
                ENDIF
                LP=>PARTICLE(NLP)
                LP%VEG_VOLFRACTION = 1._EB
                LP%TAG = PARTICLE_TAG
!               LP%TAG = NCT !added to assign a number to each &TREE with OUTPUT=T
                LP%X = REAL(NXB,EB)
                LP%Y = REAL(NYB,EB)
                LP%Z = REAL(NZB,EB)
                LP%CLASS = IPC
                LP%PWT   = 1._EB  ! This is not used, but it is necessary to assign a non-zero weight factor to each particle
                VEG_PRESENT_FLAG(NXB,NYB,NZB) = .TRUE.
! -- Determine volume fraction occupied by vegetation in cell
                IF (TREEZS <= Z(NZB).AND. TREEZF < Z(NZB+1)) LP%VEG_VOLFRACTION = LP%VEG_VOLFRACTION - (Z(NZB+1)-TREEZF)/DZ(NZB)
                IF (TREEZS >  Z(NZB)) THEN
                  LP%VEG_VOLFRACTION = LP%VEG_VOLFRACTION - (TREEZS-Z(NZB))/DZ(NZB)
                  IF (TREEZF < Z(NZB+1)) LP%VEG_VOLFRACTION = LP%VEG_VOLFRACTION - (Z(NZB+1)-TREEZF)/DZ(NZB)
                ENDIF
              ENDIF
            ENDDO
          ENDIF
        ENDDO
      ENDIF
    ENDDO
    NLP_VEG_FUEL = NLP_RECT_VEG
   ENDIF IF_RECTANGULAR_VEGETATION

!   IF_RECTANGULAR_VEGETATION:IF (VEG_FUEL_GEOM(NCT) == 'RECTANGLE')THEN
!       RECTANGLE_TREE_PRESENT = .TRUE.
!       N_RECT_TREE            = TREE_RECT_INDEX(NCT)
!       NLP_RECT_VEG           = 0
!       DO NZB=0,KBAR-1
!        ZLOC = Z(NZB) + 0.5_EB*DZ(NZB)
!        IF (ZLOC>=ZS_RECT_VEG(N_RECT_TREE) .AND. ZLOC<=ZF_RECT_VEG(N_RECT_TREE)) THEN
!         DO NXB = 0,IBAR-1
!          XLOC = X(NXB) + 0.5_EB*DX(NXB)
!          IF (XLOC >= XS_RECT_VEG(N_RECT_TREE) .AND. XLOC <= XF_RECT_VEG(N_RECT_TREE)) THEN
!           DO NYB = 0,JBAR-1
!            YLOC = Y(NYB) + 0.5_EB*DY(NYB)
!            IF (YLOC >= YS_RECT_VEG(N_RECT_TREE) .AND. YLOC <= YF_RECT_VEG(N_RECT_TREE)) THEN
!             NLP  = NLP + 1
!             NLP_RECT_VEG = NLP_RECT_VEG + 1
!             IF (NLP>NLPDIM) THEN
!              CALL RE_ALLOCATE_PARTICLES(1,NM,0,1000)
!              PARTICLE=>MESHES(NM)%PARTICLE
!             ENDIF
!             LP=>PARTICLE(NLP)
!             LP%TAG = PARTICLE_TAG
!             LP%X = REAL(NXB,EB)
!             LP%Y = REAL(NYB,EB)
!             LP%Z = REAL(NZB,EB)
!             LP%CLASS = IPC
!             LP%PWT   = 1._EB  ! This is not used, but it is necessary to assign a non-zero weight factor to each particle
!             VEG_PRESENT_FLAG(NXB,NYB,NZB) = .TRUE.
!             X_EXTENT = XF_RECT_VEG(N_RECT_TREE) - XS_RECT_VEG(N_RECT_TREE)
!             Y_EXTENT = YF_RECT_VEG(N_RECT_TREE) - YS_RECT_VEG(N_RECT_TREE)
!             Z_EXTENT = ZF_RECT_VEG(N_RECT_TREE) - ZS_RECT_VEG(N_RECT_TREE)
!             IF(X_EXTENT <= 0.0_EB .OR. Y_EXTENT <= 0.0_EB .OR. Z_EXTENT <= 0.0_EB) THEN
!               PRINT*,'ERROR RECTANGULAR TREE: for (maybe) tree number ', NCT
!               PRINT*,'ZERO OR NEGATIVE TREE WIDTH IN ONE OR MORE DIRECTIONS'
!               PRINT*,'X LENGTH = ',X_EXTENT
!               PRINT*,'Y LENGTH = ',Y_EXTENT
!               PRINT*,'Z LENGTH = ',Z_EXTENT
!               STOP
!             ENDIF
!             LP%VEG_VOLFRACTION = 1._EB
!!            IF (X_EXTENT < DX(NXB)) LP%VEG_VOLFRACTION = LP%VEG_VOLFRACTION*X_EXTENT/DX(NXB)
!!            IF (Y_EXTENT < DY(NYB)) LP%VEG_VOLFRACTION = LP%VEG_VOLFRACTION*Y_EXTENT/DY(NYB)
!             IF (Z_EXTENT < DZ(NZB)) LP%VEG_VOLFRACTION = LP%VEG_VOLFRACTION*Z_EXTENT/DZ(NZB)
!!            print*,'veg_volfraction',z_extent,dz(nzb),LP%veg_volfraction
!!            print*,'veg_volfraction',xs_rect_veg(nct),xf_rect_veg(nct),ys_rect_veg(nct),yf_rect_veg(nct), &
!!                                     zs_rect_veg(nct),zf_rect_veg(nct),z_extent,dz(nzb),LP%VEG_VOLFRACTION
!            ENDIF
!           ENDDO   
!          ENDIF
!         ENDDO 
!        ENDIF
!       ENDDO
!       NLP_VEG_FUEL = NLP_RECT_VEG
!   ENDIF IF_RECTANGULAR_VEGETATION
!
! Build a ring volume of vegetation fuel
!
   IF_RING_VEGETATION_BUILD: IF (VEG_FUEL_GEOM(NCT) == 'RING') THEN
       RING_TREE_PRESENT = .TRUE.
       N_CFCR_TREE = TREE_CFCR_INDEX(NCT)
       N_RING_TREE = TREE_RING_INDEX(NCT)
       K_BOTTOM_RING = 0
       DZ_RING       = 0.0_EB
       OUTER_RADIUS  = 0.5_EB*CROWN_W(N_CFCR_TREE)
       RING_BOTTOM   = Z_TREE(N_CFCR_TREE) + CROWN_B_H(N_CFCR_TREE)
       RING_TOP      = Z_TREE(N_CFCR_TREE) + TREE_H(N_CFCR_TREE)
!  print*,'--------- NM = ',nm
!  print*,outer_radius
       DO II=1,IBAR-1
        IF(X(II) <= OUTER_RADIUS .AND. X(II+1) > OUTER_RADIUS) I_OUTER_RING = II
       ENDDO
!  print*,i_outer_ring,nct
!  print*,dx(i_outer_ring),ring_thickness_veg(nct)
!  DX_RING = MAX(DX(I_OUTER_RING),RING_THICKNESS_VEG(N_RING_TREE))
       DX_RING = DX(1)
       INNER_RADIUS = OUTER_RADIUS - DX_RING
       DO KK=1,KBAR-1
        IF(Z(KK) <= RING_BOTTOM .AND. Z(KK+1) > RING_BOTTOM) K_BOTTOM_RING = KK
       ENDDO
       IF (K_BOTTOM_RING > 0) DZ_RING  = MAX(DZ(K_BOTTOM_RING),RING_TOP-RING_BOTTOM)
       RING_TOP = RING_BOTTOM + DZ_RING
       NLP_TREE = 0
!
       DO NZB=1,KBAR
         IF (Z(NZB)>=RING_BOTTOM .AND. Z(NZB)<=RING_TOP) THEN
          PARTICLE_TAG = PARTICLE_TAG + NMESHES
          DO NXB = 1,IBAR
           DO NYB = 1,JBAR
            RCELL = SQRT((X(NXB)-X_TREE(N_CFCR_TREE))**2 + (Y(NYB)-Y_TREE(N_CFCR_TREE))**2)
            IF (RCELL <= OUTER_RADIUS .AND. RCELL >= INNER_RADIUS) THEN
             NLP  = NLP + 1
             NLP_TREE = NLP_TREE + 1
             IF (NLP>NLPDIM) THEN
              CALL RE_ALLOCATE_PARTICLES(1,NM,0,1000)
              PARTICLE=>MESHES(NM)%PARTICLE
             ENDIF
             LP=>PARTICLE(NLP)
             LP%VEG_VOLFRACTION = 1._EB
             LP%TAG = PARTICLE_TAG
!            LP%TAG = NCT !added to assign a number to each &TREE with OUTPUT=T
             LP%X = REAL(NXB,EB)
             LP%Y = REAL(NYB,EB)
             LP%Z = REAL(NZB,EB)
             LP%CLASS = IPC
             LP%PWT   = 1._EB  ! This is not used, but it is necessary to assign a non-zero weight factor to each particle
             VEG_PRESENT_FLAG(NXB,NYB,NZB) = .TRUE.
            ENDIF
           ENDDO   
          ENDDO 
         ENDIF
       ENDDO
       NLP_VEG_FUEL = NLP_TREE
   ENDIF IF_RING_VEGETATION_BUILD
!
! For the current vegetation type (particle class) assign one fuel 
! element (PARTICLE) to each grid cell and initialize PARTICLE properties
! (this is precautionary needs more testing to determine its necessity)
!
   REP_VEG_ELEMS: DO I=NLP-NLP_VEG_FUEL+1,NLP
    LP=>PARTICLE(I)
    LP%IGNITOR = .FALSE.
!print*,'vege not from file:I,NCT,NM',I,NCT,NM
    DO NZB=0,KBAR
     DO NXB=0,IBAR
      GRID_LOOP: DO NYB=0,JBAR
       IF (.NOT. VEG_PRESENT_FLAG(NXB,NYB,NZB)) CYCLE GRID_LOOP
       IF (REAL(NXB,EB)==LP%X .AND. REAL(NYB,EB)==LP%Y .AND. REAL(NZB,EB)==LP%Z) THEN 
        IF(CELL_TAKEN_FLAG(NXB,NYB,NZB)) THEN
         LP%R = 0.0001_EB*PC%KILL_RADIUS
         CYCLE REP_VEG_ELEMS
        ENDIF
        CELL_TAKEN_FLAG(NXB,NYB,NZB) = .TRUE.
        LP%X = X(NXB) - 0.5_EB*DX(NXB)
        LP%Y = Y(NYB) - 0.5_EB*DY(NYB)
        LP%Z = Z(NZB) - 0.5_EB*DZ(NZB)
        IF (VEG_FUEL_GEOM(NCT) == 'RECTANGLE')THEN
         LP%X = X(NXB) + 0.5_EB*DX(NXB)
         LP%Y = Y(NYB) + 0.5_EB*DY(NYB)
         LP%Z = Z(NZB) + 0.5_EB*DZ(NZB)
        ENDIF
        TREE_MESH(NM) = .TRUE.
        LP%SHOW = .TRUE.
        LP%T   = 0.
        LP%U = 0.
        LP%V = 0.
        LP%W = 0.
        IF (PC%DRAG_LAW == SPHERE_DRAG)   LP%R =  3./PC%VEG_SV
        IF (PC%DRAG_LAW == CYLINDER_DRAG) LP%R =  2./PC%VEG_SV 
        LP%IOR = 0
        LP%VEG_FUEL_MASS  = PC%VEG_BULK_DENSITY
        LP%VEG_MOIST_MASS = PC%VEG_MOISTURE*LP%VEG_FUEL_MASS
!       LP%VEG_CHAR_MASS  = PC%VEG_BULK_DENSITY*PC%VEG_CHAR_FRACTION
        LP%VEG_CHAR_MASS  = 0.0_EB
        LP%VEG_ASH_MASS   = 0.0_EB
        LP%VEG_PACKING_RATIO = PC%VEG_BULK_DENSITY/PC%VEG_DENSITY 
        LP%VEG_SV            = PC%VEG_SV 
        LP%VEG_KAPPA = 0.25*PC%VEG_SV*PC%VEG_BULK_DENSITY/PC%VEG_DENSITY
        LP%TMP = PC%VEG_INITIAL_TEMPERATURE
        LP%VEG_IGNITED = .FALSE.
        LP%VEG_N_TREE_PRT_OUTPUT = N_TREE_FOR_PRT_FILE(NCT) !number of tree in .prt files
        LP%VEG_N_TREE_OUTPUT     = N_TREE_OUT(NCT) !array index for average tree stats files
        IF(IGN_ELEMS(NCT)) THEN
          IGNITOR_PRESENT = .TRUE.
          LP%TMP = TMPA
          LP%IGNITOR = .TRUE.
          N_IGN = TREE_IGN_INDEX(NCT)
          LP%VEG_IGN_TON      = TON_IGN_ELEMS(N_IGN)
          LP%VEG_IGN_TOFF     = TOFF_IGN_ELEMS(N_IGN)
          LP%VEG_IGN_TRAMPON  = T_RAMPON_IGN_ELEMS(N_IGN)
          LP%VEG_IGN_TRAMPOFF = T_RAMPOFF_IGN_ELEMS(N_IGN)
        ENDIF
        LP%VEG_EMISS = 4._EB*SIGMA*LP%VEG_KAPPA*LP%TMP**4
        LP%VEG_DIVQR = 0.0_EB
!       LP%VEG_N_TREE_OUTPUT = 0
!       TREE_MESH_OUT(NM) = .FALSE.
!       IF (N_TREE_OUT(NCT) /= 0) THEN
!        CALL GET_IJK(LP%X,LP%Y,LP%Z,NM,XI,YJ,ZK,II,JJ,KK)
!        IJK_VEGOUT(II,JJ,KK) = 1
!        LP%VEG_N_TREE_OUTPUT = N_TREE_OUT(NCT)
!        LP%IOR = 0 !airborne static PARTICLE
!        TREE_MESH_OUT(NM) = .TRUE.
!       ENDIF
        CYCLE REP_VEG_ELEMS
       ENDIF
      ENDDO GRID_LOOP
     ENDDO
    ENDDO
   ENDDO REP_VEG_ELEMS
!
!print*,'in vege 2: NM,NCT,NLP,N_TREE_OUT(NCT),TREE_MESH_OUT(NM)',NM,NCT,NLP,N_TREE_OUT(NCT),TREE_MESH_OUT(NM)
ENDDO TREE_LOOP

CALL REMOVE_PARTICLES(0._EB,NM)

!Fill veg output arrays with initial values of tree averaged quanitities 
IF (N_TREES_OUTPUT_DATA > 0) THEN 
  CALL POINT_TO_MESH(NM)
  TREE_OUTPUT_DATA(:,:,NM) = 0._EB
  PARTICLE_LOOP: DO I=1,NLP
   LP=>PARTICLE(I)
   N_TREE = LP%VEG_N_TREE_OUTPUT
   CALL GET_IJK(LP%X,LP%Y,LP%Z,NM,XI,YJ,ZK,II,JJ,KK)
   IF(N_TREE == 0 .AND. IJK_VEGOUT(II,JJ,KK)==1 .AND. .NOT. LP%IGNITOR) LP%R = 0.0001_EB*PC%KILL_RADIUS
   IF (N_TREE /= 0) THEN
     V_CELL = DX(II)*DY(JJ)*DZ(KK)
     TREE_OUTPUT_DATA(N_TREE,1,NM) = TREE_OUTPUT_DATA(N_TREE,1,NM) + LP%TMP - 273._EB !C
     TREE_OUTPUT_DATA(N_TREE,2,NM) = TREE_OUTPUT_DATA(N_TREE,2,NM) + TMPA   - 273._EB !C
     TREE_OUTPUT_DATA(N_TREE,3,NM) = TREE_OUTPUT_DATA(N_TREE,3,NM) + LP%VEG_FUEL_MASS*V_CELL*LP%VEG_VOLFRACTION !kg
     TREE_OUTPUT_DATA(N_TREE,4,NM) = TREE_OUTPUT_DATA(N_TREE,4,NM) + LP%VEG_MOIST_MASS*V_CELL*LP%VEG_VOLFRACTION !kg
     TREE_OUTPUT_DATA(N_TREE,5,NM) = TREE_OUTPUT_DATA(N_TREE,5,NM) + LP%VEG_CHAR_MASS*V_CELL !kg
     TREE_OUTPUT_DATA(N_TREE,6,NM) = TREE_OUTPUT_DATA(N_TREE,6,NM) + LP%VEG_ASH_MASS*V_CELL !kg
     TREE_OUTPUT_DATA(N_TREE,7,NM) = TREE_OUTPUT_DATA(N_TREE,7,NM) + LP%VEG_DIVQR*V_CELL*0.001_EB !kW
     TREE_OUTPUT_DATA(N_TREE,8,NM) = TREE_OUTPUT_DATA(N_TREE,8,NM) + LP%VEG_DIVQR*V_CELL*0.001_EB !kW
     TREE_OUTPUT_DATA(N_TREE,10,NM) = 0.0_EB !kg
     TREE_OUTPUT_DATA(N_TREE,11,NM) = 0.0_EB !kW
   ENDIF
  ENDDO PARTICLE_LOOP
ENDIF

CALL REMOVE_PARTICLES(0._EB,NM)

!Deallocate arrays 
DEALLOCATE(VEG_PRESENT_FLAG)
DEALLOCATE(CELL_TAKEN_FLAG)
DEALLOCATE(IJK_VEGOUT)

END SUBROUTINE INITIALIZE_RAISED_VEG

SUBROUTINE DEALLOCATE_VEG_ARRAYS
!Deallocate arrays used to initialize vegetation particles

IF (CONE_TREE_PRESENT .OR. FRUSTUM_TREE_PRESENT .OR. CYLINDER_TREE_PRESENT .OR. RING_TREE_PRESENT) THEN
 DEALLOCATE(TREE_CFCR_INDEX) 
 DEALLOCATE(X_TREE)
 DEALLOCATE(Y_TREE)
 DEALLOCATE(Z_TREE)
 DEALLOCATE(TREE_H)
 DEALLOCATE(CROWN_B_H)
 DEALLOCATE(CROWN_W)
ENDIF
IF (FRUSTUM_TREE_PRESENT) THEN
 DEALLOCATE(TREE_FRUSTUM_INDEX)
 DEALLOCATE(CROWN_W_TOP)
 DEALLOCATE(CROWN_W_BOTTOM)
ENDIF

IF (RECTANGLE_TREE_PRESENT) THEN
 DEALLOCATE(TREE_RECT_INDEX)
 DEALLOCATE(XS_RECT_VEG)
 DEALLOCATE(XF_RECT_VEG)
 DEALLOCATE(YS_RECT_VEG)
 DEALLOCATE(YF_RECT_VEG)
 DEALLOCATE(ZS_RECT_VEG)
 DEALLOCATE(ZF_RECT_VEG)
ENDIF

IF (RING_TREE_PRESENT) THEN
 DEALLOCATE(TREE_RING_INDEX)
 DEALLOCATE(RING_THICKNESS_VEG)
ENDIF

IF (IGNITOR_PRESENT) THEN
 DEALLOCATE(IGN_ELEMS)
 DEALLOCATE(TREE_IGN_INDEX)
 DEALLOCATE(TON_IGN_ELEMS)
 DEALLOCATE(TOFF_IGN_ELEMS)
 DEALLOCATE(T_RAMPOFF_IGN_ELEMS)
 DEALLOCATE(T_RAMPON_IGN_ELEMS)
ENDIF
END SUBROUTINE DEALLOCATE_VEG_ARRAYS



SUBROUTINE RAISED_VEG_MASS_ENERGY_TRANSFER(T,NM)
    
! Mass and energy transfer between gas and raised vegetation fuel elements 
!
USE PHYSICAL_FUNCTIONS, ONLY : GET_MASS_FRACTION,GET_SPECIFIC_HEAT,GET_CONDUCTIVITY,GET_VISCOSITY
USE MATH_FUNCTIONS, ONLY : AFILL2
USE TRAN, ONLY: GET_IJK
!arrays for debugging
REAL(EB), POINTER, DIMENSION(:,:,:) :: HOLD1,HOLD2,HOLD3,HOLD4
REAL(EB), POINTER, DIMENSION(:,:,:) :: UU,VV,WW !,RHOP

REAL(EB) :: RE_D,RCP_GAS,CP_GAS
REAL(EB) :: RDT,T,V_CELL,V_VEG
REAL(EB) :: CP_ASH,CP_H2O,CP_CHAR,H_VAP_H2O,TMP_H2O_BOIL
REAL(EB) :: K_AIR,K_GAS,MU_AIR,MU_GAS,RHO_GAS,RRHO_GAS_NEW,TMP_FILM,TMP_GAS,UBAR,VBAR,WBAR,UREL,VREL,WREL
REAL(EB) :: CHAR_FCTR,CHAR_FCTR2,CP_VEG,DTMP_VEG,MPV_MOIST,MPV_MOIST_MIN,DMPV_VEG,MPV_VEG,MPV_VEG_MIN, &
            SV_VEG,TMP_VEG,TMP_VEG_NEW
REAL(EB) :: TMP_IGNITOR
REAL(EB) :: MPV_ADDED,MPV_MOIST_LOSS,MPV_VOLIT,MPV_CHAR_LOSS_MAX,MPV_MOIST_LOSS_MAX,MPV_VOLIT_MAX
REAL(EB) :: QCON_VEG,QNET_VEG,QRAD_VEG,QREL,TMP_GMV,Q_FOR_DRYING,Q_VOLIT,Q_FOR_VOLIT, &
            Q_UPTO_VOLIT
REAL(EB) :: H_SENS_VEG_VOLIT,Q_ENTHALPY,Q_VEG_MOIST,Q_VEG_VOLIT,Q_VEG_CHAR
REAL(EB) :: MW_AVERAGE,MW_VEG_MOIST_TERM,MW_VEG_VOLIT_TERM
REAL(EB) :: XI,YJ,ZK
REAL(EB) :: A_H2O_VEG,E_H2O_VEG,A_PYR_VEG,E_PYR_VEG,H_PYR_VEG,R_H_PYR_VEG
REAL(EB) :: A_CHAR_VEG,E_CHAR_VEG,BETA_CHAR_VEG,NU_CHAR_VEG,NU_ASH_VEG,NU_O2_CHAR_VEG, &
            MPV_ASH,MPV_ASH_MAX,MPV_CHAR,MPV_CHAR_LOSS,MPV_CHAR_MIN,MPV_CHAR_CO2,MPV_CHAR_O2,Y_O2, &
            H_CHAR_VEG ,ORIG_PACKING_RATIO,CP_VEG_FUEL_AND_CHAR_MASS,CP_MASS_VEG_SOLID,     &
            TMP_CHAR_MAX
REAL(EB) :: ZZ_GET(0:N_TRACKED_SPECIES)
INTEGER :: I,II,JJ,KK,IIX,JJY,KKZ,IPC,N_TREE,I_FUEL
INTEGER, INTENT(IN) :: NM
LOGICAL :: VEG_DEGRADATION_LINEAR,VEG_DEGRADATION_ARRHENIUS
INTEGER :: IDT,NDT_CYCLES
REAL(EB) :: FCTR_DT_CYCLES,FCTR_RDT_CYCLES,Q_VEG_CHAR_TOTAL,MPV_CHAR_CO2_TOTAL,MPV_CHAR_O2_TOTAL,MPV_CHAR_LOSS_TOTAL, &
            MPV_MOIST_LOSS_TOTAL,MPV_VOLIT_TOTAL,VEG_VF
REAL(EB) :: VEG_CRITICAL_MASSFLUX,VEG_CRITICAL_MASSSOURCE
REAL(EB) :: CM,CN,RHO_AIR
REAL(EB) :: HCON_VEG_FORCED,HCON_VEG_FREE,LENGTH_SCALE,NUSS_HILPERT_CYL_FORCEDCONV,NUSS_MORGAN_CYL_FREECONV,RAYLEIGH_NUM, &
            R_VEG_CYL_DIAM,HC_VERT_CYL,HC_HORI_CYL

!place holder
REAL(EB) :: RCP_TEMPORARY

!Debug
REAL(EB)TOTAL_BULKDENS_MOIST,TOTAL_BULKDENS_DRY_FUEL,TOTAL_MASS_DRY_FUEL,TOTAL_MASS_MOIST


!IF (.NOT. TREE) RETURN !Exit if no raised veg anywhere
IF (.NOT. TREE_MESH(NM)) RETURN !Exit if raised veg is not present in mesh
CALL POINT_TO_MESH(NM)

!IF (PREDICTOR) THEN
    UU => U
    VV => V
    WW => W
!   RHOP => RHO
!ELSE
!   UU => US
!   VV => VS
!   WW => WS
!   RHOP => RHOS
!ENDIF

! Initializations

RDT    = 1._EB/DT
!RCP_TEMPORARY = 1._EB/CP_GAMMA
RCP_TEMPORARY = 1._EB/1010._EB

!Critical mass flux (kg/(s m^2)
VEG_CRITICAL_MASSFLUX = 0.0025_EB !kg/s/m^2 for qradinc=50 kW/m^2, M=4% measured by McAllister Fire Safety J., 61:200-206 2013
!VEG_CRITICAL_MASSFLUX = 0.0035_EB !kg/s/m^2 largest measured by McAllister Fire Safety J., 61:200-206 2013
!VEG_CRITICAL_MASSFLUX = 999999._EB !kg/s/m^2 for testing

!Constants for Arrhenius pyrolyis and Arrhenius char oxidation models
!are from the literature (Porterie et al., Num. Heat Transfer, 47:571-591, 2005)
CP_H2O       = 4190._EB !J/kg/K specific heat of water
TMP_H2O_BOIL = 373.15_EB
!H_VAP_H2O    = 2259._EB*1000._EB !J/kg/K heat of vaporization of water
TMP_CHAR_MAX = 1300._EB !K

!Kinetic constants used by multiple investigators from Porterie or Morvan papers
!VEG_A_H2O      = 600000._EB !1/s sqrt(K)
!VEG_E_H2O      = 5800._EB !K
!VEG_A_PYR      = 36300._EB !1/s
!VEG_E_PYR      = 7250._EB !K
!VEG_E_CHAR     = 9000._EB !K
!VEG_BETA_CHAR  = 0.2_EB
!!VEG_NU_CHAR    = 0.3_EB
!!VEG_NU_ASH     = 0.1_EB
!VEG_NU_O2_CHAR = 1.65_EB

!CP_ASH         = 800._EB !J/kg/K

!Kinetic constants used by Morvan and Porterie mostly obtained from Grishin
!VEG_H_PYR      = 418000._EB !J/kg 
!VEG_A_CHAR     = 430._EB !m/s 
!VEG_H_CHAR     = -12.0E+6_EB ! J/kg

!Kinetic constants used by Yolanda and Paul
!VEG_H_PYR      = 418000._EB !J/kg 
!VEG_A_CHAR     = 215._EB !m/s Yolanda, adjusted from Morvan, Porterie values based on HRR exp
!VEG_H_CHAR     = -32.74E+6_EB !J/kg via Susott

!Kinetic constants used by Shankar
!VEG_H_PYR      = 418._EB !J/kg Shankar
!VEG_A_CHAR     = 430._EB !m/s Porterie, Morvan
!VEG_H_CHAR     = -32.74E+6_EB !J/kg Shankar via Susott

!Kinetic constants used by me for ROS vs Slope excelsior experiments
!VEG_H_PYR      = 711000._EB !J/kg excelsior Catchpole et al. (via Susott)
!VEG_A_CHAR     = 430._EB !m/s Porterie, Morvan
!VEG_H_CHAR     = -32.74E+6_EB !J/kg via Susott

!R_H_PYR_VEG    = 1._EB/H_PYR_VEG

!D_AIR  = 2.6E-5_EB  ! Water Vapor - Air binary diffusion (m2/s at 25 C, Incropera & DeWitt, Table A.8) 
!SC_AIR = 0.6_EB     ! NU_AIR/D_AIR (Incropera & DeWitt, Chap 7, External Flow)
!PR_AIR = 0.7_EB     

! Working arrays
IF(N_TREES_OUTPUT_DATA > 0) TREE_OUTPUT_DATA(:,:,NM) = 0._EB !for output of veg data
!DMPVDT_FM_VEG  = 0.0_EB

!Clear arrays and scalars
HOLD1 => WORK4 ; WORK4 = 0._EB
HOLD2 => WORK5 ; WORK5 = 0._EB
HOLD3 => WORK6 ; WORK6 = 0._EB
HOLD4 => WORK7 ; WORK7 = 0._EB
TOTAL_BULKDENS_MOIST    = 0.0_EB
TOTAL_BULKDENS_DRY_FUEL = 0.0_EB
TOTAL_MASS_MOIST    = 0.0_EB
TOTAL_MASS_DRY_FUEL = 0.0_EB
V_VEG               = 0.0_EB

!print*,'vege h-m transfer: NM, NLP',nm,nlp

PARTICLE_LOOP: DO I=1,NLP

 LP => PARTICLE(I)
 IPC = LP%CLASS
 PC=>PARTICLE_CLASS(IPC)
 IF (.NOT. PC%TREE) CYCLE PARTICLE_LOOP !Ensure grid cell has vegetation
 IF (PC%MASSLESS) CYCLE PARTICLE_LOOP   !Skip PARTICLE if massless

 THERMAL_CALC: IF (.NOT. PC%VEG_STEM) THEN   !compute heat transfer, etc if thermally thin

!Quantities for sub-cycling the thermal degradation time stepping
 NDT_CYCLES  = PC%VEG_NDT_SUBCYCLES !number of thermal degradation time stepping loops within one gas phase DT
 FCTR_DT_CYCLES   = 1._EB/REAL(NDT_CYCLES,EB)
 FCTR_RDT_CYCLES  = REAL(NDT_CYCLES,EB)

! Intialize quantities
 LP%VEG_MLR      = 0.0_EB
 LP%VEG_Q_CHAROX = 0.0_EB
 Q_VEG_CHAR      = 0.0_EB
 Q_VEG_MOIST     = 0.0_EB
 Q_VEG_VOLIT     = 0.0_EB
 Q_UPTO_VOLIT    = 0.0_EB
 Q_VOLIT         = 0.0_EB
 MPV_MOIST_LOSS  = 0.0_EB
 MPV_CHAR_LOSS   = 0.0_EB
 MPV_CHAR_CO2    = 0.0_EB
 MPV_CHAR_O2     = 0.0_EB
 MPV_VOLIT       = 0.0_EB
 MPV_ADDED       = 0.0_EB
 MW_VEG_MOIST_TERM = 0.0_EB
 MW_VEG_VOLIT_TERM = 0.0_EB
 CP_VEG_FUEL_AND_CHAR_MASS = 0.0_EB
 CP_MASS_VEG_SOLID         = 0.0_EB
 VEG_DEGRADATION_LINEAR    = .FALSE.
 VEG_DEGRADATION_ARRHENIUS = .FALSE.
 MPV_CHAR_CO2_TOTAL   = 0.0_EB
 MPV_CHAR_O2_TOTAL   = 0.0_EB 
 MPV_CHAR_LOSS_TOTAL  = 0.0_EB 
 MPV_MOIST_LOSS_TOTAL = 0.0_EB 
 MPV_VOLIT_TOTAL  = 0.0_EB 
 Q_VEG_CHAR_TOTAL = 0.0_EB

! Vegetation variables
 VEG_VF             = LP%VEG_VOLFRACTION !volume fraction of vegetation in cell
 NU_CHAR_VEG        = PC%VEG_CHAR_FRACTION
 NU_ASH_VEG         = PC%VEG_ASH_FRACTION/PC%VEG_CHAR_FRACTION !fraction of char that can become ash
 CHAR_FCTR          = 1._EB - PC%VEG_CHAR_FRACTION !factor used to determine volatile mass
 CHAR_FCTR2         = 1._EB/CHAR_FCTR !factor used to determine char mass
 SV_VEG             = LP%VEG_SV !surface-to-volume ration 1/m
 TMP_VEG            = LP%TMP
 MPV_VEG            = LP%VEG_FUEL_MASS !bulk density of dry veg kg/m^3
 MPV_CHAR           = LP%VEG_CHAR_MASS !bulk density of char
 MPV_ASH            = LP%VEG_ASH_MASS  !bulk density of ash 
 MPV_MOIST          = LP%VEG_MOIST_MASS !bulk density of moisture in veg
 MPV_VEG_MIN        = VEG_VF*PC%VEG_FUEL_MPV_MIN + (1._EB - VEG_VF)*PC%VEG_BULK_DENSITY
 MPV_CHAR_MIN       = MPV_VEG_MIN*PC%VEG_CHAR_FRACTION
 MPV_MOIST_MIN      = VEG_VF*PC%VEG_MOIST_MPV_MIN + (1._EB - VEG_VF)*PC%VEG_BULK_DENSITY*PC%VEG_MOISTURE
 MPV_ASH_MAX        = PC%VEG_ASH_MPV_MAX   !maxium ash bulk density
 MPV_MOIST_LOSS_MAX = PC%VEG_DEHYDRATION_RATE_MAX*DT*FCTR_DT_CYCLES
 MPV_VOLIT_MAX      = PC%VEG_BURNING_RATE_MAX*DT*FCTR_DT_CYCLES
 MPV_CHAR_LOSS_MAX  = PC%VEG_CHAROX_RATE_MAX*DT*FCTR_DT_CYCLES
 ORIG_PACKING_RATIO = PC%VEG_BULK_DENSITY/PC%VEG_DENSITY 
 H_VAP_H2O          = PC%VEG_H_H2O !J/kg/K heat of vaporization of water
 A_H2O_VEG          = PC%VEG_A_H2O !1/s sqrt(K)
 E_H2O_VEG          = PC%VEG_E_H2O !K
 H_PYR_VEG          = PC%VEG_H_PYR !J/kg 
 A_PYR_VEG          = PC%VEG_A_PYR !1/s
 E_PYR_VEG          = PC%VEG_E_PYR !K
 H_CHAR_VEG         = PC%VEG_H_CHAR ! J/kg
 A_CHAR_VEG         = PC%VEG_A_CHAR !m/s 
 E_CHAR_VEG         = PC%VEG_E_CHAR !K
 BETA_CHAR_VEG      = PC%VEG_BETA_CHAR
 NU_O2_CHAR_VEG     = PC%VEG_NU_O2_CHAR

! Thermal degradation approach parameters
 IF(PC%VEG_DEGRADATION == 'LINEAR') VEG_DEGRADATION_LINEAR = .TRUE.
 IF(PC%VEG_DEGRADATION == 'ARRHENIUS') VEG_DEGRADATION_ARRHENIUS = .TRUE.

 R_H_PYR_VEG    = 1._EB/H_PYR_VEG

!Bound on volumetric mass flux
 VEG_CRITICAL_MASSSOURCE = VEG_CRITICAL_MASSFLUX*SV_VEG*LP%VEG_PACKING_RATIO

! Determine grid cell quantities of the vegetation fuel element
 CALL GET_IJK(LP%X,LP%Y,LP%Z,NM,XI,YJ,ZK,II,JJ,KK)
 IIX = FLOOR(XI+0.5_EB)
 JJY = FLOOR(YJ+0.5_EB)
 KKZ = FLOOR(ZK+0.5_EB)
 V_CELL = DX(II)*DY(JJ)*DZ(KK)

! Gas velocities in vegetation grid cell
 UBAR = AFILL2(UU,II-1,JJY,KKZ,XI-II+1,YJ-JJY+.5_EB,ZK-KKZ+.5_EB)
 VBAR = AFILL2(VV,IIX,JJ-1,KKZ,XI-IIX+.5_EB,YJ-JJ+1,ZK-KKZ+.5_EB)
 WBAR = AFILL2(WW,IIX,JJY,KK-1,XI-IIX+.5_EB,YJ-JJY+.5_EB,ZK-KK+1)
 UREL = LP%U - UBAR
 VREL = LP%V - VBAR
 WREL = LP%W - WBAR
 QREL = MAX(1.E-6_EB,SQRT(UREL*UREL + VREL*VREL + WREL*WREL))


! Gas thermophysical quantities
 RHO_GAS  = RHO(II,JJ,KK)
 TMP_GAS  = TMP(II,JJ,KK)
 TMP_FILM = 0.5_EB*(TMP_GAS + TMP_VEG)

! Assuming gas is air
!RHO_AIR  = 101325./(287.05*TMP_FILM) !rho_air = standard pressure / (ideal gas constant*gas temp)
!MU_AIR   =  (0.000001458_EB*TMP_FILM**1.5_EB)/(TMP_FILM+110.4_EB) !kg/m/s
!K_AIR    = (0.002495_EB*TMP_FILM**1.5_EB)/(TMP_FILM+194._EB) !W/m.K

!Use full gas composition
 ZZ_GET(1:N_TRACKED_SPECIES) = ZZ(II,JJ,KK,1:N_TRACKED_SPECIES)
 CALL GET_VISCOSITY(ZZ_GET,MU_GAS,TMP_FILM)
 CALL GET_CONDUCTIVITY(ZZ_GET,K_GAS,TMP_FILM)
 CALL GET_SPECIFIC_HEAT(ZZ_GET,CP_GAS,TMP_FILM)

TIME_SUBCYCLING_LOOP: DO IDT=1,NDT_CYCLES

! Veg thermophysical properties
 TMP_GMV  = TMP_GAS - TMP_VEG
 CP_VEG   = (0.01_EB + 0.0037_EB*TMP_VEG)*1000._EB !J/kg/K Ritchie IAFSS 1997:177-188
 CP_CHAR  = 420._EB + 2.09_EB*TMP_VEG + 6.85E-4_EB*TMP_VEG**2 !J/kg/K Park etal. C&F 2010 147:481-494
 CP_ASH   = 1244._EB*(TMP_VEG/TMPA)**0.315 !J/kg/K Lautenberger & Fernandez-Pell, C&F 2009 156:1503-1513
 R_VEG_CYL_DIAM = 0.25_EB*SV_VEG

! Convective heat flux on thermal elements

 IF_QCONV: IF (.NOT. PC%VEG_HCONV_CYLLAM) THEN

   RE_D     = RHO_GAS*QREL*4._EB/(SV_VEG*MU_GAS)

! - Forced convection heat transfer coefficients on veg particles
!
! Hilpert Correlation (Incropera & DeWitt Fourth Edition, p. 370) for cylinder in crossflow,
! forced convection
   IF(RE_D < 4._EB) THEN
     CN = 0.989_EB
     CM = 0.330_EB
   ELSE IF (RE_D >= 4._EB .AND. RE_D < 40._EB) THEN
     CN = 0.911_EB
     CM = 0.385_EB
   ELSE
     CN = 0.683_EB
     CM = 0.466_EB
   ENDIF
   NUSS_HILPERT_CYL_FORCEDCONV = CN*(RE_D**CM)*PR_ONTH !Nusselt number
!print '(A,2x,2ES12.4)','nuss Hilpert,Re', NUSS_HILPERT_CYL_FORCEDCONV,re_d
   HCON_VEG_FORCED = 0.25_EB*SV_VEG*K_GAS*NUSS_HILPERT_CYL_FORCEDCONV !W/m^2 from Hilpert (cylinder)

! - Free convection heat transfer coefficients
   LENGTH_SCALE = 4._EB/SV_VEG !horizontal cylinder diameter
   RAYLEIGH_NUM = 9.8_EB*ABS(TMP_GMV)*LENGTH_SCALE**3*RHO_GAS**2*CP_GAS/(TMP_FILM*MU_GAS*K_GAS)

! Morgan correlation (Incropera & DeWitt, 4th Edition, p. 501-502) for horizontal cylinder of diameter
! 4/SV_VEG, free convection
   IF (RAYLEIGH_NUM < 0.01_EB) THEN
     CN = 0.675_EB
     CM = 0.058_EB
   ELSE IF (RAYLEIGH_NUM >= 0.01_EB .AND. RAYLEIGH_NUM < 100._EB) THEN
     CN = 1.02_EB
     CM = 0.148_EB
   ELSE IF (RAYLEIGH_NUM >= 100._EB .AND. RAYLEIGH_NUM < 10**4._EB) THEN
     CN = 0.85_EB
     CM = 0.188_EB
   ELSE IF (RAYLEIGH_NUM >= 10**4._EB .AND. RAYLEIGH_NUM < 10**7._EB) THEN
     CN = 0.48_EB
     CM = 0.25_EB
   ELSE IF (RAYLEIGH_NUM >= 10**7._EB .AND. RAYLEIGH_NUM < 10**12._EB) THEN
     CN = 0.125_EB
     CM = 0.333_EB
   ENDIF
   NUSS_MORGAN_CYL_FREECONV = CN*RAYLEIGH_NUM**CM
   HCON_VEG_FREE = 0.25_EB*SV_VEG*K_GAS*NUSS_MORGAN_CYL_FREECONV !W/m^2

   QCON_VEG = MAX(HCON_VEG_FORCED,HCON_VEG_FREE)*TMP_GMV !W/m^2

 ELSE  !Laminar flow, cyl of diameter 4/sv_veg

  HC_VERT_CYL = 1.42_EB*(ABS(TMP_GMV)*R_VEG_CYL_DIAM)**0.25_EB !Holman vertical cylinder
  HC_HORI_CYL = 1.32_EB*(ABS(TMP_GMV)*R_VEG_CYL_DIAM)**0.25_EB !Holman horizontal cylinder
  QCON_VEG    = TMP_GMV*0.5_EB*(HC_VERT_CYL+HC_HORI_CYL) !average of vertical and horizontal cylinder 

 ENDIF IF_QCONV

 
! IF (TMP_VEG >= TMP_GAS )QCON_VEG = SV_VEG*(0.5_EB*K_AIR*0.683_EB*RE_D**0.466_EB)*0.5_EB*TMP_GMV !W/m^2 from Porterie
! IF (TMP_VEG <  TMP_GAS ) QCON_VEG = TMP_GMV*1.42_EB*(ABS(TMP_GMV)/DZ(KK))**0.25_EB !Holman
!RE_D     = RHO_GAS*QREL*2._EB/(SV_VEG*MU_GAS)
!QCON_VEG = SV_VEG*(0.5_EB*K_GAS*0.683_EB*RE_D**0.466_EB)*0.5_EB*TMP_GMV !W/m^2 from Porterie (cylinder)
! QCON_VEG = TMP_GMV*1.42_EB*(ABS(TMP_GMV)/DZ(KK))**0.25_EB !Holman vertical cylinders of length dz, Laminar flow
! QCON_VEG = TMP_GMV*1.32_EB*(ABS(TMP_GMV)*SV_VEG*0.25_EB)**0.25_EB !Holman horizontal cylinders of diameter 4/sv_veg, Laminar flow

 QCON_VEG = SV_VEG*LP%VEG_PACKING_RATIO*QCON_VEG !W/m^3
 LP%VEG_DIVQC = QCON_VEG
 QRAD_VEG = LP%VEG_DIVQR

! Divergence of net heat flux
 QNET_VEG = QCON_VEG + QRAD_VEG !W/m^3

! Update temperature of vegetation
!CP_VEG_FUEL_AND_CHAR_MASS = CP_VEG*MPV_VEG + CP_CHAR*MPV_CHAR
!DTMP_VEG    = DT*QNET_VEG/(CP_VEG_FUEL_AND_CHAR_MASS + CP_H2O*MPV_MOIST)
 CP_MASS_VEG_SOLID = CP_VEG*MPV_VEG + CP_CHAR*MPV_CHAR + CP_ASH*MPV_ASH
 DTMP_VEG    = FCTR_DT_CYCLES*DT*QNET_VEG/(CP_MASS_VEG_SOLID + CP_H2O*MPV_MOIST)
!print*,'vege:tmpveg,qnet_veg,cp_mass_veg_solid',tmp_veg,qnet_veg,cp_mass_veg_solid
 TMP_VEG_NEW = TMP_VEG + DTMP_VEG
 IF (TMP_VEG_NEW < TMPA) TMP_VEG_NEW = TMP_GAS
!print*,'---------------------------------------------------------'
!print 1113,ii,jj,kk,idt
!1113 format(2x,4(I3))
!print 1112,tmp_veg_new,tmp_veg,qnet_veg,cp_mass_veg_solid,cp_h2o,dtmp_veg
!1112 format(2x,6(e15.5))

! Set temperature of inert ignitor elements
 IF(LP%IGNITOR) THEN
  TMP_IGNITOR = PC%VEG_INITIAL_TEMPERATURE
  TMP_VEG_NEW = TMP_GAS
  IF(T>=LP%VEG_IGN_TON .AND. T<=LP%VEG_IGN_TON+LP%VEG_IGN_TRAMPON) THEN
    TMP_VEG_NEW = &
      TMPA + (TMP_IGNITOR-TMPA)*(T-LP%VEG_IGN_TON)/LP%VEG_IGN_TRAMPON
  ENDIF  
  IF(T>LP%VEG_IGN_TON+LP%VEG_IGN_TRAMPON) TMP_VEG_NEW = TMP_IGNITOR
  IF(T>=LP%VEG_IGN_TOFF .AND. T<=LP%VEG_IGN_TOFF+LP%VEG_IGN_TRAMPOFF)THEN 
    TMP_VEG_NEW = &
      TMP_IGNITOR - (TMP_IGNITOR-TMP_GAS)*(T-LP%VEG_IGN_TOFF)/LP%VEG_IGN_TRAMPOFF
  ENDIF
  IF(T > LP%VEG_IGN_TOFF+LP%VEG_IGN_TRAMPOFF) THEN
   LP%R = 0.0001_EB*PC%KILL_RADIUS !remove ignitor element
   TMP_VEG_NEW = TMP_GAS
  ENDIF
 ENDIF

!      ************** Fuel Element Linear Pyrolysis Degradation model *************************
! Drying occurs if qnet > 0 with Tveg held at 100 c
! Pyrolysis occurs if qnet > 0 according to Morvan & Dupuy empirical formula. Linear
! temperature dependence with qnet factor. 
! Char oxidation occurs if qnet > 0 (user must request char ox) after pyrolysis is completed.
!
 IF_VEG_DEGRADATION_LINEAR: IF(VEG_DEGRADATION_LINEAR) THEN
   IF_NET_HEAT_INFLUX: IF (QNET_VEG > 0.0_EB .AND. .NOT. LP%IGNITOR) THEN !dehydrate or pyrolyze 

! Drying of fuel element vegetation 
     IF_DEHYDRATION: IF (MPV_MOIST > MPV_MOIST_MIN .AND. TMP_VEG_NEW > TMP_H2O_BOIL) THEN
       Q_FOR_DRYING   = (TMP_VEG_NEW - TMP_H2O_BOIL)/DTMP_VEG * QNET_VEG
       MPV_MOIST_LOSS = MIN(DT*Q_FOR_DRYING/H_VAP_H2O,MPV_MOIST-MPV_MOIST_MIN)
       MPV_MOIST_LOSS = MIN(MPV_MOIST_LOSS,MPV_MOIST_LOSS_MAX) !use specified max
       TMP_VEG_NEW       = TMP_H2O_BOIL
       LP%VEG_MOIST_MASS = MPV_MOIST - MPV_MOIST_LOSS !kg/m^3
       IF (LP%VEG_MOIST_MASS <= MPV_MOIST_MIN) LP%VEG_MOIST_MASS = 0.0_EB
       Q_VEG_MOIST       = MPV_MOIST_LOSS*CP_H2O*(TMP_VEG_NEW - TMPA)
       MW_VEG_MOIST_TERM = MPV_MOIST_LOSS/MW_H2O
!      IF (I == 1) print*,MPV_MOIST,MPV_MOIST_LOSS
     ENDIF IF_DEHYDRATION

! Volitalization of fuel element vegetation
     IF_VOLITALIZATION: IF(MPV_MOIST <= MPV_MOIST_MIN) THEN

       IF_MD_VOLIT: IF(MPV_VEG > MPV_VEG_MIN .AND. TMP_VEG_NEW >= 400._EB) THEN !Morvan & Dupuy volitalization
         Q_UPTO_VOLIT = CP_MASS_VEG_SOLID*MAX((400._EB-TMP_VEG),0._EB)
         Q_FOR_VOLIT  = DT*QNET_VEG - Q_UPTO_VOLIT
         Q_VOLIT      = Q_FOR_VOLIT*0.01_EB*(MIN(500._EB,TMP_VEG)-400._EB)

!        MPV_VOLIT    = Q_VOLIT*R_H_PYR_VEG
         MPV_VOLIT    = CHAR_FCTR*Q_VOLIT*R_H_PYR_VEG
         MPV_VOLIT    = MAX(MPV_VOLIT,0._EB)
         MPV_VOLIT    = MIN(MPV_VOLIT,MPV_VOLIT_MAX) !user specified max

         DMPV_VEG     = CHAR_FCTR2*MPV_VOLIT
         DMPV_VEG     = MIN(DMPV_VEG,(MPV_VEG - MPV_VEG_MIN))
         MPV_VEG      = MPV_VEG - DMPV_VEG

         MPV_VOLIT    = CHAR_FCTR*DMPV_VEG
!        MPV_CHAR     = MPV_CHAR + NU_CHAR_VEG*MPV_VOLIT !kg/m^3
!        MPV_CHAR     = MPV_CHAR + PC%VEG_CHAR_FRACTION*MPV_VOLIT !kg/m^3
         MPV_CHAR     = MPV_CHAR + PC%VEG_CHAR_FRACTION*DMPV_VEG !kg/m^3
         Q_VOLIT      = MPV_VOLIT*H_PYR_VEG
         CP_MASS_VEG_SOLID = CP_VEG*MPV_VEG + CP_CHAR*MPV_CHAR 
         TMP_VEG_NEW  = TMP_VEG + (Q_FOR_VOLIT-Q_VOLIT)/CP_MASS_VEG_SOLID
         TMP_VEG_NEW  = MIN(TMP_VEG_NEW,500._EB) !set to high pyrol temp if too hot

!Handle veg. fuel elements if element mass <= prescribed minimum
         IF (MPV_VEG <= MPV_VEG_MIN) THEN
           MPV_VEG = MPV_VEG_MIN
           IF(PC%VEG_REMOVE_CHARRED .AND. .NOT. PC%VEG_CHAR_OXIDATION) THEN
             IF(.NOT. PC%VEG_KEEP_FOR_SMV) LP%R = 0.0001_EB*PC%KILL_RADIUS !fuel element will be removed
             IF(      PC%VEG_KEEP_FOR_SMV) LP%VEG_PACKING_RATIO = 0.0_EB !make drag,qc,qr=0 
           ENDIF
         ENDIF
!Enthalpy of fuel element volatiles using Cp,volatiles(T) from Ritchie
         H_SENS_VEG_VOLIT = 0.0445_EB*(TMP_VEG**1.5_EB - TMP_GAS**1.5_EB) - 0.136_EB*(TMP_VEG - TMP_GAS)
         H_SENS_VEG_VOLIT = H_SENS_VEG_VOLIT*1000._EB !J/kg
         Q_VEG_VOLIT      = MPV_VOLIT*H_SENS_VEG_VOLIT !J/m^3
         MW_VEG_VOLIT_TERM= MPV_VOLIT/SPECIES(FUEL_INDEX)%MW
        ENDIF IF_MD_VOLIT

      LP%VEG_FUEL_MASS = MPV_VEG
      LP%VEG_CHAR_MASS = MPV_CHAR !kg/m^3

    ENDIF IF_VOLITALIZATION

   ENDIF IF_NET_HEAT_INFLUX

!Char oxidation of fuel element with the Linear pyrolysis model from Morvan and Dupuy, Comb.
!Flame, 138:199-210 (2004)
!(note that this can be handled only approximately with the conserved
!scalar based gas-phase combustion model - the oxygen is consumed by
!the char oxidation reaction is not accounted for since it would be inconsistent with the state
!relation for oxygen that is based on the conserved scalar approach used for gas phase
!combustion)
   IF_CHAR_OXIDATION_LIN: IF (PC%VEG_CHAR_OXIDATION .AND. MPV_MOIST <= MPV_MOIST_MIN) THEN

     ZZ_GET(1:N_TRACKED_SPECIES) = ZZ(II,JJ,KK,1:N_TRACKED_SPECIES)
     CALL GET_MASS_FRACTION(ZZ_GET,O2_INDEX,Y_O2)
     MPV_CHAR_LOSS = DT*RHO_GAS*Y_O2*A_CHAR_VEG/NU_O2_CHAR_VEG*SV_VEG*LP%VEG_PACKING_RATIO*  &
                      EXP(-E_CHAR_VEG/TMP_VEG)*(1+BETA_CHAR_VEG*SQRT(RE_D))
     MPV_CHAR_LOSS = MIN(MPV_CHAR_LOSS,MPV_CHAR_LOSS_MAX) !user bound
     MPV_CHAR      = MAX(MPV_CHAR - MPV_CHAR_LOSS,0.0_EB)
     MPV_CHAR_LOSS = LP%VEG_CHAR_MASS - MPV_CHAR
     MPV_CHAR_CO2  = (1._EB + NU_O2_CHAR_VEG - NU_ASH_VEG)*MPV_CHAR_LOSS
     LP%VEG_CHAR_MASS  = MPV_CHAR !kg/m^3
     CP_MASS_VEG_SOLID = MPV_VEG*CP_VEG + MPV_CHAR*CP_CHAR + MPV_ASH*CP_ASH

! Reduce fuel element size based on char consumption
!!    IF (MPV_VEG <= MPV_VEG_MIN) THEN !charring reduce veg elem size
!      LP%VEG_PACKING_RATIO = LP%VEG_PACKING_RATIO - MPV_CHAR_LOSS/(PC%VEG_DENSITY*PC%VEG_CHAR_FRACTION)
!      LP%VEG_SV     = PC%VEG_SV*(ORIG_PACKING_RATIO/LP%VEG_PACKING_RATIO)**0.333_EB 
!      LP%VEG_KAPPA  = 0.25_EB*LP%VEG_SV*LP%VEG_PACKING_RATIO
!!    ENDIF

!remove fuel element if char ox is complete
      IF (MPV_CHAR <= MPV_CHAR_MIN .AND. MPV_VEG <= MPV_VEG_MIN) THEN 
        CP_MASS_VEG_SOLID = MPV_ASH*CP_ASH
        LP%VEG_CHAR_MASS = 0.0_EB
        IF(PC%VEG_REMOVE_CHARRED .AND. .NOT. PC%VEG_KEEP_FOR_SMV) LP%R = 0.0001_EB*PC%KILL_RADIUS 
        IF(PC%VEG_REMOVE_CHARRED .AND. PC%VEG_KEEP_FOR_SMV) LP%VEG_PACKING_RATIO = 0.0_EB !make drag,qc,qr 0 
      ENDIF

      Q_VEG_CHAR       = MPV_CHAR_LOSS*H_CHAR_VEG 
      LP%VEG_Q_CHAROX  = -Q_VEG_CHAR*RDT
      Q_VEG_CHAR_TOTAL = Q_VEG_CHAR_TOTAL + Q_VEG_CHAR
      TMP_VEG_NEW  = TMP_VEG_NEW - PC%VEG_CHAR_ENTHALPY_FRACTION*Q_VEG_CHAR/CP_MASS_VEG_SOLID
      TMP_VEG_NEW  = MIN(TMP_CHAR_MAX,TMP_VEG_NEW)
!     print*,'vege: q_veg_char,temp_veg_new,',q_veg_char,tmp_veg_new
!          print*,'------------------'
!    ENDIF IF_CHAR_OXIDATION_LIN_2

   ENDIF IF_CHAR_OXIDATION_LIN
  
 ENDIF IF_VEG_DEGRADATION_LINEAR

!      ************** Fuel Element Arrehnius Degradation model *************************
! Drying and pyrolysis of fuel element occur according to Arrehnius expressions obtained 
! from the literature (Porterie et al., Num. Heat Transfer, 47:571-591, 2005
! Predicting wildland fire behavior and emissions using a fine-scale physical
! model
!
 IF_VEG_DEGRADATION_ARRHENIUS: IF(VEG_DEGRADATION_ARRHENIUS) THEN

!  TMP_VEG = TMPA + 5._EB/60._EB*T ; TMP_VEG_NEW = TMP_VEG !mimic TGA with 5 C/min heating rate

   IF_NOT_IGNITOR1: IF (.NOT. LP%IGNITOR) THEN !dehydrate or pyrolyze 

! Drying of fuel element vegetation 
     IF_DEHYDRATION_2: IF (MPV_MOIST > MPV_MOIST_MIN) THEN
       MPV_MOIST_LOSS = MIN(FCTR_DT_CYCLES*DT*MPV_MOIST*A_H2O_VEG*EXP(-E_H2O_VEG/TMP_VEG)/SQRT(TMP_VEG), &
                            MPV_MOIST-MPV_MOIST_MIN)
       MPV_MOIST_LOSS = MIN(MPV_MOIST_LOSS,MPV_MOIST_LOSS_MAX) !use specified max
       MPV_MOIST      = MPV_MOIST - MPV_MOIST_LOSS
       LP%VEG_MOIST_MASS = MPV_MOIST !kg/m^3
       IF (MPV_MOIST <= MPV_MOIST_MIN) LP%VEG_MOIST_MASS = 0.0_EB
       MW_VEG_MOIST_TERM = MPV_MOIST_LOSS/MW_H2O
       Q_VEG_MOIST  = MPV_MOIST_LOSS*CP_H2O*(TMP_VEG - TMPA)
!      IF (I == 1) print*,MPV_MOIST,MPV_MOIST_LOSS
     ENDIF IF_DEHYDRATION_2

! Volitalization of fuel element vegetation
     IF_VOLITALIZATION_2: IF(MPV_VEG > MPV_VEG_MIN) THEN
       MPV_VOLIT    = FCTR_DT_CYCLES*DT*CHAR_FCTR*MPV_VEG*A_PYR_VEG*EXP(-E_PYR_VEG/TMP_VEG)
       MPV_VOLIT    = MIN(MPV_VOLIT,MPV_VOLIT_MAX) !user specified max

       DMPV_VEG     = CHAR_FCTR2*MPV_VOLIT
       DMPV_VEG     = MIN(DMPV_VEG,(MPV_VEG - MPV_VEG_MIN))
       MPV_VEG      = MPV_VEG - DMPV_VEG

       MPV_VOLIT    = CHAR_FCTR*DMPV_VEG 
       MPV_CHAR     = MPV_CHAR + PC%VEG_CHAR_FRACTION*DMPV_VEG !kg/m^3
!      MPV_CHAR     = MPV_CHAR + PC%VEG_CHAR_FRACTION*MPV_VOLIT !kg/m^3
       CP_MASS_VEG_SOLID = CP_VEG*MPV_VEG + CP_CHAR*MPV_CHAR + CP_ASH*MPV_ASH


!Yolanda's
!    MPV_VOLIT    = DT*MPV_VEG*A_PYR_VEG*EXP(-E_PYR_VEG/TMP_VEG)
!    MPV_VOLIT    = MAX(MPV_VOLIT,0._EB)
!    MPV_VOLIT    = MIN(MPV_VOLIT,MPV_VOLIT_MAX) !user specified max
!    MPV_VOLIT    = MIN(MPV_VOLIT,(MPV_VEG-MPV_VEG_MIN))
!    MPV_VEG      = MPV_VEG - MPV_VOLIT
!    MPV_CHAR     = MPV_CHAR + PC%VEG_CHAR_FRACTION*MPV_VOLIT !kg/m^3
!    CP_MASS_VEG_SOLID = CP_VEG*MPV_VEG + CP_CHAR*MPV_CHAR + CP_ASH*MPV_ASH
!    MPV_VOLIT    = CHAR_FCTR*MPV_VOLIT ! added by Paul to account that volatiles are a fraction of the dry mass transformed *****

!Handle veg. fuel elements if original element mass <= prescribed minimum
       IF (MPV_VEG <= MPV_VEG_MIN) THEN
!        MPV_VEG = MPV_VEG_MIN
         MPV_VEG = 0.0_EB
         CP_MASS_VEG_SOLID = CP_CHAR*MPV_CHAR + CP_ASH*MPV_ASH
         IF(PC%VEG_REMOVE_CHARRED .AND. .NOT. PC%VEG_CHAR_OXIDATION) THEN
           IF(.NOT. PC%VEG_KEEP_FOR_SMV) LP%R = 0.0001_EB*PC%KILL_RADIUS !remove part
           IF(      PC%VEG_KEEP_FOR_SMV) LP%VEG_PACKING_RATIO = 0.0_EB   !make drag,qc,qr= 0
         ENDIF
       ENDIF
!Enthalpy of fuel element volatiles using Cp,volatiles(T) from Ritchie
       H_SENS_VEG_VOLIT = 0.0445_EB*(TMP_VEG**1.5_EB - TMP_GAS**1.5_EB) - 0.136_EB*(TMP_VEG - TMP_GAS)
       H_SENS_VEG_VOLIT = H_SENS_VEG_VOLIT*1000._EB !J/kg
       Q_VEG_VOLIT      = MPV_VOLIT*H_SENS_VEG_VOLIT !J
       MW_VEG_VOLIT_TERM= MPV_VOLIT/SPECIES(FUEL_INDEX)%MW
     ENDIF IF_VOLITALIZATION_2

     LP%VEG_FUEL_MASS = MPV_VEG
     LP%VEG_CHAR_MASS = MPV_CHAR

!Char oxidation of fuel element within the Arrhenius pyrolysis model
!(note that this can be handled only approximately with the conserved
!scalar based gas-phase combustion model - no gas phase oxygen is consumed by
!the char oxidation reaction since it would be inconsistent with the state
!relation for oxygen based on the conserved scalar approach for gas phase
!combustion)
     IF_CHAR_OXIDATION: IF (PC%VEG_CHAR_OXIDATION) THEN
       ZZ_GET(1:N_TRACKED_SPECIES) = ZZ(II,JJ,KK,1:N_TRACKED_SPECIES)
       CALL GET_MASS_FRACTION(ZZ_GET,O2_INDEX,Y_O2)
       MPV_CHAR_LOSS = FCTR_DT_CYCLES*DT*RHO_GAS*Y_O2*A_CHAR_VEG/NU_O2_CHAR_VEG*SV_VEG*LP%VEG_PACKING_RATIO*  &
                        EXP(-E_CHAR_VEG/TMP_VEG)*(1._EB+BETA_CHAR_VEG*SQRT(RE_D))
       MPV_CHAR_LOSS = MIN(MPV_CHAR_LOSS,MPV_CHAR_LOSS_MAX) !user bound
       MPV_CHAR_LOSS = MIN(MPV_CHAR,MPV_CHAR_LOSS)
       MPV_CHAR      = MPV_CHAR - MPV_CHAR_LOSS
       MPV_ASH       = MPV_ASH + NU_ASH_VEG*MPV_CHAR_LOSS
       MPV_CHAR_CO2  = (1._EB + NU_O2_CHAR_VEG - NU_ASH_VEG)*MPV_CHAR_LOSS
       MPV_CHAR_O2   = NU_O2_CHAR_VEG*MPV_CHAR_LOSS
       CP_MASS_VEG_SOLID = CP_VEG*MPV_VEG + CP_CHAR*MPV_CHAR + CP_ASH*MPV_ASH
       LP%VEG_CHAR_MASS = MPV_CHAR !kg/m^3
       LP%VEG_ASH_MASS  = MPV_ASH

! Reduce veg element size based on char consumption
!      LP%VEG_PACKING_RATIO = LP%VEG_PACKING_RATIO - MPV_CHAR_LOSS/(PC%VEG_DENSITY*PC%VEG_CHAR_FRACTION)
!      LP%VEG_SV     = PC%VEG_SV*(ORIG_PACKING_RATIO/LP%VEG_PACKING_RATIO)**0.333_EB 
!      LP%VEG_KAPPA  = 0.25_EB*LP%VEG_SV*LP%VEG_PACKING_RATIO

! Remove particle if char is fully consumed
       IF (MPV_CHAR <= MPV_CHAR_MIN .AND. MPV_VEG <= MPV_VEG_MIN) THEN 
!        IF (MPV_ASH >= MPV_ASH_MAX .AND. MPV_VEG <= MPV_VEG_MIN) THEN 
!        CP_MASS_VEG_SOLID = CP_CHAR*MPV_CHAR_MIN
         CP_MASS_VEG_SOLID = CP_ASH*MPV_ASH
         LP%VEG_CHAR_MASS = 0.0_EB
         IF(PC%VEG_REMOVE_CHARRED .AND. .NOT. PC%VEG_KEEP_FOR_SMV) LP%R = 0.0001_EB*PC%KILL_RADIUS 
         IF(PC%VEG_REMOVE_CHARRED .AND. PC%VEG_KEEP_FOR_SMV) LP%VEG_PACKING_RATIO = 0.0_EB !make drag,qc,qr= 0 
       ENDIF
!  ENDIF IF_CHAR_OXIDATION_2

     ENDIF IF_CHAR_OXIDATION

     Q_VEG_CHAR        = MPV_CHAR_LOSS*H_CHAR_VEG 
     LP%VEG_Q_CHAROX   = -Q_VEG_CHAR*RDT
     Q_VEG_CHAR_TOTAL  =  Q_VEG_CHAR_TOTAL + Q_VEG_CHAR
     TMP_VEG_NEW  = TMP_VEG_NEW - (MPV_MOIST_LOSS*H_VAP_H2O + MPV_VOLIT*H_PYR_VEG + & 
                                  PC%VEG_CHAR_ENTHALPY_FRACTION*Q_VEG_CHAR) / &
                                 (LP%VEG_MOIST_MASS*CP_H2O + CP_MASS_VEG_SOLID)
     TMP_VEG_NEW  = MIN(TMP_CHAR_MAX,TMP_VEG_NEW)
!print 1111,tmp_veg_new,mpv_moist,mpv_volit,q_veg_char,mpv_char_loss
!1111 format(2x,5(e15.5))
!    IF (MPV_VEG <= MPV_VEG_MIN) MPV_VOLIT = 0.0_EB

   ENDIF IF_NOT_IGNITOR1
 ENDIF IF_VEG_DEGRADATION_ARRHENIUS

 LP%TMP = TMP_VEG_NEW
!LP%TMP = TMP_VEG !TGA sets temperature
 LP%VEG_EMISS = 4.*SIGMA*LP%VEG_KAPPA*LP%TMP**4 !used in RTE solver

 MPV_CHAR_LOSS_TOTAL  = MPV_CHAR_LOSS_TOTAL  + MPV_CHAR_LOSS !needed for subcycling
 MPV_MOIST_LOSS_TOTAL = MPV_MOIST_LOSS_TOTAL + MPV_MOIST_LOSS !needed for subcycling
 MPV_VOLIT_TOTAL      = MPV_VOLIT_TOTAL      + MPV_VOLIT !needed for subcycling
 MPV_CHAR_CO2_TOTAL   = MPV_CHAR_CO2_TOTAL   + MPV_CHAR_CO2
 MPV_CHAR_O2_TOTAL    = MPV_CHAR_O2_TOTAL    + MPV_CHAR_O2
 MPV_ADDED = MPV_ADDED + MPV_MOIST_LOSS + MPV_VOLIT + MPV_CHAR_CO2 - MPV_CHAR_O2

! Check if critical mass flux condition is met
!IF (MPV_ADDED*RDT < VEG_CRITICAL_MASSSOURCE .AND. .NOT. LP%VEG_IGNITED) THEN
! MPV_ADDED      = 0.0_EB
! MW_AVERAGE     = 0.0_EB
! MPV_MOIST_LOSS = 0.0_EB
! MPV_VOLIT      = 0.0_EB
! Q_VEG_MOIST    = 0.0_EB
! Q_VEG_VOLIT    = 0.0_EB
!ELSE
! LP%VEG_IGNITED = .TRUE.
!ENDIF

! Add affects of fuel element thermal degradation of vegetation to velocity divergence

 CALL GET_SPECIFIC_HEAT(ZZ_GET,CP_GAS,TMP_GAS)
 RCP_GAS    = 1._EB/CP_GAS
 !MW_TERM    = MW_VEG_MOIST_TERM + MW_VEG_VOLIT_TERM
 MW_AVERAGE = R0/RSUM(II,JJ,KK)/RHO_GAS*(MW_VEG_MOIST_TERM + MW_VEG_VOLIT_TERM)
 Q_ENTHALPY = Q_VEG_MOIST + Q_VEG_VOLIT - (1.0_EB - PC%VEG_CHAR_ENTHALPY_FRACTION)*Q_VEG_CHAR

 !D_LAGRANGIAN(II,JJ,KK) = D_LAGRANGIAN(II,JJ,KK)  +           & 
 !                         (-FCTR_RDT_CYCLES*QCON_VEG*RCP_GAS + Q_ENTHALPY*RCP_GAS)/(RHO_GAS*TMP_GAS) + &
 !                         RDT*MW_AVERAGE 
 D_LAGRANGIAN(II,JJ,KK) = D_LAGRANGIAN(II,JJ,KK)  + RDT*Q_ENTHALPY*RCP_GAS/(RHO_GAS*TMP_GAS) + &
                          RDT*MW_AVERAGE 


 TMP_VEG   = TMP_VEG_NEW
 IF (MPV_MOIST <= MPV_MOIST_MIN) THEN !for time sub cycling
  MPV_MOIST = 0.0_EB
  MW_VEG_MOIST_TERM = 0.0_EB
  Q_VEG_MOIST = 0.0_EB
 ENDIF
 IF (MPV_VEG <= MPV_VEG_MIN) THEN
  MPV_VOLIT = 0.0_EB
  MPV_VEG   = 0.0_EB
  MW_VEG_VOLIT_TERM = 0.0_EB
  Q_VEG_VOLIT = 0.0_EB
 ENDIF

ENDDO TIME_SUBCYCLING_LOOP

 D_LAGRANGIAN(II,JJ,KK) = D_LAGRANGIAN(II,JJ,KK) + (-QCON_VEG*RCP_GAS)/(RHO_GAS*TMP_GAS)

 IF_NOT_IGNITOR2: IF (.NOT. LP%IGNITOR) THEN !add fuel,H2O,CO2 to mixture factions

! Add water vapor, fuel vapor, and CO2 mass to total density
! MPV_ADDED     = MPV_MOIST_LOSS + MPV_VOLIT + MPV_CHAR_CO2
  LP%VEG_MLR    = MPV_ADDED*RDT !kg/m^3/s used in FVX,FVY,FVZ along with drag in part.f90
  RHO(II,JJ,KK) = RHO_GAS + MPV_ADDED
  RRHO_GAS_NEW  = 1._EB/RHO(II,JJ,KK)
! print*,'NM =',NM
! print*,'** ',rho(ii,jj,kk)

! Add gas species created by degradation of vegetation Yi_new = (Yi_old*rho_old + change in rho_i)/rho_new
! Add water vapor mass from drying to water vapor mass fraction
  IF (I_WATER > 0) THEN 
!  ZZ(II,JJ,KK,I_WATER) = ZZ(II,JJ,KK,I_WATER) +  MPV_MOIST_LOSS*RRHO_GAS_NEW
   ZZ(II,JJ,KK,I_WATER) = ZZ(II,JJ,KK,I_WATER) + (MPV_MOIST_LOSS_TOTAL - MPV_ADDED*ZZ(II,JJ,KK,I_WATER))*RRHO_GAS_NEW
!  ZZ(II,JJ,KK,I_WATER) = MIN(1._EB,ZZ(II,JJ,KK,I_WATER))
!  DMPVDT_FM_VEG(II,JJ,KK,I_WATER) = DMPVDT_FM_VEG(II,JJ,KK,I_WATER) + RDT*MPV_MOIST_LOSS
  ENDIF

! Add fuel vapor mass from pyrolysis to fuel mass fraction
  I_FUEL = REACTION(1)%FUEL_SMIX_INDEX
  IF (I_FUEL /= 0) THEN 
!  ZZ(II,JJ,KK,I_FUEL) = ZZ(II,JJ,KK,I_FUEL) + MPV_VOLIT*RRHO_GAS_NEW
   ZZ(II,JJ,KK,I_FUEL) = ZZ(II,JJ,KK,I_FUEL) + (MPV_VOLIT_TOTAL - MPV_ADDED*ZZ(II,JJ,KK,I_FUEL))*RRHO_GAS_NEW
!  ZZ(II,JJ,KK,I_FUEL) = MIN(1._EB,ZZ(II,JJ,KK,I_FUEL))
!  DMPVDT_FM_VEG(II,JJ,KK,I_FUEL) = DMPVDT_FM_VEG(II,JJ,KK,I_FUEL) + RDT*MPV_VOLIT
  ENDIF

! Add CO2 mass, due to production during char oxidation, to CO2 mass fraction
  IF (I_CO2 /= -1 .AND. PC%VEG_CHAR_OXIDATION) THEN 
   ZZ(II,JJ,KK,I_CO2) = ZZ(II,JJ,KK,I_CO2) + (MPV_CHAR_CO2_TOTAL - MPV_ADDED*ZZ(II,JJ,KK,I_CO2))*RRHO_GAS_NEW
  ENDIF

! Remove O2 from gas due to char oxidation
!IF (PC%VEG_CHAR_OXIDATION) THEN 
! ZZ(II,JJ,KK,O2_INDEX) = ZZ(II,JJ,KK,O2_INDEX) - (MPV_CHAR_O2_TOTAL - MPV_ADDED*ZZ(II,JJ,KK,I_CO2))*RRHO_GAS_NEW
! ZZ(II,JJ,KK,O2_INDEX) = MAX(0.0_EB,ZZ(II,JJ,KK,O2_INDEX))
!ENDIF

 ENDIF IF_NOT_IGNITOR2

! WRITE(9998,'(A)')'T,TMP_VEG,QCON_VEG,QRAD_VEG'
!IF (II==0.5*IBAR .AND. JJ==0.5*JBAR .AND. KK==0.333*KBAR) THEN
!IF (II==12 .AND. JJ==12 .AND. KK==4) THEN 
!IF (II==20 .AND. JJ==20 .AND. KK==25) THEN !M=14% and 49% element burnout
!IF (II==27 .AND. JJ==20 .AND. KK==7) THEN !M=49% not full element burnout
! WRITE(9998,'(9(ES12.4))')T,TMP_GAS,TMP_VEG,QCON_VEG,QRAD_VEG,LP%VEG_MOIST_MASS,LP%VEG_FUEL_MASS, &
!                          MPV_MOIST_LOSS_MAX*RDT,MPV_VOLIT_MAX*RDT
!ENDIF

! V_VEG               = V_VEG + V_CELL
! TOTAL_MASS_MOIST    = TOTAL_MASS_MOIST + LP%VEG_MOIST_MASS*V_CELL
! TOTAL_MASS_DRY_FUEL = TOTAL_MASS_DRY_FUEL + LP%VEG_FUEL_MASS*V_CELL

 ENDIF THERMAL_CALC  ! end of thermally thin heat transfer, etc. calculations

! Fill arrays for outputting vegetation variables when OUTPUT_TREE=.TRUE.
 N_TREE = LP%VEG_N_TREE_OUTPUT
 IF (N_TREE /= 0) THEN
  TREE_OUTPUT_DATA(N_TREE,1,NM) = TREE_OUTPUT_DATA(N_TREE,1,NM) + LP%TMP - 273._EB !C
  TREE_OUTPUT_DATA(N_TREE,2,NM) = TREE_OUTPUT_DATA(N_TREE,2,NM) + TMP_GAS - 273._EB !C
  TREE_OUTPUT_DATA(N_TREE,3,NM) = TREE_OUTPUT_DATA(N_TREE,3,NM) + LP%VEG_FUEL_MASS*V_CELL*VEG_VF !kg
  TREE_OUTPUT_DATA(N_TREE,4,NM) = TREE_OUTPUT_DATA(N_TREE,4,NM) + LP%VEG_MOIST_MASS*V_CELL*VEG_VF !kg
  TREE_OUTPUT_DATA(N_TREE,5,NM) = TREE_OUTPUT_DATA(N_TREE,5,NM) + LP%VEG_CHAR_MASS*V_CELL*VEG_VF !kg
  TREE_OUTPUT_DATA(N_TREE,6,NM) = TREE_OUTPUT_DATA(N_TREE,6,NM) + LP%VEG_ASH_MASS*V_CELL*VEG_VF !kg
  TREE_OUTPUT_DATA(N_TREE,7,NM) = TREE_OUTPUT_DATA(N_TREE,7,NM) + LP%VEG_DIVQC*V_CELL*0.001_EB !kW
  TREE_OUTPUT_DATA(N_TREE,8,NM) = TREE_OUTPUT_DATA(N_TREE,8,NM) + LP%VEG_DIVQR*V_CELL*0.001_EB !kW
  TREE_OUTPUT_DATA(N_TREE,9,NM) = TREE_OUTPUT_DATA(N_TREE,9,NM) + 1._EB !number of particles
  TREE_OUTPUT_DATA(N_TREE,10,NM) = TREE_OUTPUT_DATA(N_TREE,10,NM) + MPV_CHAR_LOSS_TOTAL*V_CELL !kg 
  TREE_OUTPUT_DATA(N_TREE,11,NM) = TREE_OUTPUT_DATA(N_TREE,11,NM) - Q_VEG_CHAR_TOTAL*V_CELL*RDT*0.001_EB !kW

! TREE_OUTPUT_DATA(N_TREE,10,NM) = TREE_OUTPUT_DATA(N_TREE,10,NM) + NUSS_HILPERT_CYL_FORCEDCONV
! TREE_OUTPUT_DATA(N_TREE,11,NM) = TREE_OUTPUT_DATA(N_TREE,11,NM) + NUSS_MORGAN_CYL_FREECONV 

! TREE_OUTPUT_DATA(N_TREE,4,NM) = TREE_OUTPUT_DATA(N_TREE,4,NM) + LP%VEG_PACKING_RATIO
! TREE_OUTPUT_DATA(N_TREE,5,NM) = TREE_OUTPUT_DATA(N_TREE,5,NM) + LP%VEG_SV

 ENDIF

ENDDO PARTICLE_LOOP

!print*,'--------------------------------'
!print '(A,1x,I2,1x,ES12.4)','vege:nm,tree_output divqc ',nm,tree_output_data(1,7,nm)

! Write out total bulk
!TOTAL_BULKDENS_MOIST = TOTAL_MASS_MOIST/V_VEG
!TOTAL_BULKDENS_DRY_FUEL = TOTAL_MASS_DRY_FUEL/V_VEG
!WRITE(9999,'(5(ES12.4))')T,TOTAL_BULKDENS_DRY_FUEL,TOTAL_BULKDENS_MOIST,TOTAL_MASS_DRY_FUEL,TOTAL_MASS_MOIST

!VEG_TOTAL_DRY_MASS(NM)   = TOTAL_MASS_DRY_FUEL
!VEG_TOTAL_MOIST_MASS(NM) = TOTAL_MASS_MOIST

! Remove vegetation that has completely burned (i.e., LP%R has been set equal to zero)
CALL REMOVE_PARTICLES(T,NM)
 
END SUBROUTINE RAISED_VEG_MASS_ENERGY_TRANSFER

! ***********************************************************************************************
SUBROUTINE BNDRY_VEG_MASS_ENERGY_TRANSFER(T,NM)
! ***********************************************************************************************
!
! Issues:
! 1. Are SF%VEG_FUEL_FLUX_L and SF%VEG_MOIST_FLUX_L needed in linear degradation model?
USE PHYSICAL_FUNCTIONS, ONLY : DRAG,GET_MASS_FRACTION,GET_SPECIFIC_HEAT,GET_VISCOSITY,GET_CONDUCTIVITY
REAL(EB) :: ZZ_GET(0:N_TRACKED_SPECIES)
REAL(EB) :: DT_BC,RDT_BC
REAL(EB), INTENT(IN) :: T
INTEGER,  INTENT(IN) :: NM
INTEGER  ::  IW
INTEGER  ::  I,IIG,JJG,KKG,KKG_L,KGRID,KLOC_GAS
REAL(EB) :: CP_GAS,CP_MOIST_AND_VEG,DZVEG_L,ETAVEG_H,H_CONV_L, &
            KAPPA_VEG,K_GAS,MU_GAS,QRADM_INC,QRADP_INC,RHO_GAS, &
            TMP_BOIL,TMP_CHAR_MAX,TMP_FILM,TMP_G,DTMP_L,RE_VEG_PART,U2,V2,RE_D,Y_O2,ZVEG,ZLOC_GAS_B,ZLOC_GAS_T
!REAL(EB) :: H_CONV_FDS_WALL,DTMP_FDS_WALL,QCONF_FDS_WALL,LAMBDA_AIR,TMPG_A
INTEGER  IIVEG_L,IVEG_L,J,LBURN,LBURN_NEW,NVEG_L,I_FUEL
!REAL(EB), ALLOCATABLE, DIMENSION(:) :: VEG_DIV_QRNET_EMISS,VEG_DIV_QRNET_INC,
!         VEG_QRNET_EMISS,VEG_QRNET_INC,VEG_QRM_EMISS,VEG_QRP_EMISS, VEG_QRM_INC,VEG_QRP_INC
REAL(EB) :: VEG_DIV_QRNET_EMISS(50),VEG_DIV_QRNET_INC(50),VEG_QRNET_EMISS(0:50),VEG_QRNET_INC(0:50), &
            VEG_QRM_EMISS(0:50),VEG_QRP_EMISS(0:50), VEG_QRM_INC(0:50),VEG_QRP_INC(0:50)
REAL(EB) :: H_H2O_VEG,A_H2O_VEG,E_H2O_VEG,H_PYR_VEG,A_PYR_VEG,E_PYR_VEG,RH_PYR_VEG,                  &
            H_CHAR_VEG,A_CHAR_VEG,E_CHAR_VEG,BETA_CHAR_VEG,NU_CHAR_VEG,NU_ASH_VEG,NU_O2_CHAR_VEG
REAL(EB) :: CP_ASH,CP_CHAR,CP_H2O,CP_VEG,CP_TOTAL,DTMP_VEG,Q_VEG_CHAR,TMP_VEG,TMP_VEG_NEW, &
            CHAR_ENTHALPY_FRACTION_VEG
REAL(EB) :: CHAR_FCTR,CHAR_FCTR2,MPA_MOIST,MPA_MOIST_LOSS,MPA_MOIST_LOSS_MAX,MPA_MOIST_MIN,DMPA_VEG, &
            MPA_CHAR,MPA_VEG,MPA_CHAR_MIN,MPA_VEG_MIN,MPA_VOLIT,MPA_VOLIT_LOSS_MAX,MPA_CHAR_LOSS,MPA_ASH
REAL(EB) :: DETA_VEG,ETA_H,ETAFM_VEG,ETAFP_VEG,VEG_TMP_FACE
REAL(EB) :: QCONF_L,QCONF_TOP,Q_FOR_DRYING,Q_UPTO_DRYING,Q_VEG_MOIST,Q_VEG_VOLIT,QNET_VEG,Q_FOR_VOLIT,Q_VOLIT,Q_UPTO_VOLIT
REAL(EB) :: C_DRAG,CM,CN,NUSS_HILPERT_CYL_FORCEDCONV,NUSS_MORGAN_CYL_FREECONV,HCON_VEG_FORCED,HCON_VEG_FREE,LENGTH_SCALE,RAYLEIGH_NUM, &
            ZGRIDCELL,ZGRIDCELL0,VEG_DRAG_RAMP_FCTR,VEG_DRAG_MIN
REAL(EB) :: MU_AIR,K_AIR
!LOGICAL  :: H_VERT_CYLINDER_LAMINAR,H_CYLINDER_RE

INTEGER  :: IC,II,IOR,JJ,KK,IW_CELL

TYPE (WALL_TYPE),    POINTER :: WC =>NULL()
TYPE (SURFACE_TYPE), POINTER :: SF =>NULL()

TYPE (WALL_TYPE),    POINTER :: WC1 =>NULL() !to handle qrad on slopes
TYPE (SURFACE_TYPE), POINTER :: SF1 =>NULL() !to handle qrad on slopes

CALL POINT_TO_MESH(NM)

IF (VEG_LEVEL_SET_COUPLED .OR. VEG_LEVEL_SET_UNCOUPLED) RETURN

TMP_BOIL          = 373._EB
TMP_CHAR_MAX      = 1300._EB
CP_ASH            = 800._EB !J/kg/K specific heat of ash
CP_H2O            = 4190._EB !J/kg/K specific heat of water
DT_BC             = T - VEG_CLOCK_BC
RDT_BC            = 1.0_EB/DT_BC
VEG_DRAG(:,:,1:8) = 0.0_EB
!VEG_DRAG(:,:,0) = -1.0_EB !default value when no veg is present (set in init.f90)

IF (N_REACTIONS>0) I_FUEL = REACTION(1)%FUEL_SMIX_INDEX

! Loop through vegetation wall cells and burn
!
VEG_WALL_CELL_LOOP: DO IW=1,N_EXTERNAL_WALL_CELLS+N_INTERNAL_WALL_CELLS
  WC  => WALL(IW)
  IF (WC%BOUNDARY_TYPE==NULL_BOUNDARY) CYCLE VEG_WALL_CELL_LOOP

  SF  => SURFACE(WC%SURF_INDEX)
!
  IF (.NOT. SF%VEGETATION) CYCLE VEG_WALL_CELL_LOOP

  H_H2O_VEG = SF%VEG_H_H2O !J/kg
  H_PYR_VEG = SF%VEG_H_PYR !J/kg
  RH_PYR_VEG = 1._EB/H_PYR_VEG
  CHAR_FCTR  = 1._EB - SF%VEG_CHAR_FRACTION
  CHAR_FCTR2 = 1._EB/CHAR_FCTR

!Gas quantities 
  IIG = WC%IIG
  JJG = WC%JJG
  KKG = WC%KKG
  TMP_G = TMP(IIG,JJG,KKG)
  IF(SF%VEG_NO_BURN .OR. T <= DT_BC) WC%VEG_HEIGHT = SF%VEG_HEIGHT
  VEG_DRAG(IIG,JJG,0) = REAL(KKG,EB) !for terrain location in drag calc in velo.f90

!-- Simple Drag implementation for BF, assumes veg height is <= grid cell height.
!   No Reynolds number dependence
!VEG_DRAG(IIG,JJG,1) = SF%VEG_DRAG_INI*(SF%VEG_CHAR_FRACTION + CHAR_FCTR*WC%VEG_HEIGHT/SF%VEG_HEIGHT)
!VEG_DRAG(IIG,JJG,1) = VEG_DRAG(IIG,JJG,1)*SF%VEG_HEIGHT/(Z(KKG)-Z(KKG-1))

!-- BF Drag varies with height above the terrain according to the fraction of the grid cell occupied by veg
!   veg height can be < or >= than grid cell height, drag is Reynolds number dependent when VEG_UNIT_DRAG_COEFF
!   is FALSE.
!   Implemented in velo.f90 
!   KKG is the grid cell in the gas phase bordering the terrain (wall). For no terrain, KKG=1 along the "ground" 
!   The Z() array is the height of the gas-phase cell. Z(0) = zmin for the current mesh 

  BF_DRAG: IF (WC%VEG_HEIGHT > 0.0_EB) THEN
 
    VEG_DRAG_RAMP_FCTR = 1.0_EB
!   IF (T-T_BEGIN <= 5.0_EB) VEG_DRAG_RAMP_FCTR = 0.20_EB*(T-T_BEGIN)

    DO KGRID=0,5
      KLOC_GAS   = KKG + KGRID            !gas-phase grid index
      ZLOC_GAS_T = Z(KLOC_GAS)  -Z(KKG-1) !height above terrain of gas-phase grid cell top
      ZLOC_GAS_B = Z(KLOC_GAS-1)-Z(KKG-1) !height above terrain of gas-phase grid cell bottom

      IF (ZLOC_GAS_T <= WC%VEG_HEIGHT) THEN !grid cell filled with veg
        IF (.NOT. SF%VEG_UNIT_DRAG_COEFF) THEN
          TMP_G = TMP(IIG,JJG,KLOC_GAS)
          RHO_GAS  = RHO(IIG,JJG,KLOC_GAS)
          ZZ_GET(1:N_TRACKED_SPECIES) = ZZ(IIG,JJG,KLOC_GAS,1:N_TRACKED_SPECIES)
          CALL GET_VISCOSITY(ZZ_GET,MU_GAS,TMP_G)
          U2 = 0.25*(U(IIG,JJG,KLOC_GAS)+U(IIG-1,JJG,KLOC_GAS))**2
          V2 = 0.25*(V(IIG,JJG,KLOC_GAS)+V(IIG,JJG-1,KLOC_GAS))**2
          RE_VEG_PART = 4._EB*RHO_GAS*SQRT(U2 + V2 + W(IIG,JJG,KLOC_GAS)**2)/SF%VEG_SV/MU_GAS !for cylinder particle
          C_DRAG = 0.0_EB
          IF (RE_VEG_PART > 0.0_EB) C_DRAG = DRAG(RE_VEG_PART,2) !2 is for cylinder, 1 is for sphere
        ELSE
          C_DRAG = 1.0_EB
        ENDIF
        VEG_DRAG(IIG,JJG,KGRID+1)= C_DRAG*SF%VEG_DRAG_INI*VEG_DRAG_RAMP_FCTR

      ENDIF

      IF (ZLOC_GAS_T >  WC%VEG_HEIGHT .AND. ZLOC_GAS_B < WC%VEG_HEIGHT) THEN !grid cell is partially filled with veg
        IF (.NOT. SF%VEG_UNIT_DRAG_COEFF) THEN
          TMP_G = TMP(IIG,JJG,KLOC_GAS)
          RHO_GAS  = RHO(IIG,JJG,KLOC_GAS)
          ZZ_GET(1:N_TRACKED_SPECIES) = ZZ(IIG,JJG,KLOC_GAS,1:N_TRACKED_SPECIES)
          CALL GET_VISCOSITY(ZZ_GET,MU_GAS,TMP_G)
          U2 = 0.25*(U(IIG,JJG,KLOC_GAS)+U(IIG-1,JJG,KLOC_GAS))**2
          V2 = 0.25*(V(IIG,JJG,KLOC_GAS)+V(IIG,JJG-1,KLOC_GAS))**2
          RE_VEG_PART = 4._EB*RHO_GAS*SQRT(U2 + V2 + W(IIG,JJG,KLOC_GAS)**2)/SF%VEG_SV/MU_GAS !for cylinder particle
          C_DRAG = 0.0_EB
          IF (RE_VEG_PART > 0.0_EB) C_DRAG = DRAG(RE_VEG_PART,2) !2 is for cylinder, 1 is for sphere
        ELSE
          C_DRAG = 1.0_EB
        ENDIF
        VEG_DRAG(IIG,JJG,KGRID+1)= &
                   C_DRAG*SF%VEG_DRAG_INI*(WC%VEG_HEIGHT-ZLOC_GAS_B)*VEG_DRAG_RAMP_FCTR/(ZLOC_GAS_T-ZLOC_GAS_B)

        IF (KGRID == 0) THEN !compute minimum drag based on user input
         VEG_DRAG_MIN = C_DRAG*SF%VEG_DRAG_INI*SF%VEG_POSTFIRE_DRAG_FCTR*VEG_DRAG_RAMP_FCTR* &
                          SF%VEG_HEIGHT/(ZLOC_GAS_T-ZLOC_GAS_B)
         VEG_DRAG(IIG,JJG,1) = MAX(VEG_DRAG(IIG,JJG,1),VEG_DRAG_MIN)
        ENDIF
!if(iig==20.and.jjg==20)print '(A,1x,4ES12.3)','C_DRAG,DRAG_INI,RAMP_FACTR,VEG_DRAG', &
!   C_DRAG,SF%VEG_DRAG_INI,VEG_DRAG_RAMP_FCTR,veg_drag(iig,jjg,1)
      ENDIF

    ENDDO

! ELSE IF (WC%VEG_HEIGHT == 0.0_EB) THEN !veg is burned away, approx drag as SF%VEG_POSTFIRE_DRAG_FCTR*original
!   IF (.NOT. SF%VEG_UNIT_DRAG_COEFF) THEN
!     TMP_G = TMP(IIG,JJG,KKG)
!     RHO_GAS  = RHO(IIG,JJG,KKG)
!     ZZ_GET(1:N_TRACKED_SPECIES) = ZZ(IIG,JJG,KKG,1:N_TRACKED_SPECIES)
!     CALL GET_VISCOSITY(ZZ_GET,MU_GAS,TMP_G)
!     U2 = 0.25*(U(IIG,JJG,KKG)+U(IIG-1,JJG,KKG))**2
!     V2 = 0.25*(V(IIG,JJG,KKG)+V(IIG,JJG-1,KKG))**2
!     RE_VEG_PART = 4._EB*RHO_GAS*SQRT(U2 + V2 + W(IIG,JJG,KKG)**2)/SF%VEG_SV/MU_GAS !for cylinder particle
!     C_DRAG = 0.0_EB
!     IF (RE_VEG_PART > 0.0_EB) C_DRAG = DRAG(RE_VEG_PART,2) !2 is for cylinder, 1 is for sphere
!   ELSE
!     C_DRAG = 1.0_EB
!   ENDIF
!   VEG_DRAG(IIG,JJG,1)= C_DRAG*SF%VEG_DRAG_INI*SF%VEG_POSTFIRE_DRAG_FCTR*VEG_DRAG_RAMP_FCTR

  ENDIF BF_DRAG

  IF(SF%VEG_NO_BURN) CYCLE VEG_WALL_CELL_LOOP

! Initialize quantities
  Q_VEG_MOIST     = 0.0_EB
  Q_VEG_VOLIT     = 0.0_EB
  Q_UPTO_VOLIT    = 0.0_EB
  Q_VOLIT         = 0.0_EB
  Q_VEG_CHAR      = 0.0_EB
  MPA_MOIST_LOSS  = 0.0_EB
  MPA_VOLIT       = 0.0_EB
  MPA_CHAR_LOSS   = 0.0_EB
  SF%VEG_DIVQNET_L          = 0.0_EB
  SF%VEG_MOIST_FLUX_L       = 0.0_EB
  SF%VEG_FUEL_FLUX_L        = 0.0_EB
  WC%MASSFLUX(I_FUEL)       = 0.0_EB 
! WC%QCONF           = 0.0_EB
  WC%LSET_FIRE       = .FALSE.

  IF (I_WATER > 0) WC%MASSFLUX(I_WATER) = 0.0_EB

  IF(WC%VEG_HEIGHT == 0.0_EB) THEN
    WALL(IW)%TMP_F = MAX(TMP(IIG,JJG,KKG),TMPA) !Tveg=Tgas if veg is completely burned
    CYCLE VEG_WALL_CELL_LOOP
  ENDIF

! Vegetation variables and minimum bounds
  NVEG_L = SF%NVEG_L
  LBURN  = 0
!  Mininum bound on dry veg. Older approach, linear pyrolysis and no char
! MPA_VEG_MIN   = SF%VEG_CHARFRAC*SF%VEG_LOAD / REAL(NVEG_L,EB) !kg/m^2
!  Minimum bound on dry veg.Newer, linear or Arrhenius degradation and char
  MPA_VEG_MIN   = 0.001_EB*SF%VEG_LOAD/REAL(NVEG_L,EB) !kg/m^2

  MPA_CHAR_MIN  = SF%VEG_CHAR_FRACTION*MPA_VEG_MIN !kg/m^2
  MPA_MOIST_MIN = 0.0001_EB*SF%VEG_MOISTURE*SF%VEG_LOAD/REAL(NVEG_L,EB) !ks/m^2

  IF (SF%VEG_MOISTURE == 0.0_EB) MPA_MOIST_MIN = MPA_VEG_MIN
  DZVEG_L   = SF%VEG_HEIGHT/REAL(NVEG_L,EB)
  KAPPA_VEG = SF%VEG_KAPPA
  DETA_VEG  = DZVEG_L*KAPPA_VEG

! Find the number of computational grids cells, in the grid for the veg, with burned veg 
! and the resulting height of the unburned veg. 
! Vegetation burns downward from the top. Array index, IVEG_L for WC% quantities, starts at top of veg top.
! LBURN is the number of computational cells with burned veg. 
! LBURN=0 when no burning has occurred. 
! LBURN=2, for example, means the top two veg grid cells have burned
! LBURN = NVEG_L when veg is completely burned away

  IF (SF%VEG_CHAR_OXIDATION) THEN
    DO IVEG_L = 1,NVEG_L 
      IF(WC%VEG_CHARMASS_L(IVEG_L) <= MPA_CHAR_MIN .AND. WC%VEG_FUELMASS_L(IVEG_L) <= MPA_VEG_MIN ) LBURN = IVEG_L
    ENDDO
  ELSE
    DO IVEG_L = 1,NVEG_L 
      IF(WC%VEG_FUELMASS_L(IVEG_L) <= MPA_VEG_MIN) LBURN = IVEG_L
    ENDDO
  ENDIF

  LBURN_NEW          = LBURN
  WC%VEG_HEIGHT      = REAL(NVEG_L-LBURN,EB)*DZVEG_L
! LBURN = 0 !keep charred veg
  !FIRELINE_MLR_MAX = w*R*(1-ChiChar)
  MPA_VOLIT_LOSS_MAX = SF%FIRELINE_MLR_MAX*DT_BC*DZVEG_L 
  MPA_MOIST_LOSS_MAX = MPA_VOLIT_LOSS_MAX

! Determine the gas-phase vertical grid cell index, SF%VEG_KGAS_L, for each cell in the vegetation grid. 
! This is needed for cases in which the vegetation height is larger than the height of the first gas-phase grid cell
! The WC% and SF% indices are related. As the WC% index goes from LBURN+1 to NVEG_L the SF% index goes 
! from 1 to NVEG_L - LBURN.
! Also, with increasing index value in WC% and SF% we pass from the top of the vegetation to the bottom

  DO IVEG_L = 1, NVEG_L - LBURN
   SF%VEG_KGAS_L(NVEG_L-LBURN-IVEG_L+1) = KKG 
   ZVEG = REAL(IVEG_L,EB)*DZVEG_L 
   ZGRIDCELL0 = 0.0_EB
   DO KGRID = 0,5
     ZGRIDCELL = ZGRIDCELL0 + Z(KKG+KGRID) - Z(KKG+KGRID-1)
     IF (ZVEG > ZGRIDCELL0 .AND. ZVEG <= ZGRIDCELL) SF%VEG_KGAS_L(NVEG_L-LBURN-IVEG_L+1) = KKG + KGRID
     ZGRIDCELL0 = ZGRIDCELL
   ENDDO
  ENDDO

! Factors for computing divergence of incident and self emission radiant fluxes
! in vegetation fuel bed. These need to be recomputed as the height of the
! vegetation surface layer decreases with burning

! Factors for computing decay of +/- incident fluxes
  SF%VEG_FINCM_RADFCT_L(:) =  0.0_EB
  SF%VEG_FINCP_RADFCT_L(:) =  0.0_EB
  ETA_H = KAPPA_VEG*WC%VEG_HEIGHT

  DO IVEG_L = 0,NVEG_L - LBURN
    ETAFM_VEG = REAL(IVEG_L,EB)*DETA_VEG
    ETAFP_VEG = ETA_H - ETAFM_VEG
    SF%VEG_FINCM_RADFCT_L(IVEG_L) = EXP(-ETAFM_VEG)
    SF%VEG_FINCP_RADFCT_L(IVEG_L) = EXP(-ETAFP_VEG)
  ENDDO

!  Integrand for computing +/- self emission fluxes
  SF%VEG_SEMISSP_RADFCT_L(:,:) = 0.0_EB
  SF%VEG_SEMISSM_RADFCT_L(:,:) = 0.0_EB
! q+
  DO IIVEG_L = 0,NVEG_L-LBURN !veg grid coordinate
    DO IVEG_L = IIVEG_L,NVEG_L-1-LBURN !integrand index
!    ETAG_VEG = IIVEG_L*DETA_VEG
!    ETAI_VEG =  IVEG_L*DETA_VEG
!    SF%VEG_SEMISSP_RADFCT_L(IVEG_L,IIVEG_L) = EXP(-(ETAI_VEG-ETAG_VEG))
     ETAFM_VEG = REAL((IVEG_L-IIVEG_L),EB)*DETA_VEG
     ETAFP_VEG = ETAFM_VEG + DETA_VEG
!    SF%VEG_SEMISSP_RADFCT_L(IVEG_L,IIVEG_L) = EXP(-ETAFM_VEG) - EXP(-ETAFP_VEG)
     SF%VEG_SEMISSP_RADFCT_L(IVEG_L,IIVEG_L) = EXP(-ETAFM_VEG)*(1.0_EB - EXP(-DETA_VEG))
    ENDDO
  ENDDO
! q-
  DO IIVEG_L = 0,NVEG_L-LBURN
    DO IVEG_L = 1,IIVEG_L
!    ETAG_VEG = IIVEG_L*DETA_VEG
!    ETAI_VEG =  IVEG_L*DETA_VEG
!    SF%VEG_SEMISSM_RADFCT_L(IVEG_L,IIVEG_L) = EXP(-(ETAG_VEG-ETAI_VEG))
     ETAFM_VEG = REAL((IIVEG_L-IVEG_L),EB)*DETA_VEG
     ETAFP_VEG = ETAFM_VEG + DETA_VEG
!    SF%VEG_SEMISSM_RADFCT_L(IVEG_L,IIVEG_L) = EXP(-ETAFM_VEG) - EXP(-ETAFP_VEG)
     SF%VEG_SEMISSM_RADFCT_L(IVEG_L,IIVEG_L) = EXP(-ETAFM_VEG)*(1.0_EB - EXP(-DETA_VEG))
    ENDDO
  ENDDO
!
! -----------------------------------------------
! compute CONVECTIVE HEAT FLUX on vegetation
! -----------------------------------------------
! Divergence of convective and radiative heat fluxes

  DO I=1,NVEG_L-LBURN
    KKG_L  = SF%VEG_KGAS_L(I)
    TMP_G  = TMP(IIG,JJG,KKG_L)
    DTMP_L = TMP_G - WC%VEG_TMP_L(I+LBURN)

!Convective heat correlation for laminar flow (Holman see ref above) 
    IF (SF%VEG_HCONV_CYLLAM) H_CONV_L = 1.42_EB*(ABS(DTMP_L)/DZVEG_L)**0.25

!Convective heat correlation that accounts for air flow using forced convection correlation for
!a cylinder in a cross flow, Hilpert Correlation; Incropera & Dewitt Forth Edition p. 370
    IF(SF%VEG_HCONV_CYLRE) THEN 
     RHO_GAS  = RHO(IIG,JJG,KKG_L)
     TMP_FILM = 0.5_EB*(TMP_G + WC%VEG_TMP_L(I+LBURN))
     ZZ_GET(1:N_TRACKED_SPECIES) = ZZ(IIG,JJG,KKG_L,1:N_TRACKED_SPECIES)
     CALL GET_VISCOSITY(ZZ_GET,MU_GAS,TMP_FILM)
     CALL GET_CONDUCTIVITY(ZZ_GET,K_GAS,TMP_FILM) !W/m/K
!    MU_AIR   = MU_Z(MIN(5000,NINT(TMP_FILM)),0)*SPECIES_MIXTURE(0)%MW
     U2 = 0.25*(U(IIG,JJG,KKG_L)+U(IIG-1,JJG,KKG_L))**2
     V2 = 0.25*(V(IIG,JJG,KKG_L)+V(IIG,JJG-1,KKG_L))**2
!    K_AIR    = CPOPR*MU_AIR !W/(m.K)
     RE_VEG_PART = 4._EB*RHO_GAS*SQRT(U2 + V2 + W(IIG,JJG,KKG_L)**2)/SF%VEG_SV/MU_GAS

     IF(RE_VEG_PART < 4._EB) THEN
       CN = 0.989_EB
       CM = 0.330_EB
     ELSE IF (RE_VEG_PART >= 4._EB .AND. RE_VEG_PART < 40._EB) THEN
       CN = 0.911_EB
       CM = 0.385_EB
     ELSE
       CN = 0.683_EB
       CM = 0.466_EB
     ENDIF
     H_CONV_L = 0.25_EB*SF%VEG_SV*K_GAS*CN*(RE_VEG_PART**CM)*PR_ONTH !W/K/m^2
    ENDIF
!
! Use largest of natural and forced convective heat transfer
   
    IF(SF%VEG_HCONV_CYLMAX) THEN 
      RHO_GAS  = RHO(IIG,JJG,KKG_L)
      TMP_FILM = 0.5_EB*(TMP_G + WC%VEG_TMP_L(I+LBURN))
      ZZ_GET(1:N_TRACKED_SPECIES) = ZZ(IIG,JJG,KKG_L,1:N_TRACKED_SPECIES)
      CALL GET_VISCOSITY(ZZ_GET,MU_GAS,TMP_FILM)
      CALL GET_SPECIFIC_HEAT(ZZ_GET,CP_GAS,TMP_FILM)
      CALL GET_CONDUCTIVITY(ZZ_GET,K_GAS,TMP_FILM)
      U2 = 0.25*(U(IIG,JJG,KKG_L)+U(IIG-1,JJG,KKG_L))**2
      V2 = 0.25*(V(IIG,JJG,KKG_L)+V(IIG,JJG-1,KKG_L))**2
      RE_VEG_PART = 4._EB*RHO_GAS*SQRT(U2 + V2 + W(IIG,JJG,KKG_L)**2)/SF%VEG_SV/MU_GAS !for cylinder SV

! - Forced convection heat transfer coefficients in a layer
!
! Hilpert Correlation (Incropera & DeWitt Fourth Edition, p. 370) for cylinder in crossflow,
! forced convection
      IF(RE_VEG_PART < 4._EB) THEN
        CN = 0.989_EB
        CM = 0.330_EB
      ELSE IF (RE_VEG_PART >= 4._EB .AND. RE_VEG_PART < 40._EB) THEN
        CN = 0.911_EB
        CM = 0.385_EB
      ELSE
        CN = 0.683_EB
        CM = 0.466_EB
      ENDIF
      NUSS_HILPERT_CYL_FORCEDCONV = CN*(RE_VEG_PART**CM)*PR_ONTH !Nusselt number
      HCON_VEG_FORCED = 0.25_EB*SF%VEG_SV*K_GAS*NUSS_HILPERT_CYL_FORCEDCONV !W/m^2 from Hilpert (cylinder)

! - Free convection heat transfer coefficients
      LENGTH_SCALE = 4._EB/SF%VEG_SV !horizontal cylinder diameter
      RAYLEIGH_NUM = 9.8_EB*ABS(DTMP_L)*LENGTH_SCALE**3*RHO_GAS**2*CP_GAS/(TMP_FILM*MU_GAS*K_GAS)

! Morgan correlation (Incropera & DeWitt, 4th Edition, p. 501-502) for horizontal cylinder, free convection
      IF (RAYLEIGH_NUM < 0.01_EB) THEN
        CN = 0.675_EB
        CM = 0.058_EB
      ELSE IF (RAYLEIGH_NUM >= 0.01_EB .AND. RAYLEIGH_NUM < 100._EB) THEN
        CN = 1.02_EB
        CM = 0.148_EB
      ELSE IF (RAYLEIGH_NUM >= 100._EB .AND. RAYLEIGH_NUM < 10**4._EB) THEN
        CN = 0.85_EB
        CM = 0.188_EB
      ELSE IF (RAYLEIGH_NUM >= 10**4._EB .AND. RAYLEIGH_NUM < 10**7._EB) THEN
        CN = 0.48_EB
        CM = 0.25_EB
      ELSE IF (RAYLEIGH_NUM >= 10**7._EB .AND. RAYLEIGH_NUM < 10**12._EB) THEN
        CN = 0.125_EB
        CM = 0.333_EB
      ENDIF

      NUSS_MORGAN_CYL_FREECONV = CN*RAYLEIGH_NUM**CM
      HCON_VEG_FREE = 0.25_EB*SF%VEG_SV*K_GAS*NUSS_MORGAN_CYL_FREECONV !W/K/m^2

      H_CONV_L = MAX(HCON_VEG_FORCED,HCON_VEG_FREE)
    ENDIF

    QCONF_L  = H_CONV_L*DTMP_L
    IF (I == LBURN+1) QCONF_TOP = QCONF_L
    SF%VEG_DIVQNET_L(I) = SF%VEG_PACKING*SF%VEG_SV*QCONF_L*DZVEG_L !W/m^2 see Mell et al. 2007 IJWF accessory pub

  ENDDO
!
! If SF%THERMAL_BC_INDEX = SPECIFIED_TEMPERATURE for veg, then WALL(IW)%QCONF is determined in wall.f90 sub THERMAL_BC
! WALL(IW)%QCONF = -SUM(SF%VEG_DIVQNET_L)*DZVEG_L !negative because seen by gas
! WALL(IW)%QCONF = -SF%VEG_DIVQNET_L(LBURN+1)*DZVEG_L 
! WALL(IW)%QCONF = -QCONF_TOP      
! qconf(iw) = 0.0_EB
!
! -----------------------------------------------
! Compute +/- radiation fluxes and their divergence due to self emission within vegetation
! -----------------------------------------------
!
! WC%VEG_TMP_L(LBURN) = 0.5_EB*(WC%VEG_TMP_L(LBURN+1)+TMP_G) !Approx. value of Tveg at top of veg

  LAYER_RAD_FLUXES: IF (LBURN < NVEG_L) THEN
    VEG_QRP_EMISS   = 0.0_EB ; VEG_QRM_EMISS = 0.0_EB 
    VEG_QRNET_EMISS = 0.0_EB ; VEG_DIV_QRNET_EMISS = 0.0_EB
! qe+
    DO J=0,NVEG_L-LBURN !veg grid coordinate loop
      DO I=J,NVEG_L-LBURN !integrand loop 
!        VEG_QRP_EMISS(J) =  VEG_QRP_EMISS(J) + SF%VEG_SEMISSP_RADFCT_L(I,J)*WC%VEG_TMP_L(I+LBURN)**4
         IF (I==0) THEN
           KKG_L = SF%VEG_KGAS_L(1)
         ELSE
           KKG_L = SF%VEG_KGAS_L(I)
         ENDIF
         TMP_G = TMP(IIG,JJG,KKG_L)
         WC%VEG_TMP_L(LBURN)    = TMP_G !for top of fuel bed
         WC%VEG_TMP_L(NVEG_L+1) = WC%VEG_TMP_L(NVEG_L) !for bottom of fuel bed
         VEG_TMP_FACE = 0.5_EB*(WC%VEG_TMP_L(I+LBURN)+WC%VEG_TMP_L(I+LBURN+1))
         VEG_QRP_EMISS(J) =  VEG_QRP_EMISS(J) + SF%VEG_SEMISSP_RADFCT_L(I,J)*VEG_TMP_FACE**4
      ENDDO
    ENDDO
! qe-
    DO J=0,NVEG_L-LBURN  !veg grid coordinate
      DO I=0,J           !integrand for q-
!        VEG_QRM_EMISS(J) = VEG_QRM_EMISS(J) + SF%VEG_SEMISSM_RADFCT_L(I,J)*WC%VEG_TMP_L(I+LBURN)**4
         IF (I==0) THEN
           KKG_L = SF%VEG_KGAS_L(1)
         ELSE
           KKG_L = SF%VEG_KGAS_L(I)
         ENDIF
         TMP_G = TMP(IIG,JJG,KKG_L)
         WC%VEG_TMP_L(LBURN)    = TMP_G
         WC%VEG_TMP_L(NVEG_L+1) = WC%VEG_TMP_L(NVEG_L) 
         VEG_TMP_FACE = 0.5_EB*(WC%VEG_TMP_L(I+LBURN)+WC%VEG_TMP_L(I+LBURN+1))
         VEG_QRM_EMISS(J) =  VEG_QRM_EMISS(J) + SF%VEG_SEMISSM_RADFCT_L(I,J)*VEG_TMP_FACE**4
      ENDDO
    ENDDO
    VEG_QRP_EMISS =  VEG_QRP_EMISS*SIGMA
    VEG_QRM_EMISS =  VEG_QRM_EMISS*SIGMA
!
    DO I=0,NVEG_L-LBURN
      VEG_QRNET_EMISS(I) = VEG_QRP_EMISS(I)-VEG_QRM_EMISS(I)
    ENDDO
!    DO I=1,NVEG_L-LBURN
!      VEG_QRNET_EMISS(I)  = VEG_QRNET_EMISS(I) - VEG_QRM_EMISS(I)
!    ENDDO
!
    DO I=1,NVEG_L-LBURN
      VEG_DIV_QRNET_EMISS(I) = VEG_QRNET_EMISS(I-1) - VEG_QRNET_EMISS(I)
    ENDDO
!
! Compute +/- radiation fluxes and their divergence due to incident fluxes on boundaries
    QRADM_INC = WALL(IW)%QRADIN/WALL(IW)%E_WALL !sigma*Ta^4 + flame
!   QRADM_INC = QRADIN(IW)/E_WALL(IW) + SIGMA*TMP_F(IW)**4 ! as done in FDS4
!   print*,'vege: QRADIN(IW)',qradin(iw)

! Adjust incident radiant flux to account for sloped terrain
! assumes user put VEG_NO_BURN=.TRUE. for vertical faces
! sets qrad on cell downspread of vertical face = qrad on cell face upspread of vertical face
!   QRADM_INC = QRADM_INC*1.0038_EB !adjustment for horizontal faces assuming 5 degree slope
!   II = WC%II
!   JJ = WC%JJ
!   KK = WC%KK
!   IC = CELL_INDEX(II-1,JJ,KK)
!   IOR = 1
!   IW_CELL = WALL_INDEX(IC,IOR) 
!   WC1 => WALL(IW_CELL)
!   SF1 => SURFACE(WC1%SURF_INDEX)
!print*,'vege: i,j,k,iw,sf',ii,jj,kk,iw,sf1%veg_no_burn
!   IF(SF1%VEG_NO_BURN) THEN
!print*,'vege: in vertical face qrad determination'
!!   QRADM_INC_SLOPE_VERTFACE = QRADM_INC_SLOPE_VERTFACE + WALL(IW_CELL)%RADIN/WALL(IW_CELL)%E_WALL
!!   QRADM_INC_SLOPE_VERTFACE = QRADM_INC_SLOPE_VERTFACE*0.0872_EB !assumes 5 degree slope
!!   QRADM_INC = QRADM_INC + QRADM_INC_SLOPE_VERTFACE !adjustment for adjacent vertical faces

!   IOR = -3
!   IW_CELL = WALL_INDEX(IC,IOR)
!adjustment for horizontal faces downspread of vertical face
!set flux = to max of flux up or downspread 
!print*,'vege: i,j,k,iw,qr',ii,jj,kk,wall(iw_cell)%qradin,wall(iw)%qradin
!   WALL(IW)%QRADIN = MAX(WALL(IW_CELL)%QRADIN,WALL(IW)%QRADIN) 
!   QRADM_INC = 1.0038_EB*WALL(IW)%QRADIN/WALL(IW_CELL)%E_WALL !assumes 5 degree slope!!!
!print*,'vege: qradm_inc,wallqrad',qradm_inc,wall(iw)%qradin
!   ENDIF

    ETAVEG_H  = (NVEG_L - LBURN)*DETA_VEG
    !this QRADP_INC ensures zero net radiant fluxes at bottom of vegetation (Albini)
    IF(SF%VEG_GROUND_ZERO_RAD) QRADP_INC = QRADM_INC*SF%VEG_FINCM_RADFCT_L(NVEG_L-LBURN) + VEG_QRM_EMISS(NVEG_L-LBURN)
    !this QRADP_INC assumes the ground stays at user specified temperature
    IF(.NOT. SF%VEG_GROUND_ZERO_RAD) QRADP_INC = SIGMA*SF%VEG_GROUND_TEMP**4
!   QRADP_INC = SIGMA*WC%VEG_TMP_L(NVEG_L)**4 
!   IF(.NOT. SF%VEG_GROUND_ZERO_RAD) QRADP_INC = SIGMA*TMP_G**4
!   QRADP_INC = SIGMA*WC%VEG_TMP_L(NVEG_L)**4*EXP(-ETAVEG_H) + VEG_QRM_EMISS(NVEG_L-LBURN) !fds4
    VEG_QRM_INC   = 0.0_EB ; VEG_QRP_INC = 0.0_EB 
    VEG_QRNET_INC = 0.0_EB ; VEG_DIV_QRNET_INC = 0.0_EB
    DO I=0,NVEG_L-LBURN
      VEG_QRM_INC(I)   = QRADM_INC*SF%VEG_FINCM_RADFCT_L(I)
      VEG_QRP_INC(I)   = QRADP_INC*SF%VEG_FINCP_RADFCT_L(I)
      VEG_QRNET_INC(I) = VEG_QRP_INC(I)-VEG_QRM_INC(I)
    ENDDO
    DO I=1,NVEG_L-LBURN
      VEG_DIV_QRNET_INC(I) = VEG_QRNET_INC(I-1) - VEG_QRNET_INC(I)
    ENDDO
  ENDIF LAYER_RAD_FLUXES
!
! Add divergence of net radiation flux to divergence of convection flux
  DO I=1,NVEG_L-LBURN
    SF%VEG_DIVQNET_L(I)= SF%VEG_DIVQNET_L(I) - (VEG_DIV_QRNET_INC(I) + VEG_DIV_QRNET_EMISS(I)) !includes self emiss
!   SF%VEG_DIVQNET_L(I)= SF%VEG_DIVQNET_L(I) - VEG_DIV_QRNET_INC(I) !no self emission contribution
  ENDDO
!
!
!      ************** Boundary Fuel Non-Arrehnius (Linear in temp) Degradation model *************************
! Drying occurs if qnet > 0 with Tveg held at 100 c
! Pyrolysis occurs according to Morvan & Dupuy empirical formula. Linear
! temperature dependence with qnet factor
!

  IF_VEG_DEGRADATION_LINEAR: IF (SF%VEG_DEGRADATION == 'LINEAR') THEN

    LAYER_LOOP1: DO IVEG_L = LBURN+1,NVEG_L
!
! Compute temperature of vegetation
!
      MPA_CHAR    = WC%VEG_CHARMASS_L(IVEG_L)
      MPA_VEG     = WC%VEG_FUELMASS_L(IVEG_L)
      MPA_MOIST   = WC%VEG_MOISTMASS_L(IVEG_L)
      TMP_VEG     = WC%VEG_TMP_L(IVEG_L)
      QNET_VEG    = SF%VEG_DIVQNET_L(IVEG_L-LBURN)
      CP_VEG      = (0.01_EB + 0.0037_EB*TMP_VEG)*1000._EB !J/kg/K
      CP_CHAR     = 420._EB + 2.09_EB*TMP_VEG + 6.85E-4_EB*TMP_VEG**2 !J/kg/K Park etal. C&F 2010 147:481-494
      CP_TOTAL    = CP_H2O*MPA_MOIST +  CP_VEG*MPA_VEG + CP_CHAR*MPA_CHAR
      DTMP_VEG    = DT_BC*QNET_VEG/CP_TOTAL
      TMP_VEG_NEW = TMP_VEG + DTMP_VEG

      IF_DIVQ_L_GE_0: IF(QNET_VEG > 0._EB) THEN 

! -- drying of veg layer
      IF(MPA_MOIST > MPA_MOIST_MIN .AND. TMP_VEG_NEW >= TMP_BOIL) THEN
        Q_UPTO_DRYING  = MAX(CP_TOTAL*(TMP_BOIL-TMP_VEG),0.0_EB)
        Q_FOR_DRYING   = DT_BC*QNET_VEG - Q_UPTO_DRYING
        MPA_MOIST_LOSS = MIN(Q_FOR_DRYING/H_H2O_VEG,MPA_MOIST_LOSS_MAX)

!       Q_FOR_DRYING   = (TMP_VEG_NEW - TMP_BOIL)/DTMP_VEG * QNET_VEG
!       MPA_MOIST_LOSS = MIN(DT_BC*Q_FOR_DRYING/H_H2O_VEG,MPA_MOIST_LOSS_MAX)

        MPA_MOIST_LOSS = MIN(MPA_MOIST_LOSS,MPA_MOIST-MPA_MOIST_MIN)
        TMP_VEG_NEW    = TMP_BOIL
        WC%VEG_MOISTMASS_L(IVEG_L) = MPA_MOIST - MPA_MOIST_LOSS !kg/m^2
        IF( WC%VEG_MOISTMASS_L(IVEG_L) <= MPA_MOIST_MIN ) WC%VEG_MOISTMASS_L(IVEG_L) = 0.0_EB
        IF (I_WATER > 0) WC%MASSFLUX(I_WATER) = WC%MASSFLUX(I_WATER) + RDT_BC*MPA_MOIST_LOSS
!       WC%VEG_TMP_L(IVEG_L) = TMP_VEG_NEW
      ENDIF

! -- pyrolysis multiple layers
      IF_VOLITIZATION: IF (MPA_MOIST <= MPA_MOIST_MIN) THEN

        IF(TMP_VEG_NEW >= 400._EB .AND. MPA_VEG > MPA_VEG_MIN) THEN
          Q_UPTO_VOLIT = MAX(CP_TOTAL*(400._EB-TMP_VEG),0.0_EB)
!         Q_UPTO_VOLIT = MAX((CP_VEG*MPA_VEG + CP_CHAR*MPA_CHAR)*(400._EB-TMP_VEG),0.0_EB)
          Q_FOR_VOLIT  = DT_BC*QNET_VEG - Q_UPTO_VOLIT
          Q_VOLIT      = Q_FOR_VOLIT*0.01_EB*(TMP_VEG-400._EB)

          MPA_VOLIT    = CHAR_FCTR*Q_VOLIT*RH_PYR_VEG
          MPA_VOLIT    = MAX(MPA_VOLIT,0._EB)
          MPA_VOLIT    = MIN(MPA_VOLIT,MPA_VOLIT_LOSS_MAX) !user specified max

          DMPA_VEG     = CHAR_FCTR2*MPA_VOLIT
          DMPA_VEG     = MIN(DMPA_VEG,(MPA_VEG-MPA_VEG_MIN))
          MPA_VEG      = MPA_VEG - DMPA_VEG

          MPA_VOLIT    = CHAR_FCTR*DMPA_VEG
          MPA_CHAR     = MPA_CHAR + SF%VEG_CHAR_FRACTION*DMPA_VEG
          Q_VOLIT      = MPA_VOLIT*H_PYR_VEG 

          TMP_VEG_NEW  = TMP_VEG + (Q_FOR_VOLIT-Q_VOLIT)/(MPA_VEG*CP_VEG + MPA_CHAR*CP_CHAR)
!         TMP_VEG_NEW  = TMP_VEG + (Q_FOR_VOLIT-Q_VOLIT)/(MPA_VEG*CP_VEG)
          TMP_VEG_NEW  = MIN(TMP_VEG_NEW,500._EB)
          WC%VEG_CHARMASS_L(IVEG_L) = MPA_CHAR
          WC%VEG_FUELMASS_L(IVEG_L) = MPA_VEG
          IF( WC%VEG_FUELMASS_L(IVEG_L) <= MPA_VEG_MIN ) WC%VEG_FUELMASS_L(IVEG_L) = 0.0_EB !**
          WC%MASSFLUX(I_FUEL)= WC%MASSFLUX(I_FUEL) + RDT_BC*MPA_VOLIT
        ENDIF        

      ENDIF IF_VOLITIZATION

      ENDIF IF_DIVQ_L_GE_0
      
      IF(MPA_VEG <= MPA_VEG_MIN) LBURN_NEW = MIN(LBURN_NEW+1,NVEG_L)
      IF(TMP_VEG_NEW < TMPA) TMP_VEG_NEW = TMPA !clip
      WC%VEG_TMP_L(IVEG_L) = TMP_VEG_NEW
      WC%VEG_HEIGHT        = REAL(NVEG_L-LBURN_NEW,EB)*DZVEG_L

    ENDDO LAYER_LOOP1

!   WC%VEG_TMP_L(LBURN) = WC%VEG_TMP_L(LBURN+1)
!   WC%VEG_TMP_L(LBURN) = TMP_G

  ENDIF  IF_VEG_DEGRADATION_LINEAR

!      ************** Boundary Fuel Arrehnius Degradation model *************************
! Drying and pyrolysis occur according to Arrehnius expressions obtained 
! from the literature (Porterie et al., Num. Heat Transfer, 47:571-591, 2005
! Predicting wildland fire behavior and emissions using a fine-scale physical
! model

  IF_VEG_DEGRADATION_ARRHENIUS: IF(SF%VEG_DEGRADATION == 'ARRHENIUS') THEN
!   A_H2O_VEG      = 600000._EB !1/s sqrt(K)
!   E_H2O_VEG      = 5800._EB !K

!   A_PYR_VEG      = 36300._EB !1/s
!   E_PYR_VEG      = 7250._EB !K

!   A_CHAR_VEG     = 430._EB !m/s
!   E_CHAR_VEG     = 9000._EB !K
!   H_CHAR_VEG     = -12.0E+6_EB !J/kg

!   BETA_CHAR_VEG  = 0.2_EB
!   NU_CHAR_VEG    = SF%VEG_CHAR_FRACTION
!   NU_ASH_VEG     = 0.1_EB
!   NU_O2_CHAR_VEG = 1.65_EB
!   CHAR_ENTHALPY_FRACTION_VEG = 0.5_EB
!print*,'-----------------------------'
!print 1115,beta_char_veg,nu_char_veg,nu_ash_veg,nu_o2_char_veg,char_enthalpy_fraction_veg

    A_H2O_VEG      = SF%VEG_A_H2O !1/2 sqrt(K)
    E_H2O_VEG      = SF%VEG_E_H2O !K

    A_PYR_VEG      = SF%VEG_A_PYR !1/s
    E_PYR_VEG      = SF%VEG_E_PYR !K

    A_CHAR_VEG     = SF%VEG_A_CHAR !m/s
    E_CHAR_VEG     = SF%VEG_E_CHAR !K
    H_CHAR_VEG     = SF%VEG_H_CHAR !J/kg

    BETA_CHAR_VEG  = SF%VEG_BETA_CHAR
    NU_CHAR_VEG    = SF%VEG_CHAR_FRACTION
    NU_ASH_VEG     = SF%VEG_ASH_FRACTION/SF%VEG_CHAR_FRACTION !fraction of char that can become ash
!   NU_ASH_VEG     = 0.1_EB !fraction of char that can become ash, Porterie et al. 2005 Num. Heat Transfer
    NU_O2_CHAR_VEG = SF%VEG_NU_O2_CHAR
    CHAR_ENTHALPY_FRACTION_VEG = SF%VEG_CHAR_ENTHALPY_FRACTION
!print 1115,nu_ash_veg,sf%veg_ash_fraction,sf%veg_char_fraction
!1115 format('vege:',2x,3(e15.5))

    LAYER_LOOP2: DO IVEG_L = LBURN+1,NVEG_L

      MPA_MOIST = WC%VEG_MOISTMASS_L(IVEG_L)
      MPA_VEG   = WC%VEG_FUELMASS_L(IVEG_L)
      MPA_CHAR  = WC%VEG_CHARMASS_L(IVEG_L)
      MPA_ASH   = WC%VEG_ASHMASS_L(IVEG_L)
      TMP_VEG   = WC%VEG_TMP_L(IVEG_L)

      TEMP_THRESEHOLD: IF (WC%VEG_TMP_L(IVEG_L) > 323._EB) THEN
              !arbitrary thresehold to prevent low-temp hrr reaction
              !added for drainage runs

! Drying of vegetation (Arrhenius)
      IF_DEHYDRATION_2: IF (MPA_MOIST > MPA_MOIST_MIN) THEN
        MPA_MOIST_LOSS = MIN(DT_BC*MPA_MOIST*A_H2O_VEG*EXP(-E_H2O_VEG/TMP_VEG)/SQRT(TMP_VEG), &
                         MPA_MOIST-MPA_MOIST_MIN)
        MPA_MOIST_LOSS = MIN(MPA_MOIST_LOSS,MPA_MOIST_LOSS_MAX) !user specified max
        MPA_MOIST      = MPA_MOIST - MPA_MOIST_LOSS
        WC%VEG_MOISTMASS_L(IVEG_L) = MPA_MOIST !kg/m^2
        IF (MPA_MOIST <= MPA_MOIST_MIN) WC%VEG_MOISTMASS_L(IVEG_L) = 0.0_EB
!print 1114,iveg_l,iig,jjg,tmp_veg,mpa_moist,mpa_moist_loss,dt_bc
!1114 format('(vege)',1x,3(I3),2x,4(e15.5))
!print*,'wwwwwwwwwwwwwwwwwwwww'
      ENDIF IF_DEHYDRATION_2

! Volitalization of vegetation(Arrhenius)
      IF_VOLITALIZATION_2: IF(MPA_VEG > MPA_VEG_MIN) THEN
        MPA_VOLIT = MAX(CHAR_FCTR*DT_BC*MPA_VEG*A_PYR_VEG*EXP(-E_PYR_VEG/TMP_VEG),0._EB)
        MPA_VOLIT = MIN(MPA_VOLIT,MPA_VOLIT_LOSS_MAX) !user specified max

        DMPA_VEG = CHAR_FCTR2*MPA_VOLIT
        DMPA_VEG = MIN(DMPA_VEG,(MPA_VEG - MPA_VEG_MIN))
        MPA_VEG  = MPA_VEG - DMPA_VEG

        MPA_VOLIT = CHAR_FCTR*DMPA_VEG
        MPA_CHAR  = MPA_CHAR + SF%VEG_CHAR_FRACTION*DMPA_VEG !kg/m^2
!print 1114,iveg_l,iig,jjg,tmp_veg,mpa_veg,mpa_volit,dt_bc
!print*,'vvvvvvvvvvvvvvvvvvvvv'

      ENDIF IF_VOLITALIZATION_2

      WC%VEG_FUELMASS_L(IVEG_L) = MPA_VEG
      WC%VEG_CHARMASS_L(IVEG_L) = MPA_CHAR

      WC%MASSFLUX(I_FUEL)= WC%MASSFLUX(I_FUEL) + MPA_VOLIT*RDT_BC
      IF (I_WATER > 0) WC%MASSFLUX(I_WATER) = WC%MASSFLUX(I_WATER) + MPA_MOIST_LOSS*RDT_BC

!Char oxidation oF Vegetation Layer within the Arrhenius pyrolysis model
!(note that this can be handled only approximately with the conserved
!scalar based gas-phase combustion model - no gas phase oxygen is consumed by
!the char oxidation reaction since it would be inconsistent with the state
!relation for oxygen based on the conserved scalar approach for gas phase
!combustion)
      IF_CHAR_OXIDATION: IF (SF%VEG_CHAR_OXIDATION .AND. MPA_CHAR > 0.0_EB) THEN
         KKG_L = SF%VEG_KGAS_L(IVEG_L-LBURN)
         ZZ_GET(1:N_TRACKED_SPECIES) = ZZ(IIG,JJG,KKG_L,1:N_TRACKED_SPECIES)
         CALL GET_MASS_FRACTION(ZZ_GET,O2_INDEX,Y_O2)
         TMP_G = TMP(IIG,JJG,KKG_L)
         CALL GET_VISCOSITY(ZZ_GET,MU_GAS,TMP_G)
         RE_D = RHO_GAS*SQRT(U2 + V2 + W(IIG,JJG,1)**2)*4._EB/SF%VEG_SV/MU_GAS 
         MPA_CHAR_LOSS = DT_BC*RHO_GAS*Y_O2*A_CHAR_VEG/NU_O2_CHAR_VEG*SF%VEG_SV*  &
                         SF%VEG_PACKING*EXP(-E_CHAR_VEG/WC%VEG_TMP_L(IVEG_L))*  &
                         (1+BETA_CHAR_VEG*SQRT(RE_D))
         MPA_CHAR_LOSS = MIN(MPA_CHAR,MPA_CHAR_LOSS)
         MPA_CHAR      = MPA_CHAR - MPA_CHAR_LOSS
         MPA_ASH       = MPA_ASH + NU_ASH_VEG*MPA_CHAR_LOSS
!        MPA_CHAR_CO2  = (1._EB + NU_O2_CHAR_VEG - NU_ASH_VEG)*MPA_CHAR_LOSS
         WC%VEG_CHARMASS_L(IVEG_L) = MPA_CHAR !kg/m^3
         WC%VEG_ASHMASS_L(IVEG_L)  = MPA_ASH

         IF (MPA_CHAR <= MPA_CHAR_MIN .AND. MPA_VEG <= MPA_VEG_MIN) WC%VEG_CHARMASS_L(IVEG_L) = 0.0_EB
       ENDIF IF_CHAR_OXIDATION

      ENDIF TEMP_THRESEHOLD

! Vegetation temperature (Arrhenius)
      CP_VEG = (0.01_EB + 0.0037_EB*TMP_VEG)*1000._EB !W/kg/K
      CP_CHAR= 420._EB + 2.09_EB*TMP_VEG + 6.85E-4_EB*TMP_VEG**2 !J/kg/K Park etal. C&F 2010 147:481-494
      Q_VEG_CHAR       = MPA_CHAR_LOSS*H_CHAR_VEG
      CP_MOIST_AND_VEG = CP_H2O*WC%VEG_MOISTMASS_L(IVEG_L) + CP_VEG*WC%VEG_FUELMASS_L(IVEG_L) + &
                         CP_CHAR*WC%VEG_CHARMASS_L(IVEG_L) + CP_ASH*WC%VEG_ASHMASS_L(IVEG_L)

      WC%VEG_TMP_L(IVEG_L) = WC%VEG_TMP_L(IVEG_L) + (DT_BC*SF%VEG_DIVQNET_L(IVEG_L-LBURN) - &
                             (MPA_MOIST_LOSS*H_H2O_VEG + MPA_VOLIT*H_PYR_VEG) + CHAR_ENTHALPY_FRACTION_VEG*Q_VEG_CHAR ) &
                             /CP_MOIST_AND_VEG
      WC%VEG_TMP_L(IVEG_L) = MAX( WC%VEG_TMP_L(IVEG_L), TMPA)
      WC%VEG_TMP_L(IVEG_L) = MIN( WC%VEG_TMP_L(IVEG_L), TMP_CHAR_MAX)

    ENDDO LAYER_LOOP2

  ENDIF IF_VEG_DEGRADATION_ARRHENIUS
  
!  if (wc%veg_tmp_L(lburn+1) > 300._EB) wc%massflux(i_fuel)=0.1
!  if (iig == 14 .or. iig==15) wc%massflux(i_fuel)=0.1
  WC%VEG_TMP_L(LBURN) = MAX(TMP_G,TMPA)
  WC%MASSFLUX_ACTUAL(I_FUEL) = WC%MASSFLUX(I_FUEL)
  IF (I_WATER > 0) WC%MASSFLUX_ACTUAL(I_WATER) = WC%MASSFLUX(I_WATER)
 
! Temperature boundary condtions 
! Mass boundary conditions are determine in subroutine SPECIES_BC in wall.f90 for case SPECIFIED_MASS_FLUX
! TMP_F(IW) = WC%VEG_TMP_L(NVEG_L)
! IF (LBURN < NVEG_L)  TMP_F(IW) = WC%VEG_TMP_L(1+LBURN)

  IF (LBURN_NEW < NVEG_L) THEN
    WALL(IW)%TMP_F = WC%VEG_TMP_L(1+LBURN_NEW)
    IF (WC%VEG_TMP_L(LBURN+1) < TMPA-10.0_eb) PRINT '(a,1X,2es16.8)','tVEG<tA-10: tVEG,tG= :',WC%VEG_TMP_L(LBURN+1),TMP_G
!!   TMP_F(IW) = ((VEG_QRP_INC(0)+VEG_QRP_EMISS(0))/SIGMA)**.25 !as done in FDS4
  ELSE
    KKG_L = SF%VEG_KGAS_L(1)
    TMP_G = TMP(IIG,JJG,KKG_L)
    WALL(IW)%TMP_F = MAX(TMP_G,TMPA) !Tveg=Tgas if veg is completely burned
  ENDIF
! TMP_F(IW) = MAX(TMP_F(IW),TMPA)

ENDDO VEG_WALL_CELL_LOOP

VEG_CLOCK_BC = T

END SUBROUTINE BNDRY_VEG_MASS_ENERGY_TRANSFER
!
!************************************************************************************************
!
!\/\/\////\/\/\/\/\/\/\\\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
!\/\/\////\/\/\/\/\/\/\\\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
SUBROUTINE INITIALIZE_LEVEL_SET_FIREFRONT(NM)
!\/\/\////\/\/\/\/\/\/\\\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
!\/\/\////\/\/\/\/\/\/\\\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
!
! Level set based modeling of fire front propatagion across terrain. 
! There are four implementations from the simplest in which the wind is constant
! in directior and magnitude to a CFD coupled implementation with buoynacy generated flow.
! See User Guide on Google Docs
!
! Issues:
! 1) Need to make level set computation mesh dependent so the the LS slice file
!    is created only where fire is expected
!
!
LOGICAL :: COMPUTE_FM10_SRXY,COMPUTE_HEADROS_FM10,COMPUTE_HEADROS_RSA,COMPUTE_RSA_SRXY
INTEGER, INTENT(IN) :: NM
INTEGER  :: I,IM1,IM2,IIG,IP1,IP2,IW,J,JJG,JM1,JP1,KKG
INTEGER  :: I1,I2,I3,I4,I5,I6
REAL(EB) :: COSDPHIU,DPHIDX,DPHIDY,DPHIDOTU,LX,SR_MAX,SR_MAX_FM10,SR_MAX_SURF,UMAX_LS,VMAX_LS
REAL(EB) :: G_EAST,G_WEST,G_SOUTH,G_NORTH
REAL(EB) :: VERT_CANOPY_EXTENT
REAL(EB) :: I_CROWN_INI,VEG_BETA_FM10,VEG_SV_FM10

REAL(EB), ALLOCATABLE, DIMENSION(:) :: X_LS,Y_LS

CHARACTER(30) :: CFORM,SMOKEVIEW_LABEL,SMOKEVIEW_BAR_LABEL,UNITS

REAL(EB), POINTER, DIMENSION(:,:) :: ZT => NULL()

TYPE (WALL_TYPE),    POINTER :: WC =>NULL()
TYPE (SURFACE_TYPE), POINTER :: SF =>NULL()


CALL CPU_TIME(CPUTIME)
LS_T_BEG = CPUTIME

CALL POINT_TO_MESH(NM)

ZT => LS_Z_TERRAIN

!print*,'vege: in initialize LS'
!WRITE(LU_OUTPUT,*)'level set: z(*)',z
!WRITE(LU_OUTPUT,*)'level set: ls_z_terrain(1,1)',ls_z_terrain(:,100)
!
!-Initialize variables
!
!-- Domain specification (meters) from input file (assumes there's only one mesh)
!
LX = XF - XS ; NX_LS = IBAR
DX_LS = LX/REAL(NX_LS,EB) ; IDX_LS = 1.0_EB / DX_LS
LX = YF - YS ; NY_LS = JBAR
DY_LS = LX/REAL(NY_LS,EB) ; IDY_LS = 1.0_EB / DY_LS
T_FINAL = T_END
 
!******************* Initialize time stepping and other constants

SUMTIME_LS = 0.0_EB ! Used for time step output

SUM_T_SLCF_LS = 0._EB
SUM_T_UAVG_LS = 0._EB ; NSUM_T_UAVG_LS = 0 ; FIRST_AVG_FLAG_LS = 0 !for obtaining uavg for use in empirical ROS
DT_COEF = 0.5_EB
TIME_FLANKFIRE_QUENCH = 20.0_EB !flankfire lifetime in seconds

LSET_ELLIPSE = .FALSE. ! Default value of flag for the elliptical spread model
LSET_TAN2    = .FALSE. ! Default value: Flag for ROS proportional to Tan(slope)^2 
!HEAD_WIDTH   = 1.0_EB

!WRITE(LU_OUTPUT,*)'surface ros',surface%veg_lset_ros_head
!WRITE(LU_OUTPUT,*)'surface wind_exp',surface%veg_lset_wind_exp
!
!C_F = 0.2_EB
!
! -- Flux limiter
!LIMITER_LS = 1 !MINMOD
!LIMITER_LS = 2 !SUPERBEE
!LIMITER_LS = 3 !First order upwinding
!
!
LIMITER_LS = FLUX_LIMITER
IF (LIMITER_LS > 3) LIMITER_LS = 1

!******************* Open output files and write headers (put this in dump.f90 ASSIGN_FILE_NAMES)
   ! Slice Filenames

!  DO N=1,M%N_SLCF
!     LU_SLCF(N,NM) = GET_FILE_NUMBER()
!     IF (NMESHES>1) THEN
!        IF (M%N_SLCF <100) CFORM = '(A,A,I4.4,A,I2.2,A)'
!        IF (M%N_SLCF>=100) CFORM = '(A,A,I4.4,A,I3.3,A)'
!        WRITE(FN_SLCF(N,NM),CFORM) TRIM(CHID),'_',NM,'_',N,'.sf'
!     ELSE
!        IF (M%N_SLCF <100) CFORM = '(A,A,I2.2,A)'
!        IF (M%N_SLCF>=100) CFORM = '(A,A,I3.3,A)'
!        WRITE(FN_SLCF(N,NM),CFORM) TRIM(CHID),'_',N,'.sf'
!     ENDIF
!  ENDDO


TIME_LS    = T_BEGIN

!******************* Assign filenames, open data files and write headers; Put filenames & case info in smv file 
!                    (put this in dump.f90 ASSIGN_FILE_NAMES)
IF (NMESHES>1) THEN
  CFORM = '(A,A,I4.4,A,A)'
ELSE
  CFORM = '(A,A,A)'
ENDIF

!--Level set field for animation via Smokeview
LU_SLCF_LS(1) = GET_FILE_NUMBER()
SMOKEVIEW_LABEL = 'phifield'
SMOKEVIEW_BAR_LABEL = 'phifield'
UNITS  = 'C'
IF(NMESHES  > 1) WRITE(FN_SLCF_LS(1),CFORM) TRIM(CHID),'_',NM,'_','lsfs.sf'
IF(NMESHES == 1) WRITE(FN_SLCF_LS(1),CFORM) TRIM(CHID),'_','lsfs.sf'
OPEN(LU_SLCF_LS(1),FILE=FN_SLCF_LS(1),FORM='UNFORMATTED',STATUS='REPLACE')
!OPEN(LU_SLCF_LS,FILE=TRIM(CHID)//'_lsfs.sf',FORM='UNFORMATTED',STATUS='REPLACE')
WRITE(LU_SLCF_LS(1)) SMOKEVIEW_LABEL(1:30)
WRITE(LU_SLCF_LS(1)) SMOKEVIEW_LABEL(1:30)
WRITE(LU_SLCF_LS(1)) UNITS(1:30)
WRITE(LU_SLCF_LS(1))0,IBAR,0,JBAR,1,1

IF (NM == 1) THEN !write to smv file
  DO I=1,NMESHES 
    IF (NMESHES == 1) THEN
      WRITE(FN_SLCF_LS(1),CFORM) TRIM(CHID),'_','lsfs.sf'
    ELSE
      WRITE(FN_SLCF_LS(1),CFORM) TRIM(CHID),'_',I,'_','lsfs.sf'
    ENDIF
    WRITE(LU_SMV,'(A,5X,I3,5x,F7.2)') 'SLCT ',I,0.1
    WRITE(LU_SMV,'(A)')FN_SLCF_LS(1)
    WRITE(LU_SMV,'(A)') 'phifield'
    WRITE(LU_SMV,'(A)') 'phifield'
    WRITE(LU_SMV,'(A)') '-'
  ENDDO
ENDIF

!--Time of Arrival for animation via Smokeview
LU_SLCF_LS(2) = GET_FILE_NUMBER()
SMOKEVIEW_LABEL = 'LS TOA'
SMOKEVIEW_BAR_LABEL = 'LS TOA'
UNITS  = 's'
IF(NMESHES  > 1) WRITE(FN_SLCF_LS(2),CFORM) TRIM(CHID),'_',NM,'_','lstoa.sf'
IF(NMESHES == 1) WRITE(FN_SLCF_LS(2),CFORM) TRIM(CHID),'_','lstoa.sf'
OPEN(LU_SLCF_LS(2),FILE=FN_SLCF_LS(2),FORM='UNFORMATTED',STATUS='REPLACE')
!OPEN(LU_SLCF_TOA_LS,FILE=TRIM(CHID)//'_lstoa.sf',FORM='UNFORMATTED',STATUS='REPLACE')
WRITE(LU_SLCF_LS(2)) SMOKEVIEW_LABEL(1:30)
WRITE(LU_SLCF_LS(2)) SMOKEVIEW_LABEL(1:30)
WRITE(LU_SLCF_LS(2)) UNITS(1:30)
WRITE(LU_SLCF_LS(2))0,IBAR,0,JBAR,1,1

IF (NM == 1) THEN !write to smv file
  DO I=1,NMESHES 
    IF (NMESHES == 1) THEN
      WRITE(FN_SLCF_LS(2),CFORM) TRIM(CHID),'_','lstoa.sf'
    ELSE
      WRITE(FN_SLCF_LS(2),CFORM) TRIM(CHID),'_',I,'_','lstoa.sf'
    ENDIF
    WRITE(LU_SMV,'(A,5X,I3,5X,F7.2)') 'SLCT ',I,0.1
    WRITE(LU_SMV,'(A)')FN_SLCF_LS(2)
    WRITE(LU_SMV,'(A)') 'LS TOA'
    WRITE(LU_SMV,'(A)') 'LS TOA'
    WRITE(LU_SMV,'(A)') 's'
  ENDDO
ENDIF

!--ROS magnitude for animation in Smokeview
LU_SLCF_LS(3) = GET_FILE_NUMBER()
SMOKEVIEW_LABEL = 'LS ROS'
SMOKEVIEW_BAR_LABEL = 'LS ROS'
UNITS  = 'm/s'
IF(NMESHES  > 1) WRITE(FN_SLCF_LS(3),CFORM) TRIM(CHID),'_',NM,'_','lsros.sf'
IF(NMESHES == 1) WRITE(FN_SLCF_LS(3),CFORM) TRIM(CHID),'_','lsros.sf'
OPEN(LU_SLCF_LS(3),FILE=FN_SLCF_LS(3),FORM='UNFORMATTED',STATUS='REPLACE')
!OPEN(LU_SLCF_ROS_LS,FILE=TRIM(CHID)//'_lsros.sf',FORM='UNFORMATTED',STATUS='REPLACE')
WRITE(LU_SLCF_LS(3)) SMOKEVIEW_LABEL(1:30)
WRITE(LU_SLCF_LS(3)) SMOKEVIEW_LABEL(1:30)
WRITE(LU_SLCF_LS(3)) UNITS(1:30)
WRITE(LU_SLCF_LS(3))0,IBAR,0,JBAR,1,1

IF (NM == 1) THEN !write to smv file
  DO I=1,NMESHES 
    IF (NMESHES == 1) THEN
      WRITE(FN_SLCF_LS(3),CFORM) TRIM(CHID),'_','lsros.sf'
    ELSE
      WRITE(FN_SLCF_LS(3),CFORM) TRIM(CHID),'_',I,'_','lsros.sf'
    ENDIF
    WRITE(LU_SMV,'(A,5X,I3,5X,F7.2)') 'SLCT ',I,0.1
    WRITE(LU_SMV,'(A)')FN_SLCF_LS(3)
    WRITE(LU_SMV,'(A)') 'LS ROS'
    WRITE(LU_SMV,'(A)') 'LS ROS'
    WRITE(LU_SMV,'(A)') 'm/s'
  ENDDO
ENDIF

!--Fire line intensity at time of fire arrival for animation in Smokeview
LU_SLCF_LS(4) = GET_FILE_NUMBER()
SMOKEVIEW_LABEL = 'LS FLI'
SMOKEVIEW_BAR_LABEL = 'LS FLI'
UNITS  = 'kW/m'
IF(NMESHES  > 1) WRITE(FN_SLCF_LS(4),CFORM) TRIM(CHID),'_',NM,'_','lsfli.sf'
IF(NMESHES == 1) WRITE(FN_SLCF_LS(4),CFORM) TRIM(CHID),'_','lsfli.sf'
OPEN(LU_SLCF_LS(4),FILE=FN_SLCF_LS(4),FORM='UNFORMATTED',STATUS='REPLACE')
!OPEN(LU_SLCF_FLI_LS,FILE=TRIM(CHID)//'_lsfli.sf',FORM='UNFORMATTED',STATUS='REPLACE')
WRITE(LU_SLCF_LS(4)) SMOKEVIEW_LABEL(1:30)
WRITE(LU_SLCF_LS(4)) SMOKEVIEW_LABEL(1:30)
WRITE(LU_SLCF_LS(4)) UNITS(1:30)
WRITE(LU_SLCF_LS(4))0,IBAR,0,JBAR,1,1

IF (NM == 1) THEN !write to smv file
  DO I=1,NMESHES 
    IF (NMESHES == 1) THEN
      WRITE(FN_SLCF_LS(4),CFORM) TRIM(CHID),'_','lsfli.sf'
    ELSE
      WRITE(FN_SLCF_LS(4),CFORM) TRIM(CHID),'_',I,'_','lsfli.sf'
    ENDIF
    WRITE(LU_SMV,'(A,5X,I3,5X,F7.2)') 'SLCT ',I,0.1
    WRITE(LU_SMV,'(A)')FN_SLCF_LS(4)
    WRITE(LU_SMV,'(A)') 'LS FLI'
    WRITE(LU_SMV,'(A)') 'LS FLI'
    WRITE(LU_SMV,'(A)') 'kW/m'
  ENDDO
ENDIF

!--HRRPUA at all output times for animation in Smokeview
IF (VEG_LEVEL_SET_COUPLED) THEN

LU_SLCF_LS(5) = GET_FILE_NUMBER()
SMOKEVIEW_LABEL = 'LS HRRPUA'
SMOKEVIEW_BAR_LABEL = 'LS HRRPUA'
UNITS  = 'kW/m^2'
IF(NMESHES  > 1) WRITE(FN_SLCF_LS(5),CFORM) TRIM(CHID),'_',NM,'_','lshrrpua.sf'
IF(NMESHES == 1) WRITE(FN_SLCF_LS(5),CFORM) TRIM(CHID),'_','lshrrpua.sf'
OPEN(LU_SLCF_LS(5),FILE=FN_SLCF_LS(5),FORM='UNFORMATTED',STATUS='REPLACE')
WRITE(LU_SLCF_LS(5)) SMOKEVIEW_LABEL(1:30)
WRITE(LU_SLCF_LS(5)) SMOKEVIEW_LABEL(1:30)
WRITE(LU_SLCF_LS(5)) UNITS(1:30)
WRITE(LU_SLCF_LS(5))0,IBAR,0,JBAR,1,1

IF (NM == 1) THEN !write to smv file
  DO I=1,NMESHES 
    IF (NMESHES == 1) THEN
      WRITE(FN_SLCF_LS(5),CFORM) TRIM(CHID),'_','lshrrpua.sf'
    ELSE
      WRITE(FN_SLCF_LS(5),CFORM) TRIM(CHID),'_',I,'_','lshrrpua.sf'
    ENDIF
    WRITE(LU_SMV,'(A,5X,I3,5X,F7.2)') 'SLCT ',I,0.1
    WRITE(LU_SMV,'(A)')FN_SLCF_LS(5)
    WRITE(LU_SMV,'(A)') 'LS HRRPUA'
    WRITE(LU_SMV,'(A)') 'LS HRRPUA'
    WRITE(LU_SMV,'(A)') 'kW/m^2'
  ENDDO
ENDIF

ENDIF

!--Crown Fire Probablity used in CFIS model (Cruz & Alexander) for animation in Smokeview
IF (VEG_LEVEL_SET_CFIS_CROWNFIRE_MODEL) THEN 
  LU_SLCF_LS(6) = GET_FILE_NUMBER()
  SMOKEVIEW_LABEL = 'LS ProbCrown'
  SMOKEVIEW_BAR_LABEL = 'LS ProbCrown'
  UNITS  = '-'
  IF(NMESHES  > 1) WRITE(FN_SLCF_LS(6),CFORM) TRIM(CHID),'_',NM,'_','lsprobc.sf'
  IF(NMESHES == 1) WRITE(FN_SLCF_LS(6),CFORM) TRIM(CHID),'_','lsprobc.sf'
  OPEN(LU_SLCF_LS(6),FILE=FN_SLCF_LS(6),FORM='UNFORMATTED',STATUS='REPLACE')
  WRITE(LU_SLCF_LS(6)) SMOKEVIEW_LABEL(1:30)
  WRITE(LU_SLCF_LS(6)) SMOKEVIEW_LABEL(1:30)
  WRITE(LU_SLCF_LS(6)) UNITS(1:30)
  WRITE(LU_SLCF_LS(6))0,IBAR,0,JBAR,1,1

  IF (NM == 1) THEN !write to smv file
    DO I=1,NMESHES 
      IF (NMESHES == 1) THEN
        WRITE(FN_SLCF_LS(6),CFORM) TRIM(CHID),'_','lsprobc.sf'
      ELSE
        WRITE(FN_SLCF_LS(6),CFORM) TRIM(CHID),'_',I,'_','lsprobc.sf'
      ENDIF
      WRITE(LU_SMV,'(A,5X,I3,5X,F7.2)') 'SLCT ',I,0.1
      WRITE(LU_SMV,'(A)')FN_SLCF_LS(6)
      WRITE(LU_SMV,'(A)') 'LS PROBCROWN'
      WRITE(LU_SMV,'(A)') 'LS PROBCROWN'
      WRITE(LU_SMV,'(A)') '-'
    ENDDO
  ENDIF
ENDIF

!******************* Open file contained HRRPUA in order to implement the "burner" method which represents a fireline 
!                    using proxies for the actual HRRPUA that are obtained from remote-sensing, or other, sources. 
! ASSUMES SINGLE MESH FOR NOW

IF (VEG_LEVEL_SET_BURNERS_FOR_FIRELINE) THEN
  LU_SLCF_LS(7) = GET_FILE_NUMBER()
  FN_SLCF_LS(7) = BRNRINFO(BURNER_FILE(NM))%BRNRFILE
  OPEN(LU_SLCF_LS(7),FILE=FN_SLCF_LS(7),FORM='UNFORMATTED',STATUS='OLD')
  READ(LU_SLCF_LS(7)) SMOKEVIEW_LABEL(1:30)
  READ(LU_SLCF_LS(7)) SMOKEVIEW_LABEL(1:30)
  READ(LU_SLCF_LS(7)) UNITS(1:30)
  READ(LU_SLCF_LS(7)) I,I,I,I,I,I
  READ(LU_SLCF_LS(7)) LSET_TIME_HRRPUA_BURNER 
  READ(LU_SLCF_LS(7)) ((HRRPUA_IN(I,J),I=0,IBAR),J=0,JBAR) 
ENDIF

!--Crown Fraction Burned from Scott and Reinghardt model for animation in Smokeview
IF (VEG_LEVEL_SET_SR_CROWNFIRE_MODEL) THEN 
  LU_SLCF_LS(8) = GET_FILE_NUMBER()
  SMOKEVIEW_LABEL = 'LS CFB S&R'
  SMOKEVIEW_BAR_LABEL = 'LS CFB S&R'
  UNITS  = '-'
  IF(NMESHES  > 1) WRITE(FN_SLCF_LS(8),CFORM) TRIM(CHID),'_',NM,'_','lscfb.sf'
  IF(NMESHES == 1) WRITE(FN_SLCF_LS(8),CFORM) TRIM(CHID),'_','lscfb.sf'
  OPEN(LU_SLCF_LS(8),FILE=FN_SLCF_LS(8),FORM='UNFORMATTED',STATUS='REPLACE')
  WRITE(LU_SLCF_LS(8)) SMOKEVIEW_LABEL(1:30)
  WRITE(LU_SLCF_LS(8)) SMOKEVIEW_LABEL(1:30)
  WRITE(LU_SLCF_LS(8)) UNITS(1:30)
  WRITE(LU_SLCF_LS(8))0,IBAR,0,JBAR,1,1

  IF (NM == 1) THEN !write to smv file
    DO I=1,NMESHES 
      IF (NMESHES == 1) THEN
        WRITE(FN_SLCF_LS(8),CFORM) TRIM(CHID),'_','lscfb.sf'
      ELSE
        WRITE(FN_SLCF_LS(8),CFORM) TRIM(CHID),'_',I,'_','lscfb.sf'
      ENDIF
      WRITE(LU_SMV,'(A,5X,I3,5X,F7.2)') 'SLCT ',I,0.1
      WRITE(LU_SMV,'(A)')FN_SLCF_LS(8)
      WRITE(LU_SMV,'(A)') 'LS CFB'
      WRITE(LU_SMV,'(A)') 'LS CFB'
      WRITE(LU_SMV,'(A)') '-'
    ENDDO
  ENDIF
ENDIF

!--Rsa from Scott and Reinghardt model for animation in Smokeview
IF (VEG_LEVEL_SET_SR_CROWNFIRE_MODEL) THEN 
  LU_SLCF_LS(9) = GET_FILE_NUMBER()
  SMOKEVIEW_LABEL = 'LS Rsa S&R'
  SMOKEVIEW_BAR_LABEL = 'LS Rsa S&R'
  UNITS  = '-'
  IF(NMESHES  > 1) WRITE(FN_SLCF_LS(9),CFORM) TRIM(CHID),'_',NM,'_','lsrsa.sf'
  IF(NMESHES == 1) WRITE(FN_SLCF_LS(9),CFORM) TRIM(CHID),'_','lsrsa.sf'
  OPEN(LU_SLCF_LS(9),FILE=FN_SLCF_LS(9),FORM='UNFORMATTED',STATUS='REPLACE')
  WRITE(LU_SLCF_LS(9)) SMOKEVIEW_LABEL(1:30)
  WRITE(LU_SLCF_LS(9)) SMOKEVIEW_LABEL(1:30)
  WRITE(LU_SLCF_LS(9)) UNITS(1:30)
  WRITE(LU_SLCF_LS(9))0,IBAR,0,JBAR,1,1

  IF (NM == 1) THEN !write to smv file
    DO I=1,NMESHES 
      IF (NMESHES == 1) THEN
        WRITE(FN_SLCF_LS(9),CFORM) TRIM(CHID),'_','lsrsa.sf'
      ELSE
        WRITE(FN_SLCF_LS(9),CFORM) TRIM(CHID),'_',I,'_','lsrsa.sf'
      ENDIF
      WRITE(LU_SMV,'(A,5X,I3,5X,F7.2)') 'SLCT ',I,0.1
      WRITE(LU_SMV,'(A)')FN_SLCF_LS(9)
      WRITE(LU_SMV,'(A)') 'LS Rsa'
      WRITE(LU_SMV,'(A)') 'LS Rsa'
      WRITE(LU_SMV,'(A)') 'm/s'
    ENDDO
  ENDIF
ENDIF

!--ROS for fuel model 10 from Scott and Reinghardt model for animation in Smokeview
IF (VEG_LEVEL_SET_SR_CROWNFIRE_MODEL) THEN 
  LU_SLCF_LS(10) = GET_FILE_NUMBER()
  SMOKEVIEW_LABEL = 'LS R10 S&R'
  SMOKEVIEW_BAR_LABEL = 'LS R10 S&R'
  UNITS  = '-'
  IF(NMESHES  > 1) WRITE(FN_SLCF_LS(10),CFORM) TRIM(CHID),'_',NM,'_','lsr10.sf'
  IF(NMESHES == 1) WRITE(FN_SLCF_LS(10),CFORM) TRIM(CHID),'_','lsr10.sf'
  OPEN(LU_SLCF_LS(10),FILE=FN_SLCF_LS(10),FORM='UNFORMATTED',STATUS='REPLACE')
  WRITE(LU_SLCF_LS(10)) SMOKEVIEW_LABEL(1:30)
  WRITE(LU_SLCF_LS(10)) SMOKEVIEW_LABEL(1:30)
  WRITE(LU_SLCF_LS(10)) UNITS(1:30)
  WRITE(LU_SLCF_LS(10))0,IBAR,0,JBAR,1,1

  IF (NM == 1) THEN !write to smv file
    DO I=1,NMESHES 
      IF (NMESHES == 1) THEN
        WRITE(FN_SLCF_LS(10),CFORM) TRIM(CHID),'_','lsr10.sf'
      ELSE
        WRITE(FN_SLCF_LS(10),CFORM) TRIM(CHID),'_',I,'_','lsr10.sf'
      ENDIF
      WRITE(LU_SMV,'(A,5X,I3,5X,F7.2)') 'SLCT ',I,0.1
      WRITE(LU_SMV,'(A)')FN_SLCF_LS(10)
      WRITE(LU_SMV,'(A)') 'LS R10'
      WRITE(LU_SMV,'(A)') 'LS R10'
      WRITE(LU_SMV,'(A)') 'm/s'
    ENDDO
  ENDIF
ENDIF

!--ROS for initiation of crown fire from Scott and Reinghardt model for animation in Smokeview
IF (VEG_LEVEL_SET_SR_CROWNFIRE_MODEL) THEN 
  LU_SLCF_LS(11) = GET_FILE_NUMBER()
  SMOKEVIEW_LABEL = 'LS RINI S&R'
  SMOKEVIEW_BAR_LABEL = 'LS RINI S&R'
  UNITS  = '-'
  IF(NMESHES  > 1) WRITE(FN_SLCF_LS(11),CFORM) TRIM(CHID),'_',NM,'_','lsrini.sf'
  IF(NMESHES == 1) WRITE(FN_SLCF_LS(11),CFORM) TRIM(CHID),'_','lsrini.sf'
  OPEN(LU_SLCF_LS(11),FILE=FN_SLCF_LS(11),FORM='UNFORMATTED',STATUS='REPLACE')
  WRITE(LU_SLCF_LS(11)) SMOKEVIEW_LABEL(1:30)
  WRITE(LU_SLCF_LS(11)) SMOKEVIEW_LABEL(1:30)
  WRITE(LU_SLCF_LS(11)) UNITS(1:30)
  WRITE(LU_SLCF_LS(11))0,IBAR,0,JBAR,1,1

  IF (NM == 1) THEN !write to smv file
    DO I=1,NMESHES 
      IF (NMESHES == 1) THEN
        WRITE(FN_SLCF_LS(11),CFORM) TRIM(CHID),'_','lsrini.sf'
      ELSE
        WRITE(FN_SLCF_LS(11),CFORM) TRIM(CHID),'_',I,'_','lsrini.sf'
      ENDIF
      WRITE(LU_SMV,'(A,5X,I3,5X,F7.2)') 'SLCT ',I,0.1
      WRITE(LU_SMV,'(A)')FN_SLCF_LS(11)
      WRITE(LU_SMV,'(A)') 'LS Rini'
      WRITE(LU_SMV,'(A)') 'LS Rini'
      WRITE(LU_SMV,'(A)') 'm/s'
    ENDDO
  ENDIF
ENDIF

!--ROS in surface fuels from Scott and Reinghardt model for animation in Smokeview
IF (VEG_LEVEL_SET_SR_CROWNFIRE_MODEL) THEN 
  LU_SLCF_LS(12) = GET_FILE_NUMBER()
  SMOKEVIEW_LABEL = 'LS Rsurf S&R'
  SMOKEVIEW_BAR_LABEL = 'LS Rsurf S&R'
  UNITS  = '-'
  IF(NMESHES  > 1) WRITE(FN_SLCF_LS(12),CFORM) TRIM(CHID),'_',NM,'_','lsrsurf.sf'
  IF(NMESHES == 1) WRITE(FN_SLCF_LS(12),CFORM) TRIM(CHID),'_','lsrsurf.sf'
  OPEN(LU_SLCF_LS(12),FILE=FN_SLCF_LS(12),FORM='UNFORMATTED',STATUS='REPLACE')
  WRITE(LU_SLCF_LS(12)) SMOKEVIEW_LABEL(1:30)
  WRITE(LU_SLCF_LS(12)) SMOKEVIEW_LABEL(1:30)
  WRITE(LU_SLCF_LS(12)) UNITS(1:30)
  WRITE(LU_SLCF_LS(12))0,IBAR,0,JBAR,1,1

  IF (NM == 1) THEN !write to smv file
    DO I=1,NMESHES 
      IF (NMESHES == 1) THEN
        WRITE(FN_SLCF_LS(12),CFORM) TRIM(CHID),'_','lsrsurf.sf'
      ELSE
        WRITE(FN_SLCF_LS(12),CFORM) TRIM(CHID),'_',I,'_','lsrsurf.sf'
      ENDIF
      WRITE(LU_SMV,'(A,5X,I3,5X,F7.2)') 'SLCT ',I,0.1
      WRITE(LU_SMV,'(A)')FN_SLCF_LS(12)
      WRITE(LU_SMV,'(A)') 'LS Rsurf'
      WRITE(LU_SMV,'(A)') 'LS Rsurf'
      WRITE(LU_SMV,'(A)') 'm/s'
    ENDDO
  ENDIF
ENDIF

!--ROS of active crown fire (Ra) from Scott and Reinghardt model for animation in Smokeview
IF (VEG_LEVEL_SET_SR_CROWNFIRE_MODEL) THEN 
  LU_SLCF_LS(13) = GET_FILE_NUMBER()
  SMOKEVIEW_LABEL = 'LS Rcfb S&R'
  SMOKEVIEW_BAR_LABEL = 'LS Rcfb S&R'
  UNITS  = '-'
  IF(NMESHES  > 1) WRITE(FN_SLCF_LS(13),CFORM) TRIM(CHID),'_',NM,'_','lsrcfb.sf'
  IF(NMESHES == 1) WRITE(FN_SLCF_LS(13),CFORM) TRIM(CHID),'_','lsrcfb.sf'
  OPEN(LU_SLCF_LS(13),FILE=FN_SLCF_LS(13),FORM='UNFORMATTED',STATUS='REPLACE')
  WRITE(LU_SLCF_LS(13)) SMOKEVIEW_LABEL(1:30)
  WRITE(LU_SLCF_LS(13)) SMOKEVIEW_LABEL(1:30)
  WRITE(LU_SLCF_LS(13)) UNITS(1:30)
  WRITE(LU_SLCF_LS(13))0,IBAR,0,JBAR,1,1

  IF (NM == 1) THEN !write to smv file
    DO I=1,NMESHES 
      IF (NMESHES == 1) THEN
        WRITE(FN_SLCF_LS(13),CFORM) TRIM(CHID),'_','lsrcfb.sf'
      ELSE
        WRITE(FN_SLCF_LS(13),CFORM) TRIM(CHID),'_',I,'_','lsrcfb.sf'
      ENDIF
      WRITE(LU_SMV,'(A,5X,I3,5X,F7.2)') 'SLCT ',I,0.1
      WRITE(LU_SMV,'(A)')FN_SLCF_LS(13)
      WRITE(LU_SMV,'(A)') 'LS Rcfb S&R'
      WRITE(LU_SMV,'(A)') 'LS Rcfb S&R'
      WRITE(LU_SMV,'(A)') 'm/s'
    ENDDO
  ENDIF
ENDIF

!-- ASCII files of level set quantities

!--Time of arrival binary format
!LU_TOA_LS = GET_FILE_NUMBER()
!OPEN(LU_TOA_LS,FILE='time_of_arrival.txt',FORM='UNFORMATTED',STATUS='REPLACE')
!WRITE(LU_TOA_LS) NX_LS,NY_LS
!WRITE(LU_TOA_LS) XS,XF,YS,YF

!--Time of arrival ASCII format
!LU_TOA_LS = GET_FILE_NUMBER()
!OPEN(LU_TOA_LS,FILE='toa_LS.txt',STATUS='REPLACE')
!WRITE(LU_TOA_LS,'(I5)') NX_LS,NY_LS
!WRITE(LU_TOA_LS,'(F7.2)') XS,XF,YS,YF

!Write across row (TOA(1,1), TOA(1,2), ...) to match Farsite output
!WRITE(LU_TOA_LS,'(F7.2)') ((TOA(IDUM,JDUM),JDUM=1,NY_LS),IDUM=1,NX_LS)
!CLOSE(LU_TOA_LS)

!--Rate of spread ASCII format (
!LU_ROSX_LS = GET_FILE_NUMBER()
!OPEN(LU_ROSX_LS,FILE='rosx_LS.txt',STATUS='REPLACE')
!WRITE(LU_ROSX_LS,'(I5)') NX_LS,NY_LS
!WRITE(LU_ROSX_LS,'(F7.2)') XS,XF,YS,YF
!LU_ROSY_LS = GET_FILE_NUMBER()
!OPEN(LU_ROSY_LS,FILE='rosy_LS.txt',STATUS='REPLACE')
!WRITE(LU_ROSY_LS,'(I5)') NX_LS,NY_LS
!WRITE(LU_ROSY_LS,'(F7.2)') XS,XF,YS,YF

!--Fire line intensity ASCII format
!LU_FLI_LS = GET_FILE_NUMBER()
!OPEN(LU_FLI_LS,FILE='fli_LS.txt',STATUS='REPLACE')
!WRITE(LU_FLI_LS,'(I5)') NX_LS,NY_LS
!WRITE(LU_FLI_LS,'(F7.2)') XS,XF,YS,YF

!--Crown Fire Probability (Cruz & Alexander) ASCII format
!LU_CRWN_PROB_LS = GET_FILE_NUMBER()
!OPEN(LU_CRWN_PROB_LS,FILE='crwn_prob_LS.txt',STATUS='REPLACE')
!WRITE(LU_CRWN_PROB_LS,'(I5)') NX_LS,NY_LS
!WRITE(LU_CRWN_PROB_LS,'(F7.2)') XS,XF,YS,YF

!--Computational grid
ALLOCATE(X_LS(NX_LS))   ; CALL ChkMemErr('VEGE:LEVEL SET','X_LS',IZERO)
ALLOCATE(Y_LS(NY_LS+1)) ; CALL ChkMemErr('VEGE:LEVEL SET','Y_LS',IZERO)

!--Aspect of terrain slope for elliptical model (currently not used)
ALLOCATE(ASPECT(NX_LS,NY_LS)); CALL ChkMemErr('VEGE:LEVEL SET','ASPECT',IZERO) ; ASPECT = 0.0_EB
    
!Location of computation grid-cell faces
DO I = 0,NX_LS-1
!X_LS(I+1) = -0.5_EB*LX + 0.5_EB*DX_LS + DX_LS*REAL(I,EB)
!X_LS(I+1) = XS + 0.5_EB*DX_LS + DX_LS*REAL(I,EB)
 X_LS(I+1) = XS + 0.5_EB*DX(I) + DX(I)*REAL(I,EB)
ENDDO
!
DO J = 0,NY_LS
 Y_LS(J+1) = YS + DY_LS*REAL(J,EB)
ENDDO

!Compute components of terrain slope gradient and magnitude of gradient

GRADIENT_ILOOP: DO I = 1,NX_LS
 IM1=I-1 ; IM2=I-2
 IP1=I+1 ; IP2=I+2

 IF (I==1) IM1 = I
 IF (I==NX_LS) IP1 = I
 
 DO J = 1,NY_LS
   JM1=J-1
   JP1=J+1
    
   IF (J==1) JM1 = J
   IF (J==NX_LS) JP1 = J
   
   !GIS-type slope calculation
   !Probably not needed, but left in for experimental purposes
   !G_EAST  = ZT(IP1,JP1) + 2._EB * ZT(IP1,J) + ZT(IP1,JM1) 
   !G_WEST  = ZT(IM1,JP1) + 2._EB * ZT(IM1,J) + ZT(IM1,JM1) 
   !G_NORTH = ZT(IM1,JP1) + 2._EB * ZT(I,JP1) + ZT(IP1,JP1) 
   !G_SOUTH = ZT(IM1,JM1) + 2._EB * ZT(I,JM1) + ZT(IP1,JM1) 
   !
   !DZTDX(I,J) = (G_EAST-G_WEST) / (8._EB*DX_LS)
   !DZTDY(I,J) = (G_NORTH-G_SOUTH) / (8._EB*DY_LS)
   
   G_EAST  = 0.5_EB*( ZT(I,J) + ZT(IP1,J) )
   G_WEST  = 0.5_EB*( ZT(I,J) + ZT(IM1,J) )
   G_NORTH = 0.5_EB*( ZT(I,J) + ZT(I,JP1) )
   G_SOUTH = 0.5_EB*( ZT(I,J) + ZT(I,JM1) )

   DZTDX(I,J) = (G_EAST-G_WEST) * RDX(I) !IDX_LS
   DZTDY(I,J) = (G_NORTH-G_SOUTH) * RDY(J) !IDY_LS


   MAG_ZT(I,J) = SQRT(DZTDX(I,J)**2 + DZTDY(I,J)**2)
   
   ASPECT(I,J) = PIO2 - ATAN2(-DZTDY(I,J),-DZTDX(I,J)) 
   IF (ASPECT(I,J) < 0.0_EB) ASPECT(I,J) = 2._EB*PI + ASPECT(I,J)

 ENDDO

ENDDO GRADIENT_ILOOP

!
!_____________________________________________________________________________
!
! Initialize arrays for head, flank, and back fire spread rates with values
! explicitly declared in the input file or from FARSITE head fire and ellipse
! based flank and back fires. 
! Fill arrays for the horizontal component of the velocity arrays.
! Initialize level set scalar array PHI

PHI_MIN_LS = -1._EB
PHI_MAX_LS =  1._EB
!PHI_LS     = PHI_MIN_LS
!PHI_LS     = LSET_PHI(1:NX_LS,1:NY_LS,1)
PHI_LS     = LSET_PHI(0:IBP1,0:JBP1,1)

LSET_INIT_WALL_CELL_LOOP: DO IW=1,N_EXTERNAL_WALL_CELLS+N_INTERNAL_WALL_CELLS
  WC  => WALL(IW)
  IF (WC%BOUNDARY_TYPE==NULL_BOUNDARY) CYCLE LSET_INIT_WALL_CELL_LOOP
  SF  => SURFACE(WC%SURF_INDEX)
  SF%VEG_LSET_SURF_HEIGHT = MAX(0.001_EB,SF%VEG_LSET_SURF_HEIGHT)
  WC%VEG_HEIGHT = SF%VEG_LSET_SURF_HEIGHT
! WC%VEG_HEIGHT = 0.0_EB

  IIG = WC%IIG
  JJG = WC%JJG
  KKG = WC%KKG

! Ignite landscape at user specified location if ignition is at time zero
  IF (SF%VEG_LSET_IGNITE_TIME == 0.0_EB .AND. T_BEGIN >= 0._EB) THEN 
!print '(A,ES12.4,1x,3I)','veg1:LS lset_ignite_time,iig,jjg ',sf%veg_lset_ignite_time,iig,jjg
    PHI_LS(IIG,JJG) = PHI_MAX_LS 
    BURN_TIME_LS(IIG,JJG) = 99999.0_EB
!   IF (SF%HRRPUA > 0.0_EB) THEN !mimic burner
!     WC%VEG_LSET_SURFACE_HEATFLUX = -SF%HRRPUA
!     IF (VEG_LEVEL_SET_SURFACE_HEATFLUX) WC%QCONF = WC%VEG_LSET_SURFACE_HEATFLUX
!     WC%LSET_FIRE = .TRUE.
!   ENDIF
  ENDIF

! Wind field 
  U_LS(IIG,JJG) = U(IIG,JJG,KKG) ; U_LS_AVG(IIG,JJG) = 0.0_EB
  V_LS(IIG,JJG) = V(IIG,JJG,KKG) ; V_LS_AVG(IIG,JJG) = 0.0_EB
!WRITE(LU_OUTPUT,*)'veg: u,v_ls(i,j)',u_ls(iig,jjg),v_ls(iig,jjg)

  IF (.NOT. SF%VEG_LSET_SPREAD) CYCLE LSET_INIT_WALL_CELL_LOOP
!WRITE(LU_OUTPUT,*)'x,y,z and U,V',X(IIG),Y(JJG),Z(KKG),U(IIG,JJG,KKG),V(IIG,JJG,KKG)

  !Diagnostics
  !WRITE(LU_OUTPUT,*)'IIG,JJG',iig,jjg
  !WRITE(LU_OUTPUT,*)'ROS_HEAD',SF%VEG_LSET_ROS_HEAD
  !WRITE(LU_OUTPUT,*)'ROS_HEAD,ROS_FLANK,ROS_BACK',SF%VEG_LSET_ROS_HEAD,SF%VEG_LSET_ROS_FLANK,SF%VEG_LSET_ROS_BACK


  UMAG     = SQRT(U_LS(IIG,JJG)**2 + V_LS(IIG,JJG)**2)

  HEAD_WIDTH(IIG,JJG)= DX(1) !DX_LS
  ROS_HEAD_SURF(IIG,JJG)  = SF%VEG_LSET_ROS_HEAD
  ROS_FLANK(IIG,JJG) = SF%VEG_LSET_ROS_FLANK
  ROS_BACKU(IIG,JJG) = SF%VEG_LSET_ROS_BACK
  WIND_EXP(IIG,JJG)  = SF%VEG_LSET_WIND_EXP
  
!If any surfaces uses tan^2 function for slope, tan^2 will be used throughout simulation
  IF (SF%VEG_LSET_TAN2) LSET_TAN2=.TRUE.
  
!Compute head ROS and coefficients when using the assumption of ellipsed shaped fireline
  IF_ELLIPSE:IF (SF%VEG_LSET_ELLIPSE) THEN    
    
!-- If any surfaces set to ellipse, then elliptical model used for all surfaces 
    IF (.NOT. LSET_ELLIPSE) LSET_ELLIPSE=.TRUE.

!-- AU grassland fire, head ROS at IIG,JJG assunig infinite head width
    IF (SF%VEG_LSET_SURFACE_FIRE_HEAD_ROS_MODEL=='AU GRASS' .AND. .NOT.SF%VEG_LSET_BURNER) & 
          CALL AUGRASS_HEADROS(NM,IIG,JJG,KKG,SF%VEG_LSET_SURF_HEIGHT,SF%VEG_LSET_SURF_EFFM)
!     UMAG = SQRT(U_LS(IIG,JJG)**2 + V_LS(IIG,JJG)**2)
!     ROS_HEAD_SURF(IIG,JJG)  = (0.165_EB + 0.534_EB*UMAG)*EXP(-0.108*SF%VEG_LSET_SURF_EFFM)
!   ENDIF

!---Ellipse assumption with WFDS derived head ROS as a fuction of a local wind velocity measure
      IF (SF%VEG_LSET_SURFACE_FIRE_HEAD_ROS_MODEL=='ROSvsU' .AND. .NOT. SF%VEG_LSET_BURNER) &
           CALL ROSVSU_HEADROS(NM,IIG,JJG,KKG,SF%VEG_LSET_SURF_HEIGHT,SF%VEG_LSET_UAVG_K,SF%VEG_LSET_UAVG_TIME, &
                               SF%VEG_LSET_ROS_HEAD)

!-- Find Rothermel surface veg head fire ROS at IIG,JJG
    IF (SF%VEG_LSET_SURFACE_FIRE_HEAD_ROS_MODEL=='ROTHERMEL') THEN    

      COMPUTE_HEADROS_FM10=.FALSE. ; COMPUTE_FM10_SRXY=.FALSE. ; COMPUTE_RSA_SRXY=.FALSE.

!---- Slope factors for surface fuel
      CALL ROTH_SLOPE_COEFF(NM,IIG,JJG,SF%VEG_LSET_BETA)

!---- Slope factors for fuel model 10
      IF (SF%VEG_LSET_CROWN_FIRE_HEAD_ROS_MODEL=='SR') THEN
        VEG_BETA_FM10 = 0.0173_EB !weighted packing ratio for fuel model 10
        VEG_SV_FM10   = 5788._EB*0.01_EB !weighted surface-to-volume ratio in 1/cm for fuel model 10
        CALL FM10_SLOPE_COEFF(NM,IIG,JJG,VEG_BETA_FM10)
      ENDIF

!---- Wind, combined wind & slope, midflame windspeed factors, and head ROS for surface fuels at IIG,JJG
!     If S&F crown fire model is to be implemented at this location, then compute Rsa head ROS using previously
!     computed wind field and surface fuel characteristics.
      COMPUTE_HEADROS_FM10 = .FALSE. ; COMPUTE_HEADROS_RSA = .FALSE. 
      IF (SF%VEG_LSET_CROWN_FIRE_HEAD_ROS_MODEL=='SR') COMPUTE_HEADROS_RSA=.TRUE.
      CALL ROTH_WINDANDSLOPE_COEFF_HEADROS(NM,IIG,JJG,KKG,SF%VEG_LSET_BETA,SF%VEG_LSET_SIGMA,SF%VEG_LSET_SURF_HEIGHT, &
           SF%VEG_LSET_CANOPY_HEIGHT,SF%VEG_LSET_CANOPY_BULK_DENSITY,SF%VEG_LSET_ROTH_ZEROWINDSLOPE_ROS, &
           SF%VEG_LSET_ROTHFM10_ZEROWINDSLOPE_ROS,COMPUTE_HEADROS_FM10,COMPUTE_HEADROS_RSA, &
           SF%VEG_LSET_WAF_UNSHELTERED,SF%VEG_LSET_WAF_SHELTERED)

      COMPUTE_HEADROS_RSA=.FALSE.
    ENDIF

!-- Scott and Reinhardt crown fire model
    IF (SF%VEG_LSET_CROWN_FIRE_HEAD_ROS_MODEL=='SR') THEN    
      I_CROWN_INI = (0.01_EB*SF%VEG_LSET_CANOPY_BASE_HEIGHT*(460._EB+25.9_EB*SF%VEG_LSET_CANOPY_FMC))**1.5_EB
      ROS_SURF_INI_LS(IIG,JJG)  = 1000._EB*I_CROWN_INI/(SF%VEG_LSET_SURF_LOAD*SF%VEG_LSET_HEAT_OF_COMBUSTION)
!if(jjg==30)print '(A,1x,1I3,6ES12.4)','I,CBH,FMC,Iini,load,Hc,Rini',iig,sf%veg_lset_canopy_base_height,sf%veg_lset_canopy_fmc, &
!                                                i_crown_ini,sf%veg_lset_surf_load,sf%veg_lset_heat_of_combustion, &
!                                                ros_surf_ini_ls(iig,jjg)
      RAC_THRESHOLD_LS(IIG,JJG) = 3.0_EB/(60.0_EB*SF%VEG_LSET_CANOPY_BULK_DENSITY) !m/s

!---- Wind, combined wind & slope, midflame windspeed factors, and head ROS for Fuel Model 10 at IIG,JJG
      COMPUTE_HEADROS_FM10 = .TRUE. ; COMPUTE_HEADROS_RSA=.FALSE.
      CALL ROTH_WINDANDSLOPE_COEFF_HEADROS(NM,IIG,JJG,KKG,VEG_BETA_FM10,VEG_SV_FM10,SF%VEG_LSET_SURF_HEIGHT, &
           SF%VEG_LSET_CANOPY_HEIGHT,SF%VEG_LSET_CANOPY_BULK_DENSITY,SF%VEG_LSET_ROTH_ZEROWINDSLOPE_ROS,     &
           SF%VEG_LSET_ROTHFM10_ZEROWINDSLOPE_ROS,COMPUTE_HEADROS_FM10,COMPUTE_HEADROS_RSA, &
           SF%VEG_LSET_WAF_UNSHELTERED,0.4_EB)

!---- Define values in a 2D array that flags, at each x,y location which method is used to compute
!     the passive crown fire rate of spread:
!     1 = S&R method, Rfinal=Ra=Rs+CFB(3.35R10+Rs)  
!     2 = FARSITE method, Rfinal=Rs for Ra<RAC, Rfinal=Ra for Ra>=RAC  
      IF(SF%VEG_LSET_MODEL_FOR_PASSIVE_ROS == 'SR') FLAG_MODEL_FOR_PASSIVE_ROS(IIG,JJG) = 1
      IF(SF%VEG_LSET_MODEL_FOR_PASSIVE_ROS == 'FS') FLAG_MODEL_FOR_PASSIVE_ROS(IIG,JJG) = 2
!if(jjg==30)print '(A,A,1x,2I3)','model for passive ros,IIG,flag ',sf%veg_lset_model_for_passive_ros,i,flag_model_for_passive_ros(i,j)

      COMPUTE_HEADROS_FM10=.FALSE. ; COMPUTE_FM10_SRXY=.FALSE. ; COMPUTE_RSA_SRXY=.FALSE.
    ENDIF

!-- Cruz et al. crown fire head fire ROS model (needed to determine time step based on surface and crown fire head ROS)
    IF (SF%VEG_LSET_CROWN_FIRE_HEAD_ROS_MODEL=='CRUZ' .AND. VEG_LEVEL_SET_UNCOUPLED) THEN    
      VERT_CANOPY_EXTENT = SF%VEG_LSET_CANOPY_HEIGHT - SF%VEG_LSET_SURF_HEIGHT - SF%VEG_LSET_FUEL_STRATA_GAP
      CALL CRUZ_CROWN_FIRE_HEADROS(NM,IIG,JJG,KKG,SF%VEG_LSET_CANOPY_BULK_DENSITY,SF%VEG_LSET_SURF_EFFM,            &
           SF%VEG_LSET_FUEL_STRATA_GAP,SF%VEG_LSET_SURF_LOAD,SF%VEG_LSET_CRUZ_PROB_PASSIVE,                         &
           SF%VEG_LSET_CRUZ_PROB_ACTIVE,SF%VEG_LSET_CRUZ_PROB_CROWN,SF%VEG_LSET_SURFACE_FIRE_HEAD_ROS_MODEL,        &
           VERT_CANOPY_EXTENT,SF%VEG_LSET_CANOPY_HEIGHT)
    ENDIF
  
  ENDIF IF_ELLIPSE

ENDDO LSET_INIT_WALL_CELL_LOOP

UMAX_LS  = MAXVAL(ABS(U_LS))
VMAX_LS  = MAXVAL(ABS(V_LS))
UMAG     = SQRT(UMAX_LS**2 + VMAX_LS**2)

!WRITE(LU_OUTPUT,*)'before assign ROS'
!WRITE(LU_OUTPUT,*)'ROS_HEAD max',MAXVAL(ROS_HEAD)
!ROS_HEAD1 = MAXVAL(ROS_HEAD)
!WRITE(LU_OUTPUT,*)'ROS_HEAD1',ROS_HEAD1

SR_MAX_SURF  = MAXVAL(ROS_HEAD_SURF)
SR_MAX_FM10  = MAXVAL(ROS_HEAD_FM10)
SR_MAX   = MAX(SR_MAX_SURF,SR_MAX_FM10)
SR_MAX   = MAX(SR_MAX,MAXVAL(ROS_FLANK))
DYN_SR_MAX = 0._EB

! Write diagnostic to standard output
!WRITE(LU_OUTPUT,*)'ROS_HEAD max',MAXVAL(ROS_HEAD)
!ROS_HEAD1 = MAXVAL(ROS_HEAD)
!WRITE(LU_OUTPUT,*)'ROS_HEAD1',ROS_HEAD1

IF (LSET_ELLIPSE) THEN
    PRINT*,'Mesh number',NM
    PRINT*,'Phi_S max',MAXVAL(PHI_S)
    PRINT*,'Phi_W max',MAXVAL(PHI_W)
    PRINT*,'UMF max',MAXVAL(UMF)
    PRINT*,'Mag_zt max',MAXVAL(MAG_ZT)
    PRINT*,'Max surf head ROS',SR_MAX_SURF
    PRINT*,'Max FM10 head ROS',SR_MAX_FM10
    PRINT*,'Overall max ROS',SR_MAX

!   WRITE(LU_OUTPUT,*)'Mesh number',NM
!   WRITE(LU_OUTPUT,*)'Phi_S max',MAXVAL(PHI_S)
!   WRITE(LU_OUTPUT,*)'Phi_W max',MAXVAL(PHI_W)
!   WRITE(LU_OUTPUT,*)'UMF max',MAXVAL(UMF)
!   WRITE(LU_OUTPUT,*)'Mag_zt max',MAXVAL(MAG_ZT)
!   WRITE(LU_OUTPUT,*)'Max surf head ROS',SR_MAX_SURF
!   WRITE(LU_OUTPUT,*)'Max FM10 head ROS',SR_MAX_FM10
!   WRITE(LU_OUTPUT,*)'Overall max ROS',SR_MAX
ENDIF

IF (.NOT. LSET_ELLIPSE) SR_MAX   = 2._EB*SR_MAX !rough accounting for upslope spread aligned with wind

IF (VEG_LEVEL_SET_UNCOUPLED) THEN
 DT_LS = 0.5_EB*MIN(DX(1),DY(1))/SR_MAX
!IF (LOCK_TIME_STEP) DT_LS = 0.05_EB*DT_LS
 IF (LOCK_TIME_STEP) DT_LS = 0.125_EB*DT_LS
!DT_LS = MESHES(NM)%DT
 MESHES(NM)%DT = DT_LS
 DT      = DT_LS
 DT_NEXT = DT_LS
ENDIF

! Initialize the level set field
LSET_PHI(0:IBP1,0:JBP1,1) = PHI_LS

!DT_LS = 0.1603_EB !to make AU F19 ignition sequence work

WRITE(LU_OUTPUT,1113)nm,dt_ls
1113 format('vegelsini nm, dt_ls ',1(i2),2x,1(ES12.4))
!WRITE(LU_OUTPUT,*)'flux limiter= ',LIMITER_LS

END SUBROUTINE INITIALIZE_LEVEL_SET_FIREFRONT

!************************************************************************************************
SUBROUTINE ROTH_SLOPE_COEFF(NM,I,J,VEG_BETA)
!************************************************************************************************
!
! Compute components and magnitude of slope coefficient vector that 
! are used in the Rothermel spread rate formula. These, along with the zero wind and zero slope
! Rothermel ROS (given in the input file) and wind coefficient vector (computed below) 
! are used to obtain the local surface fire spread rate
!
INTEGER,  INTENT(IN) :: I,J,NM
REAL(EB), INTENT(IN) :: VEG_BETA
REAL(EB) :: DZT_DUM,DZT_MAG2

!Limit effect to slope lte 80 degrees
!Phi_s_x,y are slope factors
!DZT_DUM = MIN(5.67_EB,ABS(DZTDX(I,J))) ! 5.67 ~ tan 80 deg, used in LS paper, tests show equiv to 60 deg max
DZT_DUM = MIN(1.73_EB,ABS(DZTDX(I,J))) ! 1.73 ~ tan 60 deg
PHI_S_X(I,J) = 5.275_EB * ((VEG_BETA)**(-0.3_EB)) * DZT_DUM**2
PHI_S_X(I,J) = SIGN(PHI_S_X(I,J),DZTDX(I,J))

DZT_DUM = MIN(1.73_EB,ABS(DZTDY(I,J))) ! 1.73 ~ tan 60 deg, used in LS paper
PHI_S_Y(I,J) = 5.275_EB * ((VEG_BETA)**(-0.3_EB)) * DZT_DUM**2
PHI_S_Y(I,J) = SIGN(PHI_S_Y(I,J),DZTDY(I,J))

PHI_S(I,J) = SQRT(PHI_S_X(I,J)**2 + PHI_S_Y(I,J)**2) !used in LS paper
!DZT_MAG2 = DZTDX(I,J)**2 + DZTDY(I,J)**2
!PHI_S(I,J) = 5.275_EB * ((VEG_BETA)**(-0.3_EB)) * DZT_MAG2

END SUBROUTINE ROTH_SLOPE_COEFF

!************************************************************************************************
SUBROUTINE FM10_SLOPE_COEFF(NM,I,J,VEG_BETA_FM10)
!************************************************************************************************
!
! Compute components and magnitude of slope coefficient vector that 
! are used in the Rothermel spread rate formula for fuel model 10. These, along with the zero wind and zero slope
! Rothermel ROS (given in the input file) and wind coefficient vector (computed below) 
! are used to obtain the local surface fire spread rate for fuel model 10
!
INTEGER,  INTENT(IN) :: I,J,NM
REAL(EB), INTENT(IN) :: VEG_BETA_FM10
REAL(EB) :: DZT_DUM,DZT_MAG2

!Limit effect to slope lte 80 degrees
!Phi_s_x,y are slope factors
!DZT_DUM = MIN(5.67_EB,ABS(DZTDX(I,J))) ! 5.67 ~ tan 80 deg, used in LS paper, tests show equiv to 60 deg max
DZT_DUM = MIN(1.73_EB,ABS(DZTDX(I,J))) ! 1.73 ~ tan 60 deg
PHI_S_X_FM10(I,J) = 5.275_EB * ((VEG_BETA_FM10)**(-0.3_EB)) * DZT_DUM**2
PHI_S_X_FM10(I,J) = SIGN(PHI_S_X_FM10(I,J),DZTDX(I,J))

DZT_DUM = MIN(1.73_EB,ABS(DZTDY(I,J))) ! 1.73 ~ tan 60 deg, used in LS paper
PHI_S_Y_FM10(I,J) = 5.275_EB * ((VEG_BETA_FM10)**(-0.3_EB)) * DZT_DUM**2
PHI_S_Y_FM10(I,J) = SIGN(PHI_S_Y_FM10(I,J),DZTDY(I,J))

PHI_S_FM10(I,J) = SQRT(PHI_S_X_FM10(I,J)**2 + PHI_S_Y_FM10(I,J)**2)
!DZT_MAG2 = DZTDX(I,J)**2 + DZTDY(I,J)**2
!PHI_S(I,J) = 5.275_EB * ((VEG_BETA)**(-0.3_EB)) * DZT_MAG2

END SUBROUTINE FM10_SLOPE_COEFF

!************************************************************************************************
SUBROUTINE ROTH_WINDANDSLOPE_COEFF_HEADROS(NM,I,J,K,VEG_BETA,VEG_SIGMA,SURF_VEG_HT,CANOPY_VEG_HT,CANOPY_BULK_DENSITY, &
                                           ZEROWINDSLOPE_ROS,ZEROWINDSLOPE_ROS_FM10,COMPUTE_HEADROS_FM10, &
                                           COMPUTE_HEADROS_RSA,WAF_UNSHELTERED,WAF_SHELTERED)
!************************************************************************************************
!
! Compute components and magnitude of the wind coefficient vector and the combined
! wind and slope coefficient vectors and use them along with the user defined zero wind, zero slope
! Rothermel (or Behave) surface fire ROS in the Rothermel surface fire spread rate
! formula to obtain the magnitude of the local surface head fire ROS. Top of vegetation is assumed
! to be at the bottom of the computational doamin.

LOGICAL,  INTENT(IN) :: COMPUTE_HEADROS_FM10,COMPUTE_HEADROS_RSA
INTEGER,  INTENT(IN) :: I,J,K,NM
REAL(EB), INTENT(IN) :: CANOPY_VEG_HT,CANOPY_BULK_DENSITY,SURF_VEG_HT,VEG_BETA,VEG_SIGMA,WAF_UNSHELTERED,WAF_SHELTERED,  &
                        ZEROWINDSLOPE_ROS,ZEROWINDSLOPE_ROS_FM10
LOGICAL :: UNIFORM_UV
INTEGER :: KDUM,KWIND
REAL(EB) :: CONSFCTR,FCTR1,FCTR2,MAG_PHI,PHI_WS,PHI_W_X,PHI_W_Y,PHI_W_X_FM10,PHI_W_Y_FM10,PHX,PHY,U6PH,UMF_MAG,UMF_X, &
            UMF_X_FM10,UMF_Y,UMF_Y_FM10,VEG_HT,V6PH,WAF_6M,WAF_MID,Z6PH,ZWFDS
REAL(EB) :: PHI_W_X_SA,PHI_W_Y_SA,PHI_W_SA,PHI_WS_SA,PHX_SA,PHY_SA,UMF_6M_FROM_SACOMPUTE,UMF_MAG_FROM_SACOMPUTE
REAL(EB) :: FCTR_U6m

REAL(EB), POINTER, DIMENSION(:,:) :: PHI_W_P=>NULL(),PHI_WS_P=>NULL(),THETA_ELPS_P=>NULL()

!Placeholder arrays
THETA_ELPS_P => WORK1_LS
PHI_W_P      => WORK2_LS !don't need this to be an array, except for downstread diagnostics

! Initialize S&R coefficients
PHI_W_X_SA = 0.0_EB
PHI_W_Y_SA = 0.0_EB
PHI_W_SA   = 0.0_EB

!print*,'n_csvf',n_csvf
!print*,'crown_veg',crown_veg
!print*,'k,z(k-1),z(k)',k,z(k-1),z(k)

VEG_HT = MAX(SURF_VEG_HT,CANOPY_VEG_HT)
FCTR1 = 0.64_EB*VEG_HT !constant in logrithmic wind profile Albini & Baughman INT-221 1979 or 
!                       !Andrews RMRS-GTR-266 2012 (p. 8, Eq. 4)
FCTR2 = 1.0_EB/(0.13_EB*VEG_HT) !constant in log wind profile
Z6PH  = 6.1_EB + VEG_HT
ZWFDS = ZC(K) - Z(K-1) !Height of velocity in first cell above veg, ZC(K)=cell center, Z(K-1)=height of K cell bottom
UNIFORM_UV = .FALSE.
!
!Find the wind components at 6.1 m above the vegetation for the case of a uniform
!wind field (i.e., equivalent to conventional FARSITE). This was used in 2015 LS & 
!FARSITE paper. N_CSVF = 0 when no initial wind field has been read in from a file.
IF (N_CSVF == 0 .AND. VEG_LEVEL_SET_UNCOUPLED) THEN
  U6PH = U_LS(I,J) 
  V6PH = V_LS(I,J)
  UNIFORM_UV = .TRUE.
ENDIF
!
!Find the wind components at 6.1 m (20 feet) above the vegetation for the case of nonuniform wind field. 
!The wind field can be predefined and read in at code initialization or the level set computation 
!is coupled to the CFD computation
!
!---U,V at 6.1 above the veg height computed from the WAF when vegetation height + 6.1 m is above or 
!   equal to the first u,v location on grid
!print*,'zwfds,z6ph,uniform_uv',zwfds,z6ph,uniform_uv
KWIND = 0
KDUM = 0
IF (ZWFDS <= 6.1_EB .AND. .NOT. UNIFORM_UV) THEN 
!Find k array index for first grid cell that has ZC > 6.1 m 
   KWIND = 0
   KDUM  = K
   DO WHILE (ZWFDS <= 6.1_EB) !this assumes the bottom computational boundary = top of veg
      KWIND = KDUM
      KDUM  = KDUM + 1
      ZWFDS = ZC(KDUM) - Z(K-1)
   ENDDO
   ZWFDS = ZC(KWIND) - Z(K-1)
   WAF_6M = LOG((Z6PH-FCTR1)*FCTR2)/LOG((ZWFDS+VEG_HT-FCTR1)*FCTR2) !wind adjustment factor from log wind profile
   U6PH  = WAF_6M*U(I,J,KWIND)
   V6PH  = WAF_6M*V(I,J,KWIND)
ENDIF
!
!---U,V at 6.1 m above the veg height computed from the WAF when vegetation height + 6.1 m is below
!   first u,v location on grid
IF (ZWFDS > 6.1_EB .AND. .NOT. UNIFORM_UV) THEN 
   WAF_6M = LOG((Z6PH-FCTR1)*FCTR2)/LOG((ZWFDS+VEG_HT-FCTR1)*FCTR2) 
   U6PH  = WAF_6M*U(I,J,K)
   V6PH  = WAF_6M*V(I,J,K)
ENDIF
!
!Obtain mid-flame wind adjustment factor
!Log profile based wind adjustiment for unsheltered or sheltered conditions are from 
!Andrews 2012, USDA FS Gen Tech Rep. RMRS-GTR-266 (with added SI conversion)
!When using Andrews log formula for sheltered wind the crown fill portion, f, is 0.2
IF (CANOPY_VEG_HT == 0.0_EB) THEN
  WAF_MID = WAF_UNSHELTERED !WAF is from input file
  IF (WAF_UNSHELTERED == -99.0_EB) &
      WAF_MID=1.83_EB/LOG((20.0_EB + 1.18_EB*VEG_HT)/(0.43_EB*VEG_HT))!used in LS vs FS paper
!if(x(i)==21 .and. y(j)==2) print '(A,2x,L2,1ES12.4)','----crown_veg, waf_mid =',crown_veg,waf_mid
ELSE
  WAF_MID = WAF_SHELTERED !WAF is from input file
  IF (WAF_SHELTERED == -99.0_EB)   &
      WAF_MID=0.555_EB/(SQRT(0.20_EB*3.28_EB*VEG_HT)*LOG((20.0_EB + 1.18_EB*VEG_HT)/(0.43_EB*VEG_HT)))
!if(x(i)==21 .and. y(j)==2) print '(A,2x,L2,1ES12.4)','++++crown_veg, waf_mid =',crown_veg,waf_mid
ENDIF

!if (i==41 .and. j==41) then
!print 1116,k,kwind,zwfds,zc(kwind),u(i,j,k),u(i,j,kwind),waf_6m,waf_mid
!endif
!1116 format('(vege,rothwind)',1x,2(I3),1x,6(e15.5))
!
!!Factor 60 converts U from m/s to m/min which is used in the Rothermel model.  
UMF_X = WAF_MID * U6PH * 60.0_EB
UMF_Y = WAF_MID * V6PH * 60.0_EB
  
!Variables used in Phi_W formulas below (Rothermel model)
B_ROTH = 0.15988_EB * (VEG_SIGMA**0.54_EB)
C_ROTH = 7.47_EB * EXP(-0.8711_EB * (VEG_SIGMA**0.55_EB))
E_ROTH = 0.715_EB * EXP(-0.01094_EB * VEG_SIGMA)
BETA_OP_ROTH = 0.20395_EB * (VEG_SIGMA**(-0.8189_EB))! Optimum packing ratio
     
! Find components of wind factor PHI_W_X, and PHI_W_Y
CONSFCTR = C_ROTH * (3.281_EB**B_ROTH) * (VEG_BETA / BETA_OP_ROTH)**(-E_ROTH)

!PHI_W_X = CONSFCTR*(ABS(UMF_X))**B_ROTH
!PHI_W_X = SIGN(PHI_W_X,UMF_X)
!PHI_W_Y = CONSFCTR*(ABS(UMF_Y))**B_ROTH
!PHI_W_Y = SIGN(PHI_W_Y,UMF_Y)
!PHI_W_P(I,J) =  SQRT(PHI_W_X**2 + PHI_W_Y**2) 

UMF_MAG = SQRT(UMF_X**2 + UMF_Y**2)
IF (UMF_MAG > 0.0_EB) THEN
  PHI_W_X = CONSFCTR*UMF_MAG**B_ROTH*UMF_X/UMF_MAG
  PHI_W_Y = CONSFCTR*UMF_MAG**B_ROTH*UMF_Y/UMF_MAG
  PHI_W_P(I,J) = SQRT(PHI_W_X**2 + PHI_W_Y**2) 
ELSE
  PHI_W_X = 0.0_EB
  PHI_W_Y = 0.0_EB
  PHI_W_P(I,J) = 0.0_EB 
ENDIF

!Computations for S&R crown model's Rsa during call for surface fire ROS
IF(COMPUTE_HEADROS_RSA .AND. UMF_MAG > 0.0_EB) THEN
  FCTR_U6m  = 3._EB/(200.4_EB*CANOPY_BULK_DENSITY*ZEROWINDSLOPE_ROS_FM10) - 1._EB - PHI_S_FM10(I,J)
  FCTR_U6m  = MAX(0.0_EB,FCTR_U6m) !catches case when slope dominates
  UMF_6M_FROM_SACOMPUTE  = 1.14_EB*FCTR_U6m**0.7_EB
  UMF_6M_FROM_SACOMPUTE  = UMF_6M_FROM_SACOMPUTE * 60.0_EB !convert m/s to m/min for use in Rothermel
!if(j==25) print '(A,1x,1I3,5ES12.4)','I,UMF 6m Rsa,cbd,Roo10,phi_s_fm10,phi_s',i,umf_6m_from_sacompute,canopy_bulk_density, &
!                                                                         zerowindslope_ros_fm10,phi_s_fm10(i,j),phi_s(i,j)
  UMF_MAG_FROM_SACOMPUTE = WAF_MID*UMF_6M_FROM_SACOMPUTE
  PHI_W_X_SA = CONSFCTR*UMF_MAG_FROM_SACOMPUTE**B_ROTH*UMF_X/UMF_MAG
  PHI_W_Y_SA = CONSFCTR*UMF_MAG_FROM_SACOMPUTE**B_ROTH*UMF_Y/UMF_MAG
  PHI_W_SA   = SQRT(PHI_W_X_SA**2 + PHI_W_Y_SA**2) 
ENDIF
     

! Find combined wind and slope factor PHI_WS and effective midflame windspeed UMF
IF (PHI_S(I,J) > 0.0_EB) THEN      
        
  IF(COMPUTE_HEADROS_FM10) THEN !for S&R crown fire model
    PHX = PHI_W_X + PHI_S_X_FM10(I,J)
    PHY = PHI_W_Y + PHI_S_Y_FM10(I,J)
  ENDIF
  IF(COMPUTE_HEADROS_RSA) THEN !surface and crown fuel with S&R crown fire model
    PHX = PHI_W_X + PHI_S_X(I,J)
    PHY = PHI_W_Y + PHI_S_Y(I,J)
    PHX_SA = PHI_W_X_SA + PHI_S_X(I,J) !For Rsa
    PHY_SA = PHI_W_Y_SA + PHI_S_Y(I,J)
    PHI_WS_SA = SQRT(PHX_SA**2 + PHY_SA**2)
  ENDIF
  IF(.NOT. COMPUTE_HEADROS_FM10 .AND. .NOT. COMPUTE_HEADROS_RSA) THEN !surface fuel only
    PHX = PHI_W_X + PHI_S_X(I,J)
    PHY = PHI_W_Y + PHI_S_Y(I,J)
  ENDIF

  MAG_PHI = SQRT(PHX**2 + PHY**2)
        
!Magnitude of total phi (phi_w + phi_s) for use in spread rate section
  PHI_WS = MAG_PHI
        
!Theta_elps, after adjustment below, is angle of direction (0 to 2pi) of highest spread rate
!0<=theta_elps<=2pi as measured clockwise from Y-axis. ATAN2(y,x) is the angle, measured in the
!counterclockwise direction, between the positive x-axis and the line through (0,0) and (x,y)
!positive x-axis  
  THETA_ELPS_P(I,J) = ATAN2(PHY,PHX)
        
!"Effective midflame windspeed" used in length-to-breadth ratio calculation (spread rate routine)
! is the wind + slope effect obtained by solving Phi_w eqs. above for UMF
! 8/8/13 - Changed phi_ws to Phi_s below to match Farsite, i.e., instead of adding phi_w and phi_s
! and then calculating effective wind speed, phi_s is converted to an effected wind speed and added
! to UMF calculated from the wind. Effective U has units of m/min in Wilson formula.
! 0.3048 ~= 1/3.281
!if phi_s < 0 then a complex value (NaN) results. Using abs(phi_s) and sign function to correct.
        
  UMF_TMP = (((ABS(PHI_S_X(I,J)) * (VEG_BETA / BETA_OP_ROTH)**E_ROTH)/C_ROTH)**(1/B_ROTH))*0.3048
  UMF_TMP = SIGN(UMF_TMP,PHI_S_X(I,J)) 
  UMF_X   = UMF_X + UMF_TMP
        
  UMF_TMP = (((ABS(PHI_S_Y(I,J)) * (VEG_BETA / BETA_OP_ROTH)**E_ROTH)/C_ROTH)**(1/B_ROTH))*0.3048
  UMF_TMP = SIGN(UMF_TMP,PHI_S_Y(I,J))
  UMF_Y   = UMF_Y + UMF_TMP

ELSE !zero slope case
     
   PHI_WS = PHI_W_P(I,J)
   IF(COMPUTE_HEADROS_RSA) PHI_WS_SA = PHI_W_SA
!  PHI_WS = SQRT (PHI_W_X**2 + PHI_W_Y**2)
   !IF (PHY == 0._EB) PHY = 1.E-6_EB
   !0<= Theta_elps <=2pi as measured clockwise from Y-axis 
   THETA_ELPS_P(I,J) = ATAN2(PHI_W_Y,PHI_W_X)    

ENDIF
    
!The following two lines convert ATAN2 output to compass system (0 to 2 pi CW from +Y-axis)
THETA_ELPS_P(I,J) = PIO2 - THETA_ELPS_P(I,J)
IF (THETA_ELPS_P(I,J) < 0.0_EB) THETA_ELPS_P(I,J) = 2.0_EB*PI + THETA_ELPS_P(I,J)

! Assign values for Fuel Model 10 vegetation or surface fuel (note THETA_ELPS surface is assumed to be = THETA_ELPS_FM10)
IF(COMPUTE_HEADROS_FM10) THEN
  PHI_W_FM10(I,J) = PHI_W_P(I,J) !PHI_W does not need to be an array, except for diagnotic purposes
  THETA_ELPS_FM10 = THETA_ELPS_P
  UMF_FM10(I,J)   = SQRT(UMF_X**2 + UMF_Y**2)
  ROS_HEAD_FM10(I,J) = ZEROWINDSLOPE_ROS_FM10*(1.0_EB + PHI_WS)

ELSE
  PHI_W(I,J) = PHI_W_P(I,J)
  THETA_ELPS = THETA_ELPS_P
  UMF(I,J)   = SQRT(UMF_X**2 + UMF_Y**2) !used in LS vs FS paper
! UMF(I,J) = UMF(I,J) + (((PHI_S(I,J) * (VEG_BETA / BETA_OP_ROTH)**E_ROTH)/C_ROTH)**(1/B_ROTH))*0.3048
  ROS_HEAD_SURF(I,J)    = ZEROWINDSLOPE_ROS*(1.0_EB + PHI_WS)    !used in LS vs FS paper
! ROS_HEAD_SURF(I,J)  = 0.099_EB + 0.095_EB*UMF(I,J)*0.0167_EB + 0.0025_EB*0.000278_EB*UMF(I,J)**2 !WFDS based empirical relation
  IF(COMPUTE_HEADROS_RSA) ROS_HEAD_SA(I,J) = ZEROWINDSLOPE_ROS*(1.0_EB + PHI_WS_SA) !Rsa
!if(compute_headros_rsa .and. j==25) print '(A,1x,1I3,4ES12.4)','I,phi_s_fm10,Roo,phi_ws_sa,rsa',i,phi_s_fm10(i,j),zerowindslope_ros, &
!                                                                phi_ws_sa,ros_head(i,j)
ENDIF

!
!if (i==41 .and. j==41) then
!print 1117,ros_head(i,j)
!print*,'-------------------------'
!endif
!1117 format('(vege,rothROS)',1x,1(e15.5))

END SUBROUTINE ROTH_WINDANDSLOPE_COEFF_HEADROS
!
!************************************************************************************************
SUBROUTINE AUGRASS_HEADROS(NM,I,J,K,VEG_HT,VEG_MOIST)
!************************************************************************************************
!
! Compute the magnitude of the head fire from an empirical AU grass fire formula

INTEGER,  INTENT(IN) :: I,J,K,NM
REAL(EB), INTENT(IN) :: VEG_HT,VEG_MOIST
INTEGER  :: KDUM,KWIND
REAL(EB) :: FCTR1,FCTR2,U2MAGL,UMAG,V2MAGL,WAF_2MAGL,Z2MAGL,ZWFDS 
LOGICAL  :: UNIFORM_UV

FCTR1 = 0.64_EB*VEG_HT !constant in logrithmic wind profile Albini & Baughman INT-221 1979 or 
!                       !Andrews RMRS-GTR-266 2012 (p. 8, Eq. 4)
FCTR2  = 1.0_EB/(0.13_EB*VEG_HT) !constant in log wind profile
Z2MAGL = 2.0_EB - VEG_HT !Height in WFDS grid that's 2m above ground level
ZWFDS  = ZC(K) - Z(K-1) !Height of velocity in first cell above veg, ZC(K)=cell center, Z(K-1)=height of K cell bottom
UNIFORM_UV = .FALSE.
!
!Find the wind components at 2 m above the ground for the case of a uniform
!wind field  
!N_CSVF = 0 when no initial wind field has been read in from a file.
IF (N_CSVF == 0 .AND. VEG_LEVEL_SET_UNCOUPLED) THEN
  U2MAGL = U_LS(I,J) 
  V2MAGL = V_LS(I,J)
  UNIFORM_UV = .TRUE.
ENDIF
!
!Find the wind components at 2 m above the ground for the case of nonuniform wind field. 
!The wind field can be predefined and read in at code initialization or the level set computation 
!is coupled to the CFD computation
!
!---U,V at 2m above ground level (2m - veg height) in WFDS grid computed from the WAF when 2m - vegetation height is above or 
!   equal to the first u,v location on grid
!print*,'zwfds,z6ph,uniform_uv',zwfds,z6ph,uniform_uv
KWIND = 0
KDUM = 0
IF (ZWFDS <= Z2MAGL .AND. .NOT. UNIFORM_UV) THEN 
!Find k array index for first grid cell that has ZC > 2m - VEG_HT
   KWIND = 0
   KDUM  = K
   DO WHILE (ZWFDS <= Z2MAGL) !this assumes the bottom computational boundary = top of veg
      KWIND = KDUM
      KDUM  = KDUM + 1
      ZWFDS = ZC(KDUM) - Z(K-1)
   ENDDO
   ZWFDS = ZC(KWIND) - Z(K-1)
   WAF_2MAGL = LOG((Z2MAGL-FCTR1)*FCTR2)/LOG((ZWFDS-VEG_HT-FCTR1)*FCTR2) !wind adjustment factor from log wind profile
   U2MAGL    = WAF_2MAGL*U(I,J,KWIND)
   V2MAGL    = WAF_2MAGL*V(I,J,KWIND)
ENDIF
!
!---U,V at 2 m above the above the ground computed from the WAF when 2m - vegetation height is below
!   first u,v location on the vertical WFDS grid
IF (ZWFDS > Z2MAGL .AND. .NOT. UNIFORM_UV) THEN 
   WAF_2MAGL = LOG((Z2MAGL-FCTR1)*FCTR2)/LOG((ZWFDS-VEG_HT-FCTR1)*FCTR2) 
   U2MAGL    = WAF_2MAGL*U(I,J,K)
   V2MAGL    = WAF_2MAGL*V(I,J,K)
ENDIF

!Theta_elps, after adjustment below, is angle of direction (0 to 2pi) of highest spread rate
!0<=theta_elps<=2pi as measured clockwise from Y-axis. ATAN2(y,x) is the angle, measured in the
!counterclockwise direction, between the positive x-axis and the line through (0,0) and (x,y)
!positive x-axis  

!Note, unlike the Rothermel ROS case, the slope is assumed to be zero at this point.
THETA_ELPS(I,J) = ATAN2(V2MAGL,U2MAGL)
        
!The following two lines convert ATAN2 output to compass system (0 to 2 pi CW from +Y-axis)
THETA_ELPS(I,J) = PIO2 - THETA_ELPS(I,J)
IF (THETA_ELPS(I,J) < 0.0_EB) THETA_ELPS(I,J) = 2.0_EB*PI + THETA_ELPS(I,J)

!AU grassland head ROS for infinite head width; See Mell et al. "A physics-based approach to 
!modeling grassland fires" Intnl. J. Wildland Fire, 16:1-22 (2007)
UMAG = SQRT(U2MAGL**2 + V2MAGL**2)
ROS_HEAD_SURF(I,J)  = (0.165_EB + 0.534_EB*UMAG)*EXP(-0.108*VEG_MOIST)

END SUBROUTINE AUGRASS_HEADROS
!
!************************************************************************************************
SUBROUTINE ROSVSU_HEADROS(NM,I,J,K,VEG_HT,UAVG_K,UAVG_TIME,ROS_HEAD_CONSTANT)
!************************************************************************************************
!
! Compute the magnitude of the head fire rate of spread as a function of the local wind from a given formula
!
INTEGER,  INTENT(IN) :: I,J,K,NM,UAVG_K
REAL(EB), INTENT(IN) :: VEG_HT,UAVG_TIME,ROS_HEAD_CONSTANT
INTEGER  :: KDUM,KWIND
REAL(EB) :: FCTR1,FCTR2,U2MAGL,UMAG,V2MAGL,WAF_2MAGL,Z2MAGL,ZWFDS 
LOGICAL  :: UNIFORM_UV

CALL POINT_TO_MESH(NM)

FCTR1 = 0.64_EB*VEG_HT !constant in logrithmic wind profile Albini & Baughman INT-221 1979 or 
!                       !Andrews RMRS-GTR-266 2012 (p. 8, Eq. 4)
FCTR2  = 1.0_EB/(0.13_EB*VEG_HT) !constant in log wind profile
Z2MAGL = 2.0_EB  !Height in WFDS wind grid that's 2m above ground level
ZWFDS  = ZC(K) - Z(K-1) !Height of velocity in first cell above veg, ZC(K)=cell center, Z(K-1)=height of K cell bottom
UNIFORM_UV = .FALSE.
!
!Find the wind components at 2 m above the ground for the case of a uniform
!wind field  
!N_CSVF = 0 when no initial wind field has been read in from a file.
IF (N_CSVF == 0 .AND. VEG_LEVEL_SET_UNCOUPLED) THEN
  U2MAGL = U_LS(I,J) 
  V2MAGL = V_LS(I,J)
  UNIFORM_UV = .TRUE.
ENDIF
!
!Find the wind components at 2 m above the ground for the case of nonuniform wind field. 
!The wind field can be predefined and read in at code initialization or the level set computation 
!is coupled to the CFD computation
!
!---U,V at height Z2MAGL in WFDS grid computed using a WAF when Z2MAGL is above or 
!   equal to the first u,v location on grid
!print*,'zwfds,z6ph,uniform_uv',zwfds,z6ph,uniform_uv
KWIND = 0
KDUM  = 0
IF (ZWFDS <= Z2MAGL .AND. .NOT. UNIFORM_UV) THEN 
!Find k array index for first grid cell that has ZC > Z2MAGL 
   KWIND = 0
   KDUM  = K
   DO WHILE (ZWFDS < Z2MAGL) !this assumes the bottom computational boundary ground (which is true for the wind field?)
      KWIND = KDUM
      KDUM  = KDUM + 1
      ZWFDS = ZC(KDUM) - Z(K-1)
   ENDDO
   ZWFDS     = ZC(KWIND) - Z(K-1)
   WAF_2MAGL = LOG((Z2MAGL-FCTR1)*FCTR2)/LOG((ZWFDS-FCTR1)*FCTR2) !wind adjustment factor from log wind profile
   U2MAGL    = WAF_2MAGL*U(I,J,KWIND)
   V2MAGL    = WAF_2MAGL*V(I,J,KWIND)
ENDIF
!
!---U,V at 2 m above the above the ground computed from the WAF when height Z2MAGL is below
!   first u,v location on the vertical WFDS grid
IF (ZWFDS > Z2MAGL .AND. .NOT. UNIFORM_UV) THEN 
   WAF_2MAGL = LOG((Z2MAGL-FCTR1)*FCTR2)/LOG((ZWFDS-FCTR1)*FCTR2) 
   U2MAGL    = WAF_2MAGL*U(I,J,K)
   V2MAGL    = WAF_2MAGL*V(I,J,K)
ENDIF

!
! --- Use user supplied grid index to specifiy U2MAGL
IF (UAVG_K /= -1) THEN

!Unaveraged velocity components at k=UAVG_K
  U2MAGL = U(I,J,UAVG_K)
  V2MAGL = V(I,J,UAVG_K)

! U2MAGL = 0.5_EB*(U(I,J,2) + U(I,J,3))
! V2MAGL = 0.5_EB*(V(I,J,2) + V(I,J,3))

!4 point horizontal average of U at k=UAVG_K where UAVG_K is specifice in the input file
! U2MAGL = 0.25_EB*( U(I-1,J,UAVG_K) + U(I,J+1,UAVG_K) + U(I+1,J,UAVG_K) + U(I,J-1,UAVG_K) )
! V2MAGL = 0.25_EB*( V(I-1,J,UAVG_K) + V(I,J+1,UAVG_K) + V(I+1,J,UAVG_K) + V(I,J-1,UAVG_K) )

!1/2 of 4 point horizontal average of U at k=UAVG_K where UAVG_K is specifice in the input file
! U2MAGL = 0.5_EB*0.25_EB*( U(I-1,J,UAVG_K) + U(I,J+1,UAVG_K) + U(I+1,J,UAVG_K) + U(I,J-1,UAVG_K) )
! V2MAGL = 0.5_EB*0.25_EB*( V(I-1,J,UAVG_K) + V(I,J+1,UAVG_K) + V(I+1,J,UAVG_K) + V(I,J-1,UAVG_K) )

!1/2 of 5 point horizontal average of U at k=UAVG_K where UAVG_K is specified in the input file
! U2MAGL = 0.5_EB*(0.5_EB*(0.25_EB*( U(I-1,J,UAVG_K) + U(I,J+1,UAVG_K) + U(I+1,J,UAVG_K) + U(I,J-1,UAVG_K) ) + &
!                         U(I,J,UAVG_K)) )
! V2MAGL = 0.5_EB*(0.5_EB*(0.25_EB*( V(I-1,J,UAVG_K) + V(I,J+1,UAVG_K) + V(I+1,J,UAVG_K) + V(I,J-1,UAVG_K) ) + &
!                         V(I,J,UAVG_K)) )

!4 point horizontal average of 1/2 (U(k=2)+U(k=3)), i.e., velocity component at z=2m on a dz=1m grid
! U2MAGL = 0.5_EB*0.25_EB*( U(I-1,J,2)+U(I-1,J,3) + U(I,J+1,2)+U(I,J+1,3) + U(I+1,J,2)+U(I+1,J,3) + &
!                   U(I,J-1,2)+U(I,J-1,3) )
! V2MAGL = 0.5_EB*0.25_EB*( V(I-1,J,2)+V(I-1,J,3) + V(I,J+1,2)+V(I,J+1,3) + V(I+1,J,2)+V(I+1,J,3) + &
!                   V(I,J-1,2)+V(I,J-1,3) )

!4 point horizontal average of (2/3)*U(k=1)+(1/3)*U(k=2)), i.e., velocity component at z=2m on a dz=2m grid
! U2MAGL = 0.25_EB*( 0.666_EB*U(I-1,J,1)+0.333_EB*U(I-1,J,2) + 0.666_EB*U(I,J+1,1)+0.333_EB*U(I,J+1,2) + &
!                    0.666_EB*U(I+1,J,1)+0.333_EB*U(I+1,J,2) + 0.666_EB*U(I,J-1,1)+0.333_EB*U(I,J-1,2) )
! V2MAGL = 0.25_EB*( 0.666_EB*V(I-1,J,1)+0.333_EB*V(I-1,J,2) + 0.666_EB*V(I,J+1,1)+0.333_EB*V(I,J+1,2) + &
!                    0.666_EB*V(I+1,J,1)+0.333_EB*V(I+1,J,2) + 0.666_EB*V(I,J-1,1)+0.333_EB*V(I,J-1,2) )

ENDIF

! -- Use U0,V0 to define THETA_ELPS. This is need for LS5 when the ambient wind speed is zero 
!    because the local, fire generated, winds will result in a fire that does not spread as 
!    observed (e.g., back or flank instead of head)
!    Other wise VEG_LSET_UAVG_K needs to be set. 
IF (LEVEL_SET_MODE == 5) THEN 
  IF (U0 /= 0.0_EB .OR. V0 /= 0.0_EB) THEN
    U2MAGL = U0
    V2MAGL = V0
  ENDIF
ENDIF

!Theta_elps, after adjustment below, is angle of direction (0 to 2pi) of highest spread rate
!0<=theta_elps<=2pi as measured clockwise from Y-axis. ATAN2(y,x) is the angle, measured in the
!counterclockwise direction, between the positive x-axis and the line through (0,0) and (x,y)
!positive x-axis  

!Note, unlike the Rothermel ROS case, the slope is assumed to be zero at this point in code development.
THETA_ELPS(I,J) = ATAN2(V2MAGL,U2MAGL)

!The following two lines convert ATAN2 output to compass system (0 to 2 pi CW from +Y-axis)
THETA_ELPS(I,J) = PIO2 - THETA_ELPS(I,J)
IF (THETA_ELPS(I,J) < 0.0_EB) THETA_ELPS(I,J) = 2.0_EB*PI + THETA_ELPS(I,J)

!Midflame wind speed for use length-to-breadth ratio when using the elliptical fire perimeter assumption
UMF(I,J) = SQRT(U2MAGL**2 + V2MAGL**2)*60._EB !m/min place holder until proper WAF, or other, approach is used
!UMF(I,J) = SQRT(U_LS(I,J)**2 + V_LS(I,J)**2)*60._EB !m/min place holder until proper WAF, or other, approach is used

!--Empirical relation based on WFDS runs in C064 AU grassland experiment with M=6

IF(LEVEL_SET_MODE /= 5) THEN 

!Use instantaneous umag in empirical ROS vs umag equation
  UMAG = SQRT(U2MAGL**2 + V2MAGL**2)
  ROS_HEAD_SURF(I,J)  = 0.099_EB + 0.095_EB*UMAG + 0.0025_EB*UMAG**2

!Find time average of Umag and use in emprical ROS vs umag equation
  U_LS_AVG(I,J)  = U_LS_AVG(I,J) + U2MAGL
  V_LS_AVG(I,J)  = V_LS_AVG(I,J) + V2MAGL
  NSUM_T_UAVG_LS = NSUM_T_UAVG_LS + 1
  SUM_T_UAVG_LS  = SUM_T_UAVG_LS + DT_LS

  IF (FIRST_AVG_FLAG_LS == 0) THEN !using running average until time reaches duration of averaging time window
    UMAG = SQRT(U_LS_AVG(I,J)**2 + V_LS_AVG(I,J)**2)/REAL(NSUM_T_UAVG_LS,EB)
    ROS_HEAD_SURF(I,J)  = 0.099_EB + 0.095_EB*UMAG + 0.0025_EB*UMAG**2
  ENDIF

  IF (SUM_T_UAVG_LS >= UAVG_TIME) THEN    
    UMAG = SQRT(U_LS_AVG(I,J)**2 + V_LS_AVG(I,J)**2)/REAL(NSUM_T_UAVG_LS,EB)
    ROS_HEAD_SURF(I,J)  = 0.099_EB + 0.095_EB*UMAG + 0.0025_EB*UMAG**2
    NSUM_T_UAVG_LS = 0
    SUM_T_UAVG_LS  = 0.0_EB
    FIRST_AVG_FLAG_LS = 1
  ENDIF

ELSE

  ROS_HEAD_SURF(I,J) = ROS_HEAD_CONSTANT

ENDIF

END SUBROUTINE ROSVSU_HEADROS
!
!************************************************************************************************
SUBROUTINE CRUZ_CROWN_FIRE_HEADROS(NM,I,J,K,CBD,EFFM,FSG,SFC,PROB_PASSIVE,PROB_ACTIVE,PROB_CROWN,SURFACE_FIRE_HEAD_ROS_MODEL, &
                                   VERT_CANOPY_EXTENT,CANOPY_HEIGHT)
!************************************************************************************************
!
! Compute the magnitude of the head fire from an empirical formula. See
!(1) Cruz et al. "Modeling the likelihood of crown fire occurrence in conifer forest stands," 
!    Forest Science, 50: 640-657 (2004)
!(2) Cruz et al. "Development and testing of models for predicting crown fire rate of spread
!    in conifer forest stands," 35:1626-1639 (2005)
!
! CBD = Canopy Bulk Density (kg/m^3)
! EFFM = Effective Fine Fuel Moisture (%), moisture content of fine, dead-down surface vegetation
! FSG = Fuel Strata Gap (m), distance from top of surface fuel to lower limit of the raised fuel 
!       (ladder and canopy) that sustain fire propatation
! SFC = total Surface Fuel Consumption (kg/m^2), sum of forest floor and dead-down roundwood fuel 
!       consumed, surrogate for the amount of vegetation consumed during flaming combustion
!

INTEGER,  INTENT(IN) :: I,J,K,NM
REAL(EB), INTENT(IN) :: CBD,EFFM,FSG,SFC,VERT_CANOPY_EXTENT,CANOPY_HEIGHT
CHARACTER(25), INTENT(IN) :: SURFACE_FIRE_HEAD_ROS_MODEL
LOGICAL :: UNIFORM_UV
INTEGER :: KDUM,KWIND
REAL(EB) :: CAC,CROSA,CROSP,CRLOAD,MPM_TO_MPS,MPS_TO_KPH,EXPG,G,FCTR1,FCTR2,GMAX,PROB,PROB_PASSIVE,PROB_ACTIVE, &
            PROB_CROWN,U10PH,V10PH,UMAG,UMF_TMP,VEG_HT,WAF_10m,Z10PH,ZWFDS

CALL POINT_TO_MESH(NM)

MPM_TO_MPS = 1._EB/60._EB
MPS_TO_KPH = 3600._EB/1000._EB

VEG_HT = CANOPY_HEIGHT
FCTR1 = 0.64_EB*VEG_HT !constant in logrithmic wind profile Albini & Baughman INT-221 1979 or 
!                       !Andrews RMRS-GTR-266 2012 (p. 8, Eq. 4)
FCTR2 = 1.0_EB/(0.13_EB*VEG_HT) !constant in log wind profile
Z10PH  = 10.0_EB + VEG_HT
ZWFDS = ZC(K) - Z(K-1) !Height of velocity in first cell above terrain, ZC(K)=cell center, Z(K-1)=height of K cell bottom
UNIFORM_UV = .FALSE.
!
!Find the wind components at 10 m above the vegetation for the case of a uniform
!wind field (i.e., equivalent to conventional FARSITE). 
IF (N_CSVF == 0 .AND. VEG_LEVEL_SET_UNCOUPLED) THEN
  U10PH = U_LS(I,J) 
  V10PH = V_LS(I,J)
  UNIFORM_UV = .TRUE.
ENDIF
!
!Find the wind components at 10 m above the vegetation for the case of nonuniform wind field. 
!The wind field can be predefined and read in at code initialization or the level set computation 
!is coupled to the CFD computation
!
!---U,V at 10 m above the veg height computed from the WAF when vegetation height + 10 m is above or 
!   equal to the first u,v location on grid
!print*,'zwfds,z6ph,uniform_uv',zwfds,z6ph,uniform_uv
KWIND = 0
KDUM  = 0
IF (ZWFDS <= 10.0_EB .AND. .NOT. UNIFORM_UV) THEN 
!Find k array index for first grid cell that has ZC > 10 m 
   KWIND = 0
   KDUM  = K
   DO WHILE (ZWFDS <= 10.0_EB) !this assumes the bottom computational boundary = top of veg
      KWIND = KDUM
      KDUM  = KDUM + 1
      ZWFDS = ZC(KDUM) - Z(K-1)
   ENDDO
   ZWFDS = ZC(KWIND) - Z(K-1)
   WAF_10M = LOG((Z10PH-FCTR1)*FCTR2)/LOG((ZWFDS+VEG_HT-FCTR1)*FCTR2) !wind adjustment factor from log wind profile
   U10PH  = WAF_10M*U(I,J,KWIND)
   V10PH  = WAF_10M*V(I,J,KWIND)
ENDIF
!
!---U,V at 10 m above the veg height computed from the WAF when vegetation height + 10 m is below the 
!   first u,v location on grid
IF (ZWFDS > 10.0_EB .AND. .NOT. UNIFORM_UV) THEN 
   WAF_10M = LOG((Z10PH-FCTR1)*FCTR2)/LOG((ZWFDS+VEG_HT-FCTR1)*FCTR2) 
   U10PH  = WAF_10M*U(I,J,K)
   V10PH  = WAF_10M*V(I,J,K)
ENDIF

!if (i==41 .and. j==41) then
!print 1116,k,kwind,zwfds,zc(kwind),u(i,j,k),u(i,j,kwind),waf_10m
!endif
!1116 format('(vege,cruzwind)',1x,2(I3),1x,5(e15.5))

UMAG = SQRT(U10PH**2 + V10PH**2)*MPS_TO_KPH !wind magnitude at 10 m above canopy, km/hr

!Theta_elps, after adjustment below, is angle of direction (0 to 2pi) of highest spread rate
!0<=theta_elps<=2pi as measured clockwise from Y-axis. ATAN2(y,x) is the angle, measured in the
!counterclockwise direction, between the positive x-axis and the line through (0,0) and (x,y)
!positive x-axis  

!Note, unlike the Rothermel ROS case, the slope is assumed to be zero at this point.
!THETA_ELPS(I,J) = ATAN2(V10PH,U10PH)
        
!The following two lines convert ATAN2 output to compass system (0 to 2 pi CW from +Y-axis)
!THETA_ELPS(I,J) = PIO2 - THETA_ELPS(I,J)
!IF (THETA_ELPS(I,J) < 0.0_EB) THETA_ELPS(I,J) = 2.0_EB*PI + THETA_ELPS(I,J)

!Probability of crowning
GMAX = 4.236_EB + 0.357_EB*UMAG - 0.71_EB*FSG - 0.331*EFFM 
IF (SFC <= 1.0_EB)                     G = GMAX - 4.613_EB
IF (SFC >  1.0_EB .AND. SFC <= 2.0_EB) G = GMAX - 1.856_EB
IF (SFC >  2.0_EB)                     G = GMAX
EXPG = EXP(G)
PROB = EXPG/(1.0_EB + EXPG)

CROSA = 11.02_EB*(UMAG**0.9_EB)*(CBD**0.19_EB)*EXP(-0.17_EB*EFFM)
CROSP = CROSA*EXP(-0.3333_EB*CROSA*CBD)

MIMIC_CRUZ_METHOD: IF (PROB_CROWN <= 1._EB) THEN
!Compute ROS if crown fire exists
  IF(PROB >= PROB_CROWN) THEN

!Theta_elps, after adjustment below, is angle of direction (0 to 2pi) of highest spread rate
!0<=theta_elps<=2pi as measured clockwise from Y-axis. ATAN2(y,x) is the angle, measured in the
!counterclockwise direction, between the positive x-axis and the line through (0,0) and (x,y)
!positive x-axis  

!Note, unlike the Rothermel ROS case, the slope is assumed to be zero at this point so the direction
!of local spread is dependent only on the wind direction.
!This means there is an inconsistency in the handling of the direction of spread in portions of the 
!fireline where PROB >= PROB_CROWN versus PROB < PROB_CROWN. In the latter case the influence of the
!slope on the local direction of spread is accounted for and wil be based on the Rothermel ROS_HEAD.
THETA_ELPS(I,J) = ATAN2(V10PH,U10PH)
        
!The following two lines convert ATAN2 output to compass system (0 to 2 pi CW from +Y-axis)
THETA_ELPS(I,J) = PIO2 - THETA_ELPS(I,J)
IF (THETA_ELPS(I,J) < 0.0_EB) THETA_ELPS(I,J) = 2.0_EB*PI + THETA_ELPS(I,J)

    MASSPUA_CANOPY_CONSUMED(I,J) = 0.0_EB
    CRLOAD = CBD*VERT_CANOPY_EXTENT
    CAC = CROSA*CBD/3._EB
    IF (CAC >= 1._EB) THEN !active crown fire
      ROS_HEAD_CROWN(I,J) = CROSA*MPM_TO_MPS !convert m/min to m/s
      ROS_HEAD(I,J) = ROS_HEAD_CROWN(I,J)
      MASSPUA_CANOPY_CONSUMED(I,J) = CRLOAD
    ELSE !passive crown fire
      ROS_HEAD_CROWN(I,J) = CROSP*MPM_TO_MPS
      ROS_HEAD(I,J) = ROS_HEAD_CROWN(I,J)
      MASSPUA_CANOPY_CONSUMED(I,J) = CRLOAD*MAX(1.0_EB, (PROB - PROB_CROWN)/(1._EB - PROB_CROWN))
    ENDIF
  ENDIF
ENDIF MIMIC_CRUZ_METHOD

PROB_MIN_MAX_METHOD: IF (PROB_CROWN > 1._EB)  THEN !use 
!Compute head fire rate of spread 
  IF (PROB < PROB_PASSIVE) THEN
    IF(SURFACE_FIRE_HEAD_ROS_MODEL .EQ. 'CRUZ') THEN
      ROS_HEAD_CROWN(I,J) = CROSP*MPM_TO_MPS !else use surface ROS specified in input file
      ROS_HEAD(I,J) = ROS_HEAD_CROWN(I,J)
    ENDIF
  ENDIF
  IF (PROB >= PROB_PASSIVE .AND. PROB < PROB_ACTIVE) THEN
    ROS_HEAD_CROWN(I,J) = CROSP*MPM_TO_MPS 
    ROS_HEAD(I,J) = ROS_HEAD_CROWN(I,J)
  ENDIF
  IF (PROB >= PROB_ACTIVE) THEN
    ROS_HEAD_CROWN(I,J) = CROSA*MPM_TO_MPS
    ROS_HEAD(I,J) = ROS_HEAD_CROWN(I,J)
  ENDIF

!Compute crown fraction burned (kg/m^2) for use in QCONF (heat input to atmosphere)
  MASSPUA_CANOPY_CONSUMED(I,J) = 0.0_EB
  IF (PROB >= PROB_PASSIVE) THEN
    CRLOAD = CBD*VERT_CANOPY_EXTENT
    MASSPUA_CANOPY_CONSUMED(I,J) = CRLOAD*MAX(1.0_EB, (PROB - PROB_PASSIVE)/(PROB_ACTIVE - PROB_PASSIVE))
  ENDIF
ENDIF PROB_MIN_MAX_METHOD

!if (i==41 .and. j==41) then
!print 1117,prob,ros_head(i,j)
!print*,'========================='
!endif
!1117 format('(vege,cruzROS)',1x,2(e15.5))

!Store crown fire probability values
CRUZ_CROWN_PROB(I,J) = PROB 

END SUBROUTINE CRUZ_CROWN_FIRE_HEADROS


!************************************************************************************************
SUBROUTINE LEVEL_SET_FIREFRONT_PROPAGATION(T_CFD,NM)
!************************************************************************************************
!
! Time step the scaler field PHI_LS. 
!
USE PHYSICAL_FUNCTIONS, ONLY : DRAG,GET_MASS_FRACTION,GET_SPECIFIC_HEAT,GET_VISCOSITY,GET_CONDUCTIVITY
CHARACTER(5) :: COMPUTE_ROS
INTEGER, INTENT(IN) :: NM
REAL(EB), INTENT(IN) :: T_CFD
LOGICAL :: COMPUTE_FM10_SRXY,COMPUTE_HEADROS_FM10,COMPUTE_HEADROS_RSA,COMPUTE_RSA_SRXY
INTEGER :: J_FLANK,I,II,IIG,IIO,IOR,IPC,IW,J,JJ,JJG,JJO,KK,KKG,KKO,NOM
INTEGER :: IDUM,JDUM,KDUM,KGRID,KWIND,I_FUEL
INTEGER :: KLOC_GAS
!LOGICAL :: IGNITION = .FALSE.
REAL(EB) :: ARO,BURNTIME,BURNOUT_FCTR,BT,FB_TIME_FCTR,FLI,HEAD_WIDTH_FCTR,GRIDCELL_FRACTION,GRIDCELL_TIME, &
            I_CROWN_INI,I_SURF,IGNITION_WIDTH_Y,RFIREBASE_TIME,RGRIDCELL_TIME,ROS_FLANK1, &
            ROS_MAG,R_BURNOUT_FCTR,SHF,TE_TIME_FACTOR,TIME_LS_LAST,TOTAL_FUEL_LOAD,VERT_CANOPY_EXTENT
REAL(EB) :: COSDPHIU,DPHIDX,DPHIDY,DPHIDOTU,DPHIMAG,XI,YJ,ZK,RCP_GAS,TE_HRRPUV,TE_HRR_TOTAL
REAL(EB) :: PHI_CHECK,LSET_PHI_F,LSET_PHI_V
REAL(EB) :: VEG_BETA_FM10,VEG_SV_FM10
REAL(FB) :: TIME_LS_OUT
REAL(EB) :: ZZ_GET(0:N_TRACKED_SPECIES)
REAL(EB) :: C_DRAG,MU_GAS,RE_VEG_PART,RHO_GAS,TMP_G,U2,V2,VEG_DRAG_MIN,VEG_DRAG_RAMP_FCTR,ZLOC_GAS_T,ZLOC_GAS_B

REAL(EB), POINTER, DIMENSION(:,:,:) :: OM_LSET_PHI =>NULL()
TYPE (WALL_TYPE),     POINTER :: WC =>NULL()
TYPE (SURFACE_TYPE),  POINTER :: SF =>NULL()
TYPE (REACTION_TYPE), POINTER :: RN =>NULL()
TYPE (OMESH_TYPE),    POINTER :: OM =>NULL()
TYPE (MESH_TYPE),     POINTER :: MM =>NULL()
CALL POINT_TO_MESH(NM)

IF (.NOT. VEG_LEVEL_SET_UNCOUPLED .AND. .NOT. VEG_LEVEL_SET_COUPLED) RETURN

!--- Initialize variables
HEAD_WIDTH_FCTR  = 1._EB
IGNITION_WIDTH_Y = 1
J_FLANK          = 1
ROS_FLANK1       = 0._EB

IF (VEG_LEVEL_SET_COUPLED) THEN 
!Q       = 0.0_EB !HRRPUV array
 DT_LS   = MESHES(NM)%DT
 TIME_LS = T_CFD
 T_FINAL = TIME_LS + DT_LS
ENDIF

IF (VEG_LEVEL_SET_UNCOUPLED) THEN
 DT_LS   = MESHES(NM)%DT
 TIME_LS = T_CFD
 T_FINAL = TIME_LS + DT_LS 
ENDIF

!IF (NM==1) WRITE(LU_OUTPUT,'(A,1(I2),2x,3(E12.4))')'vege: nm,dt_ls,time_ls,t_final',nm,dt_ls,time_ls,t_final
!
!-- Time step solution using second order Runge-Kutta -----------------------
!
PHI_LS = LSET_PHI(0:IBP1,0:JBP1,1)

DO WHILE (TIME_LS < T_FINAL)

!
!-- Find flank-to-flank distance at base of fire assume symmetry about ymid and
!   define spread rate based on AU head fire width dependence
 IF (.NOT. LSET_ELLIPSE) THEN

!--------------------- Specific to AU grassland fuel experiments --------------------
!  IF (SF%VEG_LSET_HEADWIDTH_DEPENDENCE) THEN
!    ROS_WALL_CELL_LOOP2: DO IW=1,N_EXTERNAL_WALL_CELLS+N_INTERNAL_WALL_CELLS
!     WC  => WALL(IW)
!     IF (WC%BOUNDARY_TYPE==NULL_BOUNDARY) CYCLE ROS_WALL_CELL_LOOP2
!     SF  => SURFACE(WC%SURF_INDEX)
!     IF (.NOT. SF%VEG_LSET_SPREAD) CYCLE ROS_WALL_CELL_LOOP2
!     IF (.NOT. SF%VEG_LSET_HEADWIDTH_DEPENDENCE) CYCLE ROS_WALL_CELL_LOOP2 
!     IIG = WC%ONE_D%IIG
!     JJG = WC%ONE_D%JJG
!!Case C064     
!     IF(TIME_LS > 0._EB .AND. TIME_LS < 27._EB)  HEAD_WIDTH(I,J) = 2._EB*0.9_EB*TIME_LS !Ignition procdure 0.9 m/s rate
!     IF(TIME_LS >= 27._EB) HEAD_WIDTH(I,J) = HEAD_WIDTH(I,J) + 2._EB*ROS_FLANK(I,J)*(TIME_LS-TIME_LS_LAST)
!!Case F19
!!    IF(TIME_LS > 0._EB .AND. TIME_LS < 57._EB)  HEAD_WIDTH(I,J) = 2._EB*1.54_EB*TIME_LS !Ignition procdure 1.54 m/s rate
!!    IF(TIME_LS >= 57._EB .AND. TIME_LS < 100._EB) &
!!                              HEAD_WIDTH(I,J) = HEAD_WIDTH(I,J) + 2._EB*ROS_FLANK(I,J)*(TIME_LS-TIME_LS_LAST)
!!    IF(TIME_LS >= 100._EB) HEAD_WIDTH(I,J) = 100000._EB
!     HEAD_WIDTH_FCTR = EXP(-(0.859_EB + 2.036_EB*UMAG)/HEAD_WIDTH(I,J))
!     IF(ROS_HEAD_SURF(I,J) > 0.0_EB) ROS_HEAD_SURF(I,J)=ROS_HEAD1*HEAD_WIDTH_FCTR
!    ENDDO ROS_WALL_CELL_LOOP2
! ENDIF



!    IF(TIME_LS > 0._EB .AND. TIME_LS < 24._EB)  HEAD_WIDTH = 2._EB*1._EB*TIME_LS !Ignition procdure 1 m/s rate
!    IF(TIME_LS >= 24._EB) HEAD_WIDTH = HEAD_WIDTH + 2._EB*ROS_FLANK1*(TIME_LS - TIME_LS_LAST)
!    TIME_LS_LAST = TIME_LS
!    HEAD_WIDTH_FCTR = EXP(-(0.859_EB + 2.036_EB*UMAG)/HEAD_WIDTH)
!     DO J = 1,NY_LS
!      DO I = 1,NX_LS
!       IF(ROS_HEAD_SURF(I,J) > 0.0_EB) ROS_HEAD_SURF(I,J)=1.48*HEAD_WIDTH_FCTR
!      ENDDO
!     ENDDO

!    IF (HEAD_WIDTH_DEPENDENCE) THEN
!     IGNITION_WIDTH_Y = 3
!     J_FLANK = 0
!     DO JJ = NY_LS/2,NY_LS
!   !  IF(PHI_LS(26,JJ) <= 0.0_EB .AND. J_FLANK==0) J_FLANK = JJ
!      IF(PHI_LS(26,JJ) > 0.0_EB) J_FLANK = J_FLANK + 1
!     ENDDO
!   ! HEAD_WIDTH = 2._EB*(J_FLANK - NY_LS/2)*DY_LS
!     HEAD_WIDTH = 2.0_EB*J_FLANK*DY_LS
!     IF (HEAD_WIDTH < IGNITION_WIDTH_Y) HEAD_WIDTH = IGNITION_WIDTH_Y
!     HEAD_WIDTH_FCTR = EXP(-(0.859_EB + 2.036_EB*UMAG)/HEAD_WIDTH)
!     DO J = 1,NY_LS
!      DO I = 1,NX_LS
!       IF(ROS_HEAD_SURF(I,J) > 0.0_EB) ROS_HEAD_SURF(I,J)=ROS_HEAD1*HEAD_WIDTH_FCTR
!      ENDDO
!     ENDDO
!    ENDIF
 ENDIF
!-----------------------------------------------------------------------------------------

 TIME_LS_LAST = TIME_LS
 VEG_DRAG(:,:,1:8) = 0.0_EB

 WALL_CELL_LOOP1: DO IW=1,N_EXTERNAL_WALL_CELLS+N_INTERNAL_WALL_CELLS
  WC  => WALL(IW)
  IF (WC%BOUNDARY_TYPE==NULL_BOUNDARY) CYCLE WALL_CELL_LOOP1
! IF (WC%BOUNDARY_TYPE/=SOLID_BOUNDARY) CYCLE WALL_CELL_LOOP1
  SF  => SURFACE(WC%SURF_INDEX)

  II  = WC%II 
  JJ  = WC%JJ 
  KK  = WC%KK 
  IIG = WC%IIG
  JJG = WC%JJG
  KKG = WC%KKG
  IOR = WC%IOR
  
!-Ignite landscape at user specified location(s) and time(s) to originate Level Set fire front propagation
  IF (SF%VEG_LSET_IGNITE_TIME > 0.0_EB .AND. SF%VEG_LSET_IGNITE_TIME < DT_LS .AND. T_CFD >= 0._EB) THEN
!print '(A,ES12.4,1x,3I)','veg2:LS lset_ignite_time,iig,jjg ',sf%veg_lset_ignite_time,iig,jjg
    PHI_LS(IIG,JJG) = PHI_MAX_LS 
    BURN_TIME_LS(IIG,JJG) = 99999.0_EB
  ENDIF
  IF (SF%VEG_LSET_IGNITE_TIME >= TIME_LS .AND. SF%VEG_LSET_IGNITE_TIME <= TIME_LS + DT_LS .AND. T_CFD >= 0._EB) THEN 
!print '(A,ES12.4,1x,3I)','veg3:LS lset_ignite_time,iig,jjg ',sf%veg_lset_ignite_time,iig,jjg
    PHI_LS(IIG,JJG) = PHI_MAX_LS 
    BURN_TIME_LS(IIG,JJG) = 99999.0_EB
  ENDIF

  IF (.NOT. SF%VEG_LSET_SPREAD) CYCLE WALL_CELL_LOOP1

  VEG_DRAG(IIG,JJG,0) = REAL(KKG,EB) !for terrain location in drag calc in velo.f90

! --- For the CFIS crown fire model, compute dot product between normal to fireline and wind direction. If location 
!     on fire perimeter is between the flank and backing fires, then skip computation of crown fire ROS and use already 
!     computed surface fire ROS

  IF (SF%VEG_LSET_CROWN_FIRE_HEAD_ROS_MODEL=='CRUZ' .AND. VEG_LEVEL_SET_UNCOUPLED) THEN

    CALL ROTH_WINDANDSLOPE_COEFF_HEADROS(NM,IIG,JJG,KKG,SF%VEG_LSET_BETA,SF%VEG_LSET_SIGMA,SF%VEG_LSET_SURF_HEIGHT, &
      SF%VEG_LSET_CANOPY_HEIGHT,SF%VEG_LSET_CANOPY_BULK_DENSITY,SF%VEG_LSET_ROTH_ZEROWINDSLOPE_ROS, &
      SF%VEG_LSET_ROTHFM10_ZEROWINDSLOPE_ROS,COMPUTE_HEADROS_FM10,COMPUTE_HEADROS_RSA, &
      SF%VEG_LSET_WAF_UNSHELTERED,SF%VEG_LSET_WAF_SHELTERED)

    DPHIDX = PHI_LS(IIG,JJG) - PHI_LS(IIG-1,JJG)
    DPHIDY = PHI_LS(IIG,JJG) - PHI_LS(IIG  ,JJG-1)
    DPHIDOTU = DPHIDX*U(IIG,JJG,KKG) + DPHIDY*V(IIG,JJG,KKG)
    IF (DPHIDOTU == 0.0_EB) THEN !account for zero wind speed
      COSDPHIU = 1._EB !use surface ROS
    ELSE
      UMAG     = SQRT(U(IIG,JJG,KKG)**2 + V(IIG,JJG,KKG)**2)
      DPHIMAG  = SQRT(DPHIDX**2 + DPHIDY**2)
      COSDPHIU = -DPHIDOTU/(UMAG*DPHIMAG) !minus sign to account for direction caused by phi=1,-1 in burned,unburned 
    ENDIF
    IF (COSDPHIU >= COS(SF%VEG_LSET_CROWNFIRE_ANGLE*PI/180._EB)) THEN  
      VERT_CANOPY_EXTENT = SF%VEG_LSET_CANOPY_HEIGHT - SF%VEG_LSET_SURF_HEIGHT - SF%VEG_LSET_FUEL_STRATA_GAP
      CALL CRUZ_CROWN_FIRE_HEADROS(NM,IIG,JJG,KKG,SF%VEG_LSET_CANOPY_BULK_DENSITY,SF%VEG_LSET_SURF_EFFM,     &
             SF%VEG_LSET_FUEL_STRATA_GAP,SF%VEG_LSET_SURF_LOAD,SF%VEG_LSET_CRUZ_PROB_PASSIVE,                    &
             SF%VEG_LSET_CRUZ_PROB_ACTIVE,SF%VEG_LSET_CRUZ_PROB_CROWN,SF%VEG_LSET_SURFACE_FIRE_HEAD_ROS_MODEL,   &
             VERT_CANOPY_EXTENT,SF%VEG_LSET_CANOPY_HEIGHT)
    ENDIF

  ENDIF


!
!****** Update quantities used in the spread rate computation if the Level Set and CFD computation are coupled.
!
  IF_CFD_COUPLED: IF (VEG_LEVEL_SET_COUPLED) THEN

    U_LS(IIG,JJG) = U(IIG,JJG,KKG)
    V_LS(IIG,JJG) = V(IIG,JJG,KKG)

    IF_ELLIPSE: IF (SF%VEG_LSET_ELLIPSE) THEN

!---Ellipse assumption with AU grassland head fire ROS for infinite head width
      IF (SF%VEG_LSET_SURFACE_FIRE_HEAD_ROS_MODEL=='AU GRASS' .AND. .NOT. SF%VEG_LSET_BURNER) &
           CALL AUGRASS_HEADROS(NM,IIG,JJG,KKG,SF%VEG_LSET_SURF_HEIGHT,SF%VEG_LSET_SURF_EFFM)

!---Ellipse assumption with WFDS derived head ROS as a fuction of a local wind velocity measure
      IF (SF%VEG_LSET_SURFACE_FIRE_HEAD_ROS_MODEL=='ROSvsU' .AND. .NOT. SF%VEG_LSET_BURNER) &
           CALL ROSVSU_HEADROS(NM,IIG,JJG,KKG,SF%VEG_LSET_SURF_HEIGHT,SF%VEG_LSET_UAVG_K,SF%VEG_LSET_UAVG_TIME, &
                               SF%VEG_LSET_ROS_HEAD)

!---Ellipse assumption with Rothermel head fire ROS (== FARSITE) and compute ROS_FM10 if S&R crown model is implemented
      IF (SF%VEG_LSET_SURFACE_FIRE_HEAD_ROS_MODEL=='ROTHERMEL' .AND. .NOT. SF%VEG_LSET_BURNER) THEN 
        CALL ROTH_WINDANDSLOPE_COEFF_HEADROS(NM,IIG,JJG,KKG,SF%VEG_LSET_BETA,SF%VEG_LSET_SIGMA,SF%VEG_LSET_SURF_HEIGHT, &
             SF%VEG_LSET_CANOPY_HEIGHT,SF%VEG_LSET_CANOPY_BULK_DENSITY,SF%VEG_LSET_ROTH_ZEROWINDSLOPE_ROS, &
              SF%VEG_LSET_ROTHFM10_ZEROWINDSLOPE_ROS,COMPUTE_HEADROS_FM10,COMPUTE_HEADROS_RSA, &
              SF%VEG_LSET_WAF_UNSHELTERED,SF%VEG_LSET_WAF_SHELTERED)
      ENDIF

!-- Scott and Reinhardt crown fire model
      IF (SF%VEG_LSET_CROWN_FIRE_HEAD_ROS_MODEL=='SR' .AND. .NOT. SF%VEG_LSET_BURNER) THEN 
!---- Wind, combined wind & slope, midflame windspeed factors, and head ROS for Fuel Model 10 at IIG,JJG
        COMPUTE_HEADROS_FM10 = .TRUE.
        VEG_BETA_FM10 = 0.0173_EB !weighted packing ratio for fuel model 10
        VEG_SV_FM10   = 5788._EB*0.01_EB !weighted surface-to-volume ratio in 1/cm for fuel model 10
        CALL ROTH_WINDANDSLOPE_COEFF_HEADROS(NM,IIG,JJG,KKG,VEG_BETA_FM10,VEG_SV_FM10,SF%VEG_LSET_SURF_HEIGHT, &
             SF%VEG_LSET_CANOPY_HEIGHT,SF%VEG_LSET_CANOPY_BULK_DENSITY,SF%VEG_LSET_ROTH_ZEROWINDSLOPE_ROS,     &
             SF%VEG_LSET_ROTHFM10_ZEROWINDSLOPE_ROS,COMPUTE_HEADROS_FM10,COMPUTE_HEADROS_RSA, &
             SF%VEG_LSET_WAF_UNSHELTERED,0.4_EB)
        COMPUTE_HEADROS_FM10=.FALSE. ; COMPUTE_FM10_SRXY=.FALSE. ; COMPUTE_RSA_SRXY=.FALSE.
      ENDIF
    
!--- Cruz et al. crown fire head fire ROS model
      IF (SF%VEG_LSET_CROWN_FIRE_HEAD_ROS_MODEL=='CRUZ' .AND. .NOT. SF%VEG_LSET_BURNER) THEN
! --- Compute dot product between normal to fireline and wind direction. If location on fire perimeter is between the flank
!     and backing fires, then skip computation of crown fire ROS and use already computed surface fire ROS
        DPHIDX = PHI_LS(IIG,JJG) - PHI_LS(IIG-1,JJG)
        DPHIDY = PHI_LS(IIG,JJG) - PHI_LS(IIG  ,JJG-1)
        DPHIDOTU = DPHIDX*U_LS(IIG,JJG) + DPHIDY*V_LS(IIG,JJG)
        IF (DPHIDOTU == 0.0_EB) THEN
          COSDPHIU = 1._EB !use surface ROS
        ELSE
          UMAG     = SQRT(U_LS(IIG,JJG)**2 + V_LS(IIG,JJG)**2)
          DPHIMAG  = SQRT(DPHIDX**2 + DPHIDY**2)
          COSDPHIU = -DPHIDOTU/(UMAG*DPHIMAG) !minus sign to account for direction caused by phi=1,-1 in burned,unburned 
        ENDIF
        IF (COSDPHIU >= COS(SF%VEG_LSET_CROWNFIRE_ANGLE*PI/180._EB)) THEN  
          VERT_CANOPY_EXTENT = SF%VEG_LSET_CANOPY_HEIGHT - SF%VEG_LSET_SURF_HEIGHT - SF%VEG_LSET_FUEL_STRATA_GAP
          CALL CRUZ_CROWN_FIRE_HEADROS(NM,IIG,JJG,KKG,SF%VEG_LSET_CANOPY_BULK_DENSITY,SF%VEG_LSET_SURF_EFFM,     &
             SF%VEG_LSET_FUEL_STRATA_GAP,SF%VEG_LSET_SURF_LOAD,SF%VEG_LSET_CRUZ_PROB_PASSIVE,                    &
             SF%VEG_LSET_CRUZ_PROB_ACTIVE,SF%VEG_LSET_CRUZ_PROB_CROWN,SF%VEG_LSET_SURFACE_FIRE_HEAD_ROS_MODEL,   &
             VERT_CANOPY_EXTENT,SF%VEG_LSET_CANOPY_HEIGHT)
        ENDIF
      ENDIF

    ENDIF IF_ELLIPSE

!--- Compute heat flux into atmosphere
    GRIDCELL_TIME  = 0.0_EB
    RFIREBASE_TIME = 1.0_EB/SF%VEG_LSET_FIREBASE_TIME
    ROS_MAG = SQRT(SR_X_LS(IIG,JJG)**2 + SR_Y_LS(IIG,JJG)**2)
    IF(ROS_MAG > 0.0_EB) THEN
      GRIDCELL_TIME = SQRT(DX(IIG)**2 + DY(JJG)**2)/ROS_MAG
      RGRIDCELL_TIME = 1.0_EB/GRIDCELL_TIME
      GRIDCELL_FRACTION = MIN(1.0_EB,SF%VEG_LSET_FIREBASE_TIME*RGRIDCELL_TIME) !assumes spread direction parallel to grid axes
    ENDIF
    BURNTIME = MAX(SF%VEG_LSET_FIREBASE_TIME,GRIDCELL_TIME) !assumes spread direction parallel to grid axes

    BT  = BURN_TIME_LS(IIG,JJG)
    SHF = 0.0_EB !surface heat flux W/m^2
    WC%LSET_FIRE = .FALSE.

!Determine surface heat flux for fire spread through grid cell. Account for fires with a depth that is smaller
!than the grid cell (GRIDCELL_FRACTION). Also account for partial presence of fire base as fire spreads into 
!and out of the grid cell (FB_TIME_FCTR).

    HRRPUA_OUT(IIG,JJG) = 0.0 !kW/m^2 
    IF (SF%VEG_LSET_CROWN_FIRE_HEAD_ROS_MODEL=='SR') MASSPUA_CANOPY_CONSUMED(IIG,JJG) = &
                  CFB_SR_LS(IIG,JJG)*SF%VEG_LSET_CANOPY_BULK_DENSITY*(SF%VEG_LSET_CANOPY_HEIGHT-SF%VEG_LSET_CANOPY_BASE_HEIGHT) 
    TOTAL_FUEL_LOAD = SF%VEG_LSET_SURF_LOAD + MASSPUA_CANOPY_CONSUMED(IIG,JJG)

    IF_FIRELINE_PASSAGE: IF (PHI_LS(IIG,JJG) >= -SF%VEG_LSET_PHIDEPTH .AND. .NOT. SF%VEG_LSET_BURNER .AND. &
                             .NOT. VEG_LEVEL_SET_BURNERS_FOR_FIRELINE) THEN 

      WC%LSET_FIRE = .TRUE.
      SHF = (1.0_EB-SF%VEG_CHAR_FRACTION)*SF%VEG_LSET_HEAT_OF_COMBUSTION*TOTAL_FUEL_LOAD*RFIREBASE_TIME !max surface heat flux, W/m^2
!if(iig==31 .and. jjg==49 .and. nm==5) print '(A,2x,5ES12.4)','time, charfrac,Hc,w,rfbt =', & 
!            t_cfd,sf%veg_char_fraction,sf%veg_lset_heat_of_combustion,total_fuel_load,rfirebase_time

!Grid cell > fire depth      
      IF (GRIDCELL_FRACTION < 1.0_EB) THEN
        SHF = SHF*GRIDCELL_FRACTION
        FB_TIME_FCTR = 1.0_EB
!       Fire entering cell
        IF (0.0_EB        <= BT .AND. BT <= SF%VEG_LSET_FIREBASE_TIME) FB_TIME_FCTR = BT*RFIREBASE_TIME
!       Fire exiting cell
        IF (GRIDCELL_TIME <  BT .AND. BT <= GRIDCELL_TIME + SF%VEG_LSET_FIREBASE_TIME) FB_TIME_FCTR = &
          1.0_EB - (BT - GRIDCELL_TIME)*RFIREBASE_TIME
!       Fire has left cell
        IF (BT > GRIDCELL_TIME + SF%VEG_LSET_FIREBASE_TIME) WC%LSET_FIRE = .FALSE.
        WC%VEG_HEIGHT = SF%VEG_LSET_SURF_HEIGHT*(1._EB - BT/(SF%VEG_LSET_FIREBASE_TIME+GRIDCELL_TIME))
!       WC%VEG_HEIGHT = 0.0_EB
        BURN_TIME_LS(IIG,JJG) = BURN_TIME_LS(IIG,JJG) + DT_LS

!if(iig==46 .and. jjg==49 .and. nm==5) then 
!   print '(A,2x,7ES12.4)','----time dx>fd, ros, bt, gct, fbt, fctr, shf =',t_cfd,ros_mag,bt,gridcell_time,sf%veg_lset_firebase_time, &
!                                                                          fb_time_fctr,-shf*0.001_EB
!   print '(A,2x,1ES12.4,L2)','cell fract, lset_fire =',gridcell_fraction,wc%lset_fire
!   print '(A,2x,4ES12.4,L2)','----time dtdx>dtfb, shf kW/m2, fb_time_fctr, cell fract, lset_fire =',t_cfd,-shf*0.001_EB,fb_time_fctr, &
!                              gridcell_fraction,wc%lset_fire
!   print '(A,2x,7ES12.4)','ros, hcomb, fuel load, fbt, cfb, probcruz, probin',ros_mag,sf%veg_lset_heat_of_combustion,total_fuel_load,  &
!                              firebase_time,cfb_ls(iig,jjg),CRUZ_CROWN_PROB(IIG,JJG),sf%veg_lset_cruz_prob_crown
!endif
        WC%VEG_LSET_SURFACE_HEATFLUX = -SHF*FB_TIME_FCTR
      ENDIF

!Grid cell <= fire depth      
      IF (GRIDCELL_FRACTION >= 1.0_EB) THEN
        FB_TIME_FCTR = 1.0_EB
!       Fire entering cell
        IF (0.0_EB        <= BT .AND. BT <= GRIDCELL_TIME) FB_TIME_FCTR = BT*RGRIDCELL_TIME
!       Fire exiting cell
        IF (SF%VEG_LSET_FIREBASE_TIME <  BT .AND. BT <= GRIDCELL_TIME + SF%VEG_LSET_FIREBASE_TIME) FB_TIME_FCTR = &
          1.0_EB - (BT - SF%VEG_LSET_FIREBASE_TIME)*RGRIDCELL_TIME
!       Fire has left cell
        IF (BT > GRIDCELL_TIME + SF%VEG_LSET_FIREBASE_TIME) WC%LSET_FIRE = .FALSE.
        WC%VEG_HEIGHT = SF%VEG_LSET_SURF_HEIGHT*(1._EB - BT/(SF%VEG_LSET_FIREBASE_TIME+GRIDCELL_TIME))
!       WC%VEG_HEIGHT = 0.0_EB
        BURN_TIME_LS(IIG,JJG) = BURN_TIME_LS(IIG,JJG) + DT_LS

!if(iig==46 .and. jjg==49 .and. nm==5) then 
!   print '(A,2x,7ES12.4)','++++time dx<=fd, ros, bt, gct, fbt, fctr, shf =',t_cfd,ros_mag,bt,gridcell_time,sf%veg_lset_firebase_time, &
!                                                                            fb_time_fctr,-shf*0.001_EB
!   print '(A,2x,2ES12.4,L2)','cell fract, lset_fire,W =',gridcell_fraction,total_fuel_load,wc%lset_fire
!   print '(A,2x,7ES12.4)','ros, hcomb, fuel load, fbt, cfb, probcruz, probin',ros_mag,sf%veg_lset_heat_of_combustion,total_fuel_load,  &
!                              firebase_time,cfb_ls(iig,jjg),CRUZ_CROWN_PROB(IIG,JJG),sf%veg_lset_cruz_prob_crown
!endif
        WC%VEG_LSET_SURFACE_HEATFLUX = -SHF*FB_TIME_FCTR
      ENDIF

!     IF (WC%LSET_FIRE) HRRPUA_OUT(IIG,JJG) = -WC%VEG_LSET_SURFACE_HEATFLUX*0.001 !kW/m^2 for Smokeview output

    ENDIF IF_FIRELINE_PASSAGE

     
! Stop burning if the fire front residence time is exceeded
    IF (PHI_LS(IIG,JJG) >= -SF%VEG_LSET_PHIDEPTH .AND. .NOT. WC%LSET_FIRE) THEN
        WC%VEG_LSET_SURFACE_HEATFLUX = 0.0_EB
        WC%VEG_HEIGHT = 0.0_EB 
        BURN_TIME_LS(IIG,JJG) = 999999999._EB
    ENDIF

!if(x(iig)==29 .and. y(jjg)==1) then 
!    print '(A,2x,8ES12.4)','time,phi_ls,burn_time_ls,shf,Rx, Ry, cell frac, burntime =',t_cfd,phi_ls(iig,jjg), &
!           burn_time_ls(iig,jjg),wc%veg_lset_surface_heatflux/gridcell_fraction, &
!           sr_x_ls(iig,jjg),sr_y_ls(iig,jjg),gridcell_fraction,burntime
!    print '(A,2x,ES12.4)','phi_ls(x+dx,y)',phi_ls(iig+1,jjg)
!endif

!-- Burner placement as explicitly specified (location,timing, etc.) in the input file
    IF (SF%VEG_LSET_BURNER .AND. .NOT. VEG_LEVEL_SET_BURNERS_FOR_FIRELINE) THEN
      IF (TIME_LS >= SF%VEG_LSET_BURNER_TIME_ON .AND. TIME_LS <= SF%VEG_LSET_BURNER_TIME_OFF) THEN
        WC%VEG_LSET_SURFACE_HEATFLUX = -SF%HRRPUA
        PHI_LS(IIG,JJG) = PHI_MAX_LS 
        WC%LSET_FIRE = .TRUE.
      ELSE
        WC%VEG_LSET_SURFACE_HEATFLUX = 0.0_EB
        WC%LSET_FIRE = .FALSE.
      ENDIF
    ENDIF

!-- Placement of burners as determined from reading a file containing a 2D array with HRRPUA values at times
    IF (VEG_LEVEL_SET_BURNERS_FOR_FIRELINE) THEN
      SHF = (1.0_EB-SF%VEG_CHAR_FRACTION)*SF%VEG_LSET_HEAT_OF_COMBUSTION*TOTAL_FUEL_LOAD*RFIREBASE_TIME !max surface heat flux, W/m^2
      WC%LSET_FIRE = .FALSE.
      WC%VEG_LSET_SURFACE_HEATFLUX = 0.0_EB
      IF (REAL(TIME_LS,FB) <=  LSET_TIME_HRRPUA_BURNER) THEN
        IF(HRRPUA_IN(IIG,JJG) > 0.0_FB) THEN
          IF (HRRPUA_IN(IIG,JJG)*1000._EB >= SF%VEG_LSET_HRRPUA_MINIMUM_FRAC*SHF) WC%VEG_LSET_SURFACE_HEATFLUX = -HRRPUA_IN(IIG,JJG)*1000._EB !W/m^2
          PHI_LS(IIG,JJG) = PHI_MAX_LS 
          WC%LSET_FIRE = .TRUE.
        ENDIF
      ELSE
        DO WHILE (REAL(TIME_LS,FB) > LSET_TIME_HRRPUA_BURNER)
          READ(LU_SLCF_LS(7),END=111) LSET_TIME_HRRPUA_BURNER 
          READ(LU_SLCF_LS(7)) ((HRRPUA_IN(IDUM,JDUM),IDUM=0,IBAR),JDUM=0,JBAR) 
        ENDDO
111     IF(HRRPUA_IN(IIG,JJG) > 0.0) THEN
          IF (HRRPUA_IN(IIG,JJG)*1000._EB >= SF%VEG_LSET_HRRPUA_MINIMUM_FRAC*SHF) WC%VEG_LSET_SURFACE_HEATFLUX = -HRRPUA_IN(IIG,JJG)*1000._EB !W/m^2
          PHI_LS(IIG,JJG) = PHI_MAX_LS 
          WC%LSET_FIRE = .TRUE.
        ENDIF
      ENDIF
!if(iig==46 .and. jjg==49 .and. nm==5) print '(A,2x,3ES12.4,L2)','SHF,HRRPUA_IN,WC%SHF=',shf,hrrpua_in(iig,jjg)*1000._EB,wc%veg_lset_surface_heatflux
    ENDIF

    IF (SF%VEG_LSET_SURFACE_HRRPUA) THEN
      I_FUEL = REACTION(1)%FUEL_SMIX_INDEX
      WC%MASSFLUX(I_FUEL)      = -WC%VEG_LSET_SURFACE_HEATFLUX/SF%VEG_LSET_HEAT_OF_COMBUSTION 
!     WC%MASSFLUX(I_FUEL)      = 0.0_EB !temporaroy
!     WC%ONE_D%MASSFLUX_SPEC(I_FUEL) =  WC%ONE_D%MASSFLUX(I_FUEL) !used in WFDS6
    ENDIF
    IF (VEG_LEVEL_SET_SURFACE_HEATFLUX) WC%QCONF = WC%VEG_LSET_SURFACE_HEATFLUX
    IF (VEG_LEVEL_SET_THERMAL_ELEMENTS) SF%DT_INSERT = DT_LS !**** is this correct?
    IF (WC%LSET_FIRE) HRRPUA_OUT(IIG,JJG) = -WC%VEG_LSET_SURFACE_HEATFLUX*0.001 !kW/m^2 for Smokeview output

!-- LS Drag (follows the method used for BF) varies with height above the terrain according to the fraction 
!   of the grid cell occupied by veg
!   veg height can be < or >= than grid cell height, drag is Reynolds number dependent when VEG_UNIT_DRAG_COEFF
!   is FALSE.
!   Implemented in velo.f90 
!   KKG is the grid cell in the gas phase bordering the terrain (wall). For no terrain, KKG=1 along the "ground" 
!   The Z() array is the height of the gas-phase cell. Z(0) = zmin for the current mesh 

  LS_DRAG: IF (WC%VEG_HEIGHT > 0.0_EB) THEN
 
    VEG_DRAG_RAMP_FCTR = 1.0_EB
!   IF (T-T_BEGIN <= 5.0_EB) VEG_DRAG_RAMP_FCTR = 0.20_EB*(T-T_BEGIN)

    DO KGRID=0,5
      KLOC_GAS   = KKG + KGRID            !gas-phase grid index
      ZLOC_GAS_T = Z(KLOC_GAS)  -Z(KKG-1) !height above terrain of gas-phase grid cell top
      ZLOC_GAS_B = Z(KLOC_GAS-1)-Z(KKG-1) !height above terrain of gas-phase grid cell bottom

      IF (ZLOC_GAS_T <= WC%VEG_HEIGHT) THEN !grid cell filled with veg
        IF (.NOT. SF%VEG_UNIT_DRAG_COEFF) THEN
          TMP_G = TMP(IIG,JJG,KLOC_GAS)
          RHO_GAS  = RHO(IIG,JJG,KLOC_GAS)
          ZZ_GET(1:N_TRACKED_SPECIES) = ZZ(IIG,JJG,KLOC_GAS,1:N_TRACKED_SPECIES)
          CALL GET_VISCOSITY(ZZ_GET,MU_GAS,TMP_G)
          U2 = 0.25*(U(IIG,JJG,KLOC_GAS)+U(IIG-1,JJG,KLOC_GAS))**2
          V2 = 0.25*(V(IIG,JJG,KLOC_GAS)+V(IIG,JJG-1,KLOC_GAS))**2
          RE_VEG_PART = 4._EB*RHO_GAS*SQRT(U2 + V2 + W(IIG,JJG,KLOC_GAS)**2)/SF%VEG_SV/MU_GAS !for cylinder particle
          C_DRAG = 0.0_EB
          IF (RE_VEG_PART > 0.0_EB) C_DRAG = DRAG(RE_VEG_PART,2) !2 is for cylinder, 1 is for sphere
        ELSE
          C_DRAG = 1.0_EB
        ENDIF
        VEG_DRAG(IIG,JJG,KGRID+1)= C_DRAG*SF%VEG_LSET_DRAG_INI*VEG_DRAG_RAMP_FCTR

      ENDIF

      IF (ZLOC_GAS_T >  WC%VEG_HEIGHT .AND. ZLOC_GAS_B < WC%VEG_HEIGHT) THEN !grid cell is partially filled with veg
        IF (.NOT. SF%VEG_UNIT_DRAG_COEFF) THEN
          TMP_G = TMP(IIG,JJG,KLOC_GAS)
          RHO_GAS  = RHO(IIG,JJG,KLOC_GAS)
          ZZ_GET(1:N_TRACKED_SPECIES) = ZZ(IIG,JJG,KLOC_GAS,1:N_TRACKED_SPECIES)
          CALL GET_VISCOSITY(ZZ_GET,MU_GAS,TMP_G)
          U2 = 0.25*(U(IIG,JJG,KLOC_GAS)+U(IIG-1,JJG,KLOC_GAS))**2
          V2 = 0.25*(V(IIG,JJG,KLOC_GAS)+V(IIG,JJG-1,KLOC_GAS))**2
          RE_VEG_PART = 4._EB*RHO_GAS*SQRT(U2 + V2 + W(IIG,JJG,KLOC_GAS)**2)/SF%VEG_SV/MU_GAS !for cylinder particle
          C_DRAG = 0.0_EB
          IF (RE_VEG_PART > 0.0_EB) C_DRAG = DRAG(RE_VEG_PART,2) !2 is for cylinder, 1 is for sphere
        ELSE
          C_DRAG = 1.0_EB
        ENDIF
        VEG_DRAG(IIG,JJG,KGRID+1)= &
                   C_DRAG*SF%VEG_LSET_DRAG_INI*(WC%VEG_HEIGHT-ZLOC_GAS_B)*VEG_DRAG_RAMP_FCTR/(ZLOC_GAS_T-ZLOC_GAS_B)

        IF (KGRID == 0) THEN !compute minimum drag based on user input
         VEG_DRAG_MIN = C_DRAG*SF%VEG_LSET_DRAG_INI*SF%VEG_POSTFIRE_DRAG_FCTR*VEG_DRAG_RAMP_FCTR* &
                          SF%VEG_HEIGHT/(ZLOC_GAS_T-ZLOC_GAS_B)
         VEG_DRAG(IIG,JJG,1) = MAX(VEG_DRAG(IIG,JJG,1),VEG_DRAG_MIN)
        ENDIF
      ENDIF
    ENDDO


  ENDIF LS_DRAG

!   IF (PHI_LS(IIG,JJG) <= SF%VEG_LSET_PHIDEPTH .AND. PHI_LS(IIG,JJG) >= -SF%VEG_LSET_PHIDEPTH) THEN 
!    WC%TMP_F = 373._EB
!    WC%QCONF = SF%VEG_LSET_QCON
!   ENDIF

  ENDIF IF_CFD_COUPLED

! Save Time of Arrival (TOA), Rate of Spread components, Fireline Intensity, etc. for output to be
! read by Smokeview
  IF (PHI_LS(IIG,JJG) >= -SF%VEG_LSET_PHIDEPTH .AND. TOA(IIG,JJG) <= -1.0_EB) THEN 
    TOA(IIG,JJG)=TIME_LS
    ROS_FINAL_MAG_OUT(IIG,JJG) = ROS_FINAL_MAG(IIG,JJG)
    ROS_X_OUT(IIG,JJG) = SR_X_LS(IIG,JJG)
    ROS_Y_OUT(IIG,JJG) = SR_Y_LS(IIG,JJG)
    ROS_SURF_X_OUT(IIG,JJG) = SR_X_SURF_LS(IIG,JJG)
    ROS_SURF_Y_OUT(IIG,JJG) = SR_Y_SURF_LS(IIG,JJG)
    ROS10_X_OUT(IIG,JJG) = SR_X_FM10_LS(IIG,JJG)
    ROS10_Y_OUT(IIG,JJG) = SR_Y_FM10_LS(IIG,JJG)
    RSA_X_OUT(IIG,JJG) = ROS_HEAD_SA(IIG,JJG)
!   RSA_X_OUT(IIG,JJG) = SR_X_RSA_LS(IIG,JJG)
    RSA_Y_OUT(IIG,JJG) = SR_Y_RSA_LS(IIG,JJG)
    RINI_OUT(IIG,JJG)  = ROS_SURF_INI_LS(IIG,JJG)
!   MASSPUA_CANOPY_BURNED = 0.0_EB
!   IF (SF%VEG_LSET_CROWN_FIRE_HEAD_ROS_MODEL=='CRUZ') MASSPUA_CANOPY_BURNED = CFB_LS(IIG,JJG) 
!   IF (SF%VEG_LSET_CROWN_FIRE_HEAD_ROS_MODEL=='SR') &
!        MASSPUA_CANOPY_BURNED = CFB_SR_LS(IIG,JJG)*SF%VEG_LSET_CANOPY_BULK_DENSITY*(SF%VEG_LSET_CANOPY_HEIGHT-SF%VEG_LSET_CANOPY_BASE_HEIGHT) 
    TOTAL_FUEL_LOAD = SF%VEG_LSET_SURF_LOAD + MASSPUA_CANOPY_CONSUMED(IIG,JJG)
    FLI = SQRT(SR_Y_LS(IIG,JJG)**2 + SR_X_LS(IIG,JJG)**2)*(SF%VEG_LSET_HEAT_OF_COMBUSTION*0.001_EB)* &
         (1.0_EB-SF%VEG_CHAR_FRACTION)*TOTAL_FUEL_LOAD
    FLI_OUT(IIG,JJG) = FLI !kW/m
    CRUZ_CROWN_PROB_OUT(IIG,JJG) = CRUZ_CROWN_PROB(IIG,JJG)
    CFB_OUT(IIG,JJG) = CFB_SR_LS(IIG,JJG)
  ENDIF

 ENDDO WALL_CELL_LOOP1

 IF (ANY(PHI_LS==PHI_MAX_LS)) LSET_IGNITION = .TRUE.

!2nd order Runge-Kutta time steppping of level set equation
 PHI_TEMP_LS = PHI_LS 

!RK Stage 1
 RK2_PREDICTOR_LS = .TRUE.
 CALL LEVEL_SET_ADVECT_FLUX(NM)
 PHI1_LS = PHI_LS - DT_LS*FLUX0_LS

!RK Stage2
 RK2_PREDICTOR_LS = .FALSE.
 MAG_SR_OUT       = 0.0_EB
 COMPUTE_ROS='RSURF' ; COMPUTE_FM10_SRXY=.FALSE. ; COMPUTE_RSA_SRXY=.FALSE.
 CALL LEVEL_SET_PERIMETER_SPREAD_RATE(NM,COMPUTE_ROS) 
 IF (VEG_LEVEL_SET_FM10_SPREADRATE) THEN
   COMPUTE_ROS='RFM10' ; COMPUTE_FM10_SRXY=.TRUE.
   CALL LEVEL_SET_PERIMETER_SPREAD_RATE(NM,COMPUTE_ROS) 
   COMPUTE_ROS = 'RSA' ; COMPUTE_FM10_SRXY=.FALSE. ; COMPUTE_RSA_SRXY=.TRUE.
   CALL LEVEL_SET_PERIMETER_SPREAD_RATE(NM,COMPUTE_ROS) 
   CALL LEVEL_SET_SR_CROWNFIRE_OR_NOT(NM)
 ENDIF
 CALL LEVEL_SET_ADVECT_FLUX(NM)
 PHI_LS = PHI_LS - 0.5_EB*DT_LS*(FLUX0_LS + FLUX1_LS)

!The following is done here instead of in Stage 1 RK so updated ROS can be used in coupled LS when
!determining if fire residence time is shorter than a time step.
 COMPUTE_ROS='RSURF' ; COMPUTE_FM10_SRXY=.FALSE. ; COMPUTE_RSA_SRXY=.FALSE.
 CALL LEVEL_SET_PERIMETER_SPREAD_RATE(NM,COMPUTE_ROS) 
 IF (VEG_LEVEL_SET_FM10_SPREADRATE) THEN
   COMPUTE_ROS='RFM10' ; COMPUTE_FM10_SRXY=.TRUE.
   CALL LEVEL_SET_PERIMETER_SPREAD_RATE(NM,COMPUTE_ROS) 
   COMPUTE_ROS='RSA' ; COMPUTE_FM10_SRXY=.FALSE. ; COMPUTE_RSA_SRXY=.TRUE.
   CALL LEVEL_SET_PERIMETER_SPREAD_RATE(NM,COMPUTE_ROS) 
   CALL LEVEL_SET_SR_CROWNFIRE_OR_NOT(NM)
 ENDIF

! Account for heat released by thermal elements (if present). Thermal elements are inserted and
! LP%LSET_HRRPUV is determined in part.f90
IF (VEG_LEVEL_SET_THERMAL_ELEMENTS) THEN
! RCP_GAS    = 0.001_EB !1/(J/kg/K)
! TE_HRR_TOTAL = 0.0_EB
  PARTICLE_LOOP: DO I=1,NLP
    LP  => PARTICLE(I)
    IPC =  LP%CLASS
    PC  => PARTICLE_CLASS(IPC)
    IF(.NOT. LP%LSET_THERMAL_ELEMENT) CYCLE PARTICLE_LOOP
    CALL GET_IJK(LP%X,LP%Y,LP%Z,NM,XI,YJ,ZK,II,JJ,KK)
!   LP%LSET_HRRPUV = 0.01_EB !W/m^3 
!   TE_TIME_FACTOR = 1.0_EB - (T_FINAL-LP%T)/PC%TE_BURNTIME !linear decay with time
    TE_TIME_FACTOR = 1.0_EB !no decay with time
!   TE_TIME_FACTOR = MAX(0.0_EB,TE_TIME_FACTOR)
!   PC%RGB = (/255,0,0/)
!   IF(TE_TIME_FACTOR == 0.0_EB) PC%RGB = (/0,0,0/)
!   TE_HRR_TOTAL  = TE_HRR_TOTAL + TE_TIME_FACTOR*LP%LSET_HRRPUV*DX(II)*DY(JJ)*DZ(KK)
    TE_HRRPUV =  TE_TIME_FACTOR*LP%LSET_HRRPUV
    IF (T_CFD - LP%T > PC%TE_BURNTIME) TE_HRRPUV = 0.0_EB
    IF (T_CFD - LP%T + DT_LS > PC%TE_BURNTIME) TE_HRRPUV = TE_HRRPUV + TE_HRRPUV*(PC%TE_BURNTIME-(T_CFD-LP%T))/DT_LS
    Q(II,JJ,KK) = Q(II,JJ,KK) + TE_HRRPUV
!   D_LAGRANGIAN(II,JJ,KK) = D_LAGRANGIAN(II,JJ,KK)  +  &
!                             TE_TIME_FACTOR*LP%LSET_HRRPUV*RCP_GAS/(RHO(II,JJ,KK)*TMP(II,JJ,KK))
  ENDDO PARTICLE_LOOP
!  CALL REMOVE_PARTICLES(T_CFD,NM)
!print '(A,2x,I3,2x,2ES12.4)','Mesh, Time, TE_HRR_TOTAL (kW) = ',NM,T_CFD,TE_HRR_TOTAL*0.001_EB
ENDIF

!print*,'min,max phi_ls',minval(phi_ls),maxval(phi_ls)

!print*,'max flux0,flux1',maxval(abs(flux0_ls)),maxval(abs(flux1_ls))

!Variable Time Step for simulations uncoupled from the CFD computation
!IF (VEG_LEVEL_SET_UNCOUPLED) THEN
! IF (.NOT. VEG_LEVEL_SET) THEN
!
!   PHI_CHECK = MAXVAL(ABS(PHI_LS - PHI_TEMP_LS)) !Find max change in phi
! 
!   IF (LSET_IGNITION) THEN
!     ! If any phi values change by more than 0.5, or all change less
!     ! than 0.1 (both values are arbitrary), during one time step,
!     ! then adjust time step accordingly.
!     
!     IF (PHI_CHECK > 0.5_EB) THEN
!         ! Cut time step in half and cycle the do-while loop
!         DT_COEF = 0.5_EB * DT_COEF 
!!        DT_LS = DT_COEF * MIN(DX_LS,DY_LS)/DYN_SR_MAX
!         DT_LS = DT_COEF * MIN(DX(1),DY(1))/DYN_SR_MAX
!         DT_LS = MIN(DT_LS,100._EB)
!         PHI_LS = PHI_TEMP_LS ! Exchange for previous phi and cycle
!         print '(A,1x,E13.5,1x,A,i3)',"Halving time step, dt=  ",dt_ls,' mesh ',nm
!         CYCLE 
!     ENDIF
! 
!     ! Increase time step by 1/4 if changes are small
!     IF (PHI_CHECK < 0.1_EB) DT_COEF = DT_COEF * 1.25_EB
!     
!     ! Dynamic Spread Rate Max
!     DYN_SR_MAX = MAX(DYN_SR_MAX,0.01_EB) ! dyn_sr_max must be g.t. zero
!!    DT_LS = DT_COEF * MIN(DX_LS,DY_LS)/DYN_SR_MAX
!     DT_LS = DT_COEF * MIN(DX(1),DY(1))/DYN_SR_MAX
!     DT_LS = MIN(DT_LS,100._EB)
!     
!   ENDIF
! ENDIF
 

 TIME_LS = TIME_LS + DT_LS
 SUMTIME_LS = SUMTIME_LS + DT_LS
 SUM_T_SLCF_LS = SUM_T_SLCF_LS + DT_LS

 LSET_PHI(0:IBP1,0:JBP1,1) = PHI_LS
!MESHES(1)%LSET_PHI(IBP1,:,1) = MESHES(2)%LSET_PHI(   1,:,1)
!MESHES(2)%LSET_PHI(   0,:,1) = MESHES(1)%LSET_PHI(IBAR,:,1)
!if (nm == 2) print '(A,1x,10ES12.4)',meshes(2)%lset_phi(0,0:9,1)

!Runtime output of slice files containing level set variables for smokeview animation
 IF (SUM_T_SLCF_LS >= DT_OUTPUT_LS) THEN    
  SUM_T_SLCF_LS = 0._EB
  PHI_OUT(0:IBAR,0:JBAR) = PHI_LS(0:IBAR,0:JBAR)
  TIME_LS_OUT = TIME_LS
!-- PHI field
  WRITE(LU_SLCF_LS(1)) TIME_LS_OUT
!if (nm ==3) print*,'vege:phi',meshes(3)%lset_phi(12,0,1)
!if (nm ==3) then
! print*,'vege:phi',phi_ls(12,0)
! print*,'vege:phiout',phi_out(12,0)
!endif
!negative for consistency with wall thickness output from wfds and viz by Smokeview
  WRITE(LU_SLCF_LS(1)) ((-PHI_OUT(I,J),I=0,IBAR),J=0,JBAR) 
!if (nm==3) print '(A,1x,1i3,1x,2E13.5)','vege:outslf',nm,phi_ls(12,0),meshes(1)%lset_phi(12,jbp1,1)
!if (nm==1) print '(A,1x,1i3,1x,2E13.5)','vege:outslfout',nm,phi_out(12,ibar)
!-- Time of Arrival, s
  WRITE(LU_SLCF_LS(2)) TIME_LS_OUT
  TOA(0,0:JBAR) = TOA(1,0:JBAR) ; TOA(0:IBAR,0) = TOA(0:IBAR,1) !for Smokeview
  WRITE(LU_SLCF_LS(2)) ((TOA(I,J),I=0,IBAR),J=0,JBAR) 
!-- ROS magnitude, m/s
  WRITE(LU_SLCF_LS(3)) TIME_LS_OUT
  ROS_X_OUT(0,0:JBAR) = ROS_X_OUT(1,0:JBAR) ; ROS_X_OUT(0:IBAR,0) = ROS_X_OUT(0:IBAR,1)
  ROS_Y_OUT(0,0:JBAR) = ROS_Y_OUT(1,0:JBAR) ; ROS_Y_OUT(0:IBAR,0) = ROS_Y_OUT(0:IBAR,1)
  WRITE(LU_SLCF_LS(3)) ((SQRT(ROS_X_OUT(I,J)**2 + ROS_Y_OUT(I,J)**2),I=0,IBAR),J=0,JBAR) 
!-- Fireline intensity at time of fire arrival, kW/m^2
  WRITE(LU_SLCF_LS(4)) TIME_LS_OUT
  FLI_OUT(0,0:JBAR) = FLI_OUT(1,0:JBAR) ; FLI_OUT(0:IBAR,0) = FLI_OUT(0:IBAR,1) !for Smokeview
  WRITE(LU_SLCF_LS(4)) ((FLI_OUT(I,J),I=0,IBAR),J=0,JBAR) 
!-- HRRPUA at every slice output time, kW/m^2
  IF (VEG_LEVEL_SET_COUPLED) THEN
    WRITE(LU_SLCF_LS(5)) TIME_LS_OUT
    HRRPUA_OUT(0,0:JBAR) = HRRPUA_OUT(1,0:JBAR) ; HRRPUA_OUT(0:IBAR,0) = HRRPUA_OUT(0:IBAR,1) !for Smokeview
    WRITE(LU_SLCF_LS(5)) ((HRRPUA_OUT(I,J),I=0,IBAR),J=0,JBAR) 
  ENDIF

!-- temporary output of total HRR so it's available for LS1. Works only for a single grid
!  write(1234,'(1x,2ES12.4)')TIME_LS,SUM(HRRPUA_OUT)*1.  

!-- Crown fire Probability (Cruz & Alexander)
  IF(VEG_LEVEL_SET_CFIS_CROWNFIRE_MODEL) THEN
    WRITE(LU_SLCF_LS(6)) TIME_LS_OUT
    CRUZ_CROWN_PROB_OUT(0,0:JBAR) = CRUZ_CROWN_PROB_OUT(1,0:JBAR) !for Smokeview
    CRUZ_CROWN_PROB_OUT(0:IBAR,0) = CRUZ_CROWN_PROB_OUT(0:IBAR,1) !for Smokeview
    WRITE(LU_SLCF_LS(6)) ((CRUZ_CROWN_PROB_OUT(I,J),I=0,IBAR),J=0,JBAR) 
  ENDIF

  IF(VEG_LEVEL_SET_SR_CROWNFIRE_MODEL) THEN
!-- Crown Fraction Burned from Scott & Reinhardt crown fire model
    WRITE(LU_SLCF_LS(8)) TIME_LS_OUT
    CFB_OUT(0,0:JBAR) = CFB_OUT(1,0:JBAR) !for Smokeview
    CFB_OUT(0:IBAR,0) = CFB_OUT(0:IBAR,1) !for Smokeview
    WRITE(LU_SLCF_LS(8)) ((CFB_OUT(I,J),I=0,IBAR),J=0,JBAR) 
!-- Rsa for Scott & Reinhardt crown fire model
    WRITE(LU_SLCF_LS(9)) TIME_LS_OUT
    RSA_X_OUT(0,0:JBAR) = RSA_X_OUT(1,0:JBAR) ; RSA_X_OUT(0:IBAR,0) = RSA_X_OUT(0:IBAR,1)
    RSA_Y_OUT(0,0:JBAR) = RSA_Y_OUT(1,0:JBAR) ; RSA_Y_OUT(0:IBAR,0) = RSA_Y_OUT(0:IBAR,1)
!   WRITE(LU_SLCF_LS(9)) ((SQRT(RSA_X_OUT(I,J)**2 + RSA_Y_OUT(I,J)**2),I=0,IBAR),J=0,JBAR) 
    WRITE(LU_SLCF_LS(9)) ((RSA_X_OUT(I,J),I=0,IBAR),J=0,JBAR) 
!-- ROS FM10 for Scott & Reinhardt crown fire model
    WRITE(LU_SLCF_LS(10)) TIME_LS_OUT
    ROS10_X_OUT(0,0:JBAR) = ROS10_X_OUT(1,0:JBAR) ; ROS10_X_OUT(0:IBAR,0) = ROS10_X_OUT(0:IBAR,1)
    ROS10_Y_OUT(0,0:JBAR) = ROS10_Y_OUT(1,0:JBAR) ; ROS10_Y_OUT(0:IBAR,0) = ROS10_Y_OUT(0:IBAR,1)
    WRITE(LU_SLCF_LS(10)) ((SQRT(ROS10_X_OUT(I,J)**2 + ROS10_Y_OUT(I,J)**2),I=0,IBAR),J=0,JBAR) 
!-- ROS SURF INI for Scott & Reinhardt crown fire model
    WRITE(LU_SLCF_LS(11)) TIME_LS_OUT
    RINI_OUT(0,0:JBAR) = RINI_OUT(1,0:JBAR) ; RINI_OUT(0:IBAR,0) = RINI_OUT(0:IBAR,1)
    WRITE(LU_SLCF_LS(11)) ((RINI_OUT(I,J),I=0,IBAR),J=0,JBAR) 
!-- ROS surf magnitude, m/s for Scott and Reinhardt
    WRITE(LU_SLCF_LS(12)) TIME_LS_OUT
    ROS_SURF_X_OUT(0,0:JBAR) = ROS_SURF_X_OUT(1,0:JBAR) ; ROS_SURF_X_OUT(0:IBAR,0) = ROS_SURF_X_OUT(0:IBAR,1)
    ROS_SURF_Y_OUT(0,0:JBAR) = ROS_SURF_Y_OUT(1,0:JBAR) ; ROS_SURF_Y_OUT(0:IBAR,0) = ROS_SURF_Y_OUT(0:IBAR,1)
    WRITE(LU_SLCF_LS(12)) ((SQRT(ROS_SURF_X_OUT(I,J)**2 + ROS_SURF_Y_OUT(I,J)**2),I=0,IBAR),J=0,JBAR) 
!-- ROS Final (Passive or Active) Crown Fire, m/s depends on whether Farsite or S&R is used, based on 
    WRITE(LU_SLCF_LS(13)) TIME_LS_OUT
    ROS_FINAL_MAG_OUT(0,0:JBAR) = ROS_FINAL_MAG(1,0:JBAR) ; ROS_FINAL_MAG_OUT(0:IBAR,0) = ROS_FINAL_MAG(0:IBAR,1)
    WRITE(LU_SLCF_LS(13)) ((ROS_FINAL_MAG_OUT(I,J),I=0,IBAR),J=0,JBAR) 
  ENDIF
 ENDIF
!
ENDDO !While loop

!if (nm == 1) print*,'vegprop nm,lset_phi(ibp1,1)',nm,phi_ls(ibp1,1)
!if (nm == 2) print*,'vegprop nm,lset_phi(0,1)',nm,phi_ls(0,1)
!if (nm == 1) print*,'vegprop nm,m(1,2)lset_phi',nm,meshes(1)%lset_phi(ibp1,1,1),meshes(2)%lset_phi(0,1,1)
!if (nm == 2) print*,'vegprop nm,m(1,2)lset_phi',nm,meshes(1)%lset_phi(ibp1,1,1),meshes(2)%lset_phi(0,1,1)
!print 1113,nm,meshes(1)%lset_phi(ibar,25,1),meshes(2)%lset_phi(1,25,1)
!1113 format('vegelsprop nm,lset_phi',1(i2),2x,2(E12.4))

!CLOSE(LU_SLCF_LS)

! ******  Write arrays to ascii file **************
!IF (VEG_LEVEL_SET_UNCOUPLED .AND. NM == 1) THEN
! CALL CPU_TIME(CPUTIME)
! LS_T_END = CPUTIME
! WRITE(LU_OUTPUT,*)'Uncoupled Level Set CPU Time: ',LS_T_END - LS_T_BEG
!ENDIF
!
!-- Output time of arrival
!LU_TOA_LS = GET_FILE_NUMBER()
!print*,'veg:toa_ls',lu_toa_ls
!OPEN(LU_TOA_LS,FILE='time_of_arrival.toa',STATUS='REPLACE')
!WRITE(LU_TOA_LS,'(I5)') NX_LS,NY_LS
!WRITE(LU_TOA_LS,'(F7.2)') XS,XF,YS,YF
!Write across row (TOA(1,1), TOA(1,2), ...) to match Farsite output
!IF (TIME_LS >= T_END) THEN
! print*,'veg:toaf_ls',lu_toa_ls
! WRITE(LU_TOA_LS,'(F7.2)') ((TOA(IDUM,JDUM),JDUM=1,NY_LS),IDUM=1,NX_LS)
! CLOSE(LU_TOA_LS)
!ENDIF

! Diagnostics at end of run
!OPEN(9998,FILE='Phi_S.txt',STATUS='REPLACE')
!WRITE(9998,'(I5)') NX_LS,NY_LS
!WRITE(9998,'(F7.2)') XS,XF,YS,YF
!WRITE(9998,'(F7.2)') ((PHI_S(IDUM,JDUM),JDUM=1,NY_LS),IDUM=1,NX_LS)
!CLOSE(9998)

!OPEN(9998,FILE='Phi_W.txt',STATUS='REPLACE')
!WRITE(9998,'(I5)') NX_LS,NY_LS
!WRITE(9998,'(F7.2)') XS,XF,YS,YF
!WRITE(9998,'(F7.2)') ((PHI_W(IDUM,JDUM),JDUM=1,NY_LS),IDUM=1,NX_LS)
!CLOSE(9998)

!OPEN(9998,FILE='alt.txt',STATUS='REPLACE')
!WRITE(9998,'(I5)') NX_LS,NY_LS
!WRITE(9998,'(F7.2)') XS,XF,YS,YF
!WRITE(9998,'(F10.5)') ((ZT(IDUM,JDUM),JDUM=1,NY_LS),IDUM=1,NX_LS)
!CLOSE(9998)

!OPEN(9998,FILE='DZTDX.txt',STATUS='REPLACE')
!WRITE(9998,'(I5)') NX_LS,NY_LS
!WRITE(9998,'(F7.2)') XS,XF,YS,YF
!WRITE(9998,'(F7.2)') ((DZTDX(IDUM,JDUM),JDUM=1,NY_LS),IDUM=1,NX_LS)
!CLOSE(9998)

!OPEN(9998,FILE='DZTDY.txt',STATUS='REPLACE')
!WRITE(9998,'(I5)') NX_LS,NY_LS
!WRITE(9998,'(F7.2)') XS,XF,YS,YF
!WRITE(9998,'(F7.2)') ((DZTDY(IDUM,JDUM),JDUM=1,NY_LS),IDUM=1,NX_LS)
!CLOSE(9998)

!OPEN(9998,FILE='Theta_Ellipse.txt',STATUS='REPLACE')
!WRITE(9998,'(I5)') NX_LS,NY_LS
!WRITE(9998,'(F7.2)') XS,XF,YS,YF
!WRITE(9998,'(F7.2)') ((Theta_Elps(IDUM,JDUM),JDUM=1,NY_LS),IDUM=1,NX_LS)
!CLOSE(9998)

!OPEN(9998,FILE='UMF.txt',STATUS='REPLACE')
!WRITE(9998,'(I5)') NX_LS,NY_LS
!WRITE(9998,'(F7.2)') XS,XF,YS,YF
!WRITE(9998,'(F7.2)') ((UMF(IDUM,JDUM),JDUM=1,NY_LS),IDUM=1,NX_LS)
!CLOSE(9998)

END SUBROUTINE LEVEL_SET_FIREFRONT_PROPAGATION

!************************************************************************************************
SUBROUTINE END_LEVEL_SET
!************************************************************************************************
!
! Output quantities at end of level set simulation
!
INTEGER :: IDUM,JDUM
! Output time of arrival array
!WRITE(LU_TOA_LS,'(F7.2)') ((TOA(IDUM,JDUM),IDUM=1,NX_LS),JDUM=1,NY_LS)
!CLOSE(LU_TOA_LS)
!!WRITE(LU_ROS_LS,'(F7.2)') ((ROS_X_OUT(IDUM,JDUM),IDUM=1,NX_LS),JDUM=1,NY_LS), &
!!                          ((ROS_Y_OUT(IDUM,JDUM),IDUM=1,NX_LS),JDUM=1,NY_LS)
!WRITE(LU_ROSX_LS,'(F7.2)') ((ROS_X_OUT(IDUM,JDUM),IDUM=1,NX_LS),JDUM=1,NY_LS)
!CLOSE(LU_ROSX_LS)
!WRITE(LU_ROSY_LS,'(F7.2)') ((ROS_Y_OUT(IDUM,JDUM),IDUM=1,NX_LS),JDUM=1,NY_LS)
!CLOSE(LU_ROSY_LS)
!WRITE(LU_FLI_LS,'(F9.2)') ((FLI_OUT(IDUM,JDUM),IDUM=1,NX_LS),JDUM=1,NY_LS)
!CLOSE(LU_FLI_LS)
!WRITE(LU_CRWN_PROB_LS,'(F9.2)') ((CRUZ_CROWN_PROB_OUT(IDUM,JDUM),IDUM=1,NX_LS),JDUM=1,NY_LS)
!CLOSE(LU_CRWN_PROB_LS)

END SUBROUTINE END_LEVEL_SET
!
!************************************************************************************************
SUBROUTINE LEVEL_SET_PERIMETER_SPREAD_RATE(NM,COMPUTE_ROS)
!************************************************************************************************
!
! Compute components of spread rate vector along fire perimeter
!
INTEGER, INTENT(IN) :: NM
CHARACTER(5), INTENT(IN) :: COMPUTE_ROS
INTEGER :: I,J,IM1,IP1,JM1,JP1
REAL(EB) :: COS_THETA_WIND,COS_THETA_SLOPE,COS_THETA_WIND_H,COS_THETA_WIND_B, &
            COS_THETA_SLOPE_H,COS_THETA_SLOPE_B,DPHIDX,DPHIDY,F_EAST,F_WEST,F_NORTH,F_SOUTH, &
            GRAD_SLOPE_DOT_NORMAL_FIRELINE,MAG_F,MAG_SR,MAG_U,WIND_DOT_NORMAL_FIRELINE,NEXP_WIND
REAL(EB) :: RAD_TO_DEGREE,DEGREES_SLOPE,SLOPE_FACTOR

!Variables for elliptical propagation model

REAL(EB) :: COS_THETA,SIN_THETA,XSF,YSF,UMF_DUM
REAL(EB) :: A_ELPS,A_ELPS2,AROS,BROS,B_ELPS2,B_ELPS,C_ELPS,DENOM,ROS_TMP,LB,LBD,HB
REAL(EB), DIMENSION(:) :: NORMAL_FIRELINE(2)

REAL(EB), POINTER, DIMENSION(:,:) :: ROS_HEAD_P=>NULL(),UMF_P=>NULL(),SR_X_LS_P,SR_Y_LS_P
ROS_HEAD_P => WORK1_LS
UMF_P      => WORK2_LS
SR_X_LS_P  => WORK3_LS
SR_Y_LS_P  => WORK4_LS

CALL POINT_TO_MESH(NM)

SR_X_LS_P = 0.0_EB ; SR_Y_LS_P = 0.0_EB

IF (COMPUTE_ROS == 'RFM10') THEN
  ROS_HEAD_P   = ROS_HEAD_FM10 !head ROS in Fuel Model 10 for S&R crown fire model
  UMF_P        = UMF_FM10
  SR_X_FM10_LS = 0.0_EB
  SR_Y_FM10_LS = 0.0_EB
ELSE IF (COMPUTE_ROS=='RSA') THEN
  ROS_HEAD_P  = ROS_HEAD_SA !head ROS for Rsa in S&R crown fire model; only computed in initialization
  UMF_P       = UMF
  SR_X_RSA_LS = 0.0_EB
  SR_Y_RSA_LS = 0.0_EB
ELSE IF (COMPUTE_ROS=='RSURF') THEN
  ROS_HEAD_P = ROS_HEAD_SURF !head ROS in surface fuel
  UMF_P      = UMF
  SR_X_LS    = 0.0_EB
  SR_Y_LS    = 0.0_EB
ENDIF
 
RAD_TO_DEGREE = 90._EB/ASIN(1._EB)

!NEXP_WIND = 2

IF (RK2_PREDICTOR_LS) PHI0_LS = PHI_LS
IF (.NOT. RK2_PREDICTOR_LS) PHI0_LS = PHI1_LS

DYN_SR_MAX = 0.0_EB

FLUX_ILOOP: DO I = 1,NX_LS
  
  IM1=I-1 
  IP1=I+1 
! IF (I==1) IM1 = I
! IF (I==NX_LS) IP1 = I
  
  DO J = 1,NY_LS
    
   JM1=J-1
   JP1=J+1
!  IF (J==1) JM1 = J
!  IF (J==NX_LS) JP1 = J

   F_EAST  = 0.5_EB*( PHI0_LS(I,J) + PHI0_LS(IP1,J) )
   F_WEST  = 0.5_EB*( PHI0_LS(I,J) + PHI0_LS(IM1,J) )
   F_NORTH = 0.5_EB*( PHI0_LS(I,J) + PHI0_LS(I,JP1) )
   F_SOUTH = 0.5_EB*( PHI0_LS(I,J) + PHI0_LS(I,JM1) )
         
   DPHIDX = (F_EAST-F_WEST) * RDX(I) !IDX_LS
   DPHIDY = (F_NORTH-F_SOUTH) * RDY(J) !IDY_LS
   
   MAG_F = SQRT(DPHIDX**2 + DPHIDY**2)
   IF (MAG_F > 0._EB) THEN   !components of unit vector normal to PHI contours
        NORMAL_FIRELINE(1) = -DPHIDX/MAG_F
        NORMAL_FIRELINE(2) = -DPHIDY/MAG_F
        XSF =  DPHIDY
        YSF = -DPHIDX 
        GRAD_SLOPE_DOT_NORMAL_FIRELINE = DZTDX(I,J)*(DPHIDY/MAG_F) + DZTDY(I,J)*(-DPHIDY/MAG_F)
   ELSE
        NORMAL_FIRELINE = 0._EB
        GRAD_SLOPE_DOT_NORMAL_FIRELINE = 0._EB
        XSF=0._EB
        YSF=0._EB
   ENDIF

   COS_THETA_SLOPE = 0.0_EB ; COS_THETA_SLOPE_H = 0.0_EB ; COS_THETA_SLOPE_B = 0.0_EB
   
   IF (MAG_ZT(I,J) > 0.0_EB) THEN
       COS_THETA_SLOPE = GRAD_SLOPE_DOT_NORMAL_FIRELINE/MAG_ZT(I,J)
       !XSF = XSF * COS_THETA_SLOPE
       !YSF = YSF * COS_THETA_SLOPE
   ENDIF
   
   DEGREES_SLOPE = ATAN(MAG_ZT(I,J))*RAD_TO_DEGREE
   
   IF (LSET_ELLIPSE) THEN
       
       ! Effective wind direction (theta) is clockwise from y-axis (Richards 1990)
       COS_THETA = COS(THETA_ELPS(I,J)) !V_LS(I,J) / MAG_U
       SIN_THETA = SIN(THETA_ELPS(I,J)) !U_LS(I,J) / MAG_U

       ROS_TMP = ROS_HEAD_P(I,J)
       
       !Mag of wind speed at midflame height must be in units of m/s here   
       UMF_DUM = UMF_P(I,J)/60.0_EB
       
       !Length to breadth ratio of ellipse based on effective UMF
       LB = 0.936_EB * EXP(0.2566_EB * UMF_DUM) + 0.461_EB * EXP(-0.1548_EB * UMF_DUM) - 0.397_EB 
       
       !Constraint LB max = 8 from Finney 2004
       LB = MAX(1.0_EB,MIN(LB,8.0_EB))
       
       LBD = SQRT(LB**2 - 1.0_EB)
       
       !Head to back ratio based on LB
       HB = (LB + LBD) / (LB - LBD)
       
       ! A_ELPS and B_ELPS notation is consistent with Farsite and Richards 
       B_ELPS =  0.5_EB * (ROS_TMP + ROS_TMP/HB)
       B_ELPS2 = B_ELPS**2
       A_ELPS =  B_ELPS / LB
       A_ELPS2=  A_ELPS**2
       C_ELPS =  B_ELPS - (ROS_TMP/HB)
  
       ! Denominator used in spread rate equation from Richards 1990 in final LS vs FS paper 
       AROS  = XSF*COS_THETA - YSF*SIN_THETA
       BROS  = XSF*SIN_THETA + YSF*COS_THETA
       DENOM = A_ELPS2*BROS**2 + B_ELPS2*AROS**2
           
       ! Finney's formulation
       !DENOM = B_ELPS2 * (XS * SIN_THETA - YS * COS_THETA)**2 - &
       !A_ELPS2 * (XS * COS_THETA + YS * SIN_THETA)**2
             
       IF (DENOM > 0._EB) THEN                 
        DENOM = 1._EB / SQRT(DENOM)        
       ELSE
        DENOM = 0._EB
       ENDIF

!WRITE(LU_OUTPUT,'(A,1x,2I3,8ES12.4)')'vege: i,j',i,j,denom,a_elps2,cos_theta,bros,b_elps2,sin_theta,aros,c_elps
       
!  
!This is with A_ELPS2 and B_ELPS2 notation consistent with Finney and Richards and in final LS vs FS paper
        SR_X_LS_P(I,J) = DENOM * ( A_ELPS2*COS_THETA*BROS - B_ELPS2*SIN_THETA*AROS) + C_ELPS*SIN_THETA
        SR_Y_LS_P(I,J) = DENOM * (-A_ELPS2*SIN_THETA*BROS - B_ELPS2*COS_THETA*AROS) + C_ELPS*COS_THETA

!if(j==25 .and. compute_rsa_srxy) print '(A,1x,3ES12.4)','roshead,srx,sry',ros_tmp,sr_x_ls_p(i,j),sr_y_ls_p(i,j)
!if(j==25 .and. compute_fm10_srxy) print '(A,1x,3ES12.4)','roshead,srx,sry',ros_tmp,sr_x_ls_p(i,j),sr_y_ls_p(i,j)
!if(j==25 .and. .not. compute_rsa_srxy .and. .not. compute_fm10_srxy) &
!                print '(A,1x,3ES12.4)','roshead,srx,sry',ros_tmp,sr_x_ls_p(i,j),sr_y_ls_p(i,j)
        
        
       !ELSE
   
            !For no-wind, no-slope case
        !    SR_X_LS_P(I,J) = ROS_HEAD_P(I,J) * NORMAL_FIRELINE(1)
        !    SR_Y_LS_P(I,J) = ROS_HEAD_P(I,J) * NORMAL_FIRELINE(2)
        
       !ENDIF  
       
       ! Project spread rates from slope to horizontal plane
       
       IF (ABS(DZTDX(I,J)) > 0._EB) SR_X_LS_P(I,J) = SR_X_LS_P(I,J) * ABS(COS(ATAN(DZTDX(I,J))))
       IF (ABS(DZTDY(I,J)) > 0._EB) SR_Y_LS_P(I,J) = SR_Y_LS_P(I,J) * ABS(COS(ATAN(DZTDY(I,J))))
       
       MAG_SR = SQRT(SR_X_LS_P(I,J)**2 + SR_Y_LS_P(I,J)**2)   
   
   ELSE !McArthur Spread Model
        
     WIND_DOT_NORMAL_FIRELINE = U_LS(I,J)*NORMAL_FIRELINE(1) + V_LS(I,J)*NORMAL_FIRELINE(2)
     MAG_U  = SQRT(U_LS(I,J)**2 + V_LS(I,J)**2)

     COS_THETA_WIND = 0.0_EB ; COS_THETA_WIND_H = 0.0_EB ; COS_THETA_WIND_B = 0.0_EB
     IF(MAG_U > 0.0_EB) COS_THETA_WIND = WIND_DOT_NORMAL_FIRELINE/MAG_U

     GRAD_SLOPE_DOT_NORMAL_FIRELINE = DZTDX(I,J)*NORMAL_FIRELINE(1) + DZTDY(I,J)*NORMAL_FIRELINE(2) 
     COS_THETA_SLOPE = 0.0_EB ; COS_THETA_SLOPE_H = 0.0_EB ; COS_THETA_SLOPE_B = 0.0_EB
   
     IF (MAG_ZT(I,J) > 0.0_EB) COS_THETA_SLOPE = GRAD_SLOPE_DOT_NORMAL_FIRELINE/MAG_ZT(I,J)
   
     DEGREES_SLOPE = ATAN(MAG_ZT(I,J))*RAD_TO_DEGREE
    
     SLOPE_FACTOR  = MAG_ZT(I,J)**2
     IF (SLOPE_FACTOR > 3._EB) SLOPE_FACTOR = 3._EB
        
     ROS_HEADS = 0.33_EB*ROS_HEAD_P(I,J)
     IF(DEGREES_SLOPE >= 5._EB .AND. DEGREES_SLOPE < 10._EB)  ROS_HEADS = 0.33_EB*ROS_HEAD_P(I,J)
     IF(DEGREES_SLOPE >= 10._EB .AND. DEGREES_SLOPE < 20._EB) ROS_HEADS =         ROS_HEAD_P(I,J)
     IF(DEGREES_SLOPE >= 20._EB)                              ROS_HEADS =  3._EB*ROS_HEAD_P(I,J)

     MAG_SR    = 0.0_EB
     ROS_HEADS = 0.0_EB
     ROS_BACKS = 0.0_EB

     NEXP_WIND = WIND_EXP(I,J)
  
     ! Spread with the wind and upslope
     IF(COS_THETA_WIND >= 0._EB .AND. COS_THETA_SLOPE >= 0._EB) THEN
       IF (.NOT. LSET_TAN2) THEN
         IF(DEGREES_SLOPE >= 5._EB .AND. DEGREES_SLOPE < 10._EB)  ROS_HEADS = 0.33_EB*ROS_HEAD_P(I,J)
         IF(DEGREES_SLOPE >= 10._EB .AND. DEGREES_SLOPE < 20._EB) ROS_HEADS =         ROS_HEAD_P(I,J)
         IF(DEGREES_SLOPE >= 20._EB)                              ROS_HEADS =  3._EB*ROS_HEAD_P(I,J)
       ELSEIF (DEGREES_SLOPE > 0._EB) THEN
                    ROS_HEADS = ROS_HEAD_P(I,J) * SLOPE_FACTOR !Dependence on TAN(slope)^2
       ENDIF
       MAG_SR = ROS_FLANK(I,J)*(1._EB + COS_THETA_WIND**NEXP_WIND*COS_THETA_SLOPE) + &
                (ROS_HEAD_P(I,J) - ROS_FLANK(I,J))*COS_THETA_WIND**NEXP_WIND + &
                (ROS_HEADS     - ROS_FLANK(I,J))*COS_THETA_SLOPE  !magnitude of spread rate
!if (abs(normal_fireline(1)) > 0._EB) print*,'rf,rh,rs',ros_flank(i,j),ros_head(i,j),ros_heads
!if (abs(normal_fireline(1)) > 0._EB) print*,'i,j',i,j
     ENDIF
   !  IF(ABS(COS_THETA_WIND) < 0.5_EB .AND. MAG_F > 0._EB) MAG_SR = 0.0_EB
   !  IF(ABS(COS_THETA_WIND) < 0.5_EB .AND. MAG_F > 0._EB) FLANKFIRE_LIFETIME(I,J) = FLANKFIRE_LIFETIME(I,J) + DT_LS
   !  IF(FLANKFIRE_LIFETIME(I,J) > TIME_FLANKFIRE_QUENCH) MAG_SR = 0.0_EB

   ! Spread with the wind and downslope
     IF(COS_THETA_WIND >= 0._EB .AND. COS_THETA_SLOPE < 0._EB) THEN
         IF(DEGREES_SLOPE >= 5._EB .AND. DEGREES_SLOPE < 10._EB)  ROS_HEADS =  0.33_EB*ROS_HEAD_P(I,J)
         IF(DEGREES_SLOPE >= 10._EB .AND. DEGREES_SLOPE < 20._EB) ROS_HEADS =  0.50_EB*ROS_HEAD_P(I,J)
         IF(DEGREES_SLOPE >= 20._EB)                              ROS_HEADS =  0.75_EB*ROS_HEAD_P(I,J)
         MAG_SR = ROS_FLANK(I,J)*(1._EB + COS_THETA_WIND*COS_THETA_SLOPE) + &
                  (ROS_HEAD_P(I,J) - ROS_FLANK(I,J))*COS_THETA_WIND**NEXP_WIND + &
                  (ROS_HEADS     - ROS_FLANK(I,J))*COS_THETA_SLOPE  !magnitude of spread rate
        !   if(cos_theta_wind == 0._EB) FLANKFIRE_LIFETIME(I,J) = FLANKFIRE_LIFETIME(I,J) + DT_LS
        !   if(flankfire_lifetime(i,j) > time_flankfire_quench) mag_sr = 0.0_EB
     ENDIF

   ! Spread against the wind and upslope
     IF(COS_THETA_WIND <  0._EB .AND. COS_THETA_SLOPE >= 0._EB) THEN
       IF (.NOT. LSET_TAN2) THEN
         IF(DEGREES_SLOPE >= 5._EB .AND. DEGREES_SLOPE < 10._EB)  ROS_BACKS = -0.33_EB*ROS_BACKU(I,J)
         IF(DEGREES_SLOPE >= 10._EB .AND. DEGREES_SLOPE < 20._EB) ROS_BACKS =         -ROS_BACKU(I,J)
         IF(DEGREES_SLOPE >= 20._EB)                              ROS_BACKS = -3.0_EB*ROS_BACKU(I,J)
       ELSEIF (DEGREES_SLOPE > 0._EB) THEN
         ROS_HEADS = ROS_HEAD_P(I,J) * SLOPE_FACTOR !Dependence on TAN(slope)^2
       ENDIF
         MAG_SR = ROS_FLANK(I,J)*(1._EB - ABS(COS_THETA_WIND)**NEXP_WIND*COS_THETA_SLOPE) + &
                  (ROS_FLANK(I,J) - ROS_BACKU(I,J))*(-ABS(COS_THETA_WIND)**NEXP_WIND) + &
                  (ROS_FLANK(I,J) - ROS_BACKS)*COS_THETA_SLOPE  !magnitude of spread rate
     ENDIF

   ! Spread against the wind and downslope
     IF(COS_THETA_WIND <  0._EB .AND. COS_THETA_SLOPE < 0._EB) THEN
       IF(DEGREES_SLOPE >= 5._EB .AND. DEGREES_SLOPE < 10._EB)  ROS_BACKS = 0.33_EB*ROS_BACKU(I,J)
       IF(DEGREES_SLOPE >= 10._EB .AND. DEGREES_SLOPE < 20._EB) ROS_BACKS = 0.50_EB*ROS_BACKU(I,J)
       IF(DEGREES_SLOPE >= 20._EB)                              ROS_BACKS = 0.75_EB*ROS_BACKU(I,J)
       MAG_SR = ROS_FLANK(I,J)*(1._EB - ABS(COS_THETA_WIND)**NEXP_WIND*COS_THETA_SLOPE) + &
                (ROS_FLANK(I,J) - ROS_BACKU(I,J))*(-ABS(COS_THETA_WIND)**NEXP_WIND) + &
                (ROS_FLANK(I,J) - ROS_BACKS)*COS_THETA_SLOPE  !magnitude of spread rate
     ENDIF


        !  MAG_SR = ROS_FLANK(I,J) + ROS_HEAD_P(I,J)*COS_THETA_WIND**1.5 !magnitude of spread rate
        !  MAG_SR = ROS_FLANK(I,J) + ROS_HEAD_P(I,J)*MAG_U*COS_THETA_WIND**1.5 !magnitude of spread rate
!if (abs(mag_sr) > 0._EB) print*,'mag_sr,nx,ny',mag_sr,normal_fireline(1),normal_fireline(2)
           SR_X_LS_P(I,J) = MAG_SR*NORMAL_FIRELINE(1) !spread rate components
           SR_Y_LS_P(I,J) = MAG_SR*NORMAL_FIRELINE(2) 
        !  MAG_SR_OUT(I,J) = MAG_SR
  
   ENDIF !Ellipse or McArthur Spread 
   
   DYN_SR_MAX = MAX(DYN_SR_MAX,MAG_SR) 

  ENDDO

ENDDO FLUX_ILOOP

IF (COMPUTE_ROS=='RFM10') THEN
  SR_X_FM10_LS = SR_X_LS_P
  SR_Y_FM10_LS = SR_Y_LS_P
ELSE IF (COMPUTE_ROS=='RSA') THEN
  SR_X_RSA_LS  = SR_X_LS_P
  SR_Y_RSA_LS  = SR_Y_LS_P
ELSE IF (COMPUTE_ROS=='RSURF') THEN
  SR_X_SURF_LS = SR_X_LS_P
  SR_Y_SURF_LS = SR_Y_LS_P
  SR_X_LS      = SR_X_SURF_LS
  SR_Y_LS      = SR_Y_SURF_LS
ENDIF

END SUBROUTINE LEVEL_SET_PERIMETER_SPREAD_RATE 

!************************************************************************************************
SUBROUTINE LEVEL_SET_SR_CROWNFIRE_OR_NOT(NM)
!************************************************************************************************
! Following Scott & Burgan, determine if there is a crown fire, if it's active or passive, and it's 
! rate of spread 
! "Assessing Crown Fire Potential by Linking Models of Surface and Crown Fire Behavior"
! RMRS-RP-29, 2001
!
INTEGER, INTENT(IN) :: NM
INTEGER  :: I,J
REAL(EB) :: SR_MAG_SURF,ROS_FINAL_X,ROS_FINAL_Y

CALL POINT_TO_MESH(NM)

DO J=1,NY_LS
  DO I=1,NX_LS

    IF (RAC_THRESHOLD_LS(I,J) < 0.0_EB) CYCLE !crown fire model not implemented for this I,J
    SR_MAG_SURF = SQRT(SR_X_SURF_LS(I,J)**2 + SR_Y_SURF_LS(I,J)**2)
    IF (SR_MAG_SURF <= ROS_SURF_INI_LS(I,J)) CYCLE
    IF (ROS_HEAD_SA(I,J) <= ROS_SURF_INI_LS(I,J)) CYCLE
!if(j==30) print '(A,1x,1I3,5ES12.4,1I3)','I,PHI_LS,CFB,RSURF,RINI,RSA,Flag',i,phi_ls(i,j),cfb_sr_ls(i,j),sr_mag_surf, &
!                                                  ros_surf_ini_ls(i,j),ros_head_sa(i,j),flag_model_for_passive_ros(i,j)
    CFB_SR_LS(I,J) = (SR_MAG_SURF - ROS_SURF_INI_LS(I,J))/(ROS_HEAD_SA(I,J) - ROS_SURF_INI_LS(I,J))
!if(cfb_sr_ls(i,j) < 0._EB) print '(A,1x,4ES12.4)','cfb,Rs,Ri,Rsa=',cfb_sr_ls(i,j),sr_mag_surf,ros_surf_ini_ls(i,j),ros_head_sa(i,j)
    CFB_SR_LS(I,J) = MIN(1.0_EB,CFB_SR_LS(I,J))
    ROS_FINAL_X = SR_X_SURF_LS(I,J) + CFB_SR_LS(I,J)*(3.34_EB*SR_X_FM10_LS(I,J) - SR_X_SURF_LS(I,J))
    ROS_FINAL_Y = SR_Y_SURF_LS(I,J) + CFB_SR_LS(I,J)*(3.34_EB*SR_Y_FM10_LS(I,J) - SR_Y_SURF_LS(I,J))
    ROS_FINAL_MAG(I,J) = SQRT(ROS_FINAL_X**2 + ROS_FINAL_Y**2)

    IF (FLAG_MODEL_FOR_PASSIVE_ROS(I,J) == 1) THEN !S&R
      SR_X_LS(I,J) = ROS_FINAL_X
      SR_Y_LS(I,J) = ROS_FINAL_Y
    ENDIF
    IF (FLAG_MODEL_FOR_PASSIVE_ROS(I,J) == 2 .AND. ROS_FINAL_MAG(I,J) >= RAC_THRESHOLD_LS(I,J)) THEN !Farsite
      SR_X_LS(I,J) = ROS_FINAL_X
      SR_Y_LS(I,J) = ROS_FINAL_Y
    ENDIF

  ENDDO
ENDDO

END SUBROUTINE LEVEL_SET_SR_CROWNFIRE_OR_NOT

!************************************************************************************************
SUBROUTINE LEVEL_SET_ADVECT_FLUX(NM)
!************************************************************************************************
!
! Use the spread rate [SR_X_LS,SR_Y_LS] to compute the limited scalar gradient
! and take dot product with spread rate vector to get advective flux

INTEGER, INTENT(IN) :: NM
INTEGER :: I,IM1,IM2,IP1,IP2,J,JM1,JM2,JP1,JP2
REAL(EB), DIMENSION(:) :: Z(4)
!REAL(EB), DIMENSION(:,:) :: FLUX_LS(0:IBP1,0:JBP1)
REAL(EB) :: DPHIDX,DPHIDY,F_EAST,F_WEST,F_NORTH,F_SOUTH
REAL(EB) :: PHIMAG

CALL POINT_TO_MESH(NM)

IF (RK2_PREDICTOR_LS) PHI0_LS = PHI_LS
IF (.NOT. RK2_PREDICTOR_LS) PHI0_LS = PHI1_LS

!if (nm == 2) then
!  print*,'predictor',rk2_predictor_ls
!  print '(A,i3,1x,2E13.5)','vege:advect ',nm,phi0_ls(0,12),phi0_ls(1,12)
!endif

ILOOP: DO I=1,NX_LS
 
 IM1=I-1!; IF (IM1<1) IM1=IM1+NX_LS
!IM2=I-2 ; IF (IM2<0) IM2=IM2+NX_LS
 IM2=I-2 ; IF (IM2<0) IM2=0

 IP1=I+1!; IF (IP1>NX_LS) IP1=IP1-NX_LS
!IP2=I+2 ; IF (IP2>NX_LS+1) IP2=IP2-NX_LS
 IP2=I+2 ; IF (IP2>NX_LS+1) IP2=NX_LS+1

 JLOOP: DO J = 1,NY_LS
   
   JM1=J-1!; IF (JM1<1) JM1=JM1+NY_LS
!  JM2=J-2 ; IF (JM2<0) JM2=JM2+NY_LS
   JM2=J-2 ; IF (JM2<0) JM2=0
   
   JP1=J+1!; IF (JP1>NY_LS) JP1=JP1-NY_LS
!  JP2=J+2 ; IF (JP2>NY_LS+1) JP2=JP2-NY_LS
   JP2=J+2 ; IF (JP2>NY_LS+1) JP2=NY_LS+1

!-- east face
   Z(1) = PHI0_LS(IM1,J)
   Z(2) = PHI0_LS(I,J)
   Z(3) = PHI0_LS(IP1,J)
   Z(4) = PHI0_LS(IP2,J)
   F_EAST = SCALAR_FACE_VALUE_LS(SR_X_LS(I,J),Z,LIMITER_LS)
   
!-- west face
   Z(1) = PHI0_LS(IM2,J)
   Z(2) = PHI0_LS(IM1,J)
   Z(3) = PHI0_LS(I,J)
   Z(4) = PHI0_LS(IP1,J)
   F_WEST = SCALAR_FACE_VALUE_LS(SR_X_LS(I,J),Z,LIMITER_LS)

!-- north face
   Z(1) = PHI0_LS(I,JM1)
   Z(2) = PHI0_LS(I,J)
   Z(3) = PHI0_LS(I,JP1)
   Z(4) = PHI0_LS(I,JP2)
   F_NORTH = SCALAR_FACE_VALUE_LS(SR_Y_LS(I,J),Z,LIMITER_LS)

!-- south face
   Z(1) = PHI0_LS(I,JM2)
   Z(2) = PHI0_LS(I,JM1)
   Z(3) = PHI0_LS(I,J)
   Z(4) = PHI0_LS(I,JP1)
   F_SOUTH = SCALAR_FACE_VALUE_LS(SR_Y_LS(I,J),Z,LIMITER_LS)
   
! IF (J<2 .OR. J>(NY_LS-2)) THEN  
!   
!      IF (J==1) THEN
!        !    north face
!!           Z(1) = PHI_MAX_LS
!            Z(1) = PHI0_LS(I,0)
!            Z(2) = PHI0_LS(I,J)
!            Z(3) = PHI0_LS(I,JP1)
!            Z(4) = PHI0_LS(I,JP2)
!            F_NORTH = SCALAR_FACE_VALUE_LS(SR_Y_LS(I,J),Z,LIMITER_LS)
!
!        !    south face
!!           Z(1) = PHI_MAX_LS
!!           Z(2) = PHI_MAX_LS
!            Z(1) = PHI0_LS(I,0)
!            Z(2) = PHI0_LS(I,0)
!            Z(3) = PHI0_LS(I,J)
!            Z(4) = PHI0_LS(I,JP1)
!            F_SOUTH = SCALAR_FACE_VALUE_LS(SR_Y_LS(I,J),Z,LIMITER_LS)
!!if (i==25 .and. nm==2) print '(A,1(i3),1x,2(E15.3))','vege:advect',nm,f_north,f_south
!
!      ELSEIF (j==2) THEN
!        !    north face
!            Z(1) = PHI0_LS(I,JM1)
!            Z(2) = PHI0_LS(I,J)
!            Z(3) = PHI0_LS(I,JP1)
!            Z(4) = PHI0_LS(I,JP2)
!            F_NORTH = SCALAR_FACE_VALUE_LS(SR_Y_LS(I,J),Z,LIMITER_LS)
!
!        !    south face
!!           Z(1) = PHI_MAX_LS
!            Z(1) = PHI0_LS(I,0)
!            Z(2) = PHI0_LS(I,JM1)
!            Z(3) = PHI0_LS(I,J)
!            Z(4) = PHI0_LS(I,JP1)
!            F_SOUTH = SCALAR_FACE_VALUE_LS(SR_Y_LS(I,J),Z,LIMITER_LS)
!   
!   
!      ELSEIF (J == NY_LS-1) THEN
!    !    north face
!            Z(1) = PHI0_LS(I,JM1)
!            Z(2) = PHI0_LS(I,J)
!            Z(3) = PHI0_LS(I,JP1)
!            Z(4) = PHI_MIN_LS
!            F_NORTH = SCALAR_FACE_VALUE_LS(SR_Y_LS(I,J),Z,LIMITER_LS)
!
!        !    south face
!            Z(1) = PHI0_LS(I,JM2)
!            Z(2) = PHI0_LS(I,JM1)
!            Z(3) = PHI0_LS(I,J)
!            Z(4) = PHI0_LS(I,JP1)
!            F_SOUTH = SCALAR_FACE_VALUE_LS(SR_Y_LS(I,J),Z,LIMITER_LS)
!
!      ELSEIF (J == NY_LS) THEN ! must be J == NY_LS
!        !    north face
!            Z(1) = PHI0_LS(I,JM1)
!            Z(2) = PHI0_LS(I,J)
!            Z(3) = PHI_MIN_LS
!            Z(4) = PHI_MIN_LS
!            F_NORTH = SCALAR_FACE_VALUE_LS(SR_Y_LS(I,J),Z,LIMITER_LS)
!
!        !    south face
!            Z(1) = PHI0_LS(I,JM2)
!            Z(2) = PHI0_LS(I,JM1)
!            Z(3) = PHI0_LS(I,J)
!            Z(4) = PHI_MIN_LS
!            F_SOUTH = SCALAR_FACE_VALUE_LS(SR_Y_LS(I,J),Z,LIMITER_LS)
!    
!      ENDIF
!  
!      ELSE
!
!    !    north face
!       Z(1) = PHI0_LS(I,JM1)
!       Z(2) = PHI0_LS(I,J)
!       Z(3) = PHI0_LS(I,JP1)
!       Z(4) = PHI0_LS(I,JP2)
!       F_NORTH = SCALAR_FACE_VALUE_LS(SR_Y_LS(I,J),Z,LIMITER_LS)
!
!    !    south face
!       Z(1) = PHI0_LS(I,JM2)
!       Z(2) = PHI0_LS(I,JM1)
!       Z(3) = PHI0_LS(I,J)
!       Z(4) = PHI0_LS(I,JP1)
!       F_SOUTH = SCALAR_FACE_VALUE_LS(SR_Y_LS(I,J),Z,LIMITER_LS)
!   
!   ENDIF !IF (J<2 .OR. J>(NY_LS-2) 
        
   DPHIDX = (F_EAST-F_WEST)* RDX(I) !IDX_LS
    
   DPHIDY = (F_NORTH-F_SOUTH)* RDY(J) !IDY_LS
   
   FLUX_LS(I,J) = SR_X_LS(I,J)*DPHIDX + SR_Y_LS(I,J)*DPHIDY
!if (j== 1 .and. i==25 .and. nm==2) print '(A,1(i3),1x,2(E15.3))','vege:advect--',nm,dphidy,flux_ls(i,j)
   
   PHIMAG          = SQRT(DPHIDX**2 + DPHIDY**2)
   MAG_SR_OUT(I,J) = 0.0_EB
   IF(PHIMAG > 0.0_EB) MAG_SR_OUT(I,J) = FLUX_LS(I,J)/PHIMAG
        
!  fx = (f_east-f_west)/dx
!  fy = (f_north-f_south)/dy
!       phi(i,j) = phi0(i,j) - dt*[Fx(i,j) Fy(i,j)]*[fx fy]

 ENDDO JLOOP

!FLUX_LS(:,1) = FLUX_LS(:,2)

ENDDO ILOOP

!print*,'veg advect_flux:maxflux    ',maxval(abs(flux_ls))
!print*,'veg advect_flux:max srx,sry',maxval(sr_x_ls),maxval(sr_y_ls)

IF (RK2_PREDICTOR_LS) FLUX0_LS = FLUX_LS
IF (.NOT. RK2_PREDICTOR_LS) FLUX1_LS = FLUX_LS

END SUBROUTINE LEVEL_SET_ADVECT_FLUX 
!
! ----------------------------------------------------
REAL(EB) FUNCTION SCALAR_FACE_VALUE_LS(SR_XY,Z,LIMITER)
!
! From Randy 7-11-08
! This function computes the scalar value on a face.
! The scalar is denoted Z, and the velocity is denoted U.
! The gradient (computed elsewhere) is a central difference across 
! the face subject to a flux limiter.  The flux limiter choices are:
! 
! limiter = 1 implements the MINMOD limiter
! limiter = 2 implements the SUPERBEE limiter of Roe
! limiter = 3 implements first-order upwinding (monotone)
!
!
!                    location of face
!                            
!                            f
!    |     o     |     o     |     o     |     o     |
!                     SRXY        SRXY
!                 (if f_east)  (if f_west)
!         Z(1)        Z(2)        Z(3)        Z(4)
!
INTEGER :: LIMITER
REAL(EB) :: SR_XY
REAL(EB), INTENT(IN), DIMENSION(4) :: Z
REAL(EB) :: B,DZLOC,DZUP,R,ZUP,ZDWN

IF (SR_XY > 0._EB) THEN
!     the flow is left to right
 DZLOC = Z(3)-Z(2)
 DZUP  = Z(2)-Z(1)

 IF (ABS(DZLOC) > 0._EB) THEN
  R = DZUP/DZLOC
 ELSE
  R = 0._EB
 ENDIF
 ZUP  = Z(2)
 ZDWN = Z(3)
ELSE
!     the flow is right to left
 DZLOC = Z(3)-Z(2)
 DZUP  = Z(4)-Z(3)

 IF (ABS(DZLOC) > 0._EB) THEN
  R = DZUP/DZLOC
 ELSE
  R = 0._EB
 ENDIF
  ZUP  = Z(3)
  ZDWN = Z(2)
ENDIF

! flux limiter
IF (LIMITER==1) THEN
!     MINMOD
    B = MAX(0._EB,MIN(1._EB,R))
ELSEIF (limiter==2) THEN
!     SUPERBEE
    B = MAX(0._EB,MIN(2._EB*R,1._EB),MIN(R,2._EB))
ELSEIF (limiter==3) THEN
!     first-order upwinding
    B = 0._EB
ENDIF

SCALAR_FACE_VALUE_LS = ZUP + 0.5_EB * B * ( ZDWN - ZUP )

END FUNCTION SCALAR_FACE_VALUE_LS

!--------------------------------------------------------------------
SUBROUTINE LEVEL_SET_BC(NM)

! This finds the values of the level set function along the mesh boundaries through
! interpolation. Follows what's done for RHO in subroutine THERMAL_BC for INTERPOLATED_BC (in wall.f90)

INTEGER, INTENT(IN) :: NM
INTEGER :: II,IIG,IIO,IOR,IW,JJ,JJO,JJG,KK,KKG,KKO,NOM
REAL(EB) :: ARO,LSET_PHI_F,LSET_PHI_V
REAL(EB), POINTER, DIMENSION(:,:,:) :: OM_LSET_PHI =>NULL()
TYPE (WALL_TYPE),     POINTER :: WC =>NULL()
TYPE (OMESH_TYPE),    POINTER :: OM =>NULL()
TYPE (MESH_TYPE),     POINTER :: MM =>NULL()

IF (EVACUATION_ONLY(NM)) RETURN
IF (.NOT. VEG_LEVEL_SET) RETURN

CALL POINT_TO_MESH(NM)
! Set ghost cell values (based on THERMAL_BC case INTERPOLATED_BC in wall.f90

WALL_CELL_LOOP_BC: DO IW=1,N_EXTERNAL_WALL_CELLS+N_INTERNAL_WALL_CELLS
   WC  => WALL(IW)
   IF (WC%BOUNDARY_TYPE==NULL_BOUNDARY) CYCLE WALL_CELL_LOOP_BC
   II  = WC%II 
   JJ  = WC%JJ 
   KK  = WC%KK 
   IIG = WC%IIG
   JJG = WC%JJG
   KKG = WC%KKG
!  IF (KKG /= 1) CYCLE WALL_CELL_LOOP_BC
   IOR = WC%IOR
   IF (IOR == -3 .OR. IOR == 3) CYCLE WALL_CELL_LOOP_BC
   NOM = WC%NOM
   IF (NOM == 0) CYCLE WALL_CELL_LOOP_BC
   OM  => OMESH(NOM)
   OM_LSET_PHI => OM%LSET_PHI
   MM  => MESHES(NOM)
   LSET_PHI_V = LSET_PHI(IIG,JJG,1)
   LSET_PHI_F = LSET_PHI_V  ! Initialize face value of LSET_PHI with LSET_PHI_V

!print '(A,1x,9I3)','NM,NOM,IOR,II,JJ,II-,II+,JJ-,JJ+',nm,nom,ior,ii,jj,wc%nom_ib(1),wc%nom_ib(4),wc%nom_ib(2),wc%nom_ib(5)
!print '(A,1x,5I3,1ES12.4)','NM,NOM,IOR,IIG,JJG,             ',nm,nom,ior,iig,jjg,lset_phi_f

!  DO KKO=WC%NOM_IB(3),WC%NOM_IB(6)
     DO JJO=WC%NOM_IB(2),WC%NOM_IB(5)
       DO IIO=WC%NOM_IB(1),WC%NOM_IB(4)
!print '(A,1x,4I3,1ES13.5)',' nm, ii, iig, jig',nm,ii,iig,jjg,lset_phi(iig,jjg,1)
!print '(A,1x,4I3,1ES13.5)','nom, ii,  io,  jo',nom,ii,iio,jjo,om_lset_phi(iio,jjo,1)
!print*,'----------------'
         SELECT CASE(IOR)
         CASE( 1)
           ARO = MIN(1._EB , RDY(JJ)*MM%DY(JJO)) * 2._EB*DX(II)/(MM%DX(IIO)+DX(II))
         CASE(-1)
           ARO = MIN(1._EB , RDY(JJ)*MM%DY(JJO)) * 2._EB*DX(II)/(MM%DX(IIO)+DX(II))
         CASE( 2)
           ARO = MIN(1._EB , RDX(II)*MM%DX(IIO)) * 2._EB*DY(JJ)/(MM%DY(JJO)+DY(JJ))
         CASE(-2)
           ARO = MIN(1._EB , RDX(II)*MM%DX(IIO)) * 2._EB*DY(JJ)/(MM%DY(JJO)+DY(JJ))
!        CASE( 1)
!          ARO = MIN(1._EB , RDY(JJ)*RDZ(KK)*MM%DY(JJO)*MM%DZ(KKO)) * 2._EB*DX(II)/(MM%DX(IIO)+DX(II))
!        CASE(-1)
!          ARO = MIN(1._EB , RDY(JJ)*RDZ(KK)*MM%DY(JJO)*MM%DZ(KKO)) * 2._EB*DX(II)/(MM%DX(IIO)+DX(II))
!        CASE( 2)
!          ARO = MIN(1._EB , RDX(II)*RDZ(KK)*MM%DX(IIO)*MM%DZ(KKO)) * 2._EB*DY(JJ)/(MM%DY(JJO)+DY(JJ))
!        CASE(-2)
!          ARO = MIN(1._EB , RDX(II)*RDZ(KK)*MM%DX(IIO)*MM%DZ(KKO)) * 2._EB*DY(JJ)/(MM%DY(JJO)+DY(JJ))
!        CASE( 3)
!          ARO = MIN(1._EB , RDX(II)*RDY(JJ)*MM%DX(IIO)*MM%DY(JJO)) * 2._EB*DZ(KK)/(MM%DZ(KKO)+DZ(KK))
!        CASE(-3)
!          ARO = MIN(1._EB , RDX(II)*RDY(JJ)*MM%DX(IIO)*MM%DY(JJO)) * 2._EB*DZ(KK)/(MM%DZ(KKO)+DZ(KK))
         END SELECT
!          LSET_PHI_F =  LSET_PHI_F + 0.5_EB*ARO*(OM_LSET_PHI(IIO,JJO,KKO)-LSET_PHI_V)
           LSET_PHI_F =  LSET_PHI_F + 0.5_EB*ARO*(OM_LSET_PHI(IIO,JJO,1)-LSET_PHI_V)
       ENDDO
     ENDDO
!  ENDDO
!print '(A,1ES12.4)','                                                ',lset_phi_f
   LSET_PHI(II,JJ,1) = MIN( 1._EB , MAX( -1._EB , 2._EB*LSET_PHI_F-LSET_PHI_V ))
!print '(A,1ES12.4)','                                                ',lset_phi(ii,jj,1)

!if (jj == 15 .and. ii==0  .and. nm == 6) then 
!    print*,'==i0, nm=6 bc'
!    print '(A,1x,1(i3),1x,1(E12.5))','vege:nm i=0 bc',nm,lset_phi(ii,jj,1)
!    print '(A,1x,1(i3),1x,1(E12.5))','vege:nom ibar',nom,om_lset_phi(ibar,jj,1)
!    print '(A,1x,1(i3),1x,1(E12.5))','vege:nm i=1 bc',nm,lset_phi(1,jj,1)
!    print '(A,1x,1(i3),1x,1(E12.5))','vege:nom ibar-1',nom,om_lset_phi(ibar-1,jj,1)
!    print '(A,1x,1(i3),1x,1(E12.5))','vege:nom ibar-2',nom,om_lset_phi(ibar-2,jj,1)
!endif

!if (ii == 0 .and. jj==12 .and. nm==2) then
!  print*,'--ibar bc'
!  print '(A,1x,1(i3),1x,1(E12.5))','vege:ibp1 bc',nm,lset_phi(ii,jj,1)
!  print '(A,1x,2(i3),1x,1(E12.5))','vege:',nom,wc%nom_ib(1),om_lset_phi(wc%nom_ib(1),jj,1)
!endif

!if (nm==5) then
! print*,'\/\/\/\ mesh 6 & bounding i,j cells'
! print '(A,1x,3i3)','nm, i,j cells',nm,ii,jj
! iio=wc%nom_ib(1)
! jjo=wc%nom_ib(2)
! print '(A,1x,3i3)','nom, i cells',nom,wc%nom_ib(1),wc%nom_ib(4)
! print '(A,1x,3i3)','nom, j cells',nom,wc%nom_ib(2),wc%nom_ib(5)
! print '(A,1x,1ES12.4)','om phi(iio,jjo)',om_lset_phi(iio,jjo,1)
!endif
!f (jj == jbp1) lset_phi(ii,jj,1) = om_lset_phi(ii,1,1)
!f (jj ==    0) om_lset_phi(ii,jbar,1) = om_lset_phi(ii,0,1)

ENDDO WALL_CELL_LOOP_BC

END SUBROUTINE LEVEL_SET_BC

!--------------------------------------------------------------------
SUBROUTINE LEVEL_SET_DT(NM)
!Variable Time Step for simulations uncoupled from the CFD computation

INTEGER, INTENT(IN) :: NM
!INTEGER :: NM
REAL(EB) :: DT_CHECK_LS,PHI_CHECK_LS

!IF (EVACUATION_ONLY(NM)) RETURN
IF (.NOT. VEG_LEVEL_SET) RETURN
IF (VEG_LEVEL_SET_COUPLED) RETURN

!DO NM=1,NMESHES

  CALL POINT_TO_MESH(NM)

  PHI_CHECK_LS = MAXVAL(ABS(PHI_LS - PHI_TEMP_LS)) !Find max change in phi

!print '(A,1x,E13.5,1x,i3)','*************ls_dt,phi check,nm',phi_check_ls, nm !maxval(phi_Ls),nm
!print*,'ls_dt lset_ignition, nm',lset_ignition,nm

 
! IF (LSET_IGNITION) THEN
CHANGE_TIME_STEP(NM) = .FALSE.
IF (PHI_CHECK_LS > 0.0_EB) THEN
! If any phi values change by more than 0.5, or all change less
! than 0.1 (both values are arbitrary), during one time step,
! then adjust time step accordingly.

IF (PHI_CHECK_LS < 0.5_EB) THEN
   DT_NEXT = DT
   IF (PHI_CHECK_LS <= 0.1_EB) DT_NEXT = MIN(1.1_EB*DT,MIN(DX(1),DY(1))/DYN_SR_MAX)
ELSE
   DT = 0.5_EB*DT
   CHANGE_TIME_STEP(NM) = .TRUE.
ENDIF

!    CHANGE_TIME_STEP(NM) = .FALSE.
!    IF (PHI_CHECK_LS > 0.5_EB) THEN
!      ! Cut time step in half
!      DT_COEF = 0.5_EB * DT_COEF 
!      DT_CHECK_LS = DT_COEF * MIN(DX(1),DY(1))/DYN_SR_MAX
!      DT_CHECK_LS = MIN(DT_CHECK_LS,100._EB)
!!     DT_LS_UNCOUPLED = DT_CHECK_LS
!      print '(A,1x,E13.5,1x,A,i3)',"ls_dt Halving time step to, dt=  ",dt_check_ls,' mesh ',nm
!!     MESHES(NM)%DT_NEXT = DT_CHECK_LS
!      DT = DT_CHECK_LS
!      CHANGE_TIME_STEP(NM) = .TRUE.
!      RETURN
!    ELSE
!      DT_NEXT = DT
!    ENDIF
! 
!    ! Increase time step by 1/4 if changes are small
!!   IF (PHI_CHECK_LS > 0.01_EB .AND. PHI_CHECK_LS < 0.1_EB) DT_COEF = DT_COEF * 1.25_EB
!     
!    ! Dynamic Spread Rate Max
!      print '(A,1x,E13.5,1x,A,i3)',"ls_dt dyn_sr_max =  ",dyn_sr_max,' mesh ',nm
!    DYN_SR_MAX = MAX(DYN_SR_MAX,0.01_EB) ! dyn_sr_max must be g.t. zero
!!   DT_CHECK_LS = DT_COEF * MIN(DX(1),DY(1))/DYN_SR_MAX
!    DT_CHECK_LS = 0.25_EB*DT_COEF * MIN(DX(1),DY(1))/DYN_SR_MAX
!    DT_CHECK_LS = MIN(DT_CHECK_LS,100._EB)
!    IF (DT_CHECK_LS > DT) THEN
!      print '(A,1x,E13.5,1x,A,i3)',"ls_dt increasing time step to, dt=  ",dt_check_ls,' mesh ',nm
!      DT_NEXT = DT_CHECK_LS 
!    ENDIF
!
!!   IF (MAXVAL(PHI_LS) == -1.0_EB) THEN
!!     DT_NEXT = 10._EB*DT
!!     print '(A,1x,E13.5,1x,A,i3)',"ls_dt dphi=0,increasing time step to, dt=  ",dt_next,' mesh ',nm
!!   ENDIF
!   
!!   MESHES(NM)%DT_NEXT = DT_CHECK_LS
!
!!   DT_LS_UNCOUPLED = MAX(DT_LS,DT_LS_UNCOUPLED)
     
ENDIF

!ENDDO

!print '(A,1x,1E13.5)',"ls_dt:meshes(:)%dt=  ",meshes(1:nmeshes)%dt

END SUBROUTINE LEVEL_SET_DT


!************************************************************************************************
SUBROUTINE READ_BRNR
!************************************************************************************************
! Read in, from the run input file, the names of the file(s) containing HRRPUA in each mesh along 
! the bottom of the domain.
!
USE OUTPUT_DATA

INTEGER :: I,IOS,BURNER_MESH_NUMBER
CHARACTER(256) :: BRNRFILE='null'
NAMELIST /BRNR/ BURNER_MESH_NUMBER,BRNRFILE

N_BRNR=0
REWIND(LU_INPUT) ; INPUT_FILE_LINE_NUMBER = 0
COUNT_BRNR_LOOP: DO
   CALL CHECKREAD('BRNR',LU_INPUT,IOS)
   IF (IOS==1) EXIT COUNT_BRNR_LOOP
   READ(LU_INPUT,NML=BRNR,END=16,ERR=17,IOSTAT=IOS)
   N_BRNR=N_BRNR+1
   16 IF (IOS>0) THEN ; CALL SHUTDOWN('ERROR: problem with BRNR line') ; RETURN ; ENDIF
ENDDO COUNT_BRNR_LOOP
17 REWIND(LU_INPUT) ; INPUT_FILE_LINE_NUMBER = 0

IF (N_BRNR==0) RETURN

ALLOCATE(BRNRINFO(N_BRNR),STAT=IZERO) !array for burner data file names
CALL ChkMemErr('VEGE','BRNRINFO',IZERO)
ALLOCATE(BURNER_FILE(NMESHES),STAT=IZERO) ; BURNER_FILE = -99 !array for mesh number of burner data file
CALL ChkMemErr('VEGE','BURNER_FILE',IZERO)

IF (N_BRNR > NMESHES) THEN
  CALL SHUTDOWN('Problem with BRNR lines: N_BRNR > NMESHES') 
  RETURN
ENDIF
IF (.NOT. VEG_LEVEL_SET_BURNERS_FOR_FIRELINE) THEN
  CALL SHUTDOWN('Problem with BRNR lines: use of burners requires VEG_LEVEL_SET_BURNERS_FOR_FIRELINE=.TRUE.') 
  RETURN
ENDIF

READ_BRNR_LOOP: DO I=1,N_BRNR

   CALL CHECKREAD('BRNR',LU_INPUT,IOS)
   IF (IOS==1) EXIT READ_BRNR_LOOP

   ! Read the BRNR line

   READ(LU_INPUT,BRNR,END=37)

   BRNRINFO(I)%BRNRFILE = TRIM(BRNRFILE)
   BURNER_FILE(BURNER_MESH_NUMBER) = I

!print*,'read_brnr, nm, brnrfile',burner_mesh_number,brnrinfo(i)%brnrfile

ENDDO READ_BRNR_LOOP
37 REWIND(LU_INPUT) ; INPUT_FILE_LINE_NUMBER = 0

END SUBROUTINE READ_BRNR

!************************************************************************************************
SUBROUTINE GET_REV_vege(MODULE_REV,MODULE_DATE)
!************************************************************************************************
INTEGER,INTENT(INOUT) :: MODULE_REV
CHARACTER(255),INTENT(INOUT) :: MODULE_DATE

WRITE(MODULE_DATE,'(A)') vegerev(INDEX(vegerev,':')+1:LEN_TRIM(vegerev)-2)
READ (MODULE_DATE,'(I5)') MODULE_REV
WRITE(MODULE_DATE,'(A)') vegedate

END SUBROUTINE GET_REV_vege


END MODULE VEGE
