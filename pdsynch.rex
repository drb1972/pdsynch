/* pdsynch                                                                   */
/*---------------------------------------------------------------------------*/
/* currdir ------> Directory of the service location                         */
/* folder_name --> Directory of the working directory                        */
parse arg currdir folder_name

do forever
   say '['||time()||'] Using pdsb4g 'directory()
   "copy "currdir||"\config.json" "C:\Temp\" || folder_name
   if stop = 'Y' then leave 
   call read_config
   call check_lpars
   if pds2git = Y then call pds2git
   if git2pds = Y then call git2pds
   if cycle = 0 then leave
   call SysSleep(cycle)
end

exit

/*---------------------------------------------------------------------------*/
/* Check if the Master & other LPARs are UP                                  */
check_lpars:
   say 'MASTERPROF : 'master_prof
   'zowe zosmf check status --zosmf-p 'master_prof ' > 'master_prof ||'.txt'
   input_file  = master_prof ||'.txt'
   line = linein(input_file)
   call lineout input_file
   'del 'master_prof||'.txt'
   if pos('successfully connected',line)<>0 then say line 'Using profile 'master_prof 
   else do
      say 'LPAR 'master_prof 'offline' 
      exit
   end 

   do k = 1 to prof.0
      'zowe zosmf check status --zosmf-p 'prof.k ' > 'prof.k ||'.txt'
      input_file  = prof.k ||'.txt'
      line = linein(input_file)
      if pos('successfully connected',line)<>0 then say line 'Using profile 'prof.k 
      else do
         say 'LPAR 'prof.k 'offline' 
         prof.k = 'OFF'
      end 
      call lineout input_file
      'del 'prof.k||'.txt' 
   end
return

/*---------------------------------------------------------------------------*/
/* read congig.json file                                                     */
read_config:
   say '==================================='
   say ' Reading configuration'
   say '==================================='
   hlq.0 = 0 ; prof.0 = 0 
   input_file  = 'config.json'
   do while lines(input_file) \= 0
      line = caseless linein(input_file)
      valid_record = pos(":",line)
      if valid_record = 0 then iterate
      parse var line '"' head '"' ':' tail ',' 

      if pos('"',tail) = 0 then command = head "='"||tail||"'"
      else command = head "="tail
      
      interpret command 
      if substr(head,1,3) = 'hlq'  then hlq.0  = hlq.0  + 1
      if substr(head,1,4) = 'prof' then prof.0 = prof.0 + 1
   end /* do while */
   call lineout input_file
return
/*---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------*/
/* pds2git - Syncs PDS files from Master LPAR to GitHub and other LPARs      */
pds2git:
   say '==================================='
   say ' Mainframe ---> GitHub'
   say '==================================='

   commit = 'N'
/* Create hlq.json file with all PDS under config.json HLQs                  */
   if SysFileExists('hlq.json') = 1 then "del hlq.json"
   do i = 1 to hlq.0 
      'zowe zos-files list ds "'hlq.i'" -a --rfj --zosmf-p 'master_prof' >> hlq.json' 
   end

   drop dsname.; drop folder.; i = 0; dsname = ''; dsorg = ''; sal = ''

/* Read hlq.json and select only PO LRECL=80 PDSs and load dsname. stem      */
   input_file  = 'hlq.json'
   do while lines(input_file) \= 0
      sal = linein(input_file)
      select
         when pos('"stdout":',sal)<>0 then iterate
         when pos('"dsname":',sal)<>0 then parse var sal '"dsname":' dsname ','
         when pos('"dsorg":',sal)<>0  then parse var sal '"dsorg":' dsorg ','
         when pos('"lrecl":',sal)<>0  then parse var sal '"lrecl":' lrecl ','
         otherwise nop
      end /* select */
      if dsname <> '' & substr(dsorg,3,2) = 'PO' & substr(lrecl,3,2) = '80' then do 
         dsname = lower(dsname)
         i=i+1; dsname.i = changestr('"',dsname,' ')
         dsname.i = strip(dsname.i)
         dsname = ''; dsorg  = ''; lrecl = ''
      end /* if dsname */
   end /* while lines */
   call lineout input_file

/* Display the datasets that are going to be Synchronized                    */
   dsname.0 = i
      do i = 1 to dsname.0
   say dsname.i
   end

