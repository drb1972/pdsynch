/* pdsynch                                                            */
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

/* read congig.json file                                             */
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

/* pds2git - Syncs PDS files with GitHub                             */
pds2git:
   say '==================================='
   say ' Mainframe ---> GitHub'
   say '==================================='

/* retrieve hlq PDS names and load dsname. stem                      */
   if SysFileExists('hlq.json') = 1 then "del hlq.json"
   do i = 1 to hlq.0 
      'zowe zos-files list ds "'hlq.i'" -a --rfj --zosmf-p 'master_prof' >> hlq.json' 
   end

   drop dsname.; drop folder.; i = 0; dsname = ''; dsorg = ''; sal = ''
   
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
   dsname.0 = i
   /* dxr*/ do i = 1 to dsname.0
   say dsname.i
   end

/* for each PDS                                                      */

   do i = 1 to dsname.0
      folder.i = translate(dsname.i,'\','.')     
      say dsname.i '--> ' folder.i
      x = value(dsname.i,'ok')
      
      command = "exists = SysIsFileDirectory('"folder.i"')"
      interpret command
      if exists = 0 then do 
/* New PDS or first time                                             */   
         say 'Folder doesn''t exist'

         select 
            when pos('.rex',dsname.i)>0 then ext = '-e rex'
            when pos('.jcl',dsname.i)>0 then ext = '-e jcl'
            when pos('.COBOL',dsname.i)>0 then ext = '-e cbl'
            otherwise ext = ''
         end

         'zowe zos-files download am "'||dsname.i||'" 'ext' --zosmf-p 'master_prof' --mcr 10 '
         say 'Creating 'dsname.i'.json file'
         'zowe zos-files list am "'||dsname.i||'" -a --rfj --zosmf-p 'master_prof' > 'dsname.i||'.json'
         message = 'first-commit'
         call commit message 
         "git push"
         /* Create files in other LPARs */
         if prof.0 > 0 then do
            do j = 1 to prof.0
               if prof.j = 'OFF' then iterate 
               returnedRows = ''; sal = ''
               'zowe zos-files list ds "'dsname.i'" -a --rfj --zosmf-p 'prof.j' > temp.json' 

               input_file  = 'temp.json'
               do while lines(input_file) \= 0
                  sal = linein(input_file)
                  select
                     when pos('"stdout":',sal)<>0 then iterate
                     when pos('"returnedRows":',sal)<>0 then parse var sal '"returnedRows":' returnedRows ','
                     otherwise nop
                  end /* select */
                  if returnedRows = '0' then do
                     'zowe files create classic "'|| dsname.i ||'"  --bs 32720 --dst LIBRARY --rf FB --rl 80 --sz 15 --ss 15 --zosmf-p 'prof.j 
                     say 'zowe files upload dir-to-pds "'|| folder.i ||'" "'|| dsname.i ||'" --zosmf-p 'prof.j
                     'zowe files upload dir-to-pds "'|| folder.i ||'" "'|| dsname.i ||'" --zosmf-p 'prof.j
                  end
                  returnedRows = ''
               end /* while lines */
               call lineout input_file
            end /* do j */
         end /* if */
      end

      command = "exists = SysFileExists('"dsname.i || ".json')"
      interpret command
      if exists = 0 then 'zowe zos-files list am "'||dsname.i||'" -a --rfj --zosmf-p 'master_prof' > 'dsname.i||'.json'

/* Update                                                            */

      j=0; drop list.; drop table.;  member = ''; vers = ''; mod = ''

/* Load old member version                                           */

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

/* Load current member version                                       */
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

/* sort stem buble method */
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
               message = table.member.new 
               call commit message
            end
            otherwise nop
         end
      end

   end /* do k = 1 to dsname.0 */

/* cleanup delete PDS                                      */
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
            "del "json_file || '.json'
            del_dir = translate(json_file,'\','.') 
            "rmdir /S /Q "del_dir  
            message = 'no more synch'
            call commit message
         end
      end
   end
   call rxqueue "Delete", stem


   if commit = 'Y' then do
      'git push'
   end
return

git2pds:
   say '==================================='
   say ' GitHub --> Mainframe'
   say '==================================='

   drop dataset.; i=0
   do k = 1 to hlq.0 

      hlq = hlq.k

      dir1 = translate(hlq,'\','.')     
      dir1 = translate(dir1,'','*')
      dir1 = translate(dir1,'','%')     
      dir2 = translate(dir1,'/','\')
      dir1 = lower(strip(dir1))
      dir2 = lower(strip(dir2))

      command = 'git pull'
      stem = rxqueue("Create")
      call rxqueue "Set",stem
      interpret "'"command" | rxqueue' "stem  
      do queued()
         filename = '' 
         parse caseless pull sal
         select
            when pos('Already up to date.',sal)<>0 then say 'Up to Date'
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
                  /* Not deleting anything in the Mainframe */
                  /* dxr */ say 'zowe zos-files delete data-set "'||dataset_member||'" --zosmf-p 'master_prof' -f '
               end
               else do 
               /* dxr - Me falta borrar/añadir a las otras LPARs y actualizar listado de miembros fichero.json*/
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
      
      call rxqueue "Delete", stem
      
   end /* do  k = 1 to hlq.0 */


   dataset.0 = i
   do i = 1 to dataset.0
      say dataset.i 
      j = i-1
      if dataset.i = dataset.j then iterate
      'zowe zos-files list am "'||dataset.i||'" -a --rfj --zosmf-p 'master_prof' > 'dataset.i||'.json'
   end
return

commit:
   parse caseless arg message 
   commit = 'Y'
   'git add -A'
   'git commit -a -m "'message'"'
return
