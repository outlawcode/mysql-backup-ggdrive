#!/bin/bash

# ==============================================================================
# Project : MySQL to Google Drive Backup (via rclone)
# Description : Script to automatically dump MySQL, compress, and upload to Google Drive.
# Features: Multi-database support and interactive configuration mode.
# ==============================================================================

usage() {
    echo "Usage: $0 --db <db1,db2,db3> --user <db_user> --pass <db_pass> --remote <rclone_remote:path> [--keep-days <days>]"
    echo "Interactive mode: $0 (no arguments)"
    exit 1
}

KEEP_DAYS=7
DB_NAME=""
DB_USER=""
DB_PASS=""
RCLONE_REMOTE=""

run_backup_wizard() {
    echo -e "\n\033[1;36m=== INTERACTIVE BACKUP CONFIGURATION ===\033[0m"
    
    if ! rclone listremotes 2>/dev/null | grep -q ".*:"; then
        echo -e "\n\033[1;33m[WARN] No cloud storage is currently linked to Rclone!\033[0m"
        echo "Please return to the Main Menu and select Option 2 to configure Google Drive first."
        return
    fi
    
    read -p "Enter MySQL Username [root]: " INP_USER
    DB_USER=${INP_USER:-root}
    
    read -s -p "Enter MySQL Password: " DB_PASS
    echo ""
    
    CRON_OUTPUT=$(crontab -l 2>/dev/null | grep "mygdrive-backup")
    
    echo -e "\n\033[1;33m[INFO] Scanning databases and calculating sizes...\033[0m"
    
    QUERY="SELECT s.schema_name, IFNULL(ROUND(SUM(t.data_length + t.index_length) / 1024 / 1024, 2), 0.00) FROM information_schema.schemata s LEFT JOIN information_schema.tables t ON s.schema_name = t.table_schema WHERE s.schema_name NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys') GROUP BY s.schema_name;"
    
    DB_NAMES=()
    DB_SIZES=()
    DB_STATUSES=()
    
    while IFS=$'\t' read -r name size; do
        if [ -n "$name" ]; then
            DB_NAMES+=("$name")
            DB_SIZES+=("$size")
            
            DB_CRON_LINE=$(echo "$CRON_OUTPUT" | grep -E "(^|[ ,\"\'\=])$name([ ,\"\'\=]|$)" | head -n 1)
            
            if [ -n "$DB_CRON_LINE" ]; then
                read -r c_min c_hour c_day c_month c_dow c_rest <<< "$DB_CRON_LINE"
                
                if [ "$c_day" == "*" ] && [ "$c_month" == "*" ] && [ "$c_dow" == "*" ] && [[ "$c_hour" =~ ^[0-9]+$ ]] && [[ "$c_min" =~ ^[0-9]+$ ]]; then
                    READABLE_CRON=$(printf "Daily at %02d:%02d" "$c_hour" "$c_min")
                else
                    READABLE_CRON="Cron ($c_min $c_hour $c_day $c_month $c_dow)"
                fi
                
                DB_STATUSES+=("\033[1;32m[OK] $READABLE_CRON\033[0m")
            else
                DB_STATUSES+=("\033[1;30m[  ] Not scheduled\033[0m")
            fi
        fi
    done < <(mysql -u "$DB_USER" -p"$DB_PASS" -B -N -e "$QUERY" 2>/dev/null)
    
    if [ ${#DB_NAMES[@]} -eq 0 ]; then
        echo -e "\033[1;31m[ERROR] No valid databases found or invalid MySQL credentials!\033[0m"
        exit 1
    fi
    
    echo -e "\n\033[1;32mAvailable Databases:\033[0m"
    echo -e "\033[1;37m  ID  | Database Name                  | Size       | Auto Backup Status\033[0m"
    echo "  -----------------------------------------------------------------------------------"
    for i in "${!DB_NAMES[@]}"; do
        printf "  %-3s | %-30s | %-7s MB | %b\n" "$((i+1)))" "${DB_NAMES[$i]}" "${DB_SIZES[$i]}" "${DB_STATUSES[$i]}"
    done
    echo "  -----------------------------------------------------------------------------------"
    
    echo ""
    echo "Enter DB ID(s) to backup, comma-separated (e.g., 1,3,4)"
    read -p "Or type 'all' to select ALL: " SELECTED_INPUT
    
    SELECTED_DBS=()
    if [[ "$SELECTED_INPUT" == "all" || "$SELECTED_INPUT" == "ALL" ]]; then
        SELECTED_DBS=("${DB_NAMES[@]}")
    else
        IFS=',' read -ra SEL_ARRAY <<< "$SELECTED_INPUT"
        for sel in "${SEL_ARRAY[@]}"; do
            sel=$(echo "$sel" | xargs)
            if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#DB_NAMES[@]}" ]; then
                idx=$((sel-1))
                SELECTED_DBS+=("${DB_NAMES[$idx]}")
            else
                echo -e "\033[1;31m[WARN] Ignoring invalid selection: '$sel'\033[0m"
            fi
        done
    fi
    
    if [ ${#SELECTED_DBS[@]} -eq 0 ]; then
         echo -e "\033[1;31m[ERROR] No databases selected. Aborting.\033[0m"
         exit 1
    fi
    
    DB_NAME=$(IFS=, ; echo "${SELECTED_DBS[*]}")
    
    FIRST_REMOTE=$(rclone listremotes 2>/dev/null | head -n 1 | tr -d ':')
    DEFAULT_REMOTE="${FIRST_REMOTE:-gdrive}:Backups"
    
    echo ""
    read -p "Enter Rclone Remote path (e.g., $FIRST_REMOTE:BackupFolder) [$DEFAULT_REMOTE]: " INP_REMOTE
    RCLONE_REMOTE=${INP_REMOTE:-$DEFAULT_REMOTE}
    
    read -p "Retention: Keep backups for how many days? [7]: " INP_KEEP
    KEEP_DAYS=${INP_KEEP:-7}
    
    echo -e "\n\033[1;36m==========================================\033[0m"
    echo -e "[OK] \033[1;32mCONFIGURATION SUMMARY:\033[0m"
    echo " - Databases to backup : $DB_NAME"
    echo " - Cloud upload path   : $RCLONE_REMOTE"
    echo " - Retention period    : $KEEP_DAYS days"
    echo -e "\033[1;36m==========================================\033[0m\n"
    
    read -p "At what time should the daily backup run? (HH:MM format) [02:00]: " INP_TIME
    INP_TIME=${INP_TIME:-02:00}
    CRON_H=$(echo "$INP_TIME" | cut -d: -f1)
    CRON_M=$(echo "$INP_TIME" | cut -d: -f2)
    
    echo ""
    read -p "Do you want to automatically install this daily cronjob? (y/n) [y]: " AUTO_CRON
    AUTO_CRON=${AUTO_CRON:-y}
    
    if [[ "$AUTO_CRON" =~ ^[Yy]$ ]]; then
        CRON_CMD="$CRON_M $CRON_H * * * /usr/local/bin/mygdrive-backup --db \"$DB_NAME\" --user $DB_USER --pass \"$DB_PASS\" --remote $RCLONE_REMOTE --keep-days $KEEP_DAYS >> /var/log/mygdrive-backup.log 2>&1"
        
        if crontab -l 2>/dev/null | grep -qF "$CRON_CMD"; then
            echo -e "\033[1;33m[WARN] This cronjob is already installed!\033[0m"
        else
            (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
            echo -e "\033[1;32m[OK] Successfully added to crontab. The tool will run daily at $CRON_H:$CRON_M.\033[0m"
        fi
    else
        echo -e "\n\033[1;33m[INFO] You can install it manually later by adding this line to 'crontab -e':\033[0m"
        echo -e "\033[1;37m$CRON_M $CRON_H * * * /usr/local/bin/mygdrive-backup --db \"$DB_NAME\" --user $DB_USER --pass \"$DB_PASS\" --remote $RCLONE_REMOTE --keep-days $KEEP_DAYS >> /var/log/mygdrive-backup.log 2>&1\033[0m"
    fi
    
    echo ""
    read -p "Do you want to run the backup process NOW for testing? (y/n) [y]: " RUN_NOW
    RUN_NOW=${RUN_NOW:-y}
    
    if [[ "$RUN_NOW" =~ ^[Nn]$ ]]; then
        exit 0
    fi
    
    execute_backup
    exit 0
}

interactive_mode() {
    while true; do
        echo -e "\n\033[1;36m=== MAIN MENU ===\033[0m"
        echo " 1) Configure & Run Database Backup"
        echo " 2) Manage Cloud Storage (Rclone Config)"
        echo " 3) Exit"
        echo ""
        read -p "Select an option [1]: " MENU_OPT
        MENU_OPT=${MENU_OPT:-1}
        
        case $MENU_OPT in
            1)
                run_backup_wizard
                ;;
            2)
                rclone config
                ;;
            3)
                echo "Exiting."
                exit 0
                ;;
            *)
                echo "Invalid option."
                ;;
        esac
    done
}

execute_backup() {
    TMP_BKP_DIR="/tmp/mysql_gdrive_backups"
    mkdir -p "$TMP_BKP_DIR"

    IFS=',' read -ra TARGET_DBS <<< "$DB_NAME"

    for CURRENT_DB in "${TARGET_DBS[@]}"; do
        CURRENT_DB=$(echo "$CURRENT_DB" | xargs)
        if [ -z "$CURRENT_DB" ]; then continue; fi

        echo -e "\n=================================================="
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] PROCESSING DATABASE: $CURRENT_DB"
        
        TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
        FILENAME="${CURRENT_DB}_${TIMESTAMP}.sql.gz"
        LOCAL_FILE_PATH="${TMP_BKP_DIR}/${FILENAME}"

        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] Dumping and compressing data..."
        if [ -z "$DB_PASS" ]; then
            mysqldump -u "$DB_USER" "$CURRENT_DB" | gzip > "$LOCAL_FILE_PATH"
        else
            mysqldump -u "$DB_USER" -p"$DB_PASS" "$CURRENT_DB" 2>/dev/null | gzip > "$LOCAL_FILE_PATH"
        fi

        if [ ${PIPESTATUS[0]} -ne 0 ]; then
            echo "[ERROR] Failed to dump database $CURRENT_DB. Skipping to next DB..."
            rm -f "$LOCAL_FILE_PATH"
            continue
        fi
        echo "[OK] Archive created at: $LOCAL_FILE_PATH"

        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] Uploading to Google Drive ($RCLONE_REMOTE)..."
        rclone copy "$LOCAL_FILE_PATH" "$RCLONE_REMOTE"

        if [ $? -ne 0 ]; then
            echo "[ERROR] Upload failed for $CURRENT_DB. Please check your rclone configuration."
        else
            echo "[OK] Upload successful."
        fi

        rm -f "$LOCAL_FILE_PATH"

        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] Applying retention policy: Deleting backups older than $KEEP_DAYS days for $CURRENT_DB..."
        rclone delete "$RCLONE_REMOTE" --min-age ${KEEP_DAYS}d --include "${CURRENT_DB}_*.sql.gz" 2>/dev/null
        
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [OK] Completed database: $CURRENT_DB"
    done

    echo -e "\n=================================================="
    echo "[OK] ALL REQUESTED DATABASES HAVE BEEN BACKED UP SUCCESSFULLY!"
    echo "=================================================="
}

if [ "$#" -eq 0 ]; then
    interactive_mode
else
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --db) DB_NAME="$2"; shift ;;
            --user) DB_USER="$2"; shift ;;
            --pass) DB_PASS="$2"; shift ;;
            --remote) RCLONE_REMOTE="$2"; shift ;;
            --keep-days) KEEP_DAYS="$2"; shift ;;
            *) echo "Error: Invalid parameter $1"; usage ;;
        esac
        shift
    done

    if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$RCLONE_REMOTE" ]; then
        usage
    fi
    execute_backup
fi
