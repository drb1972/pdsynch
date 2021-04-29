# pdsynch


Utility to 
1. Synchronize a list of z/OS Datasets (PDS) from one Master LPAR to one or many others. 
   - 
2. Synchronize with a GitHub repo automatically and bi-directional

This particular setup uses a master LPAR where we make the changes to any member and the change will be updated in all defined LPARs in the [config.json](config.json) configuration file. 

## Requirements:
- Windows 
- zowe
- zOSMF REST APIs installed on the Mainframe 
- ooRexx
- local git global configured:
   - git config --global user.name myusername
   - git config --global user.email myemail
   - git config --global github.user myusername
   - git config --global github.token mytoken

## Instructions
- Plant a tree.
- Create an empty GitHub repo (only the first time).
- Configure your settings at [config.json](config.json) :
   - ```hlq.#``` : Set of libraries to synchronize. # must be sequential number (hlq.1, hlq.2 ...). 
      - ```"hlq.1"   : "CUST001.M*",``` 
      - ```"hlq.2"   : "CUST002.M*"```
   - ```cycle``` : Time in seconds between synchronization cycles. A value of 0 means a single execution.
      - ```"cycle"       : "0"```  : Single cycle execution. 
      - ```"cycle"       : "60"``` : Execute synchronization every minute.
   - ```master_prof``` : Zowe zosmf profile for the Master LPAR. This LPAR is where we will be updating PDSs.
      - ```"master_prof" : "zosmf-sr01brs"``` 
   - ```prof.#``` : Zowe zosmf profiles for the remote LPARs where the synchronization is going to take place. # must be sequential number (prof.1, prof.2 ...).
      - ```"prof.1"   : "zosmf-pe01",``` 
      - ```"prof.2"   : "zosmf-pe02"```
   - ```stop``` : Set it to ```'N'``` to run the utility. Change to ```'Y'``` whenever you want to stop the synchronization correctly. It will stop the process in the next loop. This is to avoid shutting down the utility in the middle of the synchronization process.  
   - ```ghrepo``` : GitHub repository to manage PDS members versioning.  
      - ```"ghrepo"      : "https://github.com/drb1972/demo.git"``` 
   - ```pds2git``` : Enables Mainframe to GitHub synchronization. Whenever we create, update or delete a member in the Master LPAR the change will be commited iin the GitHub repo. 
      - ```"pds2git"     : "Y"```
      - ```"pds2git"     : "N"```
   - ```git2pds``` : Enables GitHub to Mainframe synchronization.
      - ```"git2pds"     : "Y"```
      - ```"git2pds"     : "N"```
   - Set the cycle time in seconds at "cycle". Value of 1 will synch continously 
   - Set the zowe zOSMF profile you want to use at "zosmf_p"
- Run st.rex 



pdsb4g is set to synchronize only PDS or PDS-E files with LRECL 80, but can be set to synch any dataset on the mainframe. It is meant to version home made ISPF applications that are not included in standard Mainframe SCMs. Also for JCL, Rexx, parm, ISPF panel, ISPF messages, ISPF skeleton libraries. 

The first time the service is executed takes a while until synchronizes PDSs with GitHub depending of the number of PDS and Members. Following times is very fast by updating any change. 

If you just want to se how it works or demo, choose a small amount of PDS and set the cycle to 1 second. 

Once you start the process in cmd line: "rexx st.rex"

- Test1: 
   - Edit a member in 3270 (I don't recommend zowe explorer because it works with cached data and doesn't reflect the updates sometimes), delete a couple of lines and add another. 
   - Delete another member
   - Create a new member
   - Wait a minute before you go to GitHub and see the changes. Edit the member in GitHub that you modified and click on history icon or in the commit code to see the changes.
   - Repeat various times by changing the same member. You'll see the modification history.

- Test2: 
   - Open VSCode (or your preferred IDE)
   - Open your projects folder and open a terminal
   - "git clone <your_github_repo>"
   - Position your prompt in the cloned folder
   - Modify, delete and create new files
   - Update the GitHub repo with your preferred method (GH Desktop, VSCode extension, command line, ...)
      - git add .
      - git commit -m "<any-message>"
      - git push
   - With this method, you will have one commit for all changes you made, so this is better if you want to group changes in a single commit

- Test3:
   - Create a PDS with the same HLQ than the one being synch and feed it with some members
   - Check it exists in GitHub after waiting a few seconds to complete the cycle

- Test4: 
   - Delete the PDS you just created 
   - Check it has disspeared from GitHub after waiting some seconds to complete the cycle

- Test5:
   - Add a new hlq in config.json file: "hlq.3"   : "CUST003.M*",

- Test6:
   - Delete an hlq in config.json file

   Any comment is welcome: diego.rodriguez@broadcom.com , and don't forget to plant the tree