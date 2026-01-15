As part of my DevOps self-training, I developed two scripts to make managing systems easier and more reliable:

1. **Automated Database Backup**  
    - A bash script that automatically backs up your containerized database, encrypts the backups, and securely sends them to an email address of your choice giving you peaceful nights.

    **Features**  
    - Automated database backups based on your cron job configuration
    - Added delay feature to prevent spamming
    - Secure delivery via email to an address of your choice
    - Notifications for success or failure on either mail or sms, based on your service provider
    - Easy to configure and run

    **Setting Up**
    - Clone the repo from "https://github.com/Webstar95/DEV-OPS-Automated-Server-Assists.git"
    - Create the following main directories on your instance assuming your VM is Linux Based;

        **auto-backup** is the actual directory for the raw backup file
        **auto-backup-temp** holds the chunks when the file exceeds 20MB to enable sending in batches to bypass the email attachment size restrictions.

        - Please ensure the directories match
            mkdir -p /{{directory_path}}/auto-backup
            mkdir -p /{{directory_path}}/auto-backup-temp
        - Ensure the directories are readable by the instance user by running on both;
            chmod -R 777 {{directory_name}}

    - Update the variables on the .env.demo file to your actual but keep this file out of GitHub with gitignore. 
        **Do not commit secrets!**
    - Copy the two files on your prefered server path and ensure the bash script is executable by running;
        # chmod +x {{file_name.sh}}
    - To run the backup, run the command;
        # bash {{file_name.sh}} -- This will trigger the process and will log the messages as it runs. 
    - Once certain the process is successful, you can proceed to automate by impleementing a cron job to carry out the process within your convenience;
        1. run "crontab -e"
        2. choose your prefered file editor
        3. Set cron job for example, midnight --> "0 0 * * * /path_to_file/{{file_name}}.sh" 
        4. Save the file and you should see the message; installing new crontab
        - You are now set.

    **NOTE:** Database backups may be large at times, ensure your recipient can handle large backups as this can fill quite fast if you have backups north of 200MB and also may incur costs on the email service provider.

2. **Simple Application / Server Monitoring**  
   - Monitors an application or server instance (similar in concept to Google Analytics, but lightweight).  
   - Sends notifications whenever downtime or issues occur, allowing you to address problems before they impact users.
