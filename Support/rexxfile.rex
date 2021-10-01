/* rexx */
arg action              /* receives task as an argument    */
call init action        /* loads the config.rex variables  */
interpret call action   /* launch the task                 */
call exit 0

/**
* Polls state of SSM managed resource. Return is made without error if desired state is
* reached within the the allotted time
* resource      SSM managed resource to check the state of
* desiredState  desired state of resource
* tries         max attempts to check the completion of the job
* wait          wait time in sec. between each check
*/
awaitSSMState:
   parse arg resource,desiredState
   tries = 30
   wait = 1
   command = 'zowe ops show resource 'resource

   do while tries > 0
      tries = tries - 1
      call sleep 1
      stem = rxqueue("Create")
      call rxqueue "Set",stem
      interpret "'"command" | rxqueue' "stem
      drop sal.; j = 0; sal = ''
         do queued()
         pull sal
         j=j+1
         sal.j = sal
      end
      sal.0 = j
      call rxqueue "Delete", stem
      if sal.0 <> 2 then do
         say 'Command:' command 'Stack Trace:'
         do j = 1 to sal.0
            say sal.j
         end
         call exit 8
      end
      else do
         do j = 1 to sal.0
            /* First find the header */
            parse var sal.j 'CURRENT: ' currentState .
         end
         /* log output */
         call writeToDir "command-archive/show-resource"
         /* check if currentState is the desiredState */
         /* currentState does equal desiredState so success! */
         if currentState = desiredState then return
      end
   end /* while */
   say resource 'did not reached desired state of 'desiredState' in the allotted time.'
   call exit 8
return

/**
* Changes state of SSM managed resource. Return is made without error if desired state is
* reached within the the allotted time
* resource      SSM managed resource to change the state of
* state         desired state of resource
* apf           data set to APF authorize if required
*/
changeResourceState:
   parse arg resource,state,apf
   select
      when state = "UP" then do
         command = 'zowe ops start resource '||resource
         dir = "command-archive/start-resource"
      end
      when state = "DOWN" then do
         command = 'zowe ops stop resource '||resource
         dir = "command-archive/stop-resource"
      end
      otherwise do
         say 'Unrecognized desired state of: 'state'. Expected UP or DOWN.'
        call exit 8
      end
   end

   /* Submit command, await completion */
   stem = rxqueue("Create")
   call rxqueue "Set",stem
   interpret "'"command" | rxqueue' "stem
   drop sal.; j = 0; sal = ''
   if queued() <> 2 then call exit 8
   do queued()
      pull sal
      j=j+1
      sal.j = sal
   end
   sal.0 = j
   call rxqueue "Delete", stem
   call writeToDir dir

   /* Await the SSM Resource Status to be up */
   call awaitSSMState resource,state
   if apf <> '' then do
      /* Resource state successfully changed and needs APF authorized */
      command = 'zowe zos-console issue command "SETPROG APF,ADD,DSNAME='||apf||',SMS" --cn '||consoleName
      call simpleCommand command
   end
return

createAndSetProfiles:
   parse arg host,user,pass
   drop command.
   drop dir.
   command.0=4
   command.1 = "zowe profiles create zosmf bmw --host "||host||" --user "||user||" --pass "||pass|| ,
                      " --port "||zosmfPort||" --ru "||zosmfRejectUnauthorized||" --ow"
   dir.1     = "command-archive/create-zosmf-profile"
   
   command.2 = "zowe profiles set zosmf bmw"
   dir.2     = "command-archive/set-zosmf-profile"

   command.3 = "zowe profiles create ops bmw --host "||host||" --user "||user||" --pass "||pass|| ,
                      " --port "||opsPort||" --ru "||opsRejectUnauthorized|| ,
                      " --protocol "||opsProtocol||" --ow"
   dir.3     = "command-archive/create-ops-profile"

   command.4 = "zowe profiles set ops bmw"
   dir.4     = "command-archive/set-ops-profile"

   call submitMultipleSimpleCommands 
return

/**
* Parses holddata in local file and creates holddata/actions.json file with summarized findings
* filepath local filePath to read Holddata from
*/
parseHolddata:
   parse arg filepath
   remainingHolds = "false"
   restart        = "false"
   reviewDoc      = "false"

   holds = "++HOLD ("||expectedFixLevel||")"
   file=.stream~new(filepath)  /* Create a stream object for the file */
   do while file~lines<>0      /* Loop as long as there are lines     */
      text=file~linein         /* Read a line from the file           */
      if pos(holds,text)<>0 then do
         text=file~linein
         select 
            when pos("REASON (DOC    )",text)<>0 then reviewDoc = "true"
            when pos("REASON (RESTART)",text)<>0 then restart   = "true"
            otherwise remainingHolds = "true"
         end /* select */
      end /* if */
   end /* do while */

   /* sal. stem in JSON format */
   drop sal.
   sal.1 = '{'
   sal.2 = '  "remainingHolds": ' || remainingHolds || ','
   sal.3 = '  "restart": ' || restart || ','
   sal.4 = '  "reviewDoc": ' || reviewDoc
   sal.5 = '}'
   sal.0 = 5
   
   call writeToFile 'holddata','actions.json'
