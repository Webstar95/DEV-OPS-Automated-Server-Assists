#!/bin/bash

# -------------- Retreive Environment Variables -------------- #

# Load env. file
if [ -f /.env.bkup ]; then
    export $(grep -v '^#' /.env.bkup | xargs)
else
    echo "Error: .env.bkup file not found!"
    exit 1
fi

# ------------------ Log File Setup ------------------ #

log_file="$main_directory_path/auto-backup/backup.log"
touch "$log_file"
echo "======================" >> "$log_file"
echo "$(date) - Backup started" >> "$log_file"

# ------------------ Load Variables ------------------ #

# Recipient email address
EMAIL_RECIPIENT="$email_recipient"

# Sender email address
SENDER_EMAIL="$sender_email"

# Set the current date and time for the backup file
current_date=$(date +"%Y-%m-%d_%H-%M-%S")

# Directory to store the backup files
main_dir=$main_directory_path
backup_dir="$main_dir/auto-backup"

# Temporary directory to store split files
temp_dir="$main_dir/auto-backup-temp"

# Name of the backup file
backup_file="$backup_dir/postgres_backup_$current_date.sql"

# Docker container name for PostgreSQL
container_name=$dockerized_container_name

# encryption
ENCRYPTION_PASSWORD="$encryption_password"

# PostgreSQL container credentials
db_username="$postgresql_user"
db_password="$postgresql_password"
db_name="$postgresql_database"

# Email Configuration e.g Using Mailgun API settings
MAILGUN_API_KEY="$mailgun_api_key"
MAILGUN_DOMAIN="$mailgun_domain"
MAILGUN_SMTP="https://api.mailgun.net/v3/$MAILGUN_DOMAIN/messages"
MESSAGE="Backup initialized ..."

# ------------------ Mail Content ------------------ #

# Subject of the Email
subject="PostgreSQL $application_name Backup - $current_date"

# Message body
message="Attached is the daily backup of the $application_name PostgreSQL database."

# Step 1: Dump the PostgreSQL database to a file from inside the dockerized container or path to PostgreSQL database 
docker exec -t "$container_name" pg_dump -U "$db_username" -d "$db_name" > "$backup_file"

# Step 1.1: Check if the dump was successful
if [ $? -eq 0 ]; then
    echo "PostgreSQL database dumped successfully."

    # Split the SQL file into 20MB pieces to prevent email size limits
    split -b 20M "$backup_file" "$temp_dir/sql_part_"

    # Get a list of split files
    split_files=("$temp_dir"/*)

else
    echo "Error dumping PostgreSQL database." | tee -a "$log_file"
    exit 1
fi

# Step 1.2 Loop through each split file and send it as an attachment
for split_file in "${split_files[@]}"; do

echo "This is the start of the script to send email."

# Step 2: Encrypt file using encryption password from .env file
gpg --batch --yes --passphrase "$ENCRYPTION_PASSWORD" -c "$split_file"
encrypted_file="$split_file.gpg"

# Step 2.1: Acquire file size. If above 20MB will be split equally
file_size_bytes=$(stat -c %s "$encrypted_file")
file_size_mib=$(echo "scale=2; $file_size_bytes / 1024 / 1024" | bc)
echo "Encrypted file size of '$encrypted_file' is $file_size_mib MiB." | tee -a "$log_file"

# Step 2.2: Encode encrypted file in base64
split_base64=$(base64 -w 0 "$encrypted_file")

# Step 3: Create a JSON payload for Mailgun
payload=$(cat <<EOF
{
  "from": "$SENDER_EMAIL",
  "to": "$EMAIL_RECIPIENT",
  "subject": "$subject",
  "text": "$message",
  "attachment": [ { "content": "$split_base64", "filename": "$(basename "$encrypted_file")" } ]
}
EOF
)

# Step 3.1: Send the email via Mailgun API using curl request
curl -s --user "api:$MAILGUN_API_KEY" \
  "$MAILGUN_SMTP" \
  -F from="$SENDER_EMAIL" \
  -F to="$EMAIL_RECIPIENT" \
  -F subject="$subject" \
  -F text="$message" \
  -F attachment=@$encrypted_file

# Step 3.2: Check the response from Mailgun (optional) can be Mail or SMS
if [ $? -eq 0 ]; then
    MESSAGE="Hey devs, your $application_name backup was successful and an email was sent!"
  echo "Email sent successfully."
else
  MESSAGE="Hey devs, something went wrong while backing up your $application_name dbase, please consult the server logs."
  echo "Error sending email." | tee -a "$log_file"
  exit 1
fi

# Step 3.3: Pause for 10 seconds to avoid spamming email recipient
sleep 10

echo "This is after pausing for 10 seconds. Lets continue"

done

# ------------------ Notifications Central ------------------ #

# 1: SMS Option - You can use your own SMS API provider by modifying this section

# SMS settings using Onfon Media SMS API
SMS_ACCESS_KEY="$sms_access_key"
SMS_SENDER_ID="$sms_sender_id"
SMS_API_KEY="$sms_api_key"
SMS_CLIENT_ID="$sms_client_id"

# Create messages array for multiple recipients here
messages_array='[{"Number": "'"$sms_recipient_1"'", "Text": "'"$MESSAGE"'"}, {"Number": "'"$sms_recipient_2"'", "Text": "'"$MESSAGE"'"}]'

# Send SMS to Devs
curl -X POST -H "AccessKey: $SMS_ACCESS_KEY" -H "Content-Type: application/json" \
-d '{
    "SenderId": "'"$SMS_SENDER_ID"'",
    "MessageParameters": '"$messages_array"',
    "ApiKey": "'"$SMS_API_KEY"'",
    "ClientId": "'"$SMS_CLIENT_ID"'"
}' \
"https://api.onfonmedia.co.ke/v1/sms/SendBulkSMS"

# Check the response from SMS API (optional)
if [ $? -eq 0 ]; then
    echo "SMS sent successfully."
else
    echo "Error sending SMS." | tee -a "$log_file"
    exit 1
fi

# 2: Email Option (Using Mailgun API already done above)

send_mail_notification() {
    local message="$1"
    local email_recipient="${2:-$EMAIL_RECIPIENT}"

    # Send email via Mailgun
    curl -s --user "api:$MAILGUN_API_KEY" \
         "$MAILGUN_SMTP" \
         -F from="$SENDER_EMAIL" \
         -F to="$email_recipient" \
         -F subject="$subject" \
         -F text="$message" >> "$log_file" 2>&1

    if [ $? -eq 0 ]; then
        echo "$(date) - Email sent successfully to $email_recipient" | tee -a "$log_file"
    else
        echo "$(date) - Error sending email to $email_recipient" | tee -a "$log_file"
    fi
}

# Step 3.1: Send the email via Mailgun API using curl request
# uncomment if you want to use notification email instead of SMS
# send_mail_notification "Backup completed successfully for $db_name"

# Clean up temporary split files
rm "$temp_dir"/*

# Clean up old backup files (optional)
find "$backup_dir" -type f -name "postgres_backup_*" -mtime +2 -exec rm {} \;

exit 0