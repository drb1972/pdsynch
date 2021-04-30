/* rexx - st */
call read_config
/*---------------------------------------------------------------------------*/
/* Retrieve the name of the Service location                                 */
"dir > currdir.txt"
input_file  = 'currdir.txt'
do while lines(input_file) \= 0
   line = caseless linein(input_file)
   if pos('Directory of',line)<>0 then do     
      parse var line ' Directory of ' currdir
      leave 
   end 
end /* do while */
call lineout input_file
/*---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------*/
/* Working Directory                                                         */
if SysIsFileDirectory('C:\Temp') = 0 then "md C:\Temp"
"cd C:\Temp"
parse var ghrepo . '//' . '/' . '/' folder_name '.git'

if SysIsFileDirectory(folder_name) = 0 then do
   -- "rmdir /S /Q "folder_name
   "git clone "ghrepo
end
"cd "folder_name
/* Copy congif file from Service Location to Working Directory               */
"copy "currdir||"\pdsynch.rex"
"copy "currdir||"\config.json"
"echo pdsynch.rex > .gitignore"
"echo *.txt >> .gitignore"
/* "echo *.json >> .gitignore" */
'git commit -a -m "first-commit"'

/* Start running the service                                                 */
"rexx pdsynch.rex" currdir folder_name
exit

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