return

simpleCommand:
   parse arg command,dir,expectedOutputs
   stem = rxqueue("Create")
   call rxqueue "Set",stem
   interpret "'"command" | rxqueue' "stem
   drop sal.; j = 0; sal = ''
   do queued()
      pull sal
      j=j+1; sal.j = sal
   end
   sal.0 = j
   call rxqueue "Delete", stem
   call writeToDir dir   /* log output */
   if expectedOutputs <> '' then call verifyOutput expectedOutputs
return

/**
 * Sleep function.
 * sec Number of seconds to sleep
 */
sleep:
   parse arg sec
   call SysSleep(sec)
return

/**
* Submits job, verifies successful completion, stores output
* ds        data-set to submit
* [dir="job-archive"] local directory to download spool to
* [maxRC=0] maximum allowable return code
*/
submitJobAndDownloadOutput:
   parse arg ds,dir,maxRC
   if dir   = '' then dir   = 'job-archive'
   if maxRC = '' then maxRC = '0'
   command = 'zowe jobs submit data-set "'|| ds ||'" -d '|| dir ||' --rfj'

   stem = rxqueue("Create")
   call rxqueue "Set",stem
   interpret "'"command" | rxqueue' "stem
   drop sal. ; j = 0
   do queued()
      pull sal
      j = j + 1
      sal.j = sal
   end
   sal.0 = j
   call rxqueue "Delete", stem

   dir = "command-archive/job-submission"
   call writeToDir dir  

   retcode = ''
   jobid = ''
   do i = 1 to sal.0
      v1 = ''
      v2 = ''
      parse upper var sal.i . '"RETCODE": "CC' v1 '"' .
      if v1 <> '' then retcode = v1 
      parse upper var sal.i . '"JOBID": "' v2 '"' .
      if v2 <> '' then jobid = v2 
      if retcode <> '' & jobid <> '' then leave
   end

   if retcode > maxRC then do
      say 'Job did not complete successfully. Additional diagnostics:'
      do i = 1 to sal.0
         say sal.i
      end
      call exit 8
   end
return

submitMultipleSimpleCommands:
   do i=1 to command.0
      call simpleCommand command.i,dir.i
   end
return

/**
* Verifies Output from command and returns without error if successful
* data            command to run
* expectedOutputs list of expected strings to be in the output
*/
verifyOutput:
   parse arg expectedOutputs
   data = ''
   do j = 1 to sal.0
      data = data sal.j
   end
   num = words(expectedOutputs)
   drop sym.
   do i = 1 to num
      sym.i = word(expectedOutputs,i)
   end
   do i = 1 to num
      if pos(sym.i,data) = 0 then do
         say sym.i " not found in response: " data
         call exit 8
      end
   end
return

/**
* Writes content to files
* dir      directory to write content to
* filename name of the file
*/
writeToDir:
   filename = substr(.dateTime~new,1,23)||'Z.txt'           /* Timestamp + Z.txt                  */
   filename = changestr(':',filename,'-')                   /* Replace ':' for '-' to avoid error */
   call writeToFile dir,filename
return

writeToFile:
   parse arg dir,filename
   if SysIsFileDirectory('command-archive') = 0 then call SysMkDir('command-archive')   
   if SysIsFileDirectory('job-archive') = 0 then call SysMkDir('job-archive')   
   if SysIsFileDirectory(dir) = 0 then call SysMkDir(dir)   /* Creates Directory if doesn't exist */
   filename = dir||'/'||filename                            /* Whole path route                   */
   logfile=.stream~new(filename)                            /* Create file                        */
   logfile~open("both replace")                             /* Open Read/Write                    */
   do j = 1 to sal.0
      logfile~lineout(sal.j)                                /* Write al stem output from command  */
   end
   logfile~close
return

apf:
   desc = 'apf , APF authorize dataset'
   call display_init
   ds = runtimeEnv ||'.'|| maintainedPds
   command = 'zowe console issue command "SETPROG APF,ADD,DSNAME=' || ds || ',SMS" --cn ' || consoleName
   output  = "CSV410I" ds
   call simpleCommand command,"command-archive/apf",output
   call display_end
return

apply:
   desc = 'apply , Apply Maintenance'
   call display_init
   ds = remoteJclPds ||'('|| applyMember ||')'
   call submitJobAndDownloadOutput ds, "job-archive/apply", 0
   call display_end
return

applyCheck:
   desc = 'applyCheck , Apply Check Maintenance'
   call display_init
   ds = remoteJclPds ||'('|| applyCheckMember ||')'
   call submitJobAndDownloadOutput ds, "job-archive/applyCheck", 0
   call display_end
return

copy:
   desc = 'copy , Copy Maintenance to Runtime'
   call display_init
   ds = remoteJclPds ||'('|| copyMember ||')'
   call submitJobAndDownloadOutput ds, "job-archive/copy", 0
   call display_end
