//IEBCOPY  JOB (124400000),'CUST013-R3',CLASS=A,
//             MSGCLASS=X,MSGLEVEL=(1,1),REGION=0M,NOTIFY=&SYSUID
//STEP1     EXEC PGM=IEBCOPY
//SYSPRINT  DD SYSOUT=*
//DDIN      DD DSNAME=PRODUCT.SYSV15.SMPE13.CNM4BLOD,DISP=SHR
//DDOUT     DD DSNAME=PRODUCT.SVRUN13.MSTRBRS.CNM4BLOD,
//             DISP=SHR
//SYSUT3    DD UNIT=SYSDA,SPACE=(CYL,(1,1))
//SYSIN     DD *
GROUPCPY   COPYGRP  INDD=((DDIN,R)),OUTDD=DDOUT
/*
//