/* for each PDS                                                              */
   do i = 1 to dsname.0
      folder.i = translate(dsname.i,'\','.')     
      say dsname.i '--> ' folder.i
      x = value(dsname.i,'ok')

/* We check if there is a local folder in the working directory              */
      command = "exists = SysIsFileDirectory('"folder.i"')"
      interpret command
      if exists = 0 then do 
/* New PDS or first time synch                                               */   
         say 'Folder doesn''t exist'

/* Set file extensions for known files                                       */   
         select 
            when pos('.rex',dsname.i)>0 then ext = 'rex'
            when pos('.jcl',dsname.i)>0 then ext = 'jcl'
            when pos('.COBOL',dsname.i)>0 then ext = 'cbl'
            otherwise ext = 'txt'
         end

/* Download the whole PDS                                                    */   
         'zowe zos-files download am "'||dsname.i||'" -e 'ext' --zosmf-p 'master_prof' --mcr 10 '
         say 'Creating 'dsname.i'.json file'
/* Download a <pdsname>.json file with all members and its attributes (vvmm) */   
/* This file will be used for next cycles comparison to see what changed     */   
/* and be able to update other LPARs and the GitHub repository               */
         'zowe zos-files list am "'||dsname.i||'" -a --rfj --zosmf-p 'master_prof' > 'dsname.i||'.json'
         message = 'first-commit'
/* git commit & push changes                                                 */
         call commit message 
         "git push"

         if prof.0 > 0 then do
            do j = 1 to prof.0
               if prof.j = 'OFF' then iterate 
               returnedRows = ''; sal = ''
/* Check if the PDS exists in the target LPARs                               */
               'zowe zos-files list ds "'dsname.i'" -a --rfj --zosmf-p 'prof.j' > temp.txt' 

               input_file  = 'temp.txt'
               do while lines(input_file) \= 0
                  sal = linein(input_file)
                  select
                     when pos('"stdout":',sal)<>0 then iterate
                     when pos('"returnedRows":',sal)<>0 then parse var sal '"returnedRows":' returnedRows ','
                     otherwise nop
                  end /* select */
/* If the PDS doesn't exist in the target LPAR we create it and              */
/* synchronize the members                                                   */
                  if returnedRows = '0' then do
                     'zowe files create classic "'|| dsname.i ||'"  --bs 32720 --dst LIBRARY --rf FB --rl 80 --sz 15 --ss 15 --zosmf-p 'prof.j 
                     say 'zowe files upload dir-to-pds "'|| folder.i ||'" "'|| dsname.i ||'" --zosmf-p 'prof.j
                     'zowe files upload dir-to-pds "'|| folder.i ||'" "'|| dsname.i ||'" --zosmf-p 'prof.j
                  end
                  returnedRows = ''
               end /* while lines */
               call lineout input_file
               "del temp.txt"
            end /* do j */
         end /* if */
      end

      command = "exists = SysFileExists('"dsname.i || ".json')"
      interpret command
/* If thew <pdsname>.json file with all members vvmm doesn't exists create it*/   
      if exists = 0 then 'zowe zos-files list am "'||dsname.i||'" -a --rfj --zosmf-p 'master_prof' > 'dsname.i||'.json'

/* Check for Updates in the Master LPAR and deploy the differences           */
      j=0; drop list.; drop table.;  member = ''; vers = ''; mod = ''

/* Load previous cycle member versions vvmm in a stem table.<member>.old     */
/* each occurrence will have the vvmm                                        */
      say 'Loading previous member versions'
      input_file  = dsname.i||'.json'
      do while lines(input_file) \= 0
         sal = linein(input_file)
         select
            when pos('"stdout":',sal)<>0 then iterate
            when pos('"member":',sal)<>0 then parse var sal '"member": "' member '",'
            when pos('"vers":',sal)<>0   then parse var sal '"vers":' vers ','
            when pos('"mod":',sal)<>0    then parse var sal '"mod":' mod ','
            otherwise nop
         end /* select */
         if member <> '' & vers <> '' & mod <> '' then do
            member = strip(member); vers = strip(vers); mod = strip(mod)
            j=j+1; list.j =member
            table.member.old = 'v'||vers ||'m'||mod
            member = ''; vers = ''; mod = ''
         end /* if dsname */
      end /* do queued() */
      call lineout input_file

/* Load current cycle member versions vvmm in a stem table.<member>.new      */
/* each occurrence will have the vvmm                                        */
      say 'Loading current member versions'
      'zowe zos-files list am "'||dsname.i||'" -a --rfj --zosmf-p 'master_prof'> 'dsname.i||'.json'
      message = 'members-changed' 
      call commit message
      input_file  = dsname.i||'.json'
      do while lines(input_file) \= 0
         sal = linein(input_file)
         select
            when pos('"stdout":',sal)<>0 then iterate
            when pos('"member":',sal)<>0 then parse var sal '"member": "' member '",'
            when pos('"vers":',sal)<>0   then parse var sal '"vers":' vers ','
            when pos('"mod":',sal)<>0    then parse var sal '"mod":' mod ','
            otherwise nop
         end /* select */
         if member <> '' & vers <> '' & mod <> '' then do
            member = strip(member); vers = strip(vers); mod = strip(mod)
            j=j+1; list.j =member
            table.member.new = 'v'||vers ||'m'||mod
            member = ''; vers = ''; mod = ''
         end /* if dsname */
      end /* do queued() */
      call lineout input_file

      list.0 = j

/* Sort stem list. with all the members (old and new)                        */
      Do k = list.0 To 1 By -1 Until flip_flop = 1
         flip_flop = 1
         Do j = 2 To k
            m = j - 1
            If list.m > list.j Then Do
               xchg   = list.m
               list.m = list.j
               list.j = xchg
               flip_flop = 0
            End /* If stem.m */
         End /* Do j = 2 */
      End /* Do i = stem.0 */


      do k = 1 to list.0 
         j=k-1
         if list.k = list.j then iterate 
         member = list.k
         select
/* The member has been deleted from the Master LPAR                          */
/* We will delete from the working directory to update GitHub and from the   */
/* target LPARS                                                              */                
            when table.member.new = 'TABLE.'||member||'.NEW' then do 
               say ' Deleting 'folder.i||'\'||member 
               'del 'folder.i||'\'||member||'.*'
               message = 'Delete'
               call commit message
               if prof.0 > 0 then do
                  do l = 1 to prof.0
                     if prof.l = 'OFF' then iterate
                     say 'Delete member from 'prof.l
                     'zowe files delete data-set "'|| dsname.i ||'('member')" -f --zosmf-p 'prof.l
                  end
               end
            end
/* The member has been updated or created at the Master LPAR                 */
/* We will download it to the the working directory to update GitHub and     */
/* upload it to the target LPARS                                             */ 
            when table.member.new <> table.member.old then do 
               say dsname.i||'('||member||') updated from 'table.member.old ' to 'table.member.new
               select 
                  when pos('.rex',dsname.i)>0 then ext = 'rex'
                  when pos('.jcl',dsname.i)>0 then ext = 'jcl'
                  when pos('.COBOL',dsname.i)>0 then ext = 'cbl'
                  otherwise ext = 'txt'
               end
               'zowe files download ds "'||dsname.i||'('||member||')" -e 'ext '--zosmf-p 'master_prof
               if prof.0 > 0 then do
                  do l = 1 to prof.0
                     if prof.l = 'OFF' then iterate
                     say 'Copy member to 'prof.l
                     say 'zowe files upload file-to-data-set "'|| folder.i ||'\'member'.'ext'" "'|| dsname.i ||'('|| member ||')" --zosmf-p 'prof.l
                     'zowe files upload file-to-data-set "'|| folder.i ||'\'member'.'ext'" "'|| dsname.i ||'('|| member ||')" --zosmf-p 'prof.l
                  end
               end
/* The commit message will be the vvmm of the new/updated members            */
               message = table.member.new 
               call commit message
            end
            otherwise nop
         end
      end

   end /* do k = 1 to dsname.0 */

/* Cleanup: If a PDS has been deleted in the Master LPAR or taken out of the */ 
/* Datasets to synchronice in the config.json file it will be deleted from   */
/* GitHub but not on the target LPARs                                        */
   stem = rxqueue("Create")
   call rxqueue "Set",stem
   "dir *.json /B | rxqueue "stem 
   do queued()
      parse caseless pull sal
      parse var sal json_file '.json'
      select 
         when json_file = 'config' then nop
         when json_file = 'hlq' then nop 
         when value(json_file) = 'ok' then x = value(json_file,'ko')
         otherwise do 
            say ' Deleting 'json_file 
/* Check if the PDS has been deleted from Master LPAR or just from the       */
/* config.json set of datasets                                               */

            returnedRows = ''; sal = ''
/* Check if the PDS exists in the Master LPAR                                */
            'zowe zos-files list ds "'json_file'" --rfj --zosmf-p 'master_prof' > temp.txt' 

            input_file  = 'temp.txt'
            do while lines(input_file) \= 0
               sal = linein(input_file)
               select
                  when pos('"stdout":',sal)<>0 then iterate
                  when pos('"returnedRows":',sal)<>0 then parse var sal '"returnedRows":' returnedRows ','
                  otherwise nop
               end /* select */
/* If the PDS doesn't exist in Master LPAR we delete from the target LPARs   */
               if returnedRows = '0' then do
                  if prof.0 > 0 then do
                     do j = 1 to prof.0
                        if prof.j = 'OFF' then iterate
                        'zowe files delete data-set "'|| json_file ||'"  -f --zosmf-p 'prof.j 
                        say 'zowe files delete data-set "'|| json_file ||'"  -f --zosmf-p 'prof.j
                     end /* do j */
                  end  /* if prof */
               end /* if retirnedRows */
               returnedRows = ''
            end /* while lines */
            call lineout input_file
            "del temp.txt"

/* Delete the folder in the working directory to clean the GitHub repo       */
            "del "json_file || '.json'
            del_dir = translate(json_file,'\','.') 
            "rmdir /S /Q "del_dir  
            message = 'no more synch'
            call commit message
         end /* otherwise */
      end /* select */
   end /* do queued() */
   call rxqueue "Delete", stem

/* If anything has changed in the cycle then push to GitHub                  */
   if commit = 'Y' then do
      'git push'
   end
return

/*---------------------------------------------------------------------------*/
/* git2pds - Syncs the GitHub repo with all LPARs                            */
git2pds:
   say '==================================='
   say ' GitHub --> Mainframe'
   say '==================================='

/* First task is to make sure the Working directory is up to date, since the */ 
/* Synch process could be run before unidirectional                          */
/* In case that someone has been working offline with the repo we would get  */
/* the files that have been crated/deleted/Modified                          */
   command = 'git pull'
   stem = rxqueue("Create")
   call rxqueue "Set",stem
   interpret "'"command" | rxqueue' "stem 
   pull = 0; drop pull.
   do queued()
      parse caseless pull sal
      pull = pull + 1; pull.pull = sal
      say sal
   end
   call rxqueue "Delete", stem
   pull.0 = pull

   drop dataset.; i=0
   do k = 1 to hlq.0 

      hlq = hlq.k
/* Since the folders structure is the same as PDSs we easily format the      */
/* right structure                                                           */ 
      dir1 = translate(hlq,'\','.')     
      dir1 = translate(dir1,'','*')
      dir1 = translate(dir1,'','%')     
      dir2 = translate(dir1,'/','\')
      dir1 = lower(strip(dir1))
      dir2 = lower(strip(dir2))
 
      do m = 1 to pull.0
         filename = '' 
         sal = pull.m
         select
            when pos('Already up to date.',sal)<>0 then say hlq '-> Up to Date'
            when pos('files changed',sal)<>0 | pos('file changed',sal)<>0 then leave
            when pos(dir1,sal)<>0 | pos(dir2,sal)<>0 then do
               parse var sal filename ' |' . 
               filename = strip(filename)
               len = length(filename)
               dataset_member = substr(filename,1,len-4) 
               dataset_member = translate(dataset_member,'.','/')     
               dataset_member = translate(dataset_member,'.','\')     
               lp = lastpos('.',dataset_member) 
               dataset_member = translate(dataset_member,'(','.',,lp) || ')'
               lp = pos('(',dataset_member)  
               i=i+1; dataset.i = substr(dataset_member,1,lp-1) 
               if SysFileExists(filename) = 0 then Do
                  say 'File 'filename 'doesn''t exist'
/* This section is commneted                                                 */
/* Deleted files at GitHub would be deleted as well in the LPARs             */
/* For security reasons we are not deleting anything in the Mainframe        */
/* We just send a message */ say 'zowe zos-files delete data-set "'||dataset_member||'" --zosmf-p 'master_prof' -f '
/*                if prof.0 > 0 then do
                     do l = 1 to prof.0
                        if prof.l = 'OFF' then iterate */
                        say 'zowe zos-files upload file-to-data-set "'||filename||'" "'||dataset_member||'" --zosmf-p 'prof.l
/*                     end
                  end */
               end
               else do 
/* New and updated files in GitHub will be updated at all LPARs              */
                  'zowe zos-files upload file-to-data-set "'||filename||'" "'||dataset_member||'" --zosmf-p 'master_prof
                  if prof.0 > 0 then do
                     do l = 1 to prof.0
                        if prof.l = 'OFF' then iterate
                        'zowe zos-files upload file-to-data-set "'||filename||'" "'||dataset_member||'" --zosmf-p 'prof.l
                     end
                  end
               end /* if SysFileExists */   
            end
            otherwise nop
         end
      end /* do queued() */
   end /* do  k = 1 to hlq.0 */

/* Update de <pdsname>.json files with the current members vvmm              */
   dataset.0 = i
   do i = 1 to dataset.0
      say dataset.i 
      j = i-1
      if dataset.i = dataset.j then iterate
      'zowe zos-files list am "'||dataset.i||'" -a --rfj --zosmf-p 'master_prof' > 'dataset.i||'.json'
   end
return
/*---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------*/
/* Commit changes                                                            */
commit:
   parse caseless arg message 
   commit = 'Y'
   'git add -A'
   'git commit -a -m "'message'"'
return
/*---------------------------------------------------------------------------*/