return

download:
   desc = 'download , Download Maintenance'
   call display_init
   command = 'zowe files download uf "' ,
            || serverFolder ||'/' || serverFile || '" -f "' ,
            || localFolder  ||'/' || localFile  || '" -b --rfj'
   call simpleCommand command, "command-archive/download"
   call display_end
return

receive:
   desc = 'receive , Receive Maintenance'
   call display_init
   ds = remoteJclPds ||'('|| receiveMember ||')'
   call submitJobAndDownloadOutput ds, "job-archive/receive", 0
   call parseHolddata "job-archive/receive/" || jobid || "/SMPEUCL/SMPRPT.txt"
   call display_end
return

reject:
   desc = 'reject , Reject Maintenance'
   call display_init
   ds = remoteJclPds ||'('|| rejectMember ||')'
   call submitJobAndDownloadOutput ds, "job-archive/reject", 0
   call display_end
return

restartWorkflow:
   desc = 'restartWorkflow , Create and trigger workflow to restart SYSVIEW'
   call display_init
   command = 'zowe zos-workflows start workflow-full --workflow-name ' ,
             || restartWorkflowName ||' --wait'
   call simpleCommand command, "command-archive/start-workflow" 
   call display_end
return

restore:
   desc = 'restore , Restore Maintenance'
   call display_init
   ds = remoteJclPds ||'('|| restoreMember ||')'
   call submitJobAndDownloadOutput ds, "job-archive/restore", 0
   call display_end
return

setupProfiles:
   desc = 'setupProfiles , Create project profiles and set them as default'
   say 'Host name or IP address: '
   parse caseless pull host
   say 'Username: '
   parse caseless pull user
   say 'Password: '
   parse caseless pull pass
   call display_init
   call createAndSetProfiles host, user, pass
   call display_end
return

start1:
   desc = 'start1 , Start SSM managed resource1'
   call display_init
   call changeResourceState ssmResource1,"UP"
   call display_end
return

start2:
   desc = 'start2 , Start SSM managed resource2'
   call display_init
   call changeResourceState ssmResource2,"UP"
   call display_end
return

stop1:
   desc = 'stop1 , Stop SSM managed resource1'
   call display_init
   call changeResourceState ssmResource1,"DOWN"
   call display_end
return

stop2:
   desc = 'stop2 , Stop SSM managed resource2'
   call display_init
   call changeResourceState ssmResource2,"DOWN"
   call display_end
return

upload:
   desc = 'upload , Upload Maintenance to USS'
   call display_init
   command = 'zowe files upload ftu "' ,
               || localFolder  ||'/' || localFile  ||'" "' ,
               || remoteFolder ||'/' || remoteFile ||'" -b --rfj'
   call simpleCommand command, "command-archive/upload"
   call display_end
return

reset:
   desc = 'reset , Reset maintenance level'
   call display_init
   call reject; call restore; call stop; call copy; call apf; call start
   call display_end
return

start:
   desc = 'start , Start SSM managed resources'
   call display_init
   call start1; call start2
   call display_end
return

stop:
   desc = 'stop , Stop SSM managed resources' 
   call display_init
   call stop2; call stop1
   call display_end
return

init:
   if action = '' then action = help

   say '['||time()||'] Using rexxfile 'directory()

   /* read config.json file */
   input_file  = 'config.json'
   do while lines(input_file) \= 0
      line = caseless linein(input_file)
      valid_record = pos(":",line)
      if valid_record = 0 then iterate
      parse var line '"' head '"' ':' tail ',' 

      if pos('"',tail) = 0 then command = head "='"||tail||"'"
      else command = head "="tail
      
      interpret command 
   end /* do while */
   call lineout input_file
   init = rxqueue("Create")
   
return

display_init:
   parse var desc task ',' .
   task = strip(task)
   tinit.task = time(s)
   say '['||time()||'] Starting '''task''' ...'
   call rxqueue "Set",init
   push task
return

display_end:
   call rxqueue "Set",init
   parse caseless pull task
   tend.task = time(s)
   time = tend.task - tinit.task
   say '['||time()||'] Finished '''task''' after ' time 's.'
return

/* Help */
help:
   desc = 'help , Display this help text.'
   call display_init
   say 'Usage'
   say '-----'
   say '  rexx rexxfile [TASK] [OPTIONS]'
   say ''
   say 'Available tasks'
   say '---------------'

   /* read rexxfile.rex file */
   input_file  = 'rexxfile.rex' /* dxr */
   do while lines(input_file) \= 0
      line = caseless linein(input_file)
      valid_record = pos("desc =",line)
      if valid_record = 0 then iterate
      parse var line "desc =" "'" task "," text "'"
      if pos('line',line) > 0 then iterate /* avoid previous line */
      task = strip(task)
      text = strip(text)
      say left(task,15) text
   end /* do while */
   call lineout input_file
   call display_end
return

exit:
   parse arg exitrc
   call rxqueue "Delete", init
   exit exitrc
retun

/* end-of-file */