#!/bin/bash

# -------------- Retrieve Environment Variables -------------- #

# Load env. file
if [ -f /.env.bkup ]; then
    export $(grep -v '^#' /.env.bkup | xargs)
else
    echo "Error: .env.bkup file not found!"
    exit 1
fi

# ------------------ Log File Setup ------------------ #

log_file="$main_directory_path/auto-backup/uptime.log"
touch "$log_file"
echo "======================" >> "$log_file"
echo "$(date) - Uptime check started" >> "$log_file"

# ------------------ Load Variables ------------------ #

# Recipient email address
EMAIL_RECIPIENT="$email_recipient"

# Sender email address
SENDER_EMAIL="$sender_email"

# Set the current date and time for notifications
current_date=$(date +"%Y-%m-%d_%H-%M-%S")

# Files to store the SMS and email counters
## We will use counters to limit the number of notifications sent to prevent spamming
sms_counter_file="/tmp/uptime_sms_counter.txt"
email_counter_file="/tmp/uptime_email_counter.txt"

# Email Configuration e.g Using Mailgun API settings
MAILGUN_API_KEY="$mailgun_api_key"
MAILGUN_DOMAIN="$mailgun_domain"
MAILGUN_SMTP="https://api.mailgun.net/v3/$MAILGUN_DOMAIN/messages"
MESSAGE="Backup initialized ..."

# ------------------ Uptime Check ------------------ #

# Step 1. Check the status of the URL to the application
upbeat_status=$(curl -s -o /dev/null -w "%{http_code}" $application_url)

# Step 1.1 If Cloudflare or any other medium bypasses response or hinders challenge by blocking  - Use browser headers
upbeat_status=$(curl -s -o /dev/null -w "%{http_code}" \
  -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36" \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
  -H "Accept-Language: en-US,en;q=0.9" \
  "$application_url")

# Step 1.2 Bypass Cloudflare for health checks entirely
upbeat_status=$(curl -s -o /dev/null -w "%{http_code}" \
  --resolve "{{domain}}:443:{{actual_ORIGIN_IP}}" \
  "https://{{domain}}")

# Step 2. If the status code is 200, do nothing, else send email and SMS notifications
if [[ "$upbeat_status" -ge 200 && "$upbeat_status" -lt 400 ]]; then # We will treat 200–399 as “OK”
   echo "URL is active" | tee -a "$log_file"
else

    # ------------------ Notifications Central ------------------ #

    # Step 3. Read the current SMS counter
    if [ -f "$sms_counter_file" ]; then
        sms_counter=$(cat "$sms_counter_file")
    else
        sms_counter=0
    fi

    # Step 3.1 Read the current Mail counter
    if [ -f "$email_counter_file" ]; then
        email_counter=$(cat "$email_counter_file")
    else
        email_counter=0
    fi

    # Step 3.2 Log the downtime status
    echo "URL is not responding (status code: $upbeat_status)" | tee -a "$log_file"

    # Not.1: Email Option Using Mailgun API or any other email service provider API

    # Not.1.1: Subject of the email
    subject="$application_name RESPONSE DOWNTIME - $current_date"

    # Not.1.2: Set Email Message body
    message="Dear team, $application_name is not responding. Kindly take note of this and check on the containers and server urgently."

    # Not.1.2: Check if the email counter is less than 5 and send email via Mailgun API using curl
    if [ "$email_counter" -lt 8 ]; then

        # Not.1.3: Send the email via Mailgun API using curl
        curl -s --user "api:$MAILGUN_API_KEY" \
        "$MAILGUN_SMTP" \
        -F from="$SENDER_EMAIL" \
        -F to="$EMAIL_RECIPIENT" \
        -F subject="$subject" \
        -F text="$message"

        # Not.1.4: Check the response from Mailgun API
        if [ $? -eq 0 ]; then
            email_counter=$((email_counter + 1))
            echo $email_counter > "$email_counter_file"
            echo "Email sent successfully." | tee -a "$log_file"
        else
            echo "Error sending email." | tee -a "$log_file"
            exit 1
        fi
    fi

    # Not.2: (High Priority) SMS Option using Onfon Media SMS API 

    # Not.2.1: Set the SMS message
    MESSAGE="Hey devs, $application_name is unreachable, it appears either the server or container is down. Please check up on this urgently."
    messages_array='[{"Number": "'"$sms_recipient_1"'", "Text": "'"$MESSAGE"'"}]'

    # Not.2.2: SMS Configuration Variables
    SMS_ACCESS_KEY="$sms_access_key"
    SMS_SENDER_ID="$sms_sender_id"
    SMS_API_KEY="$sms_api_key"
    SMS_CLIENT_ID="$sms_client_id"

    # Not.2.3: Check if sms counter is less than 5
    if [ "$sms_counter" -lt 5 ]; then
        
        # Not.2.4: Send SMS to Devs Team
        curl -X POST -H "AccessKey: $SMS_ACCESS_KEY" -H "Content-Type: application/json" \
        -d '{
            "SenderId": "'"$SMS_SENDER_ID"'",
            "MessageParameters": '"$messages_array"',
            "ApiKey": "'"$SMS_API_KEY"'",
            "ClientId": "'"$SMS_CLIENT_ID"'"
        }' \
        "https://api.onfonmedia.co.ke/v1/sms/SendBulkSMS"

        # Not.2.5: Check the response from SMS API
        if [ $? -eq 0 ]; then
            sms_counter=$((sms_counter + 1))
            echo $sms_counter > "$sms_counter_file"
            echo "SMS sent successfully." | tee -a "$log_file"
        else
            echo "Error sending SMS." | tee -a "$log_file"
            exit 1
        fi
    fi

    # Step 4: Reset the counter if it reaches 5
    if [ "$sms_counter" -ge 5 ]; then
        sms_counter=0
        echo $sms_counter > "$sms_counter_file"
        echo "SMS counter reset to 0." | tee -a "$log_file"
    fi

    # Step 5: Reset the counter if it reaches 8
    if [ "$email_counter" -ge 8 ]; then
        email_counter=0
        echo $email_counter > "$email_counter_file" 
        echo "Email counter reset to 0." | tee -a "$log_file"
    fi
fi

exit 